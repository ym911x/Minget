import Foundation

/// Deterministic structure observer for the app-owned console webview (Round 8).
///
/// The console's real balance data source cannot be guessed: this instrument observes it.
/// A small script injected into the app's own `WKWebView` (own non-persistent data store)
/// wraps `window.fetch` and `XMLHttpRequest` and reports, for every JSON response the
/// console page itself loads:
///
/// - the response URL's path only (query and fragment stripped),
/// - the HTTP method,
/// - the request header **names** (never values),
/// - a redacted path/type summary of the parsed body (same rules as
///   `GLMAccountReportParser.structureSummary`: depth ≤ 3, entries ≤ 24, no values).
///
/// Response bodies, header values, cookies and credentials never leave the page: the
/// redaction happens inside the injected script itself, and the Swift side re-validates
/// every message against the redacted shape as defence in depth.
public enum GLMConsoleResponseObserver {

    public static let messageHandlerName = "glmStructure"

    /// One observed response, already redacted.
    public struct Observation: Equatable, Sendable {
        public let urlPath: String
        public let method: String
        public let requestHeaderNames: [String]
        public let entries: [String]

        public init(urlPath: String, method: String, requestHeaderNames: [String], entries: [String]) {
            self.urlPath = urlPath
            self.method = method
            self.requestHeaderNames = requestHeaderNames
            self.entries = entries
        }
    }

    public static let maxDepth = 3
    public static let maxEntries = 24
    public static let maxObservationsKept = 8

    /// The injected script. Installs once per page; every post goes through the
    /// `glmStructure` message handler. All redaction happens here, in the page.
    public static let userScriptSource: String = """
    (function () {
      if (window.__usagemonitorObserverInstalled) { return; }
      window.__usagemonitorObserverInstalled = true;
      var MAX_DEPTH = \(maxDepth), MAX_ENTRIES = \(maxEntries);
      function typeOf(v) {
        if (v === null) return 'null';
        var t = typeof v;
        if (t === 'string') return 'string';
        if (t === 'number') return 'number';
        if (t === 'boolean') return 'boolean';
        if (t === 'object') return Array.isArray(v) ? 'array' : 'object';
        return 'value';
      }
      function summarize(value) {
        var entries = [];
        function walk(v, path, depth) {
          if (entries.length >= MAX_ENTRIES) return;
          if (path.length > 180) return;
          if (path) entries.push(path + ': ' + typeOf(v));
          if (depth >= MAX_DEPTH || entries.length >= MAX_ENTRIES) return;
          if (v && typeof v === 'object') {
            if (Array.isArray(v)) { if (v.length) walk(v[0], path + '[]', depth + 1); }
            else {
              Object.keys(v).sort().forEach(function (k) {
                walk(v[k], path ? path + '.' + k : k, depth + 1);
              });
            }
          }
        }
        walk(value, '', 0);
        return entries;
      }
      var OFFICIAL = ['bigmodel.cn', 'open.bigmodel.cn'];
      function matchesOfficial(host) {
        for (var i = 0; i < OFFICIAL.length; i++) {
          if (host === OFFICIAL[i]) return true;
          if (host.slice(-(OFFICIAL[i].length + 1)) === '.' + OFFICIAL[i]) return true;
        }
        return false;
      }
      function isOfficialHost(url) {
        var s = String(url);
        try {
          var base = (typeof location !== 'undefined' && location.origin) ? location.origin : 'https://bigmodel.cn/';
          return matchesOfficial(new URL(s, base).hostname.toLowerCase());
        } catch (e) {
          // No URL API: the host sits between '://' and the next '/', after any userinfo.
          var schemeEnd = s.indexOf('://');
          if (schemeEnd < 0) return false;
          var rest = s.slice(schemeEnd + 3);
          var at = rest.indexOf('@');
          if (at >= 0) rest = rest.slice(at + 1);
          var slash = rest.indexOf('/');
          var host = (slash >= 0 ? rest.slice(0, slash) : rest).toLowerCase();
          var colon = host.indexOf(':');
          if (colon >= 0) host = host.slice(0, colon);
          return matchesOfficial(host);
        }
      }
      function pathOnly(url) {
        var s = String(url);
        var q = s.indexOf('?'); if (q >= 0) s = s.slice(0, q);
        var h = s.indexOf('#'); if (h >= 0) s = s.slice(0, h);
        try {
          var base = (typeof location !== 'undefined' && location.origin) ? location.origin : 'https://bigmodel.cn/';
          var absolute = new URL(s, base);
          // Rebuilt from origin + pathname only: query, fragment and userinfo cannot
          // survive this form.
          return absolute.origin + absolute.pathname;
        } catch (e) {
          var schemeEnd = s.indexOf('://');
          if (schemeEnd >= 0) {
            var slash = s.indexOf('/', schemeEnd + 3);
            var at = s.indexOf('@', schemeEnd + 3);
            if (at >= 0 && (slash < 0 || at < slash)) {
              s = s.slice(0, schemeEnd + 3) + s.slice(at + 1);
            }
          }
          return s;
        }
      }
      function cleanHeaderNames(names) {
        var out = [];
        var pattern = /^[a-z0-9!#$%&'*+\\-.^_`|~]{1,64}$/;
        for (var i = 0; i < names.length && out.length < 16; i++) {
          var n = String(names[i]).toLowerCase();
          if (pattern.test(n) && out.indexOf(n) < 0) out.push(n);
        }
        return out;
      }
      function report(url, method, headerNames, text) {
        try {
          if (!isOfficialHost(url)) return;
          var parsed = JSON.parse(text);
          var entries = summarize(parsed);
          if (!entries.length) return;
          webkit.messageHandlers.glmStructure.postMessage({
            path: pathOnly(url),
            method: String(method || 'GET').toUpperCase(),
            headerNames: cleanHeaderNames(headerNames || []),
            entries: entries
          });
        } catch (e) { /* non-JSON or foreign host: nothing leaves the page */ }
      }
      var originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function () {
          var args = arguments;
          var promise = originalFetch.apply(this, args);
          try {
            var input = args[0];
            var url = (typeof input === 'string') ? input : (input && input.url) || '';
            var method = (args[1] && args[1].method) || (input && input.method) || 'GET';
            var names = [];
            try {
              var headers = (args[1] && args[1].headers) || (input && input.headers) || null;
              if (headers) {
                if (headers.forEach) { headers.forEach(function (v, k) { names.push(String(k)); }); }
                else { names = Object.keys(headers).map(String); }
              }
            } catch (e) {}
            promise.then(function (res) {
              try {
                res.clone().text().then(function (t) { report(url, method, names, t); }).catch(function () {});
              } catch (e) {}
            }).catch(function () {});
          } catch (e) {}
          return promise;
        };
      }
      if (window.XMLHttpRequest) {
      var originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        var names = [];
        var originalSet = this.setRequestHeader;
        this.setRequestHeader = function (name) {
          try { names.push(String(name)); } catch (e) {}
          return originalSet.apply(this, arguments);
        };
        this.addEventListener('load', function () {
          try { report(url, method, names, this.responseText); } catch (e) {}
        });
        return originalOpen.apply(this, arguments);
      };
      }
    })();
    """

    // MARK: - Swift-side validation

    private static let knownTypes: Set<String> = ["object", "array", "number", "string", "boolean", "null", "value"]

    /// Validates and caps one message posted by the injected script. Anything that does
    /// not match the redacted shape is dropped: values must never surface, even if the
    /// page script were tampered with.
    public static func observation(from message: Any?) -> Observation? {
        guard let payload = message as? [String: Any] else { return nil }
        guard let rawPath = payload["path"] as? String else { return nil }
        let urlPath = sanitizePath(rawPath)
        guard !urlPath.isEmpty else { return nil }
        let method = ((payload["method"] as? String) ?? "GET").uppercased()
        guard method.allSatisfy({ $0.isLetter }) else { return nil }

        let headerNames = ((payload["headerNames"] as? [Any])?.compactMap { $0 as? String } ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.contains(":") && !$0.contains(" ") }
            .uniqued()
            .prefix(16)

        let rawEntries = (payload["entries"] as? [Any])?.compactMap { $0 as? String } ?? []
        var entries: [String] = []
        for raw in rawEntries {
            guard entries.count < maxEntries else { break }
            guard raw.count <= 220, let separator = raw.lastIndex(of: ":") else { continue }
            let path = String(raw[raw.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let type = String(raw[raw.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, knownTypes.contains(type) else { continue }
            entries.append("\(path): \(type)")
        }
        guard !entries.isEmpty else { return nil }
        return Observation(urlPath: urlPath, method: method,
                           requestHeaderNames: Array(headerNames), entries: entries)
    }

    /// Query, fragment, user and password are stripped via `URLComponents`; only https
    /// URLs on the official console hosts survive (the page may also fetch relative
    /// paths, which survive as slash-rooted paths only).
    static func sanitizePath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), trimmed.count <= 512 else { return "" }
        if var components = URLComponents(string: trimmed), components.scheme != nil {
            guard components.scheme?.lowercased() == "https",
                  let host = components.host?.lowercased(),
                  GLMConsoleSessionPolicy.isHostAllowed(host) else { return "" }
            components.query = nil
            components.fragment = nil
            components.user = nil
            components.password = nil
            guard let normalized = components.url else { return "" }
            return normalized.absoluteString
        }
        guard trimmed.hasPrefix("/") else { return "" }
        let withoutQuery = trimmed.split(separator: "?", omittingEmptySubsequences: false)[0]
        return String(withoutQuery.split(separator: "#", omittingEmptySubsequences: false)[0])
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

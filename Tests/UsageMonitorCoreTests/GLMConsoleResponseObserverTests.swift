import XCTest
import JavaScriptCore
@testable import UsageMonitorCore

/// The console response observer (Round 8): the injected script redacts inside the page,
/// and the Swift side re-validates every message. Together they guarantee that console
/// diagnostics carry only paths, types and header names — never values, bodies or cookies.
final class GLMConsoleResponseObserverTests: XCTestCase {

    // MARK: Swift-side validation

    func testObservationValidationAcceptsARedactedMessage() throws {
        let observation = GLMConsoleResponseObserver.observation(from: [
            "path": "https://bigmodel.cn/api/biz/account/balance?token=secret",
            "method": "post",
            "headerNames": ["X-CSRF-Token", "x-csrf-token", "bad header", "bad:header", ""],
            "entries": ["code: number", "data: object", "data.balance: object",
                        "data.balance.availableBalance: number", "garbage-without-colon",
                        "x: not-a-known-type"],
        ])

        let redacted = try XCTUnwrap(observation)
        XCTAssertEqual(redacted.urlPath, "https://bigmodel.cn/api/biz/account/balance",
                       "query strings are never reported")
        XCTAssertEqual(redacted.method, "POST")
        XCTAssertEqual(redacted.requestHeaderNames, ["x-csrf-token"],
                       "header names are lowercased, deduped, and malformed names dropped")
        XCTAssertEqual(redacted.entries, ["code: number", "data: object",
                                          "data.balance: object",
                                          "data.balance.availableBalance: number"],
                       "entries that are not a path/type pair are dropped")
    }

    func testObservationValidationRejectsMalformedMessages() {
        XCTAssertNil(GLMConsoleResponseObserver.observation(from: nil))
        XCTAssertNil(GLMConsoleResponseObserver.observation(from: ["entries": ["code: number"]]))
        XCTAssertNil(GLMConsoleResponseObserver.observation(from: ["path": "not a url", "entries": ["a: number"]]))
        XCTAssertNil(GLMConsoleResponseObserver.observation(from: ["path": "ftp://bigmodel.cn/x", "entries": ["a: number"]]))
        XCTAssertNil(GLMConsoleResponseObserver.observation(from: ["path": "http://bigmodel.cn/x", "entries": ["a: number"]]))
        XCTAssertNil(GLMConsoleResponseObserver.observation(from: ["path": "https://evil.example.com/x", "entries": ["a: number"]]))
        XCTAssertNil(GLMConsoleResponseObserver.observation(from: ["path": "https://bigmodel.cn/x", "entries": []]))
        XCTAssertNil(GLMConsoleResponseObserver.observation(from: ["path": "https://bigmodel.cn/x",
                                                                   "method": "GET with spaces",
                                                                   "entries": ["a: number"]]))
        // Oversized entries are dropped; the cap is enforced.
        var entries = [String]()
        for i in 0..<40 { entries.append(String(repeating: "k", count: 300) + "\(i): number") }
        let capped = GLMConsoleResponseObserver.observation(from: ["path": "https://bigmodel.cn/x", "entries": entries])
        XCTAssertNil(capped, "entries that exceed the length cap are dropped")
    }

    func testObservationCapEnforced() {
        var entries = [String]()
        for i in 0..<GLMConsoleResponseObserver.maxEntries + 10 {
            entries.append("field\(i): number")
        }
        let observation = GLMConsoleResponseObserver.observation(from: ["path": "https://bigmodel.cn/x",
                                                                        "entries": entries])
        XCTAssertEqual(observation?.entries.count, GLMConsoleResponseObserver.maxEntries)
    }

    /// Swift-side: userinfo, fragment and query must all be stripped from an absolute
    /// URL, and only https URLs on the official console hosts survive.
    func testSanitizePathStripsUserInfoFragmentAndForeignHosts() {
        let sanitized = GLMConsoleResponseObserver.sanitizePath(
            "https://user:pass@bigmodel.cn/api/biz/account/balance?token=sentinel#frag-sentinel")
        XCTAssertEqual(sanitized, "https://bigmodel.cn/api/biz/account/balance")
        XCTAssertFalse(sanitized.contains("pass"))
        XCTAssertFalse(sanitized.contains("sentinel"))

        // A plain absolute URL keeps its fragment stripped even without a query.
        let withFragment = GLMConsoleResponseObserver.sanitizePath(
            "https://bigmodel.cn/api/x#fragment-only-sentinel")
        XCTAssertEqual(withFragment, "https://bigmodel.cn/api/x")
        XCTAssertFalse(withFragment.contains("fragment-only-sentinel"))
    }

    // MARK: The injected script itself, executed in a real JavaScript engine

    /// A plain, non-actor payload box shared with the JS capture block.
    final class PayloadBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [[String: Any]] = []
        func append(_ item: [String: Any]) {
            lock.lock(); items.append(item); lock.unlock()
        }
        var first: [String: Any]? {
            lock.lock(); defer { lock.unlock() }
            return items.first
        }
        var isEmpty: Bool {
            lock.lock(); defer { lock.unlock() }
            return items.isEmpty
        }
        func removeAll() {
            lock.lock(); items.removeAll(); lock.unlock()
        }
    }

    /// Builds a JSContext with the message-handler contract, a fake `fetch`, and the
    /// shipped observer script installed.
    static func makeObserverContext(withURLShim: Bool = true, payloads: PayloadBox) throws -> JSContext {
        let context = JSContext()!
        let capture: @convention(block) (JSValue) -> Void = { value in
            if let dict = value.toDictionary() as? [String: Any] {
                payloads.append(dict)
            }
        }
        context.setObject(capture, forKeyedSubscript: "__capture" as NSString)
        // A minimal URL shim reproduces the WKWebView branch where the URL API exists.
        let urlShim = withURLShim
            ? "var URL = function (s) { this._s = String(s); }; "
            + "Object.defineProperty(URL.prototype, 'origin', { get: function () { return this._s.split('/').slice(0, 3).join('/'); } }); "
            + "Object.defineProperty(URL.prototype, 'pathname', { get: function () { return '/' + this._s.split('/').slice(3).join('/').split('?')[0].split('#')[0]; } }); "
            + "Object.defineProperty(URL.prototype, 'hostname', { get: function () { return this._s.split('/')[2].split('@').pop().split(':')[0]; } });"
            : ""
        context.evaluateScript("""
        var window = this;
        var webkit = { messageHandlers: { glmStructure: { postMessage: function (m) { __capture(m); } } } };
        var __nextResponse = null;
        window.fetch = function () {
          return Promise.resolve({ clone: function () { return this; },
                                   text: function () { return Promise.resolve(__nextResponse); } });
        };
        \(urlShim)
        """)
        context.evaluateScript(GLMConsoleResponseObserver.userScriptSource)
        return context
    }

    static func waitForPayload(_ payloads: PayloadBox, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while payloads.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Runs the actual injected script against a fake `fetch` response. This pins the
    /// redaction guarantees of the script that really ships, not a reimplementation.
    func testInjectedScriptRedactsInsideThePage() throws {
        let payloads = PayloadBox()
        let context = try Self.makeObserverContext(payloads: payloads)

        let body = #"{"code":200,"success":true,"msg":"upstream secret text","data":{"balance":{"balance":88.5,"availableBalance":12.3,"token":"must-not-leak"}}}"#
        context.evaluateScript("__nextResponse = '" + body + "';")
        context.evaluateScript("fetch('https://bigmodel.cn/api/biz/account/balance?query=leak', { method: 'POST', headers: { 'X-CSRF-Token': 'secret-value' } });")
        Self.waitForPayload(payloads)

        let payload = try XCTUnwrap(payloads.first, "the script must post one observation")
        let observation = try XCTUnwrap(GLMConsoleResponseObserver.observation(from: payload))

        XCTAssertEqual(observation.urlPath, "https://bigmodel.cn/api/biz/account/balance",
                       "the query string never leaves the page")
        XCTAssertEqual(observation.method, "POST")
        XCTAssertEqual(observation.requestHeaderNames, ["x-csrf-token"],
                       "header names are reported, never values")

        // Paths and types only: no value of any field may appear.
        XCTAssertEqual(observation.entries, [
            "code: number",
            "data: object",
            "data.balance: object",
            "data.balance.availableBalance: number",
            "data.balance.balance: number",
            "data.balance.token: string",
            "msg: string",
            "success: boolean",
        ])
        for entry in observation.entries {
            XCTAssertFalse(entry.contains("88.5"))
            XCTAssertFalse(entry.contains("12.3"))
            XCTAssertFalse(entry.contains("secret"))
            XCTAssertFalse(entry.contains("must-not-leak"))
        }
    }

    /// The shipped script with the URL branch: userinfo, fragment and query are stripped
    /// before anything is posted, and a foreign host posts nothing at all.
    func testInjectedScriptStripsUserInfoAndFragmentsBeforePosting() throws {
        let payloads = PayloadBox()
        let context = try Self.makeObserverContext(payloads: payloads)
        context.evaluateScript("__nextResponse = '{\"code\":200}';")
        context.evaluateScript("fetch('https://user:pass@bigmodel.cn/api/biz/account/balance?token=leak#frag-sentinel', { method: 'GET', headers: { 'X-Custom-Header': 'value-must-not-appear' } });")
        Self.waitForPayload(payloads)

        let payload = try XCTUnwrap(payloads.first)
        let observation = try XCTUnwrap(GLMConsoleResponseObserver.observation(from: payload))
        XCTAssertEqual(observation.urlPath, "https://bigmodel.cn/api/biz/account/balance")
        for text in [observation.urlPath, observation.requestHeaderNames.joined(), observation.entries.joined()] {
            XCTAssertFalse(text.contains("pass"))
            XCTAssertFalse(text.contains("leak"))
            XCTAssertFalse(text.contains("frag-sentinel"))
            XCTAssertFalse(text.contains("value-must-not-appear"))
        }

        payloads.removeAll()
        // A foreign host posts nothing at all.
        context.evaluateScript("fetch('https://evil.example.com/api/balance');")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(payloads.isEmpty, "foreign-host responses never leave the page")
    }

    /// The no-URL fallback branch (constrained JS engines) must strip userinfo and the
    /// fragment too.
    func testPathOnlyFallbackStripsUserInfoAndFragments() throws {
        let payloads = PayloadBox()
        let context = try Self.makeObserverContext(withURLShim: false, payloads: payloads)
        context.evaluateScript("__nextResponse = '{\"code\":200}';")
        context.evaluateScript("fetch('https://user:pass@open.bigmodel.cn/api/x#frag-sentinel');")
        Self.waitForPayload(payloads)

        let payload = try XCTUnwrap(payloads.first)
        let observation = try XCTUnwrap(GLMConsoleResponseObserver.observation(from: payload))
        XCTAssertEqual(observation.urlPath, "https://open.bigmodel.cn/api/x")
        XCTAssertFalse(observation.urlPath.contains("pass"))
        XCTAssertFalse(observation.urlPath.contains("frag-sentinel"))
    }

    func testInjectedScriptHandlesNonJSONQuietly() throws {
        let payloads = PayloadBox()
        let context = try Self.makeObserverContext(payloads: payloads)
        context.evaluateScript("__nextResponse = '<html>not json at all</html>';")
        context.evaluateScript("fetch('https://bigmodel.cn/x');")

        // Give any (incorrect) post a moment, then assert none happened.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(payloads.isEmpty, "a non-JSON response must post nothing")
    }
}

import Foundation

/// Rules for the in-app official console connection.
///
/// The connection is a WKWebView the user drives themselves (login, captcha). Everything
/// that can be decided without AppKit lives here so it is testable, and the view layer only
/// applies the answers.
///
/// Guarantees implemented by this policy:
/// - the webview starts from a data store this app created, so no existing browser cookie
///   is ever present, read or reused,
/// - navigation is limited to `bigmodel.cn` / `open.bigmodel.cn` over https, so the
///   captured session can only ever be offered to the official console,
/// - disconnect clears both the keychain entry and the app-owned web data store.
public enum GLMConsoleSessionPolicy {

    /// Hosts the captured session may be used with. Subdomains of these are allowed.
    public static let allowedHosts: [String] = ["bigmodel.cn", "open.bigmodel.cn"]

    public static let consoleBaseURL = URL(string: "https://bigmodel.cn/")!

    /// True when `host` is an allowed host or a subdomain of one.
    public static func isHostAllowed(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let lowered = host.lowercased()
        for allowed in allowedHosts {
            if lowered == allowed { return true }
            if lowered.hasSuffix("." + allowed) { return true }
        }
        return false
    }

    /// Navigation decision for the console webview. Only https on an allowed host passes.
    public static func isNavigationAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return isHostAllowed(url.host)
    }

    /// Cookies whose domain belongs to the official console. Anything else in the store is
    /// ignored, so a cross-domain asset can never contribute to the stored session.
    public static func isCookieAllowed(domain: String?) -> Bool {
        guard let domain else { return false }
        return isHostAllowed(domain.hasPrefix(".") ? String(domain.dropFirst()) : domain)
    }

    /// Serialised session kept in the keychain. Values only, no attributes: the cookie
    /// store's own attributes are not needed to replay the session, and keeping the payload
    /// minimal makes accidental logging easier to avoid.
    public struct StoredSession: Equatable, Codable {
        public var cookies: [StoredCookie]
        public var capturedAt: Date
        public var organizationID: String?
        public var projectID: String?
        public init(cookies: [StoredCookie], capturedAt: Date,
                    organizationID: String? = nil, projectID: String? = nil) {
            self.organizationID = organizationID
            self.projectID = projectID
            self.cookies = cookies
            self.capturedAt = capturedAt
        }
    }

    public struct StoredCookie: Equatable, Codable {
        public var name: String
        public var value: String
        public var domain: String
        public var expiresAt: Date?

        public init(name: String, value: String, domain: String, expiresAt: Date?) {
            self.name = name
            self.value = value
            self.domain = domain
            self.expiresAt = expiresAt
        }
    }

    /// Matches the official console's 5f87 / 22a6 modules. Never log these headers.
    public static func requestHeaders(for session: StoredSession) -> [String: String] {
        let cookies = session.cookies.filter { isCookieAllowed(domain: $0.domain) }
        var headers = ["Cookie": cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")]
        if let token = cookies.first(where: { $0.name == "bigmodel_token_production" })?.value,
           !token.isEmpty, token.rangeOfCharacter(from: .controlCharacters) == nil {
            let decoded = token.removingPercentEncoding ?? token
            if decoded.rangeOfCharacter(from: .controlCharacters) == nil { headers["Authorization"] = decoded }
        }
        for (name, value) in [("Bigmodel-Organization", session.organizationID),
                              ("Bigmodel-Project", session.projectID)] {
            if let value, value.count <= 256, value.rangeOfCharacter(from: .controlCharacters) == nil {
                headers[name] = value
            }
        }
        return headers
    }

    public enum SessionState: Equatable, Sendable {
        case absent
        case present(expiresAt: Date?)
        case expired
    }

    /// Keychain round trip.
    public static func encode(_ session: StoredSession) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(session)
    }

    public static func decode(_ data: Data) -> StoredSession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoredSession.self, from: data)
    }

    /// State of a stored session at `now`.
    public static func evaluate(_ session: StoredSession?, now: Date = Date()) -> SessionState {
        guard let session, !session.cookies.isEmpty else { return .absent }
        // Only cookies with a hard expiry can expire; session cookies are treated as
        // present until the console says otherwise.
        let expiries = session.cookies.compactMap { $0.expiresAt }
        guard let earliest = expiries.min() else { return .present(expiresAt: nil) }
        if earliest <= now { return .expired }
        return .present(expiresAt: earliest)
    }
}

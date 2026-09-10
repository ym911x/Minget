import Foundation

/// DeepSeek reader wired to the keychain-backed key.
public final class DeepSeekReading: ProviderReading, @unchecked Sendable {

    public let platform: ProviderPlatform = .deepseek
    public var isAutomaticRefreshEnabled: Bool { true }

    private let provider: DeepSeekProvider
    private let credentials: ProviderCredentialStoring

    public init(provider: DeepSeekProvider, credentials: ProviderCredentialStoring) {
        self.provider = provider
        self.credentials = credentials
    }

    public var isConfigured: Bool {
        guard let key = credentials.load(.deepseekAPIKey) else { return false }
        return !key.isEmpty
    }

    public func read() async throws -> ProviderReadResult {
        guard let key = credentials.load(.deepseekAPIKey), !key.isEmpty else {
            throw ProviderFailure.notConfigured
        }
        let balances = try await provider.fetchBalances()
        return ProviderReadResult(accountID: DeepSeekProvider.accountFingerprint(forAPIKey: key),
                                  balances: balances,
                                  consoleURL: nil)
    }

    /// Saves or replaces the API key (keychain only). The settings flow calls this the
    /// moment the user saves a key; the reading owns its own credential, so there is no
    /// second, separately-wired store that could be left unconnected (Round 6).
    public func storeAPIKey(_ key: String) throws {
        try credentials.save(key, for: .deepseekAPIKey)
    }

    public func disconnect() throws {
        credentials.delete(.deepseekAPIKey)
    }
}

/// GLM reader.
///
/// Two connection kinds exist, each with its own endpoint and strict schema:
/// - a plain API key reads the read-only balance endpoint (`/api/paas/v4/balance`,
///   schema `apiBalanceV1`), falling back to the console report endpoint once if the
///   answer parses under no known shape;
/// - an official console session captured from the in-app login window reads the console
///   report endpoint (`/api/biz/account/query-customer-account-report`, schema
///   `consoleReportV1`).
///
/// A response is displayed only when it parses cleanly under its endpoint's confirmed
/// schema. A business-successful body that matches no known shape reports
/// `structureUnsupported` together with a redacted structure observation, so a new real
/// shape can be identified without exposing a single value.
public final class GLMReading: ProviderReading, ProviderProbeReading, @unchecked Sendable {

    public let platform: ProviderPlatform = .glm

    private let provider: GLMProvider
    private let credentials: ProviderCredentialStoring
    private let clock: () -> Date
    private let sessionLock = NSLock()
    private var cachedSession: GLMConsoleSessionPolicy.StoredSession?
    /// The credential the app is currently connected with: the one saved or captured most
    /// recently. **Persisted** (a non-secret mode choice in UserDefaults), so a restart
    /// keeps using the selected console connection instead of silently falling back to an
    /// old stored API key (REVIEW round 7 finding 1).
    private var preferredCredential: PreferredCredential?

    /// UserDefaults key for the non-secret connection-mode choice. App-owned defaults
    /// only; never a credential value.
    static let connectionModeKey = "UsageMonitor.glm.connectionMode"

    private enum PreferredCredential: String {
        case apiKey
        case consoleSession
    }

    /// Last probe observation. Field names and codes only; never key material. Surfaced to
    /// the diagnostics screen so the contract can be confirmed from real evidence.
    public private(set) var lastObservation: GLMAccountReportObservation?
    public var onObservation: ((GLMAccountReportObservation) -> Void)?

    /// - Parameter preferences: app-owned UserDefaults for the non-secret connection-mode
    ///   choice; injectable so tests run on an isolated domain.
    public init(provider: GLMProvider,
                credentials: ProviderCredentialStoring,
                clock: @escaping () -> Date = Date.init,
                preferences: UserDefaults = .standard) {
        self.provider = provider
        self.credentials = credentials
        self.clock = clock
        self.preferences = preferences
        if let raw = preferences.string(forKey: Self.connectionModeKey),
           let mode = PreferredCredential(rawValue: raw) {
            self.preferredCredential = mode
        }
        if let data = credentials.load(.glmConsoleSession).flatMap({ Data($0.utf8) }),
           let session = GLMConsoleSessionPolicy.decode(data) {
            self.cachedSession = session
        }
    }

    private let preferences: UserDefaults

    public var isConfigured: Bool {
        return hasAPIKey || hasSession
    }

    /// The periodic cycle runs only when the stored credential's endpoint schema is
    /// confirmed. Until then the endpoint is probed on connect and on explicit request,
    /// not on a timer.
    public var isAutomaticRefreshEnabled: Bool {
        guard isConfigured else { return false }
        if hasAPIKey { return GLMContract.isConfirmed(.apiBalanceV1) }
        return GLMContract.isConfirmed(.consoleReportV1)
    }

    public var hasAPIKey: Bool {
        guard let key = credentials.load(.glmAPIKey) else { return false }
        return !key.isEmpty
    }

    public var hasSession: Bool {
        return session() != nil
    }

    /// State of the stored console session.
    public var sessionState: GLMConsoleSessionPolicy.SessionState {
        return GLMConsoleSessionPolicy.evaluate(session(), now: clock())
    }

    /// Saves the API key (keychain only) and marks it the credential the next connection
    /// probe exercises. Called by the settings flow the moment the user saves a key.
    public func storeAPIKey(_ key: String) throws {
        try credentials.save(key, for: .glmAPIKey)
        sessionLock.lock()
        preferredCredential = .apiKey
        sessionLock.unlock()
        preferences.set(PreferredCredential.apiKey.rawValue, forKey: Self.connectionModeKey)
    }

    /// Replaces the console session captured by the in-app login window. The payload came
    /// from this app's own web data store, never from an existing browser profile. The
    /// session becomes the credential the next connection probe exercises.
    public func storeSession(_ session: GLMConsoleSessionPolicy.StoredSession) throws {
        let data = try GLMConsoleSessionPolicy.encode(session)
        try credentials.save(String(decoding: data, as: UTF8.self), for: .glmConsoleSession)
        sessionLock.lock()
        cachedSession = session
        preferredCredential = .consoleSession
        sessionLock.unlock()
        preferences.set(PreferredCredential.consoleSession.rawValue, forKey: Self.connectionModeKey)
    }

    public func read() async throws -> ProviderReadResult {
        guard isConfigured else { throw ProviderFailure.notConfigured }

        // The selected connection mode decides which endpoint is exercised; it survives
        // restarts, so a console connection is not silently switched back to an old key.
        let useSession = useConsoleSession()
        if !useSession, let key = credentials.load(.glmAPIKey), !key.isEmpty {
            return try await readWithAPIKey(key)
        }
        guard let session = session() else { throw ProviderFailure.notConfigured }
        return try await readWithSession(session)
    }

    /// True when the stored credential set and the persisted mode select the console
    /// session. Falls back to "only the session exists" when no mode was ever recorded.
    private func useConsoleSession() -> Bool {
        let preference = sessionLock.withLock { preferredCredential }
        switch preference {
        case .consoleSession where hasSession: return true
        case .apiKey where hasAPIKey: return false
        default: return !hasAPIKey && hasSession
        }
    }

    /// API key path: the read-only balance endpoint first; one fallback to the console
    /// report endpoint with the same key when the answer matched no known shape. A
    /// rejected key (401/403) and transport failures are never retried on the other
    /// endpoint: the answer would not be different.
    private func readWithAPIKey(_ key: String) async throws -> ProviderReadResult {
        let headers = ["Authorization": GLMHeaderScheme.bearer.headerValue(for: key)]
        let primaryResponse = try await provider.client.get(path: GLMProvider.balancePath,
                                                            headers: headers,
                                                            timeout: 15)
        let primary = GLMAccountReportParser.observe(response: primaryResponse, schema: .apiBalanceV1)
        record(primary)
        if primary.isDisplayable {
            return ProviderReadResult(accountID: "apikey-" + GLMProvider.apiKeyFingerprint(forAPIKey: key),
                                      balances: primary.candidateBalances,
                                      consoleURL: GLMProvider.consoleURL)
        }

        let primaryFailure = primary.parseFailure ?? .unexpectedResponse
        switch primaryFailure {
        case .invalidCredential, .notConfigured, .networkUnreachable, .timedOut,
             .serverError, .crossDomainRedirectBlocked, .cancelled, .other, .suspended:
            throw primaryFailure
        case .unexpectedResponse, .businessError, .structureUnsupported, .contractUnconfirmed:
            break   // worth one fallback attempt with the same key
        }

        let fallbackResponse = try await provider.client.get(path: GLMProvider.accountReportPath,
                                                             headers: headers,
                                                             timeout: 15)
        let fallback = GLMAccountReportParser.observe(response: fallbackResponse, schema: .consoleReportV1)
        record(fallback)
        if fallback.isDisplayable {
            return ProviderReadResult(accountID: "apikey-" + GLMProvider.apiKeyFingerprint(forAPIKey: key),
                                      balances: fallback.candidateBalances,
                                      consoleURL: GLMProvider.consoleURL)
        }
        throw Self.combinedFailure(primaryFailure, fallback.parseFailure)
    }

    /// Console-session path: the report endpoint with the captured cookies. A hard-expired
    /// session is never replayed.
    private func readWithSession(_ session: GLMConsoleSessionPolicy.StoredSession) async throws -> ProviderReadResult {
        guard case .present = sessionState else {
            record(GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                               businessCode: nil, candidateBalances: [],
                                               parseFailure: .invalidCredential))
            throw ProviderFailure.invalidCredential
        }
        let response = try await provider.consoleClient.get(path: GLMProvider.accountReportPath,
                                                     headers: GLMConsoleSessionPolicy.requestHeaders(for: session),
                                                     timeout: 15)
        let observation = GLMAccountReportParser.observe(response: response, schema: .consoleReportV1)
        record(observation)
        guard observation.isDisplayable else {
            throw Self.structureOr(observation.parseFailure)
        }
        // The cache identity is derived from the credential ACTUALLY used: session reads
        // must never land in an API-key's cache entry (REVIEW round 7 finding 1).
        return ProviderReadResult(accountID: Self.sessionAccountID(session),
                                  balances: observation.candidateBalances,
                                  consoleURL: GLMProvider.consoleURL)
    }

    /// Non-secret, session-specific cache identity: the capture time (millisecond
    /// precision) distinguishes relogins, so a new session never reads the old session's
    /// numbers.
    static func sessionAccountID(_ session: GLMConsoleSessionPolicy.StoredSession) -> String {
        let millis = Int64((session.capturedAt.timeIntervalSince1970 * 1000).rounded())
        return "console-\(millis)"
    }

    /// The failure a caller should see when a business-successful payload matched no
    /// known shape on every attempted endpoint: a structure problem, not a network one.
    static func combinedFailure(_ primary: ProviderFailure, _ fallback: ProviderFailure?) -> ProviderFailure {
        if primary == .unexpectedResponse && (fallback == nil || fallback == .unexpectedResponse) {
            return .structureUnsupported
        }
        return fallback ?? primary
    }

    /// Session reads have a single endpoint: an unexpected shape there is directly a
    /// structure problem.
    static func structureOr(_ failure: ProviderFailure?) -> ProviderFailure {
        return failure == .unexpectedResponse ? .structureUnsupported : (failure ?? .unexpectedResponse)
    }

    /// One-shot read-only probe, used by the 探测一次 button and by tests. Exercises the
    /// most recently saved credential against its own endpoint (API key → balance
    /// endpoint, console session → report endpoint). Records what the endpoint answered
    /// (HTTP status, business code, top-level key names, redacted structure) without
    /// displaying or caching any amount.
    ///
    /// Never throws for an HTTP outcome: a rejected credential, a hard-expired session and
    /// an HTTP 200 business error are all classified into the published observation. A
    /// hard-expired session is never replayed.
    @discardableResult
    public func probe() async -> GLMAccountReportObservation? {
        guard isConfigured else { return nil }

        let useSession = useConsoleSession()
        let observation: GLMAccountReportObservation
        if !useSession {
            observation = await provider.probeBalanceObservation()
        } else if let session = session() {
            switch sessionState {
            case .present:
                observation = await probeConsoleSession(session)
            case .absent, .expired:
                // A hard-expired session is never replayed; the observation says so.
                observation = GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                                          businessCode: nil, candidateBalances: [],
                                                          parseFailure: .invalidCredential)
            }
        } else {
            return nil
        }
        record(observation)
        return observation
    }

    /// Connection probe for the engine's save-then-connect flow: probes with the most
    /// recently saved credential, publishes the redacted observation, and returns the
    /// failure category the engine should record. A payload that parses cleanly still
    /// reports `contractUnconfirmed` while its schema is unconfirmed.
    public func probeForConnection() async -> ProviderFailure? {
        guard let observation = await probe() else { return .notConfigured }
        if let failure = observation.parseFailure { return failure }
        guard let schema = observation.schema, GLMContract.isConfirmed(schema) else {
            return .contractUnconfirmed
        }
        return nil
    }

    /// Console-session probe against the read-only report endpoint. The answer becomes an
    /// observation exactly like the API-key path, and the real HTTP status is preserved so
    /// the diagnostics screen can show what actually happened. Nothing here can display a
    /// balance: `GLMAccountReportObservation.isDisplayable` keeps the schema gate.
    private func probeConsoleSession(_ session: GLMConsoleSessionPolicy.StoredSession) async -> GLMAccountReportObservation {
        do {
            let response = try await provider.consoleClient.get(path: GLMProvider.accountReportPath,
                                                         headers: GLMConsoleSessionPolicy.requestHeaders(for: session),
                                                         timeout: 15)
            return GLMAccountReportParser.observe(response: response, schema: .consoleReportV1)
        } catch let transport as ProviderTransportError {
            return GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                               businessCode: nil, candidateBalances: [],
                                               parseFailure: ProviderFailure.from(transport))
        } catch {
            return GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                               businessCode: nil, candidateBalances: [],
                                               parseFailure: .other)
        }
    }

    /// Removes the API key, the console session and the cached numbers.
    public func disconnect() throws {
        credentials.delete(.glmAPIKey)
        credentials.delete(.glmConsoleSession)
        sessionLock.lock()
        cachedSession = nil
        preferredCredential = nil
        sessionLock.unlock()
        preferences.removeObject(forKey: Self.connectionModeKey)
    }

    // MARK: - Internals

    private func record(_ observation: GLMAccountReportObservation) {
        sessionLock.lock()
        lastObservation = observation
        sessionLock.unlock()
        onObservation?(observation)
    }

    private func session() -> GLMConsoleSessionPolicy.StoredSession? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        if let cachedSession { return cachedSession }
        guard let raw = credentials.load(.glmConsoleSession),
              let session = GLMConsoleSessionPolicy.decode(Data(raw.utf8)) else { return nil }
        cachedSession = session
        return session
    }

    static func cookieHeader(from session: GLMConsoleSessionPolicy.StoredSession) -> String {
        return session.cookies
            .filter { GLMConsoleSessionPolicy.isCookieAllowed(domain: $0.domain) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }
}

import Foundation

/// DeepSeek reader wired to the keychain-backed key.
///
/// Every credential access goes through `CredentialAccessCoordinator`. The reader itself only
/// ever reads *memory* state: `credentialState` answers status questions without touching the
/// keychain, and `read()` performs at most one access, whose value serves both the network
/// request and the account fingerprint (KEYCHAIN_REVISION_PLAN.md P1.3 and P1.7).
public final class DeepSeekReading: ProviderReading, @unchecked Sendable {

    public let platform: ProviderPlatform = .deepseek
    public var isAutomaticRefreshEnabled: Bool { true }

    private let provider: DeepSeekProvider
    private let access: CredentialAccessCoordinator

    public init(provider: DeepSeekProvider,
                credentials: ProviderCredentialStoring,
                accessQueue: DispatchQueue? = nil) {
        self.provider = provider
        self.access = accessQueue.map { CredentialAccessCoordinator(store: credentials, queue: $0) }
            ?? CredentialAccessCoordinator(store: credentials)
    }

    /// Memory only. Never touches the keychain, so it is safe from `init`, `report` and any
    /// redraw.
    public var credentialState: ProviderCredentialState {
        ProviderCredentialState(phase: access.phase(for: .deepseekAPIKey))
    }

    public var isConfigured: Bool { credentialState.isConfigured }

    /// Forwards credential-phase changes so the owner can publish a fresh report.
    public var onCredentialPhaseChange: (() -> Void)? {
        get { access.onPhaseChange }
        set { access.onPhaseChange = newValue }
    }

    /// One background read, which is what a launch needs to know whether this platform is
    /// worth connecting.
    public func primeCredentialState() async {
        await access.prime([.deepseekAPIKey])
    }

    /// One read the user asked for. It may show the system dialog; nothing else may.
    @discardableResult
    public func authorizeCredentialAccess() async -> Bool {
        let outcome = await access.value(for: .deepseekAPIKey,
                                         purpose: .userRequestedRead,
                                         interaction: .allowed)
        return outcome.isAvailable
    }

    public func read() async throws -> ProviderReadResult {
        let outcome = await access.value(for: .deepseekAPIKey,
                                        purpose: .providerRead,
                                        interaction: .allowed)
        guard let key = outcome.secret, !key.isEmpty else {
            throw Self.failure(for: outcome)
        }
        let balances = try await provider.fetchBalances(apiKey: key)
        return ProviderReadResult(accountID: DeepSeekProvider.accountFingerprint(forAPIKey: key),
                                  balances: balances,
                                  consoleURL: nil)
    }

    /// Saves or replaces the API key (keychain only). The settings flow calls this the
    /// moment the user saves a key; the reading owns its own credential, so there is no
    /// second, separately-wired store that could be left unconnected (Round 6).
    public func storeAPIKey(_ key: String) throws {
        try access.store(key, for: .deepseekAPIKey)
    }

    /// Removes the key. A failure is propagated so the caller cannot claim a disconnect that
    /// did not happen.
    public func disconnect() throws {
        try access.remove(.deepseekAPIKey)
    }

    /// Fixed category for a credential that could not be produced. A refusal is never
    /// reported as "nothing saved" (KEYCHAIN_REVISION_PLAN.md P1.8).
    static func failure(for outcome: CredentialAccessOutcome) -> ProviderFailure {
        switch outcome {
        case .available: return .other
        case .missing: return .notConfigured
        case .interactionRequired, .deniedOrCancelled: return .credentialAccessBlocked
        case .unavailable: return .other
        }
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
///
/// Credential handling: construction reads nothing. The selected connection mode decides
/// which credential is loaded, so a console connection never probes a stored API key it is
/// not using (KEYCHAIN_REVISION_PLAN.md P1.7).
public final class GLMReading: ProviderReading, ProviderProbeReading, @unchecked Sendable {

    public let platform: ProviderPlatform = .glm

    private let provider: GLMProvider
    private let access: CredentialAccessCoordinator
    private let clock: () -> Date
    private let stateLock = NSLock()
    /// Decoded session, keyed by the raw string it was decoded from, so a decode cannot be
    /// served for a different stored value.
    private var decodedSession: (raw: String, session: GLMConsoleSessionPolicy.StoredSession)?
    /// The credential the app is currently connected with: the one saved or captured most
    /// recently. **Persisted** (a non-secret mode choice in UserDefaults), so a restart
    /// keeps using the selected console connection instead of silently falling back to an
    /// old stored API key (REVIEW round 7 finding 1).
    private var preferredCredential: PreferredCredential?
    private let preferences: UserDefaults

    /// UserDefaults key for the non-secret connection-mode choice. App-owned defaults
    /// only; never a credential value.
    static let connectionModeKey = "UsageMonitor.glm.connectionMode"

    private enum PreferredCredential: String {
        case apiKey
        case consoleSession
    }

    /// Which stored credential the app should use.
    public enum SelectedCredential: Equatable, Sendable {
        case apiKey
        case consoleSession
        case none
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
                preferences: UserDefaults = .standard,
                accessQueue: DispatchQueue? = nil) {
        self.provider = provider
        self.clock = clock
        self.preferences = preferences
        self.access = accessQueue.map { CredentialAccessCoordinator(store: credentials, queue: $0) }
            ?? CredentialAccessCoordinator(store: credentials)
        if let raw = preferences.string(forKey: Self.connectionModeKey),
           let mode = PreferredCredential(rawValue: raw) {
            self.preferredCredential = mode
        }
        // Construction deliberately reads no credential. Loading the console session here used
        // to make `AppContainer` construction wait on the keychain, which is what turned an
        // authorisation prompt into a startup stall (KEYCHAIN_REVISION_PLAN.md P1.3).
    }

    // MARK: - Credential state (memory only)

    public var credentialState: ProviderCredentialState {
        if selectedCredential() != .none { return .configured }
        let keyPhase = access.phase(for: .glmAPIKey)
        let sessionPhase = access.phase(for: .glmConsoleSession)
        if keyPhase == .needsAuthorization || sessionPhase == .needsAuthorization { return .needsAuthorization }
        if keyPhase == .unknown || sessionPhase == .unknown { return .unknown }
        if keyPhase == .unavailable || sessionPhase == .unavailable { return .unavailable }
        return .missing
    }

    public var isConfigured: Bool { credentialState.isConfigured }

    /// True when the stored credential's endpoint schema is confirmed. Platforms whose
    /// contract is unconfirmed opt out of the periodic cycle and are read on demand only.
    public var isAutomaticRefreshEnabled: Bool {
        switch selectedCredential() {
        case .apiKey: return GLMContract.isConfirmed(.apiBalanceV1)
        case .consoleSession: return GLMContract.isConfirmed(.consoleReportV1)
        case .none: return false
        }
    }

    /// Memory only: the credential exists and was readable in this process.
    public var hasAPIKey: Bool { access.phase(for: .glmAPIKey).isConfigured }
    public var hasSession: Bool { access.phase(for: .glmConsoleSession).isConfigured }

    /// State of the stored console session, from the value already in memory.
    public var sessionState: GLMConsoleSessionPolicy.SessionState {
        guard let session = sessionFromMemory() else { return .absent }
        return GLMConsoleSessionPolicy.evaluate(session, now: clock())
    }

    /// Which credential the persisted mode and the known phases select.
    public func selectedCredential() -> SelectedCredential {
        let keyConfigured = access.phase(for: .glmAPIKey).isConfigured
        let sessionConfigured = access.phase(for: .glmConsoleSession).isConfigured
        let preference = stateLock.withLock { preferredCredential }
        switch preference {
        case .apiKey where keyConfigured: return .apiKey
        case .consoleSession where sessionConfigured: return .consoleSession
        default:
            if keyConfigured { return .apiKey }
            if sessionConfigured { return .consoleSession }
            return .none
        }
    }

    // MARK: - Lifecycle

    public var onCredentialPhaseChange: (() -> Void)? {
        get { access.onPhaseChange }
        set { access.onPhaseChange = newValue }
    }

    /// Background pass at launch: the credential the persisted mode needs, and the other one
    /// only when the preferred credential turns out to be absent, so a fallback can still be
    /// offered without probing a key that is not in use.
    public func primeCredentialState() async {
        switch stateLock.withLock({ preferredCredential }) {
        case .apiKey:
            await access.prime([.glmAPIKey])
            if access.phase(for: .glmAPIKey) == .missing { await access.prime([.glmConsoleSession]) }
        case .consoleSession:
            await access.prime([.glmConsoleSession])
            if access.phase(for: .glmConsoleSession) == .missing { await access.prime([.glmAPIKey]) }
        case nil:
            await access.prime([.glmAPIKey, .glmConsoleSession])
        }
    }

    /// One read the user asked for: it may show the system dialog, and it always gets its own
    /// attempt even when the background read was refused.
    @discardableResult
    public func authorizeCredentialAccess() async -> Bool {
        let keys: [ProviderCredentialKey]
        switch selectedCredential() {
        case .apiKey: keys = [.glmAPIKey]
        case .consoleSession: keys = [.glmConsoleSession]
        case .none:
            // Nothing is known yet: ask for the credential the persisted mode expects first.
            switch stateLock.withLock({ preferredCredential }) {
            case .consoleSession: keys = [.glmConsoleSession, .glmAPIKey]
            case .apiKey, nil: keys = [.glmAPIKey, .glmConsoleSession]
            }
        }
        for key in keys {
            let outcome = await access.refresh(key, purpose: .userRequestedRead, interaction: .allowed)
            if case .available(let raw) = outcome, key == .glmConsoleSession {
                rememberSession(raw)
            }
            if outcome.isAvailable {
                return true
            }
        }
        return false
    }

    // MARK: - Writing

    /// Saves the API key (keychain only) and marks it the credential the next connection
    /// probe exercises. Called by the settings flow the moment the user saves a key.
    public func storeAPIKey(_ key: String) throws {
        try access.store(key, for: .glmAPIKey)
        stateLock.withLock { preferredCredential = .apiKey }
        preferences.set(PreferredCredential.apiKey.rawValue, forKey: Self.connectionModeKey)
    }

    /// Replaces the console session captured by the in-app login window. The payload came
    /// from this app's own web data store, never from an existing browser profile. The
    /// session becomes the credential the next connection probe exercises.
    public func storeSession(_ session: GLMConsoleSessionPolicy.StoredSession) throws {
        let data = try GLMConsoleSessionPolicy.encode(session)
        let raw = String(decoding: data, as: UTF8.self)
        try access.store(raw, for: .glmConsoleSession)
        stateLock.withLock {
            decodedSession = (raw, session)
            preferredCredential = .consoleSession
        }
        preferences.set(PreferredCredential.consoleSession.rawValue, forKey: Self.connectionModeKey)
    }

    /// Removes the API key, the console session and the cached numbers. Stops at the first
    /// failure so the caller learns the disconnect was incomplete.
    public func disconnect() throws {
        try access.remove(.glmAPIKey)
        try access.remove(.glmConsoleSession)
        stateLock.withLock {
            decodedSession = nil
            preferredCredential = nil
        }
        preferences.removeObject(forKey: Self.connectionModeKey)
    }

    // MARK: - Reading

    public func read() async throws -> ProviderReadResult {
        switch selectedCredential() {
        case .apiKey:
            let outcome = await access.value(for: .glmAPIKey, purpose: .providerRead, interaction: .allowed)
            guard let key = outcome.secret, !key.isEmpty else { throw DeepSeekReading.failure(for: outcome) }
            return try await readWithAPIKey(key)

        case .consoleSession:
            let outcome = await access.value(for: .glmConsoleSession, purpose: .providerRead, interaction: .allowed)
            guard let raw = outcome.secret,
                  let session = GLMConsoleSessionPolicy.decode(Data(raw.utf8)) else {
                throw DeepSeekReading.failure(for: outcome)
            }
            return try await readWithSession(session)

        case .none:
            throw ProviderFailure.notConfigured
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
             .serverError, .crossDomainRedirectBlocked, .cancelled, .other, .suspended,
             .credentialAccessBlocked:
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
        guard case .present = GLMConsoleSessionPolicy.evaluate(session, now: clock()) else {
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
    /// credential the selected mode uses against its own endpoint (API key → balance
    /// endpoint, console session → report endpoint). Records what the endpoint answered
    /// (HTTP status, business code, top-level key names, redacted structure) without
    /// displaying or caching any amount.
    ///
    /// Never throws for an HTTP outcome: a rejected credential, a hard-expired session and
    /// an HTTP 200 business error are all classified into the published observation. A
    /// hard-expired session is never replayed.
    @discardableResult
    public func probe() async -> GLMAccountReportObservation? {
        switch selectedCredential() {
        case .apiKey:
            let outcome = await access.value(for: .glmAPIKey, purpose: .userRequestedRead, interaction: .allowed)
            guard let key = outcome.secret, !key.isEmpty else { return nil }
            let observation = await provider.probeBalanceObservation(apiKey: key)
            record(observation)
            return observation

        case .consoleSession:
            let outcome = await access.value(for: .glmConsoleSession, purpose: .userRequestedRead, interaction: .allowed)
            guard let raw = outcome.secret,
                  let session = GLMConsoleSessionPolicy.decode(Data(raw.utf8)) else { return nil }
            let observation: GLMAccountReportObservation
            switch GLMConsoleSessionPolicy.evaluate(session, now: clock()) {
            case .present:
                observation = await probeConsoleSession(session)
            case .absent, .expired:
                // A hard-expired session is never replayed; the observation says so.
                observation = GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                                          businessCode: nil, candidateBalances: [],
                                                          parseFailure: .invalidCredential)
            }
            record(observation)
            return observation

        case .none:
            return nil
        }
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

    // MARK: - Internals

    private func record(_ observation: GLMAccountReportObservation) {
        stateLock.lock()
        lastObservation = observation
        stateLock.unlock()
        onObservation?(observation)
    }

    /// The stored session, from memory only. Nil when nothing has been read in this process.
    private func sessionFromMemory() -> GLMConsoleSessionPolicy.StoredSession? {
        guard let raw = access.cachedSecret(for: .glmConsoleSession) else { return nil }
        return decodedSessionLocked(raw: raw)
    }

    private func rememberSession(_ raw: String) {
        _ = decodedSessionLocked(raw: raw)
    }

    private func decodedSessionLocked(raw: String) -> GLMConsoleSessionPolicy.StoredSession? {
        stateLock.lock(); defer { stateLock.unlock() }
        if let decodedSession, decodedSession.raw == raw { return decodedSession.session }
        guard let session = GLMConsoleSessionPolicy.decode(Data(raw.utf8)) else {
            decodedSession = nil
            return nil
        }
        decodedSession = (raw, session)
        return session
    }

    static func cookieHeader(from session: GLMConsoleSessionPolicy.StoredSession) -> String {
        return session.cookies
            .filter { GLMConsoleSessionPolicy.isCookieAllowed(domain: $0.domain) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }
}

import Foundation

/// What a platform reader produced, already normalized.
public struct ProviderReadResult: Sendable {
    /// Account the numbers belong to. Nil means the platform could not identify an account,
    /// in which case nothing is cached: an unattributed cache entry is never written.
    public let accountID: String?
    public let balances: [ProviderBalance]
    public let consoleURL: URL?

    public init(accountID: String?, balances: [ProviderBalance], consoleURL: URL?) {
        self.accountID = accountID
        self.balances = balances
        self.consoleURL = consoleURL
    }
}

/// One provider's read operation, injected so the engine can be tested with fakes.
public protocol ProviderReading: AnyObject, Sendable {
    var platform: ProviderPlatform { get }
    /// True when a credential is stored and the platform is worth reading.
    var isConfigured: Bool { get }
    /// True when automatic refresh should run. Platforms whose contract is still
    /// unconfirmed opt out of the periodic cycle and are read on demand only.
    var isAutomaticRefreshEnabled: Bool { get }
    /// What this reader knows about its credential, answered from memory only. Status
    /// questions must never touch the keychain (KEYCHAIN_REVISION_PLAN.md P1.3).
    var credentialState: ProviderCredentialState { get }
    /// One background credential read, so later status questions can be answered from memory.
    func primeCredentialState() async
    /// One credential read the user asked for. Only this may show the system dialog.
    @discardableResult
    func authorizeCredentialAccess() async -> Bool
    func read() async throws -> ProviderReadResult
    /// Removes the stored credential and any session state. Throwing means the credential is
    /// still there, and the caller must not report a disconnect.
    func disconnect() throws
}

public extension ProviderReading {
    /// Default for readings that own no keychain credential, such as test fakes: their own
    /// `isConfigured` is the whole truth.
    var credentialState: ProviderCredentialState { isConfigured ? .configured : .missing }
    func primeCredentialState() async {}
    @discardableResult
    func authorizeCredentialAccess() async -> Bool { isConfigured }
}

/// A reader that can prove its connection with a read-only probe before the first balance
/// read. Used by the connect flow: the moment a credential is saved, the probe runs and
/// publishes its redacted observation, instead of the fresh credential being handed to the
/// normal read path — which fails closed on an unconfirmed contract gate and would report
/// a bare failure without any evidence.
public protocol ProviderProbeReading: ProviderReading {
    /// Runs the read-only connection probe (the observation is published through the
    /// reader itself) and returns the failure category the engine should record, or nil
    /// when nothing was wrong.
    func probeForConnection() async -> ProviderFailure?
}

/// Refresh policy for every detail-panel provider.
///
/// Rules implemented here (v1.1 requirement 5):
/// - one in-flight read per platform: concurrent callers await the same task instead of
///   stacking requests,
/// - a successful read is cached against the account it belongs to,
/// - a failed read keeps the last successful value and marks it stale; zero is never
///   substituted, and a failure with no previous success is reported as unavailable,
/// - an authentication failure (401, expired console session) suspends automatic retries
///   until the user reconnects,
/// - saving a connection triggers an immediate read,
/// - disconnect clears the credential and this platform's cached numbers.
///
/// All mutable state is lock-guarded, so the engine is safe to drive from the main actor
/// and from background refresh tasks at the same time.
public final class ProviderRefreshEngine: @unchecked Sendable {

    public static let defaultRefreshInterval: TimeInterval = 5 * 60
    public static let defaultPanelOpenRefreshAge: TimeInterval = ProviderCache.maxAgeForPanelOpenRefresh

    private let readers: [ProviderPlatform: ProviderReading]
    private let cache: ProviderCache
    private let panelOpenRefreshAge: TimeInterval
    private let clock: () -> Date

    private struct State {
        var lastSuccessAt: Date?
        var accountID: String?
        var lastError: ProviderFailure?
        var authSuspended = false
        var hasAttempted = false
    }

    /// An in-flight read plus a token used to retire only that read, and the credential
    /// generation it was started under.
    private struct InFlight {
        let task: Task<ProviderReport, Never>
        let id: Int
        let generation: Int
    }

    private let lock = NSRecursiveLock()
    private var states: [ProviderPlatform: State] = [:]
    private var inFlight: [ProviderPlatform: InFlight] = [:]
    private var nextInFlightID = 0
    /// Per-provider credential generation. Bumped whenever the credential changes
    /// (reconnect, connectAfterCredentialChange, disconnect); a read started under an
    /// older generation is discarded on completion, whatever it found (REVIEW round 8).
    private var generations: [ProviderPlatform: Int] = [:]

    public init(readers: [ProviderReading],
                cache: ProviderCache = ProviderCache(),
                panelOpenRefreshAge: TimeInterval = ProviderRefreshEngine.defaultPanelOpenRefreshAge,
                clock: @escaping () -> Date = Date.init) {
        var mapped: [ProviderPlatform: ProviderReading] = [:]
        for reader in readers { mapped[reader.platform] = reader }
        self.readers = mapped
        self.cache = cache
        self.panelOpenRefreshAge = panelOpenRefreshAge
        self.clock = clock
    }

    // MARK: - Reading state

    /// Current report for a platform, from memory and the persisted cache. Never performs
    /// network work, so it is safe to call from the UI.
    public func report(for platform: ProviderPlatform) -> ProviderReport {
        lock.lock(); defer { lock.unlock() }
        let (state, busy) = (states[platform] ?? State(), inFlight[platform] != nil)
        let reader = readers[platform]
        let consoleURL: URL? = nil

        guard let reader else { return Self.emptyReport(platform: platform) }

        // The credential question is answered from memory. A stored-but-unreadable credential
        // is its own state: telling the user to enter a key they already entered would be
        // wrong (KEYCHAIN_REVISION_PLAN.md P1.3 and P1.8).
        switch reader.credentialState {
        case .configured, .unknown:
            break   // unknown is transient: the startup pass is still running
        case .missing:
            return ProviderReport(platform: platform, accountID: nil, balances: [],
                                  lastSuccessAt: nil, connection: .notConfigured,
                                  isLive: false, error: nil, consoleURL: consoleURL)
        case .needsAuthorization:
            return ProviderReport(platform: platform, accountID: nil, balances: [],
                                  lastSuccessAt: nil, connection: .needsAuthorization,
                                  isLive: false, error: .credentialAccessBlocked, consoleURL: consoleURL)
        case .unavailable:
            return ProviderReport(platform: platform, accountID: nil, balances: [],
                                  lastSuccessAt: nil, connection: .unavailable,
                                  isLive: false, error: nil, consoleURL: consoleURL)
        }
        // Nothing has been read yet in this run: connect or wait for the in-flight read.
        if !state.hasAttempted {
            if busy { return connectingReport(platform: platform, consoleURL: consoleURL) }
            if let accountID = state.accountID,
               cache.load(platform: platform, accountID: accountID) != nil {
                return cachedReport(platform: platform, state: state, connection: .stale, consoleURL: consoleURL)
            }
            return connectingReport(platform: platform, consoleURL: consoleURL)
        }
        if state.authSuspended {
            return cachedReport(platform: platform, state: state, connection: .authSuspended, consoleURL: consoleURL)
        }
        if busy {
            return cachedReport(platform: platform, state: state, connection: .connecting, consoleURL: consoleURL)
        }
        if let error = state.lastError {
            if state.lastSuccessAt != nil {
                // A previous success stays on display, marked stale, never zeroed.
                return cachedReport(platform: platform, state: state, connection: .stale, consoleURL: consoleURL)
            }
            let connection: ProviderConnectionState
            switch error {
            case .invalidCredential: connection = .authSuspended
            case .contractUnconfirmed, .unexpectedResponse, .structureUnsupported: connection = .unverified
            default: connection = .unavailable
            }
            return ProviderReport(platform: platform, accountID: state.accountID, balances: [],
                                  lastSuccessAt: nil, connection: connection,
                                  isLive: false, error: error, consoleURL: consoleURL)
        }
        if let lastSuccessAt = state.lastSuccessAt {
            return ProviderReport(platform: platform,
                                  accountID: state.accountID,
                                  balances: cachedBalances(platform: platform, accountID: state.accountID),
                                  lastSuccessAt: lastSuccessAt,
                                  connection: .connected,
                                  isLive: false,
                                  error: nil,
                                  consoleURL: consoleURL)
        }
        return connectingReport(platform: platform, consoleURL: consoleURL)
    }

    public func allReports() -> [ProviderReport] {
        return [ProviderPlatform.deepseek].map { report(for: $0) }
    }

    public func isAuthSuspended(_ platform: ProviderPlatform) -> Bool {
        return locked { states[platform]?.authSuspended ?? false }
    }

    public func isFetching(_ platform: ProviderPlatform) -> Bool {
        return locked { inFlight[platform] != nil }
    }

    /// The reader behind a platform for app-owned credential flows.
    public func reading(for platform: ProviderPlatform) -> ProviderReading? {
        return readers[platform]
    }

    /// True when the platform's displayed data is older than the panel-open threshold.
    public func shouldRefreshOnPanelOpen(_ platform: ProviderPlatform) -> Bool {
        let (state, busy) = locked { (states[platform] ?? State(), inFlight[platform] != nil) }
        guard !busy else { return false }
        guard let lastSuccessAt = state.lastSuccessAt else { return true }
        return clock().timeIntervalSince(lastSuccessAt) > panelOpenRefreshAge
    }

    // MARK: - Credential priming and authorisation

    /// One background credential pass for every reader, so every later status question can be
    /// answered from memory. Performs no network work and never shows UI.
    public func primeCredentials() async {
        for platform in [ProviderPlatform.deepseek] {
            guard let reader = readers[platform] else { continue }
            await reader.primeCredentialState()
        }
    }

    /// One user-initiated credential read for a platform. True means a credential became
    /// readable, so the caller should read the platform again.
    @discardableResult
    public func authorizeCredentialAccess(platform: ProviderPlatform) async -> Bool {
        guard let reader = readers[platform] else { return false }
        return await reader.authorizeCredentialAccess()
    }

    // MARK: - Refreshing

    /// Refreshes one platform. Concurrent calls coalesce: a second caller awaiting the same
    /// platform receives the first caller's result rather than issuing a second request.
    @discardableResult
    public func refresh(platform: ProviderPlatform, force: Bool = false) async -> ProviderReport {
        // An open auth suspension stops automatic work. Only an explicit user action
        // (reconnect) clears it, so a revoked key is not retried forever.
        if !force && isAuthSuspended(platform) { return report(for: platform) }
        if let reader = readers[platform], !reader.credentialState.isConfigured { return report(for: platform) }

        // Reserve the in-flight slot atomically, so two callers cannot both start a read.
        // Reads from different credential generations never coalesce: a credential change
        // must start its own read instead of awaiting the superseded one (REVIEW round 8).
        let handle: InFlight = locked {
            if let existing = inFlight[platform], existing.generation == (generations[platform] ?? 0) {
                return existing
            }
            nextInFlightID += 1
            let generation = generations[platform] ?? 0
            let created = InFlight(task: Task<ProviderReport, Never> { [weak self] in
                await self?.performRead(platform: platform, generation: generation)
                    ?? Self.emptyReport(platform: platform)
            }, id: nextInFlightID, generation: generation)
            inFlight[platform] = created
            return created
        }
        let result = await handle.task.value
        return locked {
            if inFlight[platform]?.id == handle.id { inFlight[platform] = nil }
            return handle.generation == (generations[platform] ?? 0) ? result : report(for: platform)
        }
    }

    /// Refreshes every configured platform on the periodic schedule. Platforms whose
    /// contract is unconfirmed are skipped: they are probed on connect and on manual
    /// refresh, not on a timer.
    public func refreshScheduled() async {
        for platform in [ProviderPlatform.deepseek] {
            guard let reader = readers[platform] else { continue }
            guard reader.credentialState.isConfigured, reader.isAutomaticRefreshEnabled else { continue }
            await refresh(platform: platform, force: false)
        }
    }

    /// Called right after a credential is saved or a console session is connected.
    /// Clears any suspension and reads immediately.
    @discardableResult
    public func reconnect(platform: ProviderPlatform) async -> ProviderReport {
        invalidateAttribution(platform: platform)
        return await refresh(platform: platform, force: true)
    }

    /// The credential changed: the previously displayed numbers belong to the old
    /// credential/account and must not be presented for the new one, not even while the
    /// new read is in flight (Round 8: a relogin never shows the old account's cache).
    public func invalidateAttribution(platform: ProviderPlatform) {
        locked {
            states[platform] = State()
            inFlight[platform] = nil
            generations[platform, default: 0] += 1
        }
    }

    /// The connection action taken the moment a credential is saved or a console session
    /// is captured. While the payload contract is unconfirmed the action is the reader's
    /// read-only probe, never the normal balance read: `read()` fails closed on the
    /// contract gate, so a fresh credential handed to it would only produce a bare
    /// failure. The probe's outcome is classified into the same fixed categories a failed
    /// read uses, so an auth failure suspends automatic retry and a later reconnect
    /// resumes it. Once the contract is confirmed this is a normal forced read.
    @discardableResult
    public func connectAfterCredentialChange(platform: ProviderPlatform) async -> ProviderReport {
        invalidateAttribution(platform: platform)
        guard let reader = readers[platform], reader.credentialState.isConfigured else {
            return report(for: platform)
        }
        if let probeable = reader as? ProviderProbeReading, !reader.isAutomaticRefreshEnabled {
            let generation = locked { generations[platform] ?? 0 }
            let failure = await probeable.probeForConnection()
            return locked {
                guard generation == (generations[platform] ?? 0) else { return report(for: platform) }
                return recordFailure(platform: platform, failure: failure ?? .contractUnconfirmed,
                                     consoleURL: nil)
            }
        }
        return await refresh(platform: platform, force: true)
    }

    /// Records the outcome of a user-requested read-only probe (探测一次) without touching
    /// the normal read path or clearing an auth suspension.
    @discardableResult
    public func recordProbeOutcome(platform: ProviderPlatform, failure: ProviderFailure) -> ProviderReport {
        return recordFailure(platform: platform,
                             failure: failure,
                             consoleURL: nil)
    }

    /// Removes the credential and everything derived from it: the platform's cached
    /// numbers included, so a disconnected account leaves nothing behind.
    ///
    /// Returns the failure when the credential could not be removed. The cached numbers and
    /// the recorded state are then left untouched: reporting a disconnect that did not
    /// happen would be a lie the user cannot see through
    /// (KEYCHAIN_REVISION_PLAN.md P1.8).
    @discardableResult
    public func disconnect(platform: ProviderPlatform) -> ProviderFailure? {
        lock.lock(); defer { lock.unlock() }
        inFlight[platform] = nil
        var failure: ProviderFailure?
        if let reader = readers[platform] {
            do {
                try reader.disconnect()
            } catch let providerFailure as ProviderFailure {
                failure = providerFailure
            } catch {
                failure = .other
            }
        }
        guard failure == nil else { return failure }
        cache.clear(platform: platform)
        locked {
            states[platform] = nil
            // An in-flight read of the removed credential must not resurrect state.
            generations[platform, default: 0] += 1
        }
        return nil
    }

    // MARK: - Internals

    private func performRead(platform: ProviderPlatform, generation: Int) async -> ProviderReport {
        guard let reader = readers[platform] else { return Self.emptyReport(platform: platform) }
        let consoleURL: URL? = nil

        do {
            let result = try await reader.read()
            return commit(result, platform: platform, generation: generation, consoleURL: consoleURL)
        } catch let failure as ProviderFailure {
            return commitFailure(failure, platform: platform, generation: generation, consoleURL: consoleURL)
        } catch let transport as ProviderTransportError {
            return commitFailure(ProviderFailure.from(transport), platform: platform, generation: generation, consoleURL: consoleURL)
        } catch {
            return commitFailure(.other, platform: platform, generation: generation, consoleURL: consoleURL)
        }
    }

    private func commit(_ result: ProviderReadResult, platform: ProviderPlatform, generation: Int,
                        consoleURL: URL?) -> ProviderReport {
        // The credential changed while this read was on the wire: the outcome belongs
        // to a dead credential and must not touch state or cache. Cancellation is not
        // relied on (a transport may ignore it); the generation check is the gate.
        lock.lock(); defer { lock.unlock() }
        guard generation == (generations[platform] ?? 0) else {
            return report(for: platform)
        }
        guard !result.balances.isEmpty else {
            return recordFailure(platform: platform, failure: .unexpectedResponse, consoleURL: consoleURL)
        }
        let now = clock()
        locked {
            var state = states[platform] ?? State()
            state.lastSuccessAt = now
            state.accountID = result.accountID
            state.lastError = nil
            state.authSuspended = false
            state.hasAttempted = true
            states[platform] = state
        }
        // Cache only when the account is known, so an entry can never be attributed to
        // a different account later.
        if let accountID = result.accountID, !accountID.isEmpty {
            cache.save(platform: platform, accountID: accountID, balances: result.balances, lastSuccessAt: now)
        }
        return ProviderReport(platform: platform,
                              accountID: result.accountID,
                              balances: result.balances,
                              lastSuccessAt: now,
                              connection: .connected,
                              isLive: true,
                              error: nil,
                              consoleURL: consoleURL)
    }

    private func commitFailure(_ failure: ProviderFailure, platform: ProviderPlatform,
                               generation: Int, consoleURL: URL?) -> ProviderReport {
        locked {
            guard generation == (generations[platform] ?? 0) else { return report(for: platform) }
            return recordFailure(platform: platform, failure: failure, consoleURL: consoleURL)
        }
    }

    private func recordFailure(platform: ProviderPlatform, failure: ProviderFailure, consoleURL: URL?) -> ProviderReport {
        lock.lock(); defer { lock.unlock() }
        locked {
            var state = states[platform] ?? State()
            state.lastError = failure
            state.hasAttempted = true
            if failure.isAuthenticationFailure {
                state.authSuspended = true
            }
            states[platform] = state
        }
        let state = locked { states[platform] ?? State() }
        if state.lastSuccessAt != nil {
            // The last successful value stays on display, marked stale, never zeroed.
            return cachedReport(platform: platform, state: state, connection: .stale, consoleURL: consoleURL)
        }
        let connection: ProviderConnectionState
        switch failure {
        case .invalidCredential: connection = .authSuspended
        case .contractUnconfirmed, .unexpectedResponse, .structureUnsupported: connection = .unverified
        default: connection = .unavailable
        }
        return ProviderReport(platform: platform, accountID: state.accountID, balances: [],
                              lastSuccessAt: nil, connection: connection,
                              isLive: false, error: failure, consoleURL: consoleURL)
    }

    private func cachedReport(platform: ProviderPlatform,
                              state: State,
                              connection: ProviderConnectionState,
                              consoleURL: URL?) -> ProviderReport {
        return ProviderReport(platform: platform,
                              accountID: state.accountID,
                              balances: cachedBalances(platform: platform, accountID: state.accountID),
                              lastSuccessAt: state.lastSuccessAt,
                              connection: connection,
                              isLive: false,
                              error: state.lastError,
                              consoleURL: consoleURL)
    }

    private func connectingReport(platform: ProviderPlatform, consoleURL: URL?) -> ProviderReport {
        return ProviderReport(platform: platform, accountID: nil, balances: [],
                              lastSuccessAt: nil, connection: .connecting,
                              isLive: false, error: nil, consoleURL: consoleURL)
    }

    private func cachedBalances(platform: ProviderPlatform, accountID: String?) -> [ProviderBalance] {
        guard let accountID, !accountID.isEmpty else { return [] }
        return cache.load(platform: platform, accountID: accountID)?.providerBalances ?? []
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    static func emptyReport(platform: ProviderPlatform) -> ProviderReport {
        return ProviderReport(platform: platform, accountID: nil, balances: [],
                              lastSuccessAt: nil, connection: .unavailable,
                              isLive: false, error: .other,
                              consoleURL: nil)
    }
}

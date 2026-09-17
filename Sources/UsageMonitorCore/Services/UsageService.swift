import Foundation

/// Orchestrates one long-lived app-server child, the cache and the refresh policy.
///
/// Rules implemented here (PROJECT_SPEC.md §8, §10, §11; IMPLEMENTATION_PLAN.md):
/// - a single in-flight fetch at a time,
/// - on any failure the cached snapshot is returned marked `.cached`, never presented as live,
/// - one bounded recovery state machine covers factory, start, handshake and read
///   failures alike: a continuous failure episode gets one launch attempt plus one
///   automatic restart in total (Round 3 blocker 1), and non-restartable failures open
///   the episode without consuming a restart,
/// - the episode is closed only by success or by an explicit manual retry
///   (`resetFailureBudget: true`); time alone never re-opens it,
/// - `stop()` drains: it waits, bounded, for the in-flight fetch to finish and for the
///   owned child to be reaped before returning, so a parent that exits right after
///   `stop()` leaves no survivor (Round 3 blocker 2),
/// - `fetchedAt` keeps the time of the last *successful* fetch.
public final class UsageService: @unchecked Sendable {

    public enum ConnectionState: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case disconnected
    }

    /// Injectable factory so tests can substitute a fake transport. The factory only
    /// builds the client; the service starts it so restarts are counted in one place.
    public typealias ClientFactory = () throws -> CodexAppServerProviding

    private let factory: ClientFactory
    private let cache: UsageCache
    /// Owning ChatGPT profile, or nil for the pre-1.3.0 single-account wiring.
    ///
    /// When set, every cached read and write is scoped to `profileID + accountID`, so two
    /// long-lived profiles can never serve each other's numbers (REQUIREMENTS.md §4.3).
    private let profileID: String?
    private let restartDelay: TimeInterval
    private let clock: () -> Date

    private let lock = NSLock()
    private var client: CodexAppServerProviding?
    /// Client whose `start()` is still running. Registered before `start()` so a
    /// concurrent `stop()` can reach a child that is being launched.
    private var startingClient: CodexAppServerProviding?
    /// Bumped by every `stop()`. Work started under an older generation is abandoned.
    private var generation = 0
    /// Set by `stop()`: no new children until `resume()`.
    private var stopped = false
    /// Account identity of the last successful `account/read`. Drives cache attribution.
    private var lastAccount: CodexAccount?

    // Failure-episode circuit breaker.
    private var failureEpisodeActive = false
    private var restartsUsedInEpisode = 0
    private var failureEpisodeOpenedAt: Date?

    /// In-flight fetch bookkeeping, used by the bounded drain in `stop()`.
    private var fetchInFlight = false
    private var fetchThread: Thread?
    private var fetchFinished = DispatchSemaphore(value: 0)

    private var state: ConnectionState = .idle
    private var lastError: UsageError?

    public init(factory: @escaping ClientFactory,
                cache: UsageCache = UsageCache(),
                profileID: String? = nil,
                restartDelay: TimeInterval = 0.5,
                clock: @escaping () -> Date = Date.init) {
        self.factory = factory
        self.cache = cache
        self.profileID = profileID
        self.restartDelay = restartDelay
        self.clock = clock
    }

    /// Builds the environment one child is launched with: a copy of `base` with `CODEX_HOME`
    /// replaced. Account isolation lives entirely here, so `CodexLocator` stays a plain
    /// executable finder (IMPLEMENTATION_TASKS.md §1.2).
    ///
    /// The result never reaches `Diagnostics`: only the profile identifier and the process
    /// lifecycle are logged, never environment values.
    public static func childEnvironment(base: [String: String],
                                        codexHome: URL?) -> [String: String] {
        guard let codexHome else { return base }
        var copy = base
        copy["CODEX_HOME"] = codexHome.path
        return copy
    }

    /// Default production wiring: locate `codex`, launch `codex app-server`, reuse it.
    ///
    /// - Parameters:
    ///   - environment: the process environment to copy for the child.
    ///   - codexHome: when given, the child's `CODEX_HOME`; the copy makes the profile's
    ///     isolated account directory apply to this child only.
    ///   - profileID: scopes the cache to one profile when set.
    public convenience init(cache: UsageCache = UsageCache(),
                            environment: [String: String] = ProcessInfo.processInfo.environment,
                            codexHome: URL? = nil,
                            profileID: String? = nil) {
        let childEnvironment = Self.childEnvironment(base: environment, codexHome: codexHome)
        self.init(
            factory: {
                let executable = try CodexLocator().locate(environment: environment)
                return CodexAppServerClient(transport: JSONRPCClient(executableURL: executable,
                                                                     arguments: ["app-server"],
                                                                     environment: childEnvironment))
            },
            cache: cache,
            profileID: profileID
        )
    }

    public var connectionState: ConnectionState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    /// True while a failure episode is open (no further automatic launches).
    public var isFailureEpisodeActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return failureEpisodeActive
    }

    /// Account identity of the last successful `account/read`, if any.
    public var currentAccount: CodexAccount? {
        lock.lock(); defer { lock.unlock() }
        return lastAccount
    }

    /// Identifier the business cache is attributed to: the last known account, falling back
    /// to the one remembered from a previous run. Nil when no account is known at all.
    public var currentAccountID: String? {
        lock.lock(); let account = lastAccount; lock.unlock()
        if let id = account?.cacheAccountID { return id }
        if let profileID { return cache.loadLastKnownAccountID(profileID: profileID) }
        return cache.loadLastKnownAccountID()
    }

    /// Cached snapshot for the account the app believes is current.
    ///
    /// Strictness (v1.1 requirement 2): when an account is known, only that account's entry
    /// is returned. In profile mode the lookup is additionally scoped to this profile, so
    /// account A's cache can never appear behind account B (REQUIREMENTS.md §4.3).
    public func cachedSnapshotForCurrentAccount() -> UsageSnapshot? {
        if let profileID {
            return cache.load(profileID: profileID, accountID: currentAccountID)
        }
        if let accountID = currentAccountID, !accountID.isEmpty {
            return cache.load(accountID: accountID)
        }
        return cache.load()
    }

    /// Result of a refresh attempt: a (possibly cached) snapshot plus whether it is live.
    public struct FetchResult {
        public let snapshot: UsageSnapshot
        public let isLive: Bool
        public let error: UsageError?
        /// Account identity from `account/read`, or nil when it could not be established.
        /// The panel shows 账号信息暂不可用 rather than guessing.
        public let account: CodexAccount?

        public init(snapshot: UsageSnapshot, isLive: Bool, error: UsageError?, account: CodexAccount? = nil) {
            self.snapshot = snapshot
            self.isLive = isLive
            self.error = error
            self.account = account
        }
    }

    /// Fetches usage, applying the cache-on-failure policy. Blocking; callers should
    /// invoke it off the main thread.
    ///
    /// - Parameter resetFailureBudget: pass true for an explicit user-initiated retry;
    ///   it is the only way to re-open the attempt budget of a failed episode.
    @discardableResult
    public func fetch(resetFailureBudget: Bool = false,
                      fetchTimeout: TimeInterval = CodexAppServerClient.defaultTimeout) throws -> FetchResult {
        lock.lock()
        if stopped {
            lock.unlock()
            throw UsageError.rpcFailed(.shutdown)
        }
        if fetchInFlight {
            let deferredError = lastError
            lock.unlock()
            // Coalesce concurrent refreshes instead of stacking requests.
            if let cached = servedCachedSnapshot() {
                return FetchResult(snapshot: cached, isLive: false, error: deferredError, account: nil)
            }
            throw deferredError ?? UsageError.rpcFailed(.other)
        }
        // An open failure episode means the previous episode already used its attempt plus
        // restart. Only an explicit manual retry re-opens it; the passage of time does not.
        if !resetFailureBudget && failureEpisodeActive {
            let recordedError = lastError
            lock.unlock()
            if let cached = servedCachedSnapshot() {
                return FetchResult(snapshot: cached, isLive: false, error: recordedError, account: nil)
            }
            throw recordedError ?? UsageError.rpcFailed(.other)
        }
        fetchInFlight = true
        fetchThread = Thread.current
        let generationAtStart = generation
        if resetFailureBudget {
            failureEpisodeActive = false
            restartsUsedInEpisode = 0
            failureEpisodeOpenedAt = nil
        }
        lock.unlock()
        defer {
            lock.lock()
            fetchInFlight = false
            fetchThread = nil
            lock.unlock()
            fetchFinished.signal()
        }

        do {
            let outcome = try performFetch(fetchTimeout: fetchTimeout, generationAtStart: generationAtStart)
            Diagnostics.log("fetch ok windows=5h:\(outcome.snapshot.fiveHour != nil)/weekly:\(outcome.snapshot.weekly != nil) account:\(outcome.account?.debugSummary ?? "unavailable")")
            persistSnapshot(outcome.snapshot, account: outcome.account)
            lock.lock()
            lastError = nil
            failureEpisodeActive = false   // success closes the episode
            restartsUsedInEpisode = 0
            failureEpisodeOpenedAt = nil
            lock.unlock()
            return FetchResult(snapshot: outcome.snapshot, isLive: true, error: nil, account: outcome.account)
        } catch let error as UsageError {
            Diagnostics.log("fetch failed: \(error.debugSummary)")
            lock.lock(); lastError = error; lock.unlock()
            if error.isShutdown { throw error }   // shutdown must surface, not hide behind cache
            if let cached = servedCachedSnapshot() {
                return FetchResult(snapshot: cached, isLive: false, error: error, account: nil)
            }
            throw error
        }
    }

    /// One launch attempt plus at most one automatic restart, for every failure kind:
    /// factory errors, start errors, handshake errors and read errors all flow through
    /// the same recovery decision (Round 3 blocker 1).
    private func performFetch(fetchTimeout: TimeInterval, generationAtStart: Int) throws -> (snapshot: UsageSnapshot, account: CodexAccount?) {
        while true {
            if isStale(generationAtStart) { throw UsageError.rpcFailed(.shutdown) }
            lock.lock(); state = .connecting; lock.unlock()

            let client: CodexAppServerProviding
            do {
                client = try acquireClient(generationAtStart: generationAtStart)
            } catch {
                // Factory and start failures are part of the same bounded budget.
                if isStale(generationAtStart) { throw UsageError.rpcFailed(.shutdown) }
                let usageError = Self.asUsageError(error)
                lock.lock(); state = .disconnected; lastError = usageError; lock.unlock()
                closeClient()
                if mayRetryAfter(usageError) {
                    pauseBeforeRestart()
                    continue
                }
                throw usageError
            }

            do {
                try client.handshake(timeout: fetchTimeout)
                if isStale(generationAtStart) { throw UsageError.rpcFailed(.shutdown) }

                // Identity first, so the usage read can be attributed to the account that
                // produced it. `refreshToken: false`: read only, never refresh.
                let account = readAccountBestEffort(from: client, timeout: fetchTimeout)

                let snapshot = try client.readRateLimits(timeout: fetchTimeout)
                if isStale(generationAtStart) { throw UsageError.rpcFailed(.shutdown) }
                lock.lock()
                state = .connected
                lock.unlock()
                return (snapshot, account)
            } catch {
                let usageError = Self.asUsageError(error)
                if isStale(generationAtStart) { throw UsageError.rpcFailed(.shutdown) }
                lock.lock(); state = .disconnected; lastError = usageError; lock.unlock()
                closeClient()
                if mayRetryAfter(usageError) {
                    pauseBeforeRestart()
                    continue
                }
                throw usageError
            }
        }
    }

    /// Reads the account identity without ever failing the usage read. A failed identity
    /// read is reported as 账号信息暂不可用, while the previously known account stays
    /// recorded for cache attribution.
    private func readAccountBestEffort(from client: CodexAppServerProviding, timeout: TimeInterval) -> CodexAccount? {
        do {
            guard let account = try client.readAccount(timeout: timeout) else { return nil }
            if let id = account.cacheAccountID {
                if let profileID {
                    // Profile-scoped attribution, plus the one-time 1.2.1 -> 1.3.0 cache
                    // migration this first successful identity read unlocks.
                    cache.saveLastKnownAccountID(id, profileID: profileID)
                    cache.migrateLegacyCacheIfNeeded(profileID: profileID, resolvedAccountID: id)
                } else {
                    cache.saveLastKnownAccountID(id)
                }
                lock.lock(); lastAccount = account; lock.unlock()
            }
            return account
        } catch {
            Diagnostics.log("account read unavailable")
            return nil
        }
    }

    /// Writes the snapshot to the store that matches its attribution: the profile-scoped
    /// store when this service owns a profile, otherwise the v1.1 account store when an
    /// account can be identified, and the legacy store only in the no-account case.
    private func persistSnapshot(_ snapshot: UsageSnapshot, account: CodexAccount?) {
        let accountID = account?.cacheAccountID ?? currentAccountID
        if let profileID {
            cache.save(snapshot, profileID: profileID, accountID: accountID)
            return
        }
        if let accountID, !accountID.isEmpty {
            cache.save(snapshot, accountID: accountID)
        } else {
            cache.save(snapshot)
        }
    }

    /// Cache the failure paths may serve. Strict when an account is known; the legacy
    /// unattributed store is reachable only when no account is known at all.
    private func servedCachedSnapshot() -> UsageSnapshot? {
        if let profileID {
            return cache.load(profileID: profileID, accountID: currentAccountID)
        }
        if let accountID = currentAccountID, !accountID.isEmpty {
            return cache.load(accountID: accountID)
        }
        return cache.load()
    }


    /// Whether one more attempt is permitted after a failure of any kind.
    /// Non-restartable failures (missing CLI, not signed in) open the episode without
    /// consuming a restart, so later scheduled fetches stop repeating them.
    private func mayRetryAfter(_ error: UsageError) -> Bool {
        guard !error.isShutdown, error.isRestartable else {
            openFailureEpisode()
            return false
        }
        lock.lock()
        guard !failureEpisodeActive else {
            openFailureEpisodeLocked()
            lock.unlock()
            return false
        }
        failureEpisodeActive = true
        restartsUsedInEpisode += 1
        if failureEpisodeOpenedAt == nil { failureEpisodeOpenedAt = clock() }
        lock.unlock()
        return true
    }

    private func openFailureEpisode() {
        lock.lock()
        openFailureEpisodeLocked()
        lock.unlock()
    }

    private func openFailureEpisodeLocked() {
        failureEpisodeActive = true
        if failureEpisodeOpenedAt == nil { failureEpisodeOpenedAt = clock() }
    }

    private func pauseBeforeRestart() {
        if restartDelay > 0 { Thread.sleep(forTimeInterval: restartDelay) }
    }

    private static func asUsageError(_ error: Error) -> UsageError {
        (error as? UsageError) ?? .rpcFailed(.other)
    }

    private func isStale(_ generationAtStart: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped || generation != generationAtStart
    }

    private func acquireClient(generationAtStart: Int) throws -> CodexAppServerProviding {
        lock.lock()
        if let client, !stopped, generation == generationAtStart, client.isTransportRunning {
            lock.unlock()
            return client
        }
        lock.unlock()
        closeClient()

        lock.lock()
        if stopped || generation != generationAtStart {
            lock.unlock()
            throw UsageError.rpcFailed(.shutdown)
        }
        lock.unlock()

        Diagnostics.log("starting app-server child")
        let created: CodexAppServerProviding
        do {
            created = try factory()
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.appServerStartupFailed(.launchFailed)
        }

        // Register before start() so stop() can reach the child being launched.
        lock.lock()
        if stopped || generation != generationAtStart {
            lock.unlock()
            created.stop()
            throw UsageError.rpcFailed(.shutdown)
        }
        startingClient = created
        lock.unlock()

        do {
            try created.start()
        } catch let error as UsageError {
            lock.lock(); startingClient = nil; lock.unlock()
            throw error
        } catch {
            lock.lock(); startingClient = nil; lock.unlock()
            throw UsageError.appServerStartupFailed(.launchFailed)
        }

        // start() may have been slow: only publish if the generation is still current.
        lock.lock()
        startingClient = nil
        if stopped || generation != generationAtStart {
            lock.unlock()
            created.stop()   // clean up the late child
            throw UsageError.rpcFailed(.shutdown)
        }
        client = created
        lock.unlock()
        Diagnostics.log("app-server child started pid \(created.childProcessIdentifier)")
        return created
    }

    /// Stops the owned child and refuses further launches until `resume()`.
    ///
    /// Draining (Round 3 blocker 2): returns only after the in-flight fetch has finished
    /// and any child it launched has been stopped and reaped, bounded by `shutdownTimeout`.
    /// Safe to call concurrently with a fetch, during a start, and more than once.
    public func stop(shutdownTimeout: TimeInterval = 8.0) {
        let victims: [CodexAppServerProviding]
        lock.lock()
        generation += 1
        stopped = true
        state = .idle
        var found: [CodexAppServerProviding] = []
        if let client { found.append(client); self.client = nil }
        if let startingClient { found.append(startingClient); self.startingClient = nil }
        let wasInFlight = fetchInFlight
        let fetchOwnerThread = fetchThread
        victims = found
        lock.unlock()
        for victim in victims { victim.stop() }

        // Wait, bounded, for the in-flight fetch to exit. A fetch running on the calling
        // thread cannot be waited for here (that would self-deadlock).
        if wasInFlight, fetchOwnerThread !== Thread.current {
            let deadline = Date().addingTimeInterval(shutdownTimeout)
            while Date() < deadline {
                lock.lock(); let busy = fetchInFlight; lock.unlock()
                if !busy { break }
                _ = fetchFinished.wait(timeout: .now() + 0.05)
            }
            // A child launched between the first sweep and the fetch exiting.
            lock.lock()
            let late = [client, startingClient].compactMap { $0 }
            self.client = nil
            self.startingClient = nil
            lock.unlock()
            for child in late { child.stop() }
        }
        Diagnostics.log("service stopped (generation \(generation), drained=\(wasInFlight ? "yes" : "no"))")
    }

    /// Allows fetching again after `stop()`, for explicit user-driven retries.
    public func resume() {
        lock.lock()
        stopped = false
        state = .idle
        lock.unlock()
    }

    public var cachedSnapshot: UsageSnapshot? { cache.load() }

    /// Process identifier of the currently owned child, or -1. Lifecycle reporting only.
    var currentClientPID: pid_t {
        lock.lock(); defer { lock.unlock() }
        return client?.childProcessIdentifier ?? startingClient?.childProcessIdentifier ?? -1
    }

    /// Fixed-category summary of the last failure, safe for logs and tests.
    public var lastFailureSummary: String? {
        lock.lock(); defer { lock.unlock() }
        return lastError?.debugSummary
    }

    private func closeClient() {
        lock.lock()
        let current = client
        client = nil
        lock.unlock()
        current?.stop()
    }
}

extension UsageError {
    /// `codex` missing or not signed in cannot be fixed by relaunching the child.
    public var isRestartable: Bool {
        switch self {
        case .codexCLINotFound, .codexNotSignedIn, .windowUnavailable:
            return false
        case .appServerStartupFailed, .rpcFailed:
            return !isShutdown
        }
    }

    /// Shutdown was requested; the failure is expected and must not be retried or hidden.
    public var isShutdown: Bool {
        if self == .rpcFailed(.shutdown) { return true }
        if case .appServerStartupFailed(.shutdown) = self { return true }
        return false
    }
}

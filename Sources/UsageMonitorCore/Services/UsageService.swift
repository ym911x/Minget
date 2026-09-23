import Foundation

/// Orchestrates one long-lived app-server child, the cache and the refresh policy.
///
/// Rules implemented here (1.4.2 REQUIREMENTS.md §3; earlier PROJECT_SPEC.md §8, §10, §11):
/// - one shared single-flight operation per profile. Automatic refresh, manual refresh,
///   wake probes and fire confirmation reads all join the operation that is already
///   running, and every waiter receives that operation's *actual* result. The previous
///   behaviour — serving the cache to a caller that arrived while a fetch was in flight —
///   is gone; the cache is served only by the explicit backoff gate below,
/// - a manual fetch (`resetFailureBudget: true`) that arrives while an operation runs
///   queues exactly one follow-up fetch. The runner executes it right after the current
///   operation, and every queued manual caller receives the follow-up's actual result.
///   Automatic callers only coalesce; they never queue a follow-up,
/// - one failed episode retries immediately exactly once; after that the next *automatic*
///   attempt waits the 30/60/120/300 s ladder (`CodexRetryPolicy`, capped at 300 s). A
///   success resets the ladder, a manual fetch bypasses the gate, and non-restartable
///   failures (missing CLI, not signed in) require a manual retry instead of a retry loop,
/// - timeouts are split per call: handshake 5 s, identity 3 s, quota read 15 s,
/// - `stop()` releases every waiter with a shutdown error and drains the running
///   operation, so cancellation can never leave a caller blocked,
/// - on any failure the cached snapshot is returned marked `.cached`, never presented as
///   live, and `fetchedAt` keeps the time of the last *successful* fetch.
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
    /// Pause between the two attempts of one episode (the "immediate" retry).
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
    /// Bumped every time a new child is published. Identity observed on an older epoch
    /// belongs to a replaced connection and is never carried across (1.4.2 §3.4).
    private var connectionEpoch = 0

    // MARK: Retry ladder state (CodexRetryPolicy holds the numbers)
    /// Consecutive failed episodes. Reset by any success and by a manual fetch.
    private var failedEpisodes = 0
    /// Earliest instant the next *automatic* fetch may start a new episode. Nil = no gate.
    private var nextAutomaticRetryAt: Date?
    /// Set by non-restartable failures (CLI missing, not signed in): automatic fetches
    /// stop looping entirely until an explicit manual retry.
    private var manualRetryRequired = false

    // MARK: Shared single-flight state
    /// Exactly one operation (fetch, rate-limits-only read or wake probe) runs at a time.
    private var operationRunning = false
    private var operationThread: Thread?
    private var operationFinished = DispatchSemaphore(value: 0)
    /// Waiters joined to the running operation; each receives its actual result.
    private var waiters: [WaiterBox] = []
    /// Set when a manual caller arrived during the running operation. At most one
    /// follow-up is ever queued, however many manual callers arrive.
    private var followUpQueued = false
    /// Manual callers waiting for the queued follow-up's actual result.
    private var followUpWaiters: [WaiterBox] = []

    private var state: ConnectionState = .idle
    private var lastError: UsageError?

    /// One slot of the single-flight fan-out. The runner fulfils it with the operation's
    /// actual outcome (or the shutdown error `stop()` injected), then the waiter wakes.
    private final class WaiterBox: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        private let boxLock = NSLock()
        private var value: Result<FetchResult, Error>?

        func fulfill(_ result: Result<FetchResult, Error>) {
            boxLock.lock()
            if value == nil { value = result }
            boxLock.unlock()
            semaphore.signal()
        }

        /// Blocks until fulfilled; the shutdown path always fulfils, so no caller can
        /// stay blocked across `stop()`.
        func wait() -> Result<FetchResult, Error> {
            semaphore.wait()
            boxLock.lock()
            let resolved = value
            boxLock.unlock()
            return resolved ?? .failure(UsageError.rpcFailed(.shutdown))
        }
    }

    /// Which operation the shared slot should run.
    private enum OperationKind {
        /// Full cycle: handshake, identity, quota read.
        case full(resetFailureBudget: Bool)
        /// Confirmation read: handshake and quota only; no identity request. The manual
        /// flag lets the fire flow's confirmation bypass the automatic ladder, exactly
        /// like the manual fire it belongs to.
        case rateLimitsOnly(resetFailureBudget: Bool)
        /// Wake-only light read against the existing healthy child: no launch, no
        /// episode, no ladder touch. Still occupies the shared slot, so a fetch that
        /// starts concurrently joins it instead of racing it on the same child.
        case wakeProbe
    }

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

    /// True when an automatic fetch arriving now would be gated by the retry backoff.
    public var isRetryBackoffActive: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let nextAutomaticRetryAt else { return false }
        return clock() < nextAutomaticRetryAt
    }

    /// True when a non-restartable failure stopped the automatic loop and only a manual
    /// retry may fetch again.
    public var isManualRetryRequired: Bool {
        lock.lock(); defer { lock.unlock() }
        return manualRetryRequired
    }

    /// The earliest instant the next automatic attempt may run, when the backoff gate is set.
    public var automaticRetryGate: Date? {
        lock.lock(); defer { lock.unlock() }
        return nextAutomaticRetryAt
    }

    /// True while the shared operation slot is occupied.
    public var isOperationRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return operationRunning
    }

    /// Current connection epoch. Increments whenever a new child is published; identity
    /// observed under an older epoch is not carried across.
    public var currentConnectionEpoch: Int {
        lock.lock(); defer { lock.unlock() }
        return connectionEpoch
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
    public struct FetchResult: Sendable {
        public let snapshot: UsageSnapshot
        public let isLive: Bool
        public let error: UsageError?
        /// Account identity from `account/read`, or nil when it could not be established.
        /// The panel shows 账号信息暂不可用 rather than guessing.
        public let account: CodexAccount?
        /// When the live quota read started, or nil for a cache-served result. The fire
        /// confirmation uses this as a freshness barrier: a read that began before the
        /// fire request finished is pre-fire evidence and must not be counted (1.4.2
        /// REQUIREMENTS.md §3.5).
        public let readStartedAt: Date?
        /// App-server connection under which the live result was read. A later child
        /// replacement prevents identity state from being carried across this result.
        public let connectionEpoch: Int?

        public init(snapshot: UsageSnapshot, isLive: Bool, error: UsageError?, account: CodexAccount? = nil,
                    readStartedAt: Date? = nil, connectionEpoch: Int? = nil) {
            self.snapshot = snapshot
            self.isLive = isLive
            self.error = error
            self.account = account
            self.readStartedAt = readStartedAt
            self.connectionEpoch = connectionEpoch
        }
    }

    /// Outcome of the wake-only health check. The probe never creates or restarts a child:
    /// a missing or unhealthy existing client is handed back to the ordinary refresh path,
    /// which remains the sole owner of the retry ladder.
    public enum WakeProbeResult: Sendable {
        case refreshed(FetchResult)
        case needsFullRefresh
        case suppressed
    }

    // MARK: - Public entry points

    /// Fetches usage, applying the cache-on-failure policy. Blocking; callers should
    /// invoke it off the main thread.
    ///
    /// - Parameter resetFailureBudget: pass true for an explicit user-initiated retry. It
    ///   bypasses the backoff gate, resets the ladder, and — when another operation is
    ///   already running — queues exactly one follow-up whose actual result this caller
    ///   receives.
    @discardableResult
    public func fetch(resetFailureBudget: Bool = false,
                      handshakeTimeout: TimeInterval = CodexAppServerClient.handshakeTimeout,
                      identityTimeout: TimeInterval = CodexAppServerClient.identityTimeout,
                      quotaTimeout: TimeInterval = CodexAppServerClient.quotaTimeout) throws -> FetchResult {
        try performShared(.full(resetFailureBudget: resetFailureBudget),
                          handshakeTimeout: handshakeTimeout,
                          identityTimeout: identityTimeout,
                          quotaTimeout: quotaTimeout)
    }

    /// Confirmation-only read for the fire sequence: handshake plus rate limits, without
    /// the account identity read. The confirmation only needs the 5-hour `resetsAt`, so
    /// the identity request is pure load on the service (REQUIREMENTS.md §3.1).
    ///
    /// Shares the single-flight slot, the retry ladder and the shutdown semantics with
    /// `fetch`. Nothing about the account is touched: no `lastAccount` update, no
    /// last-known attribution write, no legacy migration.
    @discardableResult
    public func fetchRateLimitsOnly(resetFailureBudget: Bool = false,
                                    handshakeTimeout: TimeInterval = CodexAppServerClient.handshakeTimeout,
                                    quotaTimeout: TimeInterval = CodexAppServerClient.quotaTimeout) throws -> FetchResult {
        try performShared(.rateLimitsOnly(resetFailureBudget: resetFailureBudget),
                          handshakeTimeout: handshakeTimeout,
                          identityTimeout: CodexAppServerClient.identityTimeout,
                          quotaTimeout: quotaTimeout)
    }

    /// Wake-only health check against the already-running child. Read-only and cheap:
    /// no child is launched, no retry episode is opened, and the ladder is untouched.
    ///
    /// The probe occupies the same single-flight slot as every other operation, so a
    /// fetch that starts while it runs joins it and receives its actual result instead
    /// of racing it on the same child (1.4.2 independent review: the free-standing read
    /// could concurrently use — and on failure close — a connection another round was
    /// about to use).
    ///
    /// - An operation already running: this probe *joins* it and reports its actual result,
    ///   instead of racing it or serving the cache.
    /// - A retry gate active (backoff or manual retry required): `.suppressed`, matching the
    ///   old breaker behaviour — the wake path must not circumvent the ladder.
    /// - No healthy child: `.needsFullRefresh`; the ordinary refresh path stays the sole
    ///   owner of child launch and retries.
    /// - Healthy child: handshake plus one quota read; a success persists the confirmation
    ///   snapshot and reports `.refreshed`, a failure retires the child and reports
    ///   `.needsFullRefresh`.
    @discardableResult
    public func probeRateLimitsAfterWake(
        handshakeTimeout: TimeInterval = CodexAppServerClient.handshakeTimeout,
        quotaTimeout: TimeInterval = CodexAppServerClient.quotaTimeout
    ) -> WakeProbeResult {
        lock.lock()
        if stopped { lock.unlock(); return .suppressed }
        if operationRunning {
            // Join the running operation and wait for its actual outcome.
            let box = joinLocked(kind: .wakeProbe)
            lock.unlock()
            let outcome = box.wait()
            if case .success(let result) = outcome, result.isLive { return .refreshed(result) }
            return .needsFullRefresh
        }
        if manualRetryRequired || !CodexRetryPolicy.isAutomaticAttemptDue(nextRetryAt: nextAutomaticRetryAt, now: clock()) {
            lock.unlock()
            return .suppressed
        }
        guard let existing = client, existing.isTransportRunning else {
            // Retire a defunct child now so the full refresh launches a fresh one.
            let defunct = client
            client = nil
            lock.unlock()
            defunct?.stop()
            return .needsFullRefresh
        }
        lock.unlock()

        // From here the probe runs as the slot's operation (a fetch starting now joins
        // it). If it cannot produce a live read, performShared escalates any joined
        // fetcher to one real episode instead of handing it the probe's dead end.
        guard let result = try? performShared(.wakeProbe,
                                              handshakeTimeout: handshakeTimeout,
                                              identityTimeout: CodexAppServerClient.identityTimeout,
                                              quotaTimeout: quotaTimeout),
              result.isLive else {
            return .needsFullRefresh
        }
        return .refreshed(result)
    }

    private func isStopped() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    // MARK: - Single-flight plumbing

    /// Joins the running operation or becomes its runner. Every caller leaves with an
    /// actual result: the running operation's, the queued follow-up's, or its own.
    private func performShared(_ kind: OperationKind,
                               handshakeTimeout: TimeInterval,
                               identityTimeout: TimeInterval,
                               quotaTimeout: TimeInterval) throws -> FetchResult {
        lock.lock()
        if stopped {
            lock.unlock()
            throw UsageError.rpcFailed(.shutdown)
        }
        if operationRunning {
            let box = joinLocked(kind: kind)
            lock.unlock()
            return try box.wait().get()
        }
        operationRunning = true
        operationThread = Thread.current
        lock.unlock()

        // The runner loop. Claiming a queued follow-up keeps `operationRunning` true, so
        // no new caller can slip in between operations; releasing the slot happens in the
        // same critical section as the final delivery, so a caller arriving in between
        // either joins a live operation or becomes the next runner — never a waiter with
        // nobody left to wake it.
        var currentKind = kind
        var outcome: Result<FetchResult, Error>?
        var runFollowUp = false
        repeat {
            outcome = executeOperation(currentKind,
                                       handshakeTimeout: handshakeTimeout,
                                       identityTimeout: identityTimeout,
                                       quotaTimeout: quotaTimeout)
            lock.lock()
            var runAgain = false
            if case .wakeProbe = currentKind,
               !isLiveOutcome(outcome!), !waiters.isEmpty, !stopped {
                // A fetcher joined a wake probe that could not produce a live read. Do
                // not hand it the probe's dead end: its boxes stay queued and this same
                // runner immediately runs one real episode for it.
                currentKind = .full(resetFailureBudget: false)
                runFollowUp = true
                runAgain = true
            }
            if !runAgain {
                deliver(outcome!, to: &waiters)
                if !stopped, isManualFollowUpQueuedLocked() {
                    // Exactly one follow-up: the queued manual callers become the waiters of
                    // the next, budget-resetting fetch, which this thread runs immediately.
                    followUpQueued = false
                    waiters = followUpWaiters
                    followUpWaiters = []
                    currentKind = .full(resetFailureBudget: true)
                    runFollowUp = true
                } else {
                    // Not stopped here means no follow-up was ever queued; stopped means the
                    // waiters were already released by stop() and this is the trailing sweep.
                    deliver(Result<FetchResult, Error>.failure(UsageError.rpcFailed(.shutdown)), to: &followUpWaiters)
                    followUpQueued = false
                    operationRunning = false
                    operationThread = nil
                    runFollowUp = false
                }
            }
            lock.unlock()
            if !runFollowUp { operationFinished.signal() }
        } while runFollowUp
        return try outcome!.get()
    }

    private func isLiveOutcome(_ outcome: Result<FetchResult, Error>) -> Bool {
        if case .success(let result) = outcome, result.isLive { return true }
        return false
    }

    /// Registers the caller under the lock. Manual callers queue the single follow-up and
    /// wait for its result; everyone else waits for the running operation's actual result.
    private func joinLocked(kind: OperationKind) -> WaiterBox {
        if case .full(true) = kind {
            followUpQueued = true
            let box = WaiterBox()
            followUpWaiters.append(box)
            return box
        }
        let box = WaiterBox()
        waiters.append(box)
        return box
    }

    private func isManualFollowUpQueuedLocked() -> Bool {
        followUpQueued && !followUpWaiters.isEmpty
    }

    private func deliver(_ outcome: Result<FetchResult, Error>, to boxes: inout [WaiterBox]) {
        for box in boxes { box.fulfill(outcome) }
        boxes.removeAll()
    }

    // MARK: - Operation execution

    /// Runs one operation to completion: the gate check, the episode (attempt plus one
    /// immediate retry) and the retry-ladder bookkeeping.
    private func executeOperation(_ kind: OperationKind,
                                  handshakeTimeout: TimeInterval,
                                  identityTimeout: TimeInterval,
                                  quotaTimeout: TimeInterval) -> Result<FetchResult, Error> {
        switch kind {
        case .full(let resetFailureBudget):
            if resetFailureBudget {
                resetRetryState()
            } else {
                do {
                    if let gated = try gateOutcome() { return .success(gated) }
                } catch {
                    return .failure(error)
                }
            }
            return runEpisode(readsIdentity: true,
                              resetFailureBudget: resetFailureBudget,
                              handshakeTimeout: handshakeTimeout,
                              identityTimeout: identityTimeout,
                              quotaTimeout: quotaTimeout)
        case .rateLimitsOnly(let resetFailureBudget):
            if resetFailureBudget {
                resetRetryState()
            } else {
                do {
                    if let gated = try gateOutcome() { return .success(gated) }
                } catch {
                    return .failure(error)
                }
            }
            return runEpisode(readsIdentity: false,
                              resetFailureBudget: resetFailureBudget,
                              handshakeTimeout: handshakeTimeout,
                              identityTimeout: identityTimeout,
                              quotaTimeout: quotaTimeout)
        case .wakeProbe:
            return runWakeProbeRead(handshakeTimeout: handshakeTimeout,
                                    quotaTimeout: quotaTimeout)
        }
    }

    /// The wake probe's light read: the existing healthy child only, no launch, no
    /// episode, no ladder touch. Runs while holding the shared slot, so closing a dead
    /// child here can never pull the connection out from under a concurrent fetch —
    /// any fetch that started meanwhile joined this operation instead.
    private func runWakeProbeRead(handshakeTimeout: TimeInterval,
                                  quotaTimeout: TimeInterval) -> Result<FetchResult, Error> {
        lock.lock()
        let existing = client
        let healthy = !stopped && existing != nil && existing!.isTransportRunning
        lock.unlock()
        guard healthy, let existing else {
            return .failure(UsageError.appServerStartupFailed(.launchFailed))
        }
        do {
            try existing.handshake(timeout: handshakeTimeout)
            if isStopped() { return .failure(UsageError.rpcFailed(.shutdown)) }
            let startedAt = clock()
            let snapshot = try existing.readRateLimits(timeout: quotaTimeout)
            if isStopped() { return .failure(UsageError.rpcFailed(.shutdown)) }
            persistConfirmationSnapshot(snapshot)
            setConnectionState(.connected)
            return .success(FetchResult(snapshot: snapshot, isLive: true, error: nil, account: nil,
                                        readStartedAt: startedAt, connectionEpoch: currentConnectionEpoch))
        } catch {
            if isStopped() { return .failure(UsageError.rpcFailed(.shutdown)) }
            setConnectionState(.disconnected)
            closeClient()
            return .failure(Self.asUsageError(error))
        }
    }

    /// What an automatic caller receives while the backoff gate or the manual-retry
    /// requirement is active. Not the busy path — the single-flight busy path waits for the
    /// actual result. This is deliberate backoff policy:
    /// - with cache, the cached snapshot is served marked not-live,
    /// - without cache, the recorded failure is re-raised so the caller sees the real
    ///   error instead of fabricated data,
    /// - `nil` means no gate is active and the operation should run.
    private func gateOutcome() throws -> FetchResult? {
        lock.lock()
        let gateApplies = manualRetryRequired || !CodexRetryPolicy.isAutomaticAttemptDue(nextRetryAt: nextAutomaticRetryAt, now: clock())
        lock.unlock()
        guard gateApplies else { return nil }
        // Cache and error lookups run unlocked: they take their own locks, and this lock
        // is not re-entrant.
        let recordedError = currentRecordedError()
        if let cached = servedCachedSnapshot() {
            return FetchResult(snapshot: cached, isLive: false, error: recordedError, account: nil)
        }
        throw recordedError
    }

    private func currentRecordedError() -> UsageError {
        lock.lock(); defer { lock.unlock() }
        return lastError ?? .rpcFailed(.other)
    }

    private func resetRetryState() {
        lock.lock()
        failedEpisodes = 0
        nextAutomaticRetryAt = nil
        manualRetryRequired = false
        lock.unlock()
    }

    /// One episode: at most `1 + immediateRetryCount` attempts, every failure kind flowing
    /// through the same bounded recovery. `readsIdentity == false` is the confirmation
    /// path, which must never attribute cache entries to an account it never resolved.
    private func runEpisode(readsIdentity: Bool,
                            resetFailureBudget: Bool,
                            handshakeTimeout: TimeInterval,
                            identityTimeout: TimeInterval,
                            quotaTimeout: TimeInterval) -> Result<FetchResult, Error> {
        lock.lock()
        let generationAtStart = generation
        lock.unlock()

        var attemptsLeft = 1 + CodexRetryPolicy.immediateRetryCount
        while true {
            if isStale(generationAtStart) { return .failure(UsageError.rpcFailed(.shutdown)) }
            setConnectionState(.connecting)

            let client: CodexAppServerProviding
            do {
                client = try acquireClient(generationAtStart: generationAtStart)
            } catch {
                if isStale(generationAtStart) { return .failure(UsageError.rpcFailed(.shutdown)) }
                let usageError = Self.asUsageError(error)
                setConnectionState(.disconnected)
                attemptsLeft -= 1
                if attemptsLeft > 0, CodexRetryPolicy.isAutoRetryable(usageError) {
                    pauseBeforeRestart()
                    continue
                }
                recordEpisodeFailure(usageError)
                return finishEpisodeFailure(usageError,
                                            readsIdentity: readsIdentity,
                                            generationAtStart: generationAtStart)
            }

            do {
                try client.handshake(timeout: handshakeTimeout)
                if isStale(generationAtStart) { return .failure(UsageError.rpcFailed(.shutdown)) }

                var account: CodexAccount?
                if readsIdentity {
                    account = readAccountBestEffort(from: client, timeout: identityTimeout)
                    if isStale(generationAtStart) { return .failure(UsageError.rpcFailed(.shutdown)) }
                }

                let readStartedAt = clock()
                let snapshot = try client.readRateLimits(timeout: quotaTimeout)
                if isStale(generationAtStart) { return .failure(UsageError.rpcFailed(.shutdown)) }

                setConnectionState(.connected)
                if readsIdentity {
                    persistSnapshot(snapshot, account: account)
                } else {
                    persistConfirmationSnapshot(snapshot)
                }
                recordEpisodeSuccess()
                let result = FetchResult(snapshot: snapshot, isLive: true, error: nil, account: account,
                                         readStartedAt: readStartedAt, connectionEpoch: currentConnectionEpoch)
                logFetchOutcome(result)
                return .success(result)
            } catch {
                if isStale(generationAtStart) { return .failure(UsageError.rpcFailed(.shutdown)) }
                let usageError = Self.asUsageError(error)
                setConnectionState(.disconnected)
                closeClient()

                attemptsLeft -= 1
                if attemptsLeft > 0, CodexRetryPolicy.isAutoRetryable(usageError) {
                    pauseBeforeRestart()
                    continue
                }
                recordEpisodeFailure(usageError)
                return finishEpisodeFailure(usageError,
                                            readsIdentity: readsIdentity,
                                            generationAtStart: generationAtStart)
            }
        }
    }

    /// Advances the retry ladder after a failed episode and returns the outcome the
    /// caller sees: the cached snapshot marked not-live when one exists, otherwise the
    /// error itself. Shutdown always surfaces and never hides behind cache.
    private func finishEpisodeFailure(_ error: UsageError,
                                      readsIdentity: Bool,
                                      generationAtStart: Int) -> Result<FetchResult, Error> {
        logFetchFailure(error)
        if error.isShutdown { return .failure(error) }
        // servedCachedSnapshot takes its own locks; never call it holding this lock.
        if let cached = servedCachedSnapshot() {
            return .success(FetchResult(snapshot: cached, isLive: false, error: error, account: nil))
        }
        return .failure(error)
    }

    private func recordEpisodeSuccess() {
        lock.lock()
        lastError = nil
        failedEpisodes = 0
        nextAutomaticRetryAt = nil
        manualRetryRequired = false
        lock.unlock()
    }

    private func recordEpisodeFailure(_ error: UsageError) {
        lock.lock()
        lastError = error
        if error.isShutdown { lock.unlock(); return }
        if CodexRetryPolicy.isAutoRetryable(error) {
            failedEpisodes += 1
            nextAutomaticRetryAt = CodexRetryPolicy.nextAutomaticRetry(now: clock(),
                                                                      failedEpisodes: failedEpisodes)
        } else {
            // Missing CLI or signed-out cannot be fixed by relaunching: stop the loop
            // until the user explicitly retries.
            manualRetryRequired = true
            nextAutomaticRetryAt = nil
        }
        lock.unlock()
    }

    private func logFetchOutcome(_ result: FetchResult) {
        Diagnostics.log("fetch ok windows=5h:\(result.snapshot.fiveHour != nil)/weekly:\(result.snapshot.weekly != nil) account:\(result.account?.debugSummary ?? "unavailable")")
    }

    private func logFetchFailure(_ error: UsageError) {
        Diagnostics.log("fetch failed: \(error.debugSummary)")
    }

    private func setConnectionState(_ newState: ConnectionState) {
        lock.lock(); state = newState; lock.unlock()
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

    /// Persists a confirmation-only snapshot under the already-known attribution, so the
    /// card can show the newly observed window. Never touches `lastAccount` and never
    /// migrates: with no identity resolved, a new attribution bucket must not be created.
    private func persistConfirmationSnapshot(_ snapshot: UsageSnapshot) {
        let accountID = currentAccountID
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
        // A freshly published child is a new connection: identity observed under the
        // previous epoch must not be carried across it.
        connectionEpoch += 1
        lock.unlock()
        Diagnostics.log("app-server child started pid \(created.childProcessIdentifier)")
        return created
    }

    /// Stops the owned child, releases every waiter with a shutdown error, and refuses
    /// further launches until `resume()`.
    ///
    /// Draining (Round 3 blocker 2): returns only after the running operation has finished
    /// and any child it launched has been stopped and reaped, bounded by `shutdownTimeout`.
    /// Waiters never stay blocked across a stop: their boxes are fulfilled with the
    /// shutdown error first, so cancellation is observable by every caller. Safe to call
    /// concurrently with an operation, during a start, and more than once.
    public func stop(shutdownTimeout: TimeInterval = 8.0) {
        let victims: [CodexAppServerProviding]
        lock.lock()
        generation += 1
        stopped = true
        state = .idle
        var found: [CodexAppServerProviding] = []
        if let client { found.append(client); self.client = nil }
        if let startingClient { found.append(startingClient); self.startingClient = nil }
        let wasRunning = operationRunning
        let operationOwner = operationThread
        // Release every waiter now; the runner's own outcome can no longer reach them.
        let shutdownOutcome = Result<FetchResult, Error>.failure(UsageError.rpcFailed(.shutdown))
        deliver(shutdownOutcome, to: &waiters)
        deliver(shutdownOutcome, to: &followUpWaiters)
        followUpQueued = false
        victims = found
        lock.unlock()
        for victim in victims { victim.stop() }

        // Wait, bounded, for the running operation to exit. An operation running on the
        // calling thread cannot be waited for here (that would self-deadlock).
        if wasRunning, operationOwner !== Thread.current {
            let deadline = Date().addingTimeInterval(shutdownTimeout)
            while Date() < deadline {
                lock.lock(); let busy = operationRunning; lock.unlock()
                if !busy { break }
                _ = operationFinished.wait(timeout: .now() + 0.05)
            }
            // A child launched between the first sweep and the operation exiting.
            lock.lock()
            let late = [client, startingClient].compactMap { $0 }
            self.client = nil
            self.startingClient = nil
            lock.unlock()
            for child in late { child.stop() }
        }
        Diagnostics.log("service stopped (generation \(generation), drained=\(wasRunning ? "yes" : "no"))")
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

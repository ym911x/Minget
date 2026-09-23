import XCTest
@testable import UsageMonitorCore

/// Stub used to exercise service policy without launching children.
final class StubClient: CodexAppServerProviding {
    var startCalls = 0
    var stopCalls = 0
    var handshakeCalls = 0
    var accountReadCalls = 0
    var startError: UsageError?
    var readErrors: [UsageError] = []
    var readResults: [UsageSnapshot] = []
    /// When set, every read fails with it (models a persistent outage).
    var persistentError: UsageError?
    var isTransportRunning = true
    /// Identity the stub reports for `account/read`.
    var account: CodexAccount?

    func start() throws {
        startCalls += 1
        if let startError { throw startError }
    }

    func handshake(timeout: TimeInterval) throws {
        handshakeCalls += 1
    }

    func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
        if let persistentError { throw persistentError }
        if !readErrors.isEmpty { throw readErrors.removeFirst() }
        if let result = readResults.first { return result }
        throw UsageError.rpcFailed(.other)
    }

    func readAccount(timeout: TimeInterval) throws -> CodexAccount? {
        accountReadCalls += 1
        return account
    }

    func stop() {
        stopCalls += 1
        isTransportRunning = false
    }
}

final class UsageServiceTests: XCTestCase {
    let fiveHour = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 25,
                                   remainingPercent: 75, resetsAt: Date(timeIntervalSince1970: 1_788_935_373))
    let weekly = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 58,
                                 remainingPercent: 42, resetsAt: Date(timeIntervalSince1970: 1_789_453_767))

    func snapshot() -> UsageSnapshot {
        UsageSnapshot(fiveHour: fiveHour, weekly: weekly,
                      fetchedAt: Date(timeIntervalSince1970: 1_788_935_000), source: .codexAppServer)
    }

    func makeUserDefaults() -> UserDefaults {
        let suite = "UsageMonitorTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: Happy path + cache

    func testSuccessfulFetchSavesCacheAndReturnsLiveSnapshot() throws {
        let defaults = makeUserDefaults()
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: defaults))

        let result = try service.fetch()
        XCTAssertTrue(result.isLive)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.snapshot.fiveHour?.remainingPercent, 75)
        XCTAssertEqual(service.connectionState, .connected)

        let cached = UsageCache(userDefaults: defaults).load()
        XCTAssertEqual(cached?.fiveHour?.usedPercent, 25)
        XCTAssertEqual(cached?.source, .cached)
        XCTAssertEqual(stub.startCalls, 1, "the same client must be reused across fetches")
    }

    func testSplitTimeoutsArePassedPerCall() throws {
        let stub = TimeoutRecordingStub()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()))

        _ = try service.fetch()
        XCTAssertEqual(stub.handshakeTimeouts, [CodexAppServerClient.handshakeTimeout], "handshake budget is 5 s")
        XCTAssertEqual(stub.identityTimeouts, [CodexAppServerClient.identityTimeout], "identity budget is 3 s")
        XCTAssertEqual(stub.quotaTimeouts, [CodexAppServerClient.quotaTimeout], "quota budget is 15 s")

        stub.reset()
        _ = try service.fetchRateLimitsOnly()
        XCTAssertEqual(stub.handshakeTimeouts, [CodexAppServerClient.handshakeTimeout])
        XCTAssertTrue(stub.identityTimeouts.isEmpty, "the confirmation path must not read identity at all")
        XCTAssertEqual(stub.quotaTimeouts, [CodexAppServerClient.quotaTimeout])
    }

    /// Records the per-call budgets the service hands to the transport.
    final class TimeoutRecordingStub: CodexAppServerProviding {
        private(set) var handshakeTimeouts: [TimeInterval] = []
        private(set) var identityTimeouts: [TimeInterval] = []
        private(set) var quotaTimeouts: [TimeInterval] = []
        var readResults: [UsageSnapshot] = []
        var isTransportRunning = true

        func reset() {
            handshakeTimeouts.removeAll()
            identityTimeouts.removeAll()
            quotaTimeouts.removeAll()
        }

        func start() throws {}
        func handshake(timeout: TimeInterval) throws { handshakeTimeouts.append(timeout) }
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            quotaTimeouts.append(timeout)
            if let result = readResults.first { return result }
            throw UsageError.rpcFailed(.other)
        }
        func readAccount(timeout: TimeInterval) throws -> CodexAccount? {
            identityTimeouts.append(timeout)
            return nil
        }
        func stop() {}
    }

    // MARK: 1.3.2 wake probe, 1.4.2 join semantics

    func testWakeProbeUsesOnlyTheExistingClientAndSkipsIdentity() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub },
                                   cache: UsageCache(userDefaults: makeUserDefaults()))
        _ = try service.fetch()
        let accountReadsBefore = stub.accountReadCalls
        let startsBefore = stub.startCalls

        switch service.probeRateLimitsAfterWake() {
        case .refreshed(let result):
            XCTAssertTrue(result.isLive)
            XCTAssertEqual(result.snapshot.fiveHour?.remainingPercent, 75)
        default:
            XCTFail("a healthy running client should satisfy the wake probe")
        }
        XCTAssertEqual(stub.startCalls, startsBefore, "the probe must not start a child")
        XCTAssertEqual(stub.accountReadCalls, accountReadsBefore, "the probe must not read identity")
        XCTAssertEqual(stub.handshakeCalls, 2)
    }

    func testFailedWakeProbeClosesClientWithoutTouchingTheLadder() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub },
                                   cache: UsageCache(userDefaults: makeUserDefaults()))
        _ = try service.fetch()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))

        if case .needsFullRefresh = service.probeRateLimitsAfterWake() {
            // expected
        } else {
            XCTFail("a failed probe must request an ordinary full refresh")
        }
        XCTAssertEqual(stub.startCalls, 1, "the probe itself cannot relaunch")
        XCTAssertEqual(stub.stopCalls, 1)
        XCTAssertFalse(service.isRetryBackoffActive, "the probe never opens a retry episode")
        XCTAssertFalse(service.isManualRetryRequired)
    }

    func testWakeProbeIsSuppressedByBackoffGateAndStop() {
        let failing = StubClient()
        failing.persistentError = .rpcFailed(.other)
        let service = UsageService(factory: { failing },
                                   cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0)
        _ = try? service.fetch()
        let starts = failing.startCalls
        XCTAssertTrue(service.isRetryBackoffActive, "a failed episode sets the automatic gate")
        if case .suppressed = service.probeRateLimitsAfterWake() {} else {
            XCTFail("an active backoff gate must suppress wake work")
        }
        XCTAssertEqual(failing.startCalls, starts)

        service.stop()
        if case .suppressed = service.probeRateLimitsAfterWake() {} else {
            XCTFail("a stopped service must suppress wake work")
        }
        XCTAssertEqual(failing.startCalls, starts)
    }

    func testWakeProbeJoinsRunningFetchAndReceivesItsActualResult() {
        let stub = BlockingStub()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()))

        let gate = DispatchSemaphore(value: 0)
        stub.onRead = { gate.wait() }   // blocks the first read until the probe has joined

        let fetchDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? service.fetch()
            fetchDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)   // the runner is now blocked inside its read

        var probeResult: UsageService.WakeProbeResult?
        let probeDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            probeResult = service.probeRateLimitsAfterWake()
            probeDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)
        gate.signal()

        XCTAssertEqual(probeDone.wait(timeout: .now() + 5), .success, "the probe must join, not race or hang")
        guard case .refreshed(let result)? = probeResult else {
            return XCTFail("the probe must receive the running fetch's actual live result")
        }
        XCTAssertTrue(result.isLive)
        XCTAssertEqual(fetchDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(stub.readCalls, 1, "the probe joins the in-flight read instead of issuing its own")
    }

    /// 1.4.2 independent review: the wake probe must occupy the single-flight slot, so a
    /// fetch that starts while it runs joins it instead of racing it on the same child.
    func testFetchJoiningARunningWakeProbeReceivesItsActualResult() throws {
        let stub = BlockingStub()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub },
                                   cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0)

        let gate = DispatchSemaphore(value: 0)
        stub.onRead = { gate.wait() }   // the probe's read wedges while it holds the slot

        let probeDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = service.probeRateLimitsAfterWake()
            probeDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)   // the probe now occupies the slot

        let fetchDone = DispatchSemaphore(value: 0)
        var fetchOutcome: Result<UsageService.FetchResult, Error>?
        DispatchQueue.global().async {
            fetchOutcome = Result { try service.fetch() }
            fetchDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)
        gate.signal()

        XCTAssertEqual(fetchDone.wait(timeout: .now() + 5), .success,
                       "the fetch must join the probe, not race it")
        XCTAssertTrue(try fetchOutcome!.get().isLive,
                      "the joined fetch receives the probe's actual live result")
        XCTAssertEqual(stub.readCalls, 1, "the join must not start a second read")
    }

    /// 1.4.2 independent review: a fetch that joined a probe which cannot read live gets
    /// one real episode run for it — it must not be handed the probe's dead end.
    func testFetchJoiningAFailingWakeProbeRunsARealEpisodeForIt() throws {
        let stub = BlockingStub()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub },
                                   cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0)

        let failGate = DispatchSemaphore(value: 0)
        stub.onRead = {
            if stub.readCalls == 1 {
                failGate.wait()   // the probe's read wedges, then fails
                throw UsageError.rpcFailed(.timedOut(method: "account/rateLimits/read"))
            }
            // The escalated episode's read succeeds normally.
        }

        let probeDone = DispatchSemaphore(value: 0)
        var probeResult: UsageService.WakeProbeResult?
        DispatchQueue.global().async {
            probeResult = service.probeRateLimitsAfterWake()
            probeDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)

        let fetchDone = DispatchSemaphore(value: 0)
        var fetchOutcome: Result<UsageService.FetchResult, Error>?
        DispatchQueue.global().async {
            fetchOutcome = Result { try service.fetch() }
            fetchDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)
        failGate.signal()   // the probe's read fails; the runner escalates to a real episode

        XCTAssertEqual(probeDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(fetchDone.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(try fetchOutcome!.get().isLive,
                      "the joined fetcher must receive a real episode's live result, not the probe failure")
        XCTAssertEqual(stub.readCalls, 2, "the probe's failed read plus the escalated episode")
    }

    /// 1.4.2 fire barrier: a live read records when it started, a cache-served result
    /// carries no timestamp at all.
    func testLiveResultsCarryReadStartedAtAndCacheServedResultsDoNot() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub },
                                   cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0)

        let live = try service.fetch()
        let startedAt = try XCTUnwrap(live.readStartedAt,
                                      "a live read records when it started, for the fire barrier")
        XCTAssertLessThanOrEqual(startedAt, Date())

        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let cached = try service.fetch()   // failed episode serves the cache
        XCTAssertFalse(cached.isLive)
        XCTAssertNil(cached.readStartedAt, "a cache-served result carries no read timestamp")
    }

    // MARK: Test 9 — RPC timeout keeps the cache

    func testTimeoutRetainsCachedSnapshotAndMarksItStale() throws {
        let defaults = makeUserDefaults()
        let cache = UsageCache(userDefaults: defaults)
        let good = StubClient()
        good.readResults = [snapshot()]
        let first = UsageService(factory: { good }, cache: cache)
        let live = try first.fetch()
        XCTAssertTrue(live.isLive)

        let failing = StubClient()
        failing.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let second = UsageService(factory: { failing }, cache: cache, restartDelay: 0)
        let result = try second.fetch()

        XCTAssertFalse(result.isLive, "a timed-out fetch must not be presented as live data")
        XCTAssertEqual(result.error, .rpcFailed(.timedOut(method: "account/rateLimits/read")))
        XCTAssertEqual(result.snapshot.fiveHour?.remainingPercent, 75, "cached numbers survive the failure")
        XCTAssertEqual(result.snapshot.source, .cached)
        XCTAssertEqual(result.snapshot.fetchedAt, live.snapshot.fetchedAt, "fetchedAt keeps the last successful time")
    }

    func testTimeoutWithoutCacheThrowsInsteadOfFabricatingData() {
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)
        XCTAssertThrowsError(try service.fetch()) { error in
            XCTAssertEqual(error as? UsageError, .rpcFailed(.timedOut(method: "account/rateLimits/read")))
        }
    }

    // MARK: 1.4.2 — bounded retry ladder (replaces the 1.3.x permanent freeze)

    func testFailedEpisodeRetriesImmediatelyOnceThenOpensTheGate() {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0, clock: { now })

        _ = try? service.fetch()
        XCTAssertEqual(stub.startCalls, 2, "one attempt plus exactly one immediate retry")
        XCTAssertTrue(service.isRetryBackoffActive)
        XCTAssertEqual(service.automaticRetryGate?.timeIntervalSince(now) ?? -1, 30,
                       "the first failed episode waits 30 seconds")
    }

    func testBackoffGateServesCacheWithoutLaunching() throws {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let defaults = makeUserDefaults()
        let cache = UsageCache(userDefaults: defaults)
        cache.save(snapshot())
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: cache, restartDelay: 0, clock: { now })

        _ = try? service.fetch()          // opens the gate: attempt + retry
        XCTAssertEqual(stub.startCalls, 2)
        let served = try service.fetch()  // automatic, gate active
        XCTAssertEqual(stub.startCalls, 2, "no additional child may be launched while gated")
        XCTAssertFalse(served.isLive)
        XCTAssertEqual(served.snapshot.source, .cached)
        XCTAssertEqual(served.snapshot.fiveHour?.remainingPercent, 75)
    }

    func testBackoffGateWithoutCacheReReportsTheRecordedFailure() {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0, clock: { now })

        _ = try? service.fetch()
        XCTAssertEqual(stub.startCalls, 2)
        XCTAssertThrowsError(try service.fetch()) { error in
            XCTAssertEqual(error as? UsageError, .rpcFailed(.timedOut(method: "account/rateLimits/read")),
                           "no cache exists, so the gate re-reports the recorded failure")
        }
        XCTAssertEqual(stub.startCalls, 2, "the gate must not launch anything")
    }

    /// The 1.4.2 replacement for the removed permanent-freeze assertion: time *does* reopen
    /// the ladder automatically, one step at a time, capped at 300 seconds.
    func testBackoffLadderAdvances30_60_120_ThenCapsAt300() {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0, clock: { now })

        let expectedSteps: [TimeInterval] = [30, 60, 120, 300, 300]
        for (index, step) in expectedSteps.enumerated() {
            now = now.addingTimeInterval(step)   // the gate has elapsed
            _ = try? service.fetch()
            XCTAssertEqual(stub.startCalls, 2 * (index + 1),
                           "episode \(index + 1) must run one attempt plus one immediate retry")
            XCTAssertEqual(service.automaticRetryGate?.timeIntervalSince(now) ?? -1, step,
                           "after \(index + 1) failed episodes the next gate is \(step) s")
        }
        XCTAssertTrue(service.isRetryBackoffActive, "the cap keeps the gate set, still bounded at 300 s")
    }

    func testSuccessResetsTheLadder() throws {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0, clock: { now })

        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        _ = try? service.fetch()
        XCTAssertTrue(service.isRetryBackoffActive)

        stub.persistentError = nil
        now = now.addingTimeInterval(30)
        let recovered = try service.fetch()
        XCTAssertTrue(recovered.isLive)
        XCTAssertFalse(service.isRetryBackoffActive, "a success clears the gate")
        XCTAssertNil(service.automaticRetryGate)

        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        _ = try? service.fetch()
        XCTAssertEqual(service.automaticRetryGate?.timeIntervalSince(now) ?? -1, 30,
                       "a success resets the ladder: the next failure waits the first step again")
    }

    func testManualRetryBypassesTheBackoffGate() throws {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0, clock: { now })

        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        _ = try? service.fetch()
        XCTAssertEqual(stub.startCalls, 2)
        XCTAssertTrue(service.isRetryBackoffActive)

        stub.persistentError = nil
        let manual = try service.fetch(resetFailureBudget: true)   // gate is active here
        XCTAssertTrue(manual.isLive, "the manual retry bypasses the gate entirely")
        XCTAssertFalse(service.isRetryBackoffActive)
    }

    func testManualRetryReopensExactlyOneEpisode() {
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        for _ in 0..<2 { _ = try? service.fetch() }
        XCTAssertEqual(stub.startCalls, 2, "the second automatic fetch is gated: no new launches")

        // Explicit user retry: a fresh episode with one attempt plus one restart.
        _ = try? service.fetch(resetFailureBudget: true)
        XCTAssertEqual(stub.startCalls, 4, "manual retry re-opens one attempt plus one restart")
    }

    // MARK: Non-restartable failures never loop

    func testNonRestartableErrorsRequireManualRetryInsteadOfRetrying() {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let stub = StubClient()
        stub.startError = .codexNotSignedIn
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0, clock: { now })
        XCTAssertThrowsError(try service.fetch()) { error in
            XCTAssertEqual(error as? UsageError, .codexNotSignedIn)
        }
        XCTAssertEqual(stub.startCalls, 1, "a missing sign-in cannot be fixed by relaunching")
        XCTAssertTrue(service.isManualRetryRequired)
        XCTAssertFalse(service.isRetryBackoffActive, "no time-based retry is scheduled for this kind")
        XCTAssertNil(service.automaticRetryGate)

        for _ in 0..<3 {
            now = now.addingTimeInterval(600)   // far past any backoff step
            XCTAssertThrowsError(try service.fetch())
        }
        XCTAssertEqual(stub.startCalls, 1, "the automatic loop must stay off; only a manual retry may run")
    }

    func testManualRetryClearsTheManualRequirement() throws {
        let stub = StubClient()
        stub.startError = .codexNotSignedIn
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)
        _ = try? service.fetch()
        XCTAssertTrue(service.isManualRetryRequired)

        stub.startError = nil
        stub.readResults = [snapshot()]
        let manual = try service.fetch(resetFailureBudget: true)
        XCTAssertTrue(manual.isLive)
        XCTAssertFalse(service.isManualRetryRequired, "the explicit retry re-enables the automatic loop")

        stub.startError = .codexNotSignedIn
        // The healthy child from the manual retry is still running: the automatic loop
        // reuses it and never calls start() again, so the new startError cannot bite.
        let automatic = try service.fetch()
        XCTAssertTrue(automatic.isLive, "the recovered automatic loop runs normally")
        XCTAssertEqual(stub.startCalls, 2, "a healthy child is reused; start errors only bite on relaunch")
    }

    func testStartThrowIsBoundedAcrossScheduledFetches() {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let stub = StubClient()
        stub.startError = .appServerStartupFailed(.launchFailed)
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0, clock: { now })

        for _ in 0..<3 { _ = try? service.fetch() }
        XCTAssertEqual(stub.startCalls, 2,
                       "a start() failure runs one attempt plus one immediate retry, then the gate holds")
        XCTAssertTrue(service.isRetryBackoffActive)

        now = now.addingTimeInterval(30)
        for _ in 0..<3 { _ = try? service.fetch() }
        XCTAssertEqual(stub.startCalls, 4, "after the gate elapses exactly one more episode runs")
    }

    func testFactoryThrowEntersManualRetryRequirement() {
        var factoryCalls = 0
        let service = UsageService(
            factory: { _ = factoryCalls; factoryCalls += 1
                throw UsageError.codexCLINotFound(searchedPaths: ["/Applications/ChatGPT.app/Contents/Resources/codex"]) },
            cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0
        )
        for _ in 0..<3 { _ = try? service.fetch() }
        XCTAssertEqual(factoryCalls, 1,
                       "a missing CLI cannot be fixed by repeating the launch; the loop stops")
        XCTAssertTrue(service.isManualRetryRequired)
        XCTAssertTrue(service.lastFailureSummary?.contains("codexCLINotFound") ?? false)
    }

    // MARK: Round 2 blocker 3 — stop/start races

    /// Fixture whose start() blocks until the test releases it, reproducing a slow launch.
    final class SlowStartClient: CodexAppServerProviding {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        private let stateLock = NSLock()
        private var runningState = false
        var stopCalls = 0

        var isTransportRunning: Bool { stateLock.withLock { runningState } }
        func start() throws {
            entered.signal()
            release.wait()
            stateLock.withLock { runningState = true }
        }
        func handshake(timeout: TimeInterval) throws {}
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            UsageSnapshot(fiveHour: nil, weekly: nil, fetchedAt: Date(), source: .codexAppServer)
        }
        func stop() {
            stopCalls += 1
            stateLock.withLock { runningState = false }
        }
    }

    func testStopDuringStartLeavesNoRunningClient() throws {
        let slow = SlowStartClient()
        let service = UsageService(factory: { slow }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        let fetchDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? service.fetch()
            fetchDone.signal()
        }

        XCTAssertEqual(slow.entered.wait(timeout: .now() + 5), .success, "start() was never entered")
        // Stop while start() is still blocked. The drain cannot finish until the fixture
        // releases, so give it a short bounded window: the assertion that matters is that
        // the late client is stopped once the start does finish.
        service.stop(shutdownTimeout: 0.5)
        slow.release.signal()        // let the late start finish
        XCTAssertEqual(fetchDone.wait(timeout: .now() + 5), .success)

        XCTAssertFalse(slow.isTransportRunning, "a client started after stop must not remain running")
        XCTAssertGreaterThanOrEqual(slow.stopCalls, 1, "the late child must be stopped")
        service.stop()               // a second stop stays safe
        XCTAssertFalse(slow.isTransportRunning)
    }

    func testStopDuringRestartDelayPreventsLateRestart() {
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0.4)

        let fetchDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? service.fetch()
            fetchDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.1)  // first attempt failed, restart delay is running
        service.stop()
        XCTAssertEqual(fetchDone.wait(timeout: .now() + 5), .success)
        XCTAssertLessThanOrEqual(stub.startCalls, 1, "no child may be launched after stop()")
        service.stop()
    }

    func testFetchAfterStopThrowsShutdownWithoutLaunchingAChild() {
        let stub = StubClient()
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)
        service.stop()
        XCTAssertThrowsError(try service.fetch()) { error in
            XCTAssertEqual(error as? UsageError, .rpcFailed(.shutdown))
        }
        XCTAssertEqual(stub.startCalls, 0, "no child may be launched after stop()")
    }

    func testResumeAllowsFetchingAgain() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)
        service.stop()
        service.resume()
        let result = try service.fetch()
        XCTAssertTrue(result.isLive)
    }

    func testStopIsIdempotent() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)
        _ = try service.fetch()   // a client now exists
        service.stop()
        service.stop()
        service.stop()
        XCTAssertEqual(stub.stopCalls, 1)
    }

    /// A failing child whose failure arrives after stop(): the fetch must not restart it.
    func testShutdownDuringFetchIsNotRetried() {
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0.2)
        let fetchDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? service.fetch()
            fetchDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)
        service.stop()
        XCTAssertEqual(fetchDone.wait(timeout: .now() + 5), .success)
        XCTAssertLessThanOrEqual(stub.startCalls, 2,
                                 "shutdown must never add restarts beyond the in-flight episode")
        service.stop()
    }

    // MARK: Error states A-F

    func testMissingCLIDoesNotRestartAndIsReported() {
        var startCalls = 0
        let service = UsageService(
            factory: { _ = startCalls; startCalls += 1
                throw UsageError.codexCLINotFound(searchedPaths: ["/Applications/ChatGPT.app/Contents/Resources/codex"]) },
            cache: UsageCache(userDefaults: makeUserDefaults())
        )
        XCTAssertThrowsError(try service.fetch()) { error in
            guard case UsageError.codexCLINotFound = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertEqual(startCalls, 1, "a missing CLI cannot be fixed by restarting")
        XCTAssertEqual(service.connectionState, .disconnected)
        // The logged summary stays categorical and lists no local paths.
        XCTAssertNil(service.lastFailureSummary?.first(where: { $0 == "/" }))
    }

    func testMissingWindowIsReportedWithoutRestart() {
        let stub = StubClient()
        stub.readResults = [UsageSnapshot(fiveHour: nil, weekly: weekly, fetchedAt: Date(), source: .codexAppServer)]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)
        let result = try? service.fetch()
        XCTAssertNotNil(result?.snapshot.weekly)
        XCTAssertNil(result?.snapshot.fiveHour)
        XCTAssertFalse(UsageError.windowUnavailable(kind: .fiveHour).isFatal)
    }

    // MARK: Concurrency — one shared operation, waiters receive actual results

    func testConcurrentFetchesAreCoalescedNotStacked() throws {
        let defaults = makeUserDefaults()
        let cache = UsageCache(userDefaults: defaults)
        cache.save(snapshot())
        let stub = BlockingStub()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: cache, restartDelay: 0)

        let gate = DispatchSemaphore(value: 0)
        stub.onRead = { gate.wait() }  // first fetch blocks until we release it

        let group = DispatchGroup()
        var results: [Result<UsageService.FetchResult, Error>] = []
        let lock = NSLock()
        for _ in 0..<3 {
            group.enter()
            DispatchQueue.global().async {
                let result = Result { try service.fetch() }
                lock.lock(); results.append(result); lock.unlock()
                group.leave()
            }
        }
        Thread.sleep(forTimeInterval: 0.3)
        gate.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(stub.readCalls, 1, "concurrent refreshes must be coalesced into one request")
        for result in results {
            let value = try result.get()
            XCTAssertTrue(value.isLive, "every waiter receives the actual live result, not cache-as-busy")
            XCTAssertEqual(value.snapshot.fiveHour?.remainingPercent, 75)
        }
    }

    func testManualArrivalDuringRunningFetchQueuesExactlyOneFollowUp() throws {
        let stub = BlockingStub()
        stub.readResults = [snapshot(), snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        let gate = DispatchSemaphore(value: 0)
        stub.onRead = { if stub.readCalls == 1 { gate.wait() } }

        var autoResult: Result<UsageService.FetchResult, Error>?
        var manualResults: [Result<UsageService.FetchResult, Error>] = []
        let resultsLock = NSLock()
        let autoDone = DispatchSemaphore(value: 0)
        let manualDone = DispatchSemaphore(value: 0)
        let manualDone2 = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            autoResult = Result { try service.fetch() }
            autoDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)   // the auto fetch now blocks inside its read

        // Two manual clicks during the running cycle: exactly one follow-up may be queued.
        DispatchQueue.global().async {
            let result = Result { try service.fetch(resetFailureBudget: true) }
            resultsLock.lock(); manualResults.append(result); resultsLock.unlock()
            manualDone.signal()
        }
        DispatchQueue.global().async {
            let result = Result { try service.fetch(resetFailureBudget: true) }
            resultsLock.lock(); manualResults.append(result); resultsLock.unlock()
            manualDone2.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)
        gate.signal()

        XCTAssertEqual(autoDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(manualDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(manualDone2.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(stub.readCalls, 2, "one running read plus exactly one queued follow-up")

        let auto = try autoResult?.get()
        XCTAssertTrue(auto?.isLive ?? false)
        for manual in manualResults {
            let value = try manual.get()
            XCTAssertTrue(value.isLive, "the queued manual callers receive the follow-up's actual result")
        }
    }

    func testManualFollowUpRunsEvenWhenTheRunningOperationIsAConfirmationRead() throws {
        let stub = BlockingStub()
        stub.readResults = [snapshot(), snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        let gate = DispatchSemaphore(value: 0)
        stub.onRead = { if stub.readCalls == 1 { gate.wait() } }

        var confirmationResult: Result<UsageService.FetchResult, Error>?
        var manualResult: Result<UsageService.FetchResult, Error>?
        let confirmationDone = DispatchSemaphore(value: 0)
        let manualDone = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            confirmationResult = Result { try service.fetchRateLimitsOnly() }
            confirmationDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)
        DispatchQueue.global().async {
            manualResult = Result { try service.fetch(resetFailureBudget: true) }
            manualDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)
        gate.signal()

        XCTAssertEqual(confirmationDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(manualDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(stub.readCalls, 2, "the queued manual fetch runs right after the confirmation read")
        XCTAssertTrue(try confirmationResult!.get().isLive)
        XCTAssertTrue(try manualResult!.get().isLive)
    }

    func testShutdownReleasesWaitersWithoutWaitingForTheRunningOperation() throws {
        let stub = BlockingStub()
        stub.readResults = [snapshot(), snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        let gate = DispatchSemaphore(value: 0)
        stub.onRead = { gate.wait() }

        let autoDone = DispatchSemaphore(value: 0)
        let manualDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = Result { try service.fetch() }
            autoDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)
        DispatchQueue.global().async {
            _ = Result { try service.fetch(resetFailureBudget: true) }
            manualDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)

        // The drain is bounded: it may not block on a wedged operation, and the waiters
        // are released before the drain wait begins.
        service.stop(shutdownTimeout: 0.5)

        // The runner is still wedged inside the stub read, so the only way the queued
        // manual caller can be done is the shutdown path releasing the waiters.
        XCTAssertEqual(manualDone.wait(timeout: .now() + 2), .success,
                       "the queued manual caller must be released by the shutdown path")

        gate.signal()    // let the abandoned runner finish so the fixture can drain
        XCTAssertEqual(autoDone.wait(timeout: .now() + 2), .success,
                       "the runner itself finishes once its read is released")
        XCTAssertThrowsError(try service.fetch()) { error in
            XCTAssertEqual(error as? UsageError, .rpcFailed(.shutdown))
        }
    }

    final class BlockingStub: CodexAppServerProviding {
        var readCalls = 0
        var onRead: (() throws -> Void)?
        var readResults: [UsageSnapshot] = []
        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            readCalls += 1
            try onRead?()
            if let result = readResults.first { return result }
            return UsageSnapshot(fiveHour: nil, weekly: nil, fetchedAt: Date(), source: .codexAppServer)
        }
        func stop() {}
        var isTransportRunning: Bool { true }
    }

    // MARK: Retry policy numbers

    func testRetryPolicyLadderNumbers() {
        XCTAssertEqual(CodexRetryPolicy.immediateRetryCount, 1)
        XCTAssertEqual(CodexRetryPolicy.backoffDelay(afterFailedEpisodes: 0), 0)
        XCTAssertEqual(CodexRetryPolicy.backoffDelay(afterFailedEpisodes: 1), 30)
        XCTAssertEqual(CodexRetryPolicy.backoffDelay(afterFailedEpisodes: 2), 60)
        XCTAssertEqual(CodexRetryPolicy.backoffDelay(afterFailedEpisodes: 3), 120)
        XCTAssertEqual(CodexRetryPolicy.backoffDelay(afterFailedEpisodes: 4), 300)
        XCTAssertEqual(CodexRetryPolicy.backoffDelay(afterFailedEpisodes: 9), 300, "capped at 300 s")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(CodexRetryPolicy.nextAutomaticRetry(now: now, failedEpisodes: 2),
                       now.addingTimeInterval(60))
        XCTAssertTrue(CodexRetryPolicy.isAutomaticAttemptDue(nextRetryAt: nil, now: now))
        // A 60 s gate: 59 s in is not yet due, the gate instant itself is.
        let gate = now.addingTimeInterval(60)
        XCTAssertFalse(CodexRetryPolicy.isAutomaticAttemptDue(nextRetryAt: gate, now: now.addingTimeInterval(59)))
        XCTAssertTrue(CodexRetryPolicy.isAutomaticAttemptDue(nextRetryAt: gate, now: gate))
        XCTAssertTrue(CodexRetryPolicy.isAutoRetryable(.rpcFailed(.timedOut(method: "account/rateLimits/read"))))
        XCTAssertFalse(CodexRetryPolicy.isAutoRetryable(.codexNotSignedIn))
        XCTAssertFalse(CodexRetryPolicy.isAutoRetryable(.rpcFailed(.shutdown)))
    }

    // MARK: Connection epoch

    func testConnectionEpochAdvancesOnlyWhenANewChildIsPublished() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        XCTAssertEqual(service.currentConnectionEpoch, 0)
        _ = try service.fetch()
        XCTAssertEqual(service.currentConnectionEpoch, 1, "the first published child opens epoch 1")
        _ = try service.fetch()
        XCTAssertEqual(service.currentConnectionEpoch, 1, "reusing the child must not bump the epoch")

        stub.readResults = []
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        _ = try? service.fetch()   // failing episode: the immediate retry publishes a replacement child
        XCTAssertEqual(service.currentConnectionEpoch, 2,
                       "the retry's newly published child opens the next epoch, even though the episode failed")

        stub.persistentError = nil
        stub.readResults = [snapshot()]
        // Manual: the failed episode above opened the backoff gate, and this step is about
        // the epoch, not the ladder.
        _ = try service.fetch(resetFailureBudget: true)    // the child was closed by the failure, so this publishes again
        XCTAssertEqual(service.currentConnectionEpoch, 3, "a replaced child opens the next epoch")
    }

    // MARK: Locator

    func testLocatorHonoursEnvironmentOverride() throws {
        let url = try CodexLocator().locate(environment: ["USAGE_MONITOR_CODEX_PATH": "/usr/bin/true"])
        XCTAssertEqual(url.path, "/usr/bin/true")
    }

    func testLocatorReportsSearchedPathsWhenMissing() throws {
        XCTAssertThrowsError(try CodexLocator().locate(environment: ["USAGE_MONITOR_CODEX_PATH": "/nonexistent/codex"])) { error in
            guard case UsageError.codexCLINotFound = error else { return XCTFail("wrong error \(error)") }
        }
        // On a machine where a candidate exists, the locator resolves it.
        if FileManager.default.isExecutableFile(atPath: "/Applications/ChatGPT.app/Contents/Resources/codex") {
            let found = try CodexLocator().locate(environment: ["PATH": "/nonexistent-dir"])
            XCTAssertEqual(found.path, "/Applications/ChatGPT.app/Contents/Resources/codex")
        }
    }
}

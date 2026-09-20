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
        return nil
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

    // MARK: 1.3.2 wake probe

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

    func testFailedWakeProbeClosesClientWithoutOpeningFailureEpisode() throws {
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
        XCTAssertFalse(service.isFailureEpisodeActive, "the full refresh still owns the original restart budget")
    }

    func testWakeProbeIsSuppressedByFailureEpisodeAndStop() {
        let failing = StubClient()
        failing.persistentError = .rpcFailed(.other)
        let service = UsageService(factory: { failing },
                                   cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0)
        _ = try? service.fetch()
        let starts = failing.startCalls
        if case .suppressed = service.probeRateLimitsAfterWake() {} else {
            XCTFail("an open failure episode must suppress wake work")
        }
        XCTAssertEqual(failing.startCalls, starts)

        service.stop()
        if case .suppressed = service.probeRateLimitsAfterWake() {} else {
            XCTFail("a stopped service must suppress wake work")
        }
        XCTAssertEqual(failing.startCalls, starts)
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

    // MARK: Round 2 blocker 2 — persistent failure budget

    func testThreeConsecutiveFailingFetchesCreateAtMostTwoClients() {
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        for _ in 0..<3 { _ = try? service.fetch() }
        XCTAssertEqual(stub.startCalls, 2,
                       "an open failure episode stops further automatic launches (probe measured 6)")
        XCTAssertTrue(service.isFailureEpisodeActive)
    }

    func testOpenEpisodeShortCircuitsWithoutLaunchingAndServesCache() throws {
        let defaults = makeUserDefaults()
        let cache = UsageCache(userDefaults: defaults)
        cache.save(snapshot())
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: cache, restartDelay: 0)

        _ = try? service.fetch()          // opens the episode: attempt + restart
        XCTAssertEqual(stub.startCalls, 2)
        let served = try service.fetch()  // automatic, episode open
        XCTAssertEqual(stub.startCalls, 2, "no additional child may be launched")
        XCTAssertFalse(served.isLive)
        XCTAssertEqual(served.snapshot.source, .cached)
        XCTAssertEqual(served.snapshot.fiveHour?.remainingPercent, 75)
    }

    func testSuccessIsOnlyReachableThroughManualRetryAfterExhaustion() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        _ = try? service.fetch()          // opens the episode
        XCTAssertTrue(service.isFailureEpisodeActive)
        XCTAssertEqual(stub.startCalls, 2)

        stub.persistentError = nil        // upstream recovered, but scheduled fetches stay frozen
        stub.readResults = [snapshot()]
        XCTAssertThrowsError(try service.fetch()) { error in
            XCTAssertEqual(error as? UsageError, .rpcFailed(.timedOut(method: "account/rateLimits/read")),
                           "no cache exists, so the frozen episode re-reports the recorded failure")
        }
        XCTAssertEqual(stub.startCalls, 2)

        let manual = try service.fetch(resetFailureBudget: true)
        XCTAssertTrue(manual.isLive, "only the explicit manual retry may re-open the budget")
        XCTAssertFalse(service.isFailureEpisodeActive)
    }

    func testManualRetryResetsTheFailureBudget() {
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        for _ in 0..<2 { _ = try? service.fetch() }
        XCTAssertEqual(stub.startCalls, 2)

        // Explicit user retry: a fresh episode with one attempt plus one restart.
        _ = try? service.fetch(resetFailureBudget: true)
        XCTAssertEqual(stub.startCalls, 4, "manual retry re-opens one attempt plus one restart")
    }

    func testSuccessClosesTheFailureEpisode() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        stub.readErrors = [.rpcFailed(.timedOut(method: "account/rateLimits/read"))]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        // Episode 1: fail once, the restart succeeds.
        let first = try service.fetch()
        XCTAssertTrue(first.isLive)
        XCTAssertFalse(service.isFailureEpisodeActive)

        // Episode 2: another single restart is available after a success.
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let second = try? service.fetch()
        XCTAssertEqual(second?.isLive, false)
        XCTAssertEqual(stub.startCalls, 4, "1+1 for the first episode, 1+1 for the second")
    }

    func testNonRestartableErrorsNeverConsumeTheBudget() {
        let stub = StubClient()
        stub.startError = .codexNotSignedIn
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)
        XCTAssertThrowsError(try service.fetch()) { error in
            XCTAssertEqual(error as? UsageError, .codexNotSignedIn)
        }
        XCTAssertEqual(stub.startCalls, 1, "a missing sign-in cannot be fixed by relaunching")
        XCTAssertTrue(service.isFailureEpisodeActive,
                      "non-restartable failures also open the episode so scheduled fetches stop repeating them")
    }

    // MARK: Round 3 blocker 1 — one bounded recovery state machine for every failure kind

    func testStartThrowIsBoundedAcrossScheduledFetches() {
        let stub = StubClient()
        stub.startError = .appServerStartupFailed(.launchFailed)
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        for _ in 0..<3 { _ = try? service.fetch() }
        XCTAssertEqual(stub.startCalls, 2,
                       "a start() failure must consume the same attempt + one restart budget (probe measured 3 attempts, breaker false)")
        XCTAssertTrue(service.isFailureEpisodeActive)
    }

    func testFactoryThrowIsBoundedAcrossScheduledFetches() {
        var factoryCalls = 0
        let service = UsageService(
            factory: { _ = factoryCalls; factoryCalls += 1
                throw UsageError.codexCLINotFound(searchedPaths: ["/Applications/ChatGPT.app/Contents/Resources/codex"]) },
            cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0
        )
        for _ in 0..<3 { _ = try? service.fetch() }
        XCTAssertEqual(factoryCalls, 1,
                       "a factory failure opens the episode, so later scheduled fetches stop repeating it")
        XCTAssertTrue(service.isFailureEpisodeActive)
        XCTAssertTrue(service.lastFailureSummary?.contains("codexCLINotFound") ?? false)
    }

    func testRestartableStartFailureThenManualRetryIsBoundedAgain() {
        let stub = StubClient()
        stub.startError = .appServerStartupFailed(.launchFailed)
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        for _ in 0..<3 { _ = try? service.fetch() }
        XCTAssertEqual(stub.startCalls, 2)

        // Only an explicit manual retry re-opens the budget, and then only once more.
        _ = try? service.fetch(resetFailureBudget: true)
        XCTAssertEqual(stub.startCalls, 4, "manual retry: one attempt plus one restart")
        for _ in 0..<2 { _ = try? service.fetch() }
        XCTAssertEqual(stub.startCalls, 4, "time and scheduled fetches must not add launches")
    }

    func testClockAdvancementNeverReopensTheBudgetAutomatically() {
        var now = Date(timeIntervalSince1970: 1_788_935_000)
        let stub = StubClient()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()),
                                   restartDelay: 0, clock: { now })

        _ = try? service.fetch()
        XCTAssertEqual(stub.startCalls, 2, "attempt plus one restart")
        for _ in 0..<5 {
            now = now.addingTimeInterval(600)   // many cooldown-sized intervals
            _ = try? service.fetch()
        }
        XCTAssertEqual(stub.startCalls, 2,
                       "the passage of time must not re-open the budget; only a manual retry may")
        XCTAssertTrue(service.isFailureEpisodeActive)
    }

    func testEpisodeClosesOnlyOnSuccess() throws {
        let stub = StubClient()
        stub.readResults = [snapshot()]
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: makeUserDefaults()), restartDelay: 0)

        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        _ = try? service.fetch()
        XCTAssertTrue(service.isFailureEpisodeActive)
        XCTAssertEqual(stub.startCalls, 2)

        stub.persistentError = nil            // upstream recovers, but only a manual retry unfreezes it
        stub.readResults = [snapshot()]
        XCTAssertThrowsError(try service.fetch())
        XCTAssertThrowsError(try service.fetch(), "the passage of time alone must not unfreeze the episode")
        let manual = try service.fetch(resetFailureBudget: true)
        XCTAssertTrue(manual.isLive)
        XCTAssertFalse(service.isFailureEpisodeActive)
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
        XCTAssertFalse(service.isFailureEpisodeActive == false && stub.startCalls > 2,
                       "shutdown must never add restarts")
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

    // MARK: Concurrency — single in-flight fetch

    func testConcurrentFetchesAreCoalescedNotStacked() throws {
        let defaults = makeUserDefaults()
        let cache = UsageCache(userDefaults: defaults)
        cache.save(snapshot())
        let stub = BlockingStub()
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
        XCTAssertTrue(results.contains { (try? $0.get())?.isLive == true })
    }

    final class BlockingStub: CodexAppServerProviding {
        var readCalls = 0
        var onRead: (() -> Void)?
        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            readCalls += 1
            onRead?()
            return UsageSnapshot(fiveHour: nil, weekly: nil, fetchedAt: Date(), source: .codexAppServer)
        }
        func stop() {}
        var isTransportRunning: Bool { true }
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

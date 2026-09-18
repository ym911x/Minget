import XCTest
import AppKit
import UsageMonitorCore
@testable import UsageMonitorApp

/// One refresh round must publish each ChatGPT profile the moment *that* profile returns
/// (REQUIREMENTS.md §3.1, IMPLEMENTATION_TASKS.md §1).
///
/// Every case here blocks the two profile reads on an explicit semaphore, so "A finished
/// while B is still in flight" is a deterministic state rather than a race the test hopes to
/// win. Nothing sleeps for a fixed period to *create* the condition; the waits are bounded
/// polls that only observe it.
@MainActor
final class ProfileRefreshPublishingTests: XCTestCase {

    // MARK: Fixtures

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "UsageMonitorAppTests.ProfilePublishing.\(label)." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func snapshot(remainingPercent: Double) -> UsageSnapshot {
        UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                usedPercent: 100 - remainingPercent,
                                                remainingPercent: remainingPercent,
                                                resetsAt: Date().addingTimeInterval(3600)),
                      weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                              usedPercent: 50, remainingPercent: 50,
                                              resetsAt: Date().addingTimeInterval(3 * 86400)),
                      fetchedAt: Date(),
                      source: .codexAppServer)
    }

    /// A client whose usage read parks until the test releases it, so completion order is
    /// decided by the test rather than by the scheduler.
    private final class GatedCodexClient: CodexAppServerProviding, @unchecked Sendable {
        private let started = DispatchSemaphore(value: 0)
        private let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls = 0

        private let snapshotValue: UsageSnapshot
        private let failure: UsageError?
        private let accountValue: CodexAccount?
        var isTransportRunning = true

        init(snapshot: UsageSnapshot,
             failure: UsageError? = nil,
             account: CodexAccount? = CodexAccount(kind: .chatgpt, email: "demo@example.com", planType: "plus")) {
            self.snapshotValue = snapshot
            self.failure = failure
            self.accountValue = account
        }

        var readCount: Int {
            lock.lock(); defer { lock.unlock() }
            return calls
        }

        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readAccount(timeout: TimeInterval) throws -> CodexAccount? { accountValue }
        func stop() { isTransportRunning = false }

        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            lock.lock(); calls += 1; lock.unlock()
            started.signal()
            release.wait()
            if let failure { throw failure }
            return snapshotValue
        }

        /// True once one usage read has entered the gated section.
        func awaitStart(timeout: TimeInterval = 5) -> Bool {
            started.wait(timeout: .now() + timeout) == .success
        }

        func releaseOnce() { release.signal() }
    }

    private func makeModel(_ label: String,
                           a: GatedCodexClient,
                           b: GatedCodexClient) -> UsageViewModel {
        let defaults = makeDefaults(label)
        let cache = UsageCache(userDefaults: defaults)
        let coordinator = CodexProfilesCoordinator(profiles: [.chatGPTA, .chatGPTB]) { profile in
            let client = profile.id == "chatgpt-a" ? a : b
            return UsageService(factory: { client }, cache: cache, profileID: profile.id, restartDelay: 0)
        }
        let engine = ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults))
        return UsageViewModel(coordinator: coordinator,
                              providerEngine: engine,
                              menuBarPreferences: MenuBarPreferences(defaults: defaults))
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    /// The round is over exactly when the last profile returns.
    private func expectRoundEnds(_ model: UsageViewModel,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) async {
        let ended = await waitUntil { !model.isRefreshing }
        XCTAssertTrue(ended, "the round must end when the last profile returns", file: file, line: line)
    }

    // MARK: A finishes first

    func testAFastProfilePublishesBeforeTheBlockedProfileReturns() async throws {
        let a = GatedCodexClient(snapshot: snapshot(remainingPercent: 66))
        let b = GatedCodexClient(snapshot: snapshot(remainingPercent: 12))
        let model = makeModel("a-first", a: a, b: b)

        model.refreshNow()
        XCTAssertTrue(a.awaitStart(), "account A's read must start")
        XCTAssertTrue(b.awaitStart(), "account B's read must start")
        XCTAssertTrue(model.isRefreshing)

        a.releaseOnce()
        let published = await waitUntil { model.profileState("chatgpt-a")?.snapshot != nil }
        XCTAssertTrue(published, "account A must publish the moment it returns, not when B does")

        XCTAssertTrue(model.isRefreshing, "the round is still in flight because B is blocked")
        XCTAssertTrue(model.profileState("chatgpt-b")?.isRefreshing ?? false,
                      "the blocked profile keeps its own refreshing flag")
        XCTAssertNil(model.profileState("chatgpt-b")?.snapshot, "B has nothing to show yet")
        XCTAssertEqual(model.profileStates.map(\.profile.id), ["chatgpt-a", "chatgpt-b"],
                       "completion order must never reorder the cards")

        b.releaseOnce()
        let ended = await waitUntil { !model.isRefreshing }
        XCTAssertTrue(ended, "the round ends when the last profile returns")
        XCTAssertEqual(model.profileState("chatgpt-b")?.snapshot?.fiveHour?.remainingPercent, 12)
        XCTAssertEqual(model.profileStates.map(\.profile.id), ["chatgpt-a", "chatgpt-b"])
    }

    func testBFastProfileAlsoPublishesFirstAndKeepsTheArrayOrder() async throws {
        let a = GatedCodexClient(snapshot: snapshot(remainingPercent: 66))
        let b = GatedCodexClient(snapshot: snapshot(remainingPercent: 12))
        let model = makeModel("b-first", a: a, b: b)

        model.refreshNow()
        XCTAssertTrue(a.awaitStart())
        XCTAssertTrue(b.awaitStart())

        b.releaseOnce()
        let published = await waitUntil { model.profileState("chatgpt-b")?.snapshot != nil }
        XCTAssertTrue(published, "B must publish while A is still blocked")

        XCTAssertTrue(model.isRefreshing)
        XCTAssertTrue(model.profileState("chatgpt-a")?.isRefreshing ?? false)
        XCTAssertNil(model.profileState("chatgpt-a")?.snapshot)
        XCTAssertEqual(model.profileStates.map(\.profile.id), ["chatgpt-a", "chatgpt-b"],
                       "B finishing first must not move account A")

        a.releaseOnce()
        await expectRoundEnds(model)
        XCTAssertEqual(model.profileState("chatgpt-a")?.snapshot?.fiveHour?.remainingPercent, 66)
        XCTAssertEqual(model.profileStates.map(\.profile.id), ["chatgpt-a", "chatgpt-b"])
    }

    // MARK: A failure is published just as promptly

    func testAFailedProfilePublishesItsFailureWhileTheOtherIsBlocked() async throws {
        // Not restartable, so the service does not loop back into the gated read.
        let a = GatedCodexClient(snapshot: snapshot(remainingPercent: 66), failure: .codexNotSignedIn)
        let b = GatedCodexClient(snapshot: snapshot(remainingPercent: 12))
        let model = makeModel("a-failure", a: a, b: b)

        model.refreshNow()
        XCTAssertTrue(a.awaitStart())
        XCTAssertTrue(b.awaitStart())

        a.releaseOnce()
        let published = await waitUntil {
            model.profileState("chatgpt-a")?.display == .unavailable(.codexNotSignedIn)
        }
        XCTAssertTrue(published, "a failed profile must publish immediately, not wait for the other")

        XCTAssertTrue(model.isRefreshing, "the round continues while B is blocked")
        XCTAssertTrue(model.profileState("chatgpt-b")?.isRefreshing ?? false)
        XCTAssertNil(model.profileState("chatgpt-b")?.snapshot, "B was not cancelled by A's failure")
        XCTAssertEqual(model.profileStates.map(\.profile.id), ["chatgpt-a", "chatgpt-b"])

        b.releaseOnce()
        await expectRoundEnds(model)
        XCTAssertNotNil(model.profileState("chatgpt-b")?.snapshot, "B still completes normally")
    }

    // MARK: The round closes and the next one is allowed

    func testTheRoundClosesAndTheNextOneIsAllowed() async throws {
        let a = GatedCodexClient(snapshot: snapshot(remainingPercent: 66))
        let b = GatedCodexClient(snapshot: snapshot(remainingPercent: 12))
        let model = makeModel("second-round", a: a, b: b)

        model.refreshNow()
        XCTAssertTrue(a.awaitStart())
        XCTAssertTrue(b.awaitStart())
        a.releaseOnce(); b.releaseOnce()
        await expectRoundEnds(model)
        XCTAssertEqual(a.readCount, 1)
        XCTAssertEqual(b.readCount, 1)

        // A stacked request is still refused while a round is running, so the counter can only
        // advance when the previous round has genuinely ended.
        model.refreshNow()
        XCTAssertTrue(a.awaitStart(), "the second round must start")
        XCTAssertTrue(b.awaitStart())
        XCTAssertEqual(a.readCount, 2, "no request is stacked for the same profile")
        XCTAssertEqual(b.readCount, 2)
        a.releaseOnce(); b.releaseOnce()
        await expectRoundEnds(model)
    }

    // MARK: Stopping suppresses anything that arrives late

    func testALateResultAfterStopIsNeverPublished() async throws {
        let a = GatedCodexClient(snapshot: snapshot(remainingPercent: 66))
        let b = GatedCodexClient(snapshot: snapshot(remainingPercent: 12))
        let model = makeModel("stop", a: a, b: b)
        let before = model.profileStates
        XCTAssertEqual(before.count, 2)

        model.refreshNow()
        XCTAssertTrue(a.awaitStart())
        XCTAssertTrue(b.awaitStart())

        let stopped = expectation(description: "stop completed")
        model.stop { stopped.fulfill() }
        XCTAssertTrue(model.isStopped)

        // The blocked reads only return after the view model has already stopped, so any
        // publication here would be a late one.
        a.releaseOnce()
        b.releaseOnce()
        await fulfillment(of: [stopped], timeout: 30)
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(model.profileStates, before, "no state may be published after stop()")
        XCTAssertFalse(model.isRefreshing)
    }
}

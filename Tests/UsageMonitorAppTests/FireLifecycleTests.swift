import XCTest
import AppKit
import UsageMonitorCore
@testable import UsageMonitorApp

/// Fire lifecycle at the view-model boundary (REVISION_SPEC.md §9, §11.6).
///
/// Two defects are pinned here: a fire child must not outlive `stop()`, and a *cached* refresh
/// must never be read as evidence that a new 5-hour window started.
@MainActor
final class FireLifecycleTests: XCTestCase {

    private static let windowStart = Date(timeIntervalSince1970: 1_800_000_000)

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minget-fire-life-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    // MARK: Fixtures

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "UsageMonitorAppTests.FireLifecycle.\(label)." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func snapshot(fiveHourResetsAt: Date, used: Double = 25) -> UsageSnapshot {
        UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                usedPercent: used, remainingPercent: 100 - used,
                                                resetsAt: fiveHourResetsAt),
                      weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                              usedPercent: 50, remainingPercent: 50,
                                              resetsAt: Self.windowStart.addingTimeInterval(3 * 86400)),
                      fetchedAt: Date(),
                      source: .codexAppServer)
    }

    /// An executable that exits 0 immediately, standing in for a successful fire request.
    private func makeSuccessfulFireExecutable() throws -> URL {
        let url = directory.appendingPathComponent("codex-ok")
        try """
        #!/usr/bin/env python3
        import sys
        sys.exit(0)
        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// An executable that hangs until a release file appears, so a stop can be observed.
    private func makeHangingFireExecutable(started: String, release: String) throws -> URL {
        let url = directory.appendingPathComponent("codex-hang")
        try """
        #!/usr/bin/env python3
        import os, time
        open(os.environ["MINGET_FIRE_STARTED"], "a").write(str(os.getpid()) + "\\n")
        while not os.path.exists(os.environ["MINGET_FIRE_RELEASE"]):
            time.sleep(0.05)
        sys.exit(0)
        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func fireService(executable: URL, extraEnvironment: [String: String] = [:]) -> ChatGPTFireService {
        var environment = ["PATH": "/usr/bin:/bin"]
        environment.merge(extraEnvironment) { _, new in new }
        return ChatGPTFireService(locator: { _ in executable },
                                  environment: environment,
                                  timeout: 30,
                                  workingDirectoryBase: directory)
    }

    /// A codex client whose answers are scripted per call, so a test can make the service
    /// serve from cache first and only later return a live read.
    private final class ScriptedClient: CodexAppServerProviding {
        enum Outcome {
            case live(UsageSnapshot)
            case failure(UsageError)
        }

        private let lock = NSLock()
        private var remaining: [Outcome]
        private let account: CodexAccount?

        init(outcomes: [Outcome], account: CodexAccount? = CodexAccount(kind: .chatgpt,
                                                                       email: "demo@example.com",
                                                                       planType: "plus")) {
            self.remaining = outcomes
            self.account = account
        }

        var isTransportRunning: Bool { true }
        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readAccount(timeout: TimeInterval) throws -> CodexAccount? { account }

        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            lock.lock()
            let outcome: Outcome
            if remaining.count > 1 {
                outcome = remaining.removeFirst()
            } else {
                outcome = remaining.first ?? .failure(.rpcFailed(.other))
            }
            lock.unlock()
            switch outcome {
            case .live(let snapshot): return snapshot
            case .failure(let error): throw error
            }
        }

        func stop() {}
    }

    /// Builds a one-profile model whose initial state is already established, so the fire has
    /// a "before" window to compare against.
    private func makeModel(_ label: String,
                           cache: UsageCache,
                           client: ScriptedClient,
                           fire: ChatGPTFireService) -> UsageViewModel {
        let defaults = makeDefaults(label)
        let coordinator = CodexProfilesCoordinator(profiles: [.chatGPTA]) { profile in
            UsageService(factory: { client }, cache: cache, profileID: profile.id, restartDelay: 0)
        }
        // Establish the pre-fire state (and, when the script says so, the cache).
        _ = coordinator.fetch(profileID: "chatgpt-a")

        let engine = ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults))
        return UsageViewModel(coordinator: coordinator,
                              providerEngine: engine,
                              menuBarPreferences: MenuBarPreferences(defaults: defaults),
                              fireService: fire,
                              fireConfirmDelay: 0,
                              fireRetryDelay: 0)
    }

    private func waitForFireResult(_ model: UsageViewModel, timeout: TimeInterval = 15) async -> ChatGPTFireResult? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = model.profileState("chatgpt-a")?.fireResult, !(model.profileState("chatgpt-a")?.isFiring ?? true) {
                return result
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return model.profileState("chatgpt-a")?.fireResult
    }

    // MARK: §11.6 Cached refreshes never confirm a window

    func testTwoCachedRefreshesReportTheRequestWithoutConfirmingAWindow() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("cached"))
        // A cached snapshot exists, and every read fails: the service answers from cache, which
        // `UsageService.FetchResult.success` still carries with `isLive == false`.
        let cachedSnapshot = snapshot(fiveHourResetsAt: Self.windowStart)
        cache.save(cachedSnapshot, profileID: "chatgpt-a", accountID: "demo@example.com")
        cache.saveLastKnownAccountID("demo@example.com", profileID: "chatgpt-a")

        let client = ScriptedClient(outcomes: [.failure(.rpcFailed(.timedOut(method: "account/rateLimits/read")))])
        let model = makeModel("cached", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        XCTAssertEqual(model.profileState("chatgpt-a")?.snapshot?.fiveHour?.resetsAt, Self.windowStart,
                       "the pre-fire state must come from the cache")

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededWindowUnchanged,
                       "a cached refresh is not evidence that a new window started")
        XCTAssertEqual(model.profileState("chatgpt-a")?.fireResult?.displayText, "请求成功，窗口未变化")
    }

    func testACachedFirstRefreshIsRetriedAndTheLiveSecondOneConfirms() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("retry"))
        cache.save(snapshot(fiveHourResetsAt: Self.windowStart),
                   profileID: "chatgpt-a", accountID: "demo@example.com")
        cache.saveLastKnownAccountID("demo@example.com", profileID: "chatgpt-a")

        // Call 1 backs the pre-fire state, call 2 is the cached first confirmation attempt,
        // call 3 is the live retry that actually moves the window.
        let movedWindow = Self.windowStart.addingTimeInterval(6 * 3600)
        let client = ScriptedClient(outcomes: [
            .failure(.rpcFailed(.timedOut(method: "account/rateLimits/read"))),
            .failure(.rpcFailed(.timedOut(method: "account/rateLimits/read"))),
            .live(snapshot(fiveHourResetsAt: movedWindow)),
        ])
        let model = makeModel("retry", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededWindowConfirmed,
                       "the 5s retry must be able to produce a live confirmation")
    }

    func testALiveRefreshThatDoesNotMoveTheWindowIsUnchanged() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("nomove"))
        let client = ScriptedClient(outcomes: [.live(snapshot(fiveHourResetsAt: Self.windowStart))])
        let model = makeModel("nomove", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        XCTAssertEqual(model.profileState("chatgpt-a")?.snapshot?.fiveHour?.resetsAt, Self.windowStart)

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededWindowUnchanged,
                       "a live read of the same window is not a new window")
    }

    func testAMovedWindowInLiveDataConfirms() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("moved"))
        // The pre-fire read reports the current window; the post-fire read reports it moved
        // forward, which is the only thing that may produce a confirmation.
        let movedWindow = Self.windowStart.addingTimeInterval(6 * 3600)
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),
            .live(snapshot(fiveHourResetsAt: movedWindow)),
        ])
        let model = makeModel("moved", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        XCTAssertEqual(model.profileState("chatgpt-a")?.snapshot?.fiveHour?.resetsAt, Self.windowStart,
                       "the pre-fire window must be the one before the request")

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededWindowConfirmed)
        XCTAssertEqual(model.profileState("chatgpt-a")?.snapshot?.fiveHour?.resetsAt, movedWindow,
                       "the card must show the newly observed window")
    }

    /// A window that moved by less than the threshold is clock skew, not a new window.
    func testAWindowThatMovesLessThanSixtySecondsIsUnchanged() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("short"))
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),
            .live(snapshot(fiveHourResetsAt: Self.windowStart.addingTimeInterval(30))),
        ])
        let model = makeModel("short", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededWindowUnchanged)
    }

    // MARK: §9.1 stop() terminates the fire child

    func testStopTerminatesARunningFireChild() async throws {
        let started = directory.appendingPathComponent("started.txt").path
        let release = directory.appendingPathComponent("release.txt").path
        let executable = try makeHangingFireExecutable(started: started, release: release)
        let service = fireService(executable: executable,
                                  extraEnvironment: ["MINGET_FIRE_STARTED": started,
                                                     "MINGET_FIRE_RELEASE": release])

        let cache = UsageCache(userDefaults: makeDefaults("stop"))
        let client = ScriptedClient(outcomes: [.live(snapshot(fiveHourResetsAt: Self.windowStart))])
        let model = makeModel("stop", cache: cache, client: client, fire: service)

        model.fire(profileID: "chatgpt-a")
        let startDeadline = Date().addingTimeInterval(10)
        while Date() < startDeadline, firstChildPID(started) == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let pid = try XCTUnwrap(firstChildPID(started), "the fire child never started")

        // The release file is never created, so only an explicit terminate can end the child.
        let stopped = expectation(description: "stop completed")
        model.stop { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 20)

        var gone = false
        for _ in 0..<100 {
            if kill(pid, 0) == -1 && errno == ESRCH { gone = true; break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(gone, "fire child \(pid) survived the app stop; it would be orphaned")
    }

    private func firstChildPID(_ path: String) -> pid_t? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let first = text.split(separator: "\n").first else { return nil }
        return pid_t(first.trimmingCharacters(in: .whitespaces))
    }
}

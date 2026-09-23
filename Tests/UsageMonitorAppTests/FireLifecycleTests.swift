import XCTest
import AppKit
@testable import UsageMonitorCore
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

    private func snapshot(fiveHourResetsAt: Date?, used: Double = 25) -> UsageSnapshot {
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
    ///
    /// `readCount` is what proves *how many* confirmation reads a case performed: the 1.3.1
    /// timing rules are about which reads happen, not only about the final result.
    private final class ScriptedClient: CodexAppServerProviding {
        enum Outcome {
            case live(UsageSnapshot)
            case failure(UsageError)
        }

        private let lock = NSLock()
        private var remaining: [Outcome]
        private var calls = 0
        private var accountReads = 0
        private let account: CodexAccount?

        init(outcomes: [Outcome], account: CodexAccount? = CodexAccount(kind: .chatgpt,
                                                                        email: "demo@example.com",
                                                                        planType: "plus")) {
            self.remaining = outcomes
            self.account = account
        }

        /// Number of `account/rateLimits/read` attempts, i.e. one per service read.
        var readCount: Int {
            lock.lock(); defer { lock.unlock() }
            return calls
        }

        /// Number of `account/read` attempts. The 1.3.2 confirmation path must keep this
        /// at zero: the confirmation only needs the reset time, never the identity.
        var accountReadCount: Int {
            lock.lock(); defer { lock.unlock() }
            return accountReads
        }

        var isTransportRunning: Bool { true }
        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readAccount(timeout: TimeInterval) throws -> CodexAccount? {
            lock.lock(); accountReads += 1; lock.unlock()
            return account
        }

        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            lock.lock()
            calls += 1
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
                           fire: ChatGPTFireService,
                           fireConfirmDelay: TimeInterval = 0,
                           fireRetryDelay: TimeInterval = 0) -> UsageViewModel {
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
                              fireConfirmDelay: fireConfirmDelay,
                              fireRetryDelay: fireRetryDelay)
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

    /// Two cached reads are not "the window did not change" — they are "there was nothing to
    /// compare". The card must say the request succeeded, not assert a fact it never observed
    /// (REQUIREMENTS.md §4.3, row 3).
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

        XCTAssertEqual(result, .requestSucceededResetUnavailable,
                       "a cached read is not evidence that a new window started, and it is not "
                       + "evidence that it did not: the card reports the request alone")
        XCTAssertEqual(model.profileState("chatgpt-a")?.fireResult?.displayText, "请求成功，重置时间未知")
    }

    func testAStalePreFireWindowCannotConfirmANewWindow() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("stale-before"))
        cache.save(snapshot(fiveHourResetsAt: Self.windowStart),
                   profileID: "chatgpt-a", accountID: "demo@example.com")
        cache.saveLastKnownAccountID("demo@example.com", profileID: "chatgpt-a")
        let moved = Self.windowStart.addingTimeInterval(6 * 3600)
        let client = ScriptedClient(outcomes: [.live(snapshot(fiveHourResetsAt: moved))])
        let service = UsageService(factory: { client }, cache: cache,
                                   profileID: "chatgpt-a", restartDelay: 0)
        let coordinator = CodexProfilesCoordinator(profiles: [.chatGPTA]) { _ in service }
        let cached = try XCTUnwrap(cache.load(profileID: "chatgpt-a", accountID: "demo@example.com"))
        coordinator.runtime(for: "chatgpt-a")?.recordFetchSuccess(
            UsageService.FetchResult(snapshot: cached, isLive: false,
                                     error: .rpcFailed(.timedOut(method: "account/rateLimits/read"))))
        let defaults = makeDefaults("stale-before")
        let model = UsageViewModel(coordinator: coordinator,
                                   providerEngine: ProviderRefreshEngine(
                                    readers: [], cache: ProviderCache(userDefaults: defaults)),
                                   menuBarPreferences: MenuBarPreferences(defaults: defaults),
                                   fireService: fireService(executable: try makeSuccessfulFireExecutable()),
                                   fireConfirmDelay: 0, fireRetryDelay: 0)
        XCTAssertTrue(model.profileState("chatgpt-a")?.isStale == true)

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededResetUnavailable,
                       "a cached before-value cannot prove that this request created the later live window")
        XCTAssertNil(model.profileState("chatgpt-a")?.fireDriftSeconds)
    }

    func testACachedFirstRefreshIsRetriedAndTheLiveSecondOneConfirms() async throws {
        // The pre-fire state is established by the first scripted outcome. The ScriptedClient
        // below only serves the two confirmation reads: call 1 is the cached first attempt,
        // call 2 is the live retry that actually moves the window.
        let cache = UsageCache(userDefaults: makeDefaults("retry"))
        let movedWindow = Self.windowStart.addingTimeInterval(6 * 3600)
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),
            .failure(.rpcFailed(.timedOut(method: "account/rateLimits/read"))),
            .live(snapshot(fiveHourResetsAt: movedWindow)),
        ])
        let model = makeModel("retry", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededResetAdvanced,
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

        XCTAssertEqual(result, .requestSucceededResetUnchanged,
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

        XCTAssertEqual(result, .requestSucceededResetAdvanced)
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

        XCTAssertEqual(result, .requestSucceededResetUnchanged)
    }

    // MARK: §4.3 The final classification truth table, row by row

    /// The truth table as a pure function: no service, no process, no timing.
    func testTheConfirmationTruthTableIsExhaustive() {
        let previous = Self.windowStart
        let moved = Self.windowStart.addingTimeInterval(6 * 3600)
        let nearly = Self.windowStart.addingTimeInterval(30)

        // Row 1: a before value and at least one live value that moved far enough.
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: previous,
                                                       previousWasLive: true,
                                                       observations: [.live(resetsAt: moved)]),
                       .requestSucceededResetAdvanced)
        // Row 2: a before value and live values, none of which moved far enough.
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: previous,
                                                       previousWasLive: true,
                                                       observations: [.live(resetsAt: previous)]),
                       .requestSucceededResetUnchanged)
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: previous,
                                                       previousWasLive: true,
                                                       observations: [.live(resetsAt: nearly)]),
                       .requestSucceededResetUnchanged)
        // A later live value can still confirm, even when the first one did not move.
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: previous,
                                                       previousWasLive: true,
                                                       observations: [.live(resetsAt: previous),
                                                                      .live(resetsAt: moved)]),
                       .requestSucceededResetAdvanced)
        // Row 3: a before value but no live evidence at all.
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: previous,
                                                       previousWasLive: true,
                                                       observations: [.noEvidence, .noEvidence]),
                       .requestSucceededResetUnavailable)
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: previous,
                                                       previousWasLive: true,
                                                       observations: []),
                       .requestSucceededResetUnavailable)
        // Row 4: no before value, however good the later reads look.
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: nil,
                                                       previousWasLive: true,
                                                       observations: [.live(resetsAt: moved)]),
                       .requestSucceededResetUnavailable)
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: nil,
                                                       previousWasLive: true,
                                                       observations: [.live(resetsAt: previous),
                                                                      .live(resetsAt: moved)]),
                       .requestSucceededResetUnavailable)
        // A cached before-value is never promoted into proof by a later live read.
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: previous,
                                                       previousWasLive: false,
                                                       observations: [.live(resetsAt: moved)]),
                       .requestSucceededResetUnavailable)
        // The threshold itself counts as movement; the classifier and the card share it.
        XCTAssertEqual(FireWindowConfirmation.threshold, 60)
        XCTAssertTrue(FireWindowConfirmation.observesAdvancedReset(live: previous.addingTimeInterval(60), previous: previous))
        XCTAssertFalse(FireWindowConfirmation.observesAdvancedReset(live: previous.addingTimeInterval(59), previous: previous))
        XCTAssertFalse(FireWindowConfirmation.observesAdvancedReset(live: moved, previous: nil))
    }

    /// The three "request succeeded" outcomes are neither successes nor failures, so the card
    /// draws them in the secondary colour rather than claiming more than it knows.
    func testTheThreeRequestSucceededResultsCarryNoSuccessOrFailureColour() {
        XCTAssertTrue(ChatGPTFireResult.requestSucceededResetAdvanced.isSuccess)
        XCTAssertFalse(ChatGPTFireResult.requestSucceededResetUnchanged.isSuccess)
        XCTAssertFalse(ChatGPTFireResult.requestSucceededResetUnavailable.isSuccess)
        for result in [ChatGPTFireResult.requestSucceededResetUnchanged,
                       .requestSucceededResetUnavailable] {
            XCTAssertFalse(result.isFailure, "\(result) is not a failure")
        }
        XCTAssertEqual(ChatGPTFireResult.requestSucceededResetUnavailable.displayText, "请求成功，重置时间未知")
    }

    /// A live first read that already moved the window ends the sequence immediately: the
    /// second read is skipped rather than spent.
    func testAConclusiveFirstReadSkipsTheSecondRefresh() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("skip-second"))
        let moved = Self.windowStart.addingTimeInterval(6 * 3600)
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),   // pre-fire
            .live(snapshot(fiveHourResetsAt: moved)),              // first confirmation
        ])
        let model = makeModel("skip-second", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        let readsAfterPrelude = client.readCount
        let accountReadsAfterPrelude = client.accountReadCount
        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededResetAdvanced)
        XCTAssertEqual(client.readCount, readsAfterPrelude + 1,
                       "a confirmed first read must not be followed by a second refresh")
        XCTAssertEqual(client.accountReadCount, accountReadsAfterPrelude,
                       "the confirmation must not resolve the account identity")
    }

    func testAnUnchangedFirstLiveReadStillTriggersTheSecondRefresh() async throws {
        // A first live read that has not moved yet is exactly the case the retry exists for.
        let cache = UsageCache(userDefaults: makeDefaults("retry-live"))
        let moved = Self.windowStart.addingTimeInterval(6 * 3600)
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),   // pre-fire
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),   // first confirmation: not moved
            .live(snapshot(fiveHourResetsAt: moved)),              // second confirmation: moved
        ])
        let model = makeModel("retry-live", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        let readsAfterPrelude = client.readCount
        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededResetAdvanced)
        XCTAssertEqual(client.readCount, readsAfterPrelude + 2,
                       "an unmoved live read must be retried once, and the retry is a real read")
    }

    /// Both live reads real, neither moving far enough: the window genuinely did not change.
    func testTwoLiveReadsBelowTheThresholdReportUnchanged() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("two-live-flat"))
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),                    // pre-fire
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),                    // first: not moved
            .live(snapshot(fiveHourResetsAt: Self.windowStart.addingTimeInterval(30))),
        ])
        let model = makeModel("two-live-flat", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededResetUnchanged)
    }

    /// No "before" value at all: the comparison the confirmation is built on does not exist,
    /// so even a later live read that looks like a fresh window cannot confirm one.
    func testAPreFireStateWithoutAWindowCannotConfirm() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("no-previous"))
        let moved = Self.windowStart.addingTimeInterval(6 * 3600)
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: nil)),   // pre-fire: live, but no reset time
            .live(snapshot(fiveHourResetsAt: moved)),
            .live(snapshot(fiveHourResetsAt: moved)),
        ])
        let model = makeModel("no-previous", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        XCTAssertNil(model.profileState("chatgpt-a")?.snapshot?.fiveHour?.resetsAt,
                     "the pre-fire state really has no reset time")

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededResetUnavailable)
    }

    // MARK: 1.3.2 Drift suffix and history

    func testConfirmedFireShowsTheMeasuredDrift() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("drift"))
        let moved = Self.windowStart.addingTimeInterval(6 * 3600 + 12 * 60)
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),
            .live(snapshot(fiveHourResetsAt: moved)),
        ])
        let model = makeModel("drift", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededResetAdvanced)
        let state = try XCTUnwrap(model.profileState("chatgpt-a"))
        XCTAssertEqual(state.fireDriftSeconds ?? -1, 6 * 3600 + 12 * 60, accuracy: 0.001)
        XCTAssertEqual(state.fireResultText, "请求成功，重置时间前移")
        XCTAssertEqual(state.fireDriftText, "+6小时12分")
        XCTAssertEqual(state.fireStatusText, "请求成功，重置时间前移 · +6小时12分")
        XCTAssertEqual(state.fireHistory.count, 1)
        XCTAssertEqual(state.fireHistoryLines.count, 1)
        XCTAssertTrue(state.fireHistoryLines[0].contains("请求成功，重置时间前移"))
    }

    func testUnchangedFireShowsASmallDriftAndUnconfirmedShowsNone() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("drift-flat"))
        let client = ScriptedClient(outcomes: [
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),
            .live(snapshot(fiveHourResetsAt: Self.windowStart)),
            .live(snapshot(fiveHourResetsAt: Self.windowStart.addingTimeInterval(32))),
        ])
        let model = makeModel("drift-flat", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()))

        model.fire(profileID: "chatgpt-a")
        let result = await waitForFireResult(model)

        XCTAssertEqual(result, .requestSucceededResetUnchanged)
        let state = try XCTUnwrap(model.profileState("chatgpt-a"))
        XCTAssertEqual(state.fireResultText, "请求成功，重置时间未变化")
        XCTAssertEqual(state.fireDriftText, "+32秒")
        XCTAssertEqual(state.fireStatusText, "请求成功，重置时间未变化 · +32秒")
    }

    func testFireDriftHelperCoversOnlyMeasuredOutcomes() {
        let moved = Self.windowStart.addingTimeInterval(3600)
        XCTAssertEqual(UsageViewModel.fireDrift(result: .requestSucceededResetAdvanced,
                                                previous: Self.windowStart,
                                                observations: [.live(resetsAt: moved)]) ?? -1,
                       3600, accuracy: 0.001 as TimeInterval)
        XCTAssertNil(UsageViewModel.fireDrift(result: .requestSucceededResetUnavailable,
                                              previous: Self.windowStart,
                                              observations: [.live(resetsAt: moved)]))
        XCTAssertNil(UsageViewModel.fireDrift(result: .requestSucceededResetAdvanced,
                                              previous: nil,
                                              observations: [.live(resetsAt: moved)]))
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

    // MARK: §4.4 Stopping inside a confirmation wait

    /// Stopping while the 2-second confirmation wait is running must publish nothing at all:
    /// the request already succeeded, but the app is gone before the verdict exists.
    func testStoppingInsideTheConfirmWaitPublishesNothing() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("stop-confirm"))
        let client = ScriptedClient(outcomes: [.live(snapshot(fiveHourResetsAt: Self.windowStart))])
        let model = makeModel("stop-confirm", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()),
                              fireConfirmDelay: 5,
                              fireRetryDelay: 5)
        let readsBeforeFire = client.readCount

        model.fire(profileID: "chatgpt-a")
        // Let the child exit and the model enter its confirm wait.
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(model.profileState("chatgpt-a")?.fireResult, "no verdict exists yet")

        let stopped = expectation(description: "stop completed")
        model.stop { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 20)
        // Longer than the remaining wait, so a late publication would have had every chance.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertNil(model.profileState("chatgpt-a")?.fireResult,
                     "a stop must suppress the verdict, even though the request already succeeded")
        XCTAssertEqual(client.readCount, readsBeforeFire,
                       "no confirmation read may run after stop()")
    }

    /// Same for the 5-second retry wait: the second read must not run after a stop, so nothing
    /// late and nothing expensive happens behind a quitting app.
    func testStoppingInsideTheRetryWaitSkipsTheSecondRead() async throws {
        let cache = UsageCache(userDefaults: makeDefaults("stop-retry"))
        // The pre-fire read and the first confirmation read both report the same window, which
        // is not a confirmation, so the model enters its retry wait.
        let client = ScriptedClient(outcomes: [.live(snapshot(fiveHourResetsAt: Self.windowStart))])
        let model = makeModel("stop-retry", cache: cache, client: client,
                              fire: fireService(executable: try makeSuccessfulFireExecutable()),
                              fireConfirmDelay: 0,
                              fireRetryDelay: 5)
        let readsAfterPrelude = client.readCount

        model.fire(profileID: "chatgpt-a")
        // One confirmation read starts; give it time to finish and the retry wait to begin.
        let startedDeadline = Date().addingTimeInterval(10)
        while Date() < startedDeadline, client.readCount < readsAfterPrelude + 1 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        let readsBeforeStop = client.readCount
        XCTAssertEqual(readsBeforeStop, readsAfterPrelude + 1,
                       "exactly one confirmation read has run at this point")

        let stopped = expectation(description: "stop completed")
        model.stop { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 20)
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertNil(model.profileState("chatgpt-a")?.fireResult)
        XCTAssertEqual(client.readCount, readsBeforeStop,
                       "the retry read must not run once the app has stopped")
    }

    private func firstChildPID(_ path: String) -> pid_t? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let first = text.split(separator: "\n").first else { return nil }
        return pid_t(first.trimmingCharacters(in: .whitespaces))
    }
}

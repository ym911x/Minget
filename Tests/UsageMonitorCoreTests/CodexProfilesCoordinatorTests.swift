import XCTest
@testable import UsageMonitorCore

/// 1.3.0 multi-profile runtime (REQUIREMENTS.md §4, IMPLEMENTATION_TASKS.md §6.1).
///
/// The isolation test launches two *real* children and reads back the `CODEX_HOME` each one
/// observed, so "two isolated profiles" is proven at the process boundary rather than asserted
/// from a stored string. Every other test uses stub clients: no network, no model call.
final class CodexProfilesCoordinatorTests: XCTestCase {

    // MARK: - Fixtures

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageMonitorCoordinatorTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minget-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A fixed-literal fake `codex` executable.
    ///
    /// It answers the three methods the app-server client uses and, crucially, reports the
    /// `CODEX_HOME` it was actually launched with as the account email. That gives the test a
    /// channel through the child's own environment instead of the parent's bookkeeping.
    private func makeFakeAppServer(in directory: URL) throws -> URL {
        let script = """
        #!/usr/bin/env python3
        import sys, json, os
        home = os.environ.get("CODEX_HOME", "")
        for raw in sys.stdin:
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            mid = msg.get("id")
            if mid is None:
                continue
            method = msg.get("method")
            if method == "initialize":
                out = {"id": mid, "result": {"ok": True}}
            elif method == "account/read":
                out = {"id": mid, "result": {"account": {"type": "chatgpt", "email": home + "@example.invalid", "planType": "test-plan"}}}
            elif method == "account/rateLimits/read":
                out = {"id": mid, "result": {"rateLimitsByLimitId": {"codex": {
                    "primary": {"usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1788935373},
                    "secondary": {"usedPercent": 20, "windowDurationMins": 10080, "resetsAt": 1789453767}}}}}
            else:
                out = {"id": mid, "result": {}}
            sys.stdout.write(json.dumps(out) + "\\n")
            sys.stdout.flush()
        """
        let url = directory.appendingPathComponent("fake-codex")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    // MARK: - Default wiring

    func testDefaultProfilesAreTheTwoFixedAccountsInOrder() {
        let coordinator = CodexProfilesCoordinator(
            makeService: { _ in
                UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                             cache: UsageCache(userDefaults: self.makeDefaults()))
            })
        XCTAssertEqual(coordinator.profileIDs, ["chatgpt-a", "chatgpt-b"])
        XCTAssertEqual(coordinator.runtimes.map(\.profile.displayName),
                       ["Codex 账号", "Hermes / OpenClaw 账号"])
        XCTAssertEqual(coordinator.runtimes.map(\.profile.shortLabel), ["A", "B"])
    }

    func testResolvedCodexHomeIsRelativeToTheProvidedHomeDirectory() {
        let coordinator = CodexProfilesCoordinator(
            makeService: { _ in
                UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                             cache: UsageCache(userDefaults: self.makeDefaults()))
            })
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        XCTAssertEqual(coordinator.resolvedCodexHome(for: "chatgpt-a", homeDirectory: home)?.path,
                       "/Users/example/.codex-minget-a")
        XCTAssertEqual(coordinator.resolvedCodexHome(for: "chatgpt-b", homeDirectory: home)?.path,
                       "/Users/example/.codex-minget-b")
        // No default value anywhere contains a personal absolute path.
        for profile in ChatGPTAccountProfile.defaults {
            XCTAssertFalse(profile.codexHomeRelativePath.hasPrefix("/"))
            XCTAssertFalse(profile.codexHomeRelativePath.contains("Users"))
        }
    }

    /// The isolation claim, proven end to end: two profile children, two `CODEX_HOME` values.
    func testTwoProfilesLaunchChildrenWithTheirOwnCodexHome() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fakeCodex = try makeFakeAppServer(in: directory)

        let environment = ["USAGE_MONITOR_CODEX_PATH": fakeCodex.path, "PATH": "/usr/bin:/bin"]
        let coordinator = CodexProfilesCoordinator(cache: UsageCache(userDefaults: makeDefaults()),
                                                   environment: environment)
        defer { coordinator.stop(shutdownTimeout: 5) }

        let resultA = coordinator.fetch(profileID: "chatgpt-a")
        let resultB = coordinator.fetch(profileID: "chatgpt-b")

        let emailA = try XCTUnwrap(try resultA.get().account?.displayEmail)
        let emailB = try XCTUnwrap(try resultB.get().account?.displayEmail)
        XCTAssertTrue(emailA.hasSuffix("/.codex-minget-a@example.invalid"), emailA)
        XCTAssertTrue(emailB.hasSuffix("/.codex-minget-b@example.invalid"), emailB)
        XCTAssertNotEqual(emailA, emailB, "the two children must not share an account home")

        // And the runtimes recorded each child's own identity, not a shared one.
        XCTAssertEqual(coordinator.runtime(for: "chatgpt-a")?.state().account?.displayEmail, emailA)
        XCTAssertEqual(coordinator.runtime(for: "chatgpt-b")?.state().account?.displayEmail, emailB)
    }

    // MARK: - Parallel refresh, independent failure

    func testBothProfilesCanBeInFlightAtTheSameTime() {
        let gate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        let cache = UsageCache(userDefaults: makeDefaults())

        func makeService() -> UsageService {
            let stub = BlockingStub()
            stub.onRead = {
                entered.signal()
                gate.wait()
            }
            return UsageService(factory: { stub }, cache: cache, restartDelay: 0)
        }

        let coordinator = CodexProfilesCoordinator { _ in makeService() }
        let done = DispatchGroup()
        for profileID in coordinator.profileIDs {
            done.enter()
            DispatchQueue.global().async {
                _ = coordinator.fetch(profileID: profileID)
                done.leave()
            }
        }

        // Both children must reach their read before either is released. If the coordinator
        // serialised the profiles, the second signal would never arrive.
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success, "profile A never started")
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success,
                       "profile B never started while A was still in flight; the refreshes are serialised")
        gate.signal()
        gate.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success)
    }

    func testOneProfileFailingDoesNotBlockTheOther() throws {
        let cache = UsageCache(userDefaults: makeDefaults())
        let failing = StubClient()
        failing.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        let healthy = StubClient()
        healthy.readResults = [snapshot()]

        let coordinator = CodexProfilesCoordinator { profile in
            UsageService(factory: { profile.id == "chatgpt-a" ? failing : healthy },
                         cache: cache, profileID: profile.id, restartDelay: 0)
        }

        let resultA = coordinator.fetch(profileID: "chatgpt-a")
        let resultB = coordinator.fetch(profileID: "chatgpt-b")

        XCTAssertNil(try? resultA.get(), "account A is out")
        XCTAssertTrue(try resultB.get().isLive, "account B must be unaffected")

        // A's failure with no cache is reported as unavailable; B's own numbers are live.
        guard case .unavailable = coordinator.runtime(for: "chatgpt-a")!.state().display else {
            return XCTFail("account A must be reported as unavailable, never as cached data")
        }
        guard case .live = coordinator.runtime(for: "chatgpt-b")!.state().display else {
            return XCTFail("account B must stay live")
        }
    }

    func testEachProfileKeepsItsOwnFailureBudget() {
        let cache = UsageCache(userDefaults: makeDefaults())
        let failing = StubClient()
        failing.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))

        let coordinator = CodexProfilesCoordinator { profile in
            UsageService(factory: { failing }, cache: cache, profileID: profile.id, restartDelay: 0)
        }

        for _ in 0..<3 { _ = coordinator.fetch(profileID: "chatgpt-a") }
        XCTAssertTrue(coordinator.runtime(for: "chatgpt-a")!.service.isFailureEpisodeActive)

        // Account B has never failed, so its budget is untouched: a shared budget would have
        // frozen it too.
        XCTAssertFalse(coordinator.runtime(for: "chatgpt-b")!.service.isFailureEpisodeActive)
        let firstB = coordinator.fetch(profileID: "chatgpt-b")
        XCTAssertNil(try? firstB.get())
        XCTAssertGreaterThanOrEqual(failing.startCalls, 4,
                                    "B must have been allowed its own attempt plus restart")
    }

    // MARK: - Shutdown

    func testStopDrainsEveryOwnedChild() throws {
        let cache = UsageCache(userDefaults: makeDefaults())
        var stubs: [String: StubClient] = [:]
        let coordinator = CodexProfilesCoordinator { profile in
            let stub = StubClient()
            stub.readResults = [self.snapshot()]
            stubs[profile.id] = stub
            return UsageService(factory: { stub }, cache: cache, profileID: profile.id, restartDelay: 0)
        }
        _ = coordinator.fetch(profileID: "chatgpt-a")
        _ = coordinator.fetch(profileID: "chatgpt-b")

        coordinator.stop(shutdownTimeout: 5)

        XCTAssertEqual(stubs["chatgpt-a"]?.stopCalls, 1, "account A's child must be stopped")
        XCTAssertEqual(stubs["chatgpt-b"]?.stopCalls, 1, "account B's child must be stopped")
        XCTAssertFalse(stubs["chatgpt-a"]?.isTransportRunning ?? true)
        XCTAssertFalse(stubs["chatgpt-b"]?.isTransportRunning ?? true)

        // Idempotent: a second stop must not try to stop the same child twice.
        coordinator.stop(shutdownTimeout: 5)
        XCTAssertEqual(stubs["chatgpt-a"]?.stopCalls, 1)
        XCTAssertEqual(stubs["chatgpt-b"]?.stopCalls, 1)
    }

    func testUnknownProfileIsReportedWithoutCrashing() {
        let coordinator = CodexProfilesCoordinator { _ in
            UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                         cache: UsageCache(userDefaults: self.makeDefaults()))
        }
        let result = coordinator.fetch(profileID: "chatgpt-z")
        XCTAssertNil(try? result.get())
        XCTAssertNil(coordinator.runtime(for: "chatgpt-z"))
    }

    // MARK: - Helpers

    private func snapshot() -> UsageSnapshot {
        UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                usedPercent: 25, remainingPercent: 75,
                                                resetsAt: Date(timeIntervalSince1970: 1_788_935_373)),
                      weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                              usedPercent: 58, remainingPercent: 42,
                                              resetsAt: Date(timeIntervalSince1970: 1_789_453_767)),
                      fetchedAt: Date(timeIntervalSince1970: 1_788_935_000),
                      source: .codexAppServer)
    }

    /// A client that blocks inside `readRateLimits` until the test releases it.
    private final class BlockingStub: CodexAppServerProviding {
        var onRead: (() -> Void)?
        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            onRead?()
            return UsageSnapshot(fiveHour: nil, weekly: nil, fetchedAt: Date(), source: .codexAppServer)
        }
        func stop() {}
        var isTransportRunning: Bool { true }
    }
}

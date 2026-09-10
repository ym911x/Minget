import XCTest
@testable import UsageMonitorCore

/// Round 3 blocker 2: termination must be able to assume quiescence when shutdown returns.
///
/// These tests model the app-exit path: a real owned child process, an in-flight fetch,
/// `stop()` returning, and then the "parent exit" moment. A survivor after that point is
/// the defect. No credentials are involved; the child is a fixed-literal python3 fixture.
final class ShutdownDrainTests: XCTestCase {

    /// Replies to initialize, then delays the rate-limits reply long enough for the test
    /// to call stop() while the read is genuinely in flight.
    static let delayedReplyServer = """
    import sys, json, time
    for raw in sys.stdin:
        try:
            msg = json.loads(raw)
        except Exception:
            break
        if msg.get("method") == "initialize":
            sys.stdout.write(json.dumps({"id": msg.get("id"), "result": {}}) + "\\n")
            sys.stdout.flush()
        else:
            time.sleep(30)
            sys.stdout.write(json.dumps({"id": msg.get("id"), "result": {}}) + "\\n")
            sys.stdout.flush()
    """

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageMonitorShutdownTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func pidIsGone(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == -1 && errno == ESRCH
    }

    /// stop() must not return while the fetch is still running: the "fetch finished"
    /// flag has to be set by the time stop() returns (probe asserted the opposite).
    func testStopReturnsOnlyAfterInFlightFetchCompletes() {
        let stub = BlockingReadStub()
        let service = UsageService(factory: { stub }, cache: UsageCache(userDefaults: self.makeDefaults()), restartDelay: 0)

        let fetchReturned = DispatchSemaphore(value: 0)
        let state = FinalStateBox()
        DispatchQueue.global().async {
            _ = try? service.fetch()
            state.fetchFinished = true
            fetchReturned.signal()
        }
        XCTAssertEqual(stub.readEntered.wait(timeout: .now() + 5), .success, "the read never started")

        service.stop(shutdownTimeout: 5)
        XCTAssertTrue(state.fetchFinished,
                      "stop() returned while the fetch was still running; termination would not be quiescent")
        XCTAssertEqual(fetchReturned.wait(timeout: .now() + 1), .success)
        service.stop()
    }

    /// Real owned child: stop() during an in-flight read must reap the child before
    /// returning, so a parent that exits immediately afterwards leaves no survivor.
    func testParentExitRightAfterShutdownLeavesNoChildSurvivor() throws {
        let executable = URL(fileURLWithPath: "/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("python3 unavailable; cannot run the real-process shutdown regression")
        }

        let defaults = makeDefaults()
        var capturedPID: pid_t = -1
        let service = UsageService(
            factory: {
                let transport = JSONRPCClient(executableURL: executable, arguments: ["-c", Self.delayedReplyServer])
                let client = CodexAppServerClient(transport: transport)
                return client
            },
            cache: UsageCache(userDefaults: defaults), restartDelay: 0
        )

        let childSeen = DispatchSemaphore(value: 0)
        let fetchDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? service.fetch()
            fetchDone.signal()
        }
        // Record the child PID as soon as the service owns one.
        DispatchQueue.global().async {
            for _ in 0..<500 {
                let current = service.childProcessIdentifier()
                if current > 0 {
                    capturedPID = current
                    childSeen.signal()
                    break
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        XCTAssertEqual(childSeen.wait(timeout: .now() + 10), .success, "no child was launched")
        XCTAssertGreaterThan(capturedPID, 0)
        Thread.sleep(forTimeInterval: 0.3)   // let the read reach its delayed reply

        // The app-exit moment: shutdown completes, then the process would exit.
        service.stop(shutdownTimeout: 10)
        XCTAssertTrue(Self.pidIsGone(capturedPID),
                      "child \(capturedPID) survived shutdown; a parent exiting now would orphan it")
        XCTAssertEqual(fetchDone.wait(timeout: .now() + 2), .success, "in-flight fetch must end before quiescence")
    }

    /// Launch raced with shutdown: the transport publishes the process before run() and
    /// serializes launch/stop, so stop() always reaches the child.
    func testStopDuringLaunchStillTerminatesTheChild() throws {
        let executable = URL(fileURLWithPath: "/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("python3 unavailable; cannot run the real-process shutdown regression")
        }
        let transport = JSONRPCClient(executableURL: executable, arguments: ["-c", Self.delayedReplyServer])
        try transport.start()
        let pid = transport.childProcessIdentifier
        XCTAssertGreaterThan(pid, 0)

        // Immediately terminate from another thread while the launch may still be running.
        let stopDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            transport.stop()
            stopDone.signal()
        }
        XCTAssertEqual(stopDone.wait(timeout: .now() + 10), .success, "stop() must not block on launch indefinitely")
        XCTAssertTrue(Self.pidIsGone(pid), "child \(pid) survived a stop() issued during launch")
    }

    /// The service-level variant: a fetch launching a child while stop() arrives.
    func testServiceStopDuringChildLaunchLeavesNoSurvivor() throws {
        let executable = URL(fileURLWithPath: "/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("python3 unavailable; cannot run the real-process shutdown regression")
        }
        let defaults = makeDefaults()
        let service = UsageService(
            factory: {
                CodexAppServerClient(transport: JSONRPCClient(executableURL: executable,
                                                              arguments: ["-c", Self.delayedReplyServer]))
            },
            cache: UsageCache(userDefaults: defaults), restartDelay: 0
        )
        let childSeen = DispatchSemaphore(value: 0)
        let fetchDone = DispatchSemaphore(value: 0)
        var pid: pid_t = -1
        DispatchQueue.global().async {
            _ = try? service.fetch()
            fetchDone.signal()
        }
        DispatchQueue.global().async {
            for _ in 0..<500 {
                let current = service.childProcessIdentifier()
                if current > 0 { pid = current; childSeen.signal(); break }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        XCTAssertEqual(childSeen.wait(timeout: .now() + 10), .success)
        service.stop(shutdownTimeout: 10)
        XCTAssertTrue(Self.pidIsGone(pid), "child \(pid) survived service shutdown")
        XCTAssertEqual(fetchDone.wait(timeout: .now() + 2), .success)
        service.stop()
    }

    private final class FinalStateBox: @unchecked Sendable {
        var fetchFinished = false
    }

    private final class BlockingReadStub: CodexAppServerProviding {
        let readEntered = DispatchSemaphore(value: 0)
        private let stateLock = NSLock()
        private var running = true

        var isTransportRunning: Bool { stateLock.withLock { running } }
        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            readEntered.signal()
            Thread.sleep(forTimeInterval: 2)   // read in flight
            return UsageSnapshot(fiveHour: nil, weekly: nil, fetchedAt: Date(), source: .codexAppServer)
        }
        func stop() { stateLock.withLock { running = false } }
    }
}

/// Narrow seam so tests can observe the owned child without reaching into private state.
extension UsageService {
    /// Process identifier of the currently owned child, or -1. Requires the factory to
    /// build clients that report it (the production `CodexAppServerClient` does).
    func childProcessIdentifier() -> pid_t {
        currentClientPID
    }
}

import XCTest
@testable import UsageMonitorCore

final class AntigravityLoginFlowTests: XCTestCase {
    func testOnboardingAfterCodeDoesNotDisplayEchoOrWrappedFragments() {
        let synthetic = "SYNTHETIC_PRIVATE_CODE_FRAGMENT"
        let terms = "Terms of Service & Data Use\n[x] Allow interaction data to improve products\n❯ I agree\n" + synthetic + "\nPRIVATE_CODE_FRAGMENT"
        let display = AntigravityLoginSession.onboardingDisplay(terms)
        XCTAssertNotNil(display)
        XCTAssertTrue(display?.contains("已勾选") == true)
        XCTAssertFalse(display?.contains("PRIVATE") == true)
        XCTAssertFalse(display?.contains(synthetic) == true)
    }
    func testThemeTrustAndUnknownPrompt() {
        XCTAssertNotNil(AntigravityLoginSession.onboardingDisplay("Select a theme\n❯ Dark\nLight"))
        XCTAssertNotNil(AntigravityLoginSession.onboardingDisplay("Do you trust this folder?\nYes, I trust this folder\nCancel"))
        XCTAssertNil(AntigravityLoginSession.onboardingDisplay("Type a message to the model"))
    }
    func testEveryProfilePathIsAbsoluteAndSharedBetweenLoginAndQuery() {
        let environment = AntigravityCLIEnvironment(executable: URL(fileURLWithPath: "/tmp/official"), home: URL(fileURLWithPath: "/tmp/profile"))
        let login = environment.environment(interactive: true)
        let query = environment.environment(interactive: false)
        for key in ["HOME=", "ANTIGRAVITY_APP_DATA_DIR=", "TMPDIR="] {
            XCTAssertEqual(login.first { $0.hasPrefix(key) }, query.first { $0.hasPrefix(key) })
            XCTAssertTrue(login.first { $0.hasPrefix(key) }?.hasPrefix(key + "/") == true)
        }
        XCTAssertTrue(environment.sandbox.contains("(deny process-fork)"))
        XCTAssertTrue(environment.sandbox.contains("(deny appleevent-send)"))
    }
    func testUnpreparedProfileCannotCommit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try AntigravityProfileStore(base: root).commit(slot: .a, uuid: UUID(), email: "synthetic@example.com"))
    }
    func testOfficialLoginMethodAndAuthorizationURLAreRecognized() throws {
        guard ProcessInfo.processInfo.environment["MINGET_AGY_REAL_PROBE"] == "1" else { throw XCTSkip("Explicit official CLI login probe; no credential input") }
        let root = AntigravityCLILocator.base.appendingPathComponent("login-gate-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AntigravityLoginSession(environment: .init(executable: AntigravityCLILocator.executable, home: root))
        let flags = LoginProbeFlags()
        session.run(timeout: 10) { event in
            if case .stage(.onboarding) = event, flags.selectOnce() { session.navigate(.confirm) }
            if case .screen(_, let url) = event, url != nil { flags.markURL(); session.cancel() }
        }
        XCTAssertTrue(flags.hasURL())
    }
    func testOfficialCLIReceivesSyntheticCodeAndRejectsIt() throws {
        guard ProcessInfo.processInfo.environment["MINGET_AGY_REAL_PROBE"] == "1" else { throw XCTSkip("Explicit official CLI synthetic input probe") }
        let root = AntigravityCLILocator.base.appendingPathComponent("input-gate-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AntigravityLoginSession(environment: .init(executable: AntigravityCLILocator.executable, home: root))
        let flags = SyntheticInputProbeFlags()
        session.run(timeout: 15, confirmationTimeout: 10) { event in
            if case .stage(.onboarding) = event, flags.selectOnce() { session.navigate(.confirm) }
            if case .stage(.awaitingCode) = event { Thread.sleep(forTimeInterval: 0.3); _ = session.submit(code: "4/SYNTHETIC_NOT_A_REAL_AUTHORIZATION_CODE") }
            if case .failed(.authenticationRejected) = event { flags.markRejected() }
        }
        XCTAssertTrue(flags.wasRejected(), "Official CLI did not acknowledge the synthetic invalid code")
    }
    func testRateLimitErrorIsClassifiedWithoutInventingRetryDuration() {
        let explicit = Data(#"{"status":"ERROR","error":"HTTP 429: too many requests"}"#.utf8)
        XCTAssertEqual(AntigravityCLIProcess.reportFailure(explicit), .rateLimited(retryAfter: nil))
        XCTAssertNil(AntigravityCLIProcess.reportFailure(Data(#"{"status":"SUCCESS","response":"429"}"#.utf8)))
        XCTAssertNil(AntigravityCLIProcess.reportFailure(Data(#"{"status":"ERROR","error":"Quota 429 remaining"}"#.utf8)))
    }
    func testOfficialReadCancellationJoinsWithoutMainActorProgress() async throws {
        guard ProcessInfo.processInfo.environment["MINGET_AGY_REAL_PROBE"] == "1" else { throw XCTSkip("Explicit official CLI cancellation probe") }
        let uuid = UUID(), root = AntigravityCLILocator.base.appendingPathComponent("cancel-gate-" + UUID().uuidString)
        let environment = AntigravityCLIEnvironment(executable: AntigravityCLILocator.executable, home: root)
        try environment.prepare(); defer { try? FileManager.default.removeItem(at: root) }
        let connection = AntigravityConnection(slot: .a, uuid: uuid, email: "synthetic@example.com", sourceVersion: AntigravityCLILocator.version)
        let task = Task { try await AntigravityUsageService().read(connection: connection, home: root) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = ProcessInfo.processInfo.systemUptime
        task.cancel()
        do { _ = try await task.value; XCTFail("Unauthenticated cancelled read published quota") }
        catch {
            XCTAssertTrue(error is CancellationError || error as? AntigravityCLIProcess.Failure == .cancelled
                          || error as? AntigravityCLIProcess.Failure == .authenticationRequired)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2.5)
    }
    func testRealEmptyProfileStopsAuthenticationWait() throws {
        guard ProcessInfo.processInfo.environment["MINGET_AGY_REAL_PROBE"] == "1" else { throw XCTSkip("Explicit official CLI read-only probe") }
        let root = AntigravityCLILocator.base.appendingPathComponent("gate-" + UUID().uuidString)
        let environment = AntigravityCLIEnvironment(executable: AntigravityCLILocator.executable, home: root)
        try environment.prepare()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try AntigravityCLIProcess(executable: environment.executable, home: root,
            appData: environment.appData, workingDirectory: environment.workspace).run()) {
            XCTAssertEqual($0 as? AntigravityCLIProcess.Failure, .authenticationRequired)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 10)
    }
}

private final class LoginProbeFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var selected = false, url = false
    func selectOnce() -> Bool { lock.lock(); defer { lock.unlock() }; if selected { return false }; selected = true; return true }
    func markURL() { lock.lock(); url = true; lock.unlock() }
    func hasURL() -> Bool { lock.lock(); defer { lock.unlock() }; return url }
}

private final class SyntheticInputProbeFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var selected = false, rejected = false
    func selectOnce() -> Bool { lock.lock(); defer { lock.unlock() }; if selected { return false }; selected = true; return true }
    func markRejected() { lock.lock(); rejected = true; lock.unlock() }
    func wasRejected() -> Bool { lock.lock(); defer { lock.unlock() }; return rejected }
}

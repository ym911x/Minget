import XCTest
@testable import UsageMonitorCore

private final class LoginEvents: @unchecked Sendable {
    private let lock = NSLock()
    var events: [AntigravityLoginSession.Event] = []
    func append(_ event: AntigravityLoginSession.Event) { lock.lock(); events.append(event); lock.unlock() }
}
final class AntigravityLoginSessionTests: XCTestCase {
    private func fixture(_ script: String) throws -> (URL, AntigravityLoginSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("minget-login-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("fixture.sh")
        try ("/bin/stty icrnl\n" + script).write(to: file, atomically: true, encoding: .utf8)
        let environment = AntigravityCLIEnvironment(executable: URL(fileURLWithPath: "/bin/sh"), home: root.appendingPathComponent("profile"))
        return (root, AntigravityLoginSession(testEnvironment: environment, arguments: [file.path]))
    }
    func testCodeSubmissionAllowsSubsequentTermsAndNeverDisplaysCode() throws {
        let code = "SYNTHETIC_SECRET_CODE_123456"
        let url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=test.apps.googleusercontent.com&response_type=code&code_challenge=test&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"
        let (root, session) = try fixture("""
        printf '\\033[2J\\033[H%s\\n' '\(url)'
        read code
        printf '\\033[2J\\033[HTerms of Service & Data Use\\n[x] Allow interaction data to improve products\\n%s\\n' "$code"
        read choice
        printf '\\033[2J\\033[HAntigravity CLI 1.2.13\\nsynthetic@example.com\\n'
        sleep 0.1
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = LoginEvents()
        session.run(timeout: 3) { event in
            events.append(event)
            if case .stage(.awaitingCode) = event { XCTAssertTrue(session.submit(code: code)) }
            if case .stage(.onboarding) = event { session.navigate(.confirm) }
        }
        XCTAssertTrue(events.events.contains { if case .identity("synthetic@example.com") = $0 { return true }; return false })
        for event in events.events { if case .screen(let text, _) = event { XCTAssertFalse(text.contains(code)) } }
    }
    func testLongCodeIsDeliveredCompletelyWithoutEcho() throws {
        let code = String(repeating: "SYNTHETIC_", count: 700)
        let url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=test.apps.googleusercontent.com&response_type=code&code_challenge=test&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"
        let (root, session) = try fixture("""
        /bin/stty -icanon min 1 time 0
        printf '\\033[2J\\033[H%s\\n' '\(url)'
        read code
        if [ "${#code}" -eq \(code.count) ]; then
          printf '\\033[2J\\033[HAntigravity CLI 1.2.13\\nsynthetic@example.com\\n'
        else
          printf '\\033[2J\\033[HAuthentication failed\\n'
        fi
        sleep 0.1
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = LoginEvents()
        session.run(timeout: 3) { event in
            events.append(event)
            if case .stage(.awaitingCode) = event { XCTAssertTrue(session.submit(code: code)) }
        }
        XCTAssertTrue(events.events.contains { if case .identity = $0 { return true }; return false })
        for event in events.events { if case .screen(let text, _) = event { XCTAssertFalse(text.contains("SYNTHETIC_")) } }
    }
    func testCodeSubmissionDoesNotDependOnTerminalCRTranslation() throws {
        let url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=test.apps.googleusercontent.com&response_type=code&code_challenge=test&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"
        let (root, session) = try fixture("""
        /bin/stty -icrnl -icanon min 1 time 0
        printf '%s\\n' '\(url)'
        read code
        printf '\\033[2J\\033[HAntigravity CLI 1.2.13\\nsynthetic@example.com\\n'
        sleep 0.1
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = LoginEvents()
        session.run(timeout: 1, confirmationTimeout: 0.3) { event in
            events.append(event)
            if case .stage(.awaitingCode) = event { session.submit(code: "SYNTHETIC_CODE") }
        }
        XCTAssertTrue(events.events.contains { if case .identity = $0 { return true }; return false })
    }
    func testSubmissionStallHasSeparateTimeout() throws {
        let url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=test.apps.googleusercontent.com&response_type=code&code_challenge=test&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"
        let (root, session) = try fixture("""
        printf '%s\\n' '\(url)'
        read code
        sleep 5
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = LoginEvents(), start = ProcessInfo.processInfo.systemUptime
        session.run(timeout: 3, confirmationTimeout: 0.1) { event in
            events.append(event)
            if case .stage(.awaitingCode) = event { session.submit(code: "SYNTHETIC_CODE") }
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        XCTAssertTrue(events.events.contains { if case .failed(.confirmationTimedOut) = $0 { return true }; return false })
    }
    func testOfficialColorSchemePromptIsOnboardingAndBareDigitsAreNotHTTPStatus() {
        let screen = "Choose your color scheme:\n> terminal\nlight\ndark\n· dim: press Enter to continue"
        let display = AntigravityLoginSession.onboardingDisplay(screen)
        XCTAssertNotNil(display)
        XCTAssertTrue(display?.contains("→ Terminal") == true)
        XCTAssertFalse(AntigravityLoginSession.safeFailureContext("secret403fragment").contains("403"))
    }
    func testTermsOptionalCollectionIsNotMislabelledAsAgreement() {
        let display = AntigravityLoginSession.onboardingDisplay("Terms of Service & Data Use\n> [x] Yes, I agree to help improve Antigravity CLI by allowing\n[Previous] > [Done]")!
        XCTAssertTrue(display.contains("[已勾选] 允许使用交互数据"))
        XCTAssertTrue(display.contains("→ 完成引导"))
        XCTAssertFalse(display.contains("同意条款"))
    }
    func testTerminalPreviousLineAndEraseBeforeCursorRemoveStaleCheckbox() {
        let data = Data("old screen\n[x] option\n\u{1B}[1F\u{1B}[2K[ ] option".utf8)
        XCTAssertTrue(AntigravityTerminal.screen(data).contains("[ ] option"))
        XCTAssertFalse(AntigravityTerminal.screen(data).contains("[x]"))
        let cleared = AntigravityTerminal.screen(Data("old\nnew\u{1B}[1Jnext".utf8))
        XCTAssertFalse(cleared.contains("old"))
        XCTAssertTrue(cleared.contains("next"))
    }
    func testTermsFooterDistinguishesPreviousFromDone() {
        let previous = AntigravityLoginSession.onboardingDisplay("Terms of Service & Data Use\n[ ] Yes, I agree to help improve Antigravity CLI\n>  Previous       [Done]\n↑/↓ Navigate · enter Confirm")!
        XCTAssertTrue(previous.contains("→ 上一步"))
        XCTAssertFalse(previous.contains("→ 完成引导"))
        let done = AntigravityLoginSession.onboardingDisplay("Terms of Service & Data Use\n[ ] Yes, I agree to help improve Antigravity CLI\n[Previous]      >  Done\n↑/↓ Navigate · enter Confirm")!
        XCTAssertTrue(done.contains("→ 完成引导"))
        XCTAssertFalse(done.contains("→ 上一步"))
    }
    func testAlternateScreenDoesNotRetainTrustPromptOverIdentity() {
        let output = Data("Do you trust this workspace?\n> Yes, I trust this folder\u{1B}[?1049hAntigravity CLI 1.2.13\nsynthetic@example.com".utf8)
        let screen = AntigravityTerminal.screen(output)
        XCTAssertNil(AntigravityLoginSession.onboardingDisplay(screen))
        XCTAssertEqual(AntigravityTerminal.identity(in: screen), "synthetic@example.com")
    }
    func testFailureContextContainsOnlyKnownLabels() {
        let input = "License fetch failed: secret-user-code https://example.com/secret?token=secret-user-code HTTP 403. Press Enter to return."
        let display = AntigravityLoginSession.safeFailureContext(input)
        XCTAssertTrue(display.contains("官方套餐读取失败"))
        XCTAssertTrue(display.contains("403"))
        XCTAssertFalse(display.contains("secret"))
        XCTAssertFalse(display.contains("https"))
    }
    func testRejectedCodeFailsWithoutCommittingIdentity() throws {
        let url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=test.apps.googleusercontent.com&response_type=code&code_challenge=test&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"
        let (root, session) = try fixture("""
        printf '\\033[2J\\033[H%s\\n' '\(url)'
        read code
        printf '\\033[2J\\033[Hinvalid_grant\\n'
        sleep 5
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = LoginEvents()
        session.run(timeout: 2) { event in
            events.append(event)
            if case .stage(.awaitingCode) = event { session.submit(code: "SYNTHETIC_INVALID_CODE") }
        }
        XCTAssertTrue(events.events.contains { if case .failed(.authenticationRejected) = $0 { return true }; return false })
        XCTAssertFalse(events.events.contains { if case .identity = $0 { return true }; return false })
    }
    func testUnknownPromptStopsInsteadOfSendingInput() throws {
        let (root, session) = try fixture("printf 'Select an option\\nUnknown feature\\n'; sleep 5")
        defer { try? FileManager.default.removeItem(at: root) }
        let events = LoginEvents(); session.run(timeout: 1, receive: { events.append($0) })
        XCTAssertTrue(events.events.contains { if case .failed(.unsupportedPrompt) = $0 { return true }; return false })
    }
    func testTimeoutAndCancellationReapSession() throws {
        let (root, session) = try fixture("sleep 5")
        defer { try? FileManager.default.removeItem(at: root) }
        let events = LoginEvents(), start = ProcessInfo.processInfo.systemUptime
        session.run(timeout: 0.1, receive: { events.append($0) })
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        XCTAssertTrue(events.events.contains { if case .failed(.timedOut) = $0 { return true }; return false })
        let (root2, cancelled) = try fixture("sleep 5")
        defer { try? FileManager.default.removeItem(at: root2) }
        cancelled.cancel(); cancelled.run(timeout: 1) { _ in XCTFail("Cancelled session published") }
    }
    func testUnrecognizedAuthenticationURLCannotAcceptCode() throws {
        let (root, session) = try fixture("printf 'https://evil.example/login\\n'; sleep 5")
        defer { try? FileManager.default.removeItem(at: root) }
        session.run(timeout: 0.1) { event in
            if case .screen(_, let url) = event { XCTAssertNil(url); XCTAssertFalse(session.submit(code: "synthetic")) }
        }
    }
}

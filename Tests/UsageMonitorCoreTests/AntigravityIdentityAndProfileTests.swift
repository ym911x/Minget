import XCTest
@testable import UsageMonitorCore

final class AntigravityIdentityAndProfileTests: XCTestCase {
    func testIdentityAllowsObservedOfficialPlanSuffixOnlyOnHeaderRow() {
        XCTAssertEqual(AntigravityTerminal.identity(in: "▄▀▀▄ Antigravity CLI 1.2.13\n▀▀▀▀▀▀ synthetic@example.com (Google AI Pro)\nGemini 3.8 Flash"), "synthetic@example.com")
        XCTAssertNil(AntigravityTerminal.identity(in: "Antigravity CLI 1.2.13\nsynthetic@example.com (unverified suffix)"))
        XCTAssertNil(AntigravityTerminal.identity(in: "Antigravity CLI 1.2.13\nnot signed in\nprompt synthetic@example.com (Google AI Pro)"))
    }
    func testIdentityRequiresPinnedOfficialHeaderAndAdjacentRow() {
        XCTAssertNil(AntigravityTerminal.identity(in: "Contact other@example.com"))
        XCTAssertNil(AntigravityTerminal.identity(in: "Antigravity CLI 9.9.9\nuser@example.com"))
        XCTAssertNil(AntigravityTerminal.identity(in: "Antigravity CLI 1.2.13\nNo identity\nuser@example.com"))
        XCTAssertEqual(AntigravityTerminal.identity(in: "▄▀▀▄ Antigravity CLI 1.2.13\n▀▀▀ USER+tag@Example.com"), "user+tag@example.com")
    }
    func testANSIScreenRewritesRowsAndHandlesChunkCompletion() {
        let raw = Data("\u{1B}[2J\u{1B}[Htheme\u{1B}[1;1HAntigravity CLI 1.2.13\u{1B}[2;1Huser@example.com\u{1B}[K".utf8)
        XCTAssertEqual(AntigravityTerminal.identity(in: AntigravityTerminal.screen(raw)), "user@example.com")
        XCTAssertNil(AntigravityTerminal.identity(in: AntigravityTerminal.screen(raw.prefix(8))))
        let partial = Data("\u{1B}[HAntigravity CLI 1.2.13\r\nuser@example.com".utf8)
        for split in 1..<partial.count {
            var rebuilt = Data(partial.prefix(split)); rebuilt.append(partial.dropFirst(split))
            XCTAssertEqual(AntigravityTerminal.identity(in: AntigravityTerminal.screen(rebuilt)), "user@example.com")
        }
    }
    func testAuthenticationURLRejectsUnexpectedHostsAndRedactsQuery() {
        XCTAssertNil(AntigravityTerminal.authenticationURL(in: "https://accounts.google.com.evil.example/login?q=synthetic"))
        XCTAssertNil(AntigravityTerminal.authenticationURL(in: "https://user@accounts.google.com/login"))
        XCTAssertNil(AntigravityTerminal.authenticationURL(in: "Go https://accounts.google.com/login?q=synthetic"))
        let fullURL = "https://accounts.google.com/o/oauth2/v2/auth?client_id=test.apps.googleusercontent.com&response_type=code&code_challenge=challenge&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"
        let wrappedURL = fullURL.replacingOccurrences(of: "&response_type", with: "\n&response_type")
            .replacingOccurrences(of: "&redirect_uri", with: "\n&redirect_uri") + "\n\nCopy and paste the URL"
        XCTAssertEqual(AntigravityTerminal.authenticationURL(in: wrappedURL)?.absoluteString, fullURL)
        let chunks = Data(("\u{1B}[31m" + fullURL + "\u{1B}[0m").utf8)
        XCTAssertEqual(AntigravityTerminal.authenticationURL(in: AntigravityTerminal.plainText(chunks))?.host, "accounts.google.com")
        XCTAssertNil(AntigravityTerminal.authenticationURL(in: "https://accounts.google.com/o/oauth2/v2/auth?client_id=test.apps.googleusercontent.com&code_challenge=challenge&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"))
        XCTAssertFalse(AntigravityTerminal.redacted("Go https://accounts.google.com/login?q=synthetic").contains("synthetic"))
        let wrapped = AntigravityTerminal.redacted("If needed: [请点击打开官方认证页面]\napps.googleusercontent.com&code_challenge=private\nSign in to continue")
        XCTAssertFalse(wrapped.contains("googleusercontent")); XCTAssertFalse(wrapped.contains("code_challenge"))
        XCTAssertTrue(wrapped.contains("Sign in to continue"))
    }
    func testProfileCommitDuplicateAndReplacementAreTransactional() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AntigravityProfileStore(base: root)
        let a = UUID(), b = UUID(), replacement = UUID()
        try store.prepare(a); try store.prepare(b); try store.prepare(replacement)
        let first = try store.commit(slot: .a, uuid: a, email: "User+tag@example.com")
        XCTAssertThrowsError(try store.commit(slot: .b, uuid: b, email: "user+tag@example.com"))
        XCTAssertEqual(try store.connections(), [first])
        let second = try store.commit(slot: .b, uuid: b, email: "user@example.com")
        XCTAssertEqual(try store.connections().count, 2)
        let replaced = try store.commit(slot: .a, uuid: replacement, email: "other@example.com")
        XCTAssertEqual(try store.connections().first(where: { $0.slot == .a }), replaced)
        try store.disconnect(second)
        XCTAssertEqual(try store.connections(), [replaced])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.home(b).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.home(replacement).path))
    }
    func testCleanupRejectsSymlinkAndDoesNotTouchOutsideData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let store = AntigravityProfileStore(base: root), uuid = UUID()
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.base.appendingPathComponent("profiles"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: store.home(uuid), withDestinationURL: outside)
        XCTAssertThrowsError(try store.removeProfile(uuid))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}

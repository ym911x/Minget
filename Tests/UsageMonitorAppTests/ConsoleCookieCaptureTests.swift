import XCTest
import WebKit
import UsageMonitorCore
@testable import UsageMonitorApp

/// Cookie capture for the console login window (REVIEW round 8 finding 1).
///
/// A login that completes via fetch/XHR never triggers another document navigation, so
/// capture-at-navigation-time alone can save a stale session. These tests pin:
/// - the store is polled, so `latestSession` follows cookies that change after the
///   initial document load,
/// - `freshSession()` (the awaited capture the 完成连接 button uses) returns the LATEST
///   store contents at call time,
/// - only official-host cookies enter the session.
///
/// The tests use a real app-owned `WKWebsiteDataStore.nonPersistent()`; no browser data
/// is touched and no cookie value is asserted or printed.
@MainActor
final class ConsoleCookieCaptureTests: XCTestCase {

    /// Minimal recording transport for the end-to-end completion flow.
    final class RecordingTransport: ProviderTransport, @unchecked Sendable {
        var handler: ((URLRequest) throws -> ProviderHTTPResponse)?
        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            return try handler?(request) ?? ProviderHTTPResponse(status: 200, body: Data())
        }
    }

    private var store: WKHTTPCookieStore!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        store = WKWebsiteDataStore.nonPersistent().httpCookieStore
        let suite = "UsageMonitorAppTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        store = nil
        defaults = nil
        super.tearDown()
    }

    private func makeCookie(_ name: String, _ value: String, domain: String) -> HTTPCookie {
        return HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: domain,
            .path: "/",
        ])!
    }

    private func officialCookie(_ name: String, _ value: String) -> HTTPCookie {
        return makeCookie(name, value, domain: "bigmodel.cn")
    }

    private func waitFor(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !condition() {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testPolledSessionFollowsCookiesThatChangeAfterTheInitialLoad() async throws {
        let capture = ConsoleCookieCapture()
        capture.attach(store)

        await store.setCookie(officialCookie("sid", "before-login"))
        try await waitFor(capture.latestSession != nil)
        let first = try XCTUnwrap(capture.latestSession)
        XCTAssertEqual(first.cookies.map { $0.name }, ["sid"])

        // The SPA login sets a new cookie without any document navigation: the poll must
        // pick it up.
        await store.setCookie(officialCookie("token", "after-login"))
        try await waitFor(capture.latestSession?.cookies.count == 2)
        let second = try XCTUnwrap(capture.latestSession)
        XCTAssertEqual(Set(second.cookies.map { $0.name }), ["sid", "token"])

        capture.detach()
    }

    func testFreshSessionAtCompletionReturnsTheLatestStoreContents() async throws {
        let capture = ConsoleCookieCapture()
        capture.attach(store)
        await store.setCookie(officialCookie("sid", "before-login"))
        try await waitFor(capture.latestSession != nil)

        // Cookies change right before the user presses 完成连接.
        await store.setCookie(officialCookie("sid2", "completion-time"))

        let fresh = await capture.freshSession()
        let session = try XCTUnwrap(fresh,
                                    "completion must capture the store's current contents")
        XCTAssertEqual(Set(session.cookies.map { $0.name }), ["sid", "sid2"],
                       "the awaited fresh capture reflects the latest cookies, not a stale snapshot")

        capture.detach()
    }

    func testOnlyOfficialHostCookiesEnterTheSession() throws {
        let captured = ConsoleCookieCapture.session(from: [
            officialCookie("good", "1"),
            makeCookie("bad", "2", domain: "tracker.example.com"),
            makeCookie("also-bad", "3", domain: "bigmodel.cn.evil.com"),
        ])
        let session = try XCTUnwrap(captured)
        XCTAssertEqual(session.cookies.map { $0.name }, ["good"],
                       "cross-domain cookies never contribute to the stored session")
    }

    func testSavingTheLatestSessionThroughTheViewModelFlow() async throws {
        // The completion flow end to end: fresh capture → saveGLMConsoleSession. The
        // reading persists the connection mode, so a restarted reader still selects it.
        let transport = RecordingTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"data":{"balance":{"balance":"9.00","availableBalance":"5.00"}}}"#.utf8))
        }
        let deepSeek = DeepSeekReading(provider: DeepSeekProvider(transport: transport, credentials: InMemoryCredentialStore()),
                                       credentials: InMemoryCredentialStore())
        let credentialStore = InMemoryCredentialStore()
        let glm = GLMReading(provider: GLMProvider(transport: transport, credentials: credentialStore),
                             credentials: credentialStore, preferences: defaults)
        let engine = ProviderRefreshEngine(readers: [deepSeek, glm], cache: ProviderCache(userDefaults: defaults))
        let service = UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                                   cache: UsageCache(userDefaults: defaults))
        let model = UsageViewModel(service: service, providerEngine: engine)

        let capture = ConsoleCookieCapture()
        capture.attach(store)
        await store.setCookie(officialCookie("sid", "late"))
        try await waitFor(capture.latestSession != nil)

        let captured = await capture.freshSession()
        let session = try XCTUnwrap(captured)
        let saved = model.saveGLMConsoleSession(session)
        XCTAssertTrue(saved, "completion saves the latest session")
        XCTAssertEqual(model.credentialFeedback(for: .glm), .verifying(platform: .glm),
                       "a successful save immediately starts verification")
    }
}

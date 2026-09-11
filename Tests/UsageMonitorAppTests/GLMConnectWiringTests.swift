import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// Application wiring for the GLM credential flows: the moment an API key or a console
/// session is saved, a read-only probe runs and its redacted observation is published.
/// The fresh credential is never handed to the normal balance read while the payload
/// contract is unconfirmed — that path fails closed on the contract gate and would
/// produce a bare failure without any observation.
///
/// No keychain is touched (in-memory store) and no network is reached (stub transport).
@MainActor
final class GLMConnectWiringTests: XCTestCase {

    /// Stub transport shared by both provider readings, recording every request.
    final class StubTransport: ProviderTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URLRequest] = []
        var handler: ((URLRequest) throws -> ProviderHTTPResponse)?

        var recordedRequests: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return requests
        }

        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            record(request)
            return try handler?(request) ?? ProviderHTTPResponse(status: 200, body: Data())
        }

        /// Synchronous helper: `lock` is unavailable from async contexts.
        private func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
        }
    }

    private var store: InMemoryCredentialStore!
    private var transport: StubTransport!
    private var engine: ProviderRefreshEngine!
    private var glm: GLMReading!
    private var model: UsageViewModel!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suite = "UsageMonitorAppTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        store = InMemoryCredentialStore()
        transport = StubTransport()
        glm = GLMReading(provider: GLMProvider(transport: transport),
                         credentials: store)
        let deepSeek = DeepSeekReading(provider: DeepSeekProvider(transport: transport),
                                       credentials: store)
        engine = ProviderRefreshEngine(readers: [deepSeek, glm],
                                       cache: ProviderCache(userDefaults: defaults))
        let service = UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                                   cache: UsageCache(userDefaults: defaults))
        model = UsageViewModel(service: service, providerEngine: engine)
    }

    override func tearDown() {
        model = nil
        engine = nil
        glm = nil
        transport = nil
        store = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Waiting

    /// The save call launches its connect task and returns; the test waits for the
    /// observation it must publish.
    private func waitForObservation(timeout: TimeInterval = 5) async -> GLMAccountReportObservation? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let observation = model.glmObservation { return observation }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return model.glmObservation
    }

    // MARK: - API key saved → immediate probe

    func testSavingAGLMKeyReadsTheBalanceEndpointAndShowsTheBalance() async throws {
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"data":{"total_balance":"100.00","available_balance":"88.00","currency":"CNY"}}"#.utf8))
        }

        model.saveGLMAPIKey("glm-test-key")
        let observation = await waitForObservation()

        let unwrapped = try XCTUnwrap(observation, "saving a key must publish an observation")
        XCTAssertEqual(unwrapped.httpStatus, 200)
        XCTAssertEqual(unwrapped.schema, .apiBalanceV1, "a plain key reads the balance endpoint")
        XCTAssertNil(unwrapped.parseFailure, "a clean payload is recorded without a failure")

        // The schema is confirmed and the parse strict: the balance is displayed.
        XCTAssertTrue(unwrapped.isDisplayable)
        let report = model.providerReports.first { $0.platform == .glm }!
        XCTAssertEqual(report.connection, .connected)
        XCTAssertEqual(report.balances.first?.total,
                       Decimal(string: "100.00", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(report.balances.first?.available,
                       Decimal(string: "88.00", locale: Locale(identifier: "en_US_POSIX")),
                       "the available amount keeps its own semantics")

        // The read went to the official host and the balance endpoint only, with the key.
        XCTAssertEqual(Set(transport.recordedRequests.compactMap { $0.url?.host }), ["open.bigmodel.cn"])
        XCTAssertEqual(transport.recordedRequests.first?.url?.path, GLMProvider.balancePath)
        XCTAssertEqual(transport.recordedRequests.first?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer glm-test-key")
    }

    /// A business-successful answer that matches no known shape: recorded with a redacted
    /// structure summary, reported as structure-unsupported, never displayed (Round 7
    /// requirement 2).
    func testAnUnknownShapeOnTheBalanceEndpointIsReportedAsStructureUnsupported() async throws {
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"data":{"wallet":{"funds":[1,2]}}}"#.utf8))
        }

        model.saveGLMAPIKey("glm-test-key")
        let observation = await waitForObservation()

        let unwrapped = try XCTUnwrap(observation)
        XCTAssertEqual(unwrapped.httpStatus, 200)
        XCTAssertTrue(unwrapped.candidateBalances.isEmpty, "no amount may be invented")
        XCTAssertFalse(unwrapped.structureSummary.isEmpty,
                       "the real shape is recorded redacted for the next revision")
        for entry in unwrapped.structureSummary {
            XCTAssertFalse(entry.contains("wallet".uppercased()) && entry.contains(":" ) == false, entry)
        }
        let report = model.providerReports.first { $0.platform == .glm }!
        XCTAssertEqual(report.connection, .unverified)
        XCTAssertEqual(report.error, .structureUnsupported)
        XCTAssertTrue(report.balances.isEmpty)
        // The feedback says connected-but-unsupported, not an invalid key.
        XCTAssertEqual(model.credentialFeedback(for: .glm), .structureUnsupported(platform: .glm))
    }

    func testARejectedKeyIsPublishedWithItsRealStatusAndSuspendsRetry() async throws {
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }

        model.saveGLMAPIKey("glm-rejected-key")
        let observation = await waitForObservation()

        let unwrapped = try XCTUnwrap(observation, "a rejection must be published, not swallowed")
        XCTAssertEqual(unwrapped.httpStatus, 401, "the real status must survive into the observation")
        XCTAssertEqual(unwrapped.parseFailure, ProviderFailure.invalidCredential)

        let report = model.providerReports.first { $0.platform == .glm }!
        XCTAssertEqual(report.connection, .authSuspended,
                       "a rejected credential suspends automatic retry")
        XCTAssertEqual(report.error, .invalidCredential)
    }

    func testAnHTTP200BusinessErrorIsClassifiedAsABusinessError() async throws {
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":1113,"message":"x"}"#.utf8))
        }

        model.saveGLMAPIKey("glm-key")
        let observation = await waitForObservation()

        let unwrapped = try XCTUnwrap(observation)
        XCTAssertEqual(unwrapped.httpStatus, 200)
        XCTAssertEqual(unwrapped.businessCode, 1113)
        XCTAssertEqual(unwrapped.parseFailure, ProviderFailure.businessError(code: 1113))
        XCTAssertTrue(unwrapped.candidateBalances.isEmpty)
        XCTAssertTrue(model.providerReports.first { $0.platform == .glm }!.balances.isEmpty)
    }

    // MARK: - Console session saved → immediate probe

    private func makeSession(expiresIn: TimeInterval?) -> GLMConsoleSessionPolicy.StoredSession {
        let cookie = GLMConsoleSessionPolicy.StoredCookie(
            name: "session", value: "captured", domain: "bigmodel.cn",
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) })
        return GLMConsoleSessionPolicy.StoredSession(cookies: [cookie], capturedAt: Date())
    }

    func testOfficialConsoleSessionUsesTokenHeaderAndFlatBalance() async throws {
        transport.handler = { request in
            XCTAssertEqual(request.url?.host, "bigmodel.cn")
            XCTAssertEqual(request.url?.path, GLMProvider.accountReportPath)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-login-token")
            return ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"data":{"balance":80.5,"availableBalance":70.25}}"#.utf8))
        }
        let session = GLMConsoleSessionPolicy.StoredSession(cookies: [
            .init(name: "bigmodel_token_production", value: "fixture-login-token", domain: ".bigmodel.cn", expiresAt: nil)
        ], capturedAt: Date())
        XCTAssertTrue(model.saveGLMConsoleSession(session))
        _ = await waitForObservation()
        let report = try XCTUnwrap(model.providerReports.first { $0.platform == .glm })
        XCTAssertEqual(report.connection, .connected)
        XCTAssertEqual(report.balances.first?.available, Decimal(string: "70.25"))
        XCTAssertEqual(report.balances.first?.currency, "CNY")
    }

    func testSavingAConsoleSessionReadsTheReportEndpointWithTheCookie() async throws {
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"msg":"success","data":{"balance":{"balance":"9.00","availableBalance":"5.00"}}}"#.utf8))
        }

        model.saveGLMConsoleSession(makeSession(expiresIn: 3600))
        let observation = await waitForObservation()

        let unwrapped = try XCTUnwrap(observation, "saving a session must publish an observation")
        XCTAssertEqual(unwrapped.httpStatus, 200)
        XCTAssertEqual(unwrapped.schema, .consoleReportV1)
        XCTAssertTrue(unwrapped.isDisplayable)
        XCTAssertEqual(model.providerReports.first { $0.platform == .glm }!.connection, .connected)

        let requests = transport.recordedRequests
        XCTAssertFalse(requests.isEmpty, "the session must be exercised without another user click")
        for request in requests {
            let cookie = request.value(forHTTPHeaderField: "Cookie")
            XCTAssertEqual(cookie, "session=captured", "the captured session must be offered as a cookie")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"),
                         "a session read must not offer an API key")
            XCTAssertEqual(request.url?.host, "bigmodel.cn")
            XCTAssertEqual(request.url?.path, GLMProvider.accountReportPath)
        }
    }

    /// An API key and a session both stored: the probe exercises the credential that was
    /// saved most recently, so connecting a session really probes the session.
    func testSavingAConsoleSessionProbesTheSessionEvenWhenAKeyIsStored() async throws {
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }
        model.saveGLMAPIKey("glm-existing-key")
        _ = await waitForObservation()
        let keyProbeCount = transport.recordedRequests.count
        XCTAssertGreaterThan(keyProbeCount, 0)

        model.saveGLMConsoleSession(makeSession(expiresIn: 3600))
        // Wait for a *new* request rather than for an observation: one is already present
        // from the key probe above.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && transport.recordedRequests.count <= keyProbeCount {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let sessionRequests = Array(transport.recordedRequests.dropFirst(keyProbeCount))
        XCTAssertFalse(sessionRequests.isEmpty)
        for request in sessionRequests {
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Cookie"),
                            "the probe after saving a session must use the session")
        }
    }

    func testASessionRejectedByTheServerSuspendsAutomaticRetry() async throws {
        transport.handler = { _ in ProviderHTTPResponse(status: 403, body: Data()) }

        model.saveGLMConsoleSession(makeSession(expiresIn: 3600))
        let observation = await waitForObservation()

        let unwrapped = try XCTUnwrap(observation)
        XCTAssertEqual(unwrapped.httpStatus, 403)
        XCTAssertEqual(unwrapped.parseFailure, ProviderFailure.invalidCredential)
        XCTAssertEqual(model.providerReports.first { $0.platform == .glm }!.connection, .authSuspended)
    }

    /// A hard-expired session is never replayed: no request leaves the process, and the
    /// observation says the credential is dead.
    func testAHardExpiredSessionIsNotReplayed() async throws {
        model.saveGLMConsoleSession(makeSession(expiresIn: -60))
        let observation = await waitForObservation()

        let unwrapped = try XCTUnwrap(observation)
        XCTAssertEqual(unwrapped.httpStatus, 0, "status 0 means no request was sent")
        XCTAssertEqual(unwrapped.parseFailure, ProviderFailure.invalidCredential)
        XCTAssertTrue(transport.recordedRequests.isEmpty,
                      "an expired session must never be sent to the endpoint")
        XCTAssertEqual(model.providerReports.first { $0.platform == .glm }!.connection, .authSuspended)
    }

    /// Reconnecting after an auth suspension clears it: saving a working credential
    /// resumes automatic refresh eligibility.
    func testReconnectingWithAWorkingCredentialClearsTheSuspension() async throws {
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }
        model.saveGLMAPIKey("glm-bad-key")
        _ = await waitForObservation()
        XCTAssertTrue(engine.isAuthSuspended(.glm))

        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"data":{"total_balance":"7.00"}}"#.utf8))
        }
        model.saveGLMAPIKey("glm-good-key")
        // Wait for the second save's request (each read issues exactly one), then for the
        // connect task to settle.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && transport.recordedRequests.count < 2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        while Date() < deadline && engine.isAuthSuspended(.glm) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(engine.isAuthSuspended(.glm), "a successful reconnect must clear the suspension")
    }

    // MARK: - Round 8: auth business codes, relogin attribution, console observations

    /// HTTP 200 with an authentication business code is a credential rejection: it
    /// suspends automatic retry, and reconnecting recovers (REVIEW round 7 finding 2).
    func testAnAuthenticationBusinessCodeSuspendsRetryUntilReconnect() async throws {
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":401,"msg":"auth"}"#.utf8))
        }
        model.saveGLMAPIKey("glm-key")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && model.credentialFeedback(for: .glm) != .invalidCredential(platform: .glm) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.credentialFeedback(for: .glm), .invalidCredential(platform: .glm))
        XCTAssertTrue(engine.isAuthSuspended(.glm))

        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"data":{"available_balance":"8.00","currency":"CNY"}}"#.utf8))
        }
        model.saveGLMAPIKey("glm-key-2")
        while Date() < deadline && model.credentialFeedback(for: .glm) != .connected(platform: .glm) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(engine.isAuthSuspended(.glm), "reconnecting must clear the suspension")
    }

    /// Relogin (a new console session) must not display the old session's cached numbers:
    /// the attribution resets when the credential changes, and the fresh read lands under
    /// the new session's own identity.
    func testReloginSwitchesToTheNewSessionCacheIdentity() async throws {
        let sessionA = GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: "sid", value: "a", domain: "bigmodel.cn",
                                                           expiresAt: Date().addingTimeInterval(3600))],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_100))
        let sessionB = GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: "sid", value: "b", domain: "bigmodel.cn",
                                                           expiresAt: Date().addingTimeInterval(3600))],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_200))

        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"data":{"balance":{"balance":"111.00","availableBalance":"11.00"}}}"#.utf8))
        }
        model.saveGLMConsoleSession(sessionA)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && model.credentialFeedback(for: .glm) != .connected(platform: .glm) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        var report = model.providerReports.first { $0.platform == .glm }!
        XCTAssertEqual(report.accountID, "console-1700000100000")

        // The account relogs: a new capture time is a new identity.
        model.saveGLMConsoleSession(sessionB)
        while Date() < deadline && model.providerReports.first(where: { $0.platform == .glm })!.accountID != "console-1700000200000" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        report = model.providerReports.first { $0.platform == .glm }!
        XCTAssertEqual(report.accountID, "console-1700000200000",
                       "session-derived numbers use the session's own cache identity")
        XCTAssertEqual(report.balances.first?.available,
                       Decimal(string: "11.00", locale: Locale(identifier: "en_US_POSIX")))
    }

    func testConsoleObservationsAreRecordedDeduplicatedAndCapped() {
        let observation = { (suffix: String) in
            GLMConsoleResponseObserver.Observation(
                urlPath: "https://bigmodel.cn/api/x" + suffix,
                method: "GET", requestHeaderNames: ["x-csrf-token"],
                entries: ["code: number", "data: object"])
        }
        model.recordConsoleObservation(observation("1"))
        model.recordConsoleObservation(observation("2"))
        model.recordConsoleObservation(observation("1"))   // same path: replaces the old one

        XCTAssertEqual(model.consoleObservations.count, 2)
        XCTAssertEqual(model.consoleObservations.first?.urlPath, "https://bigmodel.cn/api/x1",
                       "the newest observation per path comes first")

        for i in 0..<(GLMConsoleResponseObserver.maxObservationsKept + 4) {
            model.recordConsoleObservation(observation("bulk-\(i)"))
        }
        XCTAssertEqual(model.consoleObservations.count, GLMConsoleResponseObserver.maxObservationsKept,
                       "the observation list is capped")
        for observation in model.consoleObservations {
            XCTAssertFalse(observation.entries.contains { $0.contains("secret") })
        }
    }

    /// Disconnect removes the credentials and the observation path stops producing
    /// anything: after disconnect nothing is configured.
    func testDisconnectClearsTheConnection() async throws {
        transport.handler = { _ in ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"data":{"total_balance":"7.00"}}"#.utf8)) }
        model.saveGLMAPIKey("glm-key")
        _ = await waitForObservation()
        XCTAssertTrue(glm.isConfigured)

        model.disconnectGLM()

        XCTAssertFalse(glm.isConfigured)
        XCTAssertEqual(store.load(.glmAPIKey), .missing)
        let report = model.providerReports.first { $0.platform == .glm }!
        XCTAssertEqual(report.connection, .notConfigured)
        XCTAssertTrue(report.balances.isEmpty, "a disconnect leaves no numbers behind")
    }
}

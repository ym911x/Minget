import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// Production composition root and credential feedback tests (Round 6 requirement 7).
///
/// The first test instantiates the **real** `AppContainer` — the exact composition path the
/// running app uses — with an in-memory keychain store and an in-process transport. It
/// exists because a previous build wired `UsageViewModel` without any credential store, so
/// `saveDeepSeekKey` returned silently at `guard let credentials`: repeated clicks on
/// 保存 did nothing and showed nothing. A test with a hand-built engine and an explicit
/// store could never catch that; this one can.
///
/// No real keychain, no network, no child process, and no key material is ever printed.
@MainActor
final class ProductionWiringTests: XCTestCase {

    /// In-process transport, recording every request.
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

    /// A store whose keychain write fails, standing in for a real keychain error.
    final class FailingSaveCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
        func save(_ secret: String, for key: ProviderCredentialKey) throws {
            throw ProviderFailure.other
        }
        func load(_ key: ProviderCredentialKey, interaction: CredentialInteraction) -> CredentialAccessOutcome {
            return .missing
        }
        func delete(_ key: ProviderCredentialKey) throws {}
    }

    private let balanceBody = Data("""
    {"is_available": true, "balance_infos": [{"currency": "CNY", "total_balance": "110.00", \
    "granted_balance": "0.00", "topped_up_balance": "110.00"}]}
    """.utf8)

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suite = "UsageMonitorAppTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    // MARK: - Waiting

    private func waitForFeedback(on model: UsageViewModel,
                                 _ platform: ProviderPlatform,
                                 equals expected: CredentialFeedback,
                                 timeout: TimeInterval = 5) async -> CredentialFeedback? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let current = model.credentialFeedback(for: platform), current == expected {
                return current
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return model.credentialFeedback(for: platform)
    }

    /// The model under test, built exactly like `AppContainer` builds it: engine-owned
    /// readings, no separate credential store on the view model.
    private func makeModel(transport: StubTransport,
                           credentials: ProviderCredentialStoring) -> UsageViewModel {
        let deepSeek = DeepSeekReading(provider: DeepSeekProvider(transport: transport),
                                       credentials: credentials)
        let glm = GLMReading(provider: GLMProvider(transport: transport),
                             credentials: credentials)
        let engine = ProviderRefreshEngine(readers: [deepSeek, glm],
                                           cache: ProviderCache(userDefaults: defaults))
        let service = UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                                   cache: UsageCache(userDefaults: defaults))
        return UsageViewModel(service: service, providerEngine: engine)
    }

    // MARK: - The production composition root

    /// The regression test for the Round 6 root cause: saving through the real
    /// `AppContainer` must reach the container's credential store and immediately verify
    /// against the official endpoint. Under the old wiring (`UsageViewModel` without a
    /// credential store) the save silently returned, the store stayed empty and nothing
    /// was shown.
    func testSavingADeepSeekKeyThroughTheProductionRootStoresItAndVerifies() async throws {
        let store = InMemoryCredentialStore()
        let transport = StubTransport()
        transport.handler = { [balanceBody] _ in ProviderHTTPResponse(status: 200, body: balanceBody) }

        let container = AppContainer(credentials: store, transport: transport)
        let saved = container.model.saveDeepSeekKey("sk-production-root-test")
        XCTAssertTrue(saved, "the production save path must report success to the caller")

        XCTAssertEqual(store.load(.deepseekAPIKey), .available("sk-production-root-test"),
                       "the key must reach the container's own credential store")

        let feedback = await waitForFeedback(on: container.model, .deepseek,
                                             equals: .connected(platform: .deepseek))
        XCTAssertEqual(feedback, .connected(platform: .deepseek),
                       "a successful verification must end in the explicit connected state")

        let report = container.model.providerReports.first { $0.platform == .deepseek }
        XCTAssertEqual(report?.connection, .connected)
        XCTAssertEqual(report?.balances.first?.currency, "CNY")
        XCTAssertEqual(report?.balances.first?.total,
                       Decimal(string: "110.00", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertNotNil(report?.lastSuccessAt)

        // Verification went to the official read-only balance endpoint only, with the key.
        let requests = transport.recordedRequests
        XCTAssertFalse(requests.isEmpty, "saving must trigger an immediate verification")
        for request in requests {
            XCTAssertEqual(request.url?.host, "api.deepseek.com")
            XCTAssertEqual(request.url?.path, "/user/balance")
            XCTAssertFalse(ProviderRequestGuard.isModelEndpoint(path: request.url?.path ?? ""),
                           "verification must never be a model call")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-production-root-test")
        }
    }

    // MARK: - ViewModel feedback states

    func testSavingAKeyImmediatelyEntersTheVerifyingState() async throws {
        let transport = StubTransport()
        transport.handler = { [balanceBody] _ in ProviderHTTPResponse(status: 200, body: balanceBody) }
        let model = makeModel(transport: transport, credentials: InMemoryCredentialStore())

        let saved = model.saveDeepSeekKey("sk-test")
        XCTAssertTrue(saved)
        // Synchronous part of the flow has already reported "stored, verifying now".
        XCTAssertEqual(model.credentialFeedback(for: .deepseek), .verifying(platform: .deepseek),
                       "the click must show feedback immediately, not after the round trip")

        let feedback = await waitForFeedback(on: model, .deepseek, equals: .connected(platform: .deepseek))
        XCTAssertEqual(feedback, .connected(platform: .deepseek))
    }

    func testAKeychainSaveFailureIsReportedAndStopsBeforeAnyNetworkCall() async throws {
        let transport = StubTransport()
        let failingStore = FailingSaveCredentialStore()
        let model = makeModel(transport: transport, credentials: failingStore)

        let saved = model.saveDeepSeekKey("sk-test")
        XCTAssertFalse(saved, "the caller must learn the save failed so the input can stay")

        XCTAssertEqual(model.credentialFeedback(for: .deepseek), .saveFailed(platform: .deepseek),
                       "a keychain error must surface in the UI, not only in the log")
        XCTAssertTrue(transport.recordedRequests.isEmpty,
                      "nothing was stored, so there is nothing to verify")
    }

    func testARejectedKeyIsReportedAsInvalid() async throws {
        let transport = StubTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }
        let model = makeModel(transport: transport, credentials: InMemoryCredentialStore())

        let saved = model.saveDeepSeekKey("sk-rejected")
        XCTAssertTrue(saved, "the keychain accepted the key; the rejection is a verification result")

        let feedback = await waitForFeedback(on: model, .deepseek, equals: .invalidCredential(platform: .deepseek))
        XCTAssertEqual(feedback, .invalidCredential(platform: .deepseek),
                       "401 must be shown as an invalid key, never as a network problem")
        XCTAssertEqual(model.providerReports.first { $0.platform == .deepseek }?.connection, .authSuspended)
    }

    func testANetworkFailureKeepsTheKeySavedAndSaysSo() async throws {
        let transport = StubTransport()
        transport.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = InMemoryCredentialStore()
        let model = makeModel(transport: transport, credentials: store)

        let saved = model.saveDeepSeekKey("sk-offline")
        XCTAssertTrue(saved)
        XCTAssertEqual(store.load(.deepseekAPIKey), .available("sk-offline"),
                       "a network failure after a successful save must not lose the key")

        let feedback = await waitForFeedback(on: model, .deepseek, equals: .savedUnverified(platform: .deepseek))
        XCTAssertEqual(feedback, .savedUnverified(platform: .deepseek),
                       "offline must read as stored-but-unverified, never as an invalid key")
        let report = model.providerReports.first { $0.platform == .deepseek }!
        XCTAssertEqual(report.connection, .unavailable)
        XCTAssertTrue(report.balances.isEmpty,
                      "a failed verification must not display any amount")
    }

    func testDeleteClearsCredentialCacheSuspensionAndReportsIt() async throws {
        let transport = StubTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }
        let store = InMemoryCredentialStore()
        let model = makeModel(transport: transport, credentials: store)

        _ = model.saveDeepSeekKey("sk-to-delete")
        _ = await waitForFeedback(on: model, .deepseek, equals: .invalidCredential(platform: .deepseek))
        XCTAssertTrue(model.providerEngine.isAuthSuspended(.deepseek))

        transport.handler = { [balanceBody] _ in ProviderHTTPResponse(status: 200, body: balanceBody) }
        let deleted = model.deleteDeepSeekKey()
        XCTAssertTrue(deleted)

        XCTAssertEqual(model.credentialFeedback(for: .deepseek), .deleted(platform: .deepseek),
                       "deletion must be visible, not silent")
        XCTAssertEqual(store.load(.deepseekAPIKey), .missing, "the key must be gone")
        XCTAssertEqual(model.providerReports.first { $0.platform == .deepseek }?.connection, .notConfigured)
        XCTAssertTrue(model.providerReports.first { $0.platform == .deepseek }!.balances.isEmpty,
                      "the cached balance must be cleared with the credential")
        XCTAssertFalse(model.providerEngine.isAuthSuspended(.deepseek),
                       "the auth suspension must be cleared with the credential")
    }

    func testSavingAGLMKeyEndsInTheConnectedStateThroughTheBalanceEndpoint() async throws {
        let transport = StubTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"data":{"total_balance":"100.00","available_balance":"88.00","currency":"CNY"}}"#.utf8))
        }
        let model = makeModel(transport: transport, credentials: InMemoryCredentialStore())

        let saved = model.saveGLMAPIKey("glm-test")
        XCTAssertTrue(saved)

        let feedback = await waitForFeedback(on: model, .glm, equals: .connected(platform: .glm))
        XCTAssertEqual(feedback, .connected(platform: .glm),
                       "a clean parse under the confirmed balance schema is a real connection")
        let report = model.providerReports.first { $0.platform == .glm }!
        XCTAssertEqual(report.connection, .connected)
        XCTAssertEqual(report.balances.first?.available,
                       Decimal(string: "88.00", locale: Locale(identifier: "en_US_POSIX")))
        for request in transport.recordedRequests {
            XCTAssertFalse(ProviderRequestGuard.isModelEndpoint(path: request.url?.path ?? ""),
                           "no model call may ever be made with the key")
        }
    }
}

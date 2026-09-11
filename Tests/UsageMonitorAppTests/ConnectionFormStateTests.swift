import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// The collapsible connection-form rules, testable without AppKit (Round 7 requirement 5):
/// - a successful keychain write clears the draft and collapses the form,
/// - a failed write keeps the draft and the expanded form for retry,
/// - the verification feedback is visible after the form has collapsed,
/// - an auth failure keeps the form re-expandable so the key can be replaced,
/// - background refreshes never disturb the draft while typing.
@MainActor
final class ConnectionFormStateTests: XCTestCase {

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

        private func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
        }
    }

    final class FailingSaveCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
        func save(_ secret: String, for key: ProviderCredentialKey) throws { throw ProviderFailure.other }
        func load(_ key: ProviderCredentialKey, interaction: CredentialInteraction) -> CredentialAccessOutcome {
            return .missing
        }
        func delete(_ key: ProviderCredentialKey) throws {}
    }

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

    private func makeModel(transport: StubTransport, credentials: ProviderCredentialStoring) -> UsageViewModel {
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

    private let balanceBody = Data("""
    {"is_available": true, "balance_infos": [{"currency": "CNY", "total_balance": "110.00"}]}
    """.utf8)

    func testASuccessfulSaveClearsTheDraftAndCollapsesTheForm() async throws {
        let transport = StubTransport()
        transport.handler = { [balanceBody] _ in ProviderHTTPResponse(status: 200, body: balanceBody) }
        let model = makeModel(transport: transport, credentials: InMemoryCredentialStore())
        let form = ConnectionFormState(model: model, platform: .deepseek)
        form.isExpanded = true
        form.draft = "sk-form-test"

        let saved = form.save()

        XCTAssertTrue(saved)
        XCTAssertTrue(form.draft.isEmpty, "the input clears only after the keychain accepted the key")
        XCTAssertFalse(form.isExpanded, "the form collapses so no empty input area remains")
        // The feedback stays visible in the section after the collapse.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && model.credentialFeedback(for: .deepseek) != .connected(platform: .deepseek) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.credentialFeedback(for: .deepseek), .connected(platform: .deepseek),
                       "the collapsed section keeps showing the verification state")
    }

    func testAFailedSaveKeepsTheDraftAndTheExpandedForm() {
        let transport = StubTransport()
        let model = makeModel(transport: transport, credentials: FailingSaveCredentialStore())
        let form = ConnectionFormState(model: model, platform: .deepseek)
        form.isExpanded = true
        form.draft = "sk-keep-me"

        let saved = form.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(form.draft, "sk-keep-me", "the input stays for retry")
        XCTAssertTrue(form.isExpanded, "the form stays open for retry")
        XCTAssertEqual(model.credentialFeedback(for: .deepseek), .saveFailed(platform: .deepseek))
        XCTAssertTrue(transport.recordedRequests.isEmpty)
    }

    func testAnAuthFailureLeavesTheFormReexpandable() async throws {
        let transport = StubTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }
        let model = makeModel(transport: transport, credentials: InMemoryCredentialStore())
        let form = ConnectionFormState(model: model, platform: .deepseek)
        form.draft = "sk-rejected"
        _ = form.save()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && model.credentialFeedback(for: .deepseek) != .invalidCredential(platform: .deepseek) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // The user can re-open the collapsed form and replace the key.
        form.toggle()
        XCTAssertTrue(form.isExpanded)
        form.draft = "sk-replacement"
        XCTAssertTrue(form.canSave)
    }

    func testDeletingClearsTheDraftAndReportsDeletion() {
        let transport = StubTransport()
        let store = InMemoryCredentialStore()
        let model = makeModel(transport: transport, credentials: store)
        let form = ConnectionFormState(model: model, platform: .deepseek)
        form.draft = "sk-to-delete"

        form.deleteCredential()

        XCTAssertTrue(form.draft.isEmpty)
        XCTAssertEqual(model.credentialFeedback(for: .deepseek), .deleted(platform: .deepseek))
        XCTAssertEqual(store.load(.deepseekAPIKey), .missing)
    }

    /// A background balance refresh must not touch the form state: the draft and the
    /// expansion survive `objectWillChange` storms from refresh cycles.
    func testBackgroundRefreshDoesNotDisturbTheDraft() async throws {
        let transport = StubTransport()
        transport.handler = { [balanceBody] _ in ProviderHTTPResponse(status: 200, body: balanceBody) }
        let model = makeModel(transport: transport, credentials: InMemoryCredentialStore())
        let form = ConnectionFormState(model: model, platform: .deepseek)
        form.draft = "sk-typing"
        form.isExpanded = true

        model.refreshNow()   // fires provider refreshes; the form is not part of that state

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(form.draft, "sk-typing")
        XCTAssertTrue(form.isExpanded)
    }
}

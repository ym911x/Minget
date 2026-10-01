import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

@MainActor
final class ManagedAccountTests: XCTestCase {
    final class Transport: ProviderTransport, @unchecked Sendable {
        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            let total = request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-first" ? "10.00" : "20.00"
            return ProviderHTTPResponse(status: 200, body: Data("{\"is_available\":true,\"balance_infos\":[{\"currency\":\"CNY\",\"total_balance\":\"\(total)\",\"granted_balance\":\"0.00\",\"topped_up_balance\":\"\(total)\"}]}".utf8))
        }
    }
    private func makeModel(_ defaults: UserDefaults, store: ProviderCredentialStoring = InMemoryCredentialStore(), transport: ProviderTransport = Transport()) throws -> UsageViewModel {
        let registry = try AccountRegistry(defaults: defaults)
        let model = UsageViewModel(coordinator: CodexProfilesCoordinator(profiles: []), providerEngine: ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults)),
            menuBarPreferences: MenuBarPreferences(defaults: defaults), displayNames: DisplayNamePreferences(defaults: defaults), fireSchedules: FireSchedulePreferences(defaults: defaults), fireConfirmDelay: 0, fireRetryDelay: 0)
        model.installAccountManagement(registry: registry, credentials: store, transport: transport, defaults: defaults)
        return model
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(predicate())
    }
    func testTwoAPIConnectionsUseDifferentKeysCachesAndPersistAcrossRestart() async throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, store = InMemoryCredentialStore()
        let model = try makeModel(d, store: store), registry = try XCTUnwrap(model.accountRegistry)
        let first = registry.draft(.deepseek, name: "工作")
        XCTAssertTrue(model.saveManagedAPI(first, key: "synthetic-first"))
        let other = registry.draft(.deepseek, name: "个人")
        XCTAssertTrue(model.saveManagedAPI(other, key: "synthetic-second"))
        try await waitUntil { model.managedAPIStates.count == 2 && model.managedAPIStates.allSatisfy { $0.report.connection == .connected } }
        XCTAssertEqual(model.managedAPIStates[0].report.balances.first?.total, 10)
        XCTAssertEqual(model.managedAPIStates[1].report.balances.first?.total, 20)
        let restarted = try makeModel(d, store: store)
        XCTAssertEqual(restarted.managedAccounts.count, 2)
        XCTAssertEqual(restarted.managedAPIStates.map { $0.report.connection }, [.stale, .stale])
        XCTAssertEqual(restarted.managedAPIStates[1].report.balances.first?.total, 20)
        XCTAssertFalse(restarted.saveManagedAPI(registry.draft(.deepseek), key: "synthetic-first"))
        XCTAssertEqual(restarted.managedAccounts.count, 2)
    }
    func testRemoveSelectedAPIConnectionPreservesOtherAndRequiresExplicitSelection() async throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, store = InMemoryCredentialStore()
        let model = try makeModel(d, store: store), registry = try XCTUnwrap(model.accountRegistry)
        let a = registry.draft(.deepseek); XCTAssertTrue(model.saveManagedAPI(a, key: "synthetic-first"))
        let b = registry.draft(.deepseek); XCTAssertTrue(model.saveManagedAPI(b, key: "synthetic-second"))
        try await waitUntil { model.managedAPIStates.allSatisfy { $0.report.connection == .connected } }
        model.menuBarPreferences.selection = .apiAccount(a.id)
        model.removeManagedAccount(a.id)
        try await waitUntil { model.managedAccounts.count == 1 }
        XCTAssertEqual(model.managedAccounts.first?.id, b.id)
        XCTAssertEqual(model.menuBarPreferences.selection, .apiAccount(a.id))
        XCTAssertEqual(model.menuBarContent(for: .full).text, "账号已移除，请重新选择")
        XCTAssertTrue(store.load(.init(rawValue: b.credentialAccount!), interaction: .disallowed).isAvailable)
        XCTAssertTrue(store.load(.init(rawValue: a.credentialAccount!), interaction: .disallowed).isMissing)
    }
    func testDynamicSchedulesStartDisabledAndRemoveOnlyTargetEntries() throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, prefs = FireSchedulePreferences(defaults: d)
        let target = FireScheduleTarget(rawValue: "chatgpt-third"), other = FireScheduleTarget.commandCode
        let id = prefs.add(target: target), otherID = prefs.add(target: other)
        XCTAssertFalse(try XCTUnwrap(prefs.entries.first { $0.id == id }).isEnabled)
        prefs.setEnabled(true, for: id); prefs.removeAccount(target.rawValue)
        XCTAssertEqual(prefs.entries.map(\.id), [otherID])
        XCTAssertEqual(FireSchedulePreferences(defaults: d).entries.map(\.target), [other])
    }
    func testRemovedChatGPTSelectionSurvivesRestartButUnknownSourceStillFallsBack() throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, registry = try AccountRegistry(defaults: d)
        let row = registry.draft(.chatGPT); try registry.upsert(row)
        let preferences = MenuBarPreferences(defaults: d); preferences.selection = .profile(row.id)
        XCTAssertEqual(MenuBarPreferences(defaults: d).selection, .profile(row.id))
        try registry.remove(row.id)
        XCTAssertEqual(MenuBarPreferences(defaults: d).selection, .profile(row.id))
        d.set("chatgpt-unknown", forKey: "menubar.source.v1")
        XCTAssertEqual(MenuBarPreferences(defaults: d).selection, .profile("chatgpt-a"))
    }
    final class DeleteFailureStore: ProviderCredentialStoring, @unchecked Sendable {
        let backing = InMemoryCredentialStore()
        private let lock = NSLock()
        private var fail = true
        func allowDeletion() { lock.lock(); fail = false; lock.unlock() }
        func save(_ secret: String, for key: ProviderCredentialKey) throws { try backing.save(secret, for: key) }
        func load(_ key: ProviderCredentialKey, interaction: CredentialInteraction) -> CredentialAccessOutcome { backing.load(key, interaction: interaction) }
        func delete(_ key: ProviderCredentialKey) throws { lock.lock(); let shouldFail = fail; lock.unlock(); if shouldFail { throw ProviderFailure.other }; try backing.delete(key) }
    }
    func testFailedRemovalKeepsStoppedRowAndCanRetryWithoutTouchingAnotherAccount() async throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, store = DeleteFailureStore()
        let model = try makeModel(d, store: store), registry = try XCTUnwrap(model.accountRegistry)
        let row = registry.draft(.deepseek); XCTAssertTrue(model.saveManagedAPI(row, key: "synthetic-first"))
        try await waitUntil { model.managedAPIStates.first?.report.connection == .connected }
        model.removeManagedAccount(row.id)
        try await waitUntil { model.accountMessage.hasPrefix("移除未完成") }
        XCTAssertEqual(registry.account(row.id)?.removalPending, true)
        XCTAssertTrue(store.backing.load(.init(rawValue: row.credentialAccount!), interaction: .disallowed).isAvailable)
        store.allowDeletion(); model.removeManagedAccount(row.id)
        try await waitUntil { model.managedAccounts.isEmpty }
    }
    func testCommandCodeAccountsHaveIndependentFireStateAndSerializeFakeCLI() async throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, store = InMemoryCredentialStore()
        let model = try makeModel(d, store: store), registry = try XCTUnwrap(model.accountRegistry)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-command-code")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let a = registry.draft(.commandcode); XCTAssertTrue(model.saveManagedAPI(a, key: "synthetic-first"))
        let b = registry.draft(.commandcode); XCTAssertTrue(model.saveManagedAPI(b, key: "synthetic-second"))
        for row in [a, b] {
            let previous = try XCTUnwrap(model.apiRuntimes[row.id])
            model.apiRuntimes[row.id] = APIAccountRuntime(account: row, credentials: store, transport: Transport(), defaults: d, legacyEngine: previous.engine,
                fireService: CommandCodeFireService(locator: { _ in executable }, workingDirectoryBase: root))
        }
        XCTAssertTrue(model.fireManagedCommandCode(id: a.id)); XCTAssertFalse(model.fireManagedCommandCode(id: b.id))
        try await waitUntil { model.managedCommandFireState(a.id).result != nil }
        XCTAssertNil(model.managedCommandFireState(b.id).result)
        XCTAssertTrue(model.fireManagedCommandCode(id: b.id))
        try await waitUntil { model.managedCommandFireState(b.id).result != nil }
        XCTAssertTrue(model.fireSchedules.entries.isEmpty)
    }
    func testAddingDraftDoesNotPersistCancelledAccountOrEnableFire() throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, model = try makeModel(d)
        _ = model.accountRegistry?.draft(.commandcode)
        XCTAssertTrue(model.managedAccounts.isEmpty); XCTAssertTrue(model.scheduleTargets.isEmpty)
        XCTAssertTrue(model.fireSchedules.entries.isEmpty)
    }
    func testInvalidAccountMetadataDoesNotSaveOrReplaceAKey() throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, store = InMemoryCredentialStore()
        let model = try makeModel(d, store: store), registry = try XCTUnwrap(model.accountRegistry)
        var row = registry.draft(.deepseek)
        row.name = String(repeating: "长", count: 41)
        XCTAssertFalse(model.saveManagedAPI(row, key: "synthetic-first"))
        XCTAssertTrue(store.load(.init(rawValue: row.credentialAccount!), interaction: .disallowed).isMissing)
        XCTAssertTrue(registry.accounts.isEmpty)
    }
    func testWindowHeightTracksAccountCountAndCapsAtScreenViewport() throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, model = try makeModel(d)
        let registry = try XCTUnwrap(model.accountRegistry)
        XCTAssertEqual(UsagePanelView.presentationHeight(model: model), 260)
        try registry.upsert(registry.draft(.deepseek)); model.reloadManagedAccounts()
        XCTAssertLessThan(UsagePanelView.presentationHeight(model: model), 640)
        for _ in 0..<4 { try registry.upsert(registry.draft(.chatGPT)) }
        model.reloadManagedAccounts()
        XCTAssertEqual(UsagePanelView.presentationHeight(model: model), 640)
        XCTAssertEqual(StatusItemController.panelSize(for: DetailPreferences.shared, visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400), model: model).height, 384)
    }
    actor HeldReadTransport: ProviderTransport {
        var waiting: CheckedContinuation<Void, Never>?
        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            let held = request.value(forHTTPHeaderField: "Authorization") == "Bearer holding-first"
            if held { await withCheckedContinuation { waiting = $0 } }
            let total = held ? "99.00" : "20.00"
            return ProviderHTTPResponse(status: 200, body: Data("{\"is_available\":true,\"balance_infos\":[{\"currency\":\"CNY\",\"total_balance\":\"\(total)\",\"granted_balance\":\"0.00\",\"topped_up_balance\":\"\(total)\"}]}".utf8))
        }
        var isWaiting: Bool { waiting != nil }
        func release() { waiting?.resume(); waiting = nil }
    }
    private func waitForHeldRead(_ transport: HeldReadTransport) async throws {
        for _ in 0..<300 {
            if await transport.isWaiting { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected held request")
    }
    func testRemovedAccountRejectsLateResponseWithoutChangingAnotherAccount() async throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, transport = HeldReadTransport()
        let model = try makeModel(d, transport: transport), registry = try XCTUnwrap(model.accountRegistry)
        let a = registry.draft(.deepseek); XCTAssertTrue(model.saveManagedAPI(a, key: "holding-first"))
        try await waitForHeldRead(transport)
        let b = registry.draft(.deepseek); XCTAssertTrue(model.saveManagedAPI(b, key: "synthetic-second"))
        try await waitUntil { model.managedAPIStates.first { $0.id == b.id }?.report.connection == .connected }
        model.removeManagedAccount(a.id); try await waitUntil { model.managedAccounts.count == 1 }
        await transport.release(); try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.managedAPIStates.map(\.id), [b.id])
        XCTAssertEqual(model.managedAPIStates.first?.report.balances.first?.total, 20)
        XCTAssertNil(ProviderCache(userDefaults: d, namespace: a.id).load(platform: .deepseek, accountID: DeepSeekProvider.accountFingerprint(forAPIKey: "holding-first")))
    }
    func testReplacingCredentialRejectsLateOldResponseForTheSameInstance() async throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, transport = HeldReadTransport()
        let model = try makeModel(d, transport: transport), registry = try XCTUnwrap(model.accountRegistry)
        let row = registry.draft(.deepseek); XCTAssertTrue(model.saveManagedAPI(row, key: "holding-first"))
        try await waitForHeldRead(transport)
        XCTAssertTrue(model.saveManagedAPI(try XCTUnwrap(registry.account(row.id)), key: "synthetic-second"))
        await transport.release()
        try await waitUntil { model.managedAPIStates.first?.report.connection == .connected }
        XCTAssertEqual(model.managedAPIStates.first?.report.accountID, DeepSeekProvider.accountFingerprint(forAPIKey: "synthetic-second"))
        XCTAssertEqual(model.managedAPIStates.first?.report.balances.first?.total, 20)
    }
    func testMigratedAPIInstanceRestoresItsLegacyCacheWhileAwaitingRefresh() throws {
        let d = UserDefaults(suiteName: "ManagedAccountTests." + UUID().uuidString)!, store = InMemoryCredentialStore()
        let registry = try AccountRegistry(defaults: d, legacy: true)
        var row = try XCTUnwrap(registry.account("deepseek")); row.keyFingerprint = "known-identity"; try registry.upsert(row)
        let cache = ProviderCache(userDefaults: d)
        cache.save(platform: .deepseek, accountID: "known-identity", balances: [ProviderBalance(currency: "CNY", total: 10)], lastSuccessAt: Date())
        let reader = DeepSeekReading(provider: DeepSeekProvider(transport: Transport()), credentials: store)
        let engine = ProviderRefreshEngine(readers: [reader], cache: cache)
        let runtime = APIAccountRuntime(account: row, credentials: store, transport: Transport(), defaults: d, legacyEngine: engine)
        XCTAssertEqual(runtime.engine.report(for: .deepseek).connection, .stale)
        XCTAssertEqual(runtime.engine.report(for: .deepseek).balances.first?.total, 10)
        XCTAssertTrue(runtime.engine === engine)
    }
}

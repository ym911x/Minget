import XCTest
@testable import UsageMonitorCore

final class AccountRegistryTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "AccountRegistryTests." + UUID().uuidString)! }
    func testLegacyMigrationKeepsIDsPathsCredentialsNamesAndIsIdempotent() throws {
        let d = defaults(); d.set(["chatgpt-a": "工作账号", "deepseek": "DeepSeek 工作"], forKey: "detail.displayNames.v1")
        let uuid = UUID(), google = AntigravityConnection(slot: .a, uuid: uuid, email: "a@example.com", sourceVersion: AntigravityCLILocator.version)
        let registry = try AccountRegistry(defaults: d, legacy: true, googleConnections: [google])
        XCTAssertEqual(registry.account("chatgpt-a")?.codexHomeRelativePath, ".codex-minget-a")
        XCTAssertEqual(registry.account("chatgpt-a")?.name, "工作账号")
        XCTAssertEqual(registry.account("deepseek")?.credentialAccount, "deepseek.api-key")
        XCTAssertEqual(registry.account("google-A")?.googleUUID, uuid)
        try registry.remove("chatgpt-b")
        let second = try AccountRegistry(defaults: d, legacy: true, googleConnections: [google])
        XCTAssertNil(second.account("chatgpt-b")); XCTAssertEqual(second.accounts.count, 4)
        XCTAssertTrue(AccountRegistry.storedProfileIDs(defaults: d).contains("chatgpt-b"))
    }
    func testFreshInstallStartsEmptyAndOrdinalsNeverReuseRemovedAccounts() throws {
        let registry = try AccountRegistry(defaults: defaults())
        XCTAssertTrue(registry.accounts.isEmpty)
        for number in 1...4 {
            let row = registry.draft(.chatGPT)
            XCTAssertEqual(row.ordinal, number); try registry.upsert(row)
        }
        let last = try XCTUnwrap(registry.accounts.last); try registry.remove(last.id)
        XCTAssertEqual(registry.draft(.chatGPT).ordinal, 5)
    }
    func testRegistryRejectsCredentialAliasAndUnsafePathWithoutClobberingBaseline() throws {
        let registry = try AccountRegistry(defaults: defaults(), legacy: true)
        var row = registry.draft(.deepseek); row.credentialAccount = "commandcode.api-key"
        XCTAssertThrowsError(try registry.upsert(row)); XCTAssertEqual(registry.accounts.count, 4)
        var profile = registry.draft(.chatGPT); profile.codexHomeRelativePath = ".codex"
        XCTAssertThrowsError(try registry.upsert(profile)); XCTAssertEqual(registry.accounts.count, 4)
        profile.codexHomeRelativePath = ".codex-minget-a"
        XCTAssertThrowsError(try registry.upsert(profile)); XCTAssertEqual(registry.accounts.count, 4)
    }
    func testGoogleFourProfilesPersistAndRemovingOnePreservesOthers() throws {
        let d = defaults(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try AccountRegistry(defaults: d), store = AntigravityProfileStore(base: root, registry: registry)
        var connections: [AntigravityConnection] = []
        for number in 1...4 {
            let draft = registry.draft(.google), uuid = UUID(); store.pendingAccount = draft
            try store.prepare(uuid)
            let connection = try store.commit(slot: .init(rawValue: draft.googleSlot!), uuid: uuid, email: "google\(number)@example.com")
            connections.append(connection)
        }
        XCTAssertEqual(try store.connections().count, 4)
        XCTAssertEqual(try AccountRegistry(defaults: d).accounts.count, 4)
        try store.disconnect(connections[2])
        XCTAssertEqual(try store.connections().count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.home(connections[1].uuid).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.home(connections[2].uuid).path))
    }
    func testGoogleDuplicateIdentityDoesNotReplaceExistingConnection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try AccountRegistry(defaults: defaults()), store = AntigravityProfileStore(base: root, registry: registry)
        var draft = registry.draft(.google), uuid = UUID(); store.pendingAccount = draft; try store.prepare(uuid)
        let original = try store.commit(slot: .init(rawValue: draft.googleSlot!), uuid: uuid, email: "same@example.com")
        draft = registry.draft(.google); uuid = UUID(); store.pendingAccount = draft; try store.prepare(uuid)
        XCTAssertThrowsError(try store.commit(slot: .init(rawValue: draft.googleSlot!), uuid: uuid, email: "SAME@example.com"))
        XCTAssertEqual(try store.connections(), [original])
    }
    func testCacheNamespacesPreventSameIdentitySharingAndBroadRemoval() {
        let d = defaults(), a = ProviderCache(userDefaults: d, namespace: "a"), b = ProviderCache(userDefaults: d, namespace: "b")
        let balance = ProviderBalance(currency: "CNY", total: 10)
        a.save(platform: .deepseek, accountID: "same", balances: [balance], lastSuccessAt: Date())
        XCTAssertNil(b.load(platform: .deepseek, accountID: "same"))
        b.save(platform: .deepseek, accountID: "same", balances: [balance], lastSuccessAt: Date())
        a.clear(platform: .deepseek)
        XCTAssertNotNil(b.load(platform: .deepseek, accountID: "same"))
    }
    func testDynamicChatGPTThirdFourthProfilesHaveIsolatedHomesAndCanDetachIndependently() throws {
        let registry = try AccountRegistry(defaults: defaults(), legacy: true)
        let coordinator = CodexProfilesCoordinator(profiles: registry.accounts.compactMap(\.profile))
        defer { coordinator.stop() }
        let third = registry.draft(.chatGPT); try registry.upsert(third); coordinator.add(third.profile!)
        let fourth = registry.draft(.chatGPT); try registry.upsert(fourth); coordinator.add(fourth.profile!)
        XCTAssertEqual(coordinator.profileIDs.count, 4)
        XCTAssertNotEqual(coordinator.childEnvironment(for: third.id)?["CODEX_HOME"], coordinator.childEnvironment(for: fourth.id)?["CODEX_HOME"])
        _ = coordinator.detach(third.id)
        XCTAssertNotNil(coordinator.runtime(for: fourth.id)); XCTAssertNil(coordinator.runtime(for: third.id))
    }
    func testClearingOneProfileKeepsOtherLastKnownIdentity() {
        let cache = UsageCache(userDefaults: defaults())
        cache.saveLastKnownAccountID("a@example.com", profileID: "a")
        cache.saveLastKnownAccountID("b@example.com", profileID: "b")
        cache.clearProfile("a")
        XCTAssertNil(cache.loadLastKnownAccountID(profileID: "a"))
        XCTAssertEqual(cache.loadLastKnownAccountID(profileID: "b"), "b@example.com")
    }
    func testCorruptRegistryDoesNotResetOrOverwriteMetadata() {
        let d = defaults(), bytes = Data("invalid registry".utf8); d.set(bytes, forKey: AccountRegistry.storageKey)
        XCTAssertThrowsError(try AccountRegistry(defaults: d, legacy: true))
        XCTAssertEqual(d.data(forKey: AccountRegistry.storageKey), bytes)
    }
}

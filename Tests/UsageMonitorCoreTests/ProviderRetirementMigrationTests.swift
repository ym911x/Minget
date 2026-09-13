import XCTest
@testable import UsageMonitorCore

final class ProviderRetirementMigrationTests: XCTestCase {
    private struct LegacyStore: Codable {
        let entries: [String: ProviderCacheEntry]
    }

    private let cacheStorageKey = "UsageMonitor.providerBalances.v2"
    final class Store: ProviderCredentialStoring, @unchecked Sendable {
        var attempts = 0
        var shouldFail = false
        func save(_ secret: String, for key: ProviderCredentialKey) throws {}
        func load(_ key: ProviderCredentialKey, interaction: CredentialInteraction) -> CredentialAccessOutcome { .missing }
        func delete(_ key: ProviderCredentialKey) throws {}
        func deleteRetiredGLMCredentials() throws {
            attempts += 1
            if shouldFail { throw ProviderFailure.other }
        }
    }
    private func defaults() -> UserDefaults {
        let name = "ProviderRetirementMigrationTests." + UUID().uuidString
        let value = UserDefaults(suiteName: name)!; value.removePersistentDomain(forName: name); return value
    }
    func testSuccessfulMigrationRemovesRawGLMCacheKeepsDeepSeekAndIsIdempotent() throws {
        let defaults = defaults(); let cache = ProviderCache(userDefaults: defaults); let store = Store()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let deepSeek = ProviderCacheEntry(accountID: "deepseek-account", balances: [
            PersistedBalance(currency: "CNY", total: "1.25", available: "1.00",
                             granted: "0.25", toppedUp: "1.00")
        ], lastSuccessAt: timestamp)
        let retiredGLM = ProviderCacheEntry(accountID: "retired-account", balances: [
            PersistedBalance(currency: "CNY", total: "9.00", granted: nil, toppedUp: nil)
        ], lastSuccessAt: timestamp)
        let raw = try JSONEncoder().encode(LegacyStore(entries: [
            "deepseek#deepseek-account": deepSeek,
            "glm#retired-account": retiredGLM,
        ]))
        defaults.set(raw, forKey: cacheStorageKey)
        defaults.set("legacy", forKey: "UsageMonitor.glm.connectionMode")
        defaults.set(true, forKey: "detail.showGLM")
        let migration = ProviderRetirementMigration(credentials: store, cache: cache, defaults: defaults)
        migration.run()
        migration.run()

        XCTAssertEqual(store.attempts, 1)
        XCTAssertEqual(cache.allKeys(), ["deepseek#deepseek-account"])
        XCTAssertEqual(cache.load(platform: .deepseek, accountID: "deepseek-account"), deepSeek)
        let rewritten = try XCTUnwrap(defaults.data(forKey: cacheStorageKey))
        XCTAssertEqual(try JSONDecoder().decode(LegacyStore.self, from: rewritten).entries,
                       ["deepseek#deepseek-account": deepSeek])
        XCTAssertNil(defaults.object(forKey: "UsageMonitor.glm.connectionMode"))
        XCTAssertNil(defaults.object(forKey: "detail.showGLM"))
    }
    func testFailureDoesNotClearPreferencesAndRetries() {
        let defaults = defaults(); let cache = ProviderCache(userDefaults: defaults); let store = Store(); store.shouldFail = true
        defaults.set(true, forKey: "detail.showGLM")
        let migration = ProviderRetirementMigration(credentials: store, cache: cache, defaults: defaults)
        migration.run(); migration.run()
        XCTAssertEqual(store.attempts, 2)
        XCTAssertNotNil(defaults.object(forKey: "detail.showGLM"))
    }
}

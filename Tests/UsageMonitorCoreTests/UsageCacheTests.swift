import XCTest
@testable import UsageMonitorCore

/// Profile-level cache isolation and the one-time 1.2.1 -> 1.3.0 migration
/// (REQUIREMENTS.md §4.3, IMPLEMENTATION_TASKS.md §1.3).
///
/// The migration rules are the sharpest part of this version: a wrong copy would show one
/// account's numbers behind the other's name, so each branch is pinned separately.
final class UsageCacheTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageMonitorCacheTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func snapshot(fiveHourUsed: Double = 25, weeklyUsed: Double = 58) -> UsageSnapshot {
        UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                usedPercent: fiveHourUsed,
                                                remainingPercent: 100 - fiveHourUsed,
                                                resetsAt: Date(timeIntervalSince1970: 1_788_935_373)),
                      weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                              usedPercent: weeklyUsed,
                                              remainingPercent: 100 - weeklyUsed,
                                              resetsAt: Date(timeIntervalSince1970: 1_789_453_767)),
                      fetchedAt: Date(timeIntervalSince1970: 1_788_935_000),
                      source: .codexAppServer)
    }

    // MARK: - Profile + account isolation

    func testSnapshotsAreIsolatedPerProfileAndPerAccount() {
        let cache = UsageCache(userDefaults: makeDefaults())
        cache.save(snapshot(fiveHourUsed: 11), profileID: "chatgpt-a", accountID: "a@example.invalid")
        cache.save(snapshot(fiveHourUsed: 22), profileID: "chatgpt-b", accountID: "b@example.invalid")
        cache.save(snapshot(fiveHourUsed: 33), profileID: "chatgpt-a", accountID: nil)

        XCTAssertEqual(cache.load(profileID: "chatgpt-a", accountID: "a@example.invalid")?.fiveHour?.usedPercent, 11)
        XCTAssertEqual(cache.load(profileID: "chatgpt-b", accountID: "b@example.invalid")?.fiveHour?.usedPercent, 22)

        // Neither account id resolves inside the other profile.
        XCTAssertNil(cache.load(profileID: "chatgpt-a", accountID: "b@example.invalid"),
                     "account B's snapshot must never appear under profile A")
        XCTAssertNil(cache.load(profileID: "chatgpt-b", accountID: "a@example.invalid"),
                     "account A's snapshot must never appear under profile B")

        // A known account is never served the profile's unattributed entry, and vice versa.
        XCTAssertEqual(cache.load(profileID: "chatgpt-a", accountID: nil)?.fiveHour?.usedPercent, 33)
        XCTAssertNotEqual(cache.load(profileID: "chatgpt-a", accountID: "a@example.invalid")?.fiveHour?.usedPercent, 33)
    }

    func testLastKnownAccountIsRememberedPerProfile() {
        let cache = UsageCache(userDefaults: makeDefaults())
        cache.saveLastKnownAccountID("a@example.invalid", profileID: "chatgpt-a")
        cache.saveLastKnownAccountID("b@example.invalid", profileID: "chatgpt-b")

        XCTAssertEqual(cache.loadLastKnownAccountID(profileID: "chatgpt-a"), "a@example.invalid")
        XCTAssertEqual(cache.loadLastKnownAccountID(profileID: "chatgpt-b"), "b@example.invalid")
        XCTAssertNil(cache.loadLastKnownAccountID(profileID: "chatgpt-c"))
        XCTAssertNil(cache.loadLastKnownAccountID(profileID: ""))
    }

    func testClearingOneProfileLeavesTheOtherIntact() {
        let cache = UsageCache(userDefaults: makeDefaults())
        cache.save(snapshot(), profileID: "chatgpt-a", accountID: "a@example.invalid")
        cache.save(snapshot(), profileID: "chatgpt-b", accountID: "b@example.invalid")

        XCTAssertTrue(cache.clear(profileID: "chatgpt-a", accountID: "a@example.invalid"))
        XCTAssertNil(cache.load(profileID: "chatgpt-a", accountID: "a@example.invalid"))
        XCTAssertNotNil(cache.load(profileID: "chatgpt-b", accountID: "b@example.invalid"))
        XCTAssertFalse(cache.clear(profileID: "chatgpt-a", accountID: "a@example.invalid"))
    }

    func testCacheKeysCannotCollideBetweenPairs() {
        XCTAssertNotEqual(UsageCache.profileCacheKey(profileID: "a", accountID: "b@example.invalid"),
                          UsageCache.profileCacheKey(profileID: "a\u{1F}b@example.invalid", accountID: nil))
    }

    // MARK: - 1.2.1 -> 1.3.0 migration

    /// Seeds the exact v2 layout 1.2.1 wrote: an account-keyed snapshot plus a single global
    /// "last account".
    private func seedLegacyV2Cache(_ cache: UsageCache, accountID: String, snapshot: UsageSnapshot) {
        cache.save(snapshot, accountID: accountID)
        cache.saveLastKnownAccountID(accountID)
    }

    func testLegacyCacheIsNotServedBeforeMigrationRuns() {
        let cache = UsageCache(userDefaults: makeDefaults())
        seedLegacyV2Cache(cache, accountID: "a@example.invalid", snapshot: snapshot(fiveHourUsed: 11))

        // A 1.3.0 profile read finds nothing: the v2 store is a different namespace.
        XCTAssertNil(cache.load(profileID: "chatgpt-a", accountID: "a@example.invalid"))
        XCTAssertNil(cache.load(profileID: "chatgpt-a", accountID: nil))
        XCTAssertNil(cache.loadLastKnownAccountID(profileID: "chatgpt-a"))
    }

    func testMigrationCopiesTheLegacyEntryWhenTheAccountIDIsIdentical() {
        let cache = UsageCache(userDefaults: makeDefaults())
        seedLegacyV2Cache(cache, accountID: "a@example.invalid", snapshot: snapshot(fiveHourUsed: 11))

        cache.migrateLegacyCacheIfNeeded(profileID: "chatgpt-a", resolvedAccountID: "a@example.invalid")

        XCTAssertEqual(cache.load(profileID: "chatgpt-a", accountID: "a@example.invalid")?.fiveHour?.usedPercent, 11,
                       "an identical account id is the only case that migrates")
        XCTAssertEqual(cache.loadLastKnownAccountID(profileID: "chatgpt-a"), "a@example.invalid")
        XCTAssertTrue(cache.hasCompletedLegacyMigration)
        // The v2 store is retired whether or not it migrated.
        XCTAssertNil(cache.load(accountID: "a@example.invalid"))
        XCTAssertNil(cache.loadLastKnownAccountID())
    }

    func testMigrationDeletesTheLegacyEntryWhenTheAccountIDDiffers() {
        let cache = UsageCache(userDefaults: makeDefaults())
        seedLegacyV2Cache(cache, accountID: "old@example.invalid", snapshot: snapshot(fiveHourUsed: 11))

        cache.migrateLegacyCacheIfNeeded(profileID: "chatgpt-a", resolvedAccountID: "new@example.invalid")

        XCTAssertNil(cache.load(profileID: "chatgpt-a", accountID: "new@example.invalid"),
                     "a different account id must not inherit the old account's numbers")
        XCTAssertNil(cache.load(profileID: "chatgpt-a", accountID: "old@example.invalid"))
        XCTAssertNil(cache.load(accountID: "old@example.invalid"), "the v2 entry must be deleted, not kept")
        XCTAssertTrue(cache.hasCompletedLegacyMigration)
    }

    func testMigrationDeletesTheLegacyEntryWhenNoAccountIDWasRecorded() {
        let cache = UsageCache(userDefaults: makeDefaults())
        cache.save(snapshot(fiveHourUsed: 11), accountID: "orphan@example.invalid")

        cache.migrateLegacyCacheIfNeeded(profileID: "chatgpt-a", resolvedAccountID: "a@example.invalid")

        XCTAssertNil(cache.load(profileID: "chatgpt-a", accountID: "a@example.invalid"))
        XCTAssertNil(cache.load(accountID: "orphan@example.invalid"))
        XCTAssertTrue(cache.hasCompletedLegacyMigration)
    }

    func testMigrationNeverTargetsAccountB() {
        let cache = UsageCache(userDefaults: makeDefaults())
        seedLegacyV2Cache(cache, accountID: "b@example.invalid", snapshot: snapshot(fiveHourUsed: 11))

        cache.migrateLegacyCacheIfNeeded(profileID: "chatgpt-b", resolvedAccountID: "b@example.invalid")

        XCTAssertNil(cache.load(profileID: "chatgpt-b", accountID: "b@example.invalid"),
                     "account B never receives the legacy cache, even on an exact id match")
        XCTAssertFalse(cache.hasCompletedLegacyMigration,
                       "and the migration stays pending, so account A can still run it")
        XCTAssertNotNil(cache.load(accountID: "b@example.invalid"), "the v2 entry is untouched by B's call")
    }

    func testMigrationRunsOnlyOnceAndNeverOverwritesNewerData() {
        let cache = UsageCache(userDefaults: makeDefaults())
        seedLegacyV2Cache(cache, accountID: "a@example.invalid", snapshot: snapshot(fiveHourUsed: 11))
        cache.migrateLegacyCacheIfNeeded(profileID: "chatgpt-a", resolvedAccountID: "a@example.invalid")

        // A real 1.3.0 read lands afterwards with a fresh value.
        cache.save(snapshot(fiveHourUsed: 77), profileID: "chatgpt-a", accountID: "a@example.invalid")
        cache.migrateLegacyCacheIfNeeded(profileID: "chatgpt-a", resolvedAccountID: "a@example.invalid")

        XCTAssertEqual(cache.load(profileID: "chatgpt-a", accountID: "a@example.invalid")?.fiveHour?.usedPercent, 77,
                       "the one-time migration must not re-run and clobber live data")
    }

    func testMigrationIgnoresAnEmptyResolvedAccountID() {
        let cache = UsageCache(userDefaults: makeDefaults())
        seedLegacyV2Cache(cache, accountID: "a@example.invalid", snapshot: snapshot())
        cache.migrateLegacyCacheIfNeeded(profileID: "chatgpt-a", resolvedAccountID: "")
        XCTAssertFalse(cache.hasCompletedLegacyMigration)
    }

    // MARK: - Service-level behaviour

    func testProfileServiceDoesNotServeTheLegacyV2Cache() {
        let defaults = makeDefaults()
        let cache = UsageCache(userDefaults: defaults)
        seedLegacyV2Cache(cache, accountID: "a@example.invalid", snapshot: snapshot(fiveHourUsed: 11))

        let stub = FailingStub()
        let service = UsageService(factory: { stub }, cache: cache, profileID: "chatgpt-a", restartDelay: 0)
        XCTAssertNil(service.cachedSnapshotForCurrentAccount(),
                     "an upgraded app must not display the pre-1.3.0 cache before the migration has run")
    }

    func testExternalAccountSwitchReplacesTheProfileAttribution() throws {
        let defaults = makeDefaults()
        let cache = UsageCache(userDefaults: defaults)

        // First run: the profile is signed in as X.
        let first = AccountStub(account: CodexAccount(kind: .chatgpt, email: "x@example.invalid", planType: "plus"),
                                snapshot: snapshot(fiveHourUsed: 11))
        let serviceA = UsageService(factory: { first }, cache: cache, profileID: "chatgpt-a", restartDelay: 0)
        XCTAssertTrue(try serviceA.fetch().isLive)
        XCTAssertEqual(serviceA.currentAccountID, "x@example.invalid")

        // The user re-logs in outside the app: the same CODEX_HOME now reports account Y.
        let second = AccountStub(account: CodexAccount(kind: .chatgpt, email: "y@example.invalid", planType: "plus"),
                                 snapshot: snapshot(fiveHourUsed: 22))
        let serviceB = UsageService(factory: { second }, cache: cache, profileID: "chatgpt-a", restartDelay: 0)
        XCTAssertTrue(try serviceB.fetch().isLive)

        XCTAssertEqual(serviceB.currentAccountID, "y@example.invalid")
        XCTAssertEqual(cache.loadLastKnownAccountID(profileID: "chatgpt-a"), "y@example.invalid")
        XCTAssertEqual(serviceB.cachedSnapshotForCurrentAccount()?.fiveHour?.usedPercent, 22,
                       "the current account must be served its own data, never the previous account's")
        XCTAssertEqual(cache.load(profileID: "chatgpt-a", accountID: "y@example.invalid")?.fiveHour?.usedPercent, 22)
    }

    func testProfileServiceAttributionUsesProfileScopedLastKnownAccountOnFailure() throws {
        let defaults = makeDefaults()
        let cache = UsageCache(userDefaults: defaults)
        cache.save(snapshot(fiveHourUsed: 44), profileID: "chatgpt-a", accountID: "a@example.invalid")
        cache.saveLastKnownAccountID("a@example.invalid", profileID: "chatgpt-a")

        let stub = FailingStub()
        let service = UsageService(factory: { stub }, cache: cache, profileID: "chatgpt-a", restartDelay: 0)
        let result = try service.fetch()

        XCTAssertFalse(result.isLive)
        XCTAssertEqual(result.snapshot.fiveHour?.usedPercent, 44,
                       "a failed read keeps serving that profile's own last known account")
        XCTAssertEqual(result.snapshot.source, .cached)
    }

    // MARK: - Helpers

    private final class FailingStub: CodexAppServerProviding {
        var isTransportRunning = true
        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            throw UsageError.rpcFailed(.timedOut(method: "account/rateLimits/read"))
        }
        func stop() { isTransportRunning = false }
    }

    private final class AccountStub: CodexAppServerProviding {
        let account: CodexAccount
        let snapshot: UsageSnapshot
        var isTransportRunning = true

        init(account: CodexAccount, snapshot: UsageSnapshot) {
            self.account = account
            self.snapshot = snapshot
        }

        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot { snapshot }
        func readAccount(timeout: TimeInterval) throws -> CodexAccount? { account }
        func stop() { isTransportRunning = false }
    }
}

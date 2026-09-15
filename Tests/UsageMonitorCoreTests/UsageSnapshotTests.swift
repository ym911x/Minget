import XCTest
@testable import UsageMonitorCore

final class UsageSnapshotTests: XCTestCase {
    func testPersistedRoundTripPreservesNumbersAndDropsRawPayloads() throws {
        let fiveHour = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 9,
                                       remainingPercent: 91, resetsAt: Date(timeIntervalSince1970: 1_788_935_373))
        let weekly = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 5,
                                     remainingPercent: 95, resetsAt: Date(timeIntervalSince1970: 1_789_453_767))
        let snapshot = UsageSnapshot(fiveHour: fiveHour, weekly: weekly,
                                     rateLimitResetCredits: RateLimitResetCredits(
                                        availableCount: 2,
                                        nearestExpiresAt: Date(timeIntervalSince1970: 1_789_000_000)),
                                     fetchedAt: Date(timeIntervalSince1970: 1_788_935_000),
                                     source: .codexAppServer)

        let data = try JSONEncoder().encode(snapshot.persisted)
        let decoded = try JSONDecoder().decode(UsageSnapshot.Persisted.self, from: data)
        let restored = UsageSnapshot.from(persisted: decoded)

        XCTAssertEqual(restored.fiveHour?.usedPercent, 9)
        XCTAssertEqual(restored.fiveHour?.remainingPercent, 91)
        XCTAssertEqual(restored.fiveHour?.kind, .fiveHour)
        XCTAssertEqual(restored.fiveHour?.resetsAt, fiveHour.resetsAt)
        XCTAssertEqual(restored.weekly?.kind, .weekly)
        XCTAssertEqual(restored.fetchedAt, snapshot.fetchedAt)
        XCTAssertEqual(restored.source, .cached)
        XCTAssertEqual(restored.rateLimitResetCredits, snapshot.rateLimitResetCredits)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("9"))
    }

    func testPersistedRoundTripWithMissingWindowAndMissingReset() throws {
        let weekly = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 5,
                                     remainingPercent: 95, resetsAt: nil)
        let snapshot = UsageSnapshot(fiveHour: nil, weekly: weekly, fetchedAt: Date(timeIntervalSince1970: 1_788_935_000), source: .codexAppServer)
        let data = try JSONEncoder().encode(snapshot.persisted)
        let restored = UsageSnapshot.from(persisted: try JSONDecoder().decode(UsageSnapshot.Persisted.self, from: data))
        XCTAssertNil(restored.fiveHour)
        XCTAssertEqual(restored.weekly?.usedPercent, 5)
        XCTAssertNil(restored.weekly?.resetsAt)
        XCTAssertNil(restored.rateLimitResetCredits)
    }

    func testOldPersistedPayloadWithoutResetFieldsStillDecodes() throws {
        let oldJSON = Data("""
        {"fiveHourUsedPercent":9,"fiveHourWindowDurationMinutes":300,
         "fiveHourResetsAtEpochSeconds":1788935373,
         "weeklyUsedPercent":null,"weeklyWindowDurationMinutes":null,
         "weeklyResetsAtEpochSeconds":null,"fetchedAtEpochSeconds":1788935000}
        """.replacingOccurrences(of: "\n", with: "").utf8)
        let decoded = try JSONDecoder().decode(UsageSnapshot.Persisted.self, from: oldJSON)
        let restored = UsageSnapshot.from(persisted: decoded)
        XCTAssertEqual(restored.fiveHour?.usedPercent, 9)
        XCTAssertNil(restored.rateLimitResetCredits)
    }

    func testCachedSnapshotFromCorruptCacheThrowsAndIsRecoverable() throws {
        // A corrupt cache file must be rejectable without crashing the app.
        let corrupted = Data("not a valid cache".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(UsageSnapshot.Persisted.self, from: corrupted))
        let truncated = Data("{\"fiveHourUsedPercent\":9".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(UsageSnapshot.Persisted.self, from: truncated))
    }

    func testCacheFreshnessWindow() {
        let now = Date()
        // Fresh: under 30 seconds. Stale: over 30 seconds (IMPLEMENTATION_PLAN.md).
        XCTAssertFalse(UsageCache.isStale(fetchedAt: now.addingTimeInterval(-10), now: now, maxAge: 30))
        XCTAssertFalse(UsageCache.isStale(fetchedAt: now.addingTimeInterval(-30), now: now, maxAge: 30))
        XCTAssertTrue(UsageCache.isStale(fetchedAt: now.addingTimeInterval(-31), now: now, maxAge: 30))
        XCTAssertTrue(UsageCache.isStale(fetchedAt: now.addingTimeInterval(-8 * 60), now: now, maxAge: 30))
    }
}

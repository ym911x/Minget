import XCTest
@testable import UsageMonitorCore

final class UsageParserTests: XCTestCase {
    let parser = UsageParser()

    /// `BucketResolution` is intentionally not Equatable (it carries window payloads),
    /// so unavailability is asserted by pattern matching.
    func assertUnavailable(_ resolution: UsageParser.BucketResolution, _ problem: PayloadProblem,
                           file: StaticString = #filePath, line: UInt = #line) {
        guard case .unavailable(let actual) = resolution else {
            return XCTFail("expected unavailable(\(problem)), got \(resolution)", file: file, line: line)
        }
        XCTAssertEqual(actual, problem, file: file, line: line)
    }
    let fetchedAt = Date(timeIntervalSince1970: 1_788_935_000)

    func windowDict(_ used: Double?, _ mins: Int?, _ resets: Double?) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let used { dict["usedPercent"] = used }
        if let mins { dict["windowDurationMins"] = mins }
        if let resets { dict["resetsAt"] = resets }
        return dict
    }

    // MARK: Test 1 — remaining percent

    func testUsedPercent25YieldsRemaining75() throws {
        XCTAssertEqual(RateLimitWindow.remainingPercent(fromUsedPercent: 25), 75)
        let snapshot = try parser.parseSnapshot(
            result: ["rateLimits": ["primary": windowDict(25, 300, 1_788_935_373),
                                     "secondary": windowDict(18, 10_080, 1_789_826_837)]],
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 75)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 82)
    }

    // MARK: Tests 2 & 3 — classification by duration

    func test300MinutesClassifiesFiveHour() {
        XCTAssertEqual(RateLimitWindow.kind(forWindowDurationMinutes: 300), .fiveHour)
        let window = parser.parseWindow(windowDict(9, 300, 1_788_935_373))
        XCTAssertEqual(window?.kind, .fiveHour)
    }

    func test10080MinutesClassifiesWeekly() {
        XCTAssertEqual(RateLimitWindow.kind(forWindowDurationMinutes: 10_080), .weekly)
        let window = parser.parseWindow(windowDict(5, 10_080, 1_789_453_767))
        XCTAssertEqual(window?.kind, .weekly)
    }

    // MARK: Test 4 — primary/secondary order must not matter

    func testPrimarySecondarySwappedStillClassifiedByDuration() throws {
        let swapped = try parser.parseSnapshot(
            result: ["rateLimits": ["primary": windowDict(5, 10_080, 1_789_453_767),
                                     "secondary": windowDict(9, 300, 1_788_935_373)]],
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(swapped.fiveHour?.windowDurationMinutes, 300)
        XCTAssertEqual(swapped.fiveHour?.usedPercent, 9)
        XCTAssertEqual(swapped.weekly?.windowDurationMinutes, 10_080)
        XCTAssertEqual(swapped.weekly?.usedPercent, 5)
    }

    // MARK: Tests 5 & 6 — single-window snapshots

    func testOnlyFiveHourWindowLeavesWeeklyNil() throws {
        let snapshot = try parser.parseSnapshot(
            result: ["rateLimits": ["primary": windowDict(9, 300, 1_788_935_373)]],
            fetchedAt: fetchedAt
        )
        XCTAssertNotNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.weekly)
        XCTAssertEqual(snapshot.source, .codexAppServer)
    }

    func testOnlyWeeklyWindowLeavesFiveHourNil() throws {
        let snapshot = try parser.parseSnapshot(
            result: ["rateLimits": ["secondary": windowDict(5, 10_080, 1_789_453_767)]],
            fetchedAt: fetchedAt
        )
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNotNil(snapshot.weekly)
    }

    // MARK: Test 7 — unknown duration must not crash

    func testUnknownDurationPreservedAsUnknownWithoutCrash() throws {
        let snapshot = try parser.parseSnapshot(
            result: ["rateLimits": ["primary": windowDict(9, 300, 1_788_935_373),
                                     "secondary": windowDict(4, 43_800, nil)]],
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(snapshot.fiveHour?.kind, .fiveHour)
        XCTAssertNil(snapshot.weekly)
        XCTAssertEqual(snapshot.unknownWindows.count, 1)
        XCTAssertEqual(snapshot.unknownWindows.first?.windowDurationMinutes, 43_800)
        XCTAssertEqual(snapshot.unknownWindows.first?.kind, .unknown)
    }

    // MARK: Test 8 — clamping

    func testOutOfRangeUsedPercentClampsRemainingTo0Through100() {
        XCTAssertEqual(RateLimitWindow.remainingPercent(fromUsedPercent: -5), 100)
        XCTAssertEqual(RateLimitWindow.remainingPercent(fromUsedPercent: 110), 0)
        XCTAssertEqual(RateLimitWindow.remainingPercent(fromUsedPercent: 0), 100)
        XCTAssertEqual(RateLimitWindow.remainingPercent(fromUsedPercent: 100), 0)
    }

    // MARK: Test 10 — malformed payloads

    func testMalformedJSONDoesNotCrash() {
        let samples: [Data] = [
            Data("{not json".utf8),
            Data("[]".utf8),
            Data("null".utf8),
            Data("{\"error\": \"broken\"}".utf8),
            Data(String(repeating: "x", count: 4096).utf8),
        ]
        for data in samples {
            do {
                _ = try parser.parseResponse(data: data)
                XCTFail("expected parse failure for \(String(data: data, encoding: .utf8) ?? "<binary>")")
            } catch {
                // Any thrown error is acceptable; crashing is not.
            }
        }
    }

    func testResultWithoutWindowsThrowsInsteadOfFabricatingData() {
        XCTAssertThrowsError(try parser.parseSnapshot(result: [:], fetchedAt: fetchedAt))
        XCTAssertThrowsError(try parser.parseSnapshot(result: ["rateLimits": ["primary": windowDict(nil, 300, nil)]], fetchedAt: fetchedAt))
    }

    // MARK: Nulls / missing fields are unavailable, never zero

    func testNullAndNonFiniteValuesAreUnavailable() {
        var dict = windowDict(9, 300, nil)
        dict["usedPercent"] = NSNull()
        XCTAssertNil(parser.parseWindow(dict), "null usedPercent must not become 0")

        dict["usedPercent"] = 9
        dict["resetsAt"] = NSNull()
        let window = parser.parseWindow(dict)
        XCTAssertNil(window?.resetsAt)

        // Boolean is a data error, never 0/1 (Round 2 blocker 1 probe).
        dict["usedPercent"] = true
        XCTAssertNil(parser.parseWindow(dict), "boolean usedPercent must not become remaining 99")
        dict["usedPercent"] = false
        XCTAssertNil(parser.parseWindow(dict))
        dict["usedPercent"] = 9
        dict["windowDurationMins"] = true
        XCTAssertNil(parser.parseWindow(dict))

        XCTAssertNil(SafeConversion.double(nil))
        XCTAssertNil(SafeConversion.double(NSNull()))
        XCTAssertNil(SafeConversion.double(true))
        XCTAssertNil(SafeConversion.double(false))
        XCTAssertNil(SafeConversion.double("not a number"))
        XCTAssertNil(SafeConversion.double(Double.nan))
        XCTAssertNil(SafeConversion.double(Double.infinity))
        XCTAssertNil(SafeConversion.double(-Double.infinity))
        XCTAssertNil(parser.parseResetDate(NSNull()))
        XCTAssertNil(parser.parseResetDate(""))
        XCTAssertNil(parser.parseResetDate(true))

        var nonFinite = windowDict(9, 300, nil)
        nonFinite["usedPercent"] = Double.nan
        nonFinite["windowDurationMins"] = Double.infinity
        XCTAssertNil(parser.parseWindow(nonFinite))
    }

    // MARK: Round 2 blocker 1 — out-of-range and fractional numbers must not trap

    func testHugeDurationDoesNotTrapAndIsRejected() {
        // 1e100 previously crashed with "Double value cannot be converted to Int".
        var huge = windowDict(25, nil, nil)
        huge["windowDurationMins"] = 1e100
        XCTAssertNil(parser.parseWindow(huge))
        XCTAssertNil(SafeConversion.integer(1e100))
        XCTAssertNil(SafeConversion.integer(-1e100))
        XCTAssertNil(SafeConversion.integer(Double.greatestFiniteMagnitude))
        XCTAssertEqual(parser.parseWindow(huge)?.kind, nil)
    }

    func testFractionalDurationIsRejectedInsteadOfTruncated() {
        // 300.9 previously classified as fiveHour.
        var fractional = windowDict(25, nil, nil)
        fractional["windowDurationMins"] = 300.9
        XCTAssertNil(parser.parseWindow(fractional), "fractional duration must stay unavailable")
        XCTAssertNil(SafeConversion.integer(300.9))
        XCTAssertNil(SafeConversion.integer(10_080.5))
        XCTAssertNil(SafeConversion.integer(-0.5))
        XCTAssertEqual(SafeConversion.integer(300.0), 300, "exact whole numbers stay valid")
    }

    func testNonPositiveDurationIsRejected() {
        for invalid in [-5, 0, -1.0, 0.0] {
            var dict = windowDict(25, nil, nil)
            dict["windowDurationMins"] = invalid
            XCTAssertNil(parser.parseWindow(dict), "duration \(invalid) must stay unavailable")
            XCTAssertNil(SafeConversion.integer(invalid, allowNonPositive: false))
        }
    }

    func testHugeUsedPercentDoesNotTrap() {
        var dict = windowDict(nil, 300, nil)
        dict["usedPercent"] = 1e100
        // Duration is valid here, so the window parses and the extreme used percent is
        // clamped for display instead of trapping on conversion.
        let window = parser.parseWindow(dict)
        XCTAssertEqual(window?.remainingPercent, 0)
        XCTAssertNil(SafeConversion.integer(1e100))
    }

    func testResetDateAcceptsNumberAndISO8601() {
        XCTAssertEqual(parser.parseResetDate(1_788_935_373), Date(timeIntervalSince1970: 1_788_935_373))
        XCTAssertEqual(parser.parseResetDate(1_788_935_373.5), Date(timeIntervalSince1970: 1_788_935_373.5))
        XCTAssertNotNil(parser.parseResetDate("2026-09-09T12:00:00Z"))
        XCTAssertNil(parser.parseResetDate(-1))
        XCTAssertNil(parser.parseResetDate(0))
    }

    // MARK: Earned reset credits

    private func resultWithResetCredits(_ value: Any) -> [String: Any] {
        [
            "rateLimits": ["primary": windowDict(9, 300, 1_788_935_373)],
            "rateLimitResetCredits": value,
        ]
    }

    func testResetCreditCountAndNearestFutureExpiryAreNormalized() throws {
        let snapshot = try parser.parseSnapshot(
            result: resultWithResetCredits([
                "availableCount": 3,
                "credits": [
                    ["id": "opaque-a", "status": "available", "expiresAt": 1_788_937_000],
                    ["id": "opaque-b", "status": "available", "expiresAt": 1_788_936_000],
                    ["id": "opaque-c", "status": "available", "expiresAt": 1_788_939_000],
                ],
            ]),
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(snapshot.rateLimitResetCredits?.availableCount, 3)
        XCTAssertEqual(snapshot.rateLimitResetCredits?.nearestExpiresAt,
                       Date(timeIntervalSince1970: 1_788_936_000))
    }

    func testResetCreditCountRemainsAuthoritativeWhenDetailsAreMissingOrShorter() throws {
        let withNullDetails = try parser.parseSnapshot(
            result: resultWithResetCredits(["availableCount": 2, "credits": NSNull()]),
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(withNullDetails.rateLimitResetCredits,
                       RateLimitResetCredits(availableCount: 2))

        let withShortDetails = try parser.parseSnapshot(
            result: resultWithResetCredits([
                "availableCount": 4,
                "credits": [["status": "available", "expiresAt": 1_788_936_000]],
            ]),
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(withShortDetails.rateLimitResetCredits?.availableCount, 4)
        XCTAssertEqual(withShortDetails.rateLimitResetCredits?.nearestExpiresAt,
                       Date(timeIntervalSince1970: 1_788_936_000))
    }

    func testZeroResetCreditsIsExplicitAndDoesNotBorrowAnExpiry() throws {
        let snapshot = try parser.parseSnapshot(
            result: resultWithResetCredits([
                "availableCount": 0,
                "credits": [["status": "available", "expiresAt": 1_788_936_000]],
            ]),
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(snapshot.rateLimitResetCredits,
                       RateLimitResetCredits(availableCount: 0))
    }

    func testExpiredAndRedeemedDetailsAreNotPresentedAsAvailableExpiry() throws {
        let snapshot = try parser.parseSnapshot(
            result: resultWithResetCredits([
                "availableCount": 2,
                "credits": [
                    ["status": "redeemed", "expiresAt": 1_788_936_000],
                    ["status": "available", "expiresAt": fetchedAt.timeIntervalSince1970 - 1],
                ],
            ]),
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(snapshot.rateLimitResetCredits,
                       RateLimitResetCredits(availableCount: 2))
    }

    func testMalformedResetCreditSummaryIsUnavailableWithoutInvalidatingWindows() throws {
        let invalidValues: [Any] = [
            ["availableCount": -1],
            ["availableCount": 1.5],
            ["availableCount": true],
            ["credits": []],
            NSNull(),
        ]
        for value in invalidValues {
            let snapshot = try parser.parseSnapshot(result: resultWithResetCredits(value), fetchedAt: fetchedAt)
            XCTAssertNil(snapshot.rateLimitResetCredits)
            XCTAssertNotNil(snapshot.fiveHour)
        }
    }

    // MARK: Multi-bucket precedence

    func testPrefersCodexBucketFromRateLimitsByLimitId() throws {
        let result: [String: Any] = [
            "rateLimits": ["primary": windowDict(77, 300, 111)],
            "rateLimitsByLimitId": [
                "codex": ["primary": windowDict(9, 300, 1_788_935_373),
                          "secondary": windowDict(5, 10_080, 1_789_453_767)],
                "other-limit": ["primary": windowDict(99, 60, 1)],
            ],
        ]
        let snapshot = try parser.parseSnapshot(result: result, fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 9)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 5)
        XCTAssertEqual(snapshot.unknownWindows.count, 0)
    }

    func testForeignBucketIsNeverSelectedAccidentally() throws {
        // No "codex" entry: a foreign limit must not be shown as account usage.
        let result: [String: Any] = [
            "rateLimitsByLimitId": [
                "some-other-limit": ["primary": windowDict(99, 300, 1)],
            ]
        ]
        XCTAssertThrowsError(try parser.parseSnapshot(result: result, fetchedAt: fetchedAt))
    }

    func testForeignBucketFallsBackToLegacyWhenNoCodexEntry() throws {
        let result: [String: Any] = [
            "rateLimits": ["primary": windowDict(9, 300, 1_788_935_373)],
            "rateLimitsByLimitId": [String: Any]()
        ]
        let snapshot = try parser.parseSnapshot(result: result, fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 9)
    }

    func testDoesNotMixWindowsAcrossBuckets() throws {
        let result: [String: Any] = [
            "rateLimits": ["primary": windowDict(40, 10_080, 1)],
            "rateLimitsByLimitId": [
                "codex": ["primary": windowDict(9, 300, 1_788_935_373)]
            ],
        ]
        let snapshot = try parser.parseSnapshot(result: result, fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 9)
        XCTAssertNil(snapshot.weekly, "weekly from another bucket must not be mixed into the codex snapshot")
    }

    // MARK: Envelope handling

    func testEnvelopeWithErrorThrowsJSONRPCError() {
        let data = Data(#"{"id":2,"error":{"code":-32601,"message":"method not found"}}"#.utf8)
        XCTAssertThrowsError(try parser.parseResponse(data: data)) { error in
            guard let rpcError = error as? JSONRPCError else {
                return XCTFail("expected JSONRPCError, got \(error)")
            }
            XCTAssertEqual(rpcError.code, -32601)
            XCTAssertEqual(rpcError.message, "method not found")
        }
    }

    func testEnvelopeWithResultParses() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":9,"windowDurationMins":300,"resetsAt":1788935373}}}}"#.utf8)
        let response = try parser.parseResponse(data: data)
        let snapshot = try parser.parseSnapshot(result: response.resultObject ?? [:], fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 9)
    }

    func testNotificationWithoutIdIsNotAResponse() {
        let data = Data(#"{"method":"sessionConfigured","params":{}}"#.utf8)
        XCTAssertThrowsError(try parser.parseResponse(data: data))
    }

    func testDuplicateWindowsPreferOneWithResetTime() throws {
        let snapshot = try parser.parseSnapshot(
            result: ["rateLimits": ["primary": windowDict(9, 300, nil),
                                     "secondary": windowDict(11, 300, 1_788_935_373)]],
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_788_935_373))
    }

    // MARK: Round 2 blocker 4 — bucket identity

    func testForeignLegacyLimitIdIsRejected() throws {
        // rateLimits.limitId="other" with a 300-min primary was previously accepted as Codex.
        let foreign = try? parser.parseSnapshot(
            result: ["rateLimits": ["limitId": "other",
                                     "primary": windowDict(25, 300, 1_788_935_373)]],
            fetchedAt: fetchedAt
        )
        XCTAssertNil(foreign?.fiveHour, "a foreign legacy bucket must not be shown as account usage")
        assertUnavailable(parser.resolveBucket(in: ["rateLimits": ["limitId": "other",
                                                                    "primary": windowDict(25, 300, 1)]]),
                          .foreignLimitBucket)
    }

    func testLegacySnapshotWithoutLimitIdIsAccepted() throws {
        let snapshot = try parser.parseSnapshot(
            result: ["rateLimits": ["primary": windowDict(9, 300, 1_788_935_373)]],
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 9)
    }

    func testLegacyCodexLimitIdIsAccepted() throws {
        let snapshot = try parser.parseSnapshot(
            result: ["rateLimits": ["limitId": "codex",
                                     "primary": windowDict(9, 300, 1_788_935_373),
                                     "secondary": windowDict(5, 10_080, 1_789_453_767)]],
            fetchedAt: fetchedAt
        )
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 9)
        XCTAssertEqual(snapshot.weekly?.windowDurationMinutes, 10_080)
    }

    func testEmptyCodexBucketDoesNotFallBackToLegacy() throws {
        // An explicitly present but empty codex entry must stay unavailable: falling back
        // to the legacy object would present a different limit as this account's usage.
        let result: [String: Any] = [
            "rateLimits": ["primary": windowDict(77, 300, 1)],
            "rateLimitsByLimitId": ["codex": NSNull()],
        ]
        assertUnavailable(parser.resolveBucket(in: result), .codexBucketEmpty)
        XCTAssertNil((try? parser.parseSnapshot(result: result, fetchedAt: fetchedAt))?.fiveHour)
    }

    func testNullCodexEntryDoesNotFallBackToLegacy() throws {
        let result: [String: Any] = [
            "rateLimits": ["primary": windowDict(77, 300, 1)],
            "rateLimitsByLimitId": ["codex": [String: Any]()],
        ]
        assertUnavailable(parser.resolveBucket(in: result), .codexBucketEmpty)
        XCTAssertThrowsError(try parser.parseSnapshot(result: result, fetchedAt: fetchedAt))
    }

    func testForeignBucketWithoutCodexEntryIsNeverSelected() throws {
        let result: [String: Any] = ["rateLimitsByLimitId": ["other-limit": ["primary": windowDict(99, 300, 1)]]]
        assertUnavailable(parser.resolveBucket(in: result), .foreignLimitBucket)
    }

    func testDegenerateTopLevelWindowWithForeignLimitIdIsRejected() throws {
        let result: [String: Any] = ["limitId": "other", "primary": windowDict(99, 300, 1)]
        assertUnavailable(parser.resolveBucket(in: result), .noRateLimitWindows)
    }

    func testForeignBucketIsNeverMixedIntoCodexSnapshot() throws {
        let result: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": ["primary": windowDict(9, 300, 1_788_935_373)],
                "other": ["secondary": windowDict(40, 10_080, 1)],
            ],
        ]
        let snapshot = try parser.parseSnapshot(result: result, fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 9)
        XCTAssertNil(snapshot.weekly, "windows from another bucket must not be merged")
    }
}

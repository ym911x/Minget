import XCTest
@testable import UsageMonitorCore

/// v1.0.2 requirement 3 / §4: the two time rows are a pure function of an explicit `now`.
///
/// Every expectation below is the spec's own table, recomputed from the formula
/// `fills[i] = min(max(units - i, 0), 1)` with `units = clampedRemaining / secondsPerSegment`.
final class ResetTimeProgressTests: XCTestCase {

    /// A fixed anchor so the arithmetic is exact and no test waits for wall-clock time.
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fiveHourWindow(remaining: TimeInterval) -> RateLimitWindow {
        RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 22,
                        remainingPercent: 78, resetsAt: now.addingTimeInterval(remaining))
    }

    private func weeklyWindow(remaining: TimeInterval) -> RateLimitWindow {
        RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 58,
                        remainingPercent: 42, resetsAt: now.addingTimeInterval(remaining))
    }

    private func fiveHourFills(_ remaining: TimeInterval,
                              file: StaticString = #filePath, line: UInt = #line) -> [Double] {
        let progress = ResetTimeModel.progress(expected: .fiveHour, window: fiveHourWindow(remaining: remaining), now: now)
        XCTAssertEqual(progress.state, .active, "expected an active countdown", file: file, line: line)
        return progress.fills
    }

    // MARK: §8.1.1 Five-hour row

    func testFiveHourRowMatchesTheSpecTable() {
        // 5 hours: every segment full.
        XCTAssertEqual(fiveHourFills(5 * 3600), [1, 1, 1, 1, 1])
        // 4 hours 30 minutes: the rightmost segment is half filled.
        XCTAssertEqual(fiveHourFills(4.5 * 3600), [1, 1, 1, 1, 0.5])
        // 2 hours 30 minutes: the third segment is half filled.
        XCTAssertEqual(fiveHourFills(2.5 * 3600), [1, 1, 0.5, 0, 0])
        // 2 hours: the two leftmost segments stay bright, the rest are empty.
        XCTAssertEqual(fiveHourFills(2 * 3600), [1, 1, 0, 0, 0])
        // 30 minutes: only the leftmost segment is half filled.
        XCTAssertEqual(fiveHourFills(0.5 * 3600), [0.5, 0, 0, 0, 0])
        // 1 second: an almost invisible sliver at the very left, never a whole segment.
        let oneSecond = fiveHourFills(1)
        XCTAssertEqual(oneSecond[0], 1.0 / 3600, accuracy: 1e-9)
        XCTAssertEqual(Array(oneSecond.dropFirst()), [0, 0, 0, 0])
    }

    func testFiveHourRowHasFiveSegments() {
        XCTAssertEqual(fiveHourFills(3 * 3600).count, 5)
        XCTAssertEqual(ResetTimeModel.segmentCount(for: .fiveHour), 5)
    }

    func testNoSegmentIsEverUpwardRounded() {
        // 1 minute left must not read as a full hour-long segment.
        let fills = fiveHourFills(60)
        XCTAssertEqual(fills[0], 60.0 / 3600, accuracy: 1e-9)
        XCTAssertLessThan(fills[0], 0.02)
    }

    // MARK: §8.1.2 Weekly row

    func testWeeklyRowMatchesTheSpecTable() {
        func weeklyFills(_ remaining: TimeInterval) -> [Double] {
            let progress = ResetTimeModel.progress(expected: .weekly, window: weeklyWindow(remaining: remaining), now: now)
            XCTAssertEqual(progress.state, .active)
            return progress.fills
        }
        XCTAssertEqual(ResetTimeModel.segmentCount(for: .weekly), 7)
        XCTAssertEqual(weeklyFills(7 * 86400), [1, 1, 1, 1, 1, 1, 1])
        XCTAssertEqual(weeklyFills(6.5 * 86400), [1, 1, 1, 1, 1, 1, 0.5])
        // The spec's example: three and a half days left.
        XCTAssertEqual(weeklyFills(3.5 * 86400), [1, 1, 1, 0.5, 0, 0, 0])
        XCTAssertEqual(weeklyFills(86400), [1, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(weeklyFills(86400).count, 7, "the row must always have 7 segments")
    }

    // MARK: §8.1.3 Unknown, expired and invalid inputs

    func testMissingWindowIsUnknownWithAnEmptyRowOfTheRightLength() {
        let five = ResetTimeModel.progress(expected: .fiveHour, window: nil, now: now)
        XCTAssertEqual(five.state, .unknown)
        XCTAssertEqual(five.fills, [0, 0, 0, 0, 0])

        let weekly = ResetTimeModel.progress(expected: .weekly, window: nil, now: now)
        XCTAssertEqual(weekly.state, .unknown)
        XCTAssertEqual(weekly.fills, [0, 0, 0, 0, 0, 0, 0])
    }

    func testMissingResetDateIsUnknownNotEmpty() {
        let window = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 10,
                                     remainingPercent: 90, resetsAt: nil)
        let progress = ResetTimeModel.progress(expected: .fiveHour, window: window, now: now)
        XCTAssertEqual(progress.state, .unknown)
        XCTAssertFalse(progress.state.isAwaitingRefresh, "unknown is not the same as arrived")
    }

    func testExpiredResetIsArrivedAndFullyEmpty() {
        let expired = ResetTimeModel.progress(expected: .fiveHour, window: fiveHourWindow(remaining: -3600), now: now)
        XCTAssertEqual(expired.state, .arrived)
        XCTAssertEqual(expired.fills, [0, 0, 0, 0, 0])

        // Exactly at the reported time also counts as arrived.
        let exact = ResetTimeModel.progress(expected: .fiveHour, window: fiveHourWindow(remaining: 0), now: now)
        XCTAssertEqual(exact.state, .arrived)
        XCTAssertTrue(exact.hasNoBrightSegment)
    }

    func testExpiredWindowIsNeverRefilledLocally() {
        // Repeated calls at a later `now` must stay empty: the model never adds a window.
        let window = fiveHourWindow(remaining: -1)
        for extra: TimeInterval in [0, 60, 5 * 3600] {
            let progress = ResetTimeModel.progress(expected: .fiveHour, window: window, now: now.addingTimeInterval(extra))
            XCTAssertEqual(progress.state, .arrived)
            XCTAssertEqual(progress.fills, [0, 0, 0, 0, 0])
        }
    }

    func testDurationThatDoesNotMatchTheRowIsInvalid() {
        // Kind says five-hour but the duration says ten hours: never normalised into the row.
        let mismatched = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 600, usedPercent: 10,
                                         remainingPercent: 90, resetsAt: now.addingTimeInterval(3600))
        let progress = ResetTimeModel.progress(expected: .fiveHour, window: mismatched, now: now)
        XCTAssertEqual(progress.state, .invalid)
        XCTAssertEqual(progress.fills, [0, 0, 0, 0, 0])
    }

    func testWeeklyWindowIsInvalidInTheFiveHourRowAndViceVersa() {
        let five = ResetTimeModel.progress(expected: .weekly, window: fiveHourWindow(remaining: 3600), now: now)
        XCTAssertEqual(five.state, .invalid, "a 300-minute window must not be drawn in the weekly row")

        let weekly = ResetTimeModel.progress(expected: .fiveHour, window: weeklyWindow(remaining: 3600), now: now)
        XCTAssertEqual(weekly.state, .invalid, "a 10080-minute window must not be drawn in the five-hour row")
    }

    func testUnknownWindowKindHasNoRowAtAll() {
        let progress = ResetTimeModel.progress(expected: .unknown, window: nil, now: now)
        XCTAssertEqual(progress.state, .invalid)
        XCTAssertTrue(progress.fills.isEmpty, "an unknown kind maps to no time row")
    }

    func testNonFiniteInputsAreInvalidAndNeverProduceNaN() {
        let nanReset = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 10,
                                       remainingPercent: 90, resetsAt: Date(timeIntervalSince1970: .nan))
        let fromReset = ResetTimeModel.progress(expected: .fiveHour, window: nanReset, now: now)
        XCTAssertEqual(fromReset.state, .invalid)
        XCTAssertTrue(fromReset.fills.allSatisfy { $0.isFinite })

        let infiniteReset = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 10,
                                            remainingPercent: 90, resetsAt: Date(timeIntervalSince1970: .infinity))
        XCTAssertEqual(ResetTimeModel.progress(expected: .weekly, window: infiniteReset, now: now).state, .invalid)

        let fromNow = ResetTimeModel.progress(expected: .fiveHour, window: fiveHourWindow(remaining: 3600),
                                              now: Date(timeIntervalSince1970: .nan))
        XCTAssertEqual(fromNow.state, .invalid)
        XCTAssertTrue(fromNow.fills.allSatisfy { $0.isFinite })
    }

    // MARK: §4.3 Clock tolerance

    func testResetBeyondTheWindowIsClampedWithinTheToleranceOnly() {
        // 5 hours + 30 seconds: clock/service skew, clamped to a full row.
        let withinTolerance = ResetTimeModel.progress(expected: .fiveHour,
                                                      window: fiveHourWindow(remaining: 5 * 3600 + 30),
                                                      now: now)
        XCTAssertEqual(withinTolerance.state, .active)
        XCTAssertEqual(withinTolerance.fills, [1, 1, 1, 1, 1])
        XCTAssertEqual(withinTolerance.remainingSeconds, 5 * 3600, "clamped to the window length")

        // Exactly at the tolerance boundary still clamps.
        let atBoundary = ResetTimeModel.progress(expected: .fiveHour,
                                                 window: fiveHourWindow(remaining: 5 * 3600 + 60),
                                                 now: now)
        XCTAssertEqual(atBoundary.state, .active)
        XCTAssertEqual(atBoundary.fills, [1, 1, 1, 1, 1])

        // One second past the tolerance is refused rather than shown as a permanently full row.
        let pastTolerance = ResetTimeModel.progress(expected: .fiveHour,
                                                    window: fiveHourWindow(remaining: 5 * 3600 + 61),
                                                    now: now)
        XCTAssertEqual(pastTolerance.state, .invalid)
        XCTAssertEqual(pastTolerance.fills, [0, 0, 0, 0, 0])
    }

    func testConfiguredToleranceIsSixtySeconds() {
        XCTAssertEqual(ResetTimeModel.clockTolerance, 60,
                       "the implementation report must record this value")
    }

    // MARK: §8.1.7 Independent clock movement

    func testProgressIsRecomputedFromAbsoluteTime() {
        // The same window read at two different wall-clock instants gives a shorter row later.
        let window = fiveHourWindow(remaining: 5 * 3600)
        let earlier = ResetTimeModel.progress(expected: .fiveHour, window: window, now: now)
        let later = ResetTimeModel.progress(expected: .fiveHour, window: window, now: now.addingTimeInterval(3600))
        XCTAssertEqual(earlier.fills, [1, 1, 1, 1, 1])
        XCTAssertEqual(later.fills, [1, 1, 1, 1, 0], "one hour of real time consumes exactly one segment")

        // A small backwards clock jump stays inside the skew tolerance and clamps to full.
        let smallBackJump = ResetTimeModel.progress(expected: .fiveHour, window: window, now: now.addingTimeInterval(-60))
        XCTAssertEqual(smallBackJump.state, .active)
        XCTAssertEqual(smallBackJump.fills, [1, 1, 1, 1, 1])

        // A backwards jump that pushes the reset time past the window's own length is refused,
        // rather than shown as a permanently full row.
        let largeBackJump = ResetTimeModel.progress(expected: .fiveHour, window: window, now: now.addingTimeInterval(-7200))
        XCTAssertEqual(largeBackJump.state, .invalid)
        XCTAssertEqual(largeBackJump.fills, [0, 0, 0, 0, 0])
    }

    func testWakeAfterSleepJumpsStraightToTheRealRemainingTime() {
        // Sleep is modelled as one large `now` jump: the row must follow the clock, not tick
        // down once per second from its pre-sleep value.
        let window = weeklyWindow(remaining: 7 * 86400)
        let beforeSleep = ResetTimeModel.progress(expected: .weekly, window: window, now: now)
        XCTAssertEqual(beforeSleep.fills, [1, 1, 1, 1, 1, 1, 1])

        let afterSleep = ResetTimeModel.progress(expected: .weekly, window: window,
                                                 now: now.addingTimeInterval(4 * 86400))
        XCTAssertEqual(afterSleep.state, .active)
        XCTAssertEqual(afterSleep.fills, [1, 1, 1, 0, 0, 0, 0])
    }

    // MARK: Both rows from one reading

    func testRowsAreComputedIndependentlyFromTheSameNow() {
        let snapshot = UsageSnapshot(fiveHour: fiveHourWindow(remaining: 2 * 3600),
                                     weekly: weeklyWindow(remaining: 3.5 * 86400),
                                     fetchedAt: now,
                                     source: .codexAppServer)
        let rows = ResetTimeModel.rows(snapshot: snapshot, now: now)
        XCTAssertEqual(rows.fiveHour.fills, [1, 1, 0, 0, 0])
        XCTAssertEqual(rows.weekly.fills, [1, 1, 1, 0.5, 0, 0, 0])
    }

    func testOneMissingWindowDoesNotAffectTheOtherRow() {
        let snapshot = UsageSnapshot(fiveHour: nil,
                                     weekly: weeklyWindow(remaining: 86400),
                                     fetchedAt: now,
                                     source: .codexAppServer)
        let rows = ResetTimeModel.rows(snapshot: snapshot, now: now)
        XCTAssertEqual(rows.fiveHour.state, .unknown)
        XCTAssertEqual(rows.weekly.state, .active)
        XCTAssertEqual(rows.weekly.fills, [1, 0, 0, 0, 0, 0, 0])
    }

    func testQuotaPercentNeverInfluencesTheTimeRow() {
        // Two windows with identical reset times but very different percentages: the rows must
        // be identical, because the row reads the clock, not the quota.
        let low = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 5,
                                  remainingPercent: 95, resetsAt: now.addingTimeInterval(7200))
        let high = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 95,
                                   remainingPercent: 5, resetsAt: now.addingTimeInterval(7200))
        let a = ResetTimeModel.progress(expected: .fiveHour, window: low, now: now)
        let b = ResetTimeModel.progress(expected: .fiveHour, window: high, now: now)
        XCTAssertEqual(a.fills, b.fills)
    }

    // MARK: Descriptions

    func testStateTextNamesTheStateWithoutClaimingARenewal() {
        let active = ResetTimeModel.progress(expected: .fiveHour, window: fiveHourWindow(remaining: 2.5 * 3600), now: now)
        XCTAssertTrue(active.stateText(windowName: "5 小时额度").contains("2 小时 30 分"),
                      active.stateText(windowName: "5 小时额度"))

        let arrived = ResetTimeModel.progress(expected: .fiveHour, window: fiveHourWindow(remaining: -10), now: now)
        XCTAssertEqual(arrived.stateText(windowName: "5 小时额度"), "5 小时额度已到重置时间，等待刷新确认")

        XCTAssertEqual(ResetTimeModel.progress(expected: .weekly, window: nil, now: now)
                        .stateText(windowName: "周额度"), "周额度重置时间未知")
    }

    func testDurationTextNeverRoundsAWholeMinuteIntoAnHour() {
        XCTAssertEqual(ResetTimeProgress.durationText(30), "不到 1 分钟")
        XCTAssertEqual(ResetTimeProgress.durationText(60), "1 分钟")
        XCTAssertEqual(ResetTimeProgress.durationText(3599), "59 分钟")
        XCTAssertEqual(ResetTimeProgress.durationText(3600), "1 小时")
        XCTAssertEqual(ResetTimeProgress.durationText(9000), "2 小时 30 分")
        XCTAssertEqual(ResetTimeProgress.durationText(nil), "不到 1 分钟")
    }
}

import XCTest
@testable import UsageMonitorCore

/// v1.0.2 requirements 1 and 4, and §8.1.4 / §8.1.5 / §8.1.8: one content decision point
/// produces the text, the single warning and the two time rows together.
final class MenuBarContentTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(_ kind: RateLimitWindow.Kind, remaining: TimeInterval) -> RateLimitWindow {
        switch kind {
        case .fiveHour:
            return RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 22,
                                   remainingPercent: 78, resetsAt: now.addingTimeInterval(remaining))
        case .weekly:
            return RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 58,
                                   remainingPercent: 42, resetsAt: now.addingTimeInterval(remaining))
        case .unknown:
            return RateLimitWindow(kind: .unknown, windowDurationMinutes: 60, usedPercent: 1,
                                   remainingPercent: 99, resetsAt: now.addingTimeInterval(remaining))
        }
    }

    private func snapshot(fiveHour: RateLimitWindow?, weekly: RateLimitWindow?,
                          source: UsageSource = .codexAppServer) -> UsageSnapshot {
        UsageSnapshot(fiveHour: fiveHour, weekly: weekly, fetchedAt: now, source: source)
    }

    private func liveSnapshot() -> UsageSnapshot {
        snapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600),
                 weekly: window(.weekly, remaining: 3 * 86400))
    }

    private func content(_ display: UsageDisplay,
                         connection: UsageService.ConnectionState = .connected,
                         mode: MenuBarSpaceMode = .full) -> MenuBarContent {
        MenuBarContentBuilder.make(display: display, connectionState: connection, now: now, mode: mode)
    }

    // MARK: §8.1.8 Warning: zero or exactly one

    func testLiveDataHasNoWarningAtAll() {
        let result = content(.live(liveSnapshot()))
        XCTAssertEqual(result.attention, .none)
        XCTAssertNil(result.attention.symbolName)
        XCTAssertNil(result.attention.textMarker)
    }

    func testCachedDataWarnsExactlyOnceAndInFront() {
        let result = content(.stale(liveSnapshot(), .rpcFailed(.timedOut(method: "account/rateLimits/read"))))
        XCTAssertEqual(result.attention, .warning)
        XCTAssertEqual(result.attention.symbolName, "exclamationmark.triangle.fill")
        // Exactly one marker, and the text itself carries none.
        XCTAssertFalse(result.text.contains("⚠"))
        XCTAssertFalse(result.text.contains("!"))
        XCTAssertTrue(result.text.hasPrefix("5H"))
    }

    func testDefiniteReadFailureWithoutCacheWarnsOnce() {
        let result = content(.unavailable(.codexNotSignedIn), connection: .disconnected)
        XCTAssertEqual(result.attention, .warning)
        XCTAssertEqual(result.text, "5H – | W –")
    }

    func testNotYetLoadedDoesNotClaimAFailure() {
        // The view model starts as `.unavailable(.rpcFailed(.other))` before the first fetch
        // has produced a verdict. That must not read as a read failure (v1.0.2 §5.2.3).
        let initial = UsageDisplay.unavailable(.rpcFailed(.other))
        XCTAssertEqual(content(initial, connection: .idle).attention, .none)
        XCTAssertEqual(content(initial, connection: .connecting).attention, .none)
        // A failed attempt is the only thing that flips it.
        XCTAssertEqual(content(initial, connection: .disconnected).attention, .warning)
    }

    func testArrivingAtTheResetTimeAddsNoSecondWarning() {
        // Live data whose reset time has just been reached: the row reports it, and no extra
        // warning is added because no read has failed (v1.0.2 §5.2.5).
        let arrived = snapshot(fiveHour: window(.fiveHour, remaining: -10),
                               weekly: window(.weekly, remaining: -10))
        let result = content(.live(arrived))
        XCTAssertEqual(result.attention, .none, "reaching the reset time is not a read failure")
        XCTAssertEqual(result.fiveHour.state, .arrived)
        XCTAssertEqual(result.weekly.state, .arrived)
        XCTAssertTrue(result.fiveHour.hasNoBrightSegment)
        XCTAssertTrue(result.weekly.hasNoBrightSegment)
    }

    func testPartialWindowAvailabilityDoesNotAddExtraWarnings() {
        // Only the five-hour window is missing: the hour row is unknown, the week row is fine,
        // and there is still at most one warning.
        let result = content(.live(snapshot(fiveHour: nil, weekly: window(.weekly, remaining: 3 * 86400))))
        XCTAssertEqual(result.attention, .none)
        XCTAssertEqual(result.fiveHour.state, .unknown)
        XCTAssertEqual(result.weekly.state, .active)
        XCTAssertEqual(result.text, "5H – | W 42%")
    }

    // MARK: §8.1.9 Text per mode

    func testFullModeTextStartsWithFiveHourAndKeepsBothNumbers() {
        let result = content(.live(liveSnapshot()), mode: .full)
        XCTAssertEqual(result.text, "5H 78% | W 42%")
        XCTAssertTrue(result.showsTimeBars)
        XCTAssertEqual(result.fiveHour.segmentCount, 5)
        XCTAssertEqual(result.weekly.segmentCount, 7)
    }

    func testCompactModeStillStartsWithFiveHourAndKeepsBothRows() {
        let result = content(.live(liveSnapshot()), mode: .compact)
        XCTAssertEqual(result.text, "5H 78% W 42%")
        XCTAssertTrue(result.text.hasPrefix("5H"))
        XCTAssertFalse(result.text.contains("|"))
        XCTAssertTrue(result.showsTimeBars, "compact must still show both rows")
    }

    func testMinimalFallbackIsPlainTextWithNoRows() {
        let result = content(.live(liveSnapshot()), mode: .icon)
        XCTAssertEqual(result.text, "5H")
        XCTAssertFalse(result.showsTimeBars, "the minimal fallback hides both rows rather than cramping them")
        XCTAssertFalse(result.text.contains("M²"), "no brand mark in any mode")
    }

    func testCachedFlagDrivesTheDimmerRows() {
        XCTAssertFalse(content(.live(liveSnapshot())).isCached)
        XCTAssertTrue(content(.stale(liveSnapshot(), .rpcFailed(.other))).isCached)
    }

    // MARK: §4.4 size signature excludes time

    func testSizeSignatureIgnoresTheCountdown() {
        let display = UsageDisplay.live(liveSnapshot())
        let first = MenuBarContentBuilder.make(display: display, connectionState: .connected,
                                              now: now, mode: .full)
        let later = MenuBarContentBuilder.make(display: display, connectionState: .connected,
                                              now: now.addingTimeInterval(600), mode: .full)
        XCTAssertNotEqual(first.fiveHour.fills, later.fiveHour.fills, "the countdown did move")
        XCTAssertEqual(first.sizeSignature, later.sizeSignature,
                       "the width signature must not change once a second")
    }

    func testSizeSignatureChangesWhenTheTextOrWarningChanges() {
        let base = content(.live(liveSnapshot()), mode: .full)
        let cached = content(.stale(liveSnapshot(), .rpcFailed(.other)), mode: .full)
        XCTAssertNotEqual(base.sizeSignature, cached.sizeSignature)

        let differentPercent = snapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600),
                                       weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                                               usedPercent: 0, remainingPercent: 100,
                                                               resetsAt: now.addingTimeInterval(3 * 86400)))
        let full = content(.live(differentPercent), mode: .full)
        XCTAssertNotEqual(base.sizeSignature, full.sizeSignature, "100% is wider than 42%")

        // The mode is part of the signature, because each mode is measured on its own.
        let compact = content(.live(liveSnapshot()), mode: .compact)
        XCTAssertNotEqual(base.sizeSignature, compact.sizeSignature)
    }

    // MARK: §8.1.4 / §8.1.5 Rows react to the right input

    func testChangingOnlyTheWeeklyResetLeavesTheHourRowAlone() {
        let before = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600),
                                            weekly: window(.weekly, remaining: 7 * 86400))))
        let after = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600),
                                           weekly: window(.weekly, remaining: 86400))))
        XCTAssertEqual(before.fiveHour.fills, after.fiveHour.fills, "the hour row must not move")
        XCTAssertNotEqual(before.weekly.fills, after.weekly.fills, "the week row must move")
    }

    func testUnchangedQuotaWithANewResetTimeStillMovesTheRow() {
        // §8.1.5: the numbers stay identical, only the reset time moves.
        let before = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600),
                                            weekly: window(.weekly, remaining: 3 * 86400))))
        let after = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: 1 * 3600),
                                           weekly: window(.weekly, remaining: 3 * 86400))))
        XCTAssertEqual(before.text, after.text, "the quota text did not change")
        XCTAssertNotEqual(before.fiveHour.fills, after.fiveHour.fills, "the row still followed the new reset")
    }

    func testQuotaPercentChangesLeaveBothRowsAlone() {
        let base = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600),
                                          weekly: window(.weekly, remaining: 3 * 86400))))
        let changed = content(.live(snapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                                      usedPercent: 95, remainingPercent: 5,
                                                                      resetsAt: now.addingTimeInterval(4 * 3600)),
                                          weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                                                  usedPercent: 99, remainingPercent: 1,
                                                                  resetsAt: now.addingTimeInterval(3 * 86400)))))
        XCTAssertNotEqual(base.text, changed.text, "the quota text did change")
        XCTAssertEqual(base.fiveHour.fills, changed.fiveHour.fills)
        XCTAssertEqual(base.weekly.fills, changed.weekly.fills)
    }

    // MARK: Accessibility

    func testAccessibilityTextNamesEachRowState() {
        let active = content(.live(liveSnapshot()))
        XCTAssertTrue(active.accessibilityText.contains("明明有数"))
        XCTAssertTrue(active.accessibilityText.contains("5H 78% | W 42%"))

        let arrived = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: -5),
                                             weekly: window(.weekly, remaining: -5))))
        XCTAssertTrue(arrived.accessibilityText.contains("等待刷新确认"), arrived.accessibilityText)

        let unknown = content(.live(snapshot(fiveHour: nil, weekly: nil)))
        XCTAssertTrue(unknown.accessibilityText.contains("重置时间未知"), unknown.accessibilityText)

        let warned = content(.stale(liveSnapshot(), .rpcFailed(.other)))
        XCTAssertTrue(warned.accessibilityText.contains("异常提示"), warned.accessibilityText)
    }

    func testAccessibilityTextOmitsRowsInTheMinimalFallback() {
        let minimal = content(.live(liveSnapshot()), mode: .icon)
        XCTAssertEqual(minimal.accessibilityText, "明明有数 · Minget 菜单栏，5H")
    }

    // MARK: No snapshot at all

    func testNoSnapshotLeavesQuotaAsPlaceholderAndBothRowsUnknown() {
        let result = content(.unavailable(.rpcFailed(.other)), connection: .disconnected)
        XCTAssertEqual(result.text, "5H – | W –")
        XCTAssertEqual(result.fiveHour.state, .unknown)
        XCTAssertEqual(result.weekly.state, .unknown)
        XCTAssertEqual(result.fiveHour.fills, [0, 0, 0, 0, 0])
        XCTAssertEqual(result.weekly.fills, [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(result.attention, .warning, "a definite failure keeps the single warning")
        XCTAssertFalse(result.isCached, "no cache is not cached data")
    }

    func testInvalidTimingShowsADimRowRatherThanAnInventedCountdown() {
        // A window whose duration does not match the row must not be normalised.
        let mismatched = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 600, usedPercent: 10,
                                         remainingPercent: 90, resetsAt: now.addingTimeInterval(3600))
        let result = content(.live(snapshot(fiveHour: mismatched, weekly: nil)))
        XCTAssertEqual(result.fiveHour.state, .invalid)
        XCTAssertTrue(result.fiveHour.hasNoBrightSegment)
        XCTAssertEqual(result.fiveHour.segmentCount, 5, "the row keeps its 5 segments and shows a ? instead")
    }
}

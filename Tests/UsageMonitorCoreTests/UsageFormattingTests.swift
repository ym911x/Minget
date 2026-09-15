import XCTest
@testable import UsageMonitorCore

final class UsageFormattingTests: XCTestCase {
    let fiveHour = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 22,
                                   remainingPercent: 78, resetsAt: Date(timeIntervalSince1970: 1_788_935_373))
    let weekly = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 58,
                                 remainingPercent: 42, resetsAt: Date(timeIntervalSince1970: 1_789_453_767))

    func testMenuBarTitleShowsBothWindowsAndCarriesNoMarker() {
        XCTAssertEqual(UsageFormatting.menuBarTitle(fiveHour: fiveHour, weekly: weekly), "5H 78% | W 42%")
        XCTAssertEqual(UsageFormatting.menuBarTitle(fiveHour: nil, weekly: weekly), "5H – | W 42%")
        XCTAssertEqual(UsageFormatting.menuBarTitle(fiveHour: nil, weekly: nil), "5H – | W –")
        // v1.0.2 requirement 4: the quota text never carries a warning, in any combination.
        for title in [UsageFormatting.menuBarTitle(fiveHour: fiveHour, weekly: weekly),
                      UsageFormatting.menuBarTitle(fiveHour: nil, weekly: nil),
                      UsageFormatting.compactMenuBarTitle(fiveHour: fiveHour, weekly: weekly)] {
            XCTAssertFalse(title.contains("⚠"), "no trailing warning may be built here: \(title)")
            XCTAssertFalse(title.contains("!"), "no trailing exclamation mark either: \(title)")
            XCTAssertTrue(title.hasPrefix("5H"), "the text starts with 5H: \(title)")
        }
    }

    func testCompactTitleKeepsBothWindows() {
        // Compact keeps both numbers and still starts with 5H; only the separator is dropped.
        XCTAssertEqual(UsageFormatting.compactMenuBarTitle(fiveHour: fiveHour, weekly: weekly), "5H 78% W 42%")
        XCTAssertEqual(UsageFormatting.compactMenuBarTitle(fiveHour: fiveHour, weekly: nil), "5H 78% W –")
    }

    func testMenuBarTitleRoundsToWholePercent() {
        let low = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 91,
                                  remainingPercent: 9, resetsAt: nil)
        let full = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 0,
                                   remainingPercent: 100, resetsAt: nil)
        XCTAssertEqual(UsageFormatting.menuBarTitle(fiveHour: low, weekly: full), "5H 9% | W 100%")
    }

    func testRemainingTextIsExplicit() {
        XCTAssertEqual(UsageFormatting.remainingText(fiveHour), "剩余 78%")
        XCTAssertEqual(UsageFormatting.remainingText(weekly), "剩余 42%")
        let zero = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 100,
                                   remainingPercent: 0, resetsAt: nil)
        XCTAssertEqual(UsageFormatting.remainingText(zero), "剩余 0%")
    }

    func testLevelThresholdsFollowSpec() {
        XCTAssertEqual(UsageFormatting.usageLevel(remainingPercent: 78), .normal)
        XCTAssertEqual(UsageFormatting.usageLevel(remainingPercent: 51), .normal)
        XCTAssertEqual(UsageFormatting.usageLevel(remainingPercent: 50), .warning)
        XCTAssertEqual(UsageFormatting.usageLevel(remainingPercent: 20), .warning)
        XCTAssertEqual(UsageFormatting.usageLevel(remainingPercent: 19.9), .critical)
        XCTAssertEqual(UsageFormatting.usageLevel(remainingPercent: 0), .critical)
    }

    func testErrorTextCoversAllDocumentedStates() {
        XCTAssertEqual(UsageFormatting.errorText(.codexCLINotFound(searchedPaths: [])).contains("Codex CLI not found"), true)
        XCTAssertEqual(UsageFormatting.errorText(.codexNotSignedIn).contains("Codex is not signed in"), true)
        XCTAssertEqual(UsageFormatting.errorText(.appServerStartupFailed(.launchFailed)).contains("Unable to start Codex app-server"), true)
        XCTAssertEqual(UsageFormatting.errorText(.rpcFailed(.timedOut(method: "account/rateLimits/read"))).contains("Unable to read usage"), true)
        XCTAssertEqual(UsageFormatting.errorText(.windowUnavailable(kind: .fiveHour)).contains("5-hour usage unavailable"), true)
        XCTAssertEqual(UsageFormatting.errorText(.windowUnavailable(kind: .weekly)).contains("Weekly usage unavailable"), true)
    }

    func testStalenessAndUpdatedText() {
        let now = Date()
        XCTAssertEqual(UsageFormatting.updatedText(fetchedAt: now.addingTimeInterval(-3), now: now), "刚刚更新")
        XCTAssertEqual(UsageFormatting.updatedText(fetchedAt: now.addingTimeInterval(-10), now: now), "更新于 10 秒前")
        XCTAssertEqual(UsageFormatting.updatedText(fetchedAt: now.addingTimeInterval(-2 * 60), now: now), "更新于 2 分钟前")
        XCTAssertEqual(UsageFormatting.updatedText(fetchedAt: now.addingTimeInterval(-3 * 3600), now: now), "更新于 3 小时前")
        XCTAssertEqual(UsageFormatting.stalenessText(fetchedAt: now.addingTimeInterval(-8 * 60), now: now).contains("8 分钟前"), true)
        XCTAssertEqual(UsageFormatting.stalenessText(fetchedAt: now.addingTimeInterval(-45), now: now).contains("45 秒前"), true)
    }

    func testResetTextNeverPresentsPastResetAsFuture() {
        let now = Date()
        let past = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 10,
                                   remainingPercent: 90, resetsAt: now.addingTimeInterval(-3600))
        let text = UsageFormatting.resetText(past, now: now)
        // v1.0.2 §4.3: reaching the reported time only means the clock arrived; the app must
        // not claim the service has renewed the window.
        XCTAssertEqual(text, "已到重置时间，等待刷新确认")
        XCTAssertFalse(text.contains("已于"), "no certainty about a renewal may be stated: \(text)")
        XCTAssertFalse(text.hasPrefix("重置"), text)

        // Exactly at the reported time counts as reached.
        let exactly = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 10,
                                      remainingPercent: 90, resetsAt: now)
        XCTAssertEqual(UsageFormatting.resetText(exactly, now: now), "已到重置时间，等待刷新确认")

        let futureToday = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 10,
                                          remainingPercent: 90, resetsAt: now.addingTimeInterval(600))
        XCTAssertTrue(UsageFormatting.resetText(futureToday, now: now).hasPrefix("重置 "))

        let unknown = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 5,
                                      remainingPercent: 95, resetsAt: nil)
        XCTAssertEqual(UsageFormatting.resetText(unknown, now: now), "重置时间未知")
    }

    func testResetPointTextUsesTheAbsoluteLocalDateAndTime() {
        let date = Date(timeIntervalSince1970: 1_788_935_373)
        let window = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                     usedPercent: 10, remainingPercent: 90, resetsAt: date)
        let text = UsageFormatting.resetPointText(window)
        XCTAssertTrue(text.contains(" "))
        XCTAssertTrue(text.contains(UsageFormatting.formatClock(date)))

        let unknown = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                      usedPercent: 0, remainingPercent: 100, resetsAt: nil)
        XCTAssertEqual(UsageFormatting.resetPointText(unknown), "时间未知")
    }

    func testRateLimitResetTextShowsCountAndNearestExpiryForLiveData() {
        let expiry = Date(timeIntervalSince1970: 1_789_000_000)
        let text = UsageFormatting.rateLimitResetText(
            RateLimitResetCredits(availableCount: 2, nearestExpiresAt: expiry),
            source: .codexAppServer,
            now: Date(timeIntervalSince1970: 1_788_935_000)
        )
        XCTAssertEqual(text, "可用重置 2 次 · 最近到期 \(UsageFormatting.formatDate(expiry)) \(UsageFormatting.formatClock(expiry))")
    }

    func testRateLimitResetTextHandlesZeroAndUnavailableSources() {
        let now = Date(timeIntervalSince1970: 1_788_935_000)
        XCTAssertEqual(UsageFormatting.rateLimitResetText(RateLimitResetCredits(availableCount: 0), source: .codexAppServer, now: now),
                       "可用重置 0 次")
        XCTAssertEqual(UsageFormatting.rateLimitResetText(RateLimitResetCredits(availableCount: 2), source: .cached, now: now),
                       "重置信息暂不可用")
        XCTAssertEqual(UsageFormatting.rateLimitResetText(nil, source: .codexAppServer, now: now),
                       "重置信息暂不可用")
    }

    func testUSDAmountUsesExactlyTwoDecimalPlaces() {
        XCTAssertEqual(UsageFormatting.usdAmount(Decimal(string: "0.008198166")), "$0.01")
        XCTAssertEqual(UsageFormatting.usdAmount(Decimal(string: "2.991801834")), "$2.99")
        XCTAssertEqual(UsageFormatting.usdAmount(Decimal(string: "5.991801834")), "$5.99")
        XCTAssertEqual(UsageFormatting.usdAmount(Decimal(string: "121.4")), "$121.40")
        XCTAssertEqual(UsageFormatting.usdAmount(nil), "—")
    }

    func testRateLimitResetTextDoesNotKeepAnExpiredNearestDate() {
        let now = Date(timeIntervalSince1970: 1_789_000_001)
        let text = UsageFormatting.rateLimitResetText(
            RateLimitResetCredits(availableCount: 1, nearestExpiresAt: now.addingTimeInterval(-1)),
            source: .codexAppServer,
            now: now
        )
        XCTAssertEqual(text, "可用重置 1 次")
    }
}

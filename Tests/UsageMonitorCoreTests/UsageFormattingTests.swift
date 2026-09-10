import XCTest
@testable import UsageMonitorCore

final class UsageFormattingTests: XCTestCase {
    let fiveHour = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 22,
                                   remainingPercent: 78, resetsAt: Date(timeIntervalSince1970: 1_788_935_373))
    let weekly = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 58,
                                 remainingPercent: 42, resetsAt: Date(timeIntervalSince1970: 1_789_453_767))

    func testMenuBarTitleShowsBothWindowsAndStaleness() {
        XCTAssertEqual(UsageFormatting.menuBarTitle(fiveHour: fiveHour, weekly: weekly, isStale: false), "5H 78% | W 42%")
        XCTAssertEqual(UsageFormatting.menuBarTitle(fiveHour: fiveHour, weekly: weekly, isStale: true), "5H 78% | W 42% ⚠")
        XCTAssertEqual(UsageFormatting.menuBarTitle(fiveHour: nil, weekly: weekly, isStale: false), "5H – | W 42%")
        XCTAssertEqual(UsageFormatting.menuBarTitle(fiveHour: nil, weekly: nil, isStale: false), "5H – | W –")
        XCTAssertEqual(UsageFormatting.compactMenuBarTitle(fiveHour: fiveHour, weekly: weekly, isStale: false), "78% / 42%")
        XCTAssertEqual(UsageFormatting.compactMenuBarTitle(fiveHour: fiveHour, weekly: nil, isStale: true), "78% / – ⚠")
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
        XCTAssertTrue(text.contains("已于"), "past reset must be marked as past: \(text)")
        XCTAssertFalse(text.hasPrefix("重置"), text)

        let futureToday = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 10,
                                          remainingPercent: 90, resetsAt: now.addingTimeInterval(600))
        XCTAssertTrue(UsageFormatting.resetText(futureToday, now: now).hasPrefix("重置 "))

        let unknown = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 5,
                                      remainingPercent: 95, resetsAt: nil)
        XCTAssertEqual(UsageFormatting.resetText(unknown, now: now), "重置时间未知")
    }
}

import XCTest
@testable import UsageMonitorCore

/// Menu bar content across the three 1.3.0 sources (UI_SPEC.md §8, REQUIREMENTS.md §6.2/§6.3).
///
/// One decision point still produces the text, the single warning and the time rows together;
/// what changed is that it now takes an already-resolved *source* instead of a lone Codex
/// display, so the DeepSeek balance and the ChatGPT profiles share exactly one code path.
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
                         label: String = "A",
                         connection: UsageService.ConnectionState = .connected,
                         mode: MenuBarSpaceMode = .full) -> MenuBarContent {
        MenuBarContentBuilder.make(source: .chatGPT(shortLabel: label, display: display,
                                                    connectionState: connection),
                                   now: now, mode: mode)
    }

    private func deepSeek(currency: String?, amount: Decimal?,
                          cached: Bool = false,
                          mode: MenuBarSpaceMode = .full) -> MenuBarContent {
        MenuBarContentBuilder.make(source: .deepSeek(MenuBarDeepSeekContent(currency: currency,
                                                                            amount: amount,
                                                                            isCached: cached)),
                                   now: now, mode: mode)
    }

    // MARK: Warning: zero or exactly one

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
        XCTAssertFalse(result.text.contains("⚠"))
        XCTAssertFalse(result.text.contains("!"))
        XCTAssertTrue(result.text.hasPrefix("A 5H"))
    }

    func testDefiniteReadFailureWithoutCacheWarnsOnce() {
        let result = content(.unavailable(.codexNotSignedIn), connection: .disconnected)
        XCTAssertEqual(result.attention, .warning)
        XCTAssertEqual(result.text, "A 5H — | W —")
    }

    func testNotYetLoadedDoesNotClaimAFailure() {
        let initial = UsageDisplay.unavailable(.rpcFailed(.other))
        XCTAssertEqual(content(initial, connection: .idle).attention, .none)
        XCTAssertEqual(content(initial, connection: .connecting).attention, .none)
        XCTAssertEqual(content(initial, connection: .disconnected).attention, .warning)
    }

    func testArrivingAtTheResetTimeAddsNoSecondWarning() {
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
        let result = content(.live(snapshot(fiveHour: nil, weekly: window(.weekly, remaining: 3 * 86400))))
        XCTAssertEqual(result.attention, .none)
        XCTAssertEqual(result.fiveHour.state, .unknown)
        XCTAssertEqual(result.weekly.state, .active)
        XCTAssertEqual(result.text, "A 5H — | W 42%")
    }

    // MARK: ChatGPT text per account and mode

    func testFullModeTextCarriesTheAccountLabelAndBothNumbers() {
        let result = content(.live(liveSnapshot()), label: "A", mode: .full)
        XCTAssertEqual(result.text, "A 5H 78% | W 42%")
        XCTAssertTrue(result.showsTimeBars)
        XCTAssertEqual(result.fiveHour.segmentCount, 5)
        XCTAssertEqual(result.weekly.segmentCount, 7)
    }

    func testAccountBIsDistinguishableFromAccountA() {
        let a = content(.live(liveSnapshot()), label: "A", mode: .full)
        let b = content(.live(liveSnapshot()), label: "B", mode: .full)
        XCTAssertEqual(b.text, "B 5H 78% | W 42%")
        XCTAssertNotEqual(a.text, b.text)
        XCTAssertNotEqual(a.sizeSignature, b.sizeSignature, "the two accounts must not share a width signature")
    }

    func testCompactModeUsesTheFixedLabelFormatAndKeepsBothRows() {
        let result = content(.live(liveSnapshot()), label: "B", mode: .compact)
        XCTAssertEqual(result.text, "B 78% 42%")
        XCTAssertFalse(result.text.contains("|"))
        XCTAssertFalse(result.text.contains("5H"))
        XCTAssertTrue(result.showsTimeBars, "compact must still show both rows")
    }

    func testChatGPTWithNoDataUsesTheFixedPlaceholderPerMode() {
        let full = content(.unavailable(.rpcFailed(.other)), connection: .disconnected, mode: .full)
        XCTAssertEqual(full.text, "A 5H — | W —")
        XCTAssertEqual(full.attention, .warning)

        let compact = content(.unavailable(.rpcFailed(.other)), connection: .disconnected, mode: .compact)
        XCTAssertEqual(compact.text, "A — —")
        XCTAssertEqual(compact.attention, .warning)
    }

    /// The account must never be swapped silently: even with no data the label stays.
    func testNoDataNeverSilentlySwitchesAccount() {
        let b = content(.unavailable(.codexNotSignedIn), label: "B", connection: .disconnected)
        XCTAssertTrue(b.text.hasPrefix("B "), b.text)
    }

    func testCachedFlagDrivesTheDimmerRows() {
        XCTAssertFalse(content(.live(liveSnapshot())).isCached)
        XCTAssertTrue(content(.stale(liveSnapshot(), .rpcFailed(.other))).isCached)
    }

    // MARK: DeepSeek text and semantics

    func testDeepSeekFullModeUsesTheFixedFormatAndNoTimeBars() {
        let result = deepSeek(currency: "CNY", amount: Decimal(string: "123.45"), mode: .full)
        XCTAssertEqual(result.text, "DS CNY 123.45")
        XCTAssertFalse(result.showsTimeBars, "the balance endpoint has no window to draw")
        XCTAssertEqual(result.attention, .none)
    }

    func testDeepSeekCompactModeUsesTheFixedFormat() {
        let result = deepSeek(currency: "CNY", amount: Decimal(string: "123.45"), mode: .compact)
        XCTAssertEqual(result.text, "DS CNY 123.45")
        XCTAssertFalse(result.showsTimeBars)
    }

    func testDeepSeekAmountIsAlwaysShownWithTwoDecimals() {
        let result = deepSeek(currency: "USD", amount: Decimal(string: "7.5"), mode: .compact)
        XCTAssertEqual(result.text, "DS USD 7.50")
    }

    func testDeepSeekWithoutACurrencyKeepsThePositionUnnamed() {
        let full = deepSeek(currency: nil, amount: Decimal(string: "123.45"), mode: .full)
        XCTAssertEqual(full.text, "DS — 123.45")
        let compact = deepSeek(currency: nil, amount: Decimal(string: "123.45"), mode: .compact)
        XCTAssertEqual(compact.text, "DS — 123.45")
    }

    func testDeepSeekWithoutAnyBalanceShowsThePlaceholderAndWarns() {
        let full = deepSeek(currency: nil, amount: nil, mode: .full)
        XCTAssertEqual(full.text, "DS —")
        XCTAssertEqual(full.attention, .warning)
        XCTAssertFalse(full.text.contains("0"), "a missing balance is never rendered as zero")

        let compact = deepSeek(currency: "CNY", amount: nil, mode: .compact)
        XCTAssertEqual(compact.text, "DS —")
        XCTAssertEqual(compact.attention, .warning)
    }

    func testCachedDeepSeekKeepsItsAmountAndAddsTheWarning() {
        let result = deepSeek(currency: "CNY", amount: Decimal(string: "123.45"), cached: true)
        XCTAssertEqual(result.text, "DS CNY 123.45", "a cached amount keeps its text")
        XCTAssertEqual(result.attention, .warning)
        XCTAssertTrue(result.isCached)
    }

    // MARK: DeepSeek currency resolution

    private func balance(_ currency: String?, available: String?, total: String? = nil) -> ProviderBalance {
        func decimal(_ raw: String?) -> Decimal? {
            guard let raw else { return nil }
            return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
        }
        return ProviderBalance(currency: currency, total: decimal(total), available: decimal(available))
    }

    func testResolverPrefersTheSavedCurrencyWhenItIsStillPresent() {
        let balances = [balance("CNY", available: "10"), balance("USD", available: "20")]
        let resolution = DeepSeekMenuBarResolver.resolve(balances: balances, savedCurrency: "USD")
        XCTAssertEqual(resolution.currency, "USD")
        XCTAssertEqual(resolution.amount, Decimal(string: "20"))
    }

    func testResolverFallsBackToCNYThenUSDThenAscendingCode() {
        let cnyUsd = DeepSeekMenuBarResolver.resolve(
            balances: [balance("USD", available: "20"), balance("CNY", available: "10")],
            savedCurrency: nil)
        XCTAssertEqual(cnyUsd.currency, "CNY")

        let usdEur = DeepSeekMenuBarResolver.resolve(
            balances: [balance("EUR", available: "5"), balance("USD", available: "20")],
            savedCurrency: nil)
        XCTAssertEqual(usdEur.currency, "USD")

        let ascending = DeepSeekMenuBarResolver.resolve(
            balances: [balance("JPY", available: "3"), balance("EUR", available: "5")],
            savedCurrency: nil)
        XCTAssertEqual(ascending.currency, "EUR", "ascending currency code")
    }

    func testResolverIgnoresASavedCurrencyThatIsNoLongerReported() {
        let resolution = DeepSeekMenuBarResolver.resolve(
            balances: [balance("JPY", available: "3")],
            savedCurrency: "CNY")
        XCTAssertEqual(resolution.currency, "JPY")
    }

    func testResolverPutsAnUnnamedBucketLastAndStillReportsItsAmount() {
        let named = DeepSeekMenuBarResolver.resolve(
            balances: [balance(nil, available: nil, total: "7"), balance("CNY", available: "10")],
            savedCurrency: nil)
        XCTAssertEqual(named.currency, "CNY", "a named currency wins over the unknown bucket")

        let onlyUnnamed = DeepSeekMenuBarResolver.resolve(
            balances: [balance(nil, available: nil, total: "7")],
            savedCurrency: nil)
        XCTAssertNil(onlyUnnamed.currency)
        XCTAssertEqual(onlyUnnamed.amount, Decimal(string: "7"))
    }

    func testResolverPrefersAvailableOverTotalAndNeverInventsZero() {
        let both = DeepSeekMenuBarResolver.resolve(
            balances: [balance("CNY", available: "4", total: "10")],
            savedCurrency: nil)
        XCTAssertEqual(both.amount, Decimal(string: "4"))

        let totalOnly = DeepSeekMenuBarResolver.resolve(
            balances: [balance("CNY", available: nil, total: "10")],
            savedCurrency: nil)
        XCTAssertEqual(totalOnly.amount, Decimal(string: "10"))

        let neither = DeepSeekMenuBarResolver.resolve(
            balances: [balance("CNY", available: nil, total: nil)],
            savedCurrency: nil)
        XCTAssertNil(neither.amount, "no amount is not a zero amount")

        XCTAssertFalse(DeepSeekMenuBarResolver.resolve(balances: [], savedCurrency: nil).hasAmount)
    }

    func testDeepSeekSizeSignatureFollowsTheAmountAndTheCode() {
        let first = deepSeek(currency: "CNY", amount: Decimal(string: "123.45"))
        let second = deepSeek(currency: "CNY", amount: Decimal(string: "9.00"))
        XCTAssertNotEqual(first.sizeSignature, second.sizeSignature, "a different amount is a different width")

        let cached = deepSeek(currency: "CNY", amount: Decimal(string: "123.45"), cached: true)
        XCTAssertNotEqual(first.sizeSignature, cached.sizeSignature, "the warning changes the width")
    }

    // MARK: Size signature excludes time

    func testSizeSignatureIgnoresTheCountdown() {
        let display = UsageDisplay.live(liveSnapshot())
        let first = MenuBarContentBuilder.make(source: .chatGPT(shortLabel: "A", display: display,
                                                                connectionState: .connected),
                                               now: now, mode: .full)
        let later = MenuBarContentBuilder.make(source: .chatGPT(shortLabel: "A", display: display,
                                                                connectionState: .connected),
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

        let compact = content(.live(liveSnapshot()), mode: .compact)
        XCTAssertNotEqual(base.sizeSignature, compact.sizeSignature)
    }

    // MARK: Rows react to the right input

    func testChangingOnlyTheWeeklyResetLeavesTheHourRowAlone() {
        let before = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600),
                                            weekly: window(.weekly, remaining: 7 * 86400))))
        let after = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600),
                                           weekly: window(.weekly, remaining: 86400))))
        XCTAssertEqual(before.fiveHour.fills, after.fiveHour.fills, "the hour row must not move")
        XCTAssertNotEqual(before.weekly.fills, after.weekly.fills, "the week row must move")
    }

    func testUnchangedQuotaWithANewResetTimeStillMovesTheRow() {
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
        XCTAssertTrue(active.accessibilityText.contains("A 5H 78% | W 42%"))

        let arrived = content(.live(snapshot(fiveHour: window(.fiveHour, remaining: -5),
                                             weekly: window(.weekly, remaining: -5))))
        XCTAssertTrue(arrived.accessibilityText.contains("等待刷新确认"), arrived.accessibilityText)

        let unknown = content(.live(snapshot(fiveHour: nil, weekly: nil)))
        XCTAssertTrue(unknown.accessibilityText.contains("重置时间未知"), unknown.accessibilityText)

        let warned = content(.stale(liveSnapshot(), .rpcFailed(.other)))
        XCTAssertTrue(warned.accessibilityText.contains("异常提示"), warned.accessibilityText)
    }

    func testDeepSeekAccessibilityTextCarriesNoWindowRows() {
        let text = deepSeek(currency: "CNY", amount: Decimal(string: "123.45")).accessibilityText
        XCTAssertTrue(text.contains("DS CNY 123.45"))
        XCTAssertFalse(text.contains("5 小时"))
        XCTAssertFalse(text.contains("周额度"))
    }

    // MARK: No snapshot at all

    func testNoSnapshotLeavesQuotaAsPlaceholderAndBothRowsUnknown() {
        let result = content(.unavailable(.rpcFailed(.other)), connection: .disconnected)
        XCTAssertEqual(result.text, "A 5H — | W —")
        XCTAssertEqual(result.fiveHour.state, .unknown)
        XCTAssertEqual(result.weekly.state, .unknown)
        XCTAssertEqual(result.fiveHour.fills, [0, 0, 0, 0, 0])
        XCTAssertEqual(result.weekly.fills, [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(result.attention, .warning, "a definite failure keeps the single warning")
        XCTAssertFalse(result.isCached, "no cache is not cached data")
    }

    func testInvalidTimingShowsADimRowRatherThanAnInventedCountdown() {
        let mismatched = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 600, usedPercent: 10,
                                         remainingPercent: 90, resetsAt: now.addingTimeInterval(3600))
        let result = content(.live(snapshot(fiveHour: mismatched, weekly: nil)))
        XCTAssertEqual(result.fiveHour.state, .invalid)
        XCTAssertTrue(result.fiveHour.hasNoBrightSegment)
        XCTAssertEqual(result.fiveHour.segmentCount, 5, "the row keeps its 5 segments and shows a ? instead")
    }
}

import XCTest
import SwiftUI
import AppKit
@testable import UsageMonitorApp
@testable import UsageMonitorCore

@MainActor
final class OverviewPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_827_200)

    private func window(_ kind: RateLimitWindow.Kind, percent: Double, reset: Date?) -> RateLimitWindow {
        RateLimitWindow(kind: kind, windowDurationMinutes: kind == .fiveHour ? 300 : 10080,
                        usedPercent: 100 - percent, remainingPercent: percent, resetsAt: reset)
    }

    func testGeminiMissingQuotaRetainsKnownTimeAndNeverUsesSharedPool() throws {
        let reset = now.addingTimeInterval(7200)
        let primary = AntigravityQuotaGroup(id: "gemini", label: "Gemini Models", models: [], buckets: [
            AntigravityQuotaBucket(id: "5", label: "Five Hour", window: "5h", remainingFraction: nil, resetsAt: reset)
        ])
        let shared = AntigravityQuotaGroup(id: "shared", label: "Claude and GPT models", models: [], buckets: [
            AntigravityQuotaBucket(id: "s", label: "Five Hour", window: "5h", remainingFraction: 1, resetsAt: reset)
        ])
        guard case .quotas(let five, let week) = OverviewUsageSummary.gemini([shared, primary]) else { return XCTFail() }
        XCTAssertNil(five.fraction)
        XCTAssertEqual(five.percentage, "—")
        XCTAssertEqual(five.progress(now: now).segmentCount, 5)
        XCTAssertTrue(five.description(now: now).contains(QuotaPresentation.reset(reset, now: now)))
        XCTAssertEqual(week.progress(now: now), .unavailable)
        guard case .quotas(let absent, _) = OverviewUsageSummary.gemini([shared]) else { return XCTFail() }
        XCTAssertNil(absent.fraction)
        XCTAssertEqual(absent.progress(now: now), .unavailable)
    }

    func testCodexOverviewAgreesWithDetailForZeroMissingAndExpiredReset() {
        let five = window(.fiveHour, percent: 0, reset: now)
        let week = window(.weekly, percent: 53.125, reset: now.addingTimeInterval(86400))
        let snapshot = UsageSnapshot(fiveHour: five, weekly: week, fetchedAt: now, source: .codexAppServer)
        guard case .quotas(let first, let second) = OverviewUsageSummary.codex(snapshot) else { return XCTFail() }
        XCTAssertEqual(first.percentage, "0.00%")
        XCTAssertEqual(first.fraction, 0)
        XCTAssertEqual(first.progress(now: now), .arrived)
        XCTAssertTrue(first.description(now: now).contains("等待刷新"))
        XCTAssertEqual(second.percentage, QuotaPresentation.percentage(week.remainingPercent))
        XCTAssertEqual(second.progress(now: now), CodexProfileCard.timeProgress(ResetTimeModel.progress(expected: .weekly, window: week, now: now)))
        XCTAssertEqual(second.progress(now: now).segmentCount, 7)
        guard case .quotas(let missing, _) = OverviewUsageSummary.codex(nil) else { return XCTFail() }
        XCTAssertEqual(missing.percentage, "—")
        XCTAssertNil(missing.fraction)
    }

    func testOverviewColorsFollowDetailThresholdsAndRejectUnknownValues() {
        for (percent, color) in [(50.01, Color.green), (50.0, .orange), (20.0, .orange), (19.99, .red), (0, .red)] {
            let quota = OverviewQuotaWindow(kind: .fiveHour, window: window(.fiveHour, percent: percent, reset: nil))
            XCTAssertEqual(quota.color, color)
        }
        for percent in [Double.nan, .infinity, -1, 101] {
            let quota = OverviewQuotaWindow(kind: .fiveHour, window: window(.fiveHour, percent: percent, reset: nil))
            XCTAssertEqual(quota.percentage, "—")
            XCTAssertNil(quota.fraction)
            XCTAssertEqual(quota.color, .secondary)
        }
    }

    /// 1.6.6: the Antigravity pool that covers Claude and GPT models is drawn in Claude's
    /// brand orange, and the critical band is the only alert that survives there. Every
    /// other row keeps the level colours.
    func testClaudeModelPoolUsesClaudeOrangeAndOnlyTheCriticalBand() {
        for percent in [100.0, 50.01, 50, 20] {
            XCTAssertEqual(QuotaUsageTint.claudeModels.color(percent), QuotaUsageTint.claudeOrange)
        }
        for percent in [19.99, 0] {
            XCTAssertEqual(QuotaUsageTint.claudeModels.color(percent), .red)
        }
        for percent in [Double.nan, .infinity, -1, 101] {
            XCTAssertEqual(QuotaUsageTint.claudeModels.color(percent), .secondary)
        }
        XCTAssertEqual(QuotaUsageTint.levels.color(50.01), .green, "the primary pool keeps the level colours")
        XCTAssertEqual(QuotaUsageTint.levels.color(50), .orange)
        XCTAssertEqual(QuotaUsageTint.levels.color(19.99), .red)
    }

    /// 1.6.6: two quota columns take the same 224 pt the two-credit row takes, so the
    /// ChatGPT and Gemini bars are exactly as long as the Command Code ones. A single
    /// column still keeps the 1.6.2 width.
    func testTwoColumnQuotaGraphicMatchesTheTwoCreditWidth() {
        let snapshot = UsageSnapshot(fiveHour: window(.fiveHour, percent: 98, reset: nil),
                                     weekly: window(.weekly, percent: 53, reset: nil),
                                     fetchedAt: now, source: .codexAppServer)
        XCTAssertEqual(OverviewUsageSummary.codex(snapshot).graphicWidth, 224)
        XCTAssertEqual(OverviewUsageSummary.gemini([]).graphicWidth, 224)
    }

    /// 1.6.6: every reported pool is drawn in place. The primary pool is never repeated
    /// among the others, the service's order is kept, and only the shared pool that covers
    /// Claude and GPT models takes Claude's colour.
    func testOtherGroupsExcludeThePrimaryPoolAndKeepTheReportedOrder() {
        let primary = AntigravityQuotaGroup(id: "Gemini Models", label: "Gemini Models", models: [], buckets: [])
        let shared = AntigravityQuotaGroup(id: "shared", label: "Claude and GPT models", models: [], buckets: [])
        XCTAssertEqual(QuotaPresentation.otherGroups([primary, shared]).map(\.id), [shared.id])
        XCTAssertEqual(QuotaPresentation.otherGroups([shared, primary]).map(\.id), [shared.id])
        XCTAssertTrue(QuotaPresentation.otherGroups([primary]).isEmpty)
        XCTAssertEqual(QuotaPresentation.tint(for: primary), .levels)
        XCTAssertEqual(QuotaPresentation.tint(for: shared), .claudeModels)
    }

    func testBalancesRetainCurrenciesAndCreditAmountDoesNotInventLimit() {
        let cny = ProviderBalance(currency: "CNY", total: 100, available: Decimal(string: "89.67"))
        let usd = ProviderBalance(currency: "USD", total: 2)
        let description = OverviewUsageSummary.balances([cny, usd]).description(now: now)
        XCTAssertTrue(description.contains("可用余额 ¥89.67"))
        XCTAssertTrue(description.contains("余额 2.00 USD"))
        XCTAssertEqual(OverviewUsageSummary.balances([]).description(now: now), "余额暂不可用")

        // A five-hour window with only a remainder keeps that remainder and invents no limit,
        // and a row with nothing else to show stays single-column at the 1.6.2 width.
        let credit = ProviderUsageWindow(kind: .fiveHour, used: nil, limit: nil, remaining: 3, resetsAt: now)
        XCTAssertNil(credit.remainingFraction)
        let summary = OverviewUsageSummary.commandCode(ProviderUsage(windows: [credit], summary: nil))
        XCTAssertEqual(summary.description(now: now), "5 小时 $3.00 / —，重置时间 等待刷新")
        XCTAssertEqual(summary.graphicWidth, 164)
        guard case .credits(_, let second) = summary else { return XCTFail() }
        XCTAssertNil(second)
    }

    /// The Command Code row draws the widest window that really arrived: the monthly credit
    /// balance when the service reported one, the weekly window only as the fallback, and
    /// nothing when neither is usable (REQUIREMENTS.md §5.2).
    func testCommandCodeOverviewPrefersMonthlyThenWeeklyAndNeverInventsOne() {
        let five = ProviderUsageWindow(kind: .fiveHour, used: dec("0.05"), limit: dec("3"), remaining: nil,
                                       resetsAt: now.addingTimeInterval(7200))
        let week = ProviderUsageWindow(kind: .weekly, used: dec("1.57"), limit: dec("6"), remaining: nil,
                                       resetsAt: now.addingTimeInterval(4 * 86400))
        let month = ProviderUsageWindow(kind: .billingPeriod, used: dec("6.5"), limit: dec("10"),
                                        remaining: dec("3.5"), resetsAt: nil)
        let full = ProviderUsage(windows: [five, week, month], summary: nil,
                                 billingPeriodEnd: now.addingTimeInterval(11 * 86400),
                                 billingPeriodStart: now.addingTimeInterval(-19 * 86400))

        let summary = OverviewUsageSummary.commandCode(full)
        guard case .credits(let first, let monthly) = summary else { return XCTFail() }
        XCTAssertEqual(first.label, "5H")
        XCTAssertEqual(first.amountText, "$2.95 / $3.00")
        XCTAssertEqual(monthly?.label, "月")
        XCTAssertEqual(monthly?.fullLabel, "本月")
        XCTAssertEqual(monthly?.amountText, "$3.50 / $10.00")
        XCTAssertEqual(monthly?.fraction ?? 0, 0.35, accuracy: 0.0001)
        XCTAssertEqual(monthly?.isCached, false)
        XCTAssertEqual(monthly?.resetsAt, now.addingTimeInterval(11 * 86400))
        guard case .continuous(let fill)? = monthly?.progress(now: now) else {
            return XCTFail("the monthly rail must be continuous")
        }
        XCTAssertEqual(fill, 11.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(summary.graphicWidth, 224, "two money columns need the wider graphic")
        let text = summary.description(now: now)
        XCTAssertTrue(text.contains("5 小时 $2.95 / $3.00"))
        XCTAssertTrue(text.contains("本月 $3.50 / $10.00"))

        // The weekly fallback: no monthly window at all, or a monthly row whose remainder
        // could not be read. Neither may be dressed up as an empty monthly box.
        let usedOnlyMonth = ProviderUsageWindow(kind: .billingPeriod, used: dec("6.5"), limit: nil,
                                                remaining: nil, resetsAt: nil)
        for windows in [[five, week], [five, week, usedOnlyMonth]] {
            let fallback = OverviewUsageSummary.commandCode(ProviderUsage(windows: windows, summary: nil))
            guard case .credits(_, let second) = fallback else { return XCTFail() }
            XCTAssertEqual(second?.label, "周", "the weekly window is the fallback")
            XCTAssertEqual(second?.amountText, "$4.43 / $6.00")
            XCTAssertEqual(second?.resetsAt, now.addingTimeInterval(4 * 86400))
            XCTAssertEqual(second?.progress(now: now).segmentCount, 7)
        }

        // Only the five-hour window: one column, and the width stays at the 1.6.2 value.
        let fiveOnly = OverviewUsageSummary.commandCode(ProviderUsage(windows: [five], summary: nil))
        guard case .credits(_, let absent) = fiveOnly else { return XCTFail() }
        XCTAssertNil(absent)
        XCTAssertEqual(fiveOnly.graphicWidth, 164)

        // A monthly column built from cached auxiliary payloads is marked as cached, while
        // the live five-hour column beside it is not.
        let cachedMonthly = ProviderUsage(windows: [five, month], summary: nil,
                                          billingPeriodEnd: now.addingTimeInterval(11 * 86400),
                                          billingPeriodStart: now.addingTimeInterval(-19 * 86400),
                                          summaryFreshness: ProviderUsageComponentFreshness(lastSuccessfulAt: now.addingTimeInterval(-600), isLive: false))
        guard case .credits(let live, let cached) = OverviewUsageSummary.commandCode(cachedMonthly) else { return XCTFail() }
        XCTAssertFalse(live.isCached)
        XCTAssertEqual(cached?.isCached, true)

        // Nothing at all: the row keeps its placeholders and never fabricates a window.
        guard case .credits(_, let empty) = OverviewUsageSummary.commandCode(nil) else { return XCTFail() }
        XCTAssertNil(empty)
        XCTAssertEqual(OverviewUsageSummary.commandCode(nil).description(now: now), "5 小时 —，重置时间 时间未知")
    }

    private func dec(_ raw: String) -> Decimal {
        Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))!
    }

    /// Explicit opt-in export of production components with synthetic data only.
    func testExportOverviewExamples() throws {
        guard let destination = ProcessInfo.processInfo.environment["MINGET_OVERVIEW_EVIDENCE"] else { return }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let snapshot = UsageSnapshot(fiveHour: window(.fiveHour, percent: 98, reset: now.addingTimeInterval(7200)),
            weekly: window(.weekly, percent: 53, reset: now.addingTimeInterval(5 * 86400)), fetchedAt: now, source: .codexAppServer)
        let low = UsageSnapshot(fiveHour: window(.fiveHour, percent: 20, reset: now.addingTimeInterval(3600)),
            weekly: window(.weekly, percent: 0, reset: now), fetchedAt: now, source: .codexAppServer)
        let knownTime = AntigravityQuotaGroup(id: "gemini", label: "Gemini Models", models: [], buckets: [
            AntigravityQuotaBucket(id: "5", label: "Five Hour", window: "5h", remainingFraction: nil, resetsAt: now.addingTimeInterval(7200))
        ])
        for dark in [false, true] {
            let rows = VStack(spacing: 12) {
                OverviewAccountRow(service: .chatGPT, name: "主账号 A", status: "已连接", summary: .codex(snapshot), referenceDate: now) {}
                OverviewAccountRow(service: .chatGPT, name: "友情账号 B", status: "已连接", summary: .codex(snapshot), referenceDate: now) {}
                OverviewAccountRow(service: .gemini, name: "示例 Gemini A", status: "额度已更新", summary: .codex(snapshot), referenceDate: now) {}
                OverviewAccountRow(service: .gemini, name: "示例 Gemini B", status: "额度已更新", summary: .codex(snapshot), referenceDate: now) {}
                OverviewAccountRow(service: .deepSeek, name: "API 账号", status: "已连接", summary: .balances([ProviderBalance(currency: "CNY", total: Decimal(string: "89.67"))]), referenceDate: now) {}
                OverviewAccountRow(service: .commandCode, name: "GO $1", status: "已连接", summary: .commandCode(commandCodeUsage), referenceDate: now) {}
            }
            try export(rows, dark: dark, to: output.appendingPathComponent("overview-\(dark ? "dark" : "light").png"))
            let edges = VStack(spacing: 12) {
                OverviewAccountRow(service: .chatGPT, name: "这是一个很长的自定义账号名称 ABCDEFG", status: "缓存数据", summary: .codex(snapshot), isCached: true, referenceDate: now) {}
                OverviewAccountRow(service: .chatGPT, name: "阈值与真实零", status: "已连接", summary: .codex(low), referenceDate: now) {}
                OverviewAccountRow(service: .gemini, name: "额度缺失时间已知", status: "缓存 · 暂时无法读取额度，请稍后重试", summary: .gemini([knownTime]), isCached: true, referenceDate: now) {}
                OverviewAccountRow(service: .gemini, name: "未连接", status: "未连接", summary: .gemini([]), referenceDate: now) {}
                OverviewAccountRow(service: .deepSeek, name: "余额暂不可用", status: "需要重新连接", summary: .balances([]), referenceDate: now) {}
                OverviewAccountRow(service: .commandCode, name: "部分金额", status: "缓存数据", summary: .commandCode(ProviderUsage(windows: [ProviderUsageWindow(kind: .fiveHour, used: nil, limit: nil, remaining: 3, resetsAt: now)], summary: nil)), isCached: true, referenceDate: now) {}
                OverviewAccountRow(service: .commandCode, name: "只有周额度", status: "已连接", summary: .commandCode(ProviderUsage(windows: [ProviderUsageWindow(kind: .fiveHour, used: nil, limit: 3, remaining: nil, resetsAt: now.addingTimeInterval(7200)), ProviderUsageWindow(kind: .weekly, used: nil, limit: 6, remaining: 4.43, resetsAt: now.addingTimeInterval(4 * 86400))], summary: nil)), referenceDate: now) {}
            }
            try export(edges, dark: dark, height: 612, to: output.appendingPathComponent("overview-edge-\(dark ? "dark" : "light").png"))
        }
    }

    /// Synthetic Command Code usage for the example export: the same three-window shape the
    /// service returns, so the two-column overview row is exercised end to end.
    private var commandCodeUsage: ProviderUsage {
        ProviderUsage(windows: [
            ProviderUsageWindow(kind: .fiveHour, used: dec("0.05"), limit: dec("3"), remaining: dec("2.95"),
                                resetsAt: now.addingTimeInterval(7200)),
            ProviderUsageWindow(kind: .weekly, used: dec("1.57"), limit: dec("6"), remaining: dec("4.43"),
                                resetsAt: now.addingTimeInterval(4 * 86400)),
            ProviderUsageWindow(kind: .billingPeriod, used: dec("6.5"), limit: dec("10"), remaining: dec("3.5"),
                                resetsAt: nil)
        ], summary: nil,
        billingPeriodEnd: now.addingTimeInterval(11 * 86400),
        billingPeriodStart: now.addingTimeInterval(-19 * 86400))
    }

    private func export<V: View>(_ rows: V, dark: Bool, height: CGFloat = 536, to url: URL) throws {
        let size = NSSize(width: 440, height: height)
        let view = VStack(alignment: .leading, spacing: 12) {
            Text("明明有数 1.6.5 · 展示副本").font(.system(size: 17, weight: .semibold))
            Text("示例账号与数据 · 生产概览组件").font(.system(size: 11)).foregroundStyle(.secondary)
            rows
        }.padding(16).frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(NSColor.windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(size)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}

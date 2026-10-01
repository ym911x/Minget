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

    func testBalancesRetainCurrenciesAndCreditAmountDoesNotInventLimit() {
        let cny = ProviderBalance(currency: "CNY", total: 100, available: Decimal(string: "89.67"))
        let usd = ProviderBalance(currency: "USD", total: 2)
        let description = OverviewUsageSummary.balances([cny, usd]).description(now: now)
        XCTAssertTrue(description.contains("可用余额 ¥89.67"))
        XCTAssertTrue(description.contains("余额 2.00 USD"))
        XCTAssertEqual(OverviewUsageSummary.balances([]).description(now: now), "余额暂不可用")
        let credit = ProviderUsageWindow(kind: .fiveHour, used: nil, limit: nil, remaining: 3, resetsAt: now)
        XCTAssertNil(credit.remainingFraction)
        XCTAssertEqual(OverviewUsageSummary.credits(credit).description(now: now), "5 小时 $3.00 / —，重置 等待刷新")
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
                OverviewAccountRow(service: .commandCode, name: "GO $1", status: "已连接", summary: .credits(ProviderUsageWindow(kind: .fiveHour, used: 0, limit: 3, remaining: 3, resetsAt: now.addingTimeInterval(7200))), referenceDate: now) {}
            }
            try export(rows, dark: dark, to: output.appendingPathComponent("overview-\(dark ? "dark" : "light").png"))
            let edges = VStack(spacing: 12) {
                OverviewAccountRow(service: .chatGPT, name: "这是一个很长的自定义账号名称 ABCDEFG", status: "缓存数据", summary: .codex(snapshot), isCached: true, referenceDate: now) {}
                OverviewAccountRow(service: .chatGPT, name: "阈值与真实零", status: "已连接", summary: .codex(low), referenceDate: now) {}
                OverviewAccountRow(service: .gemini, name: "额度缺失时间已知", status: "缓存 · 暂时无法读取额度，请稍后重试", summary: .gemini([knownTime]), isCached: true, referenceDate: now) {}
                OverviewAccountRow(service: .gemini, name: "未连接", status: "未连接", summary: .gemini([]), referenceDate: now) {}
                OverviewAccountRow(service: .deepSeek, name: "余额暂不可用", status: "需要重新连接", summary: .balances([]), referenceDate: now) {}
                OverviewAccountRow(service: .commandCode, name: "部分金额", status: "缓存数据", summary: .credits(ProviderUsageWindow(kind: .fiveHour, used: nil, limit: nil, remaining: 3, resetsAt: now)), isCached: true, referenceDate: now) {}
            }
            try export(edges, dark: dark, to: output.appendingPathComponent("overview-edge-\(dark ? "dark" : "light").png"))
        }
    }

    private func export<V: View>(_ rows: V, dark: Bool, to url: URL) throws {
        let size = NSSize(width: 440, height: 536)
        let view = VStack(alignment: .leading, spacing: 12) {
            Text("明明有数 1.6.2 · 展示副本").font(.system(size: 17, weight: .semibold))
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

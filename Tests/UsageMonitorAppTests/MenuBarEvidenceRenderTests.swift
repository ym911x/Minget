import AppKit
import SwiftUI
import XCTest
@testable import UsageMonitorCore
@testable import UsageMonitorApp

/// Renders the production menu bar label from fixed fixtures.
///
/// 1.3.0 evidence goes to `$TMPDIR/Minget-1.3.0-Evidence/` (IMPLEMENTATION_TASKS.md §6.2):
/// automated tests must never write into `docs/archive/`, `docs/versions/1.0.2/` or any other
/// historical evidence directory. The images are fixture renders of the real view code, not
/// screenshots, and use example numbers only.
@MainActor
final class MenuBarEvidenceRenderTests: XCTestCase {

    private static let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            throw XCTSkip("AppKit hosting requires a logged-in macOS window server")
        }
    }

    // MARK: Fixtures

    private func window(_ kind: RateLimitWindow.Kind,
                        remaining: TimeInterval,
                        remainingPercent: Double) -> RateLimitWindow {
        switch kind {
        case .fiveHour:
            return RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                   usedPercent: 100 - remainingPercent, remainingPercent: remainingPercent,
                                   resetsAt: Self.anchor.addingTimeInterval(remaining))
        case .weekly:
            return RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                   usedPercent: 100 - remainingPercent, remainingPercent: remainingPercent,
                                   resetsAt: Self.anchor.addingTimeInterval(remaining))
        case .unknown:
            return RateLimitWindow(kind: .unknown, windowDurationMinutes: 60, usedPercent: 1,
                                   remainingPercent: 99, resetsAt: Self.anchor.addingTimeInterval(remaining))
        }
    }

    private func live(fiveHourRemaining: TimeInterval,
                      weeklyRemaining: TimeInterval,
                      fiveHourPercent: Double = 78,
                      weeklyPercent: Double = 42) -> UsageDisplay {
        let snapshot = UsageSnapshot(fiveHour: window(.fiveHour, remaining: fiveHourRemaining, remainingPercent: fiveHourPercent),
                                     weekly: window(.weekly, remaining: weeklyRemaining, remainingPercent: weeklyPercent),
                                     fetchedAt: Self.anchor,
                                     source: .codexAppServer)
        return .live(snapshot)
    }

    private func content(_ display: UsageDisplay,
                         label: String = "A",
                         connection: UsageService.ConnectionState = .connected,
                         mode: MenuBarSpaceMode = .full) -> MenuBarContent {
        MenuBarContentBuilder.make(source: .chatGPT(shortLabel: label, display: display,
                                                    connectionState: connection),
                                   now: Self.anchor, mode: mode)
    }

    private func deepSeek(currency: String?, amount: Decimal?,
                          cached: Bool = false,
                          mode: MenuBarSpaceMode = .full) -> MenuBarContent {
        MenuBarContentBuilder.make(source: .deepSeek(MenuBarDeepSeekContent(currency: currency,
                                                                            amount: amount,
                                                                            isCached: cached)),
                                   now: Self.anchor, mode: mode)
    }

    // MARK: Evidence

    func testRenderStateMatrix() throws {
        let cached = UsageDisplay.stale(
            UsageSnapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600, remainingPercent: 78),
                          weekly: window(.weekly, remaining: 3 * 86400, remainingPercent: 42),
                          fetchedAt: Self.anchor, source: .cached),
            .rpcFailed(.timedOut(method: "account/rateLimits/read")))
        let failed = UsageDisplay.unavailable(.codexNotSignedIn)
        let empty = UsageDisplay.live(UsageSnapshot(fiveHour: nil, weekly: nil,
                                                   fetchedAt: Self.anchor, source: .codexAppServer))

        let rows: [(String, MenuBarContent)] = [
            ("UI-01/02 正常完整 4h / 3d", content(live(fiveHourRemaining: 4 * 3600, weeklyRemaining: 3 * 86400))),
            ("UI-02 满格 5h / 7d", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 7 * 86400))),
            ("UI-03 2h30m / 3d12h", content(live(fiveHourRemaining: 2.5 * 3600, weeklyRemaining: 3.5 * 86400))),
            ("UI-03 30m / 6h", content(live(fiveHourRemaining: 0.5 * 3600, weeklyRemaining: 6 * 3600))),
            ("UI-05 到重置时间（空）", content(live(fiveHourRemaining: -10, weeklyRemaining: -10))),
            ("UI-06 未知窗口（? 状态）", content(empty)),
            ("UI-06 缓存（单一前置警告 + 变暗）", content(cached)),
            ("UI-06 确定读取失败", content(failed, connection: .disconnected)),
            ("§5.2.3 首次加载中（无警告）", content(.unavailable(.rpcFailed(.other)), connection: .connecting)),
            ("UI-08 100% / 100%（最宽文字）", content(live(fiveHourRemaining: 4 * 3600, weeklyRemaining: 3 * 86400,
                                                        fiveHourPercent: 100, weeklyPercent: 100))),
            ("UI-09 紧凑模式（双额度、双时间条）", content(live(fiveHourRemaining: 4 * 3600, weeklyRemaining: 3 * 86400),
                                                 mode: .compact)),
        ]

        try write(try renderImage(rows, background: .light), named: "01-menubar-states-light.png")
        try write(try renderImage(rows, background: .dark), named: "02-menubar-states-dark.png")
    }

    /// 1.3.0 UI_SPEC.md §10 item 6: the three menu bar sources in both modes.
    func testRenderThreeSources() throws {
        let snapshot = UsageSnapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600, remainingPercent: 78),
                                     weekly: window(.weekly, remaining: 3 * 86400, remainingPercent: 42),
                                     fetchedAt: Self.anchor, source: .codexAppServer)
        let cachedSnapshot = UsageSnapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600, remainingPercent: 78),
                                           weekly: window(.weekly, remaining: 3 * 86400, remainingPercent: 42),
                                           fetchedAt: Self.anchor, source: .cached)

        let rows: [(String, MenuBarContent)] = [
            ("ChatGPT A 完整 A 5H 78% | W 42%", content(.live(snapshot), label: "A", mode: .full)),
            ("ChatGPT A 紧凑 A 78% 42%", content(.live(snapshot), label: "A", mode: .compact)),
            ("ChatGPT B 完整 B 5H 78% | W 42%", content(.live(snapshot), label: "B", mode: .full)),
            ("ChatGPT B 紧凑 B 78% 42%", content(.live(snapshot), label: "B", mode: .compact)),
            ("ChatGPT A 无数据 完整", content(.unavailable(.rpcFailed(.other)), label: "A", connection: .disconnected, mode: .full)),
            ("ChatGPT A 无数据 紧凑", content(.unavailable(.rpcFailed(.other)), label: "A", connection: .disconnected, mode: .compact)),
            ("ChatGPT A 缓存（前置警告）", content(.stale(cachedSnapshot, .rpcFailed(.other)), label: "A", mode: .full)),
            ("DeepSeek 完整 DS CNY 123.45", deepSeek(currency: "CNY", amount: Decimal(string: "123.45"), mode: .full)),
            ("DeepSeek 紧凑 DS CNY 123.45", deepSeek(currency: "CNY", amount: Decimal(string: "123.45"), mode: .compact)),
            ("DeepSeek 币种缺失 DS — 123.45", deepSeek(currency: nil, amount: Decimal(string: "123.45"), mode: .full)),
            ("DeepSeek 缓存（同一金额 + 警告）", deepSeek(currency: "CNY", amount: Decimal(string: "123.45"), cached: true, mode: .full)),
            ("DeepSeek 无余额 DS —（警告）", deepSeek(currency: nil, amount: nil, mode: .full)),
        ]
        try write(try renderImage(rows, background: .light), named: "09-three-sources-light.png")
        try write(try renderImage(rows, background: .dark), named: "10-three-sources-dark.png")
    }

    func testRenderDirectionAndBars() throws {
        let directionRows: [(String, MenuBarContent)] = [
            ("剩余 5h00m", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 3h00m", content(live(fiveHourRemaining: 3 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 1h00m", content(live(fiveHourRemaining: 1 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 0（已到）", content(live(fiveHourRemaining: 0, weeklyRemaining: 7 * 86400))),
        ]
        try write(try renderBarsDetail(directionRows, background: .light), named: "03-direction-light.png")

        let weeklyRows: [(String, MenuBarContent)] = [
            ("周剩余 7d", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 7 * 86400))),
            ("周剩余 3d12h", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 3.5 * 86400))),
            ("周剩余 1d", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 86400))),
            ("周剩余 0（已到）", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 0))),
        ]
        try write(try renderBarsDetail(weeklyRows, background: .light), named: "04-weekly-direction-light.png")
    }

    // MARK: Rendering

    private enum Background {
        case light, dark

        var color: Color {
            switch self {
            case .light: return Color(red: 0.96, green: 0.96, blue: 0.96)
            case .dark: return Color(red: 0.13, green: 0.13, blue: 0.13)
            }
        }

        var appearance: NSAppearance.Name {
            switch self {
            case .light: return .aqua
            case .dark: return .darkAqua
            }
        }
    }

    private func renderBarsDetail(_ rows: [(String, MenuBarContent)], background: Background) throws -> Data {
        let panel = VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.0).font(.system(size: 10)).foregroundStyle(.secondary)
                    ResetTimeBarsView(fiveHour: row.1.fiveHour,
                                      weekly: row.1.weekly,
                                      width: 160,
                                      isCached: row.1.isCached)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(background.color)
        .environment(\.colorScheme, background == .dark ? .dark : .light)
        return try rasterise(panel, appearance: background.appearance, scale: 6)
    }

    private func renderImage(_ rows: [(String, MenuBarContent)], background: Background) throws -> Data {
        let panel = VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .center, spacing: 10) {
                    Text(row.0)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 240, alignment: .leading)
                    MenuBarLabelContent(content: row.1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(background.color, in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(14)
        .background(background.color)
        .environment(\.colorScheme, background == .dark ? .dark : .light)
        return try rasterise(panel, appearance: background.appearance, scale: 4)
    }

    /// Renders any SwiftUI view offscreen at `scale`. Used only for evidence images.
    private func rasterise<V: View>(_ view: V, appearance: NSAppearance.Name, scale: CGFloat) throws -> Data {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: 10, height: 10)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: Int(size.width * scale),
                                                 pixelsHigh: Int(size.height * scale),
                                                 bitsPerSample: 8,
                                                 samplesPerPixel: 4,
                                                 hasAlpha: true,
                                                 isPlanar: false,
                                                 colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0,
                                                 bitsPerPixel: 0))
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// Evidence output is confined to the 1.3.0 temporary directory.
    private func write(_ data: Data, named name: String) throws {
        let directory = try Self.evidenceDirectory()
        try data.write(to: directory.appendingPathComponent(name))
    }

    /// `$TMPDIR/Minget-1.3.0-Evidence/`, overridable with `MINGET_EVIDENCE_DIR` for a manual
    /// review pass. Never a repository path.
    static func evidenceDirectory() throws -> URL {
        let base = ProcessInfo.processInfo.environment["MINGET_EVIDENCE_DIR"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("Minget-1.3.0-Evidence")
        let url = URL(fileURLWithPath: base, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

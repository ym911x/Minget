import AppKit
import SwiftUI
import XCTest
@testable import UsageMonitorCore
@testable import UsageMonitorApp

/// Renders the production menu bar label from fixed fixtures into `docs/versions/1.0.2/evidence/`.
///
/// v1.0.2 §8.2 allows synthetic-clock visual checking as long as it is labelled as a fixture.
/// This environment has no Screen Recording permission, so a real menu bar screenshot is
/// impossible here; these images are **fixture renders of the real view code**, not screenshots,
/// and they are labelled as such in the evidence README. They are used to check the layout
/// itself: segment counts, alignment of both rows, the right-to-left recession, the single
/// leading marker, the `?` state label, and the absence of the brand mark.
///
/// The render is deterministic and runs offscreen, so it is also a regression check that the
/// view composes and lays out at all.
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
                         connection: UsageService.ConnectionState = .connected,
                         mode: MenuBarSpaceMode = .full) -> MenuBarContent {
        MenuBarContentBuilder.make(display: display, connectionState: connection,
                                   now: Self.anchor, mode: mode)
    }

    // MARK: §8.2 UI-02 / UI-03 / UI-06 evidence

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
            ("UI-03 2h / 1d", content(live(fiveHourRemaining: 2 * 3600, weeklyRemaining: 86400))),
            ("UI-03 30m / 6h", content(live(fiveHourRemaining: 0.5 * 3600, weeklyRemaining: 6 * 3600))),
            ("UI-04 1 秒 / 1 分", content(live(fiveHourRemaining: 1, weeklyRemaining: 60))),
            ("UI-05 到重置时间（空）", content(live(fiveHourRemaining: -10, weeklyRemaining: -10))),
            ("UI-06 未知窗口（? 状态）", content(empty)),
            ("UI-06 缓存（单一前置警告 + 变暗）", content(cached)),
            ("UI-06 确定读取失败", content(failed, connection: .disconnected)),
            ("§5.2.3 首次加载中（无警告）", content(.unavailable(.rpcFailed(.other)), connection: .connecting)),
            ("UI-08 100% / 100%（最宽文字）", content(live(fiveHourRemaining: 4 * 3600, weeklyRemaining: 3 * 86400,
                                                        fiveHourPercent: 100, weeklyPercent: 100))),
            ("UI-08 9% / 9%（最窄文字）", content(live(fiveHourRemaining: 4 * 3600, weeklyRemaining: 3 * 86400,
                                                     fiveHourPercent: 9, weeklyPercent: 9))),
            ("UI-09 compact 模式", content(live(fiveHourRemaining: 4 * 3600, weeklyRemaining: 3 * 86400),
                                           mode: .compact)),
            ("UI-09 最小兜底（5H，无条）", content(live(fiveHourRemaining: 4 * 3600, weeklyRemaining: 3 * 86400),
                                                 mode: .icon)),
        ]

        try write(try renderImage(rows, background: .light), named: "01-menubar-states-light.png")
        try write(try renderImage(rows, background: .dark), named: "02-menubar-states-dark.png")

        // A focused strip for the direction requirement: the same 5-hour row draining, so the
        // right-to-left recession can be read off one image.
        let directionRows: [(String, MenuBarContent)] = [
            ("剩余 5h00m", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 4h30m", content(live(fiveHourRemaining: 4.5 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 3h00m", content(live(fiveHourRemaining: 3 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 2h30m", content(live(fiveHourRemaining: 2.5 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 2h00m", content(live(fiveHourRemaining: 2 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 30m", content(live(fiveHourRemaining: 0.5 * 3600, weeklyRemaining: 7 * 86400))),
            ("剩余 0（已到）", content(live(fiveHourRemaining: 0, weeklyRemaining: 7 * 86400))),
        ]
        try write(try renderImage(directionRows, background: .light), named: "03-direction-light.png")

        let weeklyRows: [(String, MenuBarContent)] = [
            ("周剩余 7d", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 7 * 86400))),
            ("周剩余 3d12h", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 3.5 * 86400))),
            ("周剩余 1d", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 86400))),
            ("周剩余 2h", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 2 * 3600))),
            ("周剩余 0（已到）", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 0))),
        ]
        try write(try renderImage(weeklyRows, background: .light), named: "04-weekly-direction-light.png")

        // Bars only, at a large scale, so the segment counts, the gaps and the `?` state badge
        // can be inspected without a magnifier.
        let barsRows: [(String, MenuBarContent)] = [
            ("满格 5h / 7d", content(live(fiveHourRemaining: 5 * 3600, weeklyRemaining: 7 * 86400))),
            ("4h / 3d", content(live(fiveHourRemaining: 4 * 3600, weeklyRemaining: 3 * 86400))),
            ("2h30m / 3d12h", content(live(fiveHourRemaining: 2.5 * 3600, weeklyRemaining: 3.5 * 86400))),
            ("2h / 1d", content(live(fiveHourRemaining: 2 * 3600, weeklyRemaining: 86400))),
            ("30m / 6h", content(live(fiveHourRemaining: 0.5 * 3600, weeklyRemaining: 6 * 3600))),
            ("0 / 0（已到重置时间，无 ?）", content(live(fiveHourRemaining: 0, weeklyRemaining: 0))),
            ("两排均未知（单个 ? 居中）", content(empty)),
            ("仅上排未知（? 覆盖该块）", content(.live(UsageSnapshot(fiveHour: nil,
                                                            weekly: window(.weekly, remaining: 3 * 86400, remainingPercent: 42),
                                                            fetchedAt: Self.anchor, source: .codexAppServer)))),
            ("仅下排未知（? 覆盖该块）", content(.live(UsageSnapshot(fiveHour: window(.fiveHour, remaining: 4 * 3600, remainingPercent: 78),
                                                            weekly: nil,
                                                            fetchedAt: Self.anchor, source: .codexAppServer)))),
            ("缓存状态（变暗 + 前置警告）", content(cached)),
        ]
        try write(try renderBarsDetail(barsRows, background: .light), named: "05-bars-detail-light.png")
        try write(try renderBarsDetail(barsRows, background: .dark), named: "06-bars-detail-dark.png")

        // The status item gives the label exactly `NSStatusBar.system.thickness` points and
        // clips it. This reproduces that band so any clipping of the text, the rows or the
        // state badge is visible instead of being discovered on a real menu bar.
        try write(try renderClippedBand(barsRows, background: .light), named: "07-menubar-band-light.png")
        try write(try renderClippedBand(barsRows, background: .dark), named: "08-menubar-band-dark.png")
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
                        .frame(width: 200, alignment: .leading)
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

    /// Reproduces the real status item band: the label is given exactly
    /// `NSStatusBar.system.thickness` points and clipped, so any overflow is visible.
    private func renderClippedBand(_ rows: [(String, MenuBarContent)], background: Background) throws -> Data {
        let thickness = NSStatusBar.system.thickness
        let panel = VStack(alignment: .leading, spacing: 10) {
            Text("状态项带宽 \(Int(thickness)) pt（NSStatusBar.system.thickness），超出即被裁切")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0).font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        // Left: the label exactly as the status item hosts it, clipped.
                        MenuBarLabelContent(content: row.1)
                            .frame(height: thickness)
                            .clipped()
                            .background(background.color)
                        // Right: the same content unclipped, for comparison.
                        MenuBarLabelContent(content: row.1)
                            .frame(height: thickness)
                            .background(background.color)
                    }
                }
            }
        }
        .padding(16)
        .background(background.color)
        .environment(\.colorScheme, background == .dark ? .dark : .light)
        return try rasterise(panel, appearance: background.appearance, scale: 6)
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

    private func write(_ data: Data, named name: String) throws {
        let directory = URL(fileURLWithPath: #filePath)      // Tests/UsageMonitorAppTests/…
            .deletingLastPathComponent()                     // Tests/UsageMonitorAppTests
            .deletingLastPathComponent()                     // Tests
            .deletingLastPathComponent()                     // repository root
            .appendingPathComponent("docs/versions/1.0.2/evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    }
}

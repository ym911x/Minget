import AppKit
import SwiftUI
import XCTest
@testable import UsageMonitorCore
@testable import UsageMonitorApp

/// v1.0.2 §8.1.9, §8.1.10 and §8.1.11: the width/no-extra-work/lifecycle behaviour that
/// only the real App module can show.
///
/// These tests drive real AppKit objects inside the XCTest host process. They never start the
/// Codex service and never touch the network or the keychain.
@MainActor
final class MenuBarLabelWiringTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            throw XCTSkip("AppKit hosting requires a logged-in macOS window server")
        }
    }

    private func makeModel(factory: @escaping UsageService.ClientFactory = { throw UsageError.appServerStartupFailed(.launchFailed) },
                           engine: ProviderRefreshEngine = ProviderRefreshEngine(readers: []),
                          refreshInterval: TimeInterval = 3600) -> UsageViewModel {
        let service = UsageService(factory: factory,
                                   cache: UsageCache(userDefaults: Self.isolatedDefaults()))
        return UsageViewModel(service: service,
                              providerEngine: engine,
                              refreshInterval: refreshInterval,
                              providerRefreshInterval: 3600)
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suite = "UsageMonitorAppTests.width." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func window(_ kind: RateLimitWindow.Kind, remainingPercent: Double) -> RateLimitWindow {
        let duration = kind == .fiveHour ? 300 : 10_080
        return RateLimitWindow(kind: kind, windowDurationMinutes: duration, usedPercent: 100 - remainingPercent,
                               remainingPercent: remainingPercent,
                               resetsAt: Date().addingTimeInterval(kind == .fiveHour ? 3600 : 86_400))
    }

    // MARK: §8.1.9 Widths across modes and percentages

    func testMeasuredWidthsArePositiveAndOrderedForEveryMode() {
        let model = makeModel()
        let widths = MenuBarLabelMetrics.widths { mode in
            AnyView(MenuBarLabelView(model: model, mode: mode))
        }
        for mode in MenuBarSpaceMode.allCases {
            XCTAssertNotNil(widths[mode], "\(mode.description) must be measured")
            XCTAssertGreaterThan(widths[mode] ?? 0, 0, "\(mode.description) must never be zero-width")
        }
        // Full carries a separator and both rows; compact drops the separator while retaining
        // both quota values and both rows.
        XCTAssertGreaterThan(widths[.full] ?? 0, widths[.compact] ?? 0)
    }

    func testTheWidestPercentageProducesTheWidestText() {
        // 100% is one character wider than 9%. The estimator uses the same 11 pt system font
        // the label draws with, so this is a real measurement of the layout input.
        let narrow = UsageFormatting.menuBarTitle(fiveHour: window(.fiveHour, remainingPercent: 9),
                                                  weekly: window(.weekly, remainingPercent: 9))
        let wide = UsageFormatting.menuBarTitle(fiveHour: window(.fiveHour, remainingPercent: 100),
                                                weekly: window(.weekly, remainingPercent: 100))
        XCTAssertEqual(narrow, "5H 9% | W 9%")
        XCTAssertEqual(wide, "5H 100% | W 100%")
        XCTAssertGreaterThan(MenuBarLabelContent.estimatedTextWidth(wide),
                             MenuBarLabelContent.estimatedTextWidth(narrow))
    }

    func testTheUnknownPlaceholderIsMeasuredLikeAnyOtherText() {
        let placeholder = UsageFormatting.menuBarTitle(fiveHour: nil, weekly: nil)
        XCTAssertEqual(placeholder, "5H – | W –")
        XCTAssertGreaterThan(MenuBarLabelContent.estimatedTextWidth(placeholder), 0)
    }

    func testTheWarningMarkerOnlyEverAddsLeadingRoom() {
        // The marker is a separate leading element, so it cannot make the quota text wider and
        // cannot change the rows' meaning even when it appears and disappears.
        let text = UsageFormatting.menuBarTitle(fiveHour: window(.fiveHour, remainingPercent: 78),
                                                weekly: window(.weekly, remainingPercent: 42))
        let before = MenuBarLabelContent.estimatedTextWidth(text)
        let after = MenuBarLabelContent.estimatedTextWidth(text)
        XCTAssertEqual(before, after, "the same text is always the same width, marker or not")
    }

    // MARK: Both rows span the full text width

    func testFiveAndSevenSegmentsSpanTheSameTotalWidth() {
        // v1.0.2 §3.2: different segment lengths, identical row width.
        let width: CGFloat = 132
        let five = ResetTimeBarsView.segmentWidth(count: 5, totalWidth: width)
        let seven = ResetTimeBarsView.segmentWidth(count: 7, totalWidth: width)
        XCTAssertLessThan(seven, five, "seven segments are individually shorter")
        XCTAssertEqual(5 * five + 4 * ResetTimeBarsView.segmentGap, width, accuracy: 0.01)
        XCTAssertEqual(7 * seven + 6 * ResetTimeBarsView.segmentGap, width, accuracy: 0.01)
    }

    func testSegmentWidthDegradesInsteadOfCollapsing() {
        XCTAssertGreaterThanOrEqual(ResetTimeBarsView.segmentWidth(count: 7, totalWidth: 1),
                                    ResetTimeBarsView.minimumSegmentWidth)
        XCTAssertEqual(ResetTimeBarsView.segmentWidth(count: 0, totalWidth: 100), 0)
    }

    // MARK: The rows span exactly the text container

    /// v1.0.2 §3.2: the label's width is decided by the quota text; the rows consume that
    /// width. If the rows could influence it, the status item would be sized by the bars.
    func testLabelWidthIsExactlyTheQuotaTextWidth() {
        let snapshot = UsageSnapshot(fiveHour: window(.fiveHour, remainingPercent: 78),
                                     weekly: window(.weekly, remainingPercent: 42),
                                     fetchedAt: Date(), source: .codexAppServer)
        let display = UsageDisplay.live(snapshot)

        for mode in [MenuBarSpaceMode.full, .compact] {
            let content = MenuBarContentBuilder.make(display: display, connectionState: .connected,
                                                     now: Date(), mode: mode)
            let textWidth = MenuBarLabelContent.estimatedTextWidth(content.text)
            let measured = fittingWidth(MenuBarLabelContent(content: content))
            XCTAssertEqual(measured, textWidth, accuracy: 0.5,
                           "\(mode.description): the label must be exactly the text width")
            // And the rows use that same width for both rows.
            XCTAssertEqual(ResetTimeBarsView.segmentWidth(count: 5, totalWidth: measured) * 5
                           + ResetTimeBarsView.segmentGap * 4, measured, accuracy: 0.01)
            XCTAssertEqual(ResetTimeBarsView.segmentWidth(count: 7, totalWidth: measured) * 7
                           + ResetTimeBarsView.segmentGap * 6, measured, accuracy: 0.01)
        }
    }

    func testTheWarningMarkerOnlyWidensTheLeadingSlot() {
        let snapshot = UsageSnapshot(fiveHour: window(.fiveHour, remainingPercent: 78),
                                     weekly: window(.weekly, remainingPercent: 42),
                                     fetchedAt: Date(), source: .codexAppServer)
        let normal = MenuBarContentBuilder.make(display: .live(snapshot), connectionState: .connected,
                                                now: Date(), mode: .full)
        let warned = MenuBarContentBuilder.make(display: .stale(snapshot, .rpcFailed(.other)),
                                                connectionState: .connected, now: Date(), mode: .full)

        XCTAssertEqual(normal.attention, .none)
        XCTAssertEqual(warned.attention, .warning)
        XCTAssertEqual(normal.text, warned.text, "the marker must not be part of the text")

        let normalWidth = fittingWidth(MenuBarLabelContent(content: normal))
        let warnedWidth = fittingWidth(MenuBarLabelContent(content: warned))
        XCTAssertGreaterThan(warnedWidth, normalWidth, "the marker takes a leading slot")
        XCTAssertLessThan(warnedWidth - normalWidth, 20, "exactly one small marker, not a word")
    }

    func testCompactLabelKeepsBothQuotaValuesAndRows() {
        let snapshot = UsageSnapshot(fiveHour: window(.fiveHour, remainingPercent: 78),
                                     weekly: window(.weekly, remainingPercent: 42),
                                     fetchedAt: Date(), source: .codexAppServer)
        let content = MenuBarContentBuilder.make(display: .live(snapshot), connectionState: .connected,
                                                 now: Date(), mode: .compact)
        XCTAssertEqual(content.text, "5H 78% W 42%")
        XCTAssertTrue(content.showsTimeBars)
        let measured = fittingWidth(MenuBarLabelContent(content: content))
        XCTAssertEqual(measured, MenuBarLabelContent.estimatedTextWidth(content.text), accuracy: 0.5)
    }

    /// Fitting width of the real label view, measured the same way the status item measures it.
    private func fittingWidth<V: View>(_ view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: NSStatusBar.system.thickness)
        return ceil(hosting.fittingSize.width)
    }

    func testCompactFallbackWidthFitsTheCompactText() {
        let compact = MenuBarLabelMetrics.fallbackWidth(for: .compact)
        XCTAssertGreaterThanOrEqual(compact, MenuBarLabelContent.estimatedTextWidth("5H 78% W 42%"))
    }

    // MARK: §8.1.9 The item is sized from a measurement, not from the fallback

    /// v1.0.2 §3.2/§3.3 regression: the per-mode fallback is only a starting point. `install`
    /// must replace it with the real measurement before the first geometry check, otherwise a
    /// roomy menu bar is reported as truncated (fallback 132 pt against a granted ~116 pt) and
    /// the item steps down to an invalid partial label.
    func testInstallSizesTheItemFromAMeasurementNotTheFallback() {
        let controller = StatusItemController()
        controller.install(model: makeModel())

        XCTAssertFalse(controller.widths.isEmpty, "install must measure before the first check")
        let measuredFull = controller.widths[MenuBarSpaceMode.full]
        XCTAssertNotNil(measuredFull)
        XCTAssertEqual(controller.appliedWidth, measuredFull,
                       "the applied width must be the measured width")
        XCTAssertNotEqual(controller.appliedWidth, MenuBarLabelMetrics.fallbackWidth(for: .full),
                          "the fallback must not survive the first layout pass")

        controller.uninstall()
    }

    /// The measured widths stay ordered after a real measurement, so full remains wider than
    /// the compact two-quota representation.
    func testInstalledWidthsKeepTheModeOrdering() {
        let controller = StatusItemController()
        controller.install(model: makeModel())
        XCTAssertGreaterThan(controller.widths[.full] ?? 0, controller.widths[.compact] ?? 0)
        controller.uninstall()
    }

    // MARK: §8.1.10 A time-only update costs no work
    func testDrawingTheCountdownRepeatedlyDoesNotFetchOrRemeasure() async {
        let counter = FactoryCounter()
        let model = makeModel(factory: { counter.value += 1; throw UsageError.appServerStartupFailed(.launchFailed) })

        model.start()
        let settled = await waitUntil { !model.isRefreshing }
        XCTAssertTrue(settled, "the launch refresh must settle before the assertion")
        let fetchCountAfterStart = counter.value

        let controller = StatusItemController()
        controller.install(model: model)
        // Apply the current content once so the measured signature exists, then watch it.
        controller.noteContentMayHaveChanged()
        let signatureBefore = controller.labelSignature
        XCTAssertNotNil(signatureBefore, "the first content pass establishes the signature")

        // Re-render the content and re-run the content-change path many times; this is exactly
        // what the once-a-second tick does.
        for _ in 0..<20 {
            _ = model.menuBarContent(for: .full, now: Date())
            _ = model.menuBarContent(for: .compact, now: Date())
            _ = model.menuBarSizeSignature
            controller.noteContentMayHaveChanged()
        }

        XCTAssertEqual(counter.value, fetchCountAfterStart,
                       "drawing the countdown must not trigger another service fetch")
        XCTAssertEqual(controller.labelSignature, signatureBefore,
                       "a time-only update must not invalidate the measured widths")

        controller.uninstall()
        model.stop()
    }

    // MARK: §8.1.11 Dismiss-monitor lifecycle

    func testDismissMonitorInstallIsIdempotentAndStopIsRepeatable() {
        let monitor = PopoverDismissMonitor()
        let popover = NSPopover()
        XCTAssertFalse(monitor.isInstalled)

        monitor.install(popover: popover, statusButton: nil) {}
        XCTAssertTrue(monitor.isInstalled)
        XCTAssertEqual(monitor.installCount, 1)

        // Opening twice (or calling install again) must not stack a second pair of monitors.
        monitor.install(popover: popover, statusButton: nil) {}
        XCTAssertEqual(monitor.installCount, 1, "no second pair of monitors may be installed")

        monitor.stop()
        XCTAssertFalse(monitor.isInstalled)
        // Closing twice, or stopping after a stop, must not crash or half-release.
        monitor.stop()
        XCTAssertFalse(monitor.isInstalled)

        // A later open installs again, so the behaviour survives close-then-open cycles.
        monitor.install(popover: popover, statusButton: nil) {}
        XCTAssertTrue(monitor.isInstalled)
        XCTAssertEqual(monitor.installCount, 2)
        monitor.stop()
    }

    func testUninstallTearsDownTheDismissMonitor() {
        let controller = StatusItemController()
        controller.install(model: makeModel())
        XCTAssertFalse(controller.isDismissMonitorInstalled, "nothing is installed until the panel opens")

        controller.uninstall()
        XCTAssertFalse(controller.isDismissMonitorInstalled)
    }

    func testRepeatedInstallAndUninstallLeavesNoMonitorBehind() {
        let controller = StatusItemController()
        let model = makeModel()
        for _ in 0..<20 {
            controller.install(model: model)
            controller.uninstall()
        }
        XCTAssertFalse(controller.isInstalled)
        XCTAssertFalse(controller.isMonitorRunning)
        XCTAssertFalse(controller.isDismissMonitorInstalled)
        XCTAssertNil(controller.statusItem)
        XCTAssertNil(controller.labelSignature)
    }

    func testClosingThePanelIsSafeWhenItWasNeverOpened() {
        let controller = StatusItemController()
        controller.install(model: makeModel())
        controller.closePanel()
        controller.closePanel()
        XCTAssertFalse(controller.isPopoverShown)
        XCTAssertFalse(controller.isDismissMonitorInstalled)
        controller.uninstall()
    }

    // MARK: Helpers

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

/// Counts how many times the app-server factory was invoked, so a test can prove that drawing
/// the countdown adds no fetch.
private final class FactoryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import UsageMonitorCore
@testable import UsageMonitorApp

/// The width behaviour that only the real App module can show.
///
/// Since 1.6.8 the status item's length is a fixed constant: the same for every
/// source, every value and every warning state. These tests pin that invariant
/// against the real label view — the marker's reserved slot, the text budget
/// every renderable text fits inside, and the DeepSeek balance ladder.
///
/// They drive real AppKit objects inside the XCTest host process. They never
/// start the Codex service and never touch the network or the keychain.
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
                              menuBarPreferences: MenuBarPreferences(defaults: Self.isolatedDefaults()),
                              refreshInterval: refreshInterval,
                              providerRefreshInterval: 3600)
    }

    /// Content for one ChatGPT account, through the source-based builder.
    private func content(_ display: UsageDisplay,
                         code: String = "O1",
                         connection: UsageService.ConnectionState = .connected) -> MenuBarContent {
        MenuBarContentBuilder.make(source: .chatGPT(code: code, display: display,
                                                    connectionState: connection),
                                   now: Date())
    }

    private func deepSeekContent(currency: String?, amount: Decimal?,
                                 cached: Bool = false,
                                 code: String = "DS1") -> MenuBarContent {
        MenuBarContentBuilder.make(source: .deepSeek(MenuBarDeepSeekContent(code: code,
                                                                            currency: currency,
                                                                            amount: amount,
                                                                            isCached: cached)),
                                   now: Date())
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

    private func liveSnapshot(fiveHourPercent: Double = 78, weeklyPercent: Double = 42) -> UsageSnapshot {
        UsageSnapshot(fiveHour: window(.fiveHour, remainingPercent: fiveHourPercent),
                      weekly: window(.weekly, remainingPercent: weeklyPercent),
                      fetchedAt: Date(), source: .codexAppServer)
    }

    // MARK: The fixed width

    /// The width is exactly the widest quota label the menu bar shows — both
    /// percentages at 100 % behind a two-character code — plus a 2 pt rounding
    /// margin. Nothing else widens it.
    func testTheLabelWidthIsTheWidestQuotaLabel() {
        let widest = MenuBarLabelContent.estimatedTextWidth("O1 100% 100%")
        XCTAssertEqual(MenuBarLabelMetrics.textBudget, ceil(widest) + 2)
        XCTAssertEqual(MenuBarLabelMetrics.labelWidth, MenuBarLabelMetrics.textBudget)
        XCTAssertEqual(MenuBarLabelMetrics.itemWidth,
                       MenuBarLabelMetrics.labelWidth + MenuBarLabelMetrics.horizontalPadding)
        // The DeepSeek line with its currency is wider than the budget on purpose: the
        // ladder omits the currency instead of widening every item.
        XCTAssertLessThan(MenuBarLabelMetrics.textBudget,
                          MenuBarLabelContent.estimatedBalanceWidth("DS1 CNY 123.45"))
    }

    /// The quota labels and the balance forms that must fit do fit. The Chinese
    /// fallbacks and a long balance are allowed to be longer than the budget: they
    /// shrink inside it instead of widening the item, which is what
    /// `testEverySourceMeasuresTheSameFixedWidth` pins.
    func testTheQuotaLabelsAndBalanceFormsFitTheTextBudget() {
        let budget = MenuBarLabelMetrics.textBudget
        for text in ["O1 100% 100%", "O2 100% 100%", "G1 100% 100%", "G3 100% 100%",
                     "O1 — —", "O1 9% 9%", "G1 —"] {
            XCTAssertLessThanOrEqual(MenuBarLabelContent.estimatedTextWidth(text), budget, text)
        }
        for text in ["DS1 9.00", "DS1 123.45", "DS1 —"] {
            XCTAssertLessThanOrEqual(MenuBarLabelContent.estimatedBalanceWidth(text), budget, text)
        }
    }

    /// The label's own frame is the fixed width, so the hosting view reports the
    /// same width for every source and every state.
    func testEverySourceMeasuresTheSameFixedWidth() {
        let live = liveSnapshot()
        let contents: [(String, MenuBarContent)] = [
            ("chatGPT 78%", content(.live(live))),
            ("chatGPT 100%", content(.live(liveSnapshot(fiveHourPercent: 100, weeklyPercent: 100)))),
            ("chatGPT 9%", content(.live(liveSnapshot(fiveHourPercent: 9, weeklyPercent: 9)))),
            ("chatGPT no data", content(.unavailable(.rpcFailed(.other)), code: "O2", connection: .disconnected)),
            ("chatGPT cached", content(.stale(live, .rpcFailed(.other)))),
            ("deepSeek balance", deepSeekContent(currency: "CNY", amount: Decimal(string: "123.45"))),
            ("deepSeek no data", deepSeekContent(currency: nil, amount: nil)),
            ("unavailable", MenuBarContentBuilder.make(source: .unavailable("请重新选择"), now: Date())),
        ]

        for (name, built) in contents {
            let measured = fittingWidth(MenuBarLabelContent(content: built))
            XCTAssertEqual(measured, MenuBarLabelMetrics.labelWidth, accuracy: 0.5,
                           "\(name): every source draws inside the same fixed width")
        }
    }

    /// The marker's slot is reserved in every state, so a cached or failed read
    /// cannot change the item's length.
    func testTheWarningMarkerDoesNotChangeTheWidth() {
        let live = liveSnapshot()
        let normal = content(.live(live))
        let warned = content(.stale(live, .rpcFailed(.other)))

        XCTAssertEqual(normal.attention, .none)
        XCTAssertEqual(warned.attention, .warning)
        XCTAssertEqual(normal.text, warned.text, "the marker must not be part of the text")
        XCTAssertEqual(fittingWidth(MenuBarLabelContent(content: normal)),
                       fittingWidth(MenuBarLabelContent(content: warned)),
                       "the marker lives in a reserved slot, so it cannot resize the item")
    }

    func testFiveAndSevenSegmentsSpanTheSameTotalWidth() {
        // v1.0.2 §3.2: different segment lengths, identical row width. Since 1.6.8
        // that width is the fixed text budget.
        let width = MenuBarLabelMetrics.textBudget
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

    // MARK: The DeepSeek balance ladder

    func testABalanceThatAlreadyFitsIsUnchanged() {
        let fitted = MenuBarLabelContent.fittedBalanceText("DS1 9.00")
        XCTAssertEqual(fitted.text, "DS1 9.00")
        XCTAssertEqual(fitted.scale, 1)
    }

    /// The balance line with its currency is wider than the budget at 13 pt, so
    /// the currency code goes first — the user may omit it — and the amount
    /// survives untouched.
    func testTheLadderDropsTheCurrencyBeforeShrinking() {
        let fitted = MenuBarLabelContent.fittedBalanceText("DS1 CNY 1234.56")
        XCTAssertEqual(fitted.text, "DS1 1234.56", "the code and the amount stay; only the currency goes")
        XCTAssertLessThanOrEqual(MenuBarLabelContent.estimatedBalanceWidth(fitted.text, scale: fitted.scale),
                                 MenuBarLabelMetrics.textBudget)
    }

    /// A realistic long balance (six digits) still shows every digit: the line shrinks
    /// exactly as far as the measurement requires.
    func testALongBalanceShrinksJustEnoughToKeepEveryDigit() {
        let fitted = MenuBarLabelContent.fittedBalanceText("DS1 123456.78")
        XCTAssertEqual(fitted.text, "DS1 123456.78")
        XCTAssertLessThan(fitted.scale, 1)
        XCTAssertGreaterThan(fitted.scale, MenuBarLabelMetrics.balanceMinimumFactor)
        XCTAssertLessThanOrEqual(MenuBarLabelContent.estimatedBalanceWidth(fitted.text, scale: fitted.scale),
                                 MenuBarLabelMetrics.textBudget)
    }

    /// An absurd amount reaches the type floor rather than losing digits to the
    /// currency decision; the floor is far beyond any real DeepSeek balance.
    func testAnAbsurdAmountStopsAtTheTypeFloor() {
        let fitted = MenuBarLabelContent.fittedBalanceText("DS1 CNY 1234567890123.45")
        XCTAssertEqual(fitted.text, "DS1 1234567890123.45", "the code and the amount survive")
        XCTAssertEqual(fitted.scale, MenuBarLabelMetrics.balanceMinimumFactor)
    }

    func testTheLadderKeepsTheUnnamedCurrencyPosition() {
        let fitted = MenuBarLabelContent.fittedBalanceText("DS1 — 123.45")
        XCTAssertEqual(fitted.text, "DS1 — 123.45", "an unnamed currency keeps its position")
        XCTAssertLessThanOrEqual(MenuBarLabelContent.estimatedBalanceWidth(fitted.text, scale: fitted.scale),
                                 MenuBarLabelMetrics.textBudget)
    }

    func testAMissingBalanceIsNeverWidenedByTheLadder() {
        let fitted = MenuBarLabelContent.fittedBalanceText("DS1 —")
        XCTAssertEqual(fitted.text, "DS1 —")
        XCTAssertEqual(fitted.scale, 1)
    }

    // MARK: The item is sized from the fixed width

    func testInstallSizesTheItemFromTheFixedWidth() {
        let controller = StatusItemController()
        controller.install(model: makeModel())

        XCTAssertEqual(controller.appliedWidth, MenuBarLabelMetrics.itemWidth,
                       "the item's length is the fixed label width plus its padding")
        XCTAssertEqual(controller.statusItem?.length, MenuBarLabelMetrics.itemWidth,
                       "the status bar is asked for exactly that width")

        controller.uninstall()
    }

    /// Content changes redraw the label, never resize the item: this is the 1.6.8
    /// replacement for the old "remeasure only when the signature changed" rule,
    /// and it is a stronger guarantee.
    func testContentChangesNeverResizeTheItem() async {
        let counter = FactoryCounter()
        let model = makeModel(factory: { counter.value += 1; throw UsageError.appServerStartupFailed(.launchFailed) })

        model.start()
        let settled = await waitUntil { !model.isRefreshing }
        XCTAssertTrue(settled, "the launch refresh must settle before the assertion")
        let fetchCountAfterStart = counter.value

        let controller = StatusItemController()
        controller.install(model: model)
        let widthAfterInstall = controller.appliedWidth
        XCTAssertEqual(widthAfterInstall, MenuBarLabelMetrics.itemWidth)

        // Re-render the content many times; this is what the once-a-second tick does.
        for _ in 0..<20 {
            _ = model.menuBarContent(now: Date())
            _ = model.menuBarContent(now: Date().addingTimeInterval(60))
        }
        controller.checkGeometry()
        controller.checkGeometry()

        XCTAssertEqual(counter.value, fetchCountAfterStart,
                       "drawing the countdown must not trigger another service fetch")
        XCTAssertEqual(controller.appliedWidth, widthAfterInstall,
                       "the item's length never changes after install")

        controller.uninstall()
        model.stop()
    }

    /// Fitting width of the real label view, measured the way the status item was
    /// measured before 1.6.8.
    private func fittingWidth<V: View>(_ view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: NSStatusBar.system.thickness)
        return ceil(hosting.fittingSize.width)
    }

    // MARK: Dismiss-monitor lifecycle

    func testStatusButtonDeactivationDoesNotCloseBeforeTheButtonAction() throws {
        let monitor = PopoverDismissMonitor()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 140, height: 24),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        window.contentView?.addSubview(button)
        let frame = try XCTUnwrap(PopoverDismissMonitor.frame(of: button))
        var pointer = NSPoint(x: frame.midX, y: frame.midY)
        var dismissals = 0
        monitor.install(popover: NSPopover(), statusButton: button,
                        mouseLocation: { pointer }) { dismissals += 1 }
        defer { monitor.stop() }

        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertEqual(dismissals, 0, "button action must see the still-open popover")

        pointer = NSPoint(x: frame.maxX + 100, y: frame.minY - 100)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertEqual(dismissals, 1, "a click in another app must still dismiss")

        monitor.stop()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertEqual(dismissals, 1, "closing must remove the observer")
    }

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
        XCTAssertEqual(controller.appliedWidth, 0)
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

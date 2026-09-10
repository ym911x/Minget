import AppKit
import Combine
import SwiftUI
import UsageMonitorCore

/// Widths the three menu bar modes need, measured from the real SwiftUI content.
///
/// Measuring the actual hosting view is what makes the truncation check in
/// `MenuBarSpaceFacts` meaningful: the state machine compares the width the app asked for
/// with the width macOS actually gave the item.
enum MenuBarLabelMetrics {

    static let horizontalPadding: CGFloat = 12

    /// Measures the natural width of each mode. Re-measured when the underlying numbers
    /// change, because "78%" and "100%" differ by a character.
    static func widths(labelProvider: (MenuBarSpaceMode) -> AnyView) -> [MenuBarSpaceMode: CGFloat] {
        var result: [MenuBarSpaceMode: CGFloat] = [:]
        for mode in MenuBarSpaceMode.allCases {
            let hosting = NSHostingView(rootView: labelProvider(mode))
            hosting.frame = NSRect(origin: .zero, size: NSSize(width: 400, height: NSStatusBar.system.thickness))
            result[mode] = max(18, ceil(hosting.fittingSize.width) + horizontalPadding)
        }
        return result
    }
}

/// Owns the `NSStatusItem`, the detail popover and the detail window.
///
/// v1.1 replaces the previous `MenuBarExtra` with a directly managed `NSStatusItem` so the
/// item can be measured and resized. Behaviour (v1.1 requirement 1):
/// - the item is registered with `NSStatusBar.system.statusItem(withLength:)`, so it is a
///   real system menu bar item rather than an unregistered `NSStatusItem` instance,
/// - a stable `autosaveName` keeps the item where the user put it across relaunches,
/// - the label steps down full → compact → icon as the available menu bar space shrinks,
///   with hysteresis in `MenuBarSpaceStateMachine` so the mode cannot flap,
/// - the popover reuses the same SwiftUI detail view as before; no extra floating window is
///   created for it,
/// - when the item is not visible at launch (occluded by the notch or hidden by macOS), the
///   detail window opens automatically so the user still has a way to see the data,
/// - `uninstall` reverses everything at exit: the geometry monitor stops, the popover and
///   the detail window close, and the item is handed back to the system status bar.
///
/// Only public AppKit API is used, and no system-wide menu bar setting is read or written.
@MainActor
final class StatusItemController: NSObject {

    /// Stable autosave name: NSStatusItem persists its own frame under this key, which is
    /// what keeps the item's position stable across relaunches.
    static let autosaveName = "UsageMonitor.StatusItem.v1"
    /// How long to wait before the first visibility check, so the item has a window.
    static let initialLayoutDelay: TimeInterval = 1.0
    /// Pure-local geometry re-check cadence.
    static let geometryCheckInterval: TimeInterval = 10
    /// Window during which our own resize is not treated as an external space event.
    static let selfResizeSettleInterval: TimeInterval = 0.6

    /// The registered system status item. Created through `NSStatusBar.system` in
    /// `install` and handed back through `NSStatusBar.system.removeStatusItem` in
    /// `uninstall`; never constructed directly.
    private(set) var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var detailWindowController: DetailWindowController?

    private var model: UsageViewModel?
    private var stateMachine = MenuBarSpaceStateMachine()
    private var widths: [MenuBarSpaceMode: CGFloat] = [:]
    private var labelSignature: String?
    private var monitor: MenuBarSpaceMonitor?
    private var cancellables: Set<AnyCancellable> = []
    private var hasAutoOpenedDetailWindow = false
    private var appliedWidth: CGFloat = 0
    /// Until this moment, frame changes to our own window are not treated as space events.
    var selfResizeSettlesAt = Date.distantPast

    var currentMode: MenuBarSpaceMode { stateMachine.mode }

    /// Introspection for the wiring tests: the item is registered and has content.
    var isInstalled: Bool { statusItem != nil }
    /// Introspection for the wiring tests: the geometry monitor is running.
    var isMonitorRunning: Bool { monitor != nil }
    /// Introspection for the wiring tests: the popover is on screen.
    var isPopoverShown: Bool { popover.isShown }

    var isStatusItemRendered: Bool {
        guard let statusItem else { return false }
        return Self.facts(for: statusItem, requestedWidth: appliedWidth).isRendered
    }

    // MARK: - Install

    /// Registers the status item with the system menu bar and starts the geometry monitor.
    func install(model: UsageViewModel) {
        guard statusItem == nil else { return }   // idempotent: never two items
        self.model = model

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.autosaveName = Self.autosaveName
        guard let button = item.button else { return }

        button.setAccessibilityLabel("Codex 用量菜单栏")

        popover.behavior = .transient
        popover.animates = false

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        apply(mode: stateMachine.mode)

        let monitor = MenuBarSpaceMonitor(controller: self, interval: Self.geometryCheckInterval)
        self.monitor = monitor
        monitor.start()

        // Re-measure as soon as the displayed numbers change instead of waiting for the
        // periodic check, so a width change (78% → 100%) never shows a stale-sized item.
        // The hop through the main queue keeps the work off the model's mutation stack.
        model.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.refreshLabel() }
                }
            }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialLayoutDelay) { [weak self] in
            MainActor.assumeIsolated { self?.checkGeometry(spaceEvent: true) }
        }
    }

    /// Reverses `install` completely. Called on application exit: the geometry monitor and
    /// the model observation stop, the popover and the detail window close, and the item is
    /// removed from the system status bar. Idempotent, so forced-exit paths can call it
    /// unconditionally.
    func uninstall() {
        monitor?.stop()
        monitor = nil
        cancellables.removeAll()
        closePanel()
        detailWindowController?.window?.orderOut(nil)
        detailWindowController = nil
        if let item = statusItem {
            item.button?.subviews.forEach { $0.removeFromSuperview() }
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        model = nil
        widths = [:]
        labelSignature = nil
        appliedWidth = 0
    }

    /// Applies the current numbers: refreshes the label content and re-measures the widths.
    func refreshLabel() {
        labelSignature = nil
        monitor?.requestCheck()
    }

    /// Notification-driven entry point from the monitor.
    func checkGeometry(spaceEvent: Bool) {
        guard let model, let item = statusItem else { return }
        if spaceEvent { stateMachine.noteSpaceEvent() }

        let signature = model.menuBarTitle + "#" + model.menuBarStalenessMarker
        let previousWidths = widths
        if signature != labelSignature {
            labelSignature = signature
            widths = MenuBarLabelMetrics.widths { mode in
                AnyView(MenuBarLabelView(model: model, mode: mode))
            }
        }

        let facts = Self.facts(for: item, requestedWidth: appliedWidth)
        Diagnostics.log("menu bar \(facts.diagnosticSummary) mode:\(stateMachine.mode.description)")

        let decision = stateMachine.apply(facts)
        if case .change(let mode, _) = decision {
            apply(mode: mode)
        } else if widths != previousWidths {
            apply(mode: stateMachine.mode)
        }
    }

    // MARK: - Display

    private func apply(mode: MenuBarSpaceMode) {
        guard let statusItem else { return }
        let width = widths[mode] ?? MenuBarLabelMetrics.fallbackWidth(for: mode)
        statusItem.length = width
        appliedWidth = width
        selfResizeSettlesAt = Date().addingTimeInterval(Self.selfResizeSettleInterval)

        guard let button = statusItem.button, let model else { return }
        // The SwiftUI label is the whole content; the button's own title stays empty.
        button.title = ""
        button.subviews.forEach { $0.removeFromSuperview() }
        let padding = MenuBarLabelMetrics.horizontalPadding
        let hosting = MenuBarHostingView(rootView: MenuBarLabelView(model: model, mode: mode))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(x: padding / 2, y: 0,
                               width: max(1, width - padding),
                               height: NSStatusBar.system.thickness)
        button.addSubview(hosting)
    }

    // MARK: - Actions

    /// Internal (not private) so the wiring tests can pin the button to this action.
    @objc func statusItemClicked(_ sender: Any?) {
        togglePanel()
    }

    /// Shows the detail panel. Falls back to the detail window when the status item has no
    /// window to anchor to, which is exactly the case when macOS has hidden the item.
    ///
    /// The app runs as an accessory (no Dock icon), so a freshly shown popover is not the
    /// key window and its text fields cannot take keyboard focus until the app is active.
    /// Activating before `show` is what makes the SecureFields reliably clickable and
    /// typable (Round 7 requirement 4).
    func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button, button.window != nil else {
            showDetailWindow()
            return
        }
        guard let controller = makePanelViewController() else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closePanel() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// Opens the detail in its own regular window. Used at launch when the menu bar item is
    /// occluded, and from the panel's own button.
    func showDetailWindow() {
        guard let model else { return }
        closePanel()
        if detailWindowController == nil {
            detailWindowController = DetailWindowController(model: model)
        }
        detailWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makePanelViewController() -> PanelHostingController? {
        guard let model else { return nil }
        let controller = PanelHostingController(model: model)
        controller.onDetailWindowRequested = { [weak self] in self?.showDetailWindow() }
        return controller
    }

    /// Opens the detail window once, if the item is not visible after launch layout.
    /// This is the v1.1 requirement: a user whose icon is hidden still gets the detail.
    func openDetailWindowIfItemIsHidden() {
        guard !hasAutoOpenedDetailWindow else { return }
        guard !isStatusItemRendered else { return }
        hasAutoOpenedDetailWindow = true
        Diagnostics.log("status item not visible at launch, opening detail window")
        showDetailWindow()
    }

    // MARK: - Geometry

    /// Builds the pure geometry facts from AppKit. This is the only place AppKit values
    /// enter the decision, and it reads only public API.
    static func facts(for statusItem: NSStatusItem, requestedWidth: CGFloat) -> MenuBarSpaceFacts {
        let button = statusItem.button
        let window = button?.window
        let frame = window?.frame

        var screen = window?.screen
        if screen == nil, let frame {
            screen = NSScreen.screens.first { $0.frame.intersects(frame) }
        }
        if screen == nil { screen = NSScreen.main }

        return MenuBarSpaceFacts(itemFrame: frame,
                                 screenFrame: screen?.frame,
                                 safeAreaTop: screen?.safeAreaInsets.top ?? 0,
                                 auxiliaryTopLeftArea: screen?.auxiliaryTopLeftArea ?? .zero,
                                 auxiliaryTopRightArea: screen?.auxiliaryTopRightArea ?? .zero,
                                 requestedWidth: requestedWidth)
    }
}

/// Hosts the menu bar label inside the status item's button. Hit tests pass through to the
/// button itself, so the label never swallows the click that opens the detail panel.
@MainActor
final class MenuBarHostingView: NSHostingView<MenuBarLabelView> {
    override func hitTest(_ point: NSPoint) -> NSView? { return nil }
}

/// Panel host that keeps a strong reference to the view model for the popover's lifetime.
final class PanelHostingController: NSHostingController<UsagePanelView> {
    var onDetailWindowRequested: (() -> Void)?

    init(model: UsageViewModel) {
        let view = UsagePanelView(model: model, onDetailWindow: nil, onQuit: { NSApp.terminate(nil) })
        super.init(rootView: view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Regular, closable window holding the same detail view. Not a floating panel: it uses the
/// normal window level and behaves like any other document window.
final class DetailWindowController: NSWindowController {

    init(model: UsageViewModel) {
        let panel = UsagePanelView(model: model, onDetailWindow: nil, onQuit: { NSApp.terminate(nil) })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "额度详情"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: panel)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Watches everything that can change the menu bar's available space and feeds the state
/// machine: screen changes, wake from sleep, the status item's own frame moving, plus a
/// periodic pure-local geometry check that issues no network or system calls.
///
/// All observation happens on the main queue/runloop, so the class is main-actor and every
/// callback asserts that with `MainActor.assumeIsolated` — the closures themselves are
/// plain `@Sendable` blocks delivered on the main queue.
@MainActor
final class MenuBarSpaceMonitor {

    private weak var controller: StatusItemController?
    private let interval: TimeInterval
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastObservedFrame: NSRect = .zero

    init(controller: StatusItemController, interval: TimeInterval) {
        self.controller = controller
        self.interval = interval
    }

    func start() {
        let center = NotificationCenter.default

        // Screen set changed: a display was connected, removed, or the arrangement moved.
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.report(spaceEvent: true) }
        })

        // The Mac woke: menu bar space is often renegotiated around sleep and wake.
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.report(spaceEvent: true) }
        })

        // The item moved or was resized. AppKit has no single frame-change notification, so
        // the two halves are observed. A resize the app itself requested is not an
        // external event: treating it as one would feed the state machine its own output
        // and could grow/shrink in a loop.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name,
                                                object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.handleFrameChange(note) }
            })
        }

        // Fallback check. Pure local geometry: no network, no private API.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.report(spaceEvent: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    private func handleFrameChange(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        guard window === controller?.statusItem?.button?.window else { return }
        let frame = window.frame
        let previous = lastObservedFrame
        lastObservedFrame = frame

        guard previous != .zero else { return }
        let moved = abs(frame.minX - previous.minX) > 0.5 || abs(frame.width - previous.width) > 0.5
        guard moved else { return }
        let settlesAt = controller?.selfResizeSettlesAt ?? .distantPast
        guard Date() >= settlesAt else { return }
        report(spaceEvent: true)
    }

    /// Public hook so a model update can trigger a check without waiting for the timer.
    func requestCheck() {
        report(spaceEvent: false)
    }

    private func report(spaceEvent: Bool) {
        guard let controller else { return }
        if let frame = controller.statusItem?.button?.window?.frame {
            lastObservedFrame = frame
        }
        controller.checkGeometry(spaceEvent: spaceEvent)
    }
}

extension MenuBarLabelMetrics {
    /// Used before the first measurement completes, so the item is never zero-width.
    static func fallbackWidth(for mode: MenuBarSpaceMode) -> CGFloat {
        switch mode {
        case .full: return 132
        case .compact: return 78
        case .icon: return 28
        }
    }
}

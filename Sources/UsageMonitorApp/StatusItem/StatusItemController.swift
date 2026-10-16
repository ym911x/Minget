import AppKit
import Combine
import SwiftUI
import UsageMonitorCore

/// Owns the `NSStatusItem`, the detail popover and the detail window.
///
/// v1.1 replaces the previous `MenuBarExtra` with a directly managed `NSStatusItem` so the
/// item can be measured and resized. Behaviour (v1.1 requirement 1):
/// - the item is registered with `NSStatusBar.system.statusItem(withLength:)`, so it is a
///   real system menu bar item rather than an unregistered `NSStatusItem` instance,
/// - a stable `autosaveName` keeps the item where the user put it across relaunches,
/// - the label has had one fixed width since 1.6.8, so its length never changes with
///   the values it shows; when macOS cannot render the item at all — hidden, over the
///   sensor housing, off the visible area, or clipped — the detail window opens so the
///   user still sees the data,
/// - the popover reuses the same SwiftUI detail view as before; no extra floating window is
///   created for it,
/// - a click outside the popover closes it and still reaches its original target
///   (v1.0.2 requirement 4), while the regular detail window keeps normal window behaviour,
/// - `uninstall` reverses everything at exit: the geometry monitor stops, the popover and
///   the detail window close, and the item is handed back to the system status bar.
///
/// Only public AppKit API is used, and no system-wide menu bar setting is read or written.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {

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
    /// Closes the popover on an outside click. Installed only while the popover is on screen.
    private let dismissMonitor = PopoverDismissMonitor()
    private var detailWindowController: DetailWindowController?
    private var settingsWindowController: SettingsWindowController?

    private var model: UsageViewModel?
    private var lastGoogleAccountCount = 0
    private var stateMachine = MenuBarSpaceStateMachine()
    private var monitor: MenuBarSpaceMonitor?
    private var cancellables: Set<AnyCancellable> = []
    private var hasAutoOpenedDetailWindow = false
    /// Width currently applied to the status item. `private(set)` for the wiring
    /// tests, which prove the item is sized from the fixed label width.
    private(set) var appliedWidth: CGFloat = 0
    /// Until this moment, frame changes to our own window are not treated as space events.
    var selfResizeSettlesAt = Date.distantPast

    /// Introspection for the wiring tests: the item is registered and has content.
    var isInstalled: Bool { statusItem != nil }
    /// Introspection for the wiring tests: the geometry monitor is running.
    var isMonitorRunning: Bool { monitor != nil }
    /// Introspection for the wiring tests: the popover is on screen.
    var isPopoverShown: Bool { popover.isShown }
    var panelHostIdentity: ObjectIdentifier? { popover.contentViewController.map(ObjectIdentifier.init) }
    var visiblePanelFrame: NSRect? { popover.contentViewController?.view.window?.frame }

    /// The click-toggle contract requires explicit dismissal rather than AppKit auto-close.
    var popoverBehavior: NSPopover.Behavior { popover.behavior }
    /// Introspection for the wiring tests: the outside-click monitor is installed.
    var isDismissMonitorInstalled: Bool { dismissMonitor.isInstalled }

    var isStatusItemRendered: Bool {
        guard let statusItem else { return false }
        return Self.facts(for: statusItem, requestedWidth: appliedWidth).isRendered
    }

    // MARK: - Install

    /// Registers the status item with the system menu bar and starts the geometry monitor.
    func install(model: UsageViewModel) {
        guard statusItem == nil else { return }   // idempotent: never two items
        self.model = model
        NotificationCenter.default.publisher(for: .init("MingetShowDetailWindow")).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.showDetailWindow() }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .init("MingetShowAbout")).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsWindowController?.show(section: .about) }
        }.store(in: &cancellables)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.autosaveName = Self.autosaveName
        guard let button = item.button else { return }

        button.setAccessibilityLabel("明明有数 · Minget 菜单栏")

        // We own dismissal so a status-button click cannot auto-close the popover and
        // immediately re-open it on the same event.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])

        // Size the item from the fixed label width before the first paint, so the
        // first geometry check has a real baseline to compare the granted width
        // against (v1.0.2 §3.3). The width never changes after this; the label
        // observes the model itself.
        apply()

        let monitor = MenuBarSpaceMonitor(controller: self, interval: Self.geometryCheckInterval)
        self.monitor = monitor
        monitor.start()

        // The label observes the model itself, so a content update costs the
        // controller nothing. This sink only keeps a visible popover sized to
        // its content, and notices a change in the Google account count for the
        // same reason.
        model.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.resizeVisiblePanel()
                        if let self, let count = self.model?.google.accounts.count,
                           count != self.lastGoogleAccountCount {
                            self.lastGoogleAccountCount = count
                            self.resizeVisiblePanel()
                        }
                    }
                }
            }
            .store(in: &cancellables)

        DetailPreferences.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.resizeVisiblePanel() } }
        }.store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialLayoutDelay) { [weak self] in
            MainActor.assumeIsolated { self?.checkGeometry() }
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
        dismissMonitor.stop()   // idempotent: no callback survives the item
        popover.delegate = nil
        detailWindowController?.window?.orderOut(nil)
        detailWindowController = nil
        settingsWindowController?.window?.orderOut(nil)
        settingsWindowController = nil
        if let item = statusItem {
            item.button?.subviews.forEach { $0.removeFromSuperview() }
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        model = nil
        appliedWidth = 0
        hasAutoOpenedDetailWindow = false
        stateMachine = MenuBarSpaceStateMachine()
        selfResizeSettlesAt = .distantPast
    }

    /// Notification-driven entry point from the monitor.
    ///
    /// The item's width is a fixed constant, so the only question a
    /// geometry observation can answer is whether macOS can currently
    /// render the item at all. When it cannot, the detail window opens
    /// after our own resize has settled, so a transient layout pass
    /// never pops a window.
    func checkGeometry() {
        guard let item = statusItem else { return }

        // The truncation rule compares the width macOS granted with the
        // width the app asked for. The asked width is the fixed label
        // width, so the baseline is honest from the first observation on;
        // the pre-1.6.8 fallback-as-baseline made a roomy menu bar look
        // truncated, which 1.1.2 forbids.
        let facts = Self.facts(for: item, requestedWidth: appliedWidth)
        // `requested` is what the app asked for; the frame width in
        // `facts` is what macOS granted. Both are geometry only, no
        // content.
        Diagnostics.log("menu bar \(facts.diagnosticSummary) requested:\(Int(appliedWidth.rounded()))")

        if case .openDetailWindow = stateMachine.apply(facts) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.selfResizeSettleInterval) { [weak self] in
                MainActor.assumeIsolated { self?.openDetailWindowIfItemIsHidden() }
            }
        }
    }

    // MARK: - Display

    /// Sizes the item to the fixed label width and installs the label.
    /// Runs once at install: the width is a constant and the label
    /// observes the model itself afterwards.
    private func apply() {
        guard let statusItem else { return }
        let width = MenuBarLabelMetrics.itemWidth
        statusItem.length = width
        appliedWidth = width
        selfResizeSettlesAt = Date().addingTimeInterval(Self.selfResizeSettleInterval)

        guard let button = statusItem.button, let model else { return }
        // The SwiftUI label is the whole content; the button's own title stays empty.
        button.title = ""
        button.subviews.forEach { $0.removeFromSuperview() }
        let padding = MenuBarLabelMetrics.horizontalPadding
        let hosting = MenuBarHostingView(rootView: MenuBarLabelView(model: model))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(x: padding / 2, y: 0,
                               width: max(1, width - padding),
                               height: NSStatusBar.system.thickness)
        button.addSubview(hosting)
    }

    // MARK: - Actions

    /// Internal (not private) so the wiring tests can pin the button to this action.
    @objc func statusItemClicked(_ sender: Any?) {
        Diagnostics.log("status action shown=\(popover.isShown) time=\(ProcessInfo.processInfo.systemUptime) type=\(NSApp.currentEvent?.type.rawValue ?? 0)")
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
            Diagnostics.log("status toggle closing")
            popover.performClose(nil)
            return
        }
        Diagnostics.log("status toggle opening")
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            showDetailWindow()
            return
        }
        let screen = buttonWindow.screen ?? NSScreen.main
        let preferences = DetailPreferences.shared
        let size = Self.panelSize(for: preferences, visibleFrame: screen?.visibleFrame, googleAccountCount: model?.google.accounts.count ?? 0, model: model)

        // A short screen is handled by the page's scroll region. Only an unavailable width
        // still requires the regular detail window fallback.
        guard Self.panelFits(size: size, visibleFrame: screen?.visibleFrame) else {
            Diagnostics.log("panel width does not fit the screen, opening the detail window instead")
            showDetailWindow()
            return
        }

        let screenHeight = DetailPageLayout.viewportHeight(preferredHeight: 2_000,
                                                           visibleFrame: screen?.visibleFrame)
        guard let controller = makePanelViewController(maxHeight: screenHeight) else { return }
        NSApp.activate(ignoringOtherApps: true)
        // Both the hosting controller and the popover are given the final size *before*
        // `show`, so AppKit positions a panel of the right size rather than resizing one it
        // has already placed.
        controller.preferredContentSize = size
        popover.contentSize = size
        popover.contentViewController = controller
        // Anchor to a two-point-wide rect at the button's exact horizontal midpoint. Using
        // the whole variable-width button lets AppKit choose an edge midpoint that can drift
        // when the menu-bar label changes width; the detail page and arrow should share one
        // stable center line.
        let centerAnchor = Self.centerAnchor(in: button.bounds)
        popover.appearance = NSApp.effectiveAppearance
        popover.show(relativeTo: centerAnchor, of: button, preferredEdge: .minY)
        // Installed after `show`, so the click that opened the panel cannot be seen by the
        // monitor and close it again. `isShown` alone was not reliable enough across macOS
        // versions; this makes the outside-click behaviour explicit and testable
        // (v1.0.2 requirement 4).
        dismissMonitor.install(popover: popover, statusButton: button,
                               onDismiss: { [weak self] in
                                   Diagnostics.log("status monitor outside close")
                                   self?.closePanel()
                               })
    }

    func closePanel() {
        if popover.isShown { popover.performClose(nil) }
        dismissMonitor.stop()
    }

    private func resizeVisiblePanel() {
        guard popover.isShown, let button = statusItem?.button else { return }
        let frame = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let size = Self.panelSize(for: DetailPreferences.shared, visibleFrame: frame, googleAccountCount: model?.google.accounts.count ?? 0, model: model)
        // Never replace a visible host for view state changes. SwiftUI updates its
        // observed model in place; account counts or visibility may resize the shell.
        guard popover.contentSize != size else { return }
        popover.contentSize = size

    }

    /// Every close path ends here, including the ones AppKit starts itself (escape key, app
    /// deactivation, a click on another window), so no monitor outlives the popover.
    func popoverDidClose(_ notification: Notification) {
        Diagnostics.log("status popover did close")
        dismissMonitor.stop()
    }

    /// Opens the detail in its own regular window. Used at launch when the menu bar item is
    /// occluded, when the panel cannot fit the screen, and from the settings window.
    func showDetailWindow() {
        guard let model else { return }
        closePanel()
        if detailWindowController == nil {
            detailWindowController = DetailWindowController(
                model: model,
                onSettings: { [weak self] in self?.showSettingsWindow() },
                onAccounts: { [weak self] in self?.showAccountsWindow() },
                onQuit: { NSApp.terminate(nil) })
        }
        detailWindowController?.present(centeredOn: statusItem)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the one small settings window. It shares the application model and display
    /// preferences with both detail presentations, so no second refresh engine is created.
    func showSettingsWindow() {
        guard let model else { return }
        closePanel()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                model: model,
                onDetailWindow: { [weak self] in self?.showDetailWindow() },
                onQuit: { NSApp.terminate(nil) })
        }
        settingsWindowController?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAccountsWindow(firstRun: Bool = false) {
        showSettingsWindow()
        settingsWindowController?.show(section: .accounts, firstRun: firstRun)
    }

    func makePanelViewController(maxHeight: CGFloat? = nil,
                                 refreshOnAppear: Bool = true) -> PanelHostingController? {
        guard let model else { return nil }
        return PanelHostingController(
            model: model,
            preferences: DetailPreferences.shared,
            maxHeight: maxHeight,
            refreshOnAppear: refreshOnAppear,
            onSettings: { [weak self] in self?.showSettingsWindow() },
            onAccounts: { [weak self] in self?.showAccountsWindow() },
            onQuit: { NSApp.terminate(nil) })
    }

    // MARK: - Panel geometry

    /// The panel's content size for the current display preferences.
    static func panelSize(for preferences: DetailPreferences,
                          visibleFrame: CGRect? = nil, googleAccountCount: Int = 2, model: UsageViewModel? = nil) -> NSSize {
        let preferredHeight = model.map { UsagePanelView.presentationHeight(model: $0, preferences: preferences) } ?? DetailPageLayout.stableViewportHeight
        return NSSize(width: DetailPageLayout.pageWidth,
                      height: DetailPageLayout.viewportHeight(preferredHeight: preferredHeight,
                                                              visibleFrame: visibleFrame))
    }

    /// The popover anchor: a two-point-wide rect at the button's horizontal midpoint, so the
    /// panel and its arrow share one stable centre line no matter how wide the label is.
    static func centerAnchor(in buttonBounds: NSRect) -> NSRect {
        NSRect(x: buttonBounds.midX - 1,
               y: buttonBounds.minY,
               width: 2,
               height: buttonBounds.height)
    }

    /// Whether the panel width fits inside the screen's visible area. Height may be capped by
    /// `panelSize` and rendered with a scroll region when the page is taller than the screen.
    ///
    /// Pure on purpose: the caller passes a real `NSScreen.visibleFrame`, and the tests pass
    /// synthetic ones, so the fit rule is pinned without a window server.
    static func panelFits(size: NSSize, visibleFrame: CGRect?, inset: CGFloat = 8) -> Bool {
        guard let visibleFrame, visibleFrame.width > 0, visibleFrame.height > 0 else { return false }
        let usable = visibleFrame.insetBy(dx: inset, dy: inset)
        return size.width <= usable.width
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
///
/// It receives the same `DetailPreferences` instance the view renders from, so the size the
/// popover is given before `show` is the size the page actually draws.
final class PanelHostingController: NSHostingController<UsagePanelView> {
    init(model: UsageViewModel,
         preferences: DetailPreferences,
         maxHeight: CGFloat? = nil,
         refreshOnAppear: Bool = true,
         onSettings: (() -> Void)?,
         onAccounts: (() -> Void)? = nil,
         onQuit: (() -> Void)? = nil) {
        let view = UsagePanelView(model: model,
                                  preferences: preferences,
                                  maxHeight: maxHeight,
                                  refreshOnAppear: refreshOnAppear,
                                  onSettings: onSettings,
                                  onAccounts: onAccounts,
                                  onQuit: onQuit)
        super.init(rootView: view)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Regular, closable window holding the same detail view. Not a floating panel: it uses the
/// normal window level and behaves like any other document window.
///
/// The window is 440 pt wide with a stable, screen-bounded viewport.
/// Service selection and quota disclosure update only the content, never its outer frame. The first presentation centres on the menu-bar icon and is clamped into the screen's
/// visible area, so it can never open partly off-screen.
final class DetailWindowController: NSWindowController {

    private let model: UsageViewModel
    private var cancellables: Set<AnyCancellable> = []

    init(model: UsageViewModel,
         onSettings: (() -> Void)?,
         onAccounts: (() -> Void)? = nil,
         onQuit: (() -> Void)? = nil) {
        self.model = model
        let preferences = DetailPreferences.shared
        let preferredHeight = UsagePanelView.presentationHeight(model: model)
        let maxHeight = DetailPageLayout.viewportHeight(preferredHeight: 2_000,
                                                        visibleFrame: NSScreen.main?.visibleFrame)
        let panel = UsagePanelView(model: model,
                                   preferences: preferences,
                                   maxHeight: maxHeight,
                                   onSettings: onSettings,
                                   onAccounts: onAccounts,
                                   onQuit: onQuit)
        let height = min(preferredHeight, maxHeight)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                  width: DetailPageLayout.pageWidth,
                                                  height: height),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "额度详情"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: panel)
        super.init(window: window)
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyPreferredContentSize() } }
        }.store(in: &cancellables)
        preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyPreferredContentSize() } }
        }.store(in: &cancellables)
    }

    private func applyPreferredContentSize() {
        guard let window else { return }
        let preferredHeight = UsagePanelView.presentationHeight(model: model)
        let height = DetailPageLayout.viewportHeight(preferredHeight: preferredHeight,
                                                     visibleFrame: NSScreen.main?.visibleFrame)
        let size = NSSize(width: DetailPageLayout.pageWidth, height: height)
        if window.contentLayoutRect.size != size { window.setContentSize(size) }
    }

    /// Shows the window, positioned by the status item rather than by AppKit's default.
    ///
    /// The window is centred on the menu-bar icon and then clamped into the hosting screen's
    /// visible frame, so no part of the page lands off-screen. With no usable icon window —
    /// which is exactly the hidden-icon case this window exists for — it falls back to
    /// `center()`.
    func present(centeredOn statusItem: NSStatusItem?) {
        guard let window else { return }
        applyPreferredContentSize()

        if let button = statusItem?.button, let buttonWindow = button.window,
           let screen = buttonWindow.screen ?? NSScreen.main {
            let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let size = window.frame.size
            let bounds = screen.visibleFrame
            let inset: CGFloat = 8
            let targetX = buttonFrame.midX - size.width / 2
            let lowerX = bounds.minX + inset
            let upperX = max(lowerX, bounds.maxX - size.width - inset)
            let lowerY = bounds.minY + inset
            let upperY = max(lowerY, bounds.maxY - size.height - inset)
            window.setFrameOrigin(NSPoint(x: min(max(targetX, lowerX), upperX),
                                          y: min(max(window.frame.origin.y, lowerY), upperY)))
        } else {
            window.center()
        }
        showWindow(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Regular settings window. Daily schedules are user-extensible, so the bounded window owns
/// a scrolling content region while keeping a fixed desktop footprint.
final class SettingsWindowController: NSWindowController {
    private let navigation = SettingsNavigation()
    func show(section: SettingsSection? = nil, firstRun: Bool = false) {
        if let section { navigation.section = section }
        navigation.firstRun = firstRun
        showWindow(nil)
    }


    init(model: UsageViewModel,
         onDetailWindow: (() -> Void)?,
         onQuit: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                  width: MingetSettingsView.pageSize.width,
                                                  height: MingetSettingsView.pageSize.height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "明明有数设置"
        window.minSize = NSSize(width: 700, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        let view = MingetSettingsView(model: model, onDetailWindow: onDetailWindow,
            onQuit: onQuit, navigation: navigation, onDone: { [weak self] in
                self?.navigation.firstRun = false
                self?.close()
                onDetailWindow?()
            })
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(MingetSettingsView.pageSize)
        window.setFrameAutosaveName("MingetUnifiedSettings")
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
    /// Observers together with the centre each was registered on: the workspace notifications
    /// arrive on `NSWorkspace.shared.notificationCenter`, not on `NotificationCenter.default`.
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var lastObservedFrame: NSRect = .zero

    init(controller: StatusItemController, interval: TimeInterval) {
        self.controller = controller
        self.interval = interval
    }

    func start() {
        let center = NotificationCenter.default

        // Screen set changed: a display was connected, removed, or the arrangement moved.
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }))

        // The Mac woke: menu bar space is often renegotiated around sleep and wake. This
        // notification is posted on the workspace's own centre; observing it on
        // `NotificationCenter.default` — which is what the baseline did — never fires
        // (v1.0.2 §4.4).
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }))

        // The item moved or was resized. AppKit has no single frame-change notification, so
        // the two halves are observed. A resize the app itself requested is not an
        // external event: treating it as one would feed the state machine its own output
        // and could grow/shrink in a loop.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append((center, center.addObserver(forName: name,
                                                         object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.handleFrameChange(note) }
            }))
        }

        // Fallback check. Pure local geometry: no network, no private API.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
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
        report()
    }

    /// Public hook so a model update can trigger a check without waiting for the timer.
    func requestCheck() {
        report()
    }

    private func report() {
        guard let controller else { return }
        if let frame = controller.statusItem?.button?.window?.frame {
            lastObservedFrame = frame
        }
        controller.checkGeometry()
    }
}

/// Closes the popover when the click lands outside it, without swallowing the click.
///
/// v1.5.0 owns dismissal explicitly because AppKit's transient auto-close can run before
/// the status button's mouse-up action, making one click close and immediately reopen it:
/// - a local monitor dismisses clicks elsewhere inside this app and clicks on the popover
///   arrow where it overlaps the status button; an actual button click uses its action,
/// - application deactivation dismisses clicks in other apps and on the desktop,
/// - Escape also dismisses,
/// - the returned event is never consumed, so the click still reaches its original target.
///
/// The monitors exist only while the popover is on screen, and every stop path removes them.
@MainActor
final class PopoverDismissMonitor {

    private var localMonitor: Any?
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?

    /// How many times the dismissal watchers were installed. An already-open popover must
    /// not stack another set of watchers; the wiring tests read this.
    private(set) var installCount = 0

    /// Introspection for the wiring tests.
    var isInstalled: Bool {
        localMonitor != nil || escapeMonitor != nil || resignObserver != nil || workspaceObserver != nil
    }

    /// Installs the dismissal watchers. Idempotent across repeated presentations.
    func install(popover: NSPopover, statusButton: NSButton?,
                 mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
                 onDismiss: @escaping () -> Void) {
        guard !isInstalled else { return }
        installCount += 1
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated {
                let target = Self.target(for: event, popover: popover, statusButton: statusButton)
                Diagnostics.log("status local down event=\(event.eventNumber) target=\(target)")
                if target == .outside { onDismiss() }
                if target == .statusItemButton && event.window !== statusButton?.window {
                    // The popover arrow can cover part of the menu bar button. In that
                    // overlap, the button receives no action and we must close directly.
                    onDismiss()
                }
            }
            // Returning the event unchanged is what lets the click do its original job.
            return event
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { onDismiss() }
            return nil
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                // macOS can temporarily deactivate an accessory app while forwarding a
                // status-button click. Let the button action perform the only toggle.
                if Self.frame(of: statusButton)?.contains(mouseLocation()) == true {
                    Diagnostics.log("status resign over button: awaiting button action")
                    return
                }
                Diagnostics.log("status resign outside button: dismiss")
                onDismiss()
            }
        }

        // Cmd-Tab must still dismiss when the pointer happens to remain over our button.
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated {
                Diagnostics.log("status another application activated: dismiss")
                onDismiss()
            }
        }
    }

    /// Removes every watcher. Safe to call more than once, and from any close path.
    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        localMonitor = nil
        escapeMonitor = nil
        resignObserver = nil
        workspaceObserver = nil
    }

    /// Resolves an AppKit event into the pure click target. Window coordinates are converted
    /// to screen coordinates here so the decision itself stays a plain rectangle test.
    ///
    /// A sheet presented by the panel (`MingetAboutView`) is a separate window whose
    /// `sheetParent` is the popover's window; it belongs to the popover and must not be
    /// treated as an outside click.
    static func target(for event: NSEvent, popover: NSPopover, statusButton: NSButton?) -> PopoverClickTarget {
        guard let window = event.window else { return .outside }
        let popoverWindow = popover.isShown ? popover.contentViewController?.view.window : nil
        if let popoverWindow, window.sheetParent === popoverWindow {
            return .popoverContent
        }
        let clickPoint = window.convertPoint(toScreen: event.locationInWindow)
        return PopoverDismissDecision.target(clickPoint: clickPoint,
                                            popoverFrame: popoverWindow?.frame,
                                            statusButtonFrame: Self.frame(of: statusButton))
    }

    /// The status button's frame in screen coordinates, or nil when it has no window.
    static func frame(of button: NSButton?) -> CGRect? {
        guard let button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}

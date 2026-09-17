import AppKit
import XCTest
@testable import UsageMonitorCore
@testable import UsageMonitorApp

/// Application wiring: the status item is registered with the system status bar, works
/// through a full install / label / uninstall cycle, and leaves nothing behind.
///
/// These tests drive the real AppKit objects inside the XCTest host process. They never
/// start the Codex service, so no child process is spawned: the view model is given a
/// client factory that cannot launch anything.
@MainActor
final class StatusItemWiringTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()

        // GitHub-hosted macOS runners do not provide a WindowServer connection. AppKit
        // status-item creation aborts there before XCTest can make an assertion. These
        // integration tests still run in full on a logged-in local macOS session.
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            throw XCTSkip("Status-item integration tests require a logged-in macOS window server")
        }
    }

    /// A service whose factory never launches `codex app-server`, and an engine over no
    /// real readers: fetching would fail without touching the outside world, which is
    /// exactly what these tests need.
    private func makeModel() -> UsageViewModel {
        let service = UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                                   cache: UsageCache(userDefaults: Self.isolatedDefaults()))
        return UsageViewModel(service: service, providerEngine: ProviderRefreshEngine(readers: []))
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suite = "UsageMonitorAppTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testInstallRegistersAnItemWithTheSystemStatusBar() throws {
        let controller = StatusItemController()
        XCTAssertFalse(controller.isInstalled)

        controller.install(model: makeModel())

        XCTAssertTrue(controller.isInstalled, "install must create the status item")
        let item = try XCTUnwrap(controller.statusItem)
        XCTAssertEqual(item.autosaveName, StatusItemController.autosaveName,
                       "the stable autosave name keeps the item's place across relaunches")
        // `install` applies the measured label width immediately; only before `apply` runs
        // is the length still the registration value.
        XCTAssertGreaterThan(item.length, 0)
        let button = try XCTUnwrap(item.button)
        XCTAssertEqual(button.action, #selector(StatusItemController.statusItemClicked(_:)))
        XCTAssertTrue(controller.isMonitorRunning, "the geometry monitor must be running")
        XCTAssertFalse(controller.isPopoverShown)

        controller.uninstall()
    }

    func testUninstallStopsTheMonitorClosesSurfacesAndRemovesTheItem() {
        let controller = StatusItemController()
        controller.install(model: makeModel())
        XCTAssertTrue(controller.isInstalled)

        controller.uninstall()

        XCTAssertNil(controller.statusItem, "the item must be handed back to the system status bar")
        XCTAssertFalse(controller.isMonitorRunning, "the geometry monitor must stop")
        XCTAssertFalse(controller.isPopoverShown)
        XCTAssertFalse(controller.isStatusItemRendered, "no item, nothing rendered")
    }

    /// Exit must be able to call uninstall twice (applicationWillTerminate plus a forced
    /// sweep) without crashing or resurrecting anything.
    func testUninstallIsIdempotent() {
        let controller = StatusItemController()
        controller.install(model: makeModel())
        controller.uninstall()
        controller.uninstall()
        XCTAssertFalse(controller.isInstalled)
        XCTAssertFalse(controller.isMonitorRunning)
    }

    /// A fresh install after uninstall must work: a quit-and-relaunch inside one process
    /// leaves a usable item, not a broken half-state.
    func testReinstallAfterUninstallProducesAWorkingItem() throws {
        let controller = StatusItemController()
        let model = makeModel()

        controller.install(model: model)
        controller.uninstall()

        controller.install(model: model)
        XCTAssertTrue(controller.isInstalled)
        XCTAssertTrue(controller.isMonitorRunning)
        let item = try XCTUnwrap(controller.statusItem)
        XCTAssertEqual(item.autosaveName, StatusItemController.autosaveName)
        controller.uninstall()
    }

    /// The measured label must be applied to the registered item: a width of zero would
    /// make the item invisible in the real menu bar.
    func testInstallAppliesANonZeroWidthToTheItem() throws {
        let controller = StatusItemController()
        controller.install(model: makeModel())

        let item = try XCTUnwrap(controller.statusItem)
        XCTAssertGreaterThan(item.length, 0, "the label width must be applied to the registered item")
        let button = try XCTUnwrap(item.button)
        XCTAssertEqual(button.accessibilityLabel(), "明明有数 · Minget 菜单栏")

        controller.uninstall()
    }

    // MARK: - Popover geometry (REVISION_SPEC.md §8, §11.5)

    /// The panel's size must be the page's real size, for every display-preference state.
    func testPanelSizeMatchesTheFixedPageSizes() {
        let defaults = UserDefaults(suiteName: "UsageMonitorAppTests.PanelSize." + UUID().uuidString)!
        defer { defaults.removePersistentDomain(forName: "UsageMonitorAppTests.PanelSize") }
        let preferences = DetailPreferences(defaults: defaults)

        XCTAssertEqual(StatusItemController.panelSize(for: preferences), NSSize(width: 440, height: 552))

        preferences.showDeepSeek = false
        XCTAssertEqual(StatusItemController.panelSize(for: preferences), NSSize(width: 440, height: 498))

        preferences.showCommandCode = false
        XCTAssertEqual(StatusItemController.panelSize(for: preferences), NSSize(width: 440, height: 330))

        preferences.showDeepSeek = true
        XCTAssertEqual(StatusItemController.panelSize(for: preferences), NSSize(width: 440, height: 384))
    }

    /// The hosting controller and the popover must be given the same size before `show`, so
    /// AppKit places a panel of the final size instead of resizing one already on screen.
    func testHostingControllerAndLoaderAgreeOnThePanelSizeBeforeShow() {
        let controller = StatusItemController()
        let model = makeModel()
        controller.install(model: model)
        defer { controller.uninstall() }

        let preferences = DetailPreferences.shared
        let hosting = try? XCTUnwrap(controller.makePanelViewController())
        XCTAssertNotNil(hosting)

        let expected = StatusItemController.panelSize(for: preferences)
        let popover = NSPopover()
        // Mirrors exactly what `togglePanel` does, in the same order, before `show`.
        hosting?.preferredContentSize = expected
        popover.contentSize = expected
        popover.contentViewController = hosting

        XCTAssertEqual(hosting?.preferredContentSize, expected)
        XCTAssertEqual(popover.contentSize, expected)
        XCTAssertEqual(NSSize(width: hosting!.view.fittingSize.width,
                              height: hosting!.view.fittingSize.height),
                       expected,
                       "the hosted page must lay out at the size the popover was given")
    }

    func testTheAnchorIsTheButtonMidpoint() {
        let bounds = NSRect(x: 0, y: 0, width: 96, height: 24)
        let anchor = StatusItemController.centerAnchor(in: bounds)
        XCTAssertEqual(anchor.midX, bounds.midX, accuracy: 0.001)
        XCTAssertEqual(anchor.width, 2)
        XCTAssertEqual(anchor.minY, bounds.minY)
        XCTAssertEqual(anchor.height, bounds.height)

        // A wider label moves the anchor with it rather than pinning to an edge.
        let wide = StatusItemController.centerAnchor(in: NSRect(x: 0, y: 0, width: 180, height: 24))
        XCTAssertEqual(wide.midX, 90, accuracy: 0.001)
    }

    func testThePanelOnlyShowsWhenTheWholePageFitsOnScreen() {
        let size = NSSize(width: 440, height: 552)

        // A normal laptop screen: the panel fits with room to spare.
        XCTAssertTrue(StatusItemController.panelFits(
            size: size, visibleFrame: CGRect(x: 0, y: 25, width: 1512, height: 944)))

        // A narrow portrait or split screen: the 440 pt page no longer fits, so the caller
        // must fall back to the detail window instead of showing a clipped popover.
        XCTAssertFalse(StatusItemController.panelFits(
            size: size, visibleFrame: CGRect(x: 0, y: 25, width: 420, height: 944)))
        XCTAssertFalse(StatusItemController.panelFits(
            size: size, visibleFrame: CGRect(x: 0, y: 25, width: 1512, height: 500)))

        // No screen at all: never claim it fits.
        XCTAssertFalse(StatusItemController.panelFits(size: size, visibleFrame: nil))
        XCTAssertFalse(StatusItemController.panelFits(size: size, visibleFrame: .zero))
    }

    /// The three menu-bar positions REVISION_SPEC.md §12 asks evidence for, recorded as the
    /// numbers the fit decision is actually made from. Final placement is AppKit's; what this
    /// pins is that the page can never be shown where it does not fit.
    func testRecordPopoverFrameEvidenceForCentreAndBothEdges() throws {
        let preferences = DetailPreferences.shared
        let size = StatusItemController.panelSize(for: preferences)
        let screen = CGRect(x: 0, y: 25, width: 1512, height: 944)

        let positions: [(String, CGFloat)] = [
            ("中央", screen.midX),
            ("左边缘", screen.minX + 20),
            ("右边缘", screen.maxX - 20),
        ]

        var lines = [
            "1.3.0 弹层 frame 证据（合成屏幕，非截图）",
            "屏幕 visibleFrame: \(Int(screen.width))×\(Int(screen.height)) @ (\(Int(screen.minX)),\(Int(screen.minY)))",
            "弹层内容尺寸: \(Int(size.width))×\(Int(size.height))",
            "锚点：状态按钮 bounds.midX 处 2 pt 宽矩形",
            "",
            "位置\t图标 midX\t锚点 minX\t能否完整容纳\t决策",
        ]
        for (name, midX) in positions {
            let anchor = StatusItemController.centerAnchor(
                in: NSRect(x: midX - 48, y: 0, width: 96, height: 24))
            let fits = StatusItemController.panelFits(size: size, visibleFrame: screen)
            lines.append("\(name)\t\(Int(midX))\t\(Int(anchor.minX))\t\(fits ? "是" : "否")\t\(fits ? "显示弹层" : "打开普通详情窗口")")
        }
        lines.append("")
        lines.append("说明：图标中心两侧各约 220 pt；弹层整体宽度 440 pt。图标贴近屏幕边缘时由 AppKit 调整箭头位置，")
        lines.append("本实现只在 440 × 页面高度无法完整落在 visibleFrame 内时改用普通详情窗口（AppKit 会自行把弹层移入屏幕）。")

        let directory = try MenuBarEvidenceRenderTests.evidenceDirectory()
        try lines.joined(separator: "\n").write(to: directory.appendingPathComponent("11-popover-frame-evidence.txt"),
                                                atomically: true, encoding: .utf8)
    }

    // MARK: - Settings window lifecycle (REVISION_SPEC.md §11.1)

    /// The settings window is created on demand and reused, so opening it repeatedly never
    /// stacks a second window — and, because nothing creates it at launch, a cold start has
    /// no window at all.
    func testTheSettingsWindowIsCreatedOnDemandAndReused() {
        let controller = StatusItemController()
        let model = makeModel()
        controller.install(model: model)
        defer { controller.uninstall() }

        XCTAssertEqual(visibleSettingsWindows().count, 0,
                       "nothing may create the settings window before the user asks for it")

        controller.showSettingsWindow()
        let first = visibleSettingsWindows()
        XCTAssertEqual(first.count, 1, "one settings window per request at most")

        let size = first.first?.contentView?.fittingSize
        XCTAssertEqual(size?.width, 520)
        XCTAssertEqual(size?.height, 600)

        controller.showSettingsWindow()
        controller.showSettingsWindow()
        XCTAssertEqual(visibleSettingsWindows().count, 1, "reopening must not add another instance")
    }

    private func visibleSettingsWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.title == "明明有数设置" && $0.isVisible }
    }

    /// The regular detail window uses the same fixed page width and the same height the
    /// preferences ask for, so the fallback presentation is not a second layout.
    func testTheDetailWindowUsesTheFixedPageSize() {
        let controller = DetailWindowController(model: makeModel(), onSettings: nil)
        let window = controller.window
        XCTAssertEqual(window?.frame.width, DetailPageLayout.pageWidth)
        XCTAssertEqual(window?.contentView?.fittingSize.width, DetailPageLayout.pageWidth)
        XCTAssertEqual(window?.contentView?.fittingSize.height,
                       UsagePanelView.preferredHeight(for: DetailPreferences.shared))
    }

    // MARK: - Redirect pollution at the app boundary

    /// The provider flows run through transports built exactly like the app builds them.
    /// After one request is refused a cross-domain redirect, the next request that fails
    /// for network reasons must be reported as that failure: refusal state is per task,
    /// never per transport.
    func testProviderTransportErrorCategoriesStayPerRequest() async {
        AppTransportStub.reset { _ in .redirect(to: "https://evil.example.com/user/balance") }
        let transport = URLSessionProviderTransport(timeout: 5, protocolClasses: [AppTransportStub.self])

        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!))
            XCTFail("the refused request must fail")
        } catch {
            XCTAssertEqual(error as? ProviderTransportError, .crossDomainRedirectBlocked)
        }

        AppTransportStub.reset { _ in .fail(.cannotConnectToHost) }
        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!))
            XCTFail("the second request must fail")
        } catch {
            XCTAssertEqual(error as? ProviderTransportError, .networkUnreachable,
                           "a later network failure must not inherit an earlier task's refusal")
        }
    }
}

/// In-process `URLProtocol` stub, mirroring the Core test suite's stub: a redirect is only
/// a redirect for the session once it is reported through `urlProtocol(_:wasRedirectedTo:)`.
final class AppTransportStub: URLProtocol {

    enum Outcome {
        case plain(status: Int, body: Data)
        case redirect(to: String)
        case fail(URLError.Code)
    }

    private static let lock = NSLock()
    private static var maker: ((URLRequest) -> Outcome)?

    static func reset(_ responseMaker: @escaping (URLRequest) -> Outcome) {
        lock.lock()
        maker = responseMaker
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }

    override func startLoading() {
        Self.lock.lock()
        let maker = Self.maker
        Self.lock.unlock()
        guard let maker, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch maker(request) {
        case .plain(let status, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let location):
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": location])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let target = URL(string: location) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            }
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

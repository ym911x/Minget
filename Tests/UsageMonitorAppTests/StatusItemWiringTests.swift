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

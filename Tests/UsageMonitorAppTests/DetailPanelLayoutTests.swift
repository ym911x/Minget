import XCTest
import AppKit
import SwiftUI
import UsageMonitorCore
@testable import UsageMonitorApp

@MainActor
final class DetailPanelLayoutTests: XCTestCase {

    func testDetailHeightShrinksWithHiddenProviderCards() {
        let suiteName = "UsageMonitorAppTests.DetailPanelLayout." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = DetailPreferences(defaults: defaults)
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 630)

        preferences.showDeepSeek = false
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 530)

        preferences.showCommandCode = false
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 320)

        preferences.showDeepSeek = true
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 420)
    }

    func testDetailPageDoesNotEmbedAScrollView() {
        let suiteName = "UsageMonitorAppTests.DetailPanelLayout.NoScroll." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = DetailPreferences(defaults: defaults)
        let service = UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                                   cache: UsageCache(userDefaults: defaults))
        let engine = ProviderRefreshEngine(readers: [],
                                           cache: ProviderCache(userDefaults: defaults))
        let model = UsageViewModel(service: service, providerEngine: engine)
        let hosting = NSHostingView(rootView: UsagePanelView(model: model,
                                                              preferences: preferences))
        hosting.frame = NSRect(x: 0, y: 0, width: 420,
                               height: UsagePanelView.preferredHeight(for: preferences))
        hosting.layoutSubtreeIfNeeded()

        XCTAssertFalse(containsScrollView(hosting),
                       "the detail page must show the full fixed-height surface without a scroll container")
    }

    func testProductNameFollowsSystemLanguage() {
        XCTAssertEqual(UsagePanelView.productName(preferredLanguages: ["zh-Hans-CN"]), "明明有数")
        XCTAssertEqual(UsagePanelView.productName(preferredLanguages: ["en-US"]), "Minget")
        XCTAssertEqual(UsagePanelView.productName(preferredLanguages: ["fr-FR"]), "明明有数")
    }

    private func containsScrollView(_ view: NSView) -> Bool {
        if view is NSScrollView { return true }
        return view.subviews.contains { containsScrollView($0) }
    }
}

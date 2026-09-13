import XCTest
@testable import UsageMonitorApp

@MainActor
final class DetailPanelLayoutTests: XCTestCase {

    func testDetailHeightShrinksWithHiddenProviderCards() {
        let suiteName = "UsageMonitorAppTests.DetailPanelLayout." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = DetailPreferences(defaults: defaults)
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 475)

        preferences.showDeepSeek = false
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 400)

        preferences.showGLM = false
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 300)

        preferences.showDeepSeek = true
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 370)
    }

    func testProductNameFollowsSystemLanguage() {
        XCTAssertEqual(UsagePanelView.productName(preferredLanguages: ["zh-Hans-CN"]), "明明有数")
        XCTAssertEqual(UsagePanelView.productName(preferredLanguages: ["en-US"]), "Minget")
        XCTAssertEqual(UsagePanelView.productName(preferredLanguages: ["fr-FR"]), "明明有数")
    }
}

import XCTest
@testable import UsageMonitorApp

@MainActor
final class DetailPreferencesTests: XCTestCase {

    func testProviderVisibilityDefaultsToEnabledAndPersistsOnlyDisplayChoices() {
        let suiteName = "UsageMonitorAppTests.DetailPreferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = DetailPreferences(defaults: defaults)
        XCTAssertTrue(preferences.showDeepSeek)
        XCTAssertTrue(preferences.showGLM)

        preferences.showDeepSeek = false
        preferences.showGLM = false

        let restored = DetailPreferences(defaults: defaults)
        XCTAssertFalse(restored.showDeepSeek)
        XCTAssertFalse(restored.showGLM)
        XCTAssertNotNil(defaults.object(forKey: "detail.showDeepSeek"))
        XCTAssertNotNil(defaults.object(forKey: "detail.showGLM"))
    }
}

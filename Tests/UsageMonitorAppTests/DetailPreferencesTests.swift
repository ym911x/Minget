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
        XCTAssertTrue(preferences.showCommandCode)
        XCTAssertEqual(preferences.displayMode, .all)
        XCTAssertEqual(preferences.effectiveTab, .all)

        preferences.displayMode = .byProvider
        preferences.selectedTab = .deepSeek
        XCTAssertEqual(preferences.effectiveTab, .deepSeek)

        preferences.showDeepSeek = false
        preferences.showCommandCode = false
        XCTAssertEqual(preferences.effectiveTab, .all)
        XCTAssertEqual(preferences.selectedTab, .all)
        XCTAssertEqual(preferences.visibleTabs, [.all, .chatGPT])

        let restored = DetailPreferences(defaults: defaults)
        XCTAssertFalse(restored.showDeepSeek)
        XCTAssertFalse(restored.showCommandCode)
        XCTAssertEqual(restored.displayMode, .byProvider)
        XCTAssertEqual(restored.selectedTab, .all)
        XCTAssertEqual(restored.effectiveTab, .all)
        XCTAssertNotNil(defaults.object(forKey: "detail.showDeepSeek"))
        XCTAssertNotNil(defaults.object(forKey: "detail.showCommandCode"))
    }

    func testFirstRunGateDistinguishesNewInstallFromLegacyDataAndSkippedGuide() {
        let suiteName = "UsageMonitorAppTests.FirstRun." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertTrue(FirstRunGate.shouldPresent(defaults: defaults))
        FirstRunGate.markPresented(defaults: defaults)
        XCTAssertFalse(FirstRunGate.shouldPresent(defaults: defaults))
        defaults.removeObject(forKey: FirstRunGate.key)
        defaults.set(Data([1]), forKey: "UsageMonitor.lastSnapshotByProfileAccount.v3")
        XCTAssertFalse(FirstRunGate.shouldPresent(defaults: defaults))
    }
}

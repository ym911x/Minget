import XCTest
@testable import UsageMonitorApp

final class DisplayNamePreferencesTests: XCTestCase {

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "UsageMonitorAppTests.DisplayNames." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    func testNamesTrimPersistAndRestoreByStableServiceID() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = DisplayNamePreferences(defaults: defaults)
        XCTAssertEqual(preferences.displayName(for: "chatgpt-a"), "Codex 账号")
        XCTAssertEqual(preferences.displayName(for: DisplayNamePreferences.ServiceID.deepSeek), "DeepSeek")

        XCTAssertTrue(preferences.setDisplayName("  主力账号  ", for: "chatgpt-a"))
        XCTAssertEqual(preferences.displayName(for: "chatgpt-a"), "主力账号")
        XCTAssertTrue(preferences.customizedServiceIDs.contains("chatgpt-a"))

        let restored = DisplayNamePreferences(defaults: defaults)
        XCTAssertEqual(restored.displayName(for: "chatgpt-a"), "主力账号")
        XCTAssertEqual(restored.displayName(for: DisplayNamePreferences.ServiceID.deepSeek), "DeepSeek")
    }

    func testEmptyDefaultAndTooLongValuesFollowTheDocumentedRules() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = DisplayNamePreferences(defaults: defaults)
        XCTAssertTrue(preferences.setDisplayName("日常 API", for: DisplayNamePreferences.ServiceID.deepSeek))
        XCTAssertEqual(preferences.displayName(for: DisplayNamePreferences.ServiceID.deepSeek), "日常 API")

        XCTAssertTrue(preferences.setDisplayName("   ", for: DisplayNamePreferences.ServiceID.deepSeek))
        XCTAssertEqual(preferences.displayName(for: DisplayNamePreferences.ServiceID.deepSeek), "DeepSeek")

        XCTAssertTrue(preferences.setDisplayName("Command Code", for: DisplayNamePreferences.ServiceID.commandCode))
        XCTAssertFalse(preferences.customizedServiceIDs.contains(DisplayNamePreferences.ServiceID.commandCode))

        XCTAssertFalse(preferences.setDisplayName(String(repeating: "a", count: 41),
                                                  for: DisplayNamePreferences.ServiceID.commandCode))
        XCTAssertEqual(preferences.displayName(for: DisplayNamePreferences.ServiceID.commandCode), "Command Code")
    }

    func testUnknownServiceIDIsRejectedWithoutWritingPreferences() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = DisplayNamePreferences(defaults: defaults)
        XCTAssertFalse(preferences.setDisplayName("测试", for: "unknown-service"))
        XCTAssertEqual(preferences.displayName(for: "unknown-service"), "unknown-service")
        XCTAssertNil(defaults.object(forKey: "detail.displayNames.v1"))
    }
}

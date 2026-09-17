import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// Menu bar source selection and DeepSeek currency preferences (REQUIREMENTS.md §6.1,
/// IMPLEMENTATION_TASKS.md §6.2).
///
/// The preference stores a stable profile id, never an array index, and defaults to account A
/// so an upgrade from 1.2.1 keeps showing what the menu bar showed before.
@MainActor
final class MenuBarPreferencesTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageMonitorAppTests.MenuBarPreferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeModel(defaults: UserDefaults,
                           preferences: MenuBarPreferences) -> UsageViewModel {
        let cache = UsageCache(userDefaults: defaults)
        let coordinator = CodexProfilesCoordinator { profile in
            UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                         cache: cache,
                         profileID: profile.id)
        }
        let engine = ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults))
        return UsageViewModel(coordinator: coordinator,
                              providerEngine: engine,
                              menuBarPreferences: preferences)
    }

    // MARK: Persistence

    func testUpgradeDefaultsToAccountA() {
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)
        XCTAssertEqual(preferences.selection, .profile("chatgpt-a"))
        XCTAssertEqual(preferences.selectedProfileID, "chatgpt-a")
    }

    func testEverySelectionPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)

        for selection in [MenuBarPreferences.Selection.profile("chatgpt-b"), .deepSeek, .profile("chatgpt-a")] {
            preferences.selection = selection
            XCTAssertEqual(MenuBarPreferences(defaults: defaults).selection, selection,
                           "\(selection) must survive a relaunch")
        }
        XCTAssertEqual(defaults.string(forKey: "menubar.source.v1"), "chatgpt-a")
    }

    func testTheStoredValueIsAnIdentifierNotAnIndex() {
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)
        preferences.selection = .profile("chatgpt-b")
        XCTAssertEqual(defaults.string(forKey: "menubar.source.v1"), "chatgpt-b")

        preferences.selection = .deepSeek
        XCTAssertEqual(defaults.string(forKey: "menubar.source.v1"), "deepseek")
    }

    func testACorruptOrUnknownSourceFallsBackToAccountA() {
        let defaults = makeDefaults()
        defaults.set("chatgpt-does-not-exist", forKey: "menubar.source.v1")
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).selection, .profile("chatgpt-a"))

        defaults.set("", forKey: "menubar.source.v1")
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).selection, .profile("chatgpt-a"))

        defaults.removeObject(forKey: "menubar.source.v1")
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).selection, .profile("chatgpt-a"))
    }

    func testDeepSeekCurrencyPersistsAndCanBeCleared() {
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)
        XCTAssertNil(preferences.deepSeekCurrency)

        preferences.deepSeekCurrency = "USD"
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).deepSeekCurrency, "USD")

        preferences.deepSeekCurrency = nil
        XCTAssertNil(MenuBarPreferences(defaults: defaults).deepSeekCurrency)
        XCTAssertNil(defaults.string(forKey: "menubar.deepseekCurrency.v1"))
    }

    func testSelectionIsCodableWithStableIdentifiers() throws {
        let encoded = try JSONEncoder().encode(MenuBarPreferences.Selection.profile("chatgpt-b"))
        let decoded = try JSONDecoder().decode(MenuBarPreferences.Selection.self, from: encoded)
        XCTAssertEqual(decoded, .profile("chatgpt-b"))

        let deepSeek = try JSONDecoder().decode(
            MenuBarPreferences.Selection.self,
            from: try JSONEncoder().encode(MenuBarPreferences.Selection.deepSeek))
        XCTAssertEqual(deepSeek, .deepSeek)
    }

    func testPickerOffersProfilesThenDeepSeekInTheFixedOrder() {
        let preferences = MenuBarPreferences(defaults: makeDefaults())
        XCTAssertEqual(preferences.availableSelections(),
                       [.profile("chatgpt-a"), .profile("chatgpt-b"), .deepSeek])
        XCTAssertEqual(preferences.displayName(for: .profile("chatgpt-a")), "Codex 账号")
        XCTAssertEqual(preferences.displayName(for: .profile("chatgpt-b")), "Hermes / OpenClaw 账号")
        XCTAssertEqual(preferences.displayName(for: .deepSeek), "DeepSeek")
    }

    // MARK: The menu bar follows the preference

    func testMenuBarSourceFollowsTheSelectedProfile() {
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)
        let model = makeModel(defaults: defaults, preferences: preferences)

        guard case .chatGPT(let labelA, _, _) = model.menuBarSource() else {
            return XCTFail("account A must be the default source")
        }
        XCTAssertEqual(labelA, "A")

        preferences.selection = .profile("chatgpt-b")
        guard case .chatGPT(let labelB, _, _) = model.menuBarSource() else {
            return XCTFail("account B must be selectable")
        }
        XCTAssertEqual(labelB, "B")

        preferences.selection = .deepSeek
        guard case .deepSeek = model.menuBarSource() else {
            return XCTFail("DeepSeek must be selectable")
        }
    }

    func testSwitchingTheSourceChangesTheRenderedMenuBarText() {
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)
        let model = makeModel(defaults: defaults, preferences: preferences)

        let a = model.menuBarContent(for: .full)
        XCTAssertTrue(a.text.hasPrefix("A "), a.text)

        preferences.selection = .profile("chatgpt-b")
        let b = model.menuBarContent(for: .full)
        XCTAssertTrue(b.text.hasPrefix("B "), b.text)

        preferences.selection = .deepSeek
        let deepSeek = model.menuBarContent(for: .full)
        XCTAssertEqual(deepSeek.text, "DS —", "no balance yet, and never a fabricated zero")
        XCTAssertEqual(deepSeek.attention, .warning)
        XCTAssertFalse(deepSeek.showsTimeBars, "the DeepSeek source shows no reset-time rows")
        XCTAssertNotEqual(a.sizeSignature, deepSeek.sizeSignature)
    }

    func testDeepSeekMenuBarKeepsTheBalanceEvenWhenTheDetailCardIsHidden() {
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)
        preferences.selection = .deepSeek
        let model = makeModel(defaults: defaults, preferences: preferences)

        // Hiding the detail card is a separate preference and must not change the source.
        let detail = DetailPreferences(defaults: defaults)
        detail.showDeepSeek = false

        XCTAssertEqual(preferences.selection, .deepSeek)
        if case .deepSeek = model.menuBarSource() {} else {
            XCTFail("the menu bar source must stay DeepSeek while its detail card is hidden")
        }
    }

    func testAChangedPreferenceRepublishesSoTheStatusItemCanRemeasure() {
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)
        let model = makeModel(defaults: defaults, preferences: preferences)
        model.start()
        defer { model.stop() }

        let before = model.tick
        preferences.selection = .profile("chatgpt-b")

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, model.tick == before {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertGreaterThan(model.tick, before,
                             "a source change must reach the status item, not wait for the next fetch")
    }

    // MARK: Slash-command style constraints

    func testPreferenceObjectNeverCarriesCredentialsOrCaches() {
        // The type has exactly two stored preferences; this pins the surface so a later
        // version cannot quietly add a credential-shaped field here.
        let defaults = makeDefaults()
        let preferences = MenuBarPreferences(defaults: defaults)
        preferences.selection = .profile("chatgpt-b")
        preferences.deepSeekCurrency = "CNY"

        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("menubar.") }.sorted()
        XCTAssertEqual(keys, ["menubar.deepseekCurrency.v1", "menubar.source.v1"])
    }
}

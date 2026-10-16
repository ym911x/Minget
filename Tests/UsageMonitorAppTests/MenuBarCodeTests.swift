import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// The account codes every surface shows (1.6.8): `O1`/`O2` for ChatGPT,
/// `G1`/`G2`/`G3` for Gemini, `DS1` for DeepSeek.
///
/// The menu bar and the settings list both resolve a code through
/// `UsageViewModel.menuBarCode(for:)`, which is what keeps the two in step.
/// These tests pin that mapping, its registry-ordinal source, and the legacy
/// position fallback used when no registry exists.
@MainActor
final class MenuBarCodeTests: XCTestCase {

    private final class NoopTransport: ProviderTransport, @unchecked Sendable {
        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            ProviderHTTPResponse(status: 200, body: Data("{}".utf8))
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "MenuBarCodeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// The production composition: a registry carrying the two migrated ChatGPT
    /// profiles and the legacy DeepSeek row, plus the requested Google rows.
    private func makeManagedModel(_ defaults: UserDefaults, googleAccounts: Int = 0) throws -> UsageViewModel {
        let registry = try AccountRegistry(defaults: defaults, legacy: true)
        if googleAccounts > 0 {
            for index in 1...googleAccounts {
                var row = registry.draft(.google)
                row.googleUUID = UUID()
                row.googleEmail = "demo\(index)@example.com"
                row.googleVersion = AntigravityCLILocator.version
                try registry.upsert(row)
            }
        }
        let model = UsageViewModel(coordinator: CodexProfilesCoordinator(profiles: []),
                                   providerEngine: ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults)),
                                   menuBarPreferences: MenuBarPreferences(defaults: defaults),
                                   displayNames: DisplayNamePreferences(defaults: defaults),
                                   fireSchedules: FireSchedulePreferences(defaults: defaults))
        model.installAccountManagement(registry: registry, credentials: InMemoryCredentialStore(),
                                       transport: NoopTransport(), defaults: defaults)
        return model
    }

    private func makeLegacyModel(_ defaults: UserDefaults) -> UsageViewModel {
        let cache = UsageCache(userDefaults: defaults)
        let coordinator = CodexProfilesCoordinator { profile in
            UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                         cache: cache, profileID: profile.id)
        }
        return UsageViewModel(coordinator: coordinator,
                              providerEngine: ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults)),
                              menuBarPreferences: MenuBarPreferences(defaults: defaults))
    }

    func testChatGPTAccountsGetO1AndO2() throws {
        let model = try makeManagedModel(makeDefaults())
        XCTAssertEqual(model.menuBarCode(for: .profile("chatgpt-a")), "O1")
        XCTAssertEqual(model.menuBarCode(for: .profile("chatgpt-b")), "O2")
    }

    func testGoogleAccountsGetG1G2G3FromTheirOrdinals() throws {
        let model = try makeManagedModel(makeDefaults(), googleAccounts: 3)
        XCTAssertEqual(model.menuBarCode(for: .google("demo1@example.com")), "G1")
        XCTAssertEqual(model.menuBarCode(for: .google("demo2@example.com")), "G2")
        XCTAssertEqual(model.menuBarCode(for: .google("demo3@example.com")), "G3")
    }

    func testASecondDeepSeekAccountGetsDS2() throws {
        let defaults = makeDefaults()
        let model = try makeManagedModel(defaults)
        let registry = try XCTUnwrap(model.accountRegistry)
        let second = registry.draft(.deepseek, name: "第二个")
        try registry.upsert(second)
        model.reloadManagedAccounts()

        XCTAssertEqual(model.menuBarCode(for: .deepSeek), "DS1")
        XCTAssertEqual(model.menuBarCode(for: .apiAccount(second.id)), "DS2")
    }

    /// The number is the stored ordinal rather than the position in the list: after
    /// the first account is removed the survivor keeps `O2`, so a code never
    /// reshuffles under the user.
    func testRemovingAnAccountDoesNotRenumberTheOthers() throws {
        let defaults = makeDefaults()
        let model = try makeManagedModel(defaults)
        let registry = try XCTUnwrap(model.accountRegistry)

        try registry.remove("chatgpt-a")
        model.reloadManagedAccounts()

        XCTAssertEqual(model.managedAccounts.filter { $0.platform == .chatGPT }.map(\.ordinal), [2])
        XCTAssertEqual(model.menuBarCode(for: .profile("chatgpt-b")), "O2")
    }

    /// Without a registry the position in the current list stands in: that is the
    /// only order the legacy mode has.
    func testLegacyModeFallsBackToThePosition() {
        let model = makeLegacyModel(makeDefaults())
        XCTAssertNil(model.accountRegistry)
        XCTAssertEqual(model.menuBarCode(for: .profile("chatgpt-a")), "O1")
        XCTAssertEqual(model.menuBarCode(for: .profile("chatgpt-b")), "O2")
        XCTAssertEqual(model.menuBarCode(for: .deepSeek), "DS1")
        XCTAssertEqual(model.menuBarCode(for: .google("unknown@example.com")), "G1",
                       "with no accounts to count, the first code stands in")
    }

    /// The menu bar's own text carries the code the settings list shows for the same
    /// selection, because both resolve it through `menuBarCode(for:)`.
    func testTheMenuBarTextCarriesTheCodeTheSettingsListShows() throws {
        let model = try makeManagedModel(makeDefaults())

        model.menuBarPreferences.selection = .profile("chatgpt-b")
        let profileCode = model.menuBarCode(for: .profile("chatgpt-b"))
        XCTAssertEqual(profileCode, "O2")
        XCTAssertTrue(model.menuBarContent().text.hasPrefix(profileCode + " "), model.menuBarContent().text)

        model.menuBarPreferences.selection = .deepSeek
        let deepSeekCode = model.menuBarCode(for: .deepSeek)
        XCTAssertEqual(deepSeekCode, "DS1")
        XCTAssertTrue(model.menuBarContent().text.hasPrefix(deepSeekCode + " "), model.menuBarContent().text)
    }
}

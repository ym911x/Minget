import Foundation
import Combine

/// Non-secret choices that control which optional provider cards appear in the detail view.
///
/// This object deliberately owns only display preferences. It never reads credentials,
/// touches provider caches, or changes the refresh engine. A shared instance keeps the
/// popover, the regular detail window, and the settings window in sync.
final class DetailPreferences: ObservableObject {

    enum DisplayMode: String, CaseIterable { case all, byProvider }
    enum ProviderTab: String, CaseIterable { case all, chatGPT, deepSeek, commandCode }

    static let shared = DetailPreferences()

    private enum Key {
        static let showDeepSeek = "detail.showDeepSeek"
        static let showCommandCode = "detail.showCommandCode"
        static let displayMode = "detail.displayMode.v1"
        static let selectedTab = "detail.selectedTab.v1"
    }

    private let defaults: UserDefaults

    @Published var showDeepSeek: Bool {
        didSet {
            defaults.set(showDeepSeek, forKey: Key.showDeepSeek)
            if !showDeepSeek && selectedTab == .deepSeek { selectedTab = .all }
        }
    }
    @Published var showCommandCode: Bool {
        didSet {
            defaults.set(showCommandCode, forKey: Key.showCommandCode)
            if !showCommandCode && selectedTab == .commandCode { selectedTab = .all }
        }
    }
    @Published var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }
    @Published var selectedTab: ProviderTab {
        didSet { defaults.set(selectedTab.rawValue, forKey: Key.selectedTab) }
    }

    var effectiveTab: ProviderTab {
        guard displayMode == .byProvider else { return .all }
        switch selectedTab {
        case .deepSeek where !showDeepSeek, .commandCode where !showCommandCode: return .all
        default: return selectedTab
        }
    }

    var visibleTabs: [ProviderTab] {
        [.all, .chatGPT] + (showDeepSeek ? [.deepSeek] : []) + (showCommandCode ? [.commandCode] : [])
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let showDS = defaults.object(forKey: Key.showDeepSeek) as? Bool ?? true
        let showCC = defaults.object(forKey: Key.showCommandCode) as? Bool ?? true
        self.showDeepSeek = showDS
        self.showCommandCode = showCC
        self.displayMode = DisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? "") ?? .all
        let savedTab = ProviderTab(rawValue: defaults.string(forKey: Key.selectedTab) ?? "") ?? .all
        self.selectedTab = (savedTab == .deepSeek && !showDS)
            || (savedTab == .commandCode && !showCC) ? .all : savedTab
    }
}

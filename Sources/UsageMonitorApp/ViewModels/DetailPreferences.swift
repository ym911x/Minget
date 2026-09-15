import Foundation
import Combine

/// Non-secret choices that control which optional provider cards appear in the detail view.
///
/// This object deliberately owns only display preferences. It never reads credentials,
/// touches provider caches, or changes the refresh engine. A shared instance keeps the
/// popover, the regular detail window, and the settings window in sync.
final class DetailPreferences: ObservableObject {

    static let shared = DetailPreferences()

    private enum Key {
        static let showDeepSeek = "detail.showDeepSeek"
        static let showCommandCode = "detail.showCommandCode"
    }

    private let defaults: UserDefaults

    @Published var showDeepSeek: Bool {
        didSet { defaults.set(showDeepSeek, forKey: Key.showDeepSeek) }
    }
    @Published var showCommandCode: Bool {
        didSet { defaults.set(showCommandCode, forKey: Key.showCommandCode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showDeepSeek = defaults.object(forKey: Key.showDeepSeek) as? Bool ?? true
        self.showCommandCode = defaults.object(forKey: Key.showCommandCode) as? Bool ?? true
    }
}

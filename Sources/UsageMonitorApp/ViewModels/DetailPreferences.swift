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
        static let showGLM = "detail.showGLM"
    }

    private let defaults: UserDefaults

    @Published var showDeepSeek: Bool {
        didSet { defaults.set(showDeepSeek, forKey: Key.showDeepSeek) }
    }

    @Published var showGLM: Bool {
        didSet { defaults.set(showGLM, forKey: Key.showGLM) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showDeepSeek = defaults.object(forKey: Key.showDeepSeek) as? Bool ?? true
        self.showGLM = defaults.object(forKey: Key.showGLM) as? Bool ?? true
    }
}

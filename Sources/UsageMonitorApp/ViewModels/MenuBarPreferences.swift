import Foundation
import Combine
import UsageMonitorCore

/// Which source the system menu bar shows, and the DeepSeek display choices that go with it.
///
/// 1.3.0 requirement: exactly one source at a time, persisted as a *stable* identifier — a
/// profile id or the explicit DeepSeek marker — never an array index, so reordering or
/// extending the profile list cannot silently change what the user sees.
///
/// This object owns display choices only. It never reads credentials, never touches a
/// provider cache and never drives a refresh.
public final class MenuBarPreferences: ObservableObject {

    public static let shared = MenuBarPreferences()

    /// Stable, Codable selection.
    public enum Selection: Equatable, Hashable, Codable, Sendable {
        case profile(String)
        case deepSeek

        /// The exact string written to `UserDefaults`.
        public var storageValue: String {
            switch self {
            case .profile(let id): return id
            case .deepSeek: return Self.deepSeekStorageValue
            }
        }

        public static let deepSeekStorageValue = "deepseek"

        /// Parses a stored value, rejecting anything that is not a known profile id.
        /// An unknown id yields nil so the caller can fall back to the documented default
        /// instead of displaying an account that does not exist.
        public init?(storageValue: String, knownProfileIDs: [String]) {
            if storageValue == Self.deepSeekStorageValue { self = .deepSeek; return }
            guard knownProfileIDs.contains(storageValue) else { return nil }
            self = .profile(storageValue)
        }
    }

    private enum Key {
        static let selection = "menubar.source.v1"
        static let deepSeekCurrency = "menubar.deepseekCurrency.v1"
    }

    private let defaults: UserDefaults
    public let knownProfileIDs: [String]

    /// The selected source. Upgrading from 1.2.1 keeps showing account A, which is what the
    /// menu bar showed before.
    @Published public var selection: Selection {
        didSet { defaults.set(selection.storageValue, forKey: Key.selection) }
    }

    /// Preferred DeepSeek currency for the menu bar, or nil to use the documented fallback
    /// order. A display choice, not a credential.
    @Published public var deepSeekCurrency: String? {
        didSet {
            if let deepSeekCurrency, !deepSeekCurrency.isEmpty {
                defaults.set(deepSeekCurrency, forKey: Key.deepSeekCurrency)
            } else {
                defaults.removeObject(forKey: Key.deepSeekCurrency)
            }
        }
    }

    public init(defaults: UserDefaults = .standard,
                knownProfileIDs: [String] = ChatGPTAccountProfile.defaults.map(\.id)) {
        self.defaults = defaults
        self.knownProfileIDs = knownProfileIDs

        let fallback = Selection.profile(knownProfileIDs.first ?? ChatGPTAccountProfile.chatGPTA.id)
        // A missing or corrupt value falls back to account A. The app never scans the user's
        // home directory looking for another account to display.
        self.selection = Selection(storageValue: defaults.string(forKey: Key.selection) ?? "",
                                   knownProfileIDs: knownProfileIDs) ?? fallback
        let storedCurrency = defaults.string(forKey: Key.deepSeekCurrency)
        self.deepSeekCurrency = (storedCurrency?.isEmpty == false) ? storedCurrency : nil
    }

    /// The profile the menu bar shows, or nil when DeepSeek is selected.
    public var selectedProfileID: String? {
        if case .profile(let id) = selection { return id }
        return nil
    }

    /// Every selection the settings picker offers, in the fixed order: profiles first, then
    /// DeepSeek.
    public func availableSelections(profiles: [ChatGPTAccountProfile] = ChatGPTAccountProfile.defaults) -> [Selection] {
        profiles.map { .profile($0.id) } + [.deepSeek]
    }

    /// Display name for a menu bar source, used by the settings picker.
    public func displayName(for selection: Selection,
                            profiles: [ChatGPTAccountProfile] = ChatGPTAccountProfile.defaults) -> String {
        switch selection {
        case .deepSeek:
            return "DeepSeek"
        case .profile(let id):
            return profiles.first { $0.id == id }?.displayName ?? id
        }
    }
}

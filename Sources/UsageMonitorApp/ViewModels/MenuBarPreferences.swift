import Foundation
import Combine
import UsageMonitorCore

/// Which source the system menu bar shows, and the DeepSeek display choices that go with it.
///
/// 1.3.0 requirement: exactly one source at a time, persisted as a *stable* identifier — a
/// profile id or the explicit DeepSeek marker — never an array index, so reordering or
/// extending the profile list cannot silently change what the user sees.
///
/// This object owns menu bar display and cadence choices only. It never reads credentials,
/// never touches a provider cache and never drives a refresh.
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
        static let refreshEnabled = "menubar.refresh.enabled.v1"
        static let refreshIntervalSeconds = "menubar.refresh.intervalSeconds.v1"
        static let chatGPTFiveHourThresholdPercent = "menubar.refresh.chatGPTFiveHourThresholdPercent.v1"
        static let chatGPTWeeklyThresholdPercent = "menubar.refresh.chatGPTWeeklyThresholdPercent.v1"
        static let deepSeekBalanceThresholdCNY = "menubar.refresh.deepSeekBalanceThresholdCNY.v1"
    }

    public static let defaultRefreshEnabled = true
    public static let defaultRefreshIntervalSeconds = 30
    public static let defaultChatGPTFiveHourThresholdPercent = 50
    public static let defaultChatGPTWeeklyThresholdPercent = 15
    public static let defaultDeepSeekBalanceThresholdCNYText = "15.00"
    public static let supportedRefreshIntervalSeconds = [15, 30, 60]

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

    /// When enabled, only the source currently selected in the menu bar gets an additional
    /// low-usage refresh loop. The ordinary detail-page loops remain unchanged.
    @Published public var lowUsageRefreshEnabled: Bool {
        didSet { defaults.set(lowUsageRefreshEnabled, forKey: Key.refreshEnabled) }
    }

    /// Extra menu-bar polling interval. The picker only offers the documented values; the
    /// setter also normalises hand-edited defaults so an invalid value cannot create a busy
    /// loop or a zero-duration timer.
    @Published public var lowUsageRefreshIntervalSeconds: Int {
        didSet {
            let normalised = Self.normaliseRefreshInterval(lowUsageRefreshIntervalSeconds)
            if normalised != lowUsageRefreshIntervalSeconds {
                lowUsageRefreshIntervalSeconds = normalised
                return
            }
            defaults.set(lowUsageRefreshIntervalSeconds, forKey: Key.refreshIntervalSeconds)
        }
    }

    /// Remaining 5-hour percentage below which the selected ChatGPT profile is accelerated.
    @Published public var chatGPTFiveHourThresholdPercent: Int {
        didSet {
            let normalised = Self.normalisePercent(chatGPTFiveHourThresholdPercent)
            if normalised != chatGPTFiveHourThresholdPercent {
                chatGPTFiveHourThresholdPercent = normalised
                return
            }
            defaults.set(chatGPTFiveHourThresholdPercent, forKey: Key.chatGPTFiveHourThresholdPercent)
        }
    }

    /// Remaining weekly percentage below which the selected ChatGPT profile is accelerated.
    @Published public var chatGPTWeeklyThresholdPercent: Int {
        didSet {
            let normalised = Self.normalisePercent(chatGPTWeeklyThresholdPercent)
            if normalised != chatGPTWeeklyThresholdPercent {
                chatGPTWeeklyThresholdPercent = normalised
                return
            }
            defaults.set(chatGPTWeeklyThresholdPercent, forKey: Key.chatGPTWeeklyThresholdPercent)
        }
    }

    /// Text binding for the settings field. Invalid or negative text is retained for the user
    /// to correct, while the policy treats it as unavailable and therefore fails closed.
    @Published public var deepSeekBalanceThresholdCNYText: String {
        didSet { defaults.set(deepSeekBalanceThresholdCNYText, forKey: Key.deepSeekBalanceThresholdCNY) }
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
        self.lowUsageRefreshEnabled = defaults.object(forKey: Key.refreshEnabled) as? Bool
            ?? Self.defaultRefreshEnabled
        self.lowUsageRefreshIntervalSeconds = Self.normaliseRefreshInterval(
            defaults.object(forKey: Key.refreshIntervalSeconds) as? Int
                ?? Self.defaultRefreshIntervalSeconds)
        self.chatGPTFiveHourThresholdPercent = Self.normalisePercent(
            defaults.object(forKey: Key.chatGPTFiveHourThresholdPercent) as? Int
                ?? Self.defaultChatGPTFiveHourThresholdPercent)
        self.chatGPTWeeklyThresholdPercent = Self.normalisePercent(
            defaults.object(forKey: Key.chatGPTWeeklyThresholdPercent) as? Int
                ?? Self.defaultChatGPTWeeklyThresholdPercent)
        self.deepSeekBalanceThresholdCNYText = defaults.string(forKey: Key.deepSeekBalanceThresholdCNY)
            ?? Self.defaultDeepSeekBalanceThresholdCNYText
    }

    /// Parsed CNY threshold, or nil while the settings field contains invalid input.
    public var deepSeekBalanceThresholdCNY: Decimal? {
        let trimmed = deepSeekBalanceThresholdCNYText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0 else { return nil }
        return value
    }

    public var menuBarRefreshSettings: MenuBarRefreshSettings {
        MenuBarRefreshSettings(
            isEnabled: lowUsageRefreshEnabled,
            intervalSeconds: lowUsageRefreshIntervalSeconds,
            chatGPTFiveHourThresholdPercent: chatGPTFiveHourThresholdPercent,
            chatGPTWeeklyThresholdPercent: chatGPTWeeklyThresholdPercent,
            deepSeekBalanceThresholdCNY: deepSeekBalanceThresholdCNY)
    }

    /// Restores the documented defaults without touching source or currency selection.
    public func resetMenuBarRefreshSettings() {
        lowUsageRefreshEnabled = Self.defaultRefreshEnabled
        lowUsageRefreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
        chatGPTFiveHourThresholdPercent = Self.defaultChatGPTFiveHourThresholdPercent
        chatGPTWeeklyThresholdPercent = Self.defaultChatGPTWeeklyThresholdPercent
        deepSeekBalanceThresholdCNYText = Self.defaultDeepSeekBalanceThresholdCNYText
    }

    private static func normaliseRefreshInterval(_ value: Int) -> Int {
        supportedRefreshIntervalSeconds.min { abs($0 - value) < abs($1 - value) } ?? defaultRefreshIntervalSeconds
    }

    private static func normalisePercent(_ value: Int) -> Int {
        min(max(value, 0), 100)
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

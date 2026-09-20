import Foundation
import UsageMonitorCore

/// Persisted policy inputs for the menu-bar-only low-usage refresh loop.
///
/// This value deliberately contains no account identity, credential or cached provider data.
/// It is a small, pure input object so the threshold rules can be tested without starting
/// timers or touching the network.
public struct MenuBarRefreshSettings: Equatable {
    public let isEnabled: Bool
    public let intervalSeconds: Int
    public let chatGPTFiveHourThresholdPercent: Int
    public let chatGPTWeeklyThresholdPercent: Int
    public let deepSeekBalanceThresholdCNY: Decimal?

    public init(isEnabled: Bool,
                intervalSeconds: Int,
                chatGPTFiveHourThresholdPercent: Int,
                chatGPTWeeklyThresholdPercent: Int,
                deepSeekBalanceThresholdCNY: Decimal?) {
        self.isEnabled = isEnabled
        self.intervalSeconds = intervalSeconds
        self.chatGPTFiveHourThresholdPercent = chatGPTFiveHourThresholdPercent
        self.chatGPTWeeklyThresholdPercent = chatGPTWeeklyThresholdPercent
        self.deepSeekBalanceThresholdCNY = deepSeekBalanceThresholdCNY
    }

    public var interval: TimeInterval { TimeInterval(max(1, intervalSeconds)) }
}

public enum MenuBarRefreshTrigger: Equatable {
    case chatGPTFiveHour
    case chatGPTWeekly
    case deepSeekBalance

    public var displayText: String {
        switch self {
        case .chatGPTFiveHour: return "5 小时额度低于阈值"
        case .chatGPTWeekly: return "周额度低于阈值"
        case .deepSeekBalance: return "DeepSeek 余额低于阈值"
        }
    }
}

public struct MenuBarRefreshDecision: Equatable {
    public let interval: TimeInterval?
    public let trigger: MenuBarRefreshTrigger?

    public init(interval: TimeInterval?, trigger: MenuBarRefreshTrigger?) {
        self.interval = interval
        self.trigger = trigger
    }

    public var isAccelerated: Bool { interval != nil && trigger != nil }
    public static let inactive = MenuBarRefreshDecision(interval: nil, trigger: nil)
}

/// Pure threshold and source-selection rules for the adaptive menu-bar refresh.
public enum MenuBarRefreshPolicy {

    /// The comparison is intentionally strict: exactly 50% or 15% remaining does not enter
    /// the accelerated mode. Unknown windows cannot trigger a refresh.
    public static func chatGPTTrigger(snapshot: UsageSnapshot?,
                                      fiveHourThresholdPercent: Int,
                                      weeklyThresholdPercent: Int) -> MenuBarRefreshTrigger? {
        guard let snapshot else { return nil }
        if let remaining = snapshot.fiveHour?.remainingPercent,
           remaining.isFinite,
           remaining < Double(fiveHourThresholdPercent) {
            return .chatGPTFiveHour
        }
        if let remaining = snapshot.weekly?.remainingPercent,
           remaining.isFinite,
           remaining < Double(weeklyThresholdPercent) {
            return .chatGPTWeekly
        }
        return nil
    }

    /// DeepSeek's menu-bar source is compared only in CNY. If the user explicitly chose USD
    /// (or another reported currency), the CNY threshold is not applied to that display.
    public static func deepSeekTrigger(report: ProviderReport?,
                                       savedCurrency: String?,
                                       thresholdCNY: Decimal?) -> MenuBarRefreshTrigger? {
        guard let report,
              report.connection == .connected || report.connection == .stale,
              let thresholdCNY else { return nil }
        let resolution = DeepSeekMenuBarResolver.resolve(balances: report.balances,
                                                         savedCurrency: savedCurrency)
        guard let currency = resolution.currency,
              currency.caseInsensitiveCompare("CNY") == .orderedSame,
              let amount = resolution.amount,
              amount < thresholdCNY else { return nil }
        return .deepSeekBalance
    }

    /// Returns an additional timer interval only for the selected menu-bar source. The
    /// existing detail refresh interval remains the upper bound, so a user cannot make an
    /// already-near-reset 30-second ChatGPT loop slower by choosing a 60-second acceleration.
    public static func decision(selection: MenuBarPreferences.Selection,
                                profileSnapshot: UsageSnapshot?,
                                deepSeekReport: ProviderReport?,
                                deepSeekCurrency: String?,
                                settings: MenuBarRefreshSettings,
                                normalInterval: TimeInterval) -> MenuBarRefreshDecision {
        guard settings.isEnabled else { return .inactive }

        let trigger: MenuBarRefreshTrigger?
        switch selection {
        case .profile:
            trigger = chatGPTTrigger(snapshot: profileSnapshot,
                                     fiveHourThresholdPercent: settings.chatGPTFiveHourThresholdPercent,
                                     weeklyThresholdPercent: settings.chatGPTWeeklyThresholdPercent)
        case .deepSeek:
            trigger = deepSeekTrigger(report: deepSeekReport,
                                      savedCurrency: deepSeekCurrency,
                                      thresholdCNY: settings.deepSeekBalanceThresholdCNY)
        }

        guard let trigger else { return .inactive }
        return MenuBarRefreshDecision(interval: min(settings.interval, max(1, normalInterval)),
                                      trigger: trigger)
    }
}

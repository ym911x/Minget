import Foundation
import UsageMonitorCore

/// Everything one ChatGPT card renders, derived from that profile's runtime (REQUIREMENTS.md
/// §5.2, IMPLEMENTATION_TASKS.md §4).
///
/// A value type rather than a reference into the runtime: SwiftUI diffing, the layout tests
/// and the card all read the same immutable snapshot, so a card can never render account A's
/// numbers next to account B's label while a fetch is in flight.
public struct CodexProfileViewState: Identifiable, Equatable {

    public let profile: ChatGPTAccountProfile
    public let display: UsageDisplay
    public let connectionState: UsageService.ConnectionState
    /// Identity from `account/read` for this cycle, or nil when it could not be established.
    public let account: CodexAccount?
    public let isRefreshing: Bool
    public let isFiring: Bool
    /// The last fire result, or nil when this profile has not been fired in this session.
    public let fireResult: ChatGPTFireResult?
    /// Forward movement measured by the last finished fire, for the card suffix.
    /// Nil when unconfirmed, unmeasured, or never fired.
    public let fireDriftSeconds: TimeInterval?
    /// Recent finishes, newest first. Memory only, never persisted.
    public let fireHistory: [FireHistoryEntry]

    public init(profile: ChatGPTAccountProfile,
                display: UsageDisplay,
                connectionState: UsageService.ConnectionState,
                account: CodexAccount?,
                isRefreshing: Bool,
                isFiring: Bool,
                fireResult: ChatGPTFireResult?,
                fireDriftSeconds: TimeInterval? = nil,
                fireHistory: [FireHistoryEntry] = []) {
        self.profile = profile
        self.display = display
        self.connectionState = connectionState
        self.account = account
        self.isRefreshing = isRefreshing
        self.isFiring = isFiring
        self.fireResult = fireResult
        self.fireDriftSeconds = fireDriftSeconds
        self.fireHistory = fireHistory
    }

    /// Builds the card state from a runtime value snapshot. One place maps runtime -> view.
    public init(runtime: CodexProfileRuntimeState) {
        self.init(profile: runtime.profile,
                  display: runtime.display,
                  connectionState: runtime.connectionState,
                  account: runtime.account,
                  isRefreshing: runtime.isFetching,
                  isFiring: runtime.isFiring,
                  fireResult: runtime.fireResult,
                  fireDriftSeconds: runtime.fireDriftSeconds,
                  fireHistory: runtime.fireHistory)
    }

    public var id: String { profile.id }
    public var snapshot: UsageSnapshot? { display.snapshot }
    public var isStale: Bool { display.isStale }

    /// Account email for the account row, or nil so the card says 账号暂不可用.
    public var displayEmail: String? { account?.displayEmail }

    /// Package label from the service, preserved verbatim.
    public var displayPlanType: String? { account?.displayPlanType }

    /// Fixed result text and optional drift are separate so the card can protect the result
    /// while truncating the diagnostic suffix first.
    public var fireResultText: String { fireResult?.displayText ?? "" }

    public var fireDriftText: String? {
        guard let fireResult else { return nil }
        switch fireResult {
        case .requestSucceededWindowConfirmed, .requestSucceededWindowUnchanged:
            guard let fireDriftSeconds else { return nil }
            return FireWindowDrift.displayText(fireDriftSeconds)
        case .requestSucceededConfirmationUnavailable, .codexCLINotFound,
             .commandCodeCLINotFound, .credentialUnavailable, .launchFailed,
             .nonZeroExit, .timedOut, .alreadyRunning:
            return nil
        }
    }

    /// Combined wording remains the single accessibility and tooltip value.
    public var fireStatusText: String {
        guard !fireResultText.isEmpty else { return "" }
        guard let fireDriftText else { return fireResultText }
        return "\(fireResultText) · \(fireDriftText)"
    }

    /// Tooltip lines for the recent history, newest first. Empty when never fired.
    public var fireHistoryLines: [String] { fireHistory.map(\.displayLine) }

    /// Fixed connection/cache label (UI_SPEC.md §4.3).
    public var connectionText: String {
        switch display {
        case .live:
            return "已连接"
        case .stale:
            return "缓存数据"
        case .unavailable:
            switch connectionState {
            case .connecting: return "正在获取…"
            case .idle: return "等待更新"
            case .connected: return "已连接"
            case .disconnected: return "未连接"
            }
        }
    }

    /// The one row the card uses for status colour.
    public var isConnectionHealthy: Bool {
        if case .live = display { return true }
        return false
    }

    public var isConnectionCached: Bool { isStale }
}

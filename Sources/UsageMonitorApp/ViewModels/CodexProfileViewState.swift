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

    public init(profile: ChatGPTAccountProfile,
                display: UsageDisplay,
                connectionState: UsageService.ConnectionState,
                account: CodexAccount?,
                isRefreshing: Bool,
                isFiring: Bool,
                fireResult: ChatGPTFireResult?) {
        self.profile = profile
        self.display = display
        self.connectionState = connectionState
        self.account = account
        self.isRefreshing = isRefreshing
        self.isFiring = isFiring
        self.fireResult = fireResult
    }

    /// Builds the card state from a runtime value snapshot. One place maps runtime -> view.
    public init(runtime: CodexProfileRuntimeState) {
        self.init(profile: runtime.profile,
                  display: runtime.display,
                  connectionState: runtime.connectionState,
                  account: runtime.account,
                  isRefreshing: runtime.isFetching,
                  isFiring: runtime.isFiring,
                  fireResult: runtime.fireResult)
    }

    public var id: String { profile.id }
    public var snapshot: UsageSnapshot? { display.snapshot }
    public var isStale: Bool { display.isStale }

    /// Account email for the account row, or nil so the card says 账号暂不可用.
    public var displayEmail: String? { account?.displayEmail }

    /// Package label from the service, preserved verbatim.
    public var displayPlanType: String? { account?.displayPlanType }

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

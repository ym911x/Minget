import Foundation

/// Platforms the app can report on. Codex stays in the menu bar; DeepSeek and GLM are
/// detail-panel-only for this release (v1.1 requirement 7).
public enum ProviderPlatform: String, Codable, CaseIterable, Sendable {
    case codex
    case deepseek
    case glm

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .deepseek: return "DeepSeek"
        case .glm: return "智谱 GLM"
        }
    }
}

/// One provider-reported amount that is neither the total nor the available balance.
/// `field` is the original JSON field name, `label` a fixed display label, so the value
/// keeps the provider's own semantics instead of being bent into another provider's
/// granted/topped-up vocabulary (Round 7 requirement 2).
public struct ProviderLabeledAmount: Equatable, Sendable, Codable {
    public let field: String
    public let label: String
    public let amount: Decimal

    public init(field: String, label: String, amount: Decimal) {
        self.field = field
        self.label = label
        self.amount = amount
    }
}

/// One currency bucket of a balance. Amounts are `Decimal` end to end: money is never
/// routed through `Double`, so no binary rounding can reach the panel.
public struct ProviderBalance: Equatable, Sendable {
    /// ISO-4217 code as reported by the provider (e.g. `CNY`, `USD`). Never localised.
    /// Nil means the response did not name a currency: the panel then says 币种未确认
    /// instead of guessing one (Round 7 requirement 1).
    public let currency: String?
    /// Account funds (`total_balance`). Nil when the response reported only an available
    /// amount: an available balance is never copied into `total` (REVIEW round 7 finding 3).
    public let total: Decimal?
    /// 可用余额 (`available_balance`). Providers that do not report it keep this nil.
    /// The panel prefers this as the main amount when present.
    public let available: Decimal?
    /// `granted_balance` (赠费). Providers that do not report it keep this nil.
    public let granted: Decimal?
    /// `topped_up_balance` (充值). Providers that do not report it keep this nil.
    public let toppedUp: Decimal?
    /// Provider-specific amounts with their own labels (e.g. GLM report's 累计充值,
    /// 累计赠送, 累计消费, 冻结金额). Never mapped onto granted/toppedUp semantics.
    public let additionalAmounts: [ProviderLabeledAmount]?

    public init(currency: String?,
                total: Decimal?,
                available: Decimal? = nil,
                granted: Decimal? = nil,
                toppedUp: Decimal? = nil,
                additionalAmounts: [ProviderLabeledAmount]? = nil) {
        self.currency = currency
        self.total = total
        self.available = available
        self.granted = granted
        self.toppedUp = toppedUp
        self.additionalAmounts = additionalAmounts
    }
}

/// Connection health of a provider. These are the only states the UI is allowed to
/// render, so a failure can never be presented as live data.
public enum ProviderConnectionState: Equatable, Sendable {
    /// No credential stored yet.
    case notConfigured
    /// A fetch is in flight.
    case connecting
    /// The most recent fetch succeeded.
    case connected
    /// The most recent fetch failed but a previous success is on display. Never 0.
    case stale
    /// The most recent fetch failed and there is no previous success.
    case unavailable
    /// Authentication failed (401 / session expired). Automatic retries are paused until
    /// the user reconnects; the panel asks for a reconnect instead of hammering.
    case authSuspended
    /// The provider's endpoint contract could not be confirmed. No balance is shown and
    /// none is invented; the official console entry is offered instead.
    case unverified
}

/// The unified result type every provider maps onto (v1.1 requirement 6).
///
/// The UI depends only on this, never on raw provider JSON, so a field rename is a
/// parser change rather than a UI change. Credentials never appear here.
public struct ProviderReport: Equatable, Sendable {
    public let platform: ProviderPlatform
    /// Account identifier the cache is keyed on (email, or a non-secret key label).
    /// Nil when the account could not be established; nil never means "account unknown".
    public let accountID: String?
    public let balances: [ProviderBalance]
    /// Time of the last *successful* fetch. A stale value stays visible and is labelled.
    public let lastSuccessAt: Date?
    public let connection: ProviderConnectionState
    /// True only when `balances` came from the provider in this refresh cycle.
    public let isLive: Bool
    /// Fixed failure category of the most recent attempt; nil on success.
    public let error: ProviderFailure?
    /// Official console entry, offered when the app cannot or may not read the account.
    public let consoleURL: URL?

    public init(platform: ProviderPlatform,
                accountID: String?,
                balances: [ProviderBalance],
                lastSuccessAt: Date?,
                connection: ProviderConnectionState,
                isLive: Bool,
                error: ProviderFailure?,
                consoleURL: URL?) {
        self.platform = platform
        self.accountID = accountID
        self.balances = balances
        self.lastSuccessAt = lastSuccessAt
        self.connection = connection
        self.isLive = isLive
        self.error = error
        self.consoleURL = consoleURL
    }

    /// Cached form: the same numbers, marked not-live.
    public func markedCached() -> ProviderReport {
        return ProviderReport(platform: platform,
                              accountID: accountID,
                              balances: balances,
                              lastSuccessAt: lastSuccessAt,
                              connection: connection == .connected ? .stale : connection,
                              isLive: false,
                              error: error,
                              consoleURL: consoleURL)
    }
}

/// Stable, non-secret identity of a stored credential. Values never live here.
public enum ProviderCredentialKey: String, CaseIterable, Sendable {
    case deepseekAPIKey = "deepseek.api-key"
    case glmAPIKey = "glm.api-key"
    case glmConsoleSession = "glm.console-session"
}

import Foundation

/// Platforms the app can report on. Codex stays in the menu bar and DeepSeek is optional
/// in the detail panel.
public enum ProviderPlatform: String, Codable, CaseIterable, Sendable {
    case codex
    case deepseek
    case commandcode

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .deepseek: return "DeepSeek"
        case .commandcode: return "Command Code"
        }
    }
}

/// A normalised credit window reported by a provider. Monetary fields retain decimal
/// precision; `remaining` is only populated when the provider supplied both operands.
public struct ProviderUsageWindow: Equatable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable { case fiveHour, weekly, billingPeriod }
    public let kind: Kind
    public let used: Decimal?
    public let limit: Decimal?
    public let remaining: Decimal?
    public let resetsAt: Date?

    public init(kind: Kind, used: Decimal?, limit: Decimal?, remaining: Decimal?, resetsAt: Date?) {
        self.kind = kind; self.used = used; self.limit = limit; self.remaining = remaining; self.resetsAt = resetsAt
    }
}

/// Compact provider usage summary. These values are never converted into balances.
public struct ProviderUsageSummary: Equatable, Sendable, Codable {
    public enum PeriodBasis: String, Codable, Sendable { case billingPeriod, last30Days, unknown }
    public let totalTokens: Int64?
    public let inputTokens: Int64?
    public let outputTokens: Int64?
    public let totalRuns: Int64?
    public let completedRuns: Int64?
    public let failedRuns: Int64?
    public let successRate: Decimal?
    public let totalCostUSD: Decimal?
    public let periodBasis: PeriodBasis

    public init(totalTokens: Int64?, inputTokens: Int64?, outputTokens: Int64?, totalRuns: Int64?, completedRuns: Int64?, failedRuns: Int64?, successRate: Decimal?, totalCostUSD: Decimal?, periodBasis: PeriodBasis) {
        self.totalTokens = totalTokens; self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.totalRuns = totalRuns; self.completedRuns = completedRuns; self.failedRuns = failedRuns
        self.successRate = successRate; self.totalCostUSD = totalCostUSD; self.periodBasis = periodBasis
    }
}

/// Freshness of one optional provider component. The required quota source has its own
/// report-level state; this metadata prevents a reused enrichment payload from being
/// presented as if it arrived with the current credits request.
public struct ProviderUsageComponentFreshness: Equatable, Sendable, Codable {
    public let lastSuccessfulAt: Date
    public let isLive: Bool

    public init(lastSuccessfulAt: Date, isLive: Bool) {
        self.lastSuccessfulAt = lastSuccessfulAt
        self.isLive = isLive
    }

    public var isCached: Bool { !isLive }
}

public struct ProviderUsage: Equatable, Sendable, Codable {
    public let windows: [ProviderUsageWindow]
    public let summary: ProviderUsageSummary?
    public let planName: String?
    public let billingPeriodEnd: Date?
    /// Billing-cycle start. Only populated when the service actually reported it, so the
    /// monthly progress line can refuse to draw instead of assuming a 30-day month
    /// (REVISION_SPEC.md §7.3).
    public let billingPeriodStart: Date?
    /// Optional for backward-compatible decoding of provider cache entries written before
    /// 1.3.2 component-level freshness existed.
    public let summaryFreshness: ProviderUsageComponentFreshness?
    public let subscriptionFreshness: ProviderUsageComponentFreshness?
    public init(windows: [ProviderUsageWindow], summary: ProviderUsageSummary?, planName: String? = nil,
                billingPeriodEnd: Date? = nil, billingPeriodStart: Date? = nil,
                summaryFreshness: ProviderUsageComponentFreshness? = nil,
                subscriptionFreshness: ProviderUsageComponentFreshness? = nil) {
        self.windows = windows; self.summary = summary; self.planName = planName
        self.billingPeriodEnd = billingPeriodEnd; self.billingPeriodStart = billingPeriodStart
        self.summaryFreshness = summaryFreshness
        self.subscriptionFreshness = subscriptionFreshness
    }
}

public extension ProviderUsageWindow {
    /// Remaining credit for this window: the service's own `remaining` when it supplied one,
    /// otherwise `limit - used`. Nil when neither can be derived, so a caller never prints a
    /// fabricated zero.
    var effectiveRemaining: Decimal? {
        if let remaining { return remaining }
        guard let used, let limit else { return nil }
        return limit - used
    }

    /// Fraction of the window still remaining, in `0...1`, or nil when it cannot be computed
    /// from real values. REVISION_SPEC.md §7.2: the track shows *remaining*, so the bright
    /// region shrinks from the right as credit is consumed.
    var remainingFraction: Double? {
        guard let limit, limit > 0, let remaining = effectiveRemaining else { return nil }
        let clamped = min(max(remaining, 0), limit)
        return NSDecimalNumber(decimal: clamped / limit).doubleValue
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
    /// Provider-specific amounts with their own labels. Never mapped onto granted/toppedUp
    /// semantics.
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
    /// The credential is stored, but reading it needs the user's decision in the system
    /// dialog (or the user declined). Distinct from `notConfigured` on purpose: telling a
    /// user to enter a key they already entered is wrong. Automatic work stays paused until
    /// the user asks for the read (KEYCHAIN_REVISION_PLAN.md P1.4).
    case needsAuthorization
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
    /// Optional quota and statistics data. DeepSeek currently leaves this absent.
    public let usage: ProviderUsage?
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
                usage: ProviderUsage? = nil,
                lastSuccessAt: Date?,
                connection: ProviderConnectionState,
                isLive: Bool,
                error: ProviderFailure?,
                consoleURL: URL?) {
        self.platform = platform
        self.accountID = accountID
        self.balances = balances
        self.usage = usage
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
                              usage: usage,
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
    case commandCodeAPIKey = "commandcode.api-key"
}

/// What a reader knows about its own credential, from memory only.
///
/// This is what `init`, `report` and every status query are allowed to consult: answering
/// "do I have a credential?" must never itself touch the keychain
/// (KEYCHAIN_REVISION_PLAN.md P1.3). The keychain is read once, on a background pass, and
/// the result is remembered here.
public enum ProviderCredentialState: Equatable, Sendable {
    /// Nothing read yet in this process. Transient: the startup pass fills it in.
    case unknown
    case configured
    /// Confirmed absent.
    case missing
    /// Present but unreadable without the user's decision, or the user declined.
    case needsAuthorization
    /// The read failed for another reason.
    case unavailable
}

public extension ProviderCredentialState {
    var isConfigured: Bool { self == .configured }

    /// Maps one credential's phase onto the reader-level state. The two enums are separate
    /// because a reader may own more than one credential: the rule for combining them
    /// belongs to the reader, while the per-credential truth belongs to the coordinator.
    init(phase: ProviderCredentialPhase) {
        switch phase {
        case .unknown: self = .unknown
        case .available: self = .configured
        case .missing: self = .missing
        case .needsAuthorization: self = .needsAuthorization
        case .unavailable: self = .unavailable
        }
    }
}

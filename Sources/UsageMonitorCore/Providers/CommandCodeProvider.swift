import Foundation
import CryptoKit

/// Read-only Command Code usage client. The `/alpha` billing responses are not a
/// documented public contract, so unknown or malformed fields fail closed.
public struct CommandCodeProvider: Sendable {
    public static let apiBaseURL = URL(string: "https://api.commandcode.ai")!
    public static let creditsPath = "/alpha/billing/credits"
    public static let summaryPath = "/alpha/usage/summary"
    public static let subscriptionsPath = "/alpha/billing/subscriptions"
    public static let allowedPaths: Set<String> = [creditsPath, summaryPath, subscriptionsPath]
    /// Automatic refresh reuses the last auxiliary payloads inside this window and only
    /// re-reads credits. Manual refreshes and reconnects bypass it.
    public static let auxiliaryReuseInterval: TimeInterval = 15 * 60

    /// Whether the auxiliary enrichment may be reused instead of re-read.
    public enum AuxiliaryPolicy: Equatable, Sendable {
        case automatic
        case force
    }

    public let client: ProviderHTTPClient
    private let auxiliaryCache: AuxiliaryCache?

    fileprivate typealias SummaryPayload = (summary: ProviderUsageSummary, monthlyUsed: Decimal?)
    fileprivate typealias SubscriptionPayload = (planName: String?, periodStart: Date?, periodEnd: Date?)

    /// Shared in-process cache for the auxiliary payloads, so consecutive automatic
    /// refreshes in one process do not re-read what rarely changes. Memory only.
    public final class AuxiliaryCache: @unchecked Sendable {
        private struct SummaryEntry {
            var value: SummaryPayload
            var lastSuccessfulAt: Date
            var retryRequired = false
        }
        private struct SubscriptionEntry {
            var value: SubscriptionPayload
            var lastSuccessfulAt: Date
            var retryRequired = false
        }
        private struct Entry {
            var summary: SummaryEntry?
            var subscription: SubscriptionEntry?
        }

        private let lock = NSLock()
        /// Keyed by the full SHA-256 digest, never by the short account label and never by
        /// the credential itself. Concurrent reads for different generations cannot replace
        /// or consume each other's auxiliary payloads.
        private var entries: [String: Entry] = [:]
        var now: () -> Date = Date.init

        public init() {}

        fileprivate func summary(for key: String, now: Date) -> (value: SummaryPayload, lastSuccessfulAt: Date, reusable: Bool)? {
            lock.lock(); defer { lock.unlock() }
            guard let stored = entries[key]?.summary else { return nil }
            let age = now.timeIntervalSince(stored.lastSuccessfulAt)
            let reusable = !stored.retryRequired
                && age >= 0
                && age < CommandCodeProvider.auxiliaryReuseInterval
            return (stored.value, stored.lastSuccessfulAt, reusable)
        }

        fileprivate func subscription(for key: String, now: Date) -> (value: SubscriptionPayload, lastSuccessfulAt: Date, reusable: Bool)? {
            lock.lock(); defer { lock.unlock() }
            guard let stored = entries[key]?.subscription else { return nil }
            let age = now.timeIntervalSince(stored.lastSuccessfulAt)
            let reusable = !stored.retryRequired
                && age >= 0
                && age < CommandCodeProvider.auxiliaryReuseInterval
            return (stored.value, stored.lastSuccessfulAt, reusable)
        }

        fileprivate func storeSummary(_ value: SummaryPayload, for key: String, at date: Date) {
            lock.lock(); defer { lock.unlock() }
            var entry = entries[key] ?? Entry()
            entry.summary = SummaryEntry(value: value, lastSuccessfulAt: date)
            entries[key] = entry
        }

        fileprivate func storeSubscription(_ value: SubscriptionPayload, for key: String, at date: Date) {
            lock.lock(); defer { lock.unlock() }
            var entry = entries[key] ?? Entry()
            entry.subscription = SubscriptionEntry(value: value, lastSuccessfulAt: date)
            entries[key] = entry
        }

        func markSummaryFailure(for key: String) {
            lock.lock(); defer { lock.unlock() }
            guard var entry = entries[key], var summary = entry.summary else { return }
            summary.retryRequired = true
            entry.summary = summary
            entries[key] = entry
        }

        func markSubscriptionFailure(for key: String) {
            lock.lock(); defer { lock.unlock() }
            guard var entry = entries[key], var subscription = entry.subscription else { return }
            subscription.retryRequired = true
            entry.subscription = subscription
            entries[key] = entry
        }
    }

    public init(transport: ProviderTransport, auxiliaryCache: AuxiliaryCache? = AuxiliaryCache()) {
        client = ProviderHTTPClient(baseURL: Self.apiBaseURL, allowedPaths: Self.allowedPaths,
                                    transport: transport, defaultHeaders: ["Accept": "application/json"])
        self.auxiliaryCache = auxiliaryCache
    }

    public static func accountFingerprint(forAPIKey key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    private static func auxiliaryCacheKey(forAPIKey key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func fetchUsage(apiKey: String, timeout: TimeInterval = 15,
                           auxiliaryPolicy: AuxiliaryPolicy = .automatic) async throws -> ProviderUsage {
        guard !apiKey.isEmpty else { throw ProviderFailure.notConfigured }
        let headers = ["Authorization": "Bearer \(apiKey)"]
        let now = auxiliaryCache?.now() ?? Date()
        let cacheKey = Self.auxiliaryCacheKey(forAPIKey: apiKey)
        let cachedSummary = auxiliaryCache?.summary(for: cacheKey, now: now)
        let cachedSubscription = auxiliaryCache?.subscription(for: cacheKey, now: now)
        let fetchSummary = auxiliaryPolicy == .force || cachedSummary?.reusable != true
        let fetchSubscription = auxiliaryPolicy == .force || cachedSubscription?.reusable != true

        async let creditsResponse = request(path: Self.creditsPath, headers: headers, timeout: timeout)
        let summaryTask: Task<SummaryPayload?, Never>? = fetchSummary ? Task {
            guard let response = try? await request(path: Self.summaryPath, headers: headers, timeout: timeout) else { return nil }
            return try? parseSummary(response)
        } : nil
        let subscriptionTask: Task<SubscriptionPayload?, Never>? = fetchSubscription ? Task {
            guard let response = try? await request(path: Self.subscriptionsPath, headers: headers, timeout: timeout) else { return nil }
            return try? parseSubscription(response)
        } : nil
        // Credits is the only required source: its own error must surface, never be folded into
        // a missing statistic (REQUIREMENTS.md §5.1).
        let credits = try await parseCredits(creditsResponse)

        let freshSummary = await summaryTask?.value
        let summary: SummaryPayload?
        let summaryFreshness: ProviderUsageComponentFreshness?
        if fetchSummary, let freshSummary {
            auxiliaryCache?.storeSummary(freshSummary, for: cacheKey, at: now)
            summary = freshSummary
            summaryFreshness = ProviderUsageComponentFreshness(lastSuccessfulAt: now, isLive: true)
        } else if fetchSummary {
            auxiliaryCache?.markSummaryFailure(for: cacheKey)
            summary = cachedSummary?.value
            summaryFreshness = cachedSummary.map {
                ProviderUsageComponentFreshness(lastSuccessfulAt: $0.lastSuccessfulAt, isLive: false)
            }
        } else {
            summary = cachedSummary?.value
            summaryFreshness = cachedSummary.map {
                ProviderUsageComponentFreshness(lastSuccessfulAt: $0.lastSuccessfulAt, isLive: false)
            }
        }

        let freshSubscription = await subscriptionTask?.value
        let subscription: SubscriptionPayload?
        let subscriptionFreshness: ProviderUsageComponentFreshness?
        if fetchSubscription, let freshSubscription {
            auxiliaryCache?.storeSubscription(freshSubscription, for: cacheKey, at: now)
            subscription = freshSubscription
            subscriptionFreshness = ProviderUsageComponentFreshness(lastSuccessfulAt: now, isLive: true)
        } else if fetchSubscription {
            auxiliaryCache?.markSubscriptionFailure(for: cacheKey)
            subscription = cachedSubscription?.value
            subscriptionFreshness = cachedSubscription.map {
                ProviderUsageComponentFreshness(lastSuccessfulAt: $0.lastSuccessfulAt, isLive: false)
            }
        } else {
            subscription = cachedSubscription?.value
            subscriptionFreshness = cachedSubscription.map {
                ProviderUsageComponentFreshness(lastSuccessfulAt: $0.lastSuccessfulAt, isLive: false)
            }
        }

        return compose(credits: credits,
                       summary: summary,
                       subscription: subscription,
                       summaryFreshness: summaryFreshness,
                       subscriptionFreshness: subscriptionFreshness)
    }

    /// Fire confirmation needs only the live five-hour reset point. It deliberately skips
    /// summary and subscription so a single confirmation never fans out to three requests.
    public func fetchFiveHourReset(apiKey: String, timeout: TimeInterval = 15) async throws -> Date? {
        guard !apiKey.isEmpty else { throw ProviderFailure.notConfigured }
        let response = try await request(path: Self.creditsPath,
                                         headers: ["Authorization": "Bearer \(apiKey)"],
                                         timeout: timeout)
        return try parseCredits(response).windows.first { $0.kind == .fiveHour }?.resetsAt
    }

    private func compose(credits: (windows: [ProviderUsageWindow], monthlyRemaining: Decimal?),
                         summary: SummaryPayload?,
                         subscription: SubscriptionPayload?,
                         summaryFreshness: ProviderUsageComponentFreshness?,
                         subscriptionFreshness: ProviderUsageComponentFreshness?) -> ProviderUsage {
        var windows = credits.windows
        // The monthly row is composed only from fields that really arrived: with a credits
        // balance but no summary, `remaining` is kept and `used`/`limit` stay absent rather
        // than being back-filled with an assumed total (REQUIREMENTS.md §5.2).
        let monthlyUsed = summary?.monthlyUsed
        if monthlyUsed != nil || credits.monthlyRemaining != nil {
            let limit = monthlyUsed.flatMap { used in credits.monthlyRemaining.map { used + $0 } }
            windows.append(ProviderUsageWindow(kind: .billingPeriod, used: monthlyUsed,
                                               limit: limit, remaining: credits.monthlyRemaining,
                                               resetsAt: nil))
        }
        return ProviderUsage(windows: windows, summary: summary?.summary,
                             planName: subscription?.planName,
                             billingPeriodEnd: subscription?.periodEnd,
                             billingPeriodStart: subscription?.periodStart,
                             summaryFreshness: summaryFreshness,
                             subscriptionFreshness: subscriptionFreshness)
    }

    private func request(path: String, headers: [String: String], timeout: TimeInterval) async throws -> ProviderHTTPResponse {
        do {
            return try await client.get(path: path, headers: headers, timeout: timeout)
        } catch let error as ProviderTransportError { throw ProviderFailure.from(error) }
    }

    private func parseCredits(_ response: ProviderHTTPResponse) throws -> (windows: [ProviderUsageWindow], monthlyRemaining: Decimal?) {
        try validResponse(response)
        guard let root = json(response.body), let credits = root["credits"] as? [String: Any] else {
            throw ProviderFailure.structureUnsupported
        }
        let limits = (root["windowLimits"] as? [String: Any]) ?? (credits["windowLimits"] as? [String: Any])
        var windows: [ProviderUsageWindow] = []
        if let fiveHour = window(limits?["fiveHour"], kind: .fiveHour) { windows.append(fiveHour) }
        if let weekly = window(limits?["weekly"], kind: .weekly) { windows.append(weekly) }
        guard !windows.isEmpty else { throw ProviderFailure.structureUnsupported }
        let remaining = decimal(credits["monthlyCredits"])
        return (windows, remaining)
    }

    private func parseSummary(_ response: ProviderHTTPResponse) throws -> (summary: ProviderUsageSummary, monthlyUsed: Decimal?) {
        try validResponse(response)
        guard let root = json(response.body) else { throw ProviderFailure.structureUnsupported }
        let totalTokens = integer64(root["totalTokens"])
        let totalRuns = integer64(root["totalCount"])
        guard totalTokens != nil || totalRuns != nil else { throw ProviderFailure.structureUnsupported }
        let rawBasis = (root["periodBasis"] as? String)?.lowercased()
        let basis: ProviderUsageSummary.PeriodBasis
        switch rawBasis { case "billing-period", "billingperiod": basis = .billingPeriod
        case "last-30-days", "last30days": basis = .last30Days
        default: basis = .unknown }
        let summary = ProviderUsageSummary(totalTokens: totalTokens, inputTokens: integer64(root["totalTokensIn"]),
                                    outputTokens: integer64(root["totalTokensOut"]), totalRuns: totalRuns,
                                    completedRuns: integer64(root["completedCount"]), failedRuns: integer64(root["failedCount"]),
                                    successRate: nonNegativeDecimal(root["successRate"]), totalCostUSD: nonNegativeDecimal(root["totalCost"]),
                                    periodBasis: basis)
        return (summary, nonNegativeDecimal(root["totalMonthlyCredits"]))
    }

    /// Reads the optional subscription enrichment.
    ///
    /// `currentPeriodStart` is only returned when the response actually carries it: the
    /// monthly progress line refuses to draw without a real start, so a missing field must
    /// stay missing rather than be back-filled with an assumed cycle (REVISION_SPEC.md §7.3).
    /// A start that is not strictly before the end is discarded as unusable.
    private func parseSubscription(_ response: ProviderHTTPResponse) throws -> (planName: String?, periodStart: Date?, periodEnd: Date?) {
        try validResponse(response)
        guard let root = json(response.body), root["success"] as? Bool == true else { throw ProviderFailure.structureUnsupported }
        guard let data = root["data"] else { throw ProviderFailure.structureUnsupported }
        if data is NSNull { return (nil, nil, nil) }
        guard let object = data as? [String: Any] else { throw ProviderFailure.structureUnsupported }
        let start = date(object["currentPeriodStart"])
        let end = date(object["currentPeriodEnd"])
        let usableStart: Date?
        if let start, let end, start < end {
            usableStart = start
        } else {
            usableStart = nil
        }
        return (object["planId"] as? String, usableStart, end)
    }

    private func validResponse(_ response: ProviderHTTPResponse) throws {
        guard response.isOK else {
            if response.status == 401 || response.status == 403 { throw ProviderFailure.invalidCredential }
            throw ProviderFailure.serverError(status: response.status)
        }
    }
    private func json(_ data: Data) -> [String: Any]? { try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
    private func decimal(_ value: Any?) -> Decimal? { SafeConversion.decimal(value) }
    private func nonNegativeDecimal(_ value: Any?) -> Decimal? { guard let value = decimal(value), value >= 0 else { return nil }; return value }
    private func integer64(_ value: Any?) -> Int64? {
        guard let number = SafeConversion.integer(value), number >= 0 else { return nil }
        return Int64(number)
    }
    private func date(_ value: Any?) -> Date? {
        if let seconds = SafeConversion.double(value), seconds > 0 { return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds) }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    private func window(_ value: Any?, kind: ProviderUsageWindow.Kind) -> ProviderUsageWindow? {
        guard let object = value as? [String: Any], let cap = nonNegativeDecimal(object["cap"]), cap > 0 else { return nil }
        let used = nonNegativeDecimal(object["used"])
        let remaining = used.map { max(Decimal.zero, cap - $0) }
        return ProviderUsageWindow(kind: kind, used: used, limit: cap, remaining: remaining, resetsAt: date(object["resetAt"]))
    }
}

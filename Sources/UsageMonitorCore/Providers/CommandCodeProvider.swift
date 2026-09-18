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

    public let client: ProviderHTTPClient

    public init(transport: ProviderTransport) {
        client = ProviderHTTPClient(baseURL: Self.apiBaseURL, allowedPaths: Self.allowedPaths,
                                    transport: transport, defaultHeaders: ["Accept": "application/json"])
    }

    public static func accountFingerprint(forAPIKey key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    public func fetchUsage(apiKey: String, timeout: TimeInterval = 15) async throws -> ProviderUsage {
        guard !apiKey.isEmpty else { throw ProviderFailure.notConfigured }
        let headers = ["Authorization": "Bearer \(apiKey)"]
        async let creditsResponse = request(path: Self.creditsPath, headers: headers, timeout: timeout)
        async let summaryResponse = request(path: Self.summaryPath, headers: headers, timeout: timeout)
        async let subscriptionResponse = request(path: Self.subscriptionsPath, headers: headers, timeout: timeout)
        // Credits is the only required source: its own error must surface, never be folded into
        // a missing statistic (REQUIREMENTS.md §5.1).
        let credits = try await parseCredits(creditsResponse)
        // Summary is enrichment. A network error, a 5xx, a 401/403, malformed JSON or a field
        // change leaves `summary == nil` — the statistics area says so explicitly — while the
        // credits-derived windows above stay live. The credential state is decided by credits
        // alone, so an auxiliary 401/403 does not suspend the connection.
        let summary = try? await parseSummary(summaryResponse)
        // Subscription is enrichment only. It must not hide valid credits and statistics.
        let subscription = try? await parseSubscription(subscriptionResponse)
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
                             billingPeriodStart: subscription?.periodStart)
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

import Foundation
import CoreFoundation

/// Only normalized, non-secret account and quota metadata can be persisted.
public struct AntigravityAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let authIndex: String
    public let label: String
    public let email: String?
    public let projectID: String?
    public let disabled: Bool
    public let unavailable: Bool
    public var identity: String { [id, email ?? "", projectID ?? ""].joined(separator: "#") }
}

public struct AntigravityQuotaBucket: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let window: String?
    public let remainingFraction: Double?
    public let resetsAt: Date?

    public var kind: RateLimitWindow.Kind {
        switch window?.lowercased() {
        case "5h", "five-hour", "five_hour", "fivehour": return .fiveHour
        case "7d", "weekly", "week", "seven-day", "seven_day": return .weekly
        default: return .unknown
        }
    }
    public var percentageText: String {
        guard let remainingFraction else { return "额度未知" }
        return String(format: "%.2f%%", remainingFraction * 100)
    }
    public func resetText(now: Date = Date()) -> String {
        guard let resetsAt else { return "重置时间未知" }
        if resetsAt <= now { return "已到重置时间，等待刷新" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "重置 " + formatter.string(from: resetsAt)
    }
    public var rateLimitWindow: RateLimitWindow? {
        guard let fraction = remainingFraction, kind != .unknown else { return nil }
        return RateLimitWindow(kind: kind,
                               windowDurationMinutes: kind == .fiveHour ? 300 : 10080,
                               usedPercent: (1 - fraction) * 100,
                               remainingPercent: fraction * 100, resetsAt: resetsAt)
    }
}

public struct AntigravityQuotaGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let models: [String]
    public let buckets: [AntigravityQuotaBucket]
}

public struct AntigravitySnapshot: Codable, Equatable, Sendable {
    public let accountIdentity: String
    public let groups: [AntigravityQuotaGroup]
    public let fetchedAt: Date
}

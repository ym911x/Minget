import Foundation

/// One rate limit window as reported by `account/rateLimits/read`.
///
/// Classification is always derived from `windowDurationMins`, never from the
/// `primary` / `secondary` key names (PROJECT_SPEC.md §4.1).
public struct RateLimitWindow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case fiveHour
        case weekly
        case unknown
    }

    public let kind: Kind
    /// Raw `windowDurationMins` from the server. Kept for diagnostics when `kind == .unknown`.
    public let windowDurationMinutes: Int
    /// Used percent exactly as reported (may be out of 0...100; never presented to the UI raw).
    public let usedPercent: Double
    /// `max(0, min(100, 100 - usedPercent))`.
    public let remainingPercent: Double
    /// Local time the window resets, or nil when absent/unparseable/past.
    public let resetsAt: Date?

    public init(kind: Kind, windowDurationMinutes: Int, usedPercent: Double, remainingPercent: Double, resetsAt: Date?) {
        self.kind = kind
        self.windowDurationMinutes = windowDurationMinutes
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }

    /// 300 minutes = 5 hours.
    public static let fiveHourDurationMinutes = 300
    /// 10080 minutes = 7 days.
    public static let weeklyDurationMinutes = 10080

    /// Duration -> kind mapping. Unknown durations map to `.unknown` and are preserved for diagnostics.
    public static func kind(forWindowDurationMinutes minutes: Int) -> Kind {
        switch minutes {
        case RateLimitWindow.fiveHourDurationMinutes: return .fiveHour
        case RateLimitWindow.weeklyDurationMinutes: return .weekly
        default: return .unknown
        }
    }

    /// Clamp remaining percent into 0...100.
    public static func remainingPercent(fromUsedPercent usedPercent: Double) -> Double {
        return max(0, min(100, 100 - usedPercent))
    }
}

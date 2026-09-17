import Foundation

/// Remaining time in a provider-reported window, reduced to what a track can draw.
///
/// The Codex side uses `ResetTimeProgress`; providers report differently shaped windows, so
/// the monthly billing cycle needs a continuous bar, and a cycle whose start the service did
/// not report must stay undrawable rather than be assumed at 30 days
/// (REVISION_SPEC.md §7.3). Everything here is a pure function of an explicit `now`.
public enum ProviderTimeProgress: Equatable, Sendable {

    /// One fill per segment, left to right, each in `0...1`.
    case segments([Double])
    /// A single continuous fill in `0...1` (the monthly billing cycle).
    case continuous(Double)
    /// The reported end has been reached; the app waits for the service.
    case arrived
    /// No usable time information: a neutral track with a `?`, never a pretend zero.
    case unavailable

    public var segmentCount: Int {
        if case .segments(let fills) = self { return fills.count }
        return 0
    }

    public var isUnavailable: Bool { self == .unavailable }
}

/// Builds `ProviderTimeProgress` from a provider window. Pure; safe to call on every frame.
public enum ProviderTimeModel {

    public static let fiveHourSegmentCount = 5
    public static let weeklySegmentCount = 7

    /// Segments drawn for a window kind. The monthly cycle is continuous, so it has none.
    public static func segmentCount(for kind: ProviderUsageWindow.Kind) -> Int {
        switch kind {
        case .fiveHour: return fiveHourSegmentCount
        case .weekly: return weeklySegmentCount
        case .billingPeriod: return 0
        }
    }

    /// Length used to normalise a segmented window. The monthly cycle has no fixed length.
    public static func periodSeconds(for kind: ProviderUsageWindow.Kind) -> TimeInterval? {
        switch kind {
        case .fiveHour: return 5 * 3600
        case .weekly: return 7 * 24 * 3600
        case .billingPeriod: return nil
        }
    }

    public struct Outcome: Equatable, Sendable {
        public let progress: ProviderTimeProgress
        /// Seconds until the reported end, or nil when there is nothing to count down.
        public let remainingSeconds: TimeInterval?

        public init(progress: ProviderTimeProgress, remainingSeconds: TimeInterval?) {
            self.progress = progress
            self.remainingSeconds = remainingSeconds
        }
    }

    /// - Parameters:
    ///   - kind: which window row is being drawn, which fixes the segment count.
    ///   - window: the window from the current report, or nil when the service omitted it.
    ///   - billingPeriodStart/End: the monthly cycle, only used for `.billingPeriod`.
    public static func progress(kind: ProviderUsageWindow.Kind,
                                window: ProviderUsageWindow?,
                                billingPeriodStart: Date?,
                                billingPeriodEnd: Date?,
                                now: Date) -> Outcome {
        switch kind {
        case .fiveHour, .weekly:
            guard let period = periodSeconds(for: kind), let resetsAt = window?.resetsAt else {
                return Outcome(progress: .unavailable, remainingSeconds: nil)
            }
            let remaining = resetsAt.timeIntervalSince(now)
            guard remaining.isFinite else { return Outcome(progress: .unavailable, remainingSeconds: nil) }
            guard remaining > 0 else { return Outcome(progress: .arrived, remainingSeconds: nil) }

            let count = segmentCount(for: kind)
            let clamped = min(remaining, period)
            let secondsPerSegment = period / Double(count)
            let units = clamped / secondsPerSegment
            let fills = (0..<count).map { min(max(units - Double($0), 0), 1) }
            return Outcome(progress: .segments(fills), remainingSeconds: clamped)

        case .billingPeriod:
            // A monthly bar needs both ends of the cycle from the service. Without a real
            // start there is no honest fraction to draw, so nothing is drawn.
            guard let start = billingPeriodStart, let end = billingPeriodEnd, start < end else {
                return Outcome(progress: .unavailable, remainingSeconds: nil)
            }
            let remaining = end.timeIntervalSince(now)
            guard remaining.isFinite else { return Outcome(progress: .unavailable, remainingSeconds: nil) }
            guard remaining > 0 else { return Outcome(progress: .arrived, remainingSeconds: nil) }

            let total = end.timeIntervalSince(start)
            let clamped = min(remaining, total)
            return Outcome(progress: .continuous(min(max(clamped / total, 0), 1)),
                           remainingSeconds: clamped)
        }
    }
}

/// Fixed-wording durations for the provider time rows. Rounded down, so a remaining minute
/// never reads as a whole hour.
public enum ProviderTimeFormatting {

    /// `2小时13分` / `45分` / `不到1分`.
    public static func remainingText(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "不到1分" }
        let wholeMinutes = Int(seconds / 60)
        if wholeMinutes < 1 { return "不到1分" }
        let hours = wholeMinutes / 60
        let minutes = wholeMinutes % 60
        if hours == 0 { return "\(minutes)分" }
        if minutes == 0 { return "\(hours)小时" }
        return "\(hours)小时\(minutes)分"
    }

    /// `12天` for a monthly cycle; below a day it falls back to the hours-and-minutes form.
    public static func dayText(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "不到1天" }
        let days = Int(seconds / 86_400)
        if days >= 1 { return "\(days)天" }
        return remainingText(seconds)
    }
}

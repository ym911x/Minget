import Foundation

/// Remaining time until a rate-limit window resets, expressed as the per-segment fill of a
/// segmented bar.
///
/// v1.0.2 requirement 3: the menu bar draws two rows of thin segments below the quota text.
/// The upper row has one segment per hour of the five-hour window, the lower row one segment
/// per day of the weekly window. The bright region recedes from right to left as the window
/// drains, and the last bright pixel is consumed at the left edge.
///
/// Everything here is a pure function of an explicit `now`: no SwiftUI, no timers, no
/// network. `ResetTimeModel.progress` is the only way to build a value, so the display can
/// never advance the bar by accumulating its own ticks.
public struct ResetTimeProgress: Equatable, Sendable {

    /// What the row may say about the reset time. The bar itself cannot distinguish
    /// "unknown" from "already reset", so the state carries that difference.
    public enum State: Equatable, Sendable {
        /// A usable future reset time inside the window; `fills` is a real countdown.
        case active
        /// The reported reset time has been reached. Every segment is empty and the app
        /// waits for a real refresh: it never refills by itself.
        case arrived
        /// The window is missing, or its reset time is absent.
        case unknown
        /// Inputs that must not be drawn as a countdown: a duration that does not match the
        /// target window, a non-finite date, or a reset time further out than the window
        /// itself allows.
        case invalid

        /// True when the row should tell the user that the app is waiting for a refresh.
        public var isAwaitingRefresh: Bool { self == .arrived }
    }

    public let state: State
    /// Left-to-right fill fraction of each segment, each in `0...1`. Segment 0 is the
    /// visually leftmost one. `fills.count` is the window's segment count (5 or 7); it is 0
    /// only when the target window kind has no bar at all.
    public let fills: [Double]
    /// Seconds left until the reset, or nil when the state is not `.active`.
    public let remainingSeconds: TimeInterval?

    public init(state: State, fills: [Double], remainingSeconds: TimeInterval? = nil) {
        self.state = state
        self.fills = fills
        self.remainingSeconds = remainingSeconds
    }

    public var segmentCount: Int { fills.count }

    /// A row that shows nothing bright. Both `.arrived` and `.unknown`/`.invalid` can be
    /// empty; only the state tells them apart.
    public var hasNoBrightSegment: Bool { fills.allSatisfy { $0 <= 0 } }

    /// Fraction of the whole row that is bright, for tests and accessibility. Segment gaps
    /// are not part of the time fraction, so this is a segment average.
    public var averageFill: Double {
        guard !fills.isEmpty else { return 0 }
        return fills.reduce(0, +) / Double(fills.count)
    }
}

/// Builds `ResetTimeProgress` values. Pure; safe to call on every frame.
public enum ResetTimeModel {

    /// Defense-in-depth display tolerance, not a service-protocol fact (v1.0.2 §4.3):
    /// a reset time at most this far beyond the window's own length is treated as clock or
    /// service skew and clamped to a full bar. Anything further out is `.invalid` rather
    /// than a bar that pretends to be full forever.
    public static let clockTolerance: TimeInterval = 60

    /// One segment per hour of the five-hour window.
    public static let fiveHourSegmentCount = 5
    /// One segment per day of the weekly window (v1.0.2 §1.3: 7 segments, 1 day each).
    public static let weeklySegmentCount = 7

    /// Segment count for a window kind. `.unknown` has no bar (v1.0.2 §4.1).
    public static func segmentCount(for kind: RateLimitWindow.Kind) -> Int {
        switch kind {
        case .fiveHour: return fiveHourSegmentCount
        case .weekly: return weeklySegmentCount
        case .unknown: return 0
        }
    }

    /// Window length in seconds. nil for `.unknown`.
    public static func totalSeconds(for kind: RateLimitWindow.Kind) -> TimeInterval? {
        switch kind {
        case .fiveHour: return 5 * 3600
        case .weekly: return 7 * 24 * 3600
        case .unknown: return nil
        }
    }

    /// Expected `windowDurationMins` for a kind, used to reject a mismatched window instead
    /// of silently normalising it (v1.0.2 §4.3).
    public static func expectedDurationMinutes(for kind: RateLimitWindow.Kind) -> Int? {
        switch kind {
        case .fiveHour: return RateLimitWindow.fiveHourDurationMinutes
        case .weekly: return RateLimitWindow.weeklyDurationMinutes
        case .unknown: return nil
        }
    }

    /// The countdown for one window.
    ///
    /// - Parameters:
    ///   - kind: the row being drawn, which fixes the segment count and the window length.
    ///   - window: the window from the current snapshot, or nil when it is missing.
    ///   - now: the single clock reading shared by both rows for this frame.
    public static func progress(expected kind: RateLimitWindow.Kind,
                                window: RateLimitWindow?,
                                now: Date) -> ResetTimeProgress {
        let count = segmentCount(for: kind)
        guard count > 0, let total = totalSeconds(for: kind), let expectedMinutes = expectedDurationMinutes(for: kind) else {
            // No bar exists for this kind at all: not a displayable countdown.
            return ResetTimeProgress(state: .invalid, fills: [])
        }
        let empty = [Double](repeating: 0, count: count)

        guard let window else {
            return ResetTimeProgress(state: .unknown, fills: empty)
        }
        // A window whose identity does not match the row is never normalised into it.
        guard window.kind == kind, window.windowDurationMinutes == expectedMinutes else {
            return ResetTimeProgress(state: .invalid, fills: empty)
        }
        guard let resetsAt = window.resetsAt else {
            return ResetTimeProgress(state: .unknown, fills: empty)
        }

        let nowSeconds = now.timeIntervalSince1970
        let resetSeconds = resetsAt.timeIntervalSince1970
        guard nowSeconds.isFinite, resetSeconds.isFinite else {
            return ResetTimeProgress(state: .invalid, fills: empty)
        }

        let remaining = resetSeconds - nowSeconds

        // Further out than the window itself allows, beyond the skew tolerance: refuse to
        // draw a permanently full bar.
        guard remaining <= total + clockTolerance else {
            return ResetTimeProgress(state: .invalid, fills: empty)
        }
        // Reached or passed: empty, and the app waits for the service instead of inventing
        // a fresh window.
        guard remaining > 0 else {
            return ResetTimeProgress(state: .arrived, fills: empty)
        }

        let clamped = min(remaining, total)
        let secondsPerSegment = total / Double(count)
        let units = clamped / secondsPerSegment
        let fills = (0..<count).map { index in
            min(max(units - Double(index), 0), 1)
        }
        return ResetTimeProgress(state: .active, fills: fills, remainingSeconds: clamped)
    }

    /// Both rows for one frame, from the same `now`.
    public static func rows(snapshot: UsageSnapshot?, now: Date) -> (fiveHour: ResetTimeProgress, weekly: ResetTimeProgress) {
        (progress(expected: .fiveHour, window: snapshot?.fiveHour, now: now),
         progress(expected: .weekly, window: snapshot?.weekly, now: now))
    }
}

// MARK: - Descriptions

extension ResetTimeProgress {

    /// Fixed-vocabulary state text, used by the hover/accessibility description. It never
    /// quotes provider text, and it says "waiting for a refresh" instead of claiming the
    /// quota itself has been renewed.
    public func stateText(windowName: String) -> String {
        switch state {
        case .active:
            return "\(windowName)剩余重置时间 \(Self.durationText(remainingSeconds))"
        case .arrived:
            return "\(windowName)已到重置时间，等待刷新确认"
        case .unknown:
            return "\(windowName)重置时间未知"
        case .invalid:
            return "\(windowName)重置时间不可用"
        }
    }

    /// `约 2 小时 30 分` / `约 45 分钟`. Rounded down to the minute, never up: a remaining
    /// minute must not read as a whole hour (v1.0.2 §4.2).
    static func durationText(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "不到 1 分钟" }
        let wholeMinutes = Int(seconds / 60)
        if wholeMinutes < 1 { return "不到 1 分钟" }
        let hours = wholeMinutes / 60
        let minutes = wholeMinutes % 60
        if hours == 0 { return "\(minutes) 分钟" }
        if minutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(minutes) 分"
    }
}

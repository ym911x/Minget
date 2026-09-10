import Foundation

/// Where the currently displayed numbers came from.
public enum UsageSource: Equatable, Sendable {
    case codexAppServer
    case cached
}

/// Normalized usage state. The UI depends only on this type, never on raw RPC JSON.
public struct UsageSnapshot: Equatable, Sendable {
    public let fiveHour: RateLimitWindow?
    public let weekly: RateLimitWindow?
    /// Windows with a duration that is neither 300 nor 10080; kept out of the UI, useful for diagnostics.
    public let unknownWindows: [RateLimitWindow]
    public let fetchedAt: Date
    public let source: UsageSource

    public init(fiveHour: RateLimitWindow?, weekly: RateLimitWindow?, unknownWindows: [RateLimitWindow] = [], fetchedAt: Date, source: UsageSource) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.unknownWindows = unknownWindows
        self.fetchedAt = fetchedAt
        self.source = source
    }

    /// Cache-friendly reduced form: only normalized numbers, never raw auth/RPC payloads.
    public struct Persisted: Codable, Equatable, Sendable {
        public var fiveHourUsedPercent: Double?
        public var fiveHourWindowDurationMinutes: Int?
        public var fiveHourResetsAtEpochSeconds: Double?
        public var weeklyUsedPercent: Double?
        public var weeklyWindowDurationMinutes: Int?
        public var weeklyResetsAtEpochSeconds: Double?
        public var fetchedAtEpochSeconds: Double

        public init(fiveHourUsedPercent: Double?, fiveHourWindowDurationMinutes: Int?, fiveHourResetsAtEpochSeconds: Double?,
                    weeklyUsedPercent: Double?, weeklyWindowDurationMinutes: Int?, weeklyResetsAtEpochSeconds: Double?,
                    fetchedAtEpochSeconds: Double) {
            self.fiveHourUsedPercent = fiveHourUsedPercent
            self.fiveHourWindowDurationMinutes = fiveHourWindowDurationMinutes
            self.fiveHourResetsAtEpochSeconds = fiveHourResetsAtEpochSeconds
            self.weeklyUsedPercent = weeklyUsedPercent
            self.weeklyWindowDurationMinutes = weeklyWindowDurationMinutes
            self.weeklyResetsAtEpochSeconds = weeklyResetsAtEpochSeconds
            self.fetchedAtEpochSeconds = fetchedAtEpochSeconds
        }
    }

    public var persisted: Persisted {
        func fields(_ w: RateLimitWindow?) -> (Double?, Int?, Double?) {
            guard let w else { return (nil, nil, nil) }
            return (w.usedPercent, w.windowDurationMinutes, w.resetsAt.map { $0.timeIntervalSince1970 })
        }
        let f = fields(fiveHour)
        let w = fields(weekly)
        return Persisted(
            fiveHourUsedPercent: f.0,
            fiveHourWindowDurationMinutes: f.1,
            fiveHourResetsAtEpochSeconds: f.2,
            weeklyUsedPercent: w.0,
            weeklyWindowDurationMinutes: w.1,
            weeklyResetsAtEpochSeconds: w.2,
            fetchedAtEpochSeconds: fetchedAt.timeIntervalSince1970
        )
    }

    public static func from(persisted: Persisted) -> UsageSnapshot {
        func window(used: Double?, duration: Int?, resets: Double?) -> RateLimitWindow? {
            guard let used, let duration else { return nil }
            let minutes = Int(duration)
            return RateLimitWindow(
                kind: RateLimitWindow.kind(forWindowDurationMinutes: minutes),
                windowDurationMinutes: minutes,
                usedPercent: used,
                remainingPercent: RateLimitWindow.remainingPercent(fromUsedPercent: used),
                resetsAt: resets.map { Date(timeIntervalSince1970: $0) }
            )
        }
        return UsageSnapshot(
            fiveHour: window(used: persisted.fiveHourUsedPercent, duration: persisted.fiveHourWindowDurationMinutes, resets: persisted.fiveHourResetsAtEpochSeconds),
            weekly: window(used: persisted.weeklyUsedPercent, duration: persisted.weeklyWindowDurationMinutes, resets: persisted.weeklyResetsAtEpochSeconds),
            unknownWindows: [],
            fetchedAt: Date(timeIntervalSince1970: persisted.fetchedAtEpochSeconds),
            source: .cached
        )
    }
}

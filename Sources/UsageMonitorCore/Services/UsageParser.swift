import Foundation

/// Normalizer: raw RPC result -> `UsageSnapshot`.
///
/// Deliberately tolerant of shape drift (PROJECT_SPEC.md §15) while strict about identity
/// and numbers:
/// - reads `rateLimitsByLimitId["codex"]` first; a present-but-empty codex entry is
///   reported as unavailable instead of silently falling back to another bucket,
/// - the legacy top-level `rateLimits` object is only accepted when its `limitId` is
///   absent or "codex" (Round 2 blocker 4),
/// - classifies windows by `windowDurationMins`, never by `primary`/`secondary` key names,
/// - treats missing, null, non-finite, boolean, fractional and out-of-range numbers as
///   "unavailable" instead of trapping or fabricating values (Round 2 blocker 1),
/// - preserves unknown window durations for diagnostics instead of crashing.
public struct UsageParser: Sendable {

    /// The only limit bucket this app is allowed to present.
    public static let codexLimitId = "codex"

    public init() {}

    // MARK: - Entry points

    /// Parse the `result` object of an `account/rateLimits/read` response.
    public func parseSnapshot(result: [String: Any], fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let buckets = resolveBuckets(in: result)
        guard !buckets.isEmpty else {
            throw UsageError.rpcFailed(.invalidPayload(.noRateLimitWindows))
        }

        var fiveHour: RateLimitWindow?
        var weekly: RateLimitWindow?
        var unknown: [RateLimitWindow] = []

        for windowObject in buckets {
            guard let window = parseWindow(windowObject) else { continue }
            switch window.kind {
            case .fiveHour:
                fiveHour = best(existing: fiveHour, candidate: window)
            case .weekly:
                weekly = best(existing: weekly, candidate: window)
            case .unknown:
                if !unknown.contains(where: { $0 == window }) { unknown.append(window) }
            }
        }

        guard fiveHour != nil || weekly != nil else {
            // Valid transport, but nothing the UI can present.
            throw UsageError.rpcFailed(.invalidPayload(.noUsableWindow))
        }
        return UsageSnapshot(fiveHour: fiveHour,
                             weekly: weekly,
                             rateLimitResetCredits: parseRateLimitResetCredits(result["rateLimitResetCredits"], fetchedAt: fetchedAt),
                             unknownWindows: unknown,
                             fetchedAt: fetchedAt,
                             source: .codexAppServer)
    }

    /// Parse a full JSON-RPC response envelope and return either its result or its error.
    public func parseResponse(data: Data) throws -> JSONRPCResponse {
        guard let object = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any] else {
            throw UsageError.rpcFailed(.malformedResponse)
        }
        return try decodeEnvelope(object)
    }

    // MARK: - Bucket resolution

    /// Result of resolving which windows belong to this account.
    public enum BucketResolution {
        /// Windows of the codex bucket.
        case codex([[String: Any]])
        /// No codex bucket could be identified. Carries why, for diagnostics only.
        case unavailable(PayloadProblem)
    }

    /// Resolves the window list for the codex bucket, never merging buckets.
    public func resolveBuckets(in result: [String: Any]) -> [[String: Any]] {
        switch resolveBucket(in: result) {
        case .codex(let windows): return windows
        case .unavailable: return []
        }
    }

    public func resolveBucket(in result: [String: Any]) -> BucketResolution {
        // 1. Preferred, verified-by-Codex shape: rateLimitsByLimitId["codex"].
        if let byId = result["rateLimitsByLimitId"] as? [String: Any], !byId.isEmpty {
            if byId.keys.contains(Self.codexLimitId) {
                // The codex entry exists: it is authoritative, even when empty or null.
                // Falling back to another bucket here would present a foreign limit as
                // this account's usage.
                let windows = windows(in: byId[Self.codexLimitId])
                return windows.isEmpty ? .unavailable(.codexBucketEmpty) : .codex(windows)
            }
            // Other buckets exist but none named codex: refuse to guess.
            return .unavailable(.foreignLimitBucket)
        }

        // 2. Legacy shape: top-level "rateLimits" holding primary/secondary plus limitId.
        if let legacy = result["rateLimits"] as? [String: Any] {
            // An unstated limitId is accepted (older builds); a stated foreign id is not.
            if let legacyId = legacyBucketId(legacy), legacyId != Self.codexLimitId {
                return .unavailable(.foreignLimitBucket)
            }
            let legacyWindows = windows(in: legacy)
            if !legacyWindows.isEmpty { return .codex(legacyWindows) }
            // A legacy bucket that is itself keyed by limit id.
            if let nested = legacy[Self.codexLimitId] as? [String: Any] {
                let nestedWindows = windows(in: nested)
                if !nestedWindows.isEmpty { return .codex(nestedWindows) }
            }
            return .unavailable(.noRateLimitWindows)
        }

        // 3. Degenerate form: windows directly in the result. Only accepted when nothing
        //    claims a different limit identity.
        if result["limitId"] == nil || (result["limitId"] as? String) == Self.codexLimitId {
            let topLevel = windows(in: result)
            if !topLevel.isEmpty { return .codex(topLevel) }
        }
        return .unavailable(.noRateLimitWindows)
    }

    /// Bucket identity of a legacy snapshot object: nil when unstated, the id when stated.
    private func legacyBucketId(_ dict: [String: Any]) -> String? {
        if let id = dict["limitId"] as? String { return id }
        return nil
    }

    /// Accepts `Any?` so callers never rely on an implicit optional coercion.
    private func windows(in value: Any?) -> [[String: Any]] {
        guard let value else { return [] }
        if let dict = value as? [String: Any] {
            var found: [[String: Any]] = []
            for key in ["primary", "secondary", "tertiary", "windows"] {
                if let nested = dict[key] {
                    if let windowDict = nested as? [String: Any] {
                        found.append(windowDict)
                    } else if let array = nested as? [[String: Any]] {
                        found.append(contentsOf: array)
                    }
                }
            }
            if !found.isEmpty { return found }
            // Object that itself looks like a window.
            if Self.looksLikeWindow(dict) { return [dict] }
            return []
        }
        if let array = value as? [[String: Any]] {
            return array.filter(Self.looksLikeWindow)
        }
        return []
    }

    static func looksLikeWindow(_ dict: [String: Any]) -> Bool {
        return dict["windowDurationMins"] != nil
            || dict["usedPercent"] != nil
            || dict["resetsAt"] != nil
    }

    // MARK: - Single window

    /// Returns nil when the window cannot be presented: missing/invalid used percent or
    /// duration. Invalid numbers never become 0 and never trap.
    public func parseWindow(_ dict: [String: Any]) -> RateLimitWindow? {
        guard let used = Self.usedPercent(in: dict) else { return nil }
        guard let duration = Self.windowDuration(in: dict) else { return nil }
        let kind = RateLimitWindow.kind(forWindowDurationMinutes: duration)
        return RateLimitWindow(
            kind: kind,
            windowDurationMinutes: duration,
            usedPercent: used,
            remainingPercent: RateLimitWindow.remainingPercent(fromUsedPercent: used),
            resetsAt: parseResetDate(dict["resetsAt"])
        )
    }

    /// Used percent: finite number; booleans and non-numeric text are data errors and
    /// stay unavailable. Out-of-range values are kept and clamped only for display
    /// (PROJECT_SPEC.md Test 8).
    public static func usedPercent(in dict: [String: Any]) -> Double? {
        return SafeConversion.double(dict["usedPercent"])
    }

    /// Window duration: exact positive integer. `300.9`, `0`, `-5`, `1e100` and `true`
    /// are all invalid rather than being truncated, rounded or converted with a trap.
    public static func windowDuration(in dict: [String: Any]) -> Int? {
        return SafeConversion.integer(dict["windowDurationMins"], allowNonPositive: false)
    }

    /// `resetsAt` is normally epoch seconds; an ISO-8601 string is accepted defensively.
    /// A reset in the past is still returned as-is; the UI decides how to render it
    /// (never show a past reset as a future one).
    public func parseResetDate(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let number = SafeConversion.double(value) {
            guard number > 0 else { return nil }
            return Date(timeIntervalSince1970: number)
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: trimmed) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: trimmed)
        }
        return nil
    }

    /// Parses the optional earned-reset summary without allowing malformed optional data to
    /// invalidate otherwise usable quota windows. `availableCount` is authoritative; the
    /// detail array may be absent, empty, or shorter than the count.
    public func parseRateLimitResetCredits(_ value: Any?, fetchedAt: Date) -> RateLimitResetCredits? {
        guard let summary = value as? [String: Any],
              let count = SafeConversion.integer(summary["availableCount"]),
              count >= 0 else {
            return nil
        }

        guard count > 0 else {
            return RateLimitResetCredits(availableCount: 0)
        }

        var nearestExpiry: Date?
        if let rawCredits = summary["credits"] as? [Any] {
            for rawCredit in rawCredits {
                guard let credit = rawCredit as? [String: Any] else { continue }
                if let status = credit["status"] as? String, status != "available" {
                    continue
                }
                guard let expiry = parseResetDate(credit["expiresAt"]), expiry > fetchedAt else {
                    continue
                }
                if nearestExpiry == nil || expiry < nearestExpiry! {
                    nearestExpiry = expiry
                }
            }
        }
        return RateLimitResetCredits(availableCount: count, nearestExpiresAt: nearestExpiry)
    }

    // MARK: - Envelope

    public func decodeEnvelope(_ object: [String: Any]) throws -> JSONRPCResponse {
        if let errorObject = object["error"] as? [String: Any] {
            let code = SafeConversion.errorCode(errorObject["code"])
            throw JSONRPCError(code: code, message: (errorObject["message"] as? String) ?? "")
        }
        guard let id = object["id"] else {
            // Notifications (no id) are not responses.
            throw UsageError.rpcFailed(.malformedResponse)
        }
        guard let result = object["result"] else {
            throw UsageError.rpcFailed(.malformedResponse)
        }
        return JSONRPCResponse(id: id, result: result)
    }

    private func best(existing: RateLimitWindow?, candidate: RateLimitWindow) -> RateLimitWindow {
        // Prefer a window that actually reports a reset time; otherwise keep the first.
        guard let existing else { return candidate }
        if existing.resetsAt == nil && candidate.resetsAt != nil { return candidate }
        return existing
    }
}

// MARK: - Envelope types

public struct JSONRPCResponse {
    public let id: Any
    public let result: Any

    /// Normalized result object, or nil when the result is not a dictionary.
    public var resultObject: [String: Any]? { result as? [String: Any] }
}

/// A JSON-RPC error reply. The server's message text is inspected here for sign-in
/// problems and then dropped: it never reaches `UsageError`, logs or the UI.
public struct JSONRPCError: Error {
    public let code: Int
    /// Upstream text, transport-internal only. Do not log, store or display it.
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    /// Sign-in related server errors are reported as a distinct state so the UI can say
    /// "not signed in" instead of a generic failure.
    public var indicatesNotSignedIn: Bool {
        let lowered = message.lowercased()
        return lowered.contains("not signed in") || lowered.contains("not logged in")
            || lowered.contains("unauthorized") || lowered.contains("unauthenticated")
            || lowered.contains("sign in") || lowered.contains("login required")
    }
}

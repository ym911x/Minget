import Foundation

/// Validated numeric conversions.
///
/// `Int(Double)` traps on out-of-range values and truncates fractions, so every value
/// that comes from an external payload goes through here (Round 2 blocker 1: a server
/// sending `windowDurationMins: 1e100` crashed the app with a fatal error instead of
/// reporting the window as unavailable).
public enum SafeConversion {

    /// True only for boxed booleans (`__NSCFBoolean`), not for small integers.
    static func isBoxedBool(_ number: NSNumber) -> Bool {
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Finite Double, rejecting Bool (a Bool is a data error, not 0/1) and non-finite values.
    ///
    /// Note: `value is Bool` cannot be used as the discriminator here, because
    /// `NSNumber(value: 1) is Bool` evaluates to true for 0 and 1. The boxed-boolean
    /// CFTypeID check is the reliable one.
    public static func double(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            if isBoxedBool(number) { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let double = value as? Double { return double.isFinite ? double : nil }
        if let int = value as? Int { return Double(int) }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Double(trimmed), parsed.isFinite else { return nil }
            return parsed
        }
        return nil
    }

    /// Exact integer: finite, representable in Int, and mathematically integral.
    /// Fractional, oversized or non-positive (when disallowed) values yield nil rather than trapping.
    public static func integer(_ value: Any?, allowNonPositive: Bool = true) -> Int? {
        guard let double = double(value) else { return nil }
        // Above 2^53 a Double can no longer represent every integer exactly, and values
        // beyond Int.max would trap on conversion. Both are rejected as invalid data.
        let exactLimit = 9_007_199_254_740_992.0  // 2^53
        guard double.magnitude <= exactLimit else { return nil }
        let rounded = double.rounded(.towardZero)
        guard rounded == double else { return nil }  // fractional: 300.9 is not a duration
        let result = Int(rounded)                     // safe: |rounded| <= 2^53 < Int.max
        if !allowNonPositive && result <= 0 { return nil }
        return result
    }

    /// JSON-RPC error code: any finite integer value; anything else maps to -1.
    public static func errorCode(_ value: Any?) -> Int {
        return integer(value) ?? -1
    }

    /// Money as `Decimal`, never through a binary float.
    ///
    /// Provider balance fields arrive as decimal strings ("110.00"); those parse exactly.
    /// A bare JSON number reaches this function as an `NSNumber`, whose own textual form is
    /// used, so the value is whatever the sender wrote rather than a `Double` rounding.
    /// Booleans, currency symbols, thousand separators and blank strings are data errors
    /// and yield nil, never 0.
    public static func decimal(_ value: Any?) -> Decimal? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            if isBoxedBool(number) { return nil }
            return decimal(from: number.stringValue)
        }
        if let text = value as? String {
            return decimal(from: text)
        }
        return nil
    }

    /// Strict money literal: optional sign, digits with an optional fraction and an
    /// optional exponent. Rejects grouping separators so "1,234" cannot become 1234.
    static let moneyLiteralPattern = "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"

    public static func decimal(from raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: Self.moneyLiteralPattern) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard regex.firstMatch(in: trimmed, options: [], range: range) != nil else { return nil }
        guard let parsed = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        guard parsed.isFinite else { return nil }
        return parsed
    }
}

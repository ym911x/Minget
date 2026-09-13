import Foundation

/// The ChatGPT account behind the running `codex app-server`, read with
/// `account/read` and `refreshToken: false`.
///
/// `refreshToken: false` matters: the app must never trigger a token refresh, only read
/// the already-established identity (v1.1 requirement 2). No token, cookie or auth payload
/// is modelled here — the response's auth material is never decoded.
public struct CodexAccount: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        case chatgpt
        case apiKey
        case other
    }

    public let kind: Kind
    /// Account email. Displayed in the detail panel; never logged (see `debugSummary`).
    public let email: String?
    public let planType: String?

    public init(kind: Kind, email: String?, planType: String?) {
        self.kind = kind
        self.email = email
        self.planType = planType
    }

    /// Identifier the business cache is keyed on. The email when there is one; otherwise a
    /// stable non-empty label, so a cache entry can always be attributed to exactly one
    /// account and never leaks between them. A blank email is no identity at all, so it
    /// never becomes a key.
    public var cacheAccountID: String? {
        if let email {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        switch kind {
        case .apiKey: return "api-key"
        case .chatgpt: return nil
        case .other: return nil
        }
    }

    /// Account identity shown in the detail panel. The plan comes from `account/read`; it is
    /// not inferred from the email and it is never written to a credential store.
    public var displayEmail: String? {
        guard let email, !email.isEmpty else { return nil }
        return email
    }

    /// Package label for the detail-panel title row. ChatGPT plan names such as `plus` and
    /// `5xPro` are preserved exactly as returned by the local Codex app-server. API-key
    /// sessions have no package field, so their account kind is shown honestly instead of
    /// inventing a subscription tier.
    public var displayPlanType: String? {
        if let planType, !planType.isEmpty { return planType }
        switch kind {
        case .apiKey: return "API Key"
        case .chatgpt, .other: return nil
        }
    }

    /// Fixed-category summary for logs and tests. Contains no email.
    public var debugSummary: String {
        switch kind {
        case .chatgpt:
            return "chatgpt(\(planType ?? "unknown-plan"))"
        case .apiKey:
            return "apiKey"
        case .other:
            return "other"
        }
    }
}

public enum CodexAccountParser {

    /// Parses the `result` object of an `account/read` response.
    /// Returns nil when no usable identity is present; callers then show 账号信息暂不可用.
    public static func parse(result: [String: Any]) -> CodexAccount? {
        guard let account = result["account"] as? [String: Any] else { return nil }
        let type = (account["type"] as? String)?.lowercased()

        switch type {
        case "chatgpt":
            let email = Self.nonEmptyString(account["email"])
            return CodexAccount(kind: .chatgpt, email: email, planType: Self.nonEmptyString(account["planType"]))
        case "apikey":
            return CodexAccount(kind: .apiKey, email: nil, planType: nil)
        default:
            // An unrecognised account type is reported as present-but-unknown rather than
            // guessed at, so the panel says "unavailable" instead of showing a wrong email.
            return CodexAccount(kind: .other, email: nil, planType: nil)
        }
    }

    static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

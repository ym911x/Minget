import Foundation

/// Fixed provider failure categories.
///
/// Like `UsageError`, no upstream text is carried: a provider body, header or error page
/// can never reach logs, tests or the panel. Only the numeric status/code survives.
public enum ProviderFailure: Error, Equatable, Sendable {
    /// No credential stored.
    case notConfigured
    /// The credential was rejected (401, 403, expired console session).
    case invalidCredential
    /// The device has no usable network path.
    case networkUnreachable
    case timedOut
    /// HTTP status outside 200..<300.
    case serverError(status: Int)
    /// HTTP 200 but the payload reports a business error. Never rendered as a balance.
    case businessError(code: Int)
    /// The payload could not be confirmed to carry the documented fields.
    case unexpectedResponse
    /// The endpoint answered with a business success, but the payload shape matches no
    /// confirmed schema. The observation keeps a redacted structure summary as evidence.
    case structureUnsupported
    /// The endpoint contract (fields and amount units) is not confirmed yet.
    case contractUnconfirmed
    /// An authenticated request was redirected to another origin. Refused, never followed.
    case crossDomainRedirectBlocked
    /// Automatic retries are paused until the user reconnects.
    case suspended
    /// The request was cancelled because a newer one replaced it.
    case cancelled
    case other

    /// True when the credential itself is the problem. These open an auth suspension
    /// instead of a retry loop.
    public var isAuthenticationFailure: Bool {
        switch self {
        case .invalidCredential:
            return true
        default:
            return false
        }
    }

    /// Maps a transport-level error onto its fixed category. Shared by every provider
    /// client, so the same network event is reported the same way everywhere. Local rule
    /// violations (a path the client may not ask for) are a malformed request, not a
    /// server condition.
    public static func from(_ transport: ProviderTransportError) -> ProviderFailure {
        switch transport {
        case .crossDomainRedirectBlocked: return .crossDomainRedirectBlocked
        case .networkUnreachable: return .networkUnreachable
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .pathNotAllowed, .modelEndpointBlocked, .invalidURL: return .unexpectedResponse
        case .other: return .other
        }
    }

    /// Fixed category summary, safe for logs and tests.
    public var debugSummary: String {
        switch self {
        case .notConfigured: return "notConfigured"
        case .invalidCredential: return "invalidCredential"
        case .networkUnreachable: return "networkUnreachable"
        case .timedOut: return "timedOut"
        case .serverError(let status): return "serverError(status:\(status))"
        case .businessError(let code): return "businessError(code:\(code))"
        case .unexpectedResponse: return "unexpectedResponse"
        case .structureUnsupported: return "structureUnsupported"
        case .contractUnconfirmed: return "contractUnconfirmed"
        case .crossDomainRedirectBlocked: return "crossDomainRedirectBlocked"
        case .suspended: return "suspended"
        case .cancelled: return "cancelled"
        case .other: return "other"
        }
    }

    /// Panel text. Fixed labels only.
    public var displayText: String {
        switch self {
        case .notConfigured:
            return "尚未配置连接"
        case .invalidCredential:
            return "凭证被拒绝或已过期，请重新连接"
        case .networkUnreachable:
            return "网络不可用，显示最近一次成功数据"
        case .timedOut:
            return "请求超时，显示最近一次成功数据"
        case .serverError:
            return "服务返回错误，显示最近一次成功数据"
        case .businessError:
            return "服务返回业务错误，显示最近一次成功数据"
        case .unexpectedResponse:
            return "返回数据格式无法确认，未显示余额"
        case .structureUnsupported:
            return "已连接，但当前响应结构暂不支持"
        case .contractUnconfirmed:
            return "接口口径尚未确认，未显示余额"
        case .crossDomainRedirectBlocked:
            return "请求被重定向到其他站点，已中止"
        case .suspended:
            return "已暂停自动刷新，请重新连接"
        case .cancelled:
            return "请求已取消"
        case .other:
            return "无法获取数据"
        }
    }
}

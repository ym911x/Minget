import Foundation

/// Fixed failure categories. Free text from the server is deliberately not carried:
/// diagnostics and UI can only ever show these enum cases and their fixed labels, so a
/// hostile or chatty upstream message cannot leak into logs or the panel
/// (Round 2 blocker 5).
public enum RPCFailureReason: Equatable, Sendable {
    /// No reply within the timeout for the given method name (our own string).
    case timedOut(method: String)
    /// Reply channel closed before a reply arrived.
    case transportClosed
    /// Reply was not a usable JSON object / had no id.
    case malformedResponse
    /// No reply arrived at all for the given method name (our own string).
    case noReply(method: String)
    /// Reply decoded but did not contain the data the UI needs.
    case invalidPayload(PayloadProblem)
    /// Server answered with a JSON-RPC error; only the numeric code is kept.
    case serverError(code: Int)
    /// Writing the request to the child failed.
    case writeFailed
    /// Local shutdown was requested while work was in flight.
    case shutdown
    /// The child could not be launched.
    case launchFailed
    /// Anything else, with no upstream text attached.
    case other
}

/// Why a payload was rejected. Fixed vocabulary, no upstream text.
public enum PayloadProblem: Equatable, Sendable {
    case noRateLimitWindows
    case windowMissingUsedPercent
    case windowMissingDuration
    case invalidDuration
    case invalidUsedPercent
    case noUsableWindow
    case codexBucketEmpty
    case foreignLimitBucket
}

/// Error states from PROJECT_SPEC.md §13. Each maps to one explicit UI message.
public enum UsageError: Error, Equatable, Sendable {
    /// A. Codex CLI not found on disk. Local paths only, never credential material.
    case codexCLINotFound(searchedPaths: [String])
    /// B. Codex is installed but has no signed-in account.
    case codexNotSignedIn
    /// C. `codex app-server` could not be started / died during handshake.
    case appServerStartupFailed(RPCFailureReason)
    /// D. RPC call failed (timeout, malformed reply, JSON-RPC error, transport closed).
    case rpcFailed(RPCFailureReason)
    /// E/F. A specific required window is missing from an otherwise valid snapshot.
    case windowUnavailable(kind: RateLimitWindow.Kind)

    /// Missing-window states are shown per row; the rest replace the whole panel.
    public var isFatal: Bool {
        switch self {
        case .windowUnavailable:
            return false
        default:
            return true
        }
    }

    /// Safe for logs and diagnostics: fixed vocabulary only, never upstream message text.
    public var debugSummary: String {
        switch self {
        case .codexCLINotFound(let paths):
            return "codexCLINotFound(searched \(paths.count) paths)"
        case .codexNotSignedIn:
            return "codexNotSignedIn"
        case .appServerStartupFailed(let reason):
            return "appServerStartupFailed(\(reason.description))"
        case .rpcFailed(let reason):
            return "rpcFailed(\(reason.description))"
        case .windowUnavailable(let kind):
            return "windowUnavailable(\(kind))"
        }
    }

    /// JSON-RPC error code when this failure came from a server error reply.
    public var serverErrorCode: Int? {
        switch self {
        case .rpcFailed(.serverError(let code)), .appServerStartupFailed(.serverError(let code)):
            return code
        default:
            return nil
        }
    }
}

extension RPCFailureReason {
    public var description: String {
        switch self {
        case .timedOut(let method): return "timedOut(\(method))"
        case .transportClosed: return "transportClosed"
        case .malformedResponse: return "malformedResponse"
        case .noReply(let method): return "noReply(\(method))"
        case .invalidPayload(let problem): return "invalidPayload(\(problem))"
        case .serverError(let code): return "serverError(code:\(code))"
        case .writeFailed: return "writeFailed"
        case .shutdown: return "shutdown"
        case .launchFailed: return "launchFailed"
        case .other: return "other"
        }
    }
}

extension PayloadProblem {
    public var description: String {
        switch self {
        case .noRateLimitWindows: return "noRateLimitWindows"
        case .windowMissingUsedPercent: return "windowMissingUsedPercent"
        case .windowMissingDuration: return "windowMissingDuration"
        case .invalidDuration: return "invalidDuration"
        case .invalidUsedPercent: return "invalidUsedPercent"
        case .noUsableWindow: return "noUsableWindow"
        case .codexBucketEmpty: return "codexBucketEmpty"
        case .foreignLimitBucket: return "foreignLimitBucket"
        }
    }
}

import Foundation

/// Result of one manual fire request, in the fixed vocabulary the card may display.
///
/// `exit 0` only means the request ran. Whether a *new* 5-hour window actually started is a
/// separate question, answered by comparing the service's `resetsAt` before and after the
/// request, so "request succeeded" and "new window confirmed" are never conflated
/// (REQUIREMENTS.md §7.2, REVIEW.md risk row 5).
///
/// No raw process text is representable here: the enum is the whole vocabulary.
public enum ChatGPTFireResult: Equatable, Sendable {

    /// The request ran and the service moved the 5-hour window forward by at least the
    /// confirmation threshold.
    case requestSucceededWindowConfirmed
    /// The request ran, but the 5-hour window did not move. Nothing is inferred from that.
    case requestSucceededWindowUnchanged
    /// The official Codex CLI could not be located.
    case codexCLINotFound
    /// The process could not be launched at all.
    case launchFailed
    /// The process exited with a non-zero status.
    case nonZeroExit
    /// The process exceeded the fixed timeout and was terminated.
    case timedOut
    /// A fire for this profile was already in flight; the second request was not queued.
    case alreadyRunning

    /// Fixed card text (UI_SPEC.md §9). Raw process output never appears here.
    public var displayText: String {
        switch self {
        case .requestSucceededWindowConfirmed: return "新窗口已确认"
        case .requestSucceededWindowUnchanged: return "请求成功，窗口未变化"
        case .codexCLINotFound: return "Codex CLI 不可用"
        case .launchFailed: return "点火进程启动失败"
        case .nonZeroExit: return "点火请求失败"
        case .timedOut: return "点火请求超时"
        case .alreadyRunning: return "该账号正在点火"
        }
    }

    /// Draws in the success colour.
    public var isSuccess: Bool { self == .requestSucceededWindowConfirmed }

    /// Draws in the failure colour (timeout and errors). The unchanged-window result stays
    /// secondary: it is not a failure.
    public var isFailure: Bool {
        switch self {
        case .codexCLINotFound, .launchFailed, .nonZeroExit, .timedOut, .alreadyRunning:
            return true
        case .requestSucceededWindowConfirmed, .requestSucceededWindowUnchanged:
            return false
        }
    }
}

/// What launching the fixed Codex CLI command reported, before the window comparison.
///
/// The two "request succeeded" card values cannot be produced by the launch alone, so they
/// are absent here on purpose: the view model produces them from a real refresh.
public enum ChatGPTFireProcessOutcome: Equatable, Sendable {

    case requestSucceeded
    case codexCLINotFound
    case launchFailed
    case nonZeroExit
    case timedOut
    case alreadyRunning

    /// The card result for every outcome that is already final. `nil` for
    /// `.requestSucceeded`, which the caller must resolve with a window comparison.
    public var immediateResult: ChatGPTFireResult? {
        switch self {
        case .requestSucceeded: return nil
        case .codexCLINotFound: return .codexCLINotFound
        case .launchFailed: return .launchFailed
        case .nonZeroExit: return .nonZeroExit
        case .timedOut: return .timedOut
        case .alreadyRunning: return .alreadyRunning
        }
    }
}

/// Fixed process lifecycle category for diagnostics. No exit code, no output text.
extension ChatGPTFireProcessOutcome {
    public var debugSummary: String {
        switch self {
        case .requestSucceeded: return "succeeded"
        case .codexCLINotFound: return "codexCLINotFound"
        case .launchFailed: return "launchFailed"
        case .nonZeroExit: return "nonZeroExit"
        case .timedOut: return "timedOut"
        case .alreadyRunning: return "alreadyRunning"
        }
    }
}

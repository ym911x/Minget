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
    /// The request ran, but there was not enough live evidence to compare the window before
    /// and after. Distinct from `.requestSucceededWindowUnchanged`, which asserts the window
    /// really was unchanged: this one asserts only that the request succeeded
    /// (REQUIREMENTS.md §4.1).
    case requestSucceededConfirmationUnavailable
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
        case .requestSucceededConfirmationUnavailable: return "请求成功，暂无法确认"
        case .codexCLINotFound: return "Codex CLI 不可用"
        case .launchFailed: return "点火进程启动失败"
        case .nonZeroExit: return "点火请求失败"
        case .timedOut: return "点火请求超时"
        case .alreadyRunning: return "该账号正在点火"
        }
    }

    /// Draws in the success colour.
    public var isSuccess: Bool { self == .requestSucceededWindowConfirmed }

    /// Draws in the failure colour (timeout and errors). The two non-confirming "request
    /// succeeded" results stay secondary: neither is a failure.
    public var isFailure: Bool {
        switch self {
        case .codexCLINotFound, .launchFailed, .nonZeroExit, .timedOut, .alreadyRunning:
            return true
        case .requestSucceededWindowConfirmed, .requestSucceededWindowUnchanged,
             .requestSucceededConfirmationUnavailable:
            return false
        }
    }
}

/// The one place that turns "the request ran" into one of the three possible outcomes.
///
/// The rule is a truth table over fixed observations, not a judgement about the provider:
/// a new window can only be claimed when a *live* read from before the request and a *live*
/// read from after it differ by at least the threshold. A cached read is not evidence, a live
/// read without a reset time is not evidence, and with no "before" value nothing can be
/// compared at all — that case reports the request alone rather than guessing
/// (REQUIREMENTS.md §4.3).
///
/// `Observation` deliberately carries no raw error, response or process output: it is the
/// whole vocabulary, so nothing provider-specific can leak into the card.
public enum FireWindowConfirmation {

    /// The minimum forward movement that counts as a new window. Anything smaller is clock
    /// skew, not a restarted 5-hour window.
    public static let threshold: TimeInterval = 60

    /// One confirmation read, reduced to what the truth table may use.
    public enum Observation: Equatable, Sendable {
        /// A live read that reported a usable 5-hour reset time.
        case live(resetsAt: Date)
        /// A cached read, a failed read, or a live read with no 5-hour reset time. None of
        /// these can confirm a window, and they are deliberately indistinguishable here.
        case noEvidence
    }

    /// Whether one live observation proves the window moved.
    public static func confirms(live: Date, previous: Date?) -> Bool {
        guard let previous else { return false }
        return live.timeIntervalSince(previous) >= threshold
    }

    /// Final classification for one request, from the pre-fire time and the confirmation
    /// reads actually taken (one when the first was already conclusive, otherwise two).
    public static func classify(previousReset: Date?, observations: [Observation]) -> ChatGPTFireResult {
        // No "before" value means the comparison the confirmation is built on does not exist,
        // however good the "after" value looks.
        guard let previousReset else { return .requestSucceededConfirmationUnavailable }
        let liveTimes = observations.compactMap { observation -> Date? in
            switch observation {
            case .live(let resetsAt): return resetsAt
            case .noEvidence: return nil
            }
        }
        guard !liveTimes.isEmpty else { return .requestSucceededConfirmationUnavailable }
        let moved = liveTimes.contains { confirms(live: $0, previous: previousReset) }
        return moved ? .requestSucceededWindowConfirmed : .requestSucceededWindowUnchanged
    }
}

/// What launching the fixed Codex CLI command reported, before the window comparison.
///
/// The three "request succeeded" card values cannot be produced by the launch alone, so they
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

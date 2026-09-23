import Foundation

/// Pure retry policy for one profile's automatic refresh cycle (1.4.2).
///
/// 1.3.x froze a profile after one failed episode until an explicit manual retry; a
/// transient outage therefore lasted until the user noticed. This policy replaces that
/// permanent freeze with a bounded ladder:
///
/// - one failed episode retries immediately exactly once (attempt + one immediate retry),
/// - after that the next *automatic* attempt waits `30 / 60 / 120 / 300` seconds, one step
///   further per consecutive failed episode, capped at 300 seconds,
/// - a successful fetch resets the ladder,
/// - an explicit manual fetch (`resetFailureBudget: true`) bypasses the gate entirely,
/// - non-restartable failures (CLI missing, not signed in) never enter a retry loop: only a
///   manual retry may run again,
/// - the delay is computed by the pure function below and compared against an injectable
///   clock, so tests can walk the ladder without sleeping.
///
/// The policy holds no state; `UsageService` owns the counters.
public enum CodexRetryPolicy {

    /// How many attempts one episode makes before declaring the episode failed:
    /// the first attempt plus one immediate retry.
    public static let immediateRetryCount = 1

    /// Delay before the next automatic attempt after the given number of consecutive
    /// failed episodes. Step 1 is 30 s, then 60, 120, and every later failure waits the
    /// 300-second cap.
    public static func backoffDelay(afterFailedEpisodes failedEpisodes: Int) -> TimeInterval {
        guard failedEpisodes > 0 else { return 0 }
        let steps: [TimeInterval] = [30, 60, 120, 300]
        let index = min(failedEpisodes - 1, steps.count - 1)
        return steps[index]
    }

    /// The earliest instant the next automatic attempt may run, computed from an injectable
    /// reading of the clock. A pure function so the ladder is testable without sleeping.
    public static func nextAutomaticRetry(now: Date, failedEpisodes: Int) -> Date {
        now.addingTimeInterval(backoffDelay(afterFailedEpisodes: failedEpisodes))
    }

    /// Whether the next automatic attempt is allowed at `now`. `nextRetryAt == nil` means
    /// no gate is set.
    public static func isAutomaticAttemptDue(nextRetryAt: Date?, now: Date) -> Bool {
        guard let nextRetryAt else { return true }
        return now >= nextRetryAt
    }

    /// Whether a failure may be retried automatically at all. Shutdown is never retried,
    /// and the fixed non-restartable categories (missing CLI, not signed in, window shape)
    /// stop the loop instead of repeating a request that cannot succeed.
    public static func isAutoRetryable(_ error: UsageError) -> Bool {
        guard !error.isShutdown else { return false }
        return error.isRestartable
    }
}

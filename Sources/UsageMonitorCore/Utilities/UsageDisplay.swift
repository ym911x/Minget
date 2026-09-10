import Foundation

/// What the UI should render. Mapping lives in core so the live/cached distinction is
/// testable and so the snapshot's own `source` is authoritative: a result the service
/// labels non-live can never be displayed as live, whatever its error field says.
public enum UsageDisplay: Equatable {
    case live(UsageSnapshot)
    case stale(UsageSnapshot, UsageError)
    case unavailable(UsageError)

    /// Maps a service fetch outcome.
    /// `isLive == false` always yields `.stale` (or `.unavailable` when nothing cached exists).
    public init(fetchResult: UsageService.FetchResult) {
        if fetchResult.isLive && fetchResult.snapshot.source == .codexAppServer {
            self = .live(fetchResult.snapshot)
            return
        }
        if let error = fetchResult.error {
            self = .stale(fetchResult.snapshot, error)
        } else {
            // A cached snapshot without an error must still be labelled as cached.
            self = .stale(fetchResult.snapshot, .rpcFailed(.other))
        }
    }

    /// Maps a failed outcome that had no live data at all.
    public init(error: UsageError, cached: UsageSnapshot?) {
        if let cached {
            self = .stale(cached, error)
        } else {
            self = .unavailable(error)
        }
    }

    public var snapshot: UsageSnapshot? {
        switch self {
        case .live(let snapshot), .stale(let snapshot, _): return snapshot
        case .unavailable: return nil
        }
    }

    public var isStale: Bool {
        switch self {
        case .live: return false
        case .stale: return true
        case .unavailable: return false
        }
    }

    /// Categorical label for lifecycle logs, e.g. "live" / "stale(timedOut)".
    public var diagnosticLabel: String {
        switch self {
        case .live: return "live"
        case .stale(_, let error): return "stale(\(error.debugSummary))"
        case .unavailable(let error): return "unavailable(\(error.debugSummary))"
        }
    }

    /// Menu bar title: `5H 78% | W 42%`, with ⚠ whenever the data is cached.
    public var menuBarTitle: String {
        UsageFormatting.menuBarTitle(fiveHour: snapshot?.fiveHour, weekly: snapshot?.weekly, isStale: isStale)
    }
}

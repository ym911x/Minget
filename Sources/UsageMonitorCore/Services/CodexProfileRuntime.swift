import Foundation

/// Identity display state for one profile (1.4.2 REQUIREMENTS.md §3.4).
///
/// A card may only claim an identity it actually observed, and it labels how confident
/// that claim is:
/// - `confirmed`: resolved by this profile connection's latest successful identity read,
/// - `previous`: the last identity this app-server connection confirmed, kept across a
///   transient failure so the card can show 上次身份 instead of silently repeating the
///   old email as if it were still verified,
/// - `unavailable`: nothing to claim — the card shows 账号暂不可用.
///
/// A newly published app-server child starts a new connection epoch. Identities are only
/// carried across transient failures within the same epoch; a replacement child requires
/// a fresh identity read before the card may show an account.
public enum ProfileIdentityState: Equatable, Sendable {
    case confirmed(CodexAccount)
    case previous(CodexAccount)
    case unavailable

    /// The account the card may render, if any.
    public var account: CodexAccount? {
        switch self {
        case .confirmed(let account), .previous(let account): return account
        case .unavailable: return nil
        }
    }

    /// Explicit UI label for a non-confirmed identity. Confirmed needs no label.
    public var label: String? {
        switch self {
        case .confirmed: return nil
        case .previous: return "上次身份"
        case .unavailable: return nil
        }
    }
}

/// One enabled ChatGPT profile's runtime: the immutable configuration plus everything that
/// changes while the app runs (REQUIREMENTS.md §4.2, IMPLEMENTATION_TASKS.md §1.1).
///
/// Keeping configurable data (`profile`) apart from runtime state is what makes two accounts
/// possible at all: the previous single `displayState` / `connectionState` / `codexAccount`
/// triple could only ever describe one account, so a second one silently overwrote the first.
///
/// All state sits behind one lock so a background fetch can publish while the main actor
/// reads, and readers take a single consistent value snapshot rather than several
/// individually-locked fields.
public final class CodexProfileRuntime: @unchecked Sendable {

    public let profile: ChatGPTAccountProfile
    /// The long-lived service owning this profile's `codex app-server` child.
    public let service: UsageService

    private let lock = NSLock()
    private var display: UsageDisplay = .unavailable(.rpcFailed(.other))
    private var connection: UsageService.ConnectionState = .idle
    /// The account rendered by the card: the confirmed or previous identity's account.
    private var account: CodexAccount?
    /// Identity state backing `account`. Stored identity is bound to the app-server
    /// connection epoch that confirmed it, and cannot be carried to a replacement child
    /// (REQUIREMENTS.md §3.4).
    private var identity: ProfileIdentityState = .unavailable
    private var storedIdentity: CodexAccount?
    private var storedIdentityEpoch: Int?
    private var isFetching = false
    private var lastError: UsageError?
    private var isFiring = false
    private var fireResult: ChatGPTFireResult?
    /// Forward movement measured by the last finished fire, for the card suffix.
    private var fireDriftSeconds: TimeInterval?
    /// Recent finishes, newest first, at most `maxFireHistory`. Memory only.
    private var fireHistory: [FireHistoryEntry] = []

    /// How many finishes one profile remembers. Fixed so the tooltip cannot grow.
    public static let maxFireHistory = 3

    public init(profile: ChatGPTAccountProfile, service: UsageService) {
        self.profile = profile
        self.service = service
    }

    public var profileID: String { profile.id }

    /// One consistent read of everything the UI needs for this profile.
    public func state() -> CodexProfileRuntimeState {
        lock.lock(); defer { lock.unlock() }
        return CodexProfileRuntimeState(profile: profile,
                                        display: display,
                                        connectionState: connection,
                                        account: account,
                                        identity: identity,
                                        isFetching: isFetching,
                                        lastError: lastError,
                                        isFiring: isFiring,
                                        fireResult: fireResult,
                                        fireDriftSeconds: fireDriftSeconds,
                                        fireHistory: fireHistory)
    }

    // MARK: - Fetch lifecycle (coordinator)

    func recordFetchStart() {
        lock.lock(); isFetching = true; lock.unlock()
    }

    func recordFetchSuccess(_ result: UsageService.FetchResult) {
        // The service reports a failed episode that still had cache as success with
        // isLive=false and the recorded error (the backoff gate does the same). Identity
        // handling must follow the failure path, or a transient failure would wipe the
        // previous identity just because a stale snapshot arrived.
        if !result.isLive, let error = result.error {
            recordFetchFailure(error)
            return
        }
        let resultEpoch = result.connectionEpoch ?? service.currentConnectionEpoch
        let latestEpoch = service.currentConnectionEpoch
        lock.lock()
        isFetching = false
        display = UsageDisplay(fetchResult: result)
        connection = service.connectionState
        lastError = nil
        if resultEpoch == latestEpoch,
           let account = result.account, account.cacheAccountID != nil {
            // A confirmed identity replaces whatever came before it, whoever it was.
            storedIdentity = account
            storedIdentityEpoch = resultEpoch
            identity = .confirmed(account)
            self.account = account
        } else if resultEpoch == latestEpoch,
                  storedIdentityEpoch == resultEpoch,
                  let stored = storedIdentity {
            // The quota read succeeded but this cycle resolved no identity. Preserve the
            // account only while this is still the exact child connection that confirmed it.
            identity = .previous(stored)
            self.account = stored
        } else {
            // The connection changed, or this connection never confirmed an account.
            storedIdentity = nil
            storedIdentityEpoch = nil
            identity = .unavailable
            self.account = nil
        }
        lock.unlock()
    }

    func recordFetchFailure(_ error: UsageError) {
        let cached = service.cachedSnapshotForCurrentAccount()
        let mapped = UsageDisplay(error: error, cached: cached)
        let currentEpoch = service.currentConnectionEpoch
        lock.lock()
        isFetching = false
        display = mapped
        connection = service.connectionState
        account = nil
        lastError = error
        if error.isShutdown {
            // The app is stopping: claim nothing, but do not invalidate the stored
            // identity either — teardown decides nothing about the account.
            identity = .unavailable
            lock.unlock()
            return
        }
        if let stored = storedIdentity,
           storedIdentityEpoch == currentEpoch,
           error.isRestartable {
            // A transient failure within the same app-server connection may show the
            // last confirmed account, explicitly labelled as previous.
            identity = .previous(stored)
            account = stored
            lock.unlock()
            return
        }
        // Not the kind of failure a retry could ride out (signed out, CLI missing):
        // nothing to claim, and the stored identity is invalidated.
        storedIdentity = nil
        storedIdentityEpoch = nil
        identity = .unavailable
        lock.unlock()
    }

    /// Records a confirmation-only read: the quota display moves, the identity state
    /// stays exactly as it was, because no identity was requested on this path.
    func recordConfirmationSuccess(_ result: UsageService.FetchResult) {
        let resultEpoch = result.connectionEpoch ?? service.currentConnectionEpoch
        let latestEpoch = service.currentConnectionEpoch
        lock.lock()
        isFetching = false
        display = UsageDisplay(fetchResult: result)
        connection = service.connectionState
        lastError = nil
        if storedIdentityEpoch != resultEpoch || resultEpoch != latestEpoch {
            // A confirmation read does not request identity, but a replacement child still
            // invalidates an identity confirmed by the prior connection.
            storedIdentity = nil
            storedIdentityEpoch = nil
            identity = .unavailable
            account = nil
        }
        lock.unlock()
    }

    /// A confirmation read that fell back to cache: the display stays where it was, so
    /// the stale number is never mistaken for a fresh observation.
    func recordConfirmationStale() {
        lock.lock()
        isFetching = false
        connection = service.connectionState
        lock.unlock()
    }

    // MARK: - Fire lifecycle (view model)

    func recordFireStart() {
        lock.lock()
        isFiring = true
        fireResult = nil
        fireDriftSeconds = nil
        lock.unlock()
    }

    func recordFireFinished(_ result: ChatGPTFireResult, driftSeconds: TimeInterval? = nil) {
        lock.lock()
        isFiring = false
        fireResult = result
        fireDriftSeconds = driftSeconds
        fireHistory.insert(FireHistoryEntry(result: result, finishedAt: Date(), driftSeconds: driftSeconds), at: 0)
        if fireHistory.count > Self.maxFireHistory {
            fireHistory = Array(fireHistory.prefix(Self.maxFireHistory))
        }
        lock.unlock()
    }
}

/// Value snapshot of one profile's runtime state.
public struct CodexProfileRuntimeState: Equatable, Sendable {
    public let profile: ChatGPTAccountProfile
    public let display: UsageDisplay
    public let connectionState: UsageService.ConnectionState
    /// The identity account the card renders, if any.
    public let account: CodexAccount?
    /// How confidently `account` may be shown (1.4.2 §3.4).
    public let identity: ProfileIdentityState
    public let isFetching: Bool
    public let lastError: UsageError?
    public let isFiring: Bool
    public let fireResult: ChatGPTFireResult?
    /// Forward movement measured by the last finished fire, for the card suffix.
    public let fireDriftSeconds: TimeInterval?
    /// Recent finishes, newest first. Memory only, never persisted.
    public let fireHistory: [FireHistoryEntry]

    public init(profile: ChatGPTAccountProfile,
                display: UsageDisplay,
                connectionState: UsageService.ConnectionState,
                account: CodexAccount?,
                identity: ProfileIdentityState = .unavailable,
                isFetching: Bool,
                lastError: UsageError?,
                isFiring: Bool,
                fireResult: ChatGPTFireResult?,
                fireDriftSeconds: TimeInterval? = nil,
                fireHistory: [FireHistoryEntry] = []) {
        self.profile = profile
        self.display = display
        self.connectionState = connectionState
        self.account = account
        self.identity = identity
        self.isFetching = isFetching
        self.lastError = lastError
        self.isFiring = isFiring
        self.fireResult = fireResult
        self.fireDriftSeconds = fireDriftSeconds
        self.fireHistory = fireHistory
    }

    public var snapshot: UsageSnapshot? { display.snapshot }
    public var isStale: Bool { display.isStale }
}

import Foundation

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
    private var account: CodexAccount?
    private var isFetching = false
    private var lastError: UsageError?
    private var isFiring = false
    private var fireResult: ChatGPTFireResult?

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
                                        isFetching: isFetching,
                                        lastError: lastError,
                                        isFiring: isFiring,
                                        fireResult: fireResult)
    }

    // MARK: - Fetch lifecycle (coordinator)

    func recordFetchStart() {
        lock.lock(); isFetching = true; lock.unlock()
    }

    func recordFetchSuccess(_ result: UsageService.FetchResult) {
        let mapped = UsageDisplay(fetchResult: result)
        lock.lock()
        isFetching = false
        display = mapped
        connection = service.connectionState
        account = result.account
        lastError = nil
        lock.unlock()
    }

    func recordFetchFailure(_ error: UsageError) {
        let cached = service.cachedSnapshotForCurrentAccount()
        let mapped = UsageDisplay(error: error, cached: cached)
        lock.lock()
        isFetching = false
        display = mapped
        connection = service.connectionState
        // A failed cycle has no identity to report; the card says 账号暂不可用 instead of
        // reusing a possibly stale email from another cycle.
        account = nil
        lastError = error
        lock.unlock()
    }

    // MARK: - Fire lifecycle (view model)

    func recordFireStart() {
        lock.lock()
        isFiring = true
        fireResult = nil
        lock.unlock()
    }

    func recordFireFinished(_ result: ChatGPTFireResult) {
        lock.lock()
        isFiring = false
        fireResult = result
        lock.unlock()
    }
}

/// Value snapshot of one profile's runtime state.
public struct CodexProfileRuntimeState: Equatable, Sendable {
    public let profile: ChatGPTAccountProfile
    public let display: UsageDisplay
    public let connectionState: UsageService.ConnectionState
    public let account: CodexAccount?
    public let isFetching: Bool
    public let lastError: UsageError?
    public let isFiring: Bool
    public let fireResult: ChatGPTFireResult?

    public init(profile: ChatGPTAccountProfile,
                display: UsageDisplay,
                connectionState: UsageService.ConnectionState,
                account: CodexAccount?,
                isFetching: Bool,
                lastError: UsageError?,
                isFiring: Bool,
                fireResult: ChatGPTFireResult?) {
        self.profile = profile
        self.display = display
        self.connectionState = connectionState
        self.account = account
        self.isFetching = isFetching
        self.lastError = lastError
        self.isFiring = isFiring
        self.fireResult = fireResult
    }

    public var snapshot: UsageSnapshot? { display.snapshot }
    public var isStale: Bool { display.isStale }
}

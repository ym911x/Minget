import AppKit
import Foundation
import Combine
import UsageMonitorCore

/// Drives the menu bar UI and the detail panel.
///
/// Two independent refresh loops live here (v1.1 requirement 5):
/// - Codex, every 60 seconds, on the long-lived `codex app-server` child,
/// - DeepSeek, every 5 minutes, over HTTPS with its own credential and in-flight
///   in-flight coalescing.
///
/// All fetches run off the main thread; `stop()` hands the Codex join to a background queue
/// and reports completion, so the application can defer termination until the in-flight
/// fetch and the owned child are quiescent (Round 3 blocker 2).
@MainActor
public final class UsageViewModel: ObservableObject {

    // MARK: Codex

    @Published public private(set) var displayState: UsageDisplay = .unavailable(.rpcFailed(.other))
    @Published public private(set) var connectionState: UsageService.ConnectionState = .idle
    /// Account email from `account/read`, or nil when it could not be established this cycle.
    @Published public private(set) var codexAccount: CodexAccount?
    @Published public private(set) var codexAccountAvailable = false

    // MARK: Providers

    /// One report per detail-panel platform, in display order.
    @Published public private(set) var providerReports: [ProviderReport] = []
    /// The latest unauthenticated observation from DeepSeek's public status page. A failed
    /// page read remains visibly unavailable; it is never converted into a healthy state.
    @Published public private(set) var deepSeekStatus = DeepSeekStatusSnapshot.unavailable()

    // MARK: Shared

    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isProviderRefreshing = false
    @Published public private(set) var isDeepSeekStatusRefreshing = false
    /// Per-platform, fixed-vocabulary feedback for the credential settings forms (Round 6).
    /// Absence means "nothing to say". Text is fixed and safe: no provider text, no system
    /// error text, never credential material.
    @Published public private(set) var credentialFeedback: [ProviderPlatform: CredentialFeedback] = [:]
    /// Bumped whenever relative timestamps should be re-evaluated (staleness ages).
    @Published public private(set) var tick = 0
    /// Whether the call-level credential diagnostics are being written. Toggled from the
    /// panel; works on a normal launch because it reads an app-owned preference instead of an
    /// environment variable (KEYCHAIN_REVISION_PLAN.md P0.4).
    @Published public private(set) var isCredentialDiagnosticOn = CredentialAccessLog.isEnabled

    private let service: UsageService
    /// Non-optional by design (Round 6): a view model without an engine has no save path
    /// at all, which is exactly the silent-failure shape this round removes. The readings
    /// inside the engine own their credentials; the view model holds no separate store.
    /// Internal (not private) so the wiring tests can read engine state directly.
    let providerEngine: ProviderRefreshEngine
    private let refreshInterval: TimeInterval
    private let panelOpenRefreshAge: TimeInterval
    private let providerRefreshInterval: TimeInterval
    private let providerPanelOpenRefreshAge: TimeInterval
    private let deepSeekStatusReader: DeepSeekStatusReading?
    private let deepSeekStatusRefreshInterval: TimeInterval = 5 * 60
    private var timer: AnyCancellable?
    private var providerTimer: AnyCancellable?
    private var clockTimer: AnyCancellable?
    /// Wake and system-clock observers, with the centre each was registered on so `stop()` can
    /// release exactly the right one.
    private var clockObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var refreshTask: Task<Void, Never>?
    private var providerRefreshTask: Task<Void, Never>?
    private var deepSeekStatusTask: Task<Void, Never>?
    private var deepSeekStatusCheckedAt: Date?
    private(set) var isStopped = false

    public init(service: UsageService,
                providerEngine: ProviderRefreshEngine,
                refreshInterval: TimeInterval = 60,
                panelOpenRefreshAge: TimeInterval = UsageCache.maxAgeForPanelOpenRefresh,
                providerRefreshInterval: TimeInterval = ProviderRefreshEngine.defaultRefreshInterval,
                providerPanelOpenRefreshAge: TimeInterval = ProviderRefreshEngine.defaultPanelOpenRefreshAge,
                deepSeekStatusReader: DeepSeekStatusReading? = nil) {
        self.service = service
        self.providerEngine = providerEngine
        self.refreshInterval = refreshInterval
        self.panelOpenRefreshAge = panelOpenRefreshAge
        self.providerRefreshInterval = providerRefreshInterval
        self.providerPanelOpenRefreshAge = providerPanelOpenRefreshAge
        self.deepSeekStatusReader = deepSeekStatusReader
        publishProviderReports()
    }

    // MARK: - Derived values

    public var menuBarTitle: String { displayState.menuBarTitle }

    /// Everything the status item draws for one mode and one clock reading.
    ///
    /// `now` is read per frame rather than accumulated, so sleep, a delayed main thread or a
    /// system clock change can never leave the two rows drifting away from the real time
    /// (v1.0.2 §4.4).
    public func menuBarContent(for mode: MenuBarSpaceMode, now: Date = Date()) -> MenuBarContent {
        MenuBarContentBuilder.make(display: displayState,
                                   connectionState: connectionState,
                                   now: now,
                                   mode: mode)
    }

    /// Identity of everything that can change the status item's width, across all modes. The
    /// countdown is deliberately absent: the item is re-measured only when its content or its
    /// warning changes, not once a second (v1.0.2 §4.4).
    public var menuBarSizeSignature: String {
        let now = Date()
        return MenuBarSpaceMode.allCases
            .map { menuBarContent(for: $0, now: now).sizeSignature }
            .joined(separator: "|")
    }

    public var currentSnapshot: UsageSnapshot? { displayState.snapshot }

    /// Cached data is always shown with a warning; it must never read as live data.
    public var isStale: Bool { displayState.isStale }

    /// Signature of the displayed label content, so the status item only re-measures its
    /// width when the text actually changed.
    public var menuBarStalenessMarker: String {
        return displayState.isStale ? "stale" : "live"
    }

    // MARK: - Lifecycle

    /// Starts the app: immediate refresh, then on both schedules.
    public func start() {
        Diagnostics.log("viewmodel start")
        isStopped = false
        scheduleTimers()
        observeClockChanges()
        // Age the relative timestamps once a second so "更新于 X 秒前" stays truthful, and so
        // the two reset-time rows advance without any network or service work.
        clockTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick += 1 }
        refresh()
        refreshProviders(force: false)
        refreshDeepSeekStatus(force: false)
        // The credential pass runs after the first paint, off the main actor, and never shows
        // UI. Until it finishes, status questions answer "still finding out" rather than
        // asking the keychain (KEYCHAIN_REVISION_PLAN.md P0 and P1.3).
        primeCredentialAccess()
    }

    /// One background credential pass for every provider, so the panel can answer
    /// "connected?" from memory afterwards.
    private func primeCredentialAccess() {
        wireCredentialPhaseChanges()
        Task { [weak self] in
            guard let self else { return }
            await self.providerEngine.primeCredentials()
            self.publishProviderReports()
            self.refreshProviders(force: false)
        }
    }

    /// A credential phase change (a value that arrived late, a refusal) must reach the panel
    /// without the panel ever having asked the keychain anything.
    private func wireCredentialPhaseChanges() {
        let publish: () -> Void = { [weak self] in
            Task { @MainActor in self?.publishProviderReports() }
        }
        for platform in [ProviderPlatform.deepseek] {
            switch engineReading(platform) {
            case let reading as DeepSeekReading: reading.onCredentialPhaseChange = publish
            default: break
            }
        }
    }

    /// Recomputes the displayed countdowns immediately when the machine wakes or the system
    /// clock is changed, instead of waiting for the next one-second tick. The observers are
    /// released in `stop()`.
    ///
    /// `NSWorkspace.didWakeNotification` is posted on the workspace's own centre; observing it
    /// on `NotificationCenter.default` never fires (v1.0.2 §4.4).
    private func observeClockChanges() {
        guard clockObservers.isEmpty else { return }
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick += 1 }
        }
        let clockChanged = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick += 1 }
        }
        clockObservers = [(NSWorkspace.shared.notificationCenter, wake),
                          (NotificationCenter.default, clockChanged)]
    }

    private func stopObservingClockChanges() {
        for (center, token) in clockObservers { center.removeObserver(token) }
        clockObservers.removeAll()
    }

    /// Cancels in-flight Codex work, stops timers and joins the fetch plus the owned child
    /// cleanup on a dedicated join queue. `completion` is called on that queue once the
    /// service reports quiescence (or once its bounded drain timed out).
    ///
    /// The join happens off the main actor on purpose: `service.stop()` blocks, and waiting
    /// for it on the main actor would deadlock `apply()`. `completion` is likewise delivered
    /// from the join queue: hopping back to the main queue would never run while
    /// `applicationShouldTerminate` blocks the main thread waiting for that completion.
    public func stop(completion: (() -> Void)? = nil) {
        guard !isStopped else {
            completion?()   // already quiescent or already draining
            return
        }
        isStopped = true
        isRefreshing = false   // teardown: no further state is published (apply() early-returns)
        isProviderRefreshing = false
        isDeepSeekStatusRefreshing = false
        timer?.cancel()
        providerTimer?.cancel()
        clockTimer?.cancel()
        timer = nil
        providerTimer = nil
        clockTimer = nil
        stopObservingClockChanges()
        providerRefreshTask?.cancel()
        providerRefreshTask = nil
        deepSeekStatusTask?.cancel()
        deepSeekStatusTask = nil

        let task = refreshTask
        refreshTask = nil
        let service = self.service
        // The closure captures only locals; the view model itself is not touched here, so
        // teardown cannot race a mutating call.
        joinQueue.async {
            task?.cancel()      // stops publishing; the blocking fetch itself is drained below
            service.stop()      // bounded drain of the fetch and the owned child
            Diagnostics.log("viewmodel stopped")
            completion?()
        }
    }

    /// Serial queue so repeated stop() calls cannot overlap their drains.
    private let joinQueue = DispatchQueue(label: "usagemonitor.viewmodel.join")

    private func scheduleTimers() {
        timer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        providerTimer = Timer.publish(every: providerRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshProviders(force: false)
                self?.refreshDeepSeekStatus(force: false)
            }
    }

    // MARK: - Panel

    /// Called when the user opens the detail: each source is refreshed on its own freshness
    /// rule, Codex at 30 seconds and the providers at 60 seconds.
    public func panelWillOpen() {
        guard !isStopped else { return }
        panelWillOpenCodex()
        panelWillOpenProviders()
        refreshDeepSeekStatus(force: false)
    }

    private func panelWillOpenCodex() {
        guard let snapshot = currentSnapshot else {
            refresh()
            return
        }
        if UsageCache.isStale(fetchedAt: snapshot.fetchedAt, maxAge: panelOpenRefreshAge) {
            refresh()
        }
    }

    private func panelWillOpenProviders() {
        for platform in [ProviderPlatform.deepseek] {
            guard providerEngine.shouldRefreshOnPanelOpen(platform) else { continue }
            refreshProvider(platform, force: false)
        }
    }

    // MARK: - Refreshing

    /// Manual refresh: always fetches; the only path that re-opens the Codex failure budget.
    public func refreshNow() {
        guard !isStopped else { return }
        refresh(resetFailureBudget: true)
        for report in providerReports {
            refreshProvider(report.platform, force: true)
        }
        refreshDeepSeekStatus(force: true)
    }

    private func refresh(resetFailureBudget: Bool = false) {
        guard !isStopped, !isRefreshing else { return }
        isRefreshing = true
        let service = self.service
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            let outcome = Result<UsageService.FetchResult, Error> {
                try service.fetch(resetFailureBudget: resetFailureBudget)
            }
            await self?.apply(outcome)
        }
    }

    /// Scheduled provider refresh. Platforms whose contract is unconfirmed are skipped by
    /// the engine itself, so an unverified endpoint is never polled on a timer.
    public func refreshProviders(force: Bool) {
        guard !isStopped else { return }
        guard !isProviderRefreshing else { return }
        isProviderRefreshing = true
        providerRefreshTask = Task { [weak self] in
            if force {
                for platform in [ProviderPlatform.deepseek] {
                    await self?.providerEngine.refresh(platform: platform, force: true)
                }
            } else {
                await self?.providerEngine.refreshScheduled()
            }
            self?.finishProviderRefresh()
        }
    }

    private func refreshProvider(_ platform: ProviderPlatform, force: Bool) {
        guard !isStopped else { return }
        isProviderRefreshing = true
        Task { [weak self] in
            await self?.providerEngine.refresh(platform: platform, force: force)
            self?.finishProviderRefresh()
        }
    }

    /// Refreshes the public DeepSeek status page independently from the credential-backed
    /// balance loop. This keeps status visibility useful even when no API key is configured,
    /// while the five-minute freshness window avoids turning a compact panel into a poller.
    private func refreshDeepSeekStatus(force: Bool) {
        guard let reader = deepSeekStatusReader, !isStopped else { return }
        guard deepSeekStatusTask == nil else { return }
        if !force,
           let checkedAt = deepSeekStatusCheckedAt,
           Date().timeIntervalSince(checkedAt) < deepSeekStatusRefreshInterval {
            return
        }

        isDeepSeekStatusRefreshing = true
        deepSeekStatusTask = Task { [weak self] in
            let result: DeepSeekStatusSnapshot
            do {
                result = try await reader.fetchStatus()
            } catch {
                result = .unavailable()
            }
            guard let self, !self.isStopped else { return }
            self.deepSeekStatus = result
            self.deepSeekStatusCheckedAt = result.checkedAt
            self.isDeepSeekStatusRefreshing = false
            self.deepSeekStatusTask = nil
            self.tick += 1
        }
    }

    private func finishProviderRefresh() {
        guard !isStopped else { return }
        isProviderRefreshing = engineHasWork()
        publishProviderReports()
        tick += 1
    }

    private func engineHasWork() -> Bool {
        return [ProviderPlatform.deepseek].contains { providerEngine.isFetching($0) }
    }

    private func publishProviderReports() {
        providerReports = providerEngine.allReports()
    }

    private func apply(_ outcome: Result<UsageService.FetchResult, Error>) {
        // A cancelled or stopped view model must not publish state after teardown.
        guard !isStopped, !Task.isCancelled else {
            isRefreshing = false
            return
        }
        isRefreshing = false
        connectionState = service.connectionState
        switch outcome {
        case .success(let result):
            // `UsageDisplay` decides live vs cached from isLive and snapshot.source, so a
            // cached result can never be presented as live even when its error is nil.
            let display = UsageDisplay(fetchResult: result)
            Diagnostics.log("display \(display.diagnosticLabel)")
            displayState = display
            codexAccount = result.account
            codexAccountAvailable = result.account?.displayEmail != nil
        case .failure(let error):
            let usageError = (error as? UsageError) ?? .rpcFailed(.other)
            Diagnostics.log("display unavailable: \(usageError.debugSummary)")
            displayState = UsageDisplay(error: usageError, cached: service.cachedSnapshotForCurrentAccount())
            codexAccount = nil
            codexAccountAvailable = false
        }
        tick += 1
    }

    // MARK: - Credentials

    /// Saves a DeepSeek API key and verifies it immediately against the official read-only
    /// balance endpoint (v1.1 requirement 5). The reading owns the keychain write; the view
    /// model holds no second store that could be left unconnected (Round 6).
    ///
    /// Feedback is explicit from the first click. The input field may only be cleared when
    /// this returns true (the keychain accepted the key); verification then continues
    /// asynchronously and updates `credentialFeedback`.
    @discardableResult
    public func saveDeepSeekKey(_ key: String) -> Bool {
        guard let reading = engineReading(.deepseek) as? DeepSeekReading else {
            // Unreachable with the production engine wiring; reported, never silent.
            setFeedback(.saveFailed(platform: .deepseek))
            return false
        }
        setFeedback(.saving(platform: .deepseek))
        do {
            try reading.storeAPIKey(key)
        } catch {
            Diagnostics.log("credential save failed")
            setFeedback(.saveFailed(platform: .deepseek))
            return false
        }
        publishProviderReports()
        verifyAfterCredentialChange(platform: .deepseek)
        return true
    }

    /// Deletes the stored DeepSeek key, its cached numbers and any auth suspension
    /// (Round 6: the form says so instead of failing silently). A failed removal is reported
    /// as a failure, never as a completed disconnect (KEYCHAIN_REVISION_PLAN.md P1.8).
    @discardableResult
    public func deleteDeepSeekKey() -> Bool {
        if let failure = providerEngine.disconnect(platform: .deepseek) {
            setFeedback(.disconnectFailed(platform: .deepseek))
            publishProviderReports()
            Diagnostics.log("credential delete failed: \(failure.debugSummary)")
            return false
        }
        publishProviderReports()
        setFeedback(.deleted(platform: .deepseek))
        return true
    }

    @discardableResult
    public func disconnectDeepSeek() -> Bool {
        if let failure = providerEngine.disconnect(platform: .deepseek) {
            setFeedback(.disconnectFailed(platform: .deepseek))
            publishProviderReports()
            Diagnostics.log("credential delete failed: \(failure.debugSummary)")
            return false
        }
        publishProviderReports()
        setFeedback(.deleted(platform: .deepseek))
        return true
    }

    /// The connect action after a credential change reads the documented balance endpoint.
    private func verifyAfterCredentialChange(platform: ProviderPlatform) {
        setFeedback(.verifying(platform: platform))
        isProviderRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            _ = await self.providerEngine.reconnect(platform: platform)
            self.finishProviderRefresh()
            self.setFeedback(CredentialFeedback(report: self.providerEngine.report(for: platform)))
        }
    }

    // MARK: - Credential authorisation

    /// The only path that may put a keychain dialog on screen, and only because the user
    /// pressed a button. One press, one read per credential; nothing here is on a timer
    /// (KEYCHAIN_REVISION_PLAN.md P1.4).
    public func authorizeCredentialAccess(_ platform: ProviderPlatform) {
        setFeedback(.authorizing(platform: platform))
        isProviderRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.providerEngine.authorizeCredentialAccess(platform: platform)
            guard granted else {
                self.setFeedback(.authorizationDenied(platform: platform))
                self.publishProviderReports()
                self.finishProviderRefresh()
                return
            }
            _ = await self.providerEngine.reconnect(platform: platform)
            self.finishProviderRefresh()
            self.setFeedback(CredentialFeedback(report: self.providerEngine.report(for: platform)))
        }
    }

    // MARK: - Credential feedback

    /// Flips the call-level credential diagnostics and records the change, so a log segment
    /// always says when and why it started.
    public func setCredentialDiagnostics(_ enabled: Bool) {
        CredentialAccessLog.isEnabled = enabled
        isCredentialDiagnosticOn = enabled
        CredentialAccessLog.note(enabled ? "diagnostics enabled" : "diagnostics disabled")
    }

    /// Where the credential diagnostics are written, for display in the panel.
    public var credentialDiagnosticPath: String? {
        return CredentialAccessLog.logFileURL?.path
    }

    private func setFeedback(_ feedback: CredentialFeedback) {
        credentialFeedback[feedback.platform] = feedback
    }

    /// The feedback to show in `platform`'s settings form, or nil when there is nothing
    /// to say.
    public func credentialFeedback(for platform: ProviderPlatform) -> CredentialFeedback? {
        return credentialFeedback[platform]
    }

    private func engineReading(_ platform: ProviderPlatform) -> ProviderReading? {
        return providerEngine.reading(for: platform)
    }

}

/// Fixed-vocabulary feedback for the credential settings forms (Round 6 requirement 2).
///
/// Every state a save/verify/delete cycle can end in has exactly one entry here, with one
/// fixed display text. The texts never quote provider responses, system keychain errors or
/// credential material — only what the user needs to decide the next step.
public enum CredentialFeedback: Equatable, Sendable {

    /// The keychain write is running.
    case saving(platform: ProviderPlatform)
    /// Stored locally; the official read-only balance endpoint is being asked.
    case verifying(platform: ProviderPlatform)
    /// The endpoint answered and the balance is on display.
    case connected(platform: ProviderPlatform)
    /// 401/403: the key (or session) was rejected. Not a network problem.
    case invalidCredential(platform: ProviderPlatform)
    /// The keychain write itself failed. The input stays for retry.
    case saveFailed(platform: ProviderPlatform)
    /// Stored locally, but the verification could not complete right now (offline,
    /// timeout, server error). Not an authentication verdict.
    case savedUnverified(platform: ProviderPlatform)
    /// Credential removed, caches cleared, not connected.
    case deleted(platform: ProviderPlatform)
    /// The user asked for a credential read; the system dialog may be on screen.
    case authorizing(platform: ProviderPlatform)
    /// The credential is stored but unreadable without the user's decision. Never rendered
    /// as "nothing stored" (KEYCHAIN_REVISION_PLAN.md P1.8).
    case authorizationRequired(platform: ProviderPlatform)
    /// The user declined, or the request was cancelled. The credential is untouched.
    case authorizationDenied(platform: ProviderPlatform)
    /// The credential could not be removed, so the account is still connected.
    case disconnectFailed(platform: ProviderPlatform)

    public var platform: ProviderPlatform {
        switch self {
        case .saving(let platform), .verifying(let platform), .connected(let platform),
             .invalidCredential(let platform), .saveFailed(let platform),
             .savedUnverified(let platform), .deleted(let platform),
             .authorizing(let platform), .authorizationRequired(let platform),
             .authorizationDenied(let platform), .disconnectFailed(let platform):
            return platform
        }
    }

    /// True when the state should draw attention (warning colour), false for neutral states.
    public var needsAttention: Bool {
        switch self {
        case .invalidCredential, .saveFailed, .savedUnverified,
             .authorizationRequired, .authorizationDenied, .disconnectFailed:
            return true
        default:
            return false
        }
    }

    public var displayText: String {
        switch self {
        case .saving:
            return "正在保存…"
        case .verifying:
            return "已保存，正在验证余额…"
        case .connected:
            return "已连接，余额已验证"
        case .invalidCredential:
            return "Key 无效或已被拒绝，请检查后重试"
        case .saveFailed:
            return "保存失败：本机钥匙串写入未成功，请重试"
        case .savedUnverified:
            return "Key 已保存在本机，暂时无法验证余额（网络或服务不可用）"
        case .deleted:
            return "已删除，未连接"
        case .authorizing:
            return "正在请求钥匙串授权，请在系统对话框中选择允许…"
        case .authorizationRequired:
            return "凭证已保存在钥匙串，需要授权后才能读取。点「授权读取」并在系统对话框中选择允许。"
        case .authorizationDenied:
            return "已拒绝或取消钥匙串访问。凭证仍保留在钥匙串中，可稍后重新授权。"
        case .disconnectFailed:
            return "断开失败：凭证仍保留在钥匙串中，请稍后重试。"
        }
    }

    /// Maps a finished connection report onto the feedback vocabulary. Fixed categories
    /// only: the mapping reads the engine's `ProviderConnectionState`/`ProviderFailure`,
    /// never provider text.
    init(report: ProviderReport) {
        let platform = report.platform
        switch report.connection {
        case .connected:
            self = .connected(platform: platform)
        case .authSuspended:
            self = .invalidCredential(platform: platform)
        case .unverified:
            self = .savedUnverified(platform: platform)
        case .connecting:
            self = .verifying(platform: platform)
        case .notConfigured:
            // Only reachable if the credential vanished mid-flight; treated as a failed
            // cycle rather than an invented success.
            self = .saveFailed(platform: platform)
        case .needsAuthorization:
            // The credential is there; the system dialog has not been answered. Never
            // reported as "save failed", which would invite overwriting a stored key.
            self = .authorizationRequired(platform: platform)
        case .stale, .unavailable:
            // A previous value may still be on display, but this verification did not
            // complete: the key is stored locally either way.
            self = .savedUnverified(platform: platform)
        }
    }
}

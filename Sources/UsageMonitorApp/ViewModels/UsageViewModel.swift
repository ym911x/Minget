import AppKit
import Foundation
import Combine
import UsageMonitorCore

/// Drives the menu bar UI and the detail panel.
///
/// Three independent refresh loops live here:
/// - two ChatGPT profiles, every 60 seconds, each on its own long-lived `codex app-server`
///   child under its own `CODEX_HOME`. Both profiles are refreshed in parallel inside one
///   cycle, so one slow or signed-out account cannot delay the other
///   (REQUIREMENTS.md §4.1, IMPLEMENTATION_TASKS.md §2);
/// - DeepSeek, every 5 minutes, over HTTPS with its own credential;
/// - the DeepSeek public status page, every 5 minutes, unauthenticated.
///
/// All fetches run off the main thread; `stop()` hands both drains to a background queue and
/// reports completion, so the application can defer termination until every owned child is
/// quiescent.
@MainActor
public final class UsageViewModel: ObservableObject {

    // MARK: ChatGPT profiles

    /// One entry per enabled profile, in the fixed order account A, account B. A single
    /// `displayState`/`codexAccount` pair is deliberately gone: it could only ever describe
    /// one account.
    @Published public private(set) var profileStates: [CodexProfileViewState] = []

    // MARK: Providers

    /// One report per detail-panel platform, in display order.
    @Published public private(set) var providerReports: [ProviderReport] = []
    /// The latest unauthenticated observation from DeepSeek's public status page. A failed
    /// page read remains visibly unavailable; it is never converted into a healthy state.
    @Published public private(set) var deepSeekStatus = DeepSeekStatusSnapshot.unavailable()

    // MARK: Shared

    /// True while a ChatGPT refresh cycle is in flight (any profile).
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isProviderRefreshing = false
    @Published public private(set) var isDeepSeekStatusRefreshing = false
    /// Per-platform, fixed-vocabulary feedback for the credential settings forms (Round 6).
    @Published public private(set) var credentialFeedback: [ProviderPlatform: CredentialFeedback] = [:]
    /// Bumped whenever relative timestamps should be re-evaluated (staleness ages).
    @Published public private(set) var tick = 0
    @Published public private(set) var isCredentialDiagnosticOn = CredentialAccessLog.isEnabled

    /// Owns the per-profile runtimes and their services.
    let coordinator: CodexProfilesCoordinator
    /// Menu bar source and DeepSeek currency choice. Display preferences only.
    let menuBarPreferences: MenuBarPreferences
    private let fireService: ChatGPTFireService

    /// Non-optional by design (Round 6): a view model without an engine has no save path
    /// at all. Internal (not private) so the wiring tests can read engine state directly.
    let providerEngine: ProviderRefreshEngine

    private let refreshInterval: TimeInterval
    private let panelOpenRefreshAge: TimeInterval
    private let providerRefreshInterval: TimeInterval
    private let providerPanelOpenRefreshAge: TimeInterval
    private let deepSeekStatusReader: DeepSeekStatusReading?
    private let deepSeekStatusRefreshInterval: TimeInterval = 5 * 60

    /// How long to wait after a successful request before the confirming refresh, and how
    /// long to wait before the single retry. Fixed by REQUIREMENTS.md §7.2; injectable so
    /// tests do not have to sleep for real.
    private let fireConfirmDelay: TimeInterval
    private let fireRetryDelay: TimeInterval

    /// A new 5-hour window counts as confirmed only when the service's reset time moved
    /// forward by at least this much. `exit 0` alone proves nothing.
    static let windowConfirmationThreshold: TimeInterval = 60

    private var timer: AnyCancellable?
    private var providerTimer: AnyCancellable?
    private var clockTimer: AnyCancellable?
    /// Re-publishes when the menu bar source or the DeepSeek currency changes, so the status
    /// item re-measures its width immediately instead of waiting for the next data change.
    private var menuBarPreferenceObserver: AnyCancellable?
    private var clockObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var refreshTask: Task<Void, Never>?
    private var providerRefreshTask: Task<Void, Never>?
    private var deepSeekStatusTask: Task<Void, Never>?
    private var fireTasks: [String: Task<Void, Never>] = [:]
    private var deepSeekStatusCheckedAt: Date?
    private(set) var isStopped = false

    /// Designated initializer: the production composition path.
    public init(coordinator: CodexProfilesCoordinator,
                providerEngine: ProviderRefreshEngine,
                menuBarPreferences: MenuBarPreferences = .shared,
                fireService: ChatGPTFireService = ChatGPTFireService(),
                refreshInterval: TimeInterval = 60,
                panelOpenRefreshAge: TimeInterval = UsageCache.maxAgeForPanelOpenRefresh,
                providerRefreshInterval: TimeInterval = ProviderRefreshEngine.defaultRefreshInterval,
                providerPanelOpenRefreshAge: TimeInterval = ProviderRefreshEngine.defaultPanelOpenRefreshAge,
                deepSeekStatusReader: DeepSeekStatusReading? = nil,
                fireConfirmDelay: TimeInterval = 2,
                fireRetryDelay: TimeInterval = 5) {
        self.coordinator = coordinator
        self.providerEngine = providerEngine
        self.menuBarPreferences = menuBarPreferences
        self.fireService = fireService
        self.refreshInterval = refreshInterval
        self.panelOpenRefreshAge = panelOpenRefreshAge
        self.providerRefreshInterval = providerRefreshInterval
        self.providerPanelOpenRefreshAge = providerPanelOpenRefreshAge
        self.deepSeekStatusReader = deepSeekStatusReader
        self.fireConfirmDelay = fireConfirmDelay
        self.fireRetryDelay = fireRetryDelay
        publishProfileStates()
        publishProviderReports()
    }

    /// Single-service convenience, used by tests that only need one account.
    public convenience init(service: UsageService,
                            providerEngine: ProviderRefreshEngine,
                            menuBarPreferences: MenuBarPreferences = .shared,
                            fireService: ChatGPTFireService = ChatGPTFireService(),
                            refreshInterval: TimeInterval = 60,
                            panelOpenRefreshAge: TimeInterval = UsageCache.maxAgeForPanelOpenRefresh,
                            providerRefreshInterval: TimeInterval = ProviderRefreshEngine.defaultRefreshInterval,
                            providerPanelOpenRefreshAge: TimeInterval = ProviderRefreshEngine.defaultPanelOpenRefreshAge,
                            deepSeekStatusReader: DeepSeekStatusReading? = nil,
                            fireConfirmDelay: TimeInterval = 2,
                            fireRetryDelay: TimeInterval = 5) {
        self.init(coordinator: CodexProfilesCoordinator(profiles: [ChatGPTAccountProfile.chatGPTA],
                                                          makeService: { _ in service }),
                  providerEngine: providerEngine,
                  menuBarPreferences: menuBarPreferences,
                  fireService: fireService,
                  refreshInterval: refreshInterval,
                  panelOpenRefreshAge: panelOpenRefreshAge,
                  providerRefreshInterval: providerRefreshInterval,
                  providerPanelOpenRefreshAge: providerPanelOpenRefreshAge,
                  deepSeekStatusReader: deepSeekStatusReader,
                  fireConfirmDelay: fireConfirmDelay,
                  fireRetryDelay: fireRetryDelay)
    }

    // MARK: - Derived values

    /// The state of one profile, or nil when the identifier is unknown.
    public func profileState(_ profileID: String) -> CodexProfileViewState? {
        profileStates.first { $0.profile.id == profileID }
    }

    /// Everything the status item draws for one mode and one clock reading.
    ///
    /// `now` is read per frame rather than accumulated, so sleep, a delayed main thread or a
    /// system clock change can never leave the rows drifting away from the real time.
    public func menuBarContent(for mode: MenuBarSpaceMode, now: Date = Date()) -> MenuBarContent {
        MenuBarContentBuilder.make(source: menuBarSource(), now: now, mode: mode)
    }

    /// The single resolved source the menu bar currently shows.
    ///
    /// The selection is validated when it is loaded, so a stale or hand-edited preference
    /// falls back to account A rather than to "no source".
    public func menuBarSource() -> MenuBarSource {
        switch menuBarPreferences.selection {
        case .profile(let id):
            if let state = profileStates.first(where: { $0.profile.id == id }) {
                return .chatGPT(shortLabel: state.profile.shortLabel,
                                display: state.display,
                                connectionState: state.connectionState)
            }
            let fallback = profileStates.first
            return .chatGPT(shortLabel: fallback?.profile.shortLabel ?? "",
                            display: fallback?.display ?? .unavailable(.rpcFailed(.other)),
                            connectionState: fallback?.connectionState ?? .idle)
        case .deepSeek:
            return .deepSeek(deepSeekMenuBarContent())
        }
    }

    /// Identity of everything that can change the status item's width, across all modes. The
    /// countdown is deliberately absent: the item is re-measured only when its content or its
    /// warning changes, not once a second.
    public var menuBarSizeSignature: String {
        let now = Date()
        return MenuBarSpaceMode.allCases
            .map { menuBarContent(for: $0, now: now).sizeSignature }
            .joined(separator: "|")
    }

    /// Cached data is always shown with a warning; it must never read as live data.
    public var isStale: Bool { profileStates.contains { $0.isStale } }

    /// Every timestamp the header's global update line must aggregate: both ChatGPT profiles
    /// and the visible provider cards (REQUIREMENTS.md §5.1, IMPLEMENTATION_TASKS.md §4).
    public var codexSnapshotDates: [Date] {
        profileStates.compactMap { $0.snapshot?.fetchedAt }
    }

    /// Currencies the current DeepSeek response actually reports, for the settings picker.
    public var deepSeekCurrencies: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for balance in deepSeekReport?.balances ?? [] {
            guard let currency = balance.currency, !currency.isEmpty else { continue }
            guard !seen.contains(currency.uppercased()) else { continue }
            seen.insert(currency.uppercased())
            result.append(currency)
        }
        return result.sorted()
    }

    private var deepSeekReport: ProviderReport? {
        providerReports.first { $0.platform == .deepseek }
    }

    /// The DeepSeek half of the menu bar, resolved from the current report.
    ///
    /// A stale report keeps its amount and adds the warning marker; a report with nothing
    /// attributable shows `DS —` with a warning. A zero balance can never be produced here.
    private func deepSeekMenuBarContent() -> MenuBarDeepSeekContent {
        guard let report = deepSeekReport else {
            return MenuBarDeepSeekContent(currency: nil, amount: nil, isCached: false)
        }
        let isCached = report.connection == .stale
        let usable = report.connection == .connected || report.connection == .stale
        guard usable, !report.balances.isEmpty else {
            return MenuBarDeepSeekContent(currency: nil, amount: nil, isCached: isCached)
        }
        let resolution = DeepSeekMenuBarResolver.resolve(balances: report.balances,
                                                         savedCurrency: menuBarPreferences.deepSeekCurrency)
        return MenuBarDeepSeekContent(currency: resolution.currency,
                                      amount: resolution.amount,
                                      isCached: isCached)
    }

    // MARK: - Lifecycle

    /// Starts the app: immediate refresh of both profiles, then on both schedules.
    public func start() {
        Diagnostics.log("viewmodel start")
        isStopped = false
        scheduleTimers()
        observeClockChanges()
        observeMenuBarPreferences()
        clockTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick += 1 }
        refresh()
        refreshProviders(force: false)
        refreshDeepSeekStatus(force: false)
        primeCredentialAccess()
    }

    /// The menu bar source is a separate observable object, so a change to it must still make
    /// the status item re-render and re-measure. `tick` is published, which is what
    /// `StatusItemController.noteContentMayHaveChanged` listens for.
    private func observeMenuBarPreferences() {
        guard menuBarPreferenceObserver == nil else { return }
        menuBarPreferenceObserver = menuBarPreferences.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.tick += 1 }
                }
            }
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
        for platform in [ProviderPlatform.deepseek, .commandcode] {
            switch engineReading(platform) {
            case let reading as DeepSeekReading: reading.onCredentialPhaseChange = publish
            case let reading as CommandCodeReading: reading.onCredentialPhaseChange = publish
            default: break
            }
        }
    }

    /// Recomputes the displayed countdowns immediately when the machine wakes or the system
    /// clock is changed, instead of waiting for the next one-second tick.
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

    /// Cancels in-flight work, stops timers and joins *both* profile drains on a dedicated
    /// queue. `completion` is called on that queue once every service reports quiescence (or
    /// once its bounded drain timed out).
    ///
    /// The join happens off the main actor on purpose: the drains block, and waiting for them
    /// on the main actor would deadlock `applicationShouldTerminate`, which is itself waiting
    /// on this completion.
    public func stop(completion: (() -> Void)? = nil) {
        guard !isStopped else {
            completion?()
            return
        }
        isStopped = true
        isRefreshing = false
        isProviderRefreshing = false
        isDeepSeekStatusRefreshing = false
        timer?.cancel()
        providerTimer?.cancel()
        clockTimer?.cancel()
        menuBarPreferenceObserver?.cancel()
        timer = nil
        providerTimer = nil
        clockTimer = nil
        menuBarPreferenceObserver = nil
        stopObservingClockChanges()
        providerRefreshTask?.cancel()
        providerRefreshTask = nil
        deepSeekStatusTask?.cancel()
        deepSeekStatusTask = nil
        for task in fireTasks.values { task.cancel() }
        fireTasks.removeAll()

        let task = refreshTask
        refreshTask = nil
        let coordinator = self.coordinator
        let fireService = self.fireService
        joinQueue.async {
            task?.cancel()
            // `fire()` blocks in `Process.waitUntilExit()`, so cancelling the task above does
            // not reach the child. Terminating it explicitly is what keeps a `codex exec`
            // from outliving the app (REVISION_SPEC.md §9.1).
            fireService.stopAll()
            coordinator.stop()
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
    /// rule, ChatGPT at 30 seconds per profile and the providers at 60 seconds.
    public func panelWillOpen() {
        guard !isStopped else { return }
        panelWillOpenCodex()
        panelWillOpenProviders()
        refreshDeepSeekStatus(force: false)
    }

    /// A cycle is due when *any* profile has no data or has data older than the open-age.
    /// Both profiles are then refreshed together, so the two cards never disagree about
    /// which cycle they belong to.
    private func panelWillOpenCodex() {
        let due = coordinator.runtimes.contains { runtime in
            guard let snapshot = runtime.state().snapshot else { return true }
            return UsageCache.isStale(fetchedAt: snapshot.fetchedAt, maxAge: panelOpenRefreshAge)
        }
        if due { refresh() }
    }

    private func panelWillOpenProviders() {
        for platform in [ProviderPlatform.deepseek, .commandcode] {
            guard providerEngine.shouldRefreshOnPanelOpen(platform) else { continue }
            refreshProvider(platform, force: false)
        }
    }

    // MARK: - Refreshing

    /// Manual refresh: always fetches both profiles and every provider; the only path that
    /// re-opens the Codex failure budget.
    public func refreshNow() {
        guard !isStopped else { return }
        refresh(resetFailureBudget: true)
        for report in providerReports {
            refreshProvider(report.platform, force: true)
        }
        refreshDeepSeekStatus(force: true)
    }

    /// Refreshes every profile in parallel inside one cycle. No request is stacked: a slow
    /// profile simply finishes later than the other.
    private func refresh(resetFailureBudget: Bool = false) {
        guard !isStopped, !isRefreshing else { return }
        isRefreshing = true
        let coordinator = self.coordinator
        let profileIDs = coordinator.profileIDs
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for profileID in profileIDs {
                    group.addTask {
                        _ = coordinator.fetch(profileID: profileID,
                                              resetFailureBudget: resetFailureBudget)
                    }
                }
                await group.waitForAll()
            }
            await self?.applyProfileStates()
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
                for platform in [ProviderPlatform.deepseek, .commandcode] {
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
    /// balance loop, so status visibility stays useful even with no API key configured.
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
        return [ProviderPlatform.deepseek, .commandcode].contains { providerEngine.isFetching($0) }
    }

    private func publishProviderReports() {
        providerReports = providerEngine.allReports()
    }

    /// Publishes the current runtime state of both profiles as value snapshots.
    private func publishProfileStates() {
        profileStates = coordinator.runtimes.map { CodexProfileViewState(runtime: $0.state()) }
    }

    private func applyProfileStates() {
        // A cancelled or stopped view model must not publish state after teardown.
        guard !isStopped, !Task.isCancelled else {
            isRefreshing = false
            return
        }
        isRefreshing = false
        publishProfileStates()
        tick += 1
    }

    // MARK: - Fire

    /// Runs one manual 5-hour fire for the profile. The caller must already have shown the
    /// fixed confirmation; this method never asks again.
    ///
    /// The result the card shows separates "the request ran" from "a new window was
    /// confirmed": only a refresh that moves the service's 5-hour `resetsAt` forward by at
    /// least `windowConfirmationThreshold` produces the confirmed text.
    public func fire(profileID: String) {
        guard !isStopped, let runtime = coordinator.runtime(for: profileID) else { return }
        let current = runtime.state()
        guard !current.isFiring else { return }

        let previousFiveHourReset = current.display.snapshot?.fiveHour?.resetsAt
        coordinator.recordFireStart(profileID: profileID)
        publishProfileStates()
        tick += 1

        let service = fireService
        let profile = runtime.profile
        fireTasks[profileID] = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = service.fire(profile: profile)
            await self?.finishFire(profileID: profileID,
                                   outcome: outcome,
                                   previousFiveHourReset: previousFiveHourReset)
        }
    }

    private func finishFire(profileID: String,
                            outcome: ChatGPTFireProcessOutcome,
                            previousFiveHourReset: Date?) async {
        guard !isStopped else { return }

        if let immediate = outcome.immediateResult {
            coordinator.recordFireFinished(profileID: profileID, result: immediate)
            fireTasks[profileID] = nil
            publishProfileStates()
            tick += 1
            return
        }

        // The request ran. Wait, then force-refresh this profile only — the other account's
        // window was not touched by this request.
        try? await Task.sleep(nanoseconds: Self.nanoseconds(fireConfirmDelay))
        guard !isStopped else { return }
        var newReset = await fetchFiveHourReset(profileID: profileID)
        if newReset == nil {
            try? await Task.sleep(nanoseconds: Self.nanoseconds(fireRetryDelay))
            guard !isStopped else { return }
            newReset = await fetchFiveHourReset(profileID: profileID)
        }

        let confirmed: Bool
        if let newReset, let previousFiveHourReset {
            confirmed = newReset.timeIntervalSince(previousFiveHourReset) >= Self.windowConfirmationThreshold
        } else {
            // Without a before/after pair there is no evidence a new window started, so the
            // card reports the request alone rather than inferring success.
            confirmed = false
        }

        coordinator.recordFireFinished(profileID: profileID,
                                       result: confirmed ? .requestSucceededWindowConfirmed
                                                         : .requestSucceededWindowUnchanged)
        fireTasks[profileID] = nil
        publishProfileStates()
        tick += 1
    }

    /// One forced refresh of a single profile, returning its new 5-hour reset time.
    ///
    /// Only a *live* result counts (REVISION_SPEC.md §9.2). `UsageService.fetch` returns
    /// `.success` for a cache-served snapshot too, and a cached `resetsAt` is last cycle's
    /// number: treating it as freshly observed would let the card claim a new window that was
    /// never confirmed. A cached success therefore reports "no evidence" and the caller
    /// retries once.
    private func fetchFiveHourReset(profileID: String) async -> Date? {
        let coordinator = self.coordinator
        return await Task.detached(priority: .userInitiated) {
            let outcome = coordinator.fetch(profileID: profileID, resetFailureBudget: true)
            guard case .success(let result) = outcome, result.isLive else { return nil }
            return result.snapshot.fiveHour?.resetsAt
        }.value
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    // MARK: - Credentials

    /// Saves a DeepSeek API key and verifies it immediately against the official read-only
    /// balance endpoint. The reading owns the keychain write; the view model holds no second
    /// store that could be left unconnected (Round 6).
    @discardableResult
    public func saveDeepSeekKey(_ key: String) -> Bool {
        guard let reading = engineReading(.deepseek) as? DeepSeekReading else {
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

    @discardableResult
    public func saveCommandCodeKey(_ key: String) -> Bool {
        guard let reading = engineReading(.commandcode) as? CommandCodeReading else {
            setFeedback(.saveFailed(platform: .commandcode)); return false
        }
        setFeedback(.saving(platform: .commandcode))
        do { try reading.storeAPIKey(key) } catch {
            Diagnostics.log("commandcode credential save failed")
            setFeedback(.saveFailed(platform: .commandcode)); return false
        }
        publishProviderReports()
        verifyAfterCredentialChange(platform: .commandcode)
        return true
    }

    /// Deletes the stored DeepSeek key, its cached numbers and any auth suspension.
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

    @discardableResult
    public func deleteCommandCodeKey() -> Bool {
        if let failure = providerEngine.disconnect(platform: .commandcode) {
            setFeedback(.disconnectFailed(platform: .commandcode))
            publishProviderReports()
            Diagnostics.log("commandcode credential delete failed: \(failure.debugSummary)")
            return false
        }
        publishProviderReports()
        setFeedback(.deleted(platform: .commandcode))
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
    /// pressed a button. One press, one read per credential.
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

    /// Flips the call-level credential diagnostics and records the change.
    public func setCredentialDiagnostics(_ enabled: Bool) {
        CredentialAccessLog.isEnabled = enabled
        isCredentialDiagnosticOn = enabled
        CredentialAccessLog.note(enabled ? "diagnostics enabled" : "diagnostics disabled")
    }

    public var credentialDiagnosticPath: String? {
        return CredentialAccessLog.logFileURL?.path
    }

    private func setFeedback(_ feedback: CredentialFeedback) {
        credentialFeedback[feedback.platform] = feedback
    }

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

    case saving(platform: ProviderPlatform)
    case verifying(platform: ProviderPlatform)
    case connected(platform: ProviderPlatform)
    case invalidCredential(platform: ProviderPlatform)
    case saveFailed(platform: ProviderPlatform)
    case savedUnverified(platform: ProviderPlatform)
    case deleted(platform: ProviderPlatform)
    case authorizing(platform: ProviderPlatform)
    case authorizationRequired(platform: ProviderPlatform)
    case authorizationDenied(platform: ProviderPlatform)
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
            self = .saveFailed(platform: platform)
        case .needsAuthorization:
            self = .authorizationRequired(platform: platform)
        case .stale, .unavailable:
            self = .savedUnverified(platform: platform)
        }
    }
}

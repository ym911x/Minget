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
    @Published private(set) var commandCodeFireState = CommandCodeFireViewState()
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
    /// Menu bar source, currency and menu-bar-only cadence preferences. No credentials or
    /// provider caches are stored here.
    let menuBarPreferences: MenuBarPreferences
    private let fireService: ChatGPTFireService
    private let commandCodeFireService: CommandCodeFireService
    let fireSchedules: FireSchedulePreferences

    /// Non-optional by design (Round 6): a view model without an engine has no save path
    /// at all. Internal (not private) so the wiring tests can read engine state directly.
    let providerEngine: ProviderRefreshEngine

    private let baseRefreshInterval: TimeInterval
    private let panelOpenRefreshAge: TimeInterval
    private let providerRefreshInterval: TimeInterval
    private let providerPanelOpenRefreshAge: TimeInterval
    private let deepSeekStatusReader: DeepSeekStatusReading?
    private let deepSeekStatusRefreshInterval: TimeInterval = 5 * 60
    /// How often the detail page re-evaluates relative timestamps. 30 seconds by default:
    /// the per-second countdown is drawn from `Date()` on demand, so a 1-second tick only
    /// paid for a full page recompute (REQUIREMENTS.md §4.1).
    private let clockInterval: TimeInterval
    private var lastScheduledCodexRefreshAt: Date?
    private var lastWakeRefreshAt: Date?

    /// Refresh cadence for the ChatGPT timer, chosen from the known reset times.
    ///
    /// Near a reset the windows move fast and deserve a 30-second poll; far from any
    /// reset the numbers barely change and 120 seconds is enough; with nothing known
    /// yet the 1.3.1 behaviour of 60 seconds is kept so the first screen is not delayed.
    public static let baseCodexRefreshInterval: TimeInterval = 60
    public static let nearResetCodexRefreshInterval: TimeInterval = 30
    public static let idleCodexRefreshInterval: TimeInterval = 120
    public static let nearResetHorizon: TimeInterval = 10 * 60
    /// Minimum gap between a wake-triggered refresh and the next scheduled one, so the
    /// two cannot stack the same request twice.
    public static let wakeRefreshCooldown: TimeInterval = 30

    public static func codexRefreshInterval(snapshots: [UsageSnapshot?], now: Date = Date(),
                                            baseInterval: TimeInterval = 60) -> TimeInterval {
        var hasData = false
        for snapshot in snapshots {
            for resetsAt in [snapshot?.fiveHour?.resetsAt, snapshot?.weekly?.resetsAt] {
                guard let resetsAt else { continue }
                hasData = true
                let delta = resetsAt.timeIntervalSince(now)
                if delta.isFinite, delta >= 0, delta <= nearResetHorizon {
                    return nearResetCodexRefreshInterval
                }
            }
            if snapshot != nil { hasData = true }
        }
        return hasData ? idleCodexRefreshInterval : baseInterval
    }

    /// How long to wait after a successful request before the confirming refresh, and how
    /// long to wait before the single retry. Fixed by REQUIREMENTS.md §7.2; injectable so
    /// tests do not have to sleep for real.
    private let fireConfirmDelay: TimeInterval
    private let fireRetryDelay: TimeInterval

    /// A new 5-hour window counts as confirmed only when the service's reset time moved
    /// forward by at least this much. `exit 0` alone proves nothing. The number itself lives
    /// with the confirmation rule in core, so the card and the classifier share one constant.
    static let windowConfirmationThreshold: TimeInterval = FireWindowConfirmation.threshold

    private var timer: AnyCancellable?
    private var providerTimer: AnyCancellable?
    private var menuBarRefreshTimer: AnyCancellable?
    private var clockTimer: AnyCancellable?
    /// Re-publishes when the menu bar source or the DeepSeek currency changes, so the status
    /// item re-measures its width immediately instead of waiting for the next data change.
    private var menuBarPreferenceObserver: AnyCancellable?
    private var clockObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var refreshTask: Task<Void, Never>?
    private var providerRefreshTask: Task<Void, Never>?
    private var menuBarRefreshTask: Task<Void, Never>?
    private var deepSeekStatusTask: Task<Void, Never>?
    private var fireTasks: [String: Task<Void, Never>] = [:]
    private var deepSeekStatusCheckedAt: Date?
    private(set) var isStopped = false

    /// Designated initializer: the production composition path.
    public init(coordinator: CodexProfilesCoordinator,
                providerEngine: ProviderRefreshEngine,
                menuBarPreferences: MenuBarPreferences = .shared,
                fireService: ChatGPTFireService = ChatGPTFireService(),
                commandCodeFireService: CommandCodeFireService = CommandCodeFireService(),
                fireSchedules: FireSchedulePreferences? = nil,
                refreshInterval: TimeInterval = 60,
                panelOpenRefreshAge: TimeInterval = UsageCache.maxAgeForPanelOpenRefresh,
                providerRefreshInterval: TimeInterval = ProviderRefreshEngine.defaultRefreshInterval,
                providerPanelOpenRefreshAge: TimeInterval = ProviderRefreshEngine.defaultPanelOpenRefreshAge,
                deepSeekStatusReader: DeepSeekStatusReading? = nil,
                fireConfirmDelay: TimeInterval = 2,
                fireRetryDelay: TimeInterval = 5,
                clockInterval: TimeInterval = 30) {
        self.coordinator = coordinator
        self.providerEngine = providerEngine
        self.menuBarPreferences = menuBarPreferences
        self.fireService = fireService
        self.commandCodeFireService = commandCodeFireService
        self.fireSchedules = fireSchedules ?? FireSchedulePreferences()
        self.baseRefreshInterval = refreshInterval
        self.panelOpenRefreshAge = panelOpenRefreshAge
        self.providerRefreshInterval = providerRefreshInterval
        self.providerPanelOpenRefreshAge = providerPanelOpenRefreshAge
        self.deepSeekStatusReader = deepSeekStatusReader
        self.fireConfirmDelay = fireConfirmDelay
        self.fireRetryDelay = fireRetryDelay
        self.clockInterval = clockInterval
        publishProfileStates()
        publishProviderReports()
    }

    /// Single-service convenience, used by tests that only need one account.
    public convenience init(service: UsageService,
                            providerEngine: ProviderRefreshEngine,
                            menuBarPreferences: MenuBarPreferences = .shared,
                            fireService: ChatGPTFireService = ChatGPTFireService(),
                            commandCodeFireService: CommandCodeFireService = CommandCodeFireService(),
                            fireSchedules: FireSchedulePreferences? = nil,
                            refreshInterval: TimeInterval = 60,
                            panelOpenRefreshAge: TimeInterval = UsageCache.maxAgeForPanelOpenRefresh,
                            providerRefreshInterval: TimeInterval = ProviderRefreshEngine.defaultRefreshInterval,
                            providerPanelOpenRefreshAge: TimeInterval = ProviderRefreshEngine.defaultPanelOpenRefreshAge,
                            deepSeekStatusReader: DeepSeekStatusReading? = nil,
                            fireConfirmDelay: TimeInterval = 2,
                            fireRetryDelay: TimeInterval = 5,
                            clockInterval: TimeInterval = 30) {
        self.init(coordinator: CodexProfilesCoordinator(profiles: [ChatGPTAccountProfile.chatGPTA],
                                                          makeService: { _ in service }),
                  providerEngine: providerEngine,
                  menuBarPreferences: menuBarPreferences,
                  fireService: fireService,
                  commandCodeFireService: commandCodeFireService,
                  fireSchedules: fireSchedules,
                  refreshInterval: refreshInterval,
                  panelOpenRefreshAge: panelOpenRefreshAge,
                  providerRefreshInterval: providerRefreshInterval,
                  providerPanelOpenRefreshAge: providerPanelOpenRefreshAge,
                  deepSeekStatusReader: deepSeekStatusReader,
                  fireConfirmDelay: fireConfirmDelay,
                  fireRetryDelay: fireRetryDelay,
                  clockInterval: clockInterval)
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

    /// Current adaptive decision for the source shown in the menu bar. A nil interval means
    /// the ordinary detail/provider timer is sufficient and no extra request is scheduled.
    public var currentMenuBarRefreshDecision: MenuBarRefreshDecision {
        let selectedSnapshot: UsageSnapshot?
        let normalInterval: TimeInterval
        switch menuBarPreferences.selection {
        case .profile(let profileID):
            selectedSnapshot = profileState(profileID)?.snapshot
            normalInterval = currentCodexInterval
        case .deepSeek:
            selectedSnapshot = nil
            normalInterval = providerRefreshInterval
        }
        return MenuBarRefreshPolicy.decision(
            selection: menuBarPreferences.selection,
            profileSnapshot: selectedSnapshot,
            deepSeekReport: deepSeekReport,
            deepSeekCurrency: menuBarPreferences.deepSeekCurrency,
            settings: menuBarPreferences.menuBarRefreshSettings,
            normalInterval: normalInterval)
    }

    /// Compact status text used in settings to make the active source and trigger visible.
    public var menuBarRefreshStatusText: String {
        let settings = menuBarPreferences.menuBarRefreshSettings
        guard settings.isEnabled else { return "低额度加速已关闭" }
        let decision = currentMenuBarRefreshDecision
        guard let interval = decision.interval, let trigger = decision.trigger else {
            if menuBarPreferences.selection == .deepSeek,
               settings.deepSeekBalanceThresholdCNY == nil {
                return "DeepSeek 阈值无效，已暂停加速"
            }
            return "当前来源正常，按常规频率刷新"
        }
        return "当前来源每 " + String(Int(interval)) + " 秒刷新 · " + trigger.displayText
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
        clockTimer = Timer.publish(every: clockInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.handleClockTick(date) }
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
                    MainActor.assumeIsolated {
                        self?.tick += 1
                        self?.rescheduleMenuBarRefreshTimer()
                    }
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
            // Scheduled Command Code fire is intentionally evaluated only after the
            // non-interactive Keychain priming pass has settled. Otherwise launch and
            // credential loading can race, causing a due row to miss its catch-up window.
            self.evaluateFireSchedules(at: Date())
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
    /// clock is changed, instead of waiting for the next clock tick. A wake additionally
    /// triggers one throttled refresh so a child that died in sleep is noticed without
    /// waiting for the next scheduled round.
    private func observeClockChanges() {
        guard clockObservers.isEmpty else { return }
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick += 1
                self?.refreshAfterWake()
                self?.evaluateFireSchedules(at: Date())
            }
        }
        let clockChanged = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick += 1
                self?.evaluateFireSchedules(at: Date())
            }
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
        menuBarRefreshTimer?.cancel()
        clockTimer?.cancel()
        menuBarPreferenceObserver?.cancel()
        timer = nil
        providerTimer = nil
        menuBarRefreshTimer = nil
        clockTimer = nil
        menuBarPreferenceObserver = nil
        stopObservingClockChanges()
        providerRefreshTask?.cancel()
        providerRefreshTask = nil
        menuBarRefreshTask?.cancel()
        menuBarRefreshTask = nil
        deepSeekStatusTask?.cancel()
        deepSeekStatusTask = nil
        for task in fireTasks.values { task.cancel() }
        fireTasks.removeAll()

        let task = refreshTask
        refreshTask = nil
        let coordinator = self.coordinator
        let fireService = self.fireService
        let commandCodeFireService = self.commandCodeFireService
        joinQueue.async {
            task?.cancel()
            // `fire()` blocks in `Process.waitUntilExit()`, so cancelling the task above does
            // not reach the child. Terminating it explicitly is what keeps a `codex exec`
            // from outliving the app (REVISION_SPEC.md §9.1).
            fireService.stopAll()
            commandCodeFireService.stop()
            coordinator.stop()
            Diagnostics.log("viewmodel stopped")
            completion?()
        }
    }

    /// Serial queue so repeated stop() calls cannot overlap their drains.
    private let joinQueue = DispatchQueue(label: "usagemonitor.viewmodel.join")

    private func scheduleTimers() {
        rescheduleCodexTimer()
        providerTimer = Timer.publish(every: providerRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshProviders(force: false)
                self?.refreshDeepSeekStatus(force: false)
            }
        rescheduleMenuBarRefreshTimer()
    }

    /// Current cadence for the ChatGPT timer, from the snapshots on hand.
    var currentCodexInterval: TimeInterval {
        Self.codexRefreshInterval(snapshots: coordinator.runtimes.map { $0.state().snapshot },
                                  baseInterval: baseRefreshInterval)
    }

    /// Exposes the configured detail-page clock cadence to deterministic wiring tests.
    /// The timer itself remains private and is still created only by `start()`.
    var configuredClockInterval: TimeInterval { clockInterval }

    /// Exposes whether the menu-bar-only timer is currently installed, without exposing the
    /// timer itself or allowing tests to fire it. This keeps source-switch and teardown
    /// lifecycle checks deterministic instead of waiting 15 real seconds for a tick.
    var configuredMenuBarRefreshInterval: TimeInterval? {
        menuBarRefreshTimer == nil ? nil : lastMenuBarRefreshTimerInterval
    }

    /// Rebuilds the ChatGPT timer only when the cadence actually changed, so a steady
    /// state keeps one subscription instead of churning one per round.
    private func rescheduleCodexTimer() {
        let interval = currentCodexInterval
        if timer != nil, abs(interval - lastCodexTimerInterval) < 0.001 { return }
        timer?.cancel()
        lastCodexTimerInterval = interval
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.scheduledCodexRefresh() }
    }

    private var lastCodexTimerInterval: TimeInterval = 0

    /// Creates an additional timer only while the currently selected source is below its
    /// configured threshold. The ordinary ChatGPT/provider timers remain responsible for all
    /// other accounts and providers.
    private func rescheduleMenuBarRefreshTimer() {
        guard !isStopped else { return }
        guard let interval = currentMenuBarRefreshDecision.interval else {
            menuBarRefreshTimer?.cancel()
            menuBarRefreshTimer = nil
            lastMenuBarRefreshTimerInterval = 0
            return
        }
        if menuBarRefreshTimer != nil,
           abs(interval - lastMenuBarRefreshTimerInterval) < 0.001 {
            return
        }
        menuBarRefreshTimer?.cancel()
        lastMenuBarRefreshTimerInterval = interval
        menuBarRefreshTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshSelectedMenuBarSource() }
    }

    private var lastMenuBarRefreshTimerInterval: TimeInterval = 0

    private func refreshSelectedMenuBarSource() {
        guard !isStopped, menuBarRefreshTask == nil,
              currentMenuBarRefreshDecision.isAccelerated else { return }

        switch menuBarPreferences.selection {
        case .profile(let profileID):
            guard let runtime = coordinator.runtime(for: profileID),
                  !runtime.state().isFetching else { return }
            let coordinator = self.coordinator
            menuBarRefreshTask = Task.detached(priority: .utility) { [weak self] in
                _ = coordinator.fetch(profileID: profileID, resetFailureBudget: false)
                await self?.finishMenuBarProfileRefresh()
            }
        case .deepSeek:
            let engine = providerEngine
            menuBarRefreshTask = Task { [weak self] in
                await engine.refresh(platform: .deepseek, force: false)
                guard let self, !self.isStopped else { return }
                self.finishMenuBarProviderRefresh()
            }
        }
    }

    private func finishMenuBarProfileRefresh() {
        guard !isStopped, !Task.isCancelled else {
            menuBarRefreshTask = nil
            return
        }
        menuBarRefreshTask = nil
        publishProfileStates()
        tick += 1
        rescheduleMenuBarRefreshTimer()
    }

    private func finishMenuBarProviderRefresh() {
        guard !isStopped, !Task.isCancelled else {
            menuBarRefreshTask = nil
            return
        }
        menuBarRefreshTask = nil
        publishProviderReports()
        tick += 1
        rescheduleMenuBarRefreshTimer()
    }

    /// One scheduled round, then a cadence re-check: near a reset the next round comes
    /// sooner, far from any reset it backs off.
    private func scheduledCodexRefresh() {
        guard !isStopped else { return }
        if let lastWake = lastWakeRefreshAt,
           Self.isInsideWakeCooldown(now: Date(), previous: lastWake) {
            return
        }
        lastScheduledCodexRefreshAt = Date()
        refresh()
        rescheduleCodexTimer()
    }

    /// One throttled refresh after sleep: healthy profiles use their existing app-server and
    /// read only rate limits; only an unhealthy client falls back to the ordinary full read.
    /// Neither route re-opens the failure budget.
    func refreshAfterWake(now: Date = Date()) {
        guard !isStopped, !isRefreshing else { return }
        if let lastScheduled = lastScheduledCodexRefreshAt,
           Self.isInsideWakeCooldown(now: now, previous: lastScheduled) {
            return
        }
        if let lastWake = lastWakeRefreshAt,
           Self.isInsideWakeCooldown(now: now, previous: lastWake) {
            return
        }
        lastWakeRefreshAt = now
        isRefreshing = true
        let coordinator = self.coordinator
        let profileIDs = coordinator.profileIDs
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: String?.self) { group in
                for profileID in profileIDs {
                    group.addTask {
                        switch coordinator.probeAfterWake(profileID: profileID) {
                        case .refreshed:
                            return profileID
                        case .needsFullRefresh:
                            _ = coordinator.fetch(profileID: profileID, resetFailureBudget: false)
                            return profileID
                        case .suppressed:
                            return nil
                        }
                    }
                }
                for await completedProfileID in group {
                    if let completedProfileID {
                        await self?.publishCompletedProfile(completedProfileID)
                    }
                }
            }
            await self?.finishProfileRefreshCycle()
        }
    }

    /// Wall-clock corrections must not extend the throttle indefinitely. Only a previous
    /// event in the real non-negative cooldown window suppresses new work.
    static func isInsideWakeCooldown(now: Date, previous: Date) -> Bool {
        let elapsed = now.timeIntervalSince(previous)
        return elapsed >= 0 && elapsed < wakeRefreshCooldown
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
    ///
    /// Each group task returns the profile's stable identifier, and the parent consumes the
    /// group in completion order: the moment one profile finishes, its new state is published
    /// on the main actor. Waiting for `waitForAll()` would hold a fast account's fresh numbers
    /// behind a slow one's request, which is the 1.3.0 defect this cycle shape removes
    /// (REQUIREMENTS.md §3.1).
    private func refresh(resetFailureBudget: Bool = false) {
        guard !isStopped, !isRefreshing else { return }
        isRefreshing = true
        let coordinator = self.coordinator
        let profileIDs = coordinator.profileIDs
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: String.self) { group in
                for profileID in profileIDs {
                    group.addTask {
                        _ = coordinator.fetch(profileID: profileID,
                                              resetFailureBudget: resetFailureBudget)
                        return profileID
                    }
                }
                for await completedProfileID in group {
                    await self?.publishCompletedProfile(completedProfileID)
                }
            }
            await self?.finishProfileRefreshCycle()
        }
    }

    /// Publishes the state of one profile as soon as its fetch returns.
    ///
    /// The publication always reads every profile's full value snapshot, so the array order
    /// stays account A, account B regardless of who finished first (REQUIREMENTS.md §3.1).
    /// The cycle-wide `isRefreshing` deliberately stays true: other profiles are still in
    /// flight, and the card for this one already shows its own new numbers.
    private func publishCompletedProfile(_ profileID: String) {
        guard !isStopped, !Task.isCancelled else { return }
        publishProfileStates()
        tick += 1
    }

    /// Ends the cycle once the last profile has returned, and only then clears the round-wide
    /// refreshing flag so the next round can start.
    private func finishProfileRefreshCycle() {
        // A cancelled or stopped view model must not publish state after teardown. The flag is
        // still cleared so a later cycle is not blocked by a stale `true`.
        guard !isStopped, !Task.isCancelled else {
            isRefreshing = false
            refreshTask = nil
            return
        }
        isRefreshing = false
        refreshTask = nil
        publishProfileStates()
        tick += 1
        rescheduleCodexTimer()
        rescheduleMenuBarRefreshTimer()
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
        rescheduleMenuBarRefreshTimer()
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

    // MARK: - Fire

    /// Runs one manual 5-hour fire for the profile. The caller must already have shown the
    /// fixed confirmation; this method never asks again.
    ///
    /// The result the card shows separates "the request ran" from "a new window was
    /// confirmed": only a refresh that moves the service's 5-hour `resetsAt` forward by at
    /// least `windowConfirmationThreshold` produces the confirmed text.
    @discardableResult
    public func fire(profileID: String) -> Bool {
        guard !isStopped, let runtime = coordinator.runtime(for: profileID) else { return false }
        let current = runtime.state()
        guard !current.isFiring else { return false }

        let previousFiveHourReset = current.display.snapshot?.fiveHour?.resetsAt
        let previousWasLive: Bool
        switch current.display {
        case .live: previousWasLive = true
        case .stale, .unavailable: previousWasLive = false
        }
        coordinator.recordFireStart(profileID: profileID)
        publishProfileStates()
        tick += 1

        let service = fireService
        let profile = runtime.profile
        fireTasks[profileID] = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = service.fire(profile: profile)
            await self?.finishFire(profileID: profileID,
                                   outcome: outcome,
                                   previousFiveHourReset: previousFiveHourReset,
                                   previousWasLive: previousWasLive)
        }
        return true
    }

    private func finishFire(profileID: String,
                            outcome: ChatGPTFireProcessOutcome,
                            previousFiveHourReset: Date?,
                            previousWasLive: Bool) async {
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

        // First confirmation read. When it is already conclusive the second read is skipped:
        // there is nothing left to learn, and the extra read is pure load on the service.
        var observations: [FireWindowConfirmation.Observation] = []
        let first = await fetchFiveHourResetObservation(profileID: profileID)
        observations.append(first)
        if previousWasLive,
           case .live(let resetsAt) = first,
           FireWindowConfirmation.confirms(live: resetsAt, previous: previousFiveHourReset) {
            finishFireCycle(profileID: profileID,
                            result: .requestSucceededWindowConfirmed,
                            previousFiveHourReset: previousFiveHourReset,
                            observations: observations)
            return
        }

        // Every other case waits once more and reads again — including a first live read whose
        // reset time has not moved yet, because the service may simply not have published the
        // new window on the first read (REQUIREMENTS.md §4.2 steps 3–5).
        try? await Task.sleep(nanoseconds: Self.nanoseconds(fireRetryDelay))
        guard !isStopped else { return }
        observations.append(await fetchFiveHourResetObservation(profileID: profileID))

        finishFireCycle(profileID: profileID,
                        result: FireWindowConfirmation.classify(previousReset: previousFiveHourReset,
                                                                previousWasLive: previousWasLive,
                                                                observations: observations),
                        previousFiveHourReset: previousFiveHourReset,
                        observations: observations)
    }

    /// Records the final fire result and republishes, unless the app has stopped in the
    /// meantime (in which case nothing may reach the UI).
    ///
    private func finishFireCycle(profileID: String,
                                 result: ChatGPTFireResult,
                                 previousFiveHourReset: Date? = nil,
                                 observations: [FireWindowConfirmation.Observation] = []) {
        guard !isStopped else { return }
        coordinator.recordFireFinished(profileID: profileID,
                                       result: result,
                                       driftSeconds: Self.fireDrift(result: result,
                                                                    previous: previousFiveHourReset,
                                                                    observations: observations))
        fireTasks[profileID] = nil
        publishProfileStates()
        tick += 1
    }

    /// The measured forward movement behind a finished fire, for the card suffix. Only the
    /// two measured outcomes carry one; anything unconfirmed shows the request alone.
    static func fireDrift(result: ChatGPTFireResult,
                          previous: Date?,
                          observations: [FireWindowConfirmation.Observation]) -> TimeInterval? {
        switch result {
        case .requestSucceededWindowConfirmed, .requestSucceededWindowUnchanged:
            let latest = observations.compactMap { observation -> Date? in
                if case .live(let resetsAt) = observation { return resetsAt }
                return nil
            }.last
            return FireWindowDrift.shift(from: previous, to: latest)
        case .requestSucceededConfirmationUnavailable, .codexCLINotFound,
             .commandCodeCLINotFound, .credentialUnavailable, .launchFailed,
             .nonZeroExit, .timedOut, .alreadyRunning:
            return nil
        }
    }

    /// Runs a Command Code fire through the official CLI. Manual calls may request Keychain
    /// access; scheduled calls are background-only and fail visibly instead of showing UI.
    @discardableResult
    public func fireCommandCode(userInitiated: Bool = true) -> Bool {
        guard !isStopped, !commandCodeFireState.isFiring,
              let reading = engineReading(.commandcode) as? CommandCodeReading else { return false }

        let report = providerReports.first { $0.platform == .commandcode }
        let previousReset = report?.usage?.windows.first { $0.kind == .fiveHour }?.resetsAt
        let previousWasLive = report?.connection == .connected && previousReset != nil
        commandCodeFireState.start()
        tick += 1

        let service = commandCodeFireService
        fireTasks[CommandCodeFireService.targetID] = Task { [weak self] in
            let credential = await reading.fireCredential(userInitiated: userInitiated)
            guard let key = credential.secret, !key.isEmpty else {
                self?.finishCommandCodeFire(result: .credentialUnavailable)
                return
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                service.fire(apiKey: key)
            }.value
            await self?.finishCommandCodeFire(outcome: outcome,
                                              previousReset: previousReset,
                                              previousWasLive: previousWasLive,
                                              userInitiated: userInitiated,
                                              reading: reading)
        }
        return true
    }

    private func finishCommandCodeFire(outcome: CommandCodeFireProcessOutcome,
                                       previousReset: Date?,
                                       previousWasLive: Bool,
                                       userInitiated: Bool,
                                       reading: CommandCodeReading) async {
        guard !isStopped else { return }
        if let immediate = outcome.immediateResult {
            finishCommandCodeFire(result: immediate)
            return
        }

        try? await Task.sleep(nanoseconds: Self.nanoseconds(fireConfirmDelay))
        guard !isStopped else { return }
        var observations: [FireWindowConfirmation.Observation] = []
        let first = await commandCodeObservation(reading: reading, userInitiated: userInitiated)
        observations.append(first)
        if previousWasLive,
           case .live(let resetsAt) = first,
           FireWindowConfirmation.confirms(live: resetsAt, previous: previousReset) {
            finishCommandCodeFire(result: .requestSucceededWindowConfirmed,
                                  previousReset: previousReset,
                                  observations: observations)
            refreshProvider(.commandcode, force: false)
            return
        }

        try? await Task.sleep(nanoseconds: Self.nanoseconds(fireRetryDelay))
        guard !isStopped else { return }
        observations.append(await commandCodeObservation(reading: reading,
                                                         userInitiated: userInitiated))
        let result = FireWindowConfirmation.classify(previousReset: previousReset,
                                                     previousWasLive: previousWasLive,
                                                     observations: observations)
        finishCommandCodeFire(result: result,
                              previousReset: previousReset,
                              observations: observations)
        refreshProvider(.commandcode, force: false)
    }

    private func commandCodeObservation(reading: CommandCodeReading,
                                        userInitiated: Bool) async -> FireWindowConfirmation.Observation {
        do {
            guard let reset = try await reading.fiveHourResetForFire(userInitiated: userInitiated) else {
                return .noEvidence
            }
            return .live(resetsAt: reset)
        } catch {
            return .noEvidence
        }
    }

    private func finishCommandCodeFire(result: ChatGPTFireResult,
                                       previousReset: Date? = nil,
                                       observations: [FireWindowConfirmation.Observation] = []) {
        guard !isStopped else { return }
        commandCodeFireState.finish(result,
                                    driftSeconds: Self.fireDrift(result: result,
                                                                 previous: previousReset,
                                                                 observations: observations))
        fireTasks[CommandCodeFireService.targetID] = nil
        tick += 1
    }

    private func handleClockTick(_ date: Date) {
        tick += 1
        evaluateFireSchedules(at: date)
    }

    /// Executes each due row at most once. A row is claimed only after its target accepted
    /// the work, so a temporarily busy target may still run on the next tick inside the
    /// ten-minute catch-up window.
    func evaluateFireSchedules(at date: Date, calendar: Calendar = .current) {
        guard !isStopped else { return }
        for occurrence in fireSchedules.dueOccurrences(at: date, calendar: calendar) {
            let accepted: Bool
            switch occurrence.entry.target {
            case .chatGPTA, .chatGPTB:
                accepted = occurrence.entry.target.profileID.map { fire(profileID: $0) } ?? false
            case .commandCode:
                accepted = fireCommandCode(userInitiated: false)
            }
            if accepted { fireSchedules.markFired(occurrence) }
        }
    }

    /// One confirmation-only read of a single profile, reduced to the only thing the
    /// confirmation can use: a live 5-hour reset time, or no evidence.
    ///
    /// Only a *live* result counts (REVISION_SPEC.md §9.2). `UsageService.fetch` returns
    /// `.success` for a cache-served snapshot too, and a cached `resetsAt` is last cycle's
    /// number: treating it as freshly observed would let the card claim a new window that was
    /// never confirmed. A live read without a 5-hour reset time is equally meaningless here.
    ///
    /// The confirmation path deliberately skips `account/read`: it resolves no identity,
    /// touches no attribution and triggers no cache migration.
    private func fetchFiveHourResetObservation(profileID: String) async -> FireWindowConfirmation.Observation {
        let coordinator = self.coordinator
        return await Task.detached(priority: .userInitiated) {
            let outcome = coordinator.fetchRateLimitsOnly(profileID: profileID)
            guard case .success(let result) = outcome, result.isLive,
                  let resetsAt = result.snapshot.fiveHour?.resetsAt else {
                return FireWindowConfirmation.Observation.noEvidence
            }
            return .live(resetsAt: resetsAt)
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

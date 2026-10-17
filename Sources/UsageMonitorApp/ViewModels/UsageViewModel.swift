import AppKit
import Foundation
import Combine
import UsageMonitorCore

/// Drives the menu bar UI and the detail panel.
///
/// Refresh scopes since 1.6.9 (REQUIREMENTS.md §1–§3):
/// - the menu bar displays exactly one source, and one loop maintains exactly that source
///   on its own cadence: a ChatGPT profile adapts at 30/60/120 seconds, a DeepSeek,
///   Command Code or Google source at five minutes, and the 1.4.0 low-usage setting may
///   shorten the displayed source's interval;
/// - every other account has no background loop at all. It is read once when a page that
///   shows it is opened or switched to, and only when the page's accounts have not all
///   been attempted within the last five minutes;
/// - manual paths (the header's refresh, a brand page's refresh, the fire confirmation)
///   ignore every threshold.
///
/// Each ChatGPT profile still owns a long-lived `codex app-server` child under its own
/// `CODEX_HOME`, and a cycle runs its profiles in parallel so one slow or signed-out
/// account cannot delay another (REQUIREMENTS.md §4.1, IMPLEMENTATION_TASKS.md §2).
///
/// All fetches run off the main thread; `stop()` hands both drains to a background queue and
/// reports completion, so the application can defer termination until every owned child is
/// quiescent.
@MainActor
public final class UsageViewModel: ObservableObject {

    var accountManagementUnavailable = false
    var accountRegistry: AccountRegistry?
    var accountDefaults: UserDefaults = .standard
    var accountCredentials: ProviderCredentialStoring?
    var accountTransport: ProviderTransport?
    var apiRuntimes: [String: APIAccountRuntime] = [:]
    var pendingChatGPTAccount: ManagedAccount?
    var removedChatGPTRuntimes: [String: CodexProfileRuntime] = [:]
    @Published var managedAccounts: [ManagedAccount] = []
    @Published var managedAPIStates: [APIAccountState] = []
    @Published var accountMessage = ""
    @Published var showAddAccount = false
    @Published var addingPlatform: AccountPlatform?
    @Published var additionalFireStates: [String: CommandCodeFireViewState] = [:]
    var managedAPITasks: [String: Task<Void, Never>] = [:]

    // MARK: ChatGPT profiles

    /// One entry per enabled profile, in the fixed order account A, account B. A single
    /// `displayState`/`codexAccount` pair is deliberately gone: it could only ever describe
    /// one account.
    @Published public private(set) var profileStates: [CodexProfileViewState] = []
    @Published private(set) var loginStatus: [String: String] = [:]
    @Published private(set) var activeLoginProfile: String?
    private var loginAttemptID: UUID?

    // MARK: Providers

    /// One report per detail-panel platform, in display order.
    @Published public internal(set) var providerReports: [ProviderReport] = []
    @Published private(set) var commandCodeFireState = CommandCodeFireViewState()
    /// The latest unauthenticated observation from DeepSeek's public status page. A failed
    /// page read remains visibly unavailable; it is never converted into a healthy state.
    @Published public private(set) var deepSeekStatus = DeepSeekStatusSnapshot.unavailable()

    // MARK: Shared

    /// True while a ChatGPT refresh cycle is in flight (any profile).
    @Published public private(set) var isRefreshing = false
    /// A manual refresh arrived while a cycle was running: exactly one follow-up cycle is
    /// owed once that cycle ends (1.4.2 §3.1). Automatic arrivals never set this.
    private var pendingManualRefresh = false
    @Published public internal(set) var isProviderRefreshing = false
    @Published public private(set) var isDeepSeekStatusRefreshing = false
    /// Per-platform, fixed-vocabulary feedback for the credential settings forms (Round 6).
    @Published public private(set) var credentialFeedback: [ProviderPlatform: CredentialFeedback] = [:]
    /// Bumped whenever relative timestamps should be re-evaluated (staleness ages).
    @Published public internal(set) var tick = 0
    @Published public private(set) var isCredentialDiagnosticOn = CredentialAccessLog.isEnabled

    /// Owns the per-profile runtimes and their services.
    let coordinator: CodexProfilesCoordinator
    /// Menu bar source, currency and menu-bar-only cadence preferences. No credentials or
    /// provider caches are stored here.
    let menuBarPreferences: MenuBarPreferences
    /// Local display metadata shared by the detail and settings surfaces.
    let displayNames: DisplayNamePreferences
    let google: AntigravityModel
    private var googleObserver: AnyCancellable?
    let fireService: ChatGPTFireService
    let commandCodeFireService: CommandCodeFireService
    let fireSchedules: FireSchedulePreferences

    /// Non-optional by design (Round 6): a view model without an engine has no save path
    /// at all. Internal (not private) so the wiring tests can read engine state directly.
    let providerEngine: ProviderRefreshEngine

    private let baseRefreshInterval: TimeInterval
    private let providerRefreshInterval: TimeInterval
    private let deepSeekStatusReader: DeepSeekStatusReading?
    private let deepSeekStatusRefreshInterval: TimeInterval = 5 * 60
    /// How often the detail page re-evaluates relative timestamps. 30 seconds by default:
    /// the per-second countdown is drawn from `Date()` on demand, so a 1-second tick only
    /// paid for a full page recompute (REQUIREMENTS.md §4.1).
    private let clockInterval: TimeInterval
    private var lastScheduledMenuBarRefreshAt: Date?
    private var lastWakeRefreshAt: Date?
    /// When a read was last started for each account, memory only. The page-batch gate reads
    /// it; Google accounts answer from the Google model, which owns their reads.
    private let refreshAttempts = RefreshAttemptLedger()

    /// Refresh cadence for the menu bar loop while it displays a ChatGPT profile, chosen
    /// from that profile's known reset times.
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

    /// Selects the next UI timer interval while honoring the earliest per-profile retry
    /// deadline. A retry gate can shorten the normal cadence, but never makes a profile
    /// fetch before its own service permits it.
    static func retryAwareCodexRefreshInterval(normalInterval: TimeInterval,
                                               retryDates: [Date],
                                               now: Date) -> TimeInterval {
        guard let nextRetry = retryDates.filter({ $0 > now }).min() else { return normalInterval }
        return min(normalInterval, max(0.1, nextRetry.timeIntervalSince(now)))
    }

    /// How long to wait after a successful request before the confirming refresh, and how
    /// long to wait before the single retry. Fixed by REQUIREMENTS.md §7.2; injectable so
    /// tests do not have to sleep for real.
    let fireConfirmDelay: TimeInterval
    let fireRetryDelay: TimeInterval

    /// A new 5-hour window counts as confirmed only when the service's reset time moved
    /// forward by at least this much. `exit 0` alone proves nothing. The number itself lives
    /// with the confirmation rule in core, so the card and the classifier share one constant.
    static let windowConfirmationThreshold: TimeInterval = FireWindowConfirmation.threshold

    private var menuBarRefreshTimer: AnyCancellable?
    private var clockTimer: AnyCancellable?
    /// Re-publishes when the menu bar source or the DeepSeek currency changes, so the status
    /// item re-measures its width immediately instead of waiting for the next data change.
    private var menuBarPreferenceObserver: AnyCancellable?
    private var clockObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var refreshTask: Task<Void, Never>?
    private var deepSeekStatusTask: Task<Void, Never>?
    var fireTasks: [String: Task<Void, Never>] = [:]
    private var deepSeekStatusCheckedAt: Date?
    private(set) var isStopped = false

    /// Designated initializer: the production composition path.
    public init(coordinator: CodexProfilesCoordinator,
                google: AntigravityModel? = nil,
                providerEngine: ProviderRefreshEngine,
                menuBarPreferences: MenuBarPreferences = .shared,
                displayNames: DisplayNamePreferences = .shared,
                fireService: ChatGPTFireService = ChatGPTFireService(),
                commandCodeFireService: CommandCodeFireService = CommandCodeFireService(),
                fireSchedules: FireSchedulePreferences? = nil,
                refreshInterval: TimeInterval = 60,
                providerRefreshInterval: TimeInterval = ProviderRefreshEngine.defaultRefreshInterval,
                deepSeekStatusReader: DeepSeekStatusReading? = nil,
                fireConfirmDelay: TimeInterval = 2,
                fireRetryDelay: TimeInterval = 5,
                clockInterval: TimeInterval = 30) {
        self.coordinator = coordinator
        self.google = google ?? AntigravityModel(credentials: InMemoryCredentialStore(), defaults: UserDefaults(suiteName: "minget-unconnected-google")!,
            store: AntigravityProfileStore(base: FileManager.default.temporaryDirectory.appendingPathComponent("minget-unconnected-google")), migrateLegacy: false)
        self.providerEngine = providerEngine
        self.menuBarPreferences = menuBarPreferences
        self.displayNames = displayNames
        self.fireService = fireService
        self.commandCodeFireService = commandCodeFireService
        self.fireSchedules = fireSchedules ?? FireSchedulePreferences()
        self.baseRefreshInterval = refreshInterval
        self.providerRefreshInterval = providerRefreshInterval
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
                            displayNames: DisplayNamePreferences = .shared,
                            fireService: ChatGPTFireService = ChatGPTFireService(),
                            commandCodeFireService: CommandCodeFireService = CommandCodeFireService(),
                            fireSchedules: FireSchedulePreferences? = nil,
                            refreshInterval: TimeInterval = 60,
                            providerRefreshInterval: TimeInterval = ProviderRefreshEngine.defaultRefreshInterval,
                            deepSeekStatusReader: DeepSeekStatusReading? = nil,
                            fireConfirmDelay: TimeInterval = 2,
                            fireRetryDelay: TimeInterval = 5,
                            clockInterval: TimeInterval = 30) {
        self.init(coordinator: CodexProfilesCoordinator(profiles: [ChatGPTAccountProfile.chatGPTA],
                                                        makeService: { _ in service }),
                  providerEngine: providerEngine,
                  menuBarPreferences: menuBarPreferences,
                  displayNames: displayNames,
                  fireService: fireService,
                  commandCodeFireService: commandCodeFireService,
                  fireSchedules: fireSchedules,
                  refreshInterval: refreshInterval,
                  providerRefreshInterval: providerRefreshInterval,
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
    public func menuBarContent(now: Date = Date()) -> MenuBarContent {
        MenuBarContentBuilder.make(source: menuBarSource(), now: now)
    }

    /// The single resolved source the menu bar currently shows.
    ///
    /// The selection is validated when it is loaded, so a stale or hand-edited preference
    /// falls back to account A rather than to "no source".
    ///
    /// The unavailable messages are deliberately short: since 1.6.8 the item has one
    /// fixed width, so every renderable text must fit the same budget.
    public func menuBarSource() -> MenuBarSource {
        if accountRegistry != nil {
            if managedAccounts.isEmpty { return .unavailable("请添加账号") }
            let exists: Bool
            switch menuBarPreferences.selection {
            case .profile(let id), .apiAccount(let id): exists = managedAccounts.contains { $0.id == id && !$0.removalPending }
            case .deepSeek: exists = managedAccounts.contains { $0.id == "deepseek" && !$0.removalPending }
            case .google(let email): exists = managedAccounts.contains { $0.googleEmail == email && !$0.removalPending }
            }
            if !exists {
                let removed = accountDefaults.stringArray(forKey: AccountRegistry.removedSelectionsKey) ?? []
                return .unavailable(removed.contains(menuBarPreferences.selection.storageValue) ? "请重新选择" : "请选择账号")
            }
        }
        switch menuBarPreferences.selection {
        case .apiAccount(let id):
            return .deepSeek(deepSeekMenuBarContent(code: menuBarCode(for: .apiAccount(id)),
                                                       report: managedAPIStates.first { $0.id == id }?.report))
        case .profile(let id):
            if let state = profileStates.first(where: { $0.profile.id == id }) {
                return .chatGPT(code: menuBarCode(for: .profile(id)),
                                 display: state.display,
                                 connectionState: state.connectionState)
            }
            let fallback = profileStates.first
            return .chatGPT(code: menuBarCode(for: .profile(fallback?.profile.id ?? id)),
                             display: fallback?.display ?? .unavailable(.rpcFailed(.other)),
                             connectionState: fallback?.connectionState ?? .idle)
        case .google(let id):
            let state = google.accounts.first { $0.id == id }
            let groupID = menuBarPreferences.googleGroupIDs[id]
            let group = state?.snapshot?.groups.first { $0.id == groupID }
            return .antigravity(code: menuBarCode(for: .google(id)),
                                 group: group, isCached: state?.isCached ?? true,
                                 missingGroup: groupID != nil && group == nil)
        case .deepSeek:
            return .deepSeek(deepSeekMenuBarContent(code: menuBarCode(for: .deepSeek)))
        }
    }

    /// The code every surface shows for one menu bar selection: `O1` for a
    /// ChatGPT account, `G1` for a Gemini account, `DS1` for DeepSeek.
    ///
    /// The number comes from the account's stored ordinal when the registry is
    /// available, so a code survives renames and does not reshuffle when another
    /// account is removed. Without a registry the position in the current list
    /// stands in, which is the only order the legacy mode has. The menu bar and
    /// the settings list resolve the code through this one method, so the two
    /// can never disagree.
    public func menuBarCode(for selection: MenuBarPreferences.Selection) -> String {
        switch selection {
        case .profile(let id):
            return "O" + String(ordinal(forAccount: id) ?? (coordinator.profileIDs.firstIndex(of: id).map { $0 + 1 } ?? 1))
        case .google(let email):
            return "G" + String(ordinal(forGoogleAccount: email) ?? (google.accounts.firstIndex { $0.id == email }.map { $0 + 1 } ?? 1))
        case .deepSeek:
            return "DS" + String(ordinal(forAccount: "deepseek") ?? 1)
        case .apiAccount(let id):
            return "DS" + String(ordinal(forAccount: id) ?? 1)
        }
    }

    private func ordinal(forAccount id: String) -> Int? {
        managedAccounts.first { $0.id == id }?.ordinal
    }

    private func ordinal(forGoogleAccount email: String) -> Int? {
        managedAccounts.first { $0.googleEmail == email }?.ordinal
    }

    /// Current adaptive decision for the source shown in the menu bar. A nil interval means
    /// the source is not below any configured threshold, so its own cadence applies.
    public var currentMenuBarRefreshDecision: MenuBarRefreshDecision {
        if accountRegistry != nil, case .unavailable = menuBarSource() { return .inactive }
        let selectedSnapshot: UsageSnapshot?
        let normalInterval: TimeInterval
        switch menuBarPreferences.selection {
        case .google: return .inactive
        case .profile(let profileID):
            selectedSnapshot = profileState(profileID)?.snapshot
            normalInterval = currentMenuBarBaseInterval
        case .deepSeek, .apiAccount:
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
        if case .apiAccount(let id) = menuBarPreferences.selection { return managedAPIStates.first { $0.id == id }?.report }
        return providerReports.first { $0.platform == .deepseek }
    }

    /// The DeepSeek half of the menu bar, resolved from the current report.
    ///
    /// A stale report keeps its amount and adds the warning marker; a report with
    /// nothing attributable shows `DS1 —` with a warning. A zero balance can
    /// never be produced here.
    private func deepSeekMenuBarContent(code: String, report input: ProviderReport? = nil) -> MenuBarDeepSeekContent {
        guard let report = input ?? deepSeekReport else {
            return MenuBarDeepSeekContent(code: code, currency: nil, amount: nil, isCached: false)
        }
        let isCached = report.connection == .stale
        let usable = report.connection == .connected || report.connection == .stale
        guard usable, !report.balances.isEmpty else {
            return MenuBarDeepSeekContent(code: code, currency: nil, amount: nil, isCached: isCached)
        }
        let resolution = DeepSeekMenuBarResolver.resolve(balances: report.balances,
                                                         savedCurrency: menuBarPreferences.deepSeekCurrency)
        return MenuBarDeepSeekContent(code: code,
                                       currency: resolution.currency,
                                       amount: resolution.amount,
                                       isCached: isCached)
    }

    // MARK: - Lifecycle

    /// Starts the app: one immediate read of the source the menu bar displays, then on that
    /// source's schedule. No other account is read at launch.
    public func start() {
        guard !accountManagementUnavailable else { return }
        Diagnostics.log("viewmodel start")
        isStopped = false
        googleObserver = google.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.tick += 1 }
        }
        resumePendingRemovals()
        primeManagedCredentials()
        google.start(accountIDs: selectedGoogleAccountIDs)
        scheduleTimers()
        observeClockChanges()
        observeMenuBarPreferences()
        clockTimer = Timer.publish(every: clockInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.handleClockTick(date) }
        // The launch read of the displayed source. A credential-gated source (an API
        // connection) is read by the credential pass instead, which is the only moment its
        // key is known to be readable.
        if let target = menuBarRefreshTarget(), !target.isCredentialGated {
            refreshTargets([target], force: false)
        }
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
    /// "connected?" from memory afterwards. A displayed legacy provider is read once the
    /// pass settles, because that is the first moment its key is known; a managed API
    /// account primes and reads through its own runtime, and a profile or Google
    /// connection was already read at launch.
    private func primeCredentialAccess() {
        wireCredentialPhaseChanges()
        Task { [weak self] in
            guard let self else { return }
            await self.providerEngine.primeCredentials()
            self.publishProviderReports()
            if let target = self.menuBarRefreshTarget(), case .providerPlatform = target {
                self.refreshTargets([target], force: false)
            }
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
        google.stop()
        for task in managedAPITasks.values { task.cancel() }; managedAPITasks.removeAll()
        for runtime in apiRuntimes.values { runtime.engine.invalidateAttribution(platform: runtime.platform) }
        googleObserver?.cancel(); googleObserver = nil
        activeLoginProfile = nil
        loginAttemptID = nil
        isRefreshing = false
        pendingManualRefresh = false
        isProviderRefreshing = false
        isDeepSeekStatusRefreshing = false
        menuBarRefreshTimer?.cancel()
        clockTimer?.cancel()
        menuBarPreferenceObserver?.cancel()
        menuBarRefreshTimer = nil
        clockTimer = nil
        menuBarPreferenceObserver = nil
        stopObservingClockChanges()
        deepSeekStatusTask?.cancel()
        deepSeekStatusTask = nil
        for task in fireTasks.values { task.cancel() }
        fireTasks.removeAll()

        let task = refreshTask
        refreshTask = nil
        let coordinator = self.coordinator
        let fireService = self.fireService
        let commandCodeFireService = self.commandCodeFireService
        let managedFireServices = apiRuntimes.values.map(\.fireService)
        let detachedServices = removedChatGPTRuntimes.values.map(\.service)
        joinQueue.async {
            task?.cancel()
            // `fire()` blocks in `Process.waitUntilExit()`, so cancelling the task above does
            // not reach the child. Terminating it explicitly is what keeps a `codex exec`
            // from outliving the app (REVISION_SPEC.md §9.1).
            fireService.stopAll()
            commandCodeFireService.stop()
            for service in managedFireServices { service.stop() }
            for service in detachedServices { service.stop() }
            coordinator.stop()
            Diagnostics.log("viewmodel stopped")
            completion?()
        }
    }

    /// Serial queue so repeated stop() calls cannot overlap their drains.
    private let joinQueue = DispatchQueue(label: "usagemonitor.viewmodel.join")

    /// Installs the one automatic loop: the menu bar source's own schedule. The detail
    /// clock is installed by `start()` alongside it.
    private func scheduleTimers() {
        rescheduleMenuBarRefreshTimer()
    }

    /// The account the menu bar loop maintains, or nil when the current selection cannot be
    /// read: an empty registry, a removed account, a hand-edited preference.
    func menuBarRefreshTarget() -> RefreshTarget? {
        if case .unavailable = menuBarSource() { return nil }
        return RefreshBatchPolicy.menuBarTarget(selection: menuBarPreferences.selection,
                                                isRegistryMode: accountRegistry != nil)
    }

    /// The Google connections the launch may read: only the one the menu bar displays.
    private var selectedGoogleAccountIDs: Set<String> {
        if case .google(let email) = menuBarPreferences.selection { return [email] }
        return []
    }

    /// The displayed source's own cadence before the low-usage setting shortens it: a
    /// ChatGPT profile follows its reset distance (30/60/120 s), every other source the
    /// provider cadence.
    var currentMenuBarBaseInterval: TimeInterval {
        switch menuBarPreferences.selection {
        case .profile(let profileID):
            return Self.codexRefreshInterval(snapshots: [profileState(profileID)?.snapshot],
                                             baseInterval: baseRefreshInterval)
        case .google, .deepSeek, .apiAccount:
            return providerRefreshInterval
        }
    }

    /// The interval the menu bar loop currently runs with, or nil when there is nothing to
    /// maintain. A pending retry deadline for the displayed profile shortens the wait, and
    /// the low-usage setting never delays the source beyond its own cadence.
    var currentMenuBarRefreshInterval: TimeInterval? {
        guard let target = menuBarRefreshTarget() else { return nil }
        let interval = currentMenuBarRefreshDecision.interval ?? currentMenuBarBaseInterval
        guard let profileID = target.chatGPTProfileID,
              let retryDate = retryDeadline(for: profileID) else { return interval }
        return Self.retryAwareCodexRefreshInterval(normalInterval: interval,
                                                   retryDates: [retryDate],
                                                   now: Date())
    }

    /// The automatic retry deadline of one profile, or nil when the ladder is not holding it.
    private func retryDeadline(for profileID: String) -> Date? {
        guard let runtime = coordinator.runtime(for: profileID),
              !runtime.service.isManualRetryRequired else { return nil }
        return runtime.service.automaticRetryGate
    }

    /// Exposes the configured detail-page clock cadence to deterministic wiring tests.
    /// The timer itself remains private and is still created only by `start()`.
    var configuredClockInterval: TimeInterval { clockInterval }

    /// Exposes the menu bar loop's current interval, or nil when no source is maintained,
    /// without exposing the timer itself or allowing tests to fire it.
    var configuredMenuBarRefreshInterval: TimeInterval? {
        menuBarRefreshTimer == nil ? nil : lastMenuBarRefreshTimerInterval
    }

    /// Rebuilds the menu bar loop only when its cadence actually changed, so a steady state
    /// keeps one subscription instead of churning one per round.
    func rescheduleMenuBarRefreshTimer() {
        guard !isStopped else { return }
        guard let interval = currentMenuBarRefreshInterval else {
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
            .sink { [weak self] _ in self?.scheduledMenuBarRefresh() }
    }

    private var lastMenuBarRefreshTimerInterval: TimeInterval = 0

    /// One scheduled round of the menu bar loop, then a cadence re-check: near a reset the
    /// next round comes sooner, far from any reset it backs off. Internal so a test can run
    /// one round without waiting for the real timer.
    func scheduledMenuBarRefresh() {
        guard !isStopped else { return }
        if let lastWake = lastWakeRefreshAt,
           Self.isInsideWakeCooldown(now: Date(), previous: lastWake) {
            return
        }
        lastScheduledMenuBarRefreshAt = Date()
        if let target = menuBarRefreshTarget() { refreshTargets([target], force: false) }
        rescheduleMenuBarRefreshTimer()
    }

    /// One throttled refresh after sleep, scoped like every other automatic path: only the
    /// source the menu bar displays is woken. A healthy profile reuses its existing
    /// app-server and reads rate limits only; an unhealthy client falls back to the ordinary
    /// full read. Neither route re-opens the failure budget.
    func refreshAfterWake(now: Date = Date()) {
        guard !isStopped, let target = menuBarRefreshTarget() else { return }
        if let lastScheduled = lastScheduledMenuBarRefreshAt,
           Self.isInsideWakeCooldown(now: now, previous: lastScheduled) {
            return
        }
        if let lastWake = lastWakeRefreshAt,
           Self.isInsideWakeCooldown(now: now, previous: lastWake) {
            return
        }
        guard let profileID = target.chatGPTProfileID else {
            lastWakeRefreshAt = now
            switch target {
            case .googleAccount(let email):
                google.refresh(force: false, now: now, afterWake: true, accountIDs: [email])
            case .apiAccount, .providerPlatform:
                refreshTargets([target], force: false)
            case .chatGPTProfile:
                break
            }
            return
        }
        guard !isRefreshing else { return }
        lastWakeRefreshAt = now
        isRefreshing = true
        let coordinator = self.coordinator
        let attempts = refreshAttempts
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            switch coordinator.probeAfterWake(profileID: profileID) {
            case .refreshed:
                attempts.record(.chatGPTProfile(profileID))
                await self?.publishCompletedProfile(profileID)
            case .needsFullRefresh:
                attempts.record(.chatGPTProfile(profileID))
                _ = coordinator.fetch(profileID: profileID, resetFailureBudget: false)
                await self?.publishCompletedProfile(profileID)
            case .suppressed:
                break
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

    /// Called when the user opens the detail: the page the panel shows is read once, minus
    /// the menu bar source, and only when its accounts have not all been attempted within
    /// the batch age. `now` is injectable so the age rule is testable without waiting.
    func panelWillOpen(tab: DetailPreferences.ProviderTab, now: Date = Date()) {
        performPageBatch(scope: RefreshBatchScope(tab: tab), now: now)
    }

    /// The user switched the page inside an open panel. The newly shown page follows the
    /// same rule, so switching back to a stale page reads it once more.
    func panelDidSwitchTab(_ tab: DetailPreferences.ProviderTab, now: Date = Date()) {
        performPageBatch(scope: RefreshBatchScope(tab: tab), now: now)
    }

    private func performPageBatch(scope: RefreshBatchScope, now: Date = Date()) {
        guard !isStopped else { return }
        if scope.showsDeepSeekStatus { refreshDeepSeekStatus(force: false) }
        let members = pageBatch(scope: scope)
        guard !members.isEmpty else { return }
        guard RefreshBatchPolicy.needsRefresh(members, attempts: attempts(for: members), now: now) else { return }
        refreshTargets(members, force: false)
    }

    /// One page's members: the accounts the page shows, minus the menu bar source.
    func pageBatch(scope: RefreshBatchScope) -> [RefreshTarget] {
        RefreshBatchPolicy.members(scope: scope,
                                   selection: menuBarPreferences.selection,
                                   inventory: refreshInventory,
                                   isRegistryMode: accountRegistry != nil)
    }

    /// Every account this launch can read, grouped the way the pages present them.
    private var refreshInventory: RefreshInventory {
        var inventory = RefreshInventory()
        inventory.chatGPTProfileIDs = profileStates.map(\.profile.id)
        inventory.googleAccountIDs = google.accounts.map(\.id)
        if accountRegistry != nil {
            let rows = managedAccounts.filter { !$0.removalPending && $0.platform.apiPlatform != nil }
            inventory.managedDeepSeekIDs = rows.filter { $0.platform == .deepseek }.map(\.id)
            inventory.managedCommandCodeIDs = rows.filter { $0.platform == .commandcode }.map(\.id)
        } else {
            inventory.legacyDeepSeek = hasAccounts(.deepseek)
            inventory.legacyCommandCode = hasAccounts(.commandcode)
        }
        return inventory
    }

    /// The recorded attempt time of one account, or nil when it has never been read. Google
    /// accounts answer from the Google model, which owns their reads.
    func lastRefreshAttempt(for target: RefreshTarget) -> Date? {
        if case .googleAccount(let email) = target { return google.lastAttemptAt(accountID: email) }
        return refreshAttempts.lastAttempt(for: target)
    }

    func recordRefreshAttempt(_ target: RefreshTarget, at date: Date) {
        refreshAttempts.record(target, at: date)
    }

    private func attempts(for targets: [RefreshTarget]) -> [RefreshTarget: Date] {
        var attempts: [RefreshTarget: Date] = [:]
        for target in targets { attempts[target] = lastRefreshAttempt(for: target) }
        return attempts
    }

    /// Reads an explicit set of accounts. The page batches and the menu bar loop share this
    /// dispatch, so the scope decision stays in one place.
    private func refreshTargets(_ targets: [RefreshTarget], force: Bool) {
        let profileIDs = targets.compactMap(\.chatGPTProfileID)
        if !profileIDs.isEmpty { refreshProfiles(ids: profileIDs, resetFailureBudget: force) }
        let googleIDs = targets.compactMap(\.googleAccountID)
        if !googleIDs.isEmpty { google.refresh(force: force, accountIDs: Set(googleIDs)) }
        for target in targets {
            switch target {
            case .apiAccount(let id): refreshManagedAPI(id: id, force: force)
            case .providerPlatform(let platform): refreshProvider(platform, force: force)
            case .chatGPTProfile, .googleAccount: break
            }
        }
    }

    // MARK: - Refreshing

    public func connectChatGPT(profileID: String) {
        guard activeLoginProfile == nil,
              let runtime = coordinator.runtime(for: profileID), !isStopped else { return }
        let attemptID = UUID()
        loginAttemptID = attemptID
        activeLoginProfile = profileID
        loginStatus[profileID] = "正在准备官方登录…"
        let service = runtime.service
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let started = try service.beginManagedLogin { [weak self] success in
                    Task { @MainActor [weak self] in self?.finishChatGPTLogin(profileID: profileID, attemptID: attemptID, success: success) }
                }
                await self?.showBrowserLogin(started, profileID: profileID, attemptID: attemptID, service: service)
            } catch {
                let message = (error as? UsageError).map(Self.loginErrorText)
                    ?? "无法启动登录，请检查 Codex 安装后重试。"
                await self?.failBrowserLogin(profileID: profileID, attemptID: attemptID, message: message)
            }
        }
    }

    private func showBrowserLogin(_ started: ManagedLoginStart, profileID: String,
                                  attemptID: UUID, service: UsageService) {
        guard service.isInteractiveLoginActive else { return }
        guard activeLoginProfile == profileID, loginAttemptID == attemptID else {
            if service.isInteractiveLoginActive {
                Task.detached { service.cancelManagedLogin() }
            }
            return
        }
        loginStatus[profileID] = "等待在浏览器中完成授权…"
        if !NSWorkspace.shared.open(started.authorizationURL) {
            activeLoginProfile = nil
            loginAttemptID = nil
            loginStatus[profileID] = "无法打开官方登录页，请检查默认浏览器后重试。"
            Task.detached { service.cancelManagedLogin() }
        }
    }

    private func failBrowserLogin(profileID: String, attemptID: UUID, message: String) {
        guard activeLoginProfile == profileID, loginAttemptID == attemptID else { return }
        activeLoginProfile = nil
        loginAttemptID = nil
        loginStatus[profileID] = message
    }

    nonisolated private static func loginErrorText(_ error: UsageError) -> String {
        switch error {
        case .codexCLINotFound:
            return "未找到 Codex CLI。请安装官方 Codex 桌面应用或 CLI 后重试。"
        case .codexNodeUnavailable:
            return "缺少 Node 运行环境。请安装 Node 或官方 Codex 桌面应用后重试。"
        case .rpcFailed(.serverError(code: -32601)), .rpcFailed(.malformedResponse):
            return "当前 Codex 不支持所需登录接口。请更新 Codex 后重试。"
        default:
            return UsageFormatting.errorText(error).components(separatedBy: "\n")[0] + "，请重试。"
        }
    }

    public func cancelChatGPTLogin() {
        guard let id = activeLoginProfile, let service = coordinator.runtime(for: id)?.service else { return }
        activeLoginProfile = nil
        loginAttemptID = nil
        loginStatus[id] = "已取消登录"
        Task.detached { service.cancelManagedLogin() }
        cancelPendingChatGPT()
    }

    private func finishChatGPTLogin(profileID: String, attemptID: UUID, success: Bool) {
        guard activeLoginProfile == profileID, loginAttemptID == attemptID else { return }
        activeLoginProfile = nil
        loginStatus[profileID] = success ? "授权完成，正在读取额度…" : "登录未完成，请重试。"
        guard success else { return }
        let coordinator = self.coordinator
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = coordinator.fetch(profileID: profileID, resetFailureBudget: true)
            await self?.publishLoginRefresh(profileID: profileID, attemptID: attemptID)
        }
    }

    private func publishLoginRefresh(profileID: String, attemptID: UUID) {
        guard loginAttemptID == attemptID else { return }
        completePendingChatGPT(profileID: profileID)
        publishProfileStates()
        let state = profileStates.first(where: { $0.profile.id == profileID })
        loginStatus[profileID] = (state?.snapshot != nil && state?.isStale == false && state?.failure == nil)
            ? "连接成功，额度已更新" : "已登录，实时额度暂不可用，请重试。"
    }

    /// Manual refresh: always fetches both profiles and every provider; the only path that
    /// re-opens the Codex failure budget.
    public func refreshNow() {
        guard !isStopped else { return }
        google.refresh(force: true)
        refreshProfiles(ids: coordinator.profileIDs, resetFailureBudget: true)
        if accountRegistry != nil { refreshManagedAPIs(force: true) }
        else { for report in providerReports { refreshProvider(report.platform, force: true) } }
        refreshDeepSeekStatus(force: true)
    }

    /// Manual refresh scoped to the brand page the user is looking at: only that brand's
    /// accounts are read, so nothing else on the panel changes state or timestamp.
    ///
    /// Every branch takes the same manual path as `refreshNow()`, so throttles, panel-open
    /// ages and the provider failure budget never silently swallow an explicit tap.
    func refreshBrand(_ tab: DetailPreferences.ProviderTab) {
        guard !isStopped else { return }
        switch tab {
        case .all:
            refreshNow()
        case .chatGPT:
            refreshProfiles(ids: coordinator.profileIDs, resetFailureBudget: true)
        case .google:
            google.refresh(force: true)
        case .deepSeek:
            refreshBrandPlatform(.deepseek)
        case .commandCode:
            refreshBrandPlatform(.commandcode)
        }
    }

    /// True while any source is in flight: the header's status line and the brand refresh
    /// button read this same value so they can never disagree about whether work is running.
    public var isAnyRefreshInFlight: Bool {
        isRefreshing || isProviderRefreshing || isDeepSeekStatusRefreshing || google.isRefreshing
    }

    /// Whether that brand's own page already has its read in flight.
    func isRefreshing(brand tab: DetailPreferences.ProviderTab) -> Bool {
        switch tab {
        case .all: return isAnyRefreshInFlight
        case .chatGPT: return isRefreshing
        case .google: return google.isRefreshing
        case .deepSeek: return isPlatformRefreshing(.deepseek) || isDeepSeekStatusRefreshing
        case .commandCode: return isPlatformRefreshing(.commandcode)
        }
    }

    /// Whether a brand page has at least one account to read. The overview always answers
    /// false: it keeps the header's global refresh instead of a brand-scoped one, and a brand
    /// with no account at all must not offer a dead control.
    func hasRefreshableAccounts(brand tab: DetailPreferences.ProviderTab) -> Bool {
        switch tab {
        case .all: return false
        case .chatGPT: return !profileStates.isEmpty
        case .google: return !google.accounts.isEmpty
        case .deepSeek: return hasAccounts(.deepseek)
        case .commandCode: return hasAccounts(.commandcode)
        }
    }

    private func hasAccounts(_ platform: ProviderPlatform) -> Bool {
        if accountRegistry != nil {
            return managedAccounts.contains { $0.platform.apiPlatform == platform && !$0.removalPending }
        }
        // Legacy single-connection mode: the engine's own reader answers from memory whether
        // there is a credential worth reading, and a confirmed-absent one offers no button.
        guard let reader = providerEngine.reading(for: platform) else { return false }
        return reader.credentialState != .missing
    }

    /// One API platform only. Managed accounts are read through their own runtime, so the
    /// other connections of the same registry are never touched; the DeepSeek page also
    /// owns the public status line, which a manual refresh re-reads for the same reason.
    private func refreshBrandPlatform(_ platform: ProviderPlatform) {
        if accountRegistry != nil {
            for row in managedAccounts where row.platform.apiPlatform == platform && !row.removalPending {
                refreshManagedAPI(id: row.id, force: true)
            }
        } else {
            refreshProvider(platform, force: true)
        }
        if platform == .deepseek { refreshDeepSeekStatus(force: true) }
    }

    private func isPlatformRefreshing(_ platform: ProviderPlatform) -> Bool {
        if accountRegistry != nil {
            return apiRuntimes.values.contains { $0.platform == platform && $0.engine.isFetching(platform) }
        }
        return providerEngine.isFetching(platform)
    }

    /// Refreshes the requested profiles in parallel inside one cycle. No request is stacked:
    /// a slow profile simply finishes later than the other.
    ///
    /// Each group task returns the profile's stable identifier, and the parent consumes the
    /// group in completion order: the moment one profile finishes, its new state is published
    /// on the main actor. Waiting for `waitForAll()` would hold a fast account's fresh numbers
    /// behind a slow one's request, which is the 1.3.0 defect this cycle shape removes
    /// (REQUIREMENTS.md §3.1).
    ///
    /// A manual request (`resetFailureBudget: true`) arriving while a cycle runs is never
    /// dropped: it queues exactly one follow-up cycle (1.4.2 §3.1). Automatic callers only
    /// coalesce — the running cycle's fresh results are what they wanted anyway.
    private func refreshProfiles(ids: [String], resetFailureBudget: Bool = false) {
        guard !isStopped, !ids.isEmpty else { return }
        if isRefreshing {
            if resetFailureBudget { pendingManualRefresh = true }
            return
        }
        isRefreshing = true
        let coordinator = self.coordinator
        let attempts = refreshAttempts
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: String.self) { group in
                for profileID in ids {
                    group.addTask {
                        // Automatic rounds respect the per-profile retry ladder: a profile
                        // whose backoff gate is open is skipped here rather than told
                        // "no" again by the service. Manual rounds (resetFailureBudget)
                        // bypass the gate by design.
                        if coordinator.runtime(for: profileID)?.service.isInteractiveLoginActive == true
                            || (!resetFailureBudget && coordinator.isAutomaticRetryGated(profileID: profileID)) {
                            return profileID
                        }
                        // The attempt is recorded the moment the read is dispatched, on this
                        // task rather than through the main actor, so a failure still counts
                        // and a busy main thread never delays the fetch.
                        attempts.record(.chatGPTProfile(profileID))
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
    /// refreshing flag so the next round can start. A queued manual refresh runs here, exactly
    /// once, as the next cycle.
    private func finishProfileRefreshCycle() {
        // A cancelled or stopped view model must not publish state after teardown. The flag is
        // still cleared so a later cycle is not blocked by a stale `true`.
        guard !isStopped, !Task.isCancelled else {
            isRefreshing = false
            refreshTask = nil
            pendingManualRefresh = false
            return
        }
        isRefreshing = false
        refreshTask = nil
        publishProfileStates()
        tick += 1
        if pendingManualRefresh {
            // Exactly one follow-up; it clears the flag itself before the next cycle starts.
            pendingManualRefresh = false
            refreshProfiles(ids: coordinator.profileIDs, resetFailureBudget: true)
            return
        }
        rescheduleMenuBarRefreshTimer()
    }

    private func refreshProvider(_ platform: ProviderPlatform, force: Bool) {
        guard !isStopped else { return }
        recordRefreshAttempt(.providerPlatform(platform), at: Date())
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

    func finishProviderRefresh() {
        guard !isStopped else { return }
        isProviderRefreshing = engineHasWork()
        publishProviderReports()
        tick += 1
        rescheduleMenuBarRefreshTimer()
    }

    func engineHasWork() -> Bool {
        if accountRegistry != nil { return apiRuntimes.values.contains { $0.engine.isFetching($0.platform) } }
        return [ProviderPlatform.deepseek, .commandcode].contains { providerEngine.isFetching($0) }
    }

    func publishProviderReports() {
        if accountRegistry != nil { publishManagedAPIStates() }
        else { providerReports = providerEngine.allReports() }
    }

    /// Publishes the current runtime state of both profiles as value snapshots.
    func publishProfileStates() {
        profileStates = coordinator.runtimes.filter { runtime in
            accountRegistry == nil || managedAccounts.contains { $0.id == runtime.profileID && !$0.removalPending }
        }.map { CodexProfileViewState(runtime: $0.state()) }
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
        guard !isStopped, accountRegistry?.account(profileID)?.removalPending != true, let runtime = coordinator.runtime(for: profileID) else { return false }
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

        // The request ran. Everything observed from here on counts as post-fire evidence;
        // the barrier is the completion of the request itself.
        let fireCompletedAt = Date()

        // Wait, then force-refresh this profile only — the other account's
        // window was not touched by this request.
        try? await Task.sleep(nanoseconds: Self.nanoseconds(fireConfirmDelay))
        guard !isStopped else { return }

        // First confirmation read. When it is already conclusive the second read is skipped:
        // there is nothing left to learn, and the extra read is pure load on the service.
        var observations: [FireWindowConfirmation.Observation] = []
        let first = await fetchFiveHourResetObservation(profileID: profileID, notBefore: fireCompletedAt)
        observations.append(first)
        if previousWasLive,
           case .live(let resetsAt) = first,
           FireWindowConfirmation.observesAdvancedReset(live: resetsAt, previous: previousFiveHourReset) {
            finishFireCycle(profileID: profileID,
                            result: .requestSucceededResetAdvanced,
                            previousFiveHourReset: previousFiveHourReset,
                            observations: observations)
            return
        }

        // Every other case waits once more and reads again — including a first live read whose
        // reset time has not moved yet, because the service may simply not have published the
        // new window on the first read (REQUIREMENTS.md §4.2 steps 3–5).
        try? await Task.sleep(nanoseconds: Self.nanoseconds(fireRetryDelay))
        guard !isStopped else { return }
        observations.append(await fetchFiveHourResetObservation(profileID: profileID, notBefore: fireCompletedAt))

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
        case .requestSucceededResetAdvanced, .requestSucceededResetUnchanged:
            let latest = observations.compactMap { observation -> Date? in
                if case .live(let resetsAt) = observation { return resetsAt }
                return nil
            }.last
            return FireWindowDrift.shift(from: previous, to: latest)
        case .requestSucceededResetUnavailable, .codexCLINotFound,
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
           FireWindowConfirmation.observesAdvancedReset(live: resetsAt, previous: previousReset) {
            finishCommandCodeFire(result: .requestSucceededResetAdvanced,
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
        guard !ProcessInfo.processInfo.arguments.contains("--disable-scheduled-fire"), !isStopped else { return }
        for occurrence in fireSchedules.dueOccurrences(at: date, calendar: calendar) {
            let accepted: Bool
            let id = occurrence.entry.target.rawValue
            if let profileID = occurrence.entry.target.profileID { accepted = fire(profileID: profileID) }
            else { accepted = fireManagedCommandCode(id: id, userInitiated: false) }
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
    private func fetchFiveHourResetObservation(profileID: String, notBefore barrier: Date) async -> FireWindowConfirmation.Observation {
        let coordinator = self.coordinator
        return await Task.detached(priority: .userInitiated) {
            // A manual fire owns its confirmation: the read bypasses the automatic
            // backoff gate exactly like the manual fire itself.
            let outcome = coordinator.fetchRateLimitsOnly(profileID: profileID,
                                                          resetFailureBudget: true)
            guard case .success(let result) = outcome, result.isLive,
                  // Freshness barrier: a shared read that began before the fire request
                  // finished is pre-fire evidence, however live it looks, and must not
                  // be counted (1.4.2 independent review: 点火后共享查询必须确实发生于
                  // 请求完成后).
                  let startedAt = result.readStartedAt, startedAt >= barrier,
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

import XCTest
import AppKit
import UsageMonitorCore
@testable import UsageMonitorApp

/// Cadence rules behind the 1.3.2 refresh savings and 1.4.0 menu-bar acceleration: which
/// interval the ChatGPT timer uses, how the wake refresh is throttled, and when the menu bar
/// re-measures. Pure state and fake clocks only: no real sleep, no long waits.
@MainActor
final class RefreshCadenceTests: XCTestCase {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(fiveHourResetsAt: Date?, weeklyResetsAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                usedPercent: 25, remainingPercent: 75,
                                                resetsAt: fiveHourResetsAt),
                      weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                              usedPercent: 50, remainingPercent: 50,
                                              resetsAt: weeklyResetsAt),
                      fetchedAt: Self.now,
                      source: .codexAppServer)
    }

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "UsageMonitorAppTests.RefreshCadence.\(label)." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeModel(_ label: String, service: UsageService,
                           refreshInterval: TimeInterval = 60,
                           clockInterval: TimeInterval = 30) -> UsageViewModel {
        let defaults = makeDefaults(label)
        let coordinator = CodexProfilesCoordinator(profiles: [.chatGPTA]) { _ in service }
        let engine = ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults))
        return UsageViewModel(coordinator: coordinator,
                              providerEngine: engine,
                              menuBarPreferences: MenuBarPreferences(defaults: defaults),
                              refreshInterval: refreshInterval,
                              clockInterval: clockInterval)
    }

    // MARK: Interval selection

    func testNoDataKeepsTheBaseInterval() {
        XCTAssertEqual(UsageViewModel.codexRefreshInterval(snapshots: [nil], now: Self.now),
                       UsageViewModel.baseCodexRefreshInterval)
        XCTAssertEqual(UsageViewModel.baseCodexRefreshInterval, 60)
        XCTAssertEqual(UsageViewModel.codexRefreshInterval(snapshots: [nil], now: Self.now,
                                                           baseInterval: 17), 17,
                       "the injected base interval must not be a dead initializer argument")
    }

    func testNearResetPollsFaster() {
        let soon = snapshot(fiveHourResetsAt: Self.now.addingTimeInterval(5 * 60))
        XCTAssertEqual(UsageViewModel.codexRefreshInterval(snapshots: [soon], now: Self.now),
                       UsageViewModel.nearResetCodexRefreshInterval)
        XCTAssertEqual(UsageViewModel.nearResetCodexRefreshInterval, 30)
    }

    func testFarFromResetBacksOff() {
        let later = snapshot(fiveHourResetsAt: Self.now.addingTimeInterval(3 * 3600),
                             weeklyResetsAt: Self.now.addingTimeInterval(3 * 86400))
        XCTAssertEqual(UsageViewModel.codexRefreshInterval(snapshots: [later], now: Self.now),
                       UsageViewModel.idleCodexRefreshInterval)
        XCTAssertEqual(UsageViewModel.idleCodexRefreshInterval, 120)
    }

    func testWeeklyResetInsideTheHorizonCountsAsNear() {
        let weeklySoon = snapshot(fiveHourResetsAt: Self.now.addingTimeInterval(3 * 3600),
                                  weeklyResetsAt: Self.now.addingTimeInterval(5 * 60))
        XCTAssertEqual(UsageViewModel.codexRefreshInterval(snapshots: [weeklySoon], now: Self.now),
                       UsageViewModel.nearResetCodexRefreshInterval)
    }

    func testHorizonBoundaryIsInclusive() {
        let edge = snapshot(fiveHourResetsAt: Self.now.addingTimeInterval(UsageViewModel.nearResetHorizon))
        XCTAssertEqual(UsageViewModel.codexRefreshInterval(snapshots: [edge], now: Self.now),
                       UsageViewModel.nearResetCodexRefreshInterval)
        let past = snapshot(fiveHourResetsAt: Self.now.addingTimeInterval(UsageViewModel.nearResetHorizon + 1))
        XCTAssertEqual(UsageViewModel.codexRefreshInterval(snapshots: [past], now: Self.now),
                       UsageViewModel.idleCodexRefreshInterval)
    }

    // MARK: Menu-bar low-usage acceleration

    private func menuBarSettings(interval: Int = 30,
                                 fiveHour: Int = 50,
                                 weekly: Int = 15,
                                 deepSeek: Decimal? = Decimal(string: "15.00"),
                                 enabled: Bool = true) -> MenuBarRefreshSettings {
        MenuBarRefreshSettings(isEnabled: enabled,
                               intervalSeconds: interval,
                               chatGPTFiveHourThresholdPercent: fiveHour,
                               chatGPTWeeklyThresholdPercent: weekly,
                               deepSeekBalanceThresholdCNY: deepSeek)
    }

    private func deepSeekReport(amount: Decimal,
                                currency: String = "CNY",
                                connection: ProviderConnectionState = .connected) -> ProviderReport {
        ProviderReport(platform: .deepseek,
                       accountID: "deepseek-test",
                       balances: [ProviderBalance(currency: currency, total: amount)],
                       lastSuccessAt: Self.now,
                       connection: connection,
                       isLive: connection == .connected,
                       error: nil,
                       consoleURL: nil)
    }

    func testMenuBarChatGPTThresholdsAreStrictAndUseEitherWindow() {
        let exactSnapshot = UsageSnapshot(
            fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                      usedPercent: 50, remainingPercent: 50, resetsAt: nil),
            weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                    usedPercent: 85, remainingPercent: 15, resetsAt: nil),
            fetchedAt: Self.now, source: .codexAppServer)
        XCTAssertNil(MenuBarRefreshPolicy.chatGPTTrigger(snapshot: exactSnapshot,
                                                         fiveHourThresholdPercent: 50,
                                                         weeklyThresholdPercent: 15))

        let lowFiveHour = UsageSnapshot(
            fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                      usedPercent: 50.01, remainingPercent: 49.99, resetsAt: nil),
            weekly: exactSnapshot.weekly,
            fetchedAt: Self.now, source: .codexAppServer)
        XCTAssertEqual(MenuBarRefreshPolicy.chatGPTTrigger(snapshot: lowFiveHour,
                                                           fiveHourThresholdPercent: 50,
                                                           weeklyThresholdPercent: 15),
                       .chatGPTFiveHour)

        let lowWeekly = UsageSnapshot(
            fiveHour: exactSnapshot.fiveHour,
            weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                    usedPercent: 85.01, remainingPercent: 14.99, resetsAt: nil),
            fetchedAt: Self.now, source: .codexAppServer)
        XCTAssertEqual(MenuBarRefreshPolicy.chatGPTTrigger(snapshot: lowWeekly,
                                                           fiveHourThresholdPercent: 50,
                                                           weeklyThresholdPercent: 15),
                       .chatGPTWeekly)
    }

    func testMenuBarDecisionOnlyUsesTheSelectedSourceAndNeverSlowsNormalCadence() {
        let low = UsageSnapshot(
            fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                      usedPercent: 60, remainingPercent: 40, resetsAt: nil),
            weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                    usedPercent: 20, remainingPercent: 80, resetsAt: nil),
            fetchedAt: Self.now, source: .codexAppServer)
        let high = UsageSnapshot(
            fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                      usedPercent: 10, remainingPercent: 90, resetsAt: nil),
            weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                    usedPercent: 20, remainingPercent: 80, resetsAt: nil),
            fetchedAt: Self.now, source: .codexAppServer)
        let settings = menuBarSettings(interval: 60)

        let selectedLow = MenuBarRefreshPolicy.decision(
            selection: .profile("chatgpt-a"), profileSnapshot: low, deepSeekReport: nil,
            deepSeekCurrency: nil, settings: settings, normalInterval: 30)
        XCTAssertEqual(selectedLow.interval, 30)
        XCTAssertEqual(selectedLow.trigger, .chatGPTFiveHour)

        let selectedHigh = MenuBarRefreshPolicy.decision(
            selection: .profile("chatgpt-b"), profileSnapshot: high, deepSeekReport: nil,
            deepSeekCurrency: nil, settings: settings, normalInterval: 120)
        XCTAssertFalse(selectedHigh.isAccelerated)
    }

    func testMenuBarDeepSeekUsesDisplayedCNYOnlyAndStrictBoundary() {
        let exact = deepSeekReport(amount: Decimal(string: "15.00")!)
        XCTAssertNil(MenuBarRefreshPolicy.deepSeekTrigger(report: exact,
                                                          savedCurrency: nil,
                                                          thresholdCNY: Decimal(string: "15.00")))

        let low = deepSeekReport(amount: Decimal(string: "14.99")!)
        XCTAssertEqual(MenuBarRefreshPolicy.deepSeekTrigger(report: low,
                                                            savedCurrency: nil,
                                                            thresholdCNY: Decimal(string: "15.00")),
                       .deepSeekBalance)

        let usd = deepSeekReport(amount: Decimal(string: "1.00")!, currency: "USD")
        XCTAssertNil(MenuBarRefreshPolicy.deepSeekTrigger(report: usd,
                                                          savedCurrency: "USD",
                                                          thresholdCNY: Decimal(string: "15.00")))
    }

    func testMenuBarAccelerationCanBeDisabledOrFailClosed() {
        let low = UsageSnapshot(
            fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                      usedPercent: 60, remainingPercent: 40, resetsAt: nil),
            weekly: nil, fetchedAt: Self.now, source: .codexAppServer)
        let disabled = MenuBarRefreshPolicy.decision(
            selection: .profile("chatgpt-a"), profileSnapshot: low, deepSeekReport: nil,
            deepSeekCurrency: nil, settings: menuBarSettings(enabled: false), normalInterval: 120)
        XCTAssertFalse(disabled.isAccelerated)

        let invalidDeepSeek = MenuBarRefreshPolicy.decision(
            selection: .deepSeek,
            profileSnapshot: nil,
            deepSeekReport: deepSeekReport(amount: Decimal(string: "1.00")!),
            deepSeekCurrency: nil,
            settings: menuBarSettings(deepSeek: nil),
            normalInterval: 300)
        XCTAssertFalse(invalidDeepSeek.isAccelerated)
    }

    func testMenuBarTimerFollowsSelectionDisableAndStopLifecycle() throws {
        let defaults = makeDefaults("menu-bar-timer")
        let preferences = MenuBarPreferences(defaults: defaults)
        let low = UsageSnapshot(
            fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                      usedPercent: 60, remainingPercent: 40, resetsAt: nil),
            weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                    usedPercent: 20, remainingPercent: 80, resetsAt: nil),
            fetchedAt: Self.now, source: .codexAppServer)
        let client = WakeClient(snapshot: low)
        let service = UsageService(factory: { client },
                                   cache: UsageCache(userDefaults: defaults))
        let coordinator = CodexProfilesCoordinator(profiles: [.chatGPTA]) { _ in service }
        _ = coordinator.fetch(profileID: "chatgpt-a")
        let engine = ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults))
        let model = UsageViewModel(coordinator: coordinator,
                                   providerEngine: engine,
                                   menuBarPreferences: preferences,
                                   refreshInterval: 120)

        model.start()
        XCTAssertEqual(model.configuredMenuBarRefreshInterval, 30)

        preferences.selection = .deepSeek
        waitForPreferencePropagation()
        XCTAssertNil(model.configuredMenuBarRefreshInterval,
                     "a source without a matching low-usage trigger must cancel the old timer")

        preferences.selection = .profile("chatgpt-a")
        waitForPreferencePropagation()
        XCTAssertEqual(model.configuredMenuBarRefreshInterval, 30)

        preferences.lowUsageRefreshEnabled = false
        waitForPreferencePropagation()
        XCTAssertNil(model.configuredMenuBarRefreshInterval)

        model.stop()
        XCTAssertNil(model.configuredMenuBarRefreshInterval)
    }

    // MARK: Wake throttling

    func testWakeRefreshIsThrottledWithinThirtySeconds() async throws {
        let client = WakeClient(snapshot: snapshot(fiveHourResetsAt: Self.now.addingTimeInterval(3600)))
        let service = UsageService(factory: { client },
                                   cache: UsageCache(userDefaults: makeDefaults("wake")))
        _ = try service.fetch()
        let model = makeModel("wake", service: service)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        model.refreshAfterWake(now: base)
        await waitUntilIdle(model)
        let reads = client.rateLimitReads
        model.refreshAfterWake(now: base.addingTimeInterval(10))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(client.rateLimitReads, reads, "a second wake inside 30 seconds must do no work")
        model.stop()
    }

    func testClockRollbackDoesNotExtendTheWakeCooldown() {
        let previous = Self.now
        XCTAssertTrue(UsageViewModel.isInsideWakeCooldown(now: previous.addingTimeInterval(29),
                                                         previous: previous))
        XCTAssertFalse(UsageViewModel.isInsideWakeCooldown(now: previous.addingTimeInterval(30),
                                                          previous: previous))
        XCTAssertFalse(UsageViewModel.isInsideWakeCooldown(now: previous.addingTimeInterval(-1),
                                                          previous: previous))
    }

    func testWakeProbesHealthyProfileAndFullyRefreshesOnlyFailedProfile() async throws {
        let defaults = makeDefaults("wake-ab")
        let initial = snapshot(fiveHourResetsAt: Self.now.addingTimeInterval(3600))
        let refreshed = snapshot(fiveHourResetsAt: Self.now.addingTimeInterval(7200))
        let clientA = WakeClient(snapshot: refreshed)
        let failedB = WakeClient(snapshot: initial)
        let replacementB = WakeClient(snapshot: refreshed)
        let factoryLock = NSLock()
        var bFactoryCalls = 0
        let coordinator = CodexProfilesCoordinator { profile in
            if profile.id == "chatgpt-a" {
                return UsageService(factory: { clientA }, cache: UsageCache(userDefaults: defaults),
                                    profileID: profile.id, restartDelay: 0)
            }
            return UsageService(factory: {
                factoryLock.lock(); defer { factoryLock.unlock() }
                bFactoryCalls += 1
                return bFactoryCalls == 1 ? failedB : replacementB
            }, cache: UsageCache(userDefaults: defaults), profileID: profile.id, restartDelay: 0)
        }
        _ = coordinator.fetch(profileID: "chatgpt-a")
        _ = coordinator.fetch(profileID: "chatgpt-b")
        failedB.readError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))

        let engine = ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults))
        let model = UsageViewModel(coordinator: coordinator, providerEngine: engine,
                                   menuBarPreferences: MenuBarPreferences(defaults: defaults))
        model.refreshAfterWake(now: Self.now)
        await waitUntilIdle(model)

        XCTAssertEqual(clientA.startCalls, 1, "healthy A reuses its existing child")
        XCTAssertEqual(clientA.accountReads, 1, "A's wake probe must not read identity")
        XCTAssertEqual(clientA.rateLimitReads, 2, "A performs exactly one wake quota read")
        XCTAssertEqual(failedB.stopCalls, 1, "B's failed client is retired")
        XCTAssertEqual(bFactoryCalls, 2, "only B creates a replacement client")
        XCTAssertEqual(replacementB.startCalls, 1)
        XCTAssertEqual(replacementB.accountReads, 1, "B's fallback is the ordinary full refresh")
        XCTAssertEqual(replacementB.rateLimitReads, 1)
        model.stop()
    }

    func testInitializerUsesTheInjectedBaseAndClockIntervals() {
        let service = UsageService(factory: { throw UsageError.rpcFailed(.other) },
                                   cache: UsageCache(userDefaults: makeDefaults("clock")),
                                   restartDelay: 0)
        let defaults = makeModel("clock-defaults", service: service)
        XCTAssertEqual(defaults.currentCodexInterval, 60)
        XCTAssertEqual(defaults.configuredClockInterval, 30)

        let injected = makeModel("clock-injected", service: service,
                                 refreshInterval: 17, clockInterval: 23)
        XCTAssertEqual(injected.currentCodexInterval, 17)
        XCTAssertEqual(injected.configuredClockInterval, 23)
    }

    private func waitUntilIdle(_ model: UsageViewModel) async {
        let deadline = Date().addingTimeInterval(3)
        while model.isRefreshing, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(model.isRefreshing, "wake refresh should finish within the test bound")
    }

    private func waitForPreferencePropagation() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: Width remeasure rule

    func testShouldRemeasureOnlyOnSignatureChange() {
        XCTAssertTrue(StatusItemController.shouldRemeasure(cachedSignature: nil, newSignature: "full#A 5H 78% | W 42%#none"))
        XCTAssertFalse(StatusItemController.shouldRemeasure(cachedSignature: "full#A 5H 78% | W 42%#none",
                                                            newSignature: "full#A 5H 78% | W 42%#none"))
        XCTAssertTrue(StatusItemController.shouldRemeasure(cachedSignature: "full#A 5H 78% | W 42%#none",
                                                           newSignature: "full#A 5H 79% | W 42%#none"))
        XCTAssertTrue(StatusItemController.shouldRemeasure(cachedSignature: "full#A 5H 78% | W 42%#none",
                                                           newSignature: "full#A 5H 78% | W 42%#warning"))
    }
}

private final class WakeClient: CodexAppServerProviding {
    private let lock = NSLock()
    private let snapshot: UsageSnapshot
    private var running = true
    var readError: UsageError?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var handshakeCalls = 0
    private(set) var rateLimitReads = 0
    private(set) var accountReads = 0

    init(snapshot: UsageSnapshot) { self.snapshot = snapshot }

    func start() throws {
        lock.lock(); defer { lock.unlock() }
        startCalls += 1
        running = true
    }

    func handshake(timeout: TimeInterval) throws {
        lock.lock(); handshakeCalls += 1; lock.unlock()
    }

    func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
        lock.lock()
        rateLimitReads += 1
        let error = readError
        lock.unlock()
        if let error { throw error }
        return snapshot
    }

    func readAccount(timeout: TimeInterval) throws -> CodexAccount? {
        lock.lock(); accountReads += 1; lock.unlock()
        return CodexAccount(kind: .chatgpt, email: "test@example.invalid", planType: nil)
    }

    func stop() {
        lock.lock(); stopCalls += 1; running = false; lock.unlock()
    }

    var isTransportRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }
}

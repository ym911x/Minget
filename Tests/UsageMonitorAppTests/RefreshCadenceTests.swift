import XCTest
import AppKit
import UsageMonitorCore
@testable import UsageMonitorApp

/// Cadence rules behind the 1.3.2 refresh savings: which interval the ChatGPT timer uses,
/// how the wake refresh is throttled, and when the menu bar re-measures. Pure state and
/// fake clocks only: no real sleep, no long waits.
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

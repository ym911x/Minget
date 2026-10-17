import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// 1.6.9 的刷新范围规则（REQUIREMENTS.md §1–§3）：菜单栏只维护显示的那一个来源，其余账号
/// 只在打开页面或切换标签时按整批 5 分钟门槛补刷一次。
///
/// Every case here counts reads, so "the other accounts were not asked" is a measured fact
/// rather than an assumption about which function a path calls.
@MainActor
final class RefreshScopeTests: XCTestCase {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Fixtures

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "UsageMonitorAppTests.RefreshScope.\(label)." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    /// A codex client that counts its reads and can be made to fail.
    private final class CountingCodexClient: CodexAppServerProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var reads = 0
        var readError: UsageError?
        var isTransportRunning = true

        var readCount: Int {
            lock.lock(); defer { lock.unlock() }
            return reads
        }

        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func stop() { isTransportRunning = false }

        func readAccount(timeout: TimeInterval) throws -> CodexAccount? {
            CodexAccount(kind: .chatgpt, email: "demo@example.com", planType: "plus")
        }

        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            lock.lock(); reads += 1; let error = readError; lock.unlock()
            if let error { throw error }
            let stamp = Date()
            return UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                           usedPercent: 10, remainingPercent: 90,
                                                           resetsAt: stamp.addingTimeInterval(3600)),
                                 weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                                         usedPercent: 50, remainingPercent: 50,
                                                         resetsAt: stamp.addingTimeInterval(3 * 86400)),
                                 fetchedAt: stamp, source: .codexAppServer)
        }
    }

    /// A platform reader that counts its reads, so a page's request is observed while every
    /// other account's count stays put.
    private final class CountingReader: ProviderReading, @unchecked Sendable {
        let platform: ProviderPlatform
        var isConfigured = true
        var isAutomaticRefreshEnabled = true
        private let lock = NSLock()
        private var reads = 0

        init(platform: ProviderPlatform) { self.platform = platform }

        var readCount: Int {
            lock.lock(); defer { lock.unlock() }
            return reads
        }

        func read() async throws -> ProviderReadResult {
            lock.lock(); reads += 1; lock.unlock()
            return ProviderReadResult(accountID: "acct-\(platform.rawValue)", balances: [], usage: nil,
                                      consoleURL: nil)
        }

        func disconnect() throws {}
    }

    private struct Harness {
        let model: UsageViewModel
        let preferences: MenuBarPreferences
        let clients: [String: CountingCodexClient]
        let readers: [ProviderPlatform: CountingReader]

        func profileReads(_ id: String) -> Int { clients[id]?.readCount ?? -1 }
        func platformReads(_ platform: ProviderPlatform) -> Int { readers[platform]?.readCount ?? -1 }
    }

    /// Legacy (no registry) composition: two ChatGPT profiles plus both provider platforms.
    private func makeHarness(_ label: String,
                             profiles: [ChatGPTAccountProfile] = [.chatGPTA, .chatGPTB],
                             platforms: [ProviderPlatform] = [.deepseek, .commandcode]) -> Harness {
        let defaults = makeDefaults(label)
        let clients = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, CountingCodexClient()) })
        let coordinator = CodexProfilesCoordinator(profiles: profiles) { profile in
            UsageService(factory: { clients[profile.id]! },
                         cache: UsageCache(userDefaults: defaults),
                         profileID: profile.id, restartDelay: 0)
        }
        let readers = Dictionary(uniqueKeysWithValues: platforms.map { ($0, CountingReader(platform: $0)) })
        let engine = ProviderRefreshEngine(readers: platforms.map { readers[$0]! },
                                           cache: ProviderCache(userDefaults: defaults))
        let preferences = MenuBarPreferences(defaults: defaults)
        let model = UsageViewModel(coordinator: coordinator,
                                   providerEngine: engine,
                                   menuBarPreferences: preferences,
                                   displayNames: DisplayNamePreferences(defaults: defaults),
                                   fireSchedules: FireSchedulePreferences(defaults: defaults),
                                   fireConfirmDelay: 0, fireRetryDelay: 0)
        return Harness(model: model, preferences: preferences, clients: clients, readers: readers)
    }

    // MARK: Menu bar target

    func testMenuBarTargetMapsEverySelectionKind() {
        XCTAssertEqual(RefreshBatchPolicy.menuBarTarget(selection: .profile("chatgpt-a"), isRegistryMode: false),
                       .chatGPTProfile("chatgpt-a"))
        XCTAssertEqual(RefreshBatchPolicy.menuBarTarget(selection: .google("a@example.invalid"), isRegistryMode: false),
                       .googleAccount("a@example.invalid"))
        XCTAssertEqual(RefreshBatchPolicy.menuBarTarget(selection: .apiAccount("ds2"), isRegistryMode: true),
                       .apiAccount("ds2"))
        XCTAssertEqual(RefreshBatchPolicy.menuBarTarget(selection: .deepSeek, isRegistryMode: false),
                       .providerPlatform(.deepseek))
        XCTAssertEqual(RefreshBatchPolicy.menuBarTarget(selection: .deepSeek, isRegistryMode: true),
                       .apiAccount("deepseek"),
                       "the registry keeps the legacy DeepSeek connection under this fixed id")
    }

    // MARK: Batch membership

    func testBatchMembersExcludeTheDisplayedAccountAndStayInsideThePage() {
        var inventory = RefreshInventory()
        inventory.chatGPTProfileIDs = ["chatgpt-a", "chatgpt-b"]
        inventory.googleAccountIDs = ["a@example.invalid"]
        inventory.legacyDeepSeek = true
        inventory.legacyCommandCode = true

        let overview = RefreshBatchPolicy.members(scope: .overview, selection: .profile("chatgpt-a"),
                                                  inventory: inventory, isRegistryMode: false)
        XCTAssertEqual(overview, [.chatGPTProfile("chatgpt-b"), .googleAccount("a@example.invalid"),
                                  .providerPlatform(.deepseek), .providerPlatform(.commandcode)],
                       "the overview reads every account except the menu bar source")

        let chatGPT = RefreshBatchPolicy.members(scope: .chatGPT, selection: .profile("chatgpt-a"),
                                                 inventory: inventory, isRegistryMode: false)
        XCTAssertEqual(chatGPT, [.chatGPTProfile("chatgpt-b")])

        let deepSeek = RefreshBatchPolicy.members(scope: .deepSeek, selection: .deepSeek,
                                                  inventory: inventory, isRegistryMode: false)
        XCTAssertTrue(deepSeek.isEmpty,
                      "a brand page whose only account is displayed has nothing to read")

        let commandCode = RefreshBatchPolicy.members(scope: .commandCode, selection: .deepSeek,
                                                     inventory: inventory, isRegistryMode: false)
        XCTAssertEqual(commandCode, [.providerPlatform(.commandcode)],
                       "another brand's page never touches the displayed DeepSeek connection")
    }

    func testRegistryModeBatchExcludesTheDisplayedManagedAccount() {
        var inventory = RefreshInventory()
        inventory.managedDeepSeekIDs = ["deepseek", "ds2"]
        inventory.managedCommandCodeIDs = ["cc1"]

        let deepSeek = RefreshBatchPolicy.members(scope: .deepSeek, selection: .apiAccount("ds2"),
                                                  inventory: inventory, isRegistryMode: true)
        XCTAssertEqual(deepSeek, [.apiAccount("deepseek")])

        let overview = RefreshBatchPolicy.members(scope: .overview, selection: .apiAccount("ds2"),
                                                  inventory: inventory, isRegistryMode: true)
        XCTAssertEqual(overview, [.apiAccount("deepseek"), .apiAccount("cc1")])
    }

    func testLegacyPlatformsOnlyEnterTheBatchWithAConfiguredCredential() {
        var inventory = RefreshInventory()
        inventory.chatGPTProfileIDs = ["chatgpt-a", "chatgpt-b"]
        inventory.legacyDeepSeek = false
        inventory.legacyCommandCode = true

        let overview = RefreshBatchPolicy.members(scope: .overview, selection: .profile("chatgpt-a"),
                                                  inventory: inventory, isRegistryMode: false)
        XCTAssertEqual(overview, [.chatGPTProfile("chatgpt-b"), .providerPlatform(.commandcode)])
    }

    // MARK: Gate

    func testBatchGateSkipsOnlyWhenEveryMemberWasAttemptedRecently() {
        let now = Self.now
        let fresh = now.addingTimeInterval(-60)
        let atTheAge = now.addingTimeInterval(-RefreshBatchPolicy.batchAge)
        let members: [RefreshTarget] = [.chatGPTProfile("chatgpt-b"), .providerPlatform(.commandcode)]

        XCTAssertEqual(RefreshBatchPolicy.batchAge, 5 * 60)
        XCTAssertTrue(RefreshBatchPolicy.needsRefresh(members, attempts: [:], now: now),
                      "an account that was never read keeps the batch due")
        XCTAssertTrue(RefreshBatchPolicy.needsRefresh(members,
                                                       attempts: [.chatGPTProfile("chatgpt-b"): fresh],
                                                       now: now),
                      "one stale member makes the whole batch due")
        XCTAssertTrue(RefreshBatchPolicy.needsRefresh(members,
                                                       attempts: [.chatGPTProfile("chatgpt-b"): fresh,
                                                                  .providerPlatform(.commandcode): atTheAge],
                                                       now: now),
                      "exactly the batch age is already past")
        XCTAssertFalse(RefreshBatchPolicy.needsRefresh(members,
                                                        attempts: [.chatGPTProfile("chatgpt-b"): fresh,
                                                                   .providerPlatform(.commandcode): fresh],
                                                        now: now))
        XCTAssertTrue(RefreshBatchPolicy.needsRefresh(members,
                                                       attempts: [.chatGPTProfile("chatgpt-b"): now.addingTimeInterval(60),
                                                                  .providerPlatform(.commandcode): fresh],
                                                       now: now),
                      "a future timestamp from a clock change never silences the batch")
    }

    // MARK: Launch and the menu bar loop

    func testLaunchReadsOnlyTheDisplayedProfile() async {
        let harness = makeHarness("launch")
        harness.model.start()
        defer { harness.model.stop() }

        let displayedRead = await waitUntil { harness.profileReads("chatgpt-a") == 1 }
        XCTAssertTrue(displayedRead, "the displayed profile is read at launch")
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(harness.profileReads("chatgpt-b"), 0,
                       "the hidden profile is never read at launch")
        XCTAssertEqual(harness.platformReads(.deepseek), 0)
        XCTAssertEqual(harness.platformReads(.commandcode), 0)
    }

    func testMenuBarLoopReadsOnlyTheDisplayedSource() async {
        let harness = makeHarness("loop")
        harness.model.start()
        defer { harness.model.stop() }
        let launchRead = await waitUntil { harness.profileReads("chatgpt-a") == 1 }
        XCTAssertTrue(launchRead)

        harness.preferences.selection = .profile("chatgpt-b")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        harness.model.scheduledMenuBarRefresh()

        let switchedRead = await waitUntil { harness.profileReads("chatgpt-b") == 1 }
        XCTAssertTrue(switchedRead, "one round reads the newly displayed profile")
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(harness.profileReads("chatgpt-a"), 1,
                       "the previous source is no longer maintained")
        XCTAssertEqual(harness.platformReads(.deepseek), 0)
    }

    func testTheDisplayedDeepSeekBalanceIsExcludedFromEveryPageBatch() async {
        let harness = makeHarness("deepseek-source")
        harness.preferences.selection = .deepSeek
        harness.model.start()
        defer { harness.model.stop() }

        let launchRead = await waitUntil { harness.platformReads(.deepseek) == 1 }
        XCTAssertTrue(launchRead, "the displayed DeepSeek balance is read at launch")
        XCTAssertEqual(harness.profileReads("chatgpt-a"), 0)

        harness.model.panelWillOpen(tab: .all)
        let overviewRead = await waitUntil {
            harness.profileReads("chatgpt-a") == 1 && harness.profileReads("chatgpt-b") == 1
                && harness.platformReads(.commandcode) == 1
        }
        XCTAssertTrue(overviewRead)
        XCTAssertEqual(harness.platformReads(.deepseek), 1,
                       "the displayed balance keeps its own loop cadence")
    }

    // MARK: Page batches

    func testOpeningTheOverviewReadsEveryHiddenAccountOnce() async {
        let harness = makeHarness("overview")
        harness.model.start()
        defer { harness.model.stop() }
        let launchRead = await waitUntil { harness.profileReads("chatgpt-a") == 1 }
        XCTAssertTrue(launchRead)

        harness.model.panelWillOpen(tab: .all)
        let batchRead = await waitUntil {
            harness.profileReads("chatgpt-b") == 1
                && harness.platformReads(.deepseek) == 1
                && harness.platformReads(.commandcode) == 1
        }
        XCTAssertTrue(batchRead, "the overview reads every hidden account once")
        XCTAssertEqual(harness.profileReads("chatgpt-a"), 1)

        harness.model.panelWillOpen(tab: .all)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(harness.profileReads("chatgpt-b"), 1, "inside five minutes the batch is skipped")
        XCTAssertEqual(harness.platformReads(.deepseek), 1)
        XCTAssertEqual(harness.platformReads(.commandcode), 1)
    }

    func testABatchPastTheAgeReadsAgain() async {
        let harness = makeHarness("overview-age")
        harness.model.start()
        defer { harness.model.stop() }
        let launchRead = await waitUntil { harness.profileReads("chatgpt-a") == 1 }
        XCTAssertTrue(launchRead)

        harness.model.panelWillOpen(tab: .all)
        let firstBatch = await waitUntil { harness.profileReads("chatgpt-b") == 1 }
        XCTAssertTrue(firstBatch)

        harness.model.panelWillOpen(tab: .all,
                                    now: Date().addingTimeInterval(RefreshBatchPolicy.batchAge + 1))
        let secondBatch = await waitUntil { harness.profileReads("chatgpt-b") == 2 }
        XCTAssertTrue(secondBatch, "past the batch age the page reads once more")
        let platformAgain = await waitUntil { harness.platformReads(.deepseek) == 2 }
        XCTAssertTrue(platformAgain)
    }

    func testSwitchingToABrandPageReadsOnlyThatBrand() async {
        let harness = makeHarness("brand-switch")
        harness.model.start()
        defer { harness.model.stop() }
        let launchRead = await waitUntil { harness.profileReads("chatgpt-a") == 1 }
        XCTAssertTrue(launchRead)

        harness.model.panelDidSwitchTab(.chatGPT)
        let chatGPTRead = await waitUntil { harness.profileReads("chatgpt-b") == 1 }
        XCTAssertTrue(chatGPTRead)
        XCTAssertEqual(harness.profileReads("chatgpt-a"), 1)
        XCTAssertEqual(harness.platformReads(.deepseek), 0)
        XCTAssertEqual(harness.platformReads(.commandcode), 0)

        harness.model.panelDidSwitchTab(.commandCode)
        let commandRead = await waitUntil { harness.platformReads(.commandcode) == 1 }
        XCTAssertTrue(commandRead)
        XCTAssertEqual(harness.platformReads(.deepseek), 0,
                       "another brand is never part of the page batch")

        harness.model.panelDidSwitchTab(.chatGPT)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(harness.profileReads("chatgpt-b"), 1,
                       "switching back inside the window is a no-op")
    }

    func testTheWholeBatchReadsTogetherWhenOneMemberIsStale() async {
        let harness = makeHarness("whole-batch")
        harness.model.start()
        defer { harness.model.stop() }
        let launchRead = await waitUntil { harness.profileReads("chatgpt-a") == 1 }
        XCTAssertTrue(launchRead)

        harness.model.panelDidSwitchTab(.chatGPT)
        let brandRead = await waitUntil { harness.profileReads("chatgpt-b") == 1 }
        XCTAssertTrue(brandRead)

        harness.model.panelWillOpen(tab: .all)
        let platforms = await waitUntil {
            harness.platformReads(.deepseek) == 1 && harness.platformReads(.commandcode) == 1
        }
        XCTAssertTrue(platforms)
        let sibling = await waitUntil { harness.profileReads("chatgpt-b") == 2 }
        XCTAssertTrue(sibling,
                      "the batch reads as one unit: a stale member brings its fresh sibling along")
    }

    func testFailedAttemptsStillCloseTheBatchGate() async {
        let harness = makeHarness("failure")
        harness.clients["chatgpt-b"]?.readError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        harness.model.start()
        defer { harness.model.stop() }
        let launchRead = await waitUntil { harness.profileReads("chatgpt-a") == 1 }
        XCTAssertTrue(launchRead)

        harness.model.panelWillOpen(tab: .chatGPT)
        let attempted = await waitUntil { harness.profileReads("chatgpt-b") >= 1 }
        XCTAssertTrue(attempted)
        try? await Task.sleep(nanoseconds: 250_000_000)
        let settled = harness.profileReads("chatgpt-b")
        XCTAssertNotNil(harness.model.lastRefreshAttempt(for: .chatGPTProfile("chatgpt-b")),
                        "a failed read still records the attempt")

        harness.model.panelDidSwitchTab(.chatGPT)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(harness.profileReads("chatgpt-b"), settled,
                       "a failed read counts as the batch's attempt")
    }

    func testManualRefreshIgnoresTheBatchGate() async {
        let harness = makeHarness("manual")
        harness.model.start()
        defer { harness.model.stop() }
        let launchRead = await waitUntil { harness.profileReads("chatgpt-a") == 1 }
        XCTAssertTrue(launchRead)

        harness.model.panelWillOpen(tab: .all)
        let batchRead = await waitUntil {
            harness.profileReads("chatgpt-b") == 1 && harness.platformReads(.deepseek) == 1
        }
        XCTAssertTrue(batchRead)
        harness.model.panelWillOpen(tab: .all)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(harness.profileReads("chatgpt-b"), 1, "precondition: the gate is closed")

        harness.model.refreshNow()
        let manualRead = await waitUntil {
            harness.profileReads("chatgpt-a") == 2 && harness.profileReads("chatgpt-b") == 2
                && harness.platformReads(.deepseek) == 2 && harness.platformReads(.commandcode) == 2
        }
        XCTAssertTrue(manualRead, "a manual refresh reads every account regardless of the gate")
    }
}

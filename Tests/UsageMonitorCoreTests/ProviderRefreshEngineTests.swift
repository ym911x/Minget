import XCTest
@testable import UsageMonitorCore

/// Refresh policy for the detail-panel providers: dedupe, staleness, auth suspension and
/// disconnect cleanup.
final class ProviderRefreshEngineTests: XCTestCase {

    // MARK: Fakes

    /// Reader whose behaviour the test drives directly.
    final class FakeReader: ProviderReading, @unchecked Sendable {
        let platform: ProviderPlatform
        var configured = true
        var automatic = true
        var result: Result<ProviderReadResult, ProviderFailure> = .success(ProviderReadResult(accountID: "acct", balances: [], consoleURL: nil))
        private let lock = NSLock()
        private var reads = 0
        /// When set, `read` waits on this gate before returning, so a test can hold a read
        /// in flight and observe what a concurrent caller sees.
        var gate: DispatchSemaphore?

        init(platform: ProviderPlatform) { self.platform = platform }

        var readCount: Int {
            lock.lock(); defer { lock.unlock() }
            return reads
        }

        var isConfigured: Bool { configured }
        var isAutomaticRefreshEnabled: Bool { automatic }

        func read() async throws -> ProviderReadResult {
            bumpReadCount()
            holdOnGate()
            switch result {
            case .success(let value): return value
            case .failure(let failure): throw failure
            }
        }

        /// Synchronous helpers: `lock`/`wait` are unavailable from async contexts.
        private func bumpReadCount() {
            lock.lock(); defer { lock.unlock() }
            reads += 1
        }

        private func holdOnGate() {
            guard let gate else { return }
            _ = gate.wait(timeout: .now() + 5)
        }

        func disconnect() throws {
            configured = false
        }
    }

    private func balance(_ currency: String, _ amount: String) -> ProviderBalance {
        return ProviderBalance(currency: currency, total: dec(amount), granted: nil, toppedUp: nil)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageMonitorTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Pause at the timestamp hook between receipt and commit, then disconnect on a
    /// different thread. The old implementation checked generation before this hook
    /// and resurrected the cache after disconnect. Commit now owns the same lock.
    func testDisconnectDuringCommitCannotResurrectCache() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .success(ProviderReadResult(accountID: "old", balances: [balance("CNY", "10")], consoleURL: nil))
        let cache = ProviderCache(userDefaults: makeDefaults())
        let entered = DispatchSemaphore(value: 0)
        let disconnected = DispatchSemaphore(value: 0)
        let engine = ProviderRefreshEngine(readers: [reader], cache: cache, clock: {
            entered.signal()
            _ = disconnected.wait(timeout: .now() + 0.3)
            return Date()
        })
        let done = expectation(description: "disconnect finished")
        DispatchQueue.global().async {
            guard entered.wait(timeout: .now() + 3) == .success else { done.fulfill(); return }
            engine.disconnect(platform: .deepseek)
            disconnected.signal()
            done.fulfill()
        }
        _ = await engine.refresh(platform: .deepseek, force: true)
        await fulfillment(of: [done], timeout: 4)
        XCTAssertNil(cache.load(platform: .deepseek, accountID: "old"))
        XCTAssertEqual(engine.report(for: .deepseek).connection, .notConfigured)
    }

    // MARK: Dedupe

    func testConcurrentRefreshesAreCoalescedIntoOneRequest() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .success(ProviderReadResult(accountID: "acct",
                                                    balances: [balance("CNY", "10.00")],
                                                    consoleURL: nil))
        reader.gate = DispatchSemaphore(value: 0)
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: makeDefaults()))

        async let first = engine.refresh(platform: .deepseek, force: true)
        // Give the first task a moment to claim the in-flight slot, then join it.
        try? await Task.sleep(nanoseconds: 100_000_000)
        async let second = engine.refresh(platform: .deepseek, force: true)

        reader.gate?.signal()
        let (a, b) = await (first, second)

        XCTAssertEqual(reader.readCount, 1, "two concurrent refreshes must produce one read")
        XCTAssertEqual(a.balances, b.balances)
        XCTAssertEqual(a.connection, .connected)
    }

    func testRefreshIsSkippedWhenNotConfigured() async {
        let reader = FakeReader(platform: .deepseek)
        reader.configured = false
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: makeDefaults()))

        let report = await engine.refresh(platform: .deepseek)
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertEqual(report.connection, .notConfigured)
    }

    // MARK: Staleness

    func testFailureKeepsTheLastSuccessfulValueAndMarksItStale() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .success(ProviderReadResult(accountID: "acct",
                                                    balances: [balance("CNY", "42.00")],
                                                    consoleURL: nil))
        let cache = ProviderCache(userDefaults: makeDefaults())
        let engine = ProviderRefreshEngine(readers: [reader], cache: cache)

        let good = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertEqual(good.connection, .connected)
        XCTAssertEqual(good.balances.first?.total, dec("42.00"))

        // Network disappears: the previous value stays, marked stale, never zero.
        reader.result = .failure(.networkUnreachable)
        let bad = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertEqual(bad.connection, .stale)
        XCTAssertEqual(bad.balances.first?.total, dec("42.00"), "the last success survives")
        XCTAssertFalse(bad.balances.isEmpty, "a failure must not be displayed as a zero balance")
        XCTAssertEqual(bad.error, .networkUnreachable)
        XCTAssertNotNil(bad.lastSuccessAt)
    }

    func testFailureWithNoPreviousSuccessIsUnavailableWithNoAmounts() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .failure(.timedOut)
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: makeDefaults()))

        let report = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertEqual(report.connection, .unavailable)
        XCTAssertTrue(report.balances.isEmpty)
        XCTAssertNil(report.lastSuccessAt)
    }

    func testNothingIsCachedWhenTheAccountIsUnknown() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .success(ProviderReadResult(accountID: nil,
                                                    balances: [balance("CNY", "1.00")],
                                                    consoleURL: nil))
        let cache = ProviderCache(userDefaults: makeDefaults())
        let engine = ProviderRefreshEngine(readers: [reader], cache: cache)

        let report = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertEqual(report.connection, .connected)
        XCTAssertTrue(cache.allKeys().isEmpty, "an unattributed entry must not be written")
    }

    func testUsageSurvivesThePostRefreshReportPublication() async {
        let reader = FakeReader(platform: .commandcode)
        let usage = ProviderUsage(
            windows: [ProviderUsageWindow(kind: .fiveHour, used: dec("1"), limit: dec("5"), remaining: dec("4"), resetsAt: nil)],
            summary: ProviderUsageSummary(totalTokens: 42, inputTokens: 30, outputTokens: 12,
                                          totalRuns: 3, completedRuns: 3, failedRuns: 0,
                                          successRate: dec("100"), totalCostUSD: dec("0.01"), periodBasis: .billingPeriod))
        reader.result = .success(ProviderReadResult(accountID: "command-account", balances: [], usage: usage, consoleURL: nil))
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: makeDefaults()))

        let immediate = await engine.refresh(platform: .commandcode, force: true)
        XCTAssertEqual(immediate.usage, usage)

        // UsageViewModel publishes `allReports()` after the request task finishes. This must
        // preserve the same cached usage instead of reverting the card to its empty state.
        let published = engine.report(for: .commandcode)
        XCTAssertEqual(published.connection, .connected)
        XCTAssertEqual(published.usage, usage)
    }

    func testUsageSurvivesAPostSuccessCacheReadFailure() async {
        let suite = makeDefaults()
        let reader = FakeReader(platform: .commandcode)
        let usage = ProviderUsage(windows: [],
                                  summary: ProviderUsageSummary(totalTokens: 7, inputTokens: nil, outputTokens: nil,
                                                               totalRuns: 1, completedRuns: 1, failedRuns: 0,
                                                               successRate: dec("100"), totalCostUSD: nil, periodBasis: .unknown))
        reader.result = .success(ProviderReadResult(accountID: "command-account", balances: [], usage: usage, consoleURL: nil))
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: suite))
        _ = await engine.refresh(platform: .commandcode, force: true)

        // A corrupt persisted store must not make a fresh, already committed response vanish
        // when the view model immediately republishes reports.
        suite.set(Data("not provider cache json".utf8), forKey: "UsageMonitor.providerBalances.v2")
        XCTAssertEqual(engine.report(for: .commandcode).usage, usage)
    }

    // MARK: Auth suspension

    func testAuthenticationFailureSuspendsAutomaticRefresh() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .failure(.invalidCredential)
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: makeDefaults()))

        let report = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertEqual(report.connection, .authSuspended)
        XCTAssertTrue(engine.isAuthSuspended(.deepseek))

        await engine.refreshScheduled()
        XCTAssertEqual(reader.readCount, 1, "an auth suspension must stop further automatic reads")
    }

    func testReconnectClearsTheSuspensionAndReadsImmediately() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .failure(.invalidCredential)
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: makeDefaults()))
        _ = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertTrue(engine.isAuthSuspended(.deepseek))

        reader.result = .success(ProviderReadResult(accountID: "acct",
                                                    balances: [balance("CNY", "7.00")],
                                                    consoleURL: nil))
        let report = await engine.reconnect(platform: .deepseek)
        XCTAssertFalse(engine.isAuthSuspended(.deepseek))
        XCTAssertEqual(report.connection, .connected)
        XCTAssertEqual(report.balances.first?.total, dec("7.00"))
        XCTAssertEqual(reader.readCount, 2)
    }

    func testManualRefreshStillWorksWhileSuspended() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .failure(.invalidCredential)
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: makeDefaults()))
        _ = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertTrue(engine.isAuthSuspended(.deepseek))

        reader.result = .success(ProviderReadResult(accountID: "acct",
                                                    balances: [balance("CNY", "3.00")],
                                                    consoleURL: nil))
        let forced = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertEqual(forced.connection, .connected)
    }

    // MARK: Account isolation

    func testCacheIsIsolatedPerAccount() async {
        let cache = ProviderCache(userDefaults: makeDefaults())
        let reader = FakeReader(platform: .deepseek)
        let engine = ProviderRefreshEngine(readers: [reader], cache: cache)

        reader.result = .success(ProviderReadResult(accountID: "acct-a",
                                                    balances: [balance("CNY", "10.00")],
                                                    consoleURL: nil))
        _ = await engine.refresh(platform: .deepseek, force: true)

        reader.result = .success(ProviderReadResult(accountID: "acct-b",
                                                    balances: [balance("CNY", "20.00")],
                                                    consoleURL: nil))
        _ = await engine.refresh(platform: .deepseek, force: true)

        XCTAssertEqual(cache.load(platform: .deepseek, accountID: "acct-a")?.providerBalances.first?.total,
                       dec("10.00"))
        XCTAssertEqual(cache.load(platform: .deepseek, accountID: "acct-b")?.providerBalances.first?.total,
                       dec("20.00"))
        XCTAssertNotEqual(cache.load(platform: .deepseek, accountID: "acct-a"),
                          cache.load(platform: .deepseek, accountID: "acct-b"),
                          "two accounts on one platform must not share numbers")
    }

    // MARK: Disconnect cleanup

    func testDisconnectClearsCredentialAndCache() async {
        let reader = FakeReader(platform: .deepseek)
        reader.result = .success(ProviderReadResult(accountID: "acct",
                                                    balances: [balance("CNY", "10.00")],
                                                    consoleURL: nil))
        let cache = ProviderCache(userDefaults: makeDefaults())
        let engine = ProviderRefreshEngine(readers: [reader], cache: cache)
        _ = await engine.refresh(platform: .deepseek, force: true)
        XCTAssertNotNil(cache.load(platform: .deepseek, accountID: "acct"))

        engine.disconnect(platform: .deepseek)

        XCTAssertFalse(reader.configured, "the credential must be removed")
        XCTAssertTrue(cache.allKeys().isEmpty, "the platform's cached numbers must be removed")
        XCTAssertEqual(engine.report(for: .deepseek).connection, .notConfigured)
    }

    // MARK: Credential generation (REVIEW round 8 finding 2)

    /// A reader that parks each read until the test completes it by index, so
    /// out-of-order completion can be modeled deterministically.
    final class GatedReader: ProviderReading, @unchecked Sendable {
        let platform: ProviderPlatform
        private let lock = NSLock()
        private var pending: [CheckedContinuation<ProviderReadResult, Error>] = []
        private(set) var readCount = 0

        init(platform: ProviderPlatform) { self.platform = platform }
        var isConfigured: Bool { true }
        var isAutomaticRefreshEnabled: Bool { true }

        func read() async throws -> ProviderReadResult {
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock(); readCount += 1; pending.append(continuation); lock.unlock()
            }
        }

        var pendingCount: Int {
            lock.lock(); defer { lock.unlock() }
            return pending.count
        }

        func complete(at index: Int, with result: ProviderReadResult) {
            lock.lock()
            guard pending.count > index else {
                lock.unlock()
                return
            }
            let continuation = pending.remove(at: index)
            lock.unlock()
            continuation.resume(returning: result)
        }

        func fail(at index: Int, with failure: ProviderFailure) {
            lock.lock()
            guard pending.count > index else {
                lock.unlock()
                return
            }
            let continuation = pending.remove(at: index)
            lock.unlock()
            continuation.resume(throwing: failure)
        }

        func disconnect() throws {}
    }

    /// The load-bearing race: account A's read is in flight when the credential changes to
    /// B; A completes after B. A's outcome (success or failure) must never overwrite B's
    /// state or cache, and B must start its own read rather than awaiting A's.
    func testASupersededReadCannotOverwriteANewerCredential() async throws {
        let reader = GatedReader(platform: .deepseek)
        let cache = ProviderCache(userDefaults: makeDefaults())
        let engine = ProviderRefreshEngine(readers: [reader], cache: cache)

        // Account A's read starts and parks on the wire.
        let firstRefresh = Task { await engine.refresh(platform: .deepseek, force: true) }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && reader.pendingCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(reader.pendingCount, 1)

        // The credential changes; reconnect must NOT await A's superseded read.
        engine.invalidateAttribution(platform: .deepseek)
        let reconnect = Task { await engine.reconnect(platform: .deepseek) }
        while Date() < deadline && reader.pendingCount < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(reader.readCount, 2, "a new credential starts its own read")

        // B completes first, A completes after it (the review's exact ordering).
        reader.complete(at: 1, with: ProviderReadResult(
            accountID: "acct-b",
            balances: [ProviderBalance(currency: "CNY", total: dec("20.00"), granted: nil, toppedUp: nil)],
            consoleURL: nil))
        let bReport = await reconnect.value
        XCTAssertEqual(bReport.accountID, "acct-b")
        XCTAssertEqual(bReport.balances.first?.total, dec("20.00"))

        reader.complete(at: 0, with: ProviderReadResult(
            accountID: "acct-a",
            balances: [ProviderBalance(currency: "CNY", total: dec("10.00"), granted: nil, toppedUp: nil)],
            consoleURL: nil))
        _ = await firstRefresh.value

        // Settle: if the superseded task (wrongly) wrote state, it would show here.
        try await Task.sleep(nanoseconds: 150_000_000)

        let report = engine.report(for: .deepseek)
        XCTAssertEqual(report.accountID, "acct-b", "A's late completion must not overwrite B")
        XCTAssertEqual(report.balances.first?.total, dec("20.00"))
        XCTAssertNil(cache.load(platform: .deepseek, accountID: "acct-a"),
                     "the superseded outcome must not touch the cache")
        XCTAssertNotNil(cache.load(platform: .deepseek, accountID: "acct-b"))
    }

    /// A superseded FAILURE is discarded too: A failing with a bad credential after B
    /// succeeded must not suspend B's automatic refresh.
    func testASupersededFailureCannotSuspendANewerCredential() async throws {
        let reader = GatedReader(platform: .deepseek)
        let engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: makeDefaults()))

        let firstRefresh = Task { await engine.refresh(platform: .deepseek, force: true) }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && reader.pendingCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        engine.invalidateAttribution(platform: .deepseek)
        let reconnect = Task { await engine.reconnect(platform: .deepseek) }
        while Date() < deadline && reader.pendingCount < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        reader.complete(at: 1, with: ProviderReadResult(
            accountID: "acct-b",
            balances: [ProviderBalance(currency: "CNY", total: dec("7.00"), granted: nil, toppedUp: nil)],
            consoleURL: nil))
        _ = await reconnect.value

        // A's read then fails with a rejected credential, landing AFTER B's success.
        reader.fail(at: 0, with: ProviderFailure.invalidCredential)
        _ = await firstRefresh.value

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(engine.isAuthSuspended(.deepseek),
                       "a superseded failure must not suspend the newer credential")
        XCTAssertEqual(engine.report(for: .deepseek).connection, .connected)
    }

    // MARK: Provider cache

    func testProviderCacheIsolatesAccounts() {
        let cache = ProviderCache(userDefaults: makeDefaults())
        let at = Date(timeIntervalSince1970: 1_700_000_000)

        cache.save(platform: .deepseek, accountID: "a", balances: [balance("CNY", "1.00")], lastSuccessAt: at)
        cache.save(platform: .deepseek, accountID: "b", balances: [balance("CNY", "2.00")], lastSuccessAt: at)

        XCTAssertEqual(cache.load(platform: .deepseek, accountID: "a")?.providerBalances.first?.total, dec("1.00"))
        XCTAssertEqual(cache.load(platform: .deepseek, accountID: "b")?.providerBalances.first?.total, dec("2.00"))

        cache.clear(platform: .deepseek, accountID: "a")
        XCTAssertNil(cache.load(platform: .deepseek, accountID: "a"))
        XCTAssertNotNil(cache.load(platform: .deepseek, accountID: "b"))
    }

    func testProviderCacheRejectsAnEmptyAccountIdentifier() {
        let cache = ProviderCache(userDefaults: makeDefaults())
        cache.save(platform: .deepseek, accountID: "", balances: [balance("CNY", "1.00")], lastSuccessAt: Date())
        XCTAssertNil(cache.load(platform: .deepseek, accountID: ""))
        XCTAssertTrue(cache.allKeys().isEmpty, "no unattributed entry may be written")
    }
}

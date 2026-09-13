import XCTest
@testable import UsageMonitorCore

/// `account/read` identity handling and the account-scoped usage cache
/// (v1.1 requirement 2).
final class CodexAccountTests: XCTestCase {

    // MARK: Parsing

    func testChatgptAccountWithEmailIsParsed() {
        let account = CodexAccountParser.parse(result: [
            "requiresOpenaiAuth": false,
            "account": ["type": "chatgpt", "email": "someone@example.com", "planType": "plus"],
        ])
        XCTAssertEqual(account?.kind, .chatgpt)
        XCTAssertEqual(account?.displayEmail, "someone@example.com")
        XCTAssertEqual(account?.planType, "plus")
        XCTAssertEqual(account?.displayPlanType, "plus")
        XCTAssertEqual(account?.debugSummary, "chatgpt(plus)", "the summary must not contain the address")
    }

    func testEmailMayBeNull() {
        let account = CodexAccountParser.parse(result: [
            "account": ["type": "chatgpt", "email": NSNull(), "planType": "free"],
        ])
        XCTAssertEqual(account?.kind, .chatgpt)
        XCTAssertNil(account?.displayEmail)
    }

    func testAPIKeyAccountHasNoEmail() {
        let account = CodexAccountParser.parse(result: ["account": ["type": "apiKey"]])
        XCTAssertEqual(account?.kind, .apiKey)
        XCTAssertNil(account?.displayEmail)
        XCTAssertEqual(account?.displayPlanType, "API Key")
        XCTAssertEqual(account?.cacheAccountID, "api-key")
    }

    func testUnknownAccountTypeIsReportedAsUnknownNotGuessed() {
        let account = CodexAccountParser.parse(result: ["account": ["type": "somethingNew"]])
        XCTAssertEqual(account?.kind, .other)
        XCTAssertNil(account?.displayEmail)
    }

    func testMissingAccountYieldsNil() {
        XCTAssertNil(CodexAccountParser.parse(result: ["requiresOpenaiAuth": true]))
        XCTAssertNil(CodexAccountParser.parse(result: [:]))
    }

    func testCacheAccountIDPrefersTheEmailAndRejectsBlanks() {
        XCTAssertEqual(CodexAccount(kind: .chatgpt, email: "a@b.c", planType: nil).cacheAccountID, "a@b.c")
        XCTAssertNil(CodexAccount(kind: .chatgpt, email: "   ", planType: nil).cacheAccountID)
        XCTAssertNil(CodexAccount(kind: .other, email: nil, planType: nil).cacheAccountID)
    }

    // MARK: Request shape (real child process, same fixture style as the transport tests)

    /// Echoes the params it received for `account/read` into the account email, so the test
    /// can assert on the exact wire request the client sent.
    static let accountEchoServer = """
    import sys, json
    for raw in sys.stdin:
        try:
            msg = json.loads(raw)
        except Exception:
            continue
        method = msg.get("method")
        mid = msg.get("id")
        if method == "initialize":
            sys.stdout.write(json.dumps({"id": mid, "result": {"ok": True}}) + "\\n")
            sys.stdout.flush()
        elif method == "account/read":
            echo = json.dumps(msg.get("params", {}), sort_keys=True)
            sys.stdout.write(json.dumps({"id": mid, "result": {
                "requiresOpenaiAuth": False,
                "account": {"type": "chatgpt", "email": "echo:" + echo, "planType": "plus"}}}) + "\\n")
            sys.stdout.flush()
        else:
            sys.stdout.write(json.dumps({"id": mid, "result": {}}) + "\\n")
            sys.stdout.flush()
    """

    func makeClient(_ script: String) throws -> (CodexAppServerClient, JSONRPCClient) {
        let transport = JSONRPCClient(executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                                      arguments: ["-c", script])
        try transport.start()
        return (CodexAppServerClient(transport: transport), transport)
    }

    func testAccountReadIsSentWithRefreshTokenFalse() throws {
        let (client, _) = try makeClient(Self.accountEchoServer)
        defer { client.stop() }

        let account = try client.readAccount(timeout: 5)
        let echo = try XCTUnwrap(account?.displayEmail, "the fixture must echo the params back")
        XCTAssertTrue(echo.contains("refreshToken"), "the request must carry refreshToken")
        XCTAssertTrue(echo.contains("false"), "refreshToken must be false: the app never triggers a refresh")
        XCTAssertFalse(echo.contains("true"))
    }

    // MARK: Account-scoped cache

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageMonitorTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func snapshot(remaining: Double) -> UsageSnapshot {
        let window = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                     usedPercent: 100 - remaining, remainingPercent: remaining,
                                     resetsAt: nil)
        return UsageSnapshot(fiveHour: window, weekly: nil,
                             fetchedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .codexAppServer)
    }

    func testCacheIsIsolatedPerAccount() {
        let cache = UsageCache(userDefaults: makeDefaults())
        cache.save(snapshot(remaining: 80), accountID: "a@example.com")
        cache.save(snapshot(remaining: 20), accountID: "b@example.com")

        XCTAssertEqual(cache.load(accountID: "a@example.com")?.fiveHour?.remainingPercent, 80)
        XCTAssertEqual(cache.load(accountID: "b@example.com")?.fiveHour?.remainingPercent, 20)
    }

    func testLegacyUnattributedCacheIsNeverServedToAKnownAccount() {
        let cache = UsageCache(userDefaults: makeDefaults())
        cache.save(snapshot(remaining: 50))          // v1.0 store, no account attribution
        cache.save(snapshot(remaining: 70), accountID: "current@example.com")

        XCTAssertEqual(cache.load(accountID: "current@example.com")?.fiveHour?.remainingPercent, 70)
        XCTAssertNotNil(cache.load(), "the unattributed store still exists for the no-account case")
    }

    func testUnknownAccountNeverResolvesToAnything() {
        let cache = UsageCache(userDefaults: makeDefaults())
        cache.save(snapshot(remaining: 50), accountID: "a@example.com")
        XCTAssertNil(cache.load(accountID: nil))
        XCTAssertNil(cache.load(accountID: ""))
        XCTAssertNil(cache.load(accountID: "other@example.com"))
    }

    func testLastKnownAccountIsRememberedAcrossRuns() {
        let defaults = makeDefaults()
        let first = UsageCache(userDefaults: defaults)
        XCTAssertNil(first.loadLastKnownAccountID())
        first.saveLastKnownAccountID("a@example.com")
        first.saveLastKnownAccountID("")
        XCTAssertEqual(first.loadLastKnownAccountID(), "a@example.com", "an empty id must not overwrite it")

        let second = UsageCache(userDefaults: defaults)
        XCTAssertEqual(second.loadLastKnownAccountID(), "a@example.com")
    }

    func testAccountSwitchThroughTheServiceChangesTheServedCache() throws {
        let defaults = makeDefaults()
        let cache = UsageCache(userDefaults: defaults)

        let clientA = StubCodexClientForAccount(account: CodexAccount(kind: .chatgpt, email: "a@example.com", planType: nil),
                                                snapshot: snapshot(remaining: 80))
        let serviceA = UsageService(factory: { clientA }, cache: cache, restartDelay: 0)
        let resultA = try serviceA.fetch()
        XCTAssertEqual(resultA.account?.displayEmail, "a@example.com")
        XCTAssertEqual(serviceA.cachedSnapshotForCurrentAccount()?.fiveHour?.remainingPercent, 80)

        let clientB = StubCodexClientForAccount(account: CodexAccount(kind: .chatgpt, email: "b@example.com", planType: nil),
                                                snapshot: snapshot(remaining: 30))
        let serviceB = UsageService(factory: { clientB }, cache: cache, restartDelay: 0)
        let resultB = try serviceB.fetch()
        XCTAssertEqual(resultB.account?.displayEmail, "b@example.com")
        XCTAssertEqual(serviceB.cachedSnapshotForCurrentAccount()?.fiveHour?.remainingPercent, 30)
        XCTAssertNotEqual(serviceB.cachedSnapshotForCurrentAccount()?.fiveHour?.remainingPercent, 80,
                          "account A's numbers must not be served to account B")
    }

    func testFailureServesTheCurrentAccountCacheAndNotAnotherAccounts() throws {
        let defaults = makeDefaults()
        let cache = UsageCache(userDefaults: defaults)
        cache.saveLastKnownAccountID("a@example.com")

        // Warm the store for A.
        let good = StubCodexClientForAccount(account: CodexAccount(kind: .chatgpt, email: "a@example.com", planType: nil),
                                             snapshot: snapshot(remaining: 80))
        _ = try UsageService(factory: { good }, cache: cache, restartDelay: 0).fetch()

        // A later run whose identity read fails still serves A's own numbers, and reports
        // the identity as unavailable rather than guessing.
        let failing = StubCodexClientForAccount(account: nil,
                                                snapshot: nil,
                                                persistentError: .rpcFailed(.timedOut(method: "account/rateLimits/read")))
        let service = UsageService(factory: { failing }, cache: cache, restartDelay: 0)
        let result = try service.fetch()

        XCTAssertFalse(result.isLive)
        XCTAssertEqual(result.snapshot.fiveHour?.remainingPercent, 80, "the account's own cache is served")
        XCTAssertNil(result.account, "a failed identity read is reported as unavailable")
    }

    func testSuccessfulReadWritesOnlyTheAccountScopedStore() throws {
        let defaults = makeDefaults()
        let cache = UsageCache(userDefaults: defaults)

        let client = StubCodexClientForAccount(account: CodexAccount(kind: .chatgpt, email: "a@example.com", planType: nil),
                                               snapshot: snapshot(remaining: 80))
        let service = UsageService(factory: { client }, cache: cache, restartDelay: 0)
        _ = try service.fetch()

        XCTAssertEqual(cache.load(accountID: "a@example.com")?.fiveHour?.remainingPercent, 80)
        XCTAssertEqual(cache.loadLastKnownAccountID(), "a@example.com")
    }
}

/// Client stub that reports an identity alongside its usage snapshot.
final class StubCodexClientForAccount: CodexAppServerProviding {
    let account: CodexAccount?
    let snapshot: UsageSnapshot?
    let persistentError: UsageError?
    var isTransportRunning = true
    var startCalls = 0
    var stopCalls = 0

    init(account: CodexAccount?, snapshot: UsageSnapshot?, persistentError: UsageError? = nil) {
        self.account = account
        self.snapshot = snapshot
        self.persistentError = persistentError
    }

    func start() throws { startCalls += 1 }
    func handshake(timeout: TimeInterval) throws {}

    func readAccount(timeout: TimeInterval) throws -> CodexAccount? {
        if let persistentError { throw persistentError }
        return account
    }

    func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
        if let persistentError { throw persistentError }
        guard let snapshot else { throw UsageError.rpcFailed(.other) }
        return snapshot
    }

    func stop() { stopCalls += 1 }
}

import XCTest
@testable import UsageMonitorCore

/// 1.4.2 §3.4: the identity state machine per profile.
///
/// `confirmed` is an identity this connection resolved; `previous` is the last identity
/// confirmed on the *same* connection, shown with the explicit 上次身份 label across a
/// transient failure; `unavailable` claims nothing. Stored identity is invalidated by an
/// account replacement, a sign-out, or a replaced connection (new epoch).
final class CodexProfileIdentityTests: XCTestCase {

    func makeUserDefaults() -> UserDefaults {
        let suite = "UsageMonitorIdentityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func snapshot(fiveHourRemaining: Double = 75) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 25,
                                      remainingPercent: fiveHourRemaining,
                                      resetsAt: Date(timeIntervalSince1970: 1_788_935_373)),
            weekly: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_788_935_000),
            source: .codexAppServer
        )
    }

    private func account(_ email: String) -> CodexAccount {
        CodexAccount(kind: .chatgpt, email: email, planType: "plus")
    }

    /// One stub shared by every attempt of the service under test.
    private typealias SharedStub = StubClient

    private func makeCoordinator(stub: SharedStub) -> CodexProfilesCoordinator {
        CodexProfilesCoordinator(profiles: [.chatGPTA]) { _ in
            UsageService(factory: { stub }, cache: UsageCache(userDefaults: self.makeUserDefaults()),
                         restartDelay: 0)
        }
    }

    func testSuccessfulFetchConfirmsTheIdentity() throws {
        let stub = SharedStub()
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        let coordinator = makeCoordinator(stub: stub)

        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        let state = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")).state()
        XCTAssertEqual(state.identity, .confirmed(account("a@example.com")))
        XCTAssertEqual(state.account?.displayEmail, "a@example.com")
        XCTAssertNil(state.identity.label, "a confirmed identity needs no label")
    }

    func testLiveReadWithoutIdentityDowngradesToPreviousOnTheSameConnection() throws {
        let stub = SharedStub()
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        let coordinator = makeCoordinator(stub: stub)

        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        // A later cycle resolves the quota but not the identity (identity read failed).
        // The connection is unchanged — an authenticated child just answered a quota
        // read — so the confirmed identity downgrades to 上次身份, it is not wiped.
        stub.account = nil
        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        let state = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")).state()
        XCTAssertEqual(state.identity, .previous(account("a@example.com")),
                       "a same-connection identity hiccup keeps the last confirmed identity, labelled")
        XCTAssertEqual(state.identity.label, "上次身份")
        XCTAssertEqual(state.account?.displayEmail, "a@example.com")

        // And the next resolved identity re-confirms it.
        stub.account = account("a@example.com")
        _ = try coordinator.fetch(profileID: "chatgpt-a", resetFailureBudget: true).get()
        XCTAssertEqual(coordinator.runtime(for: "chatgpt-a")?.state().identity,
                       .confirmed(account("a@example.com")))
    }

    func testReplacementConnectionInvalidatesIdentityWhenIdentityReadFails() throws {
        let stub = SharedStub()
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        let coordinator = makeCoordinator(stub: stub)

        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        let firstEpoch = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")?.service.currentConnectionEpoch)

        // Force the service to publish a new child, then make only identity lookup
        // unavailable. The live quota result must not keep the old email on the card.
        stub.isTransportRunning = false
        stub.account = nil
        _ = try coordinator.fetch(profileID: "chatgpt-a").get()

        let state = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")).state()
        XCTAssertGreaterThan(coordinator.runtime(for: "chatgpt-a")?.service.currentConnectionEpoch ?? 0,
                             firstEpoch, "the service has published a replacement child")
        XCTAssertEqual(state.identity, .unavailable)
        XCTAssertNil(state.account, "identity from the old connection must be cleared")
    }

    func testSignOutInvalidatesTheStoredIdentity() throws {
        let stub = SharedStub()
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        let coordinator = makeCoordinator(stub: stub)

        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        // The read now reports a signed-out account: nothing a retry could ride out.
        stub.readErrors = [.codexNotSignedIn]
        stub.readResults = []
        _ = try? coordinator.fetch(profileID: "chatgpt-a").get()

        let state = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")).state()
        XCTAssertEqual(state.identity, .unavailable, "a sign-out invalidates the stored identity")
        XCTAssertNil(state.identity.label)

        // And a later transient failure has nothing to fall back to any more.
        stub.readErrors = []
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        _ = try? coordinator.fetch(profileID: "chatgpt-a").get()
        XCTAssertEqual(coordinator.runtime(for: "chatgpt-a")?.state().identity, .unavailable,
                       "the invalidated identity never comes back as 上次身份")
    }

    func testRetryLadderChildRelaunchInvalidatesPreviousIdentity() throws {
        let stub = SharedStub()
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        let coordinator = makeCoordinator(stub: stub)

        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        stub.persistentError = .rpcFailed(.timedOut(method: "account/rateLimits/read"))
        stub.readResults = []
        _ = try? coordinator.fetch(profileID: "chatgpt-a").get()
        XCTAssertEqual(coordinator.runtime(for: "chatgpt-a")?.state().identity,
                       .unavailable,
                       "the failed episode replaces the app-server child")

        // The automatic retry publishes a replacement app-server child. Its epoch differs,
        // so the previous connection's identity cannot be shown as belonging to it.
        _ = try? coordinator.fetch(profileID: "chatgpt-a").get()
        let state = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")).state()
        XCTAssertEqual(state.identity, .unavailable,
                       "identity must not survive a replacement app-server child")
        XCTAssertNil(state.account)

        stub.persistentError = nil
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        // Manual: the failed episode above opened the backoff gate, and this step is about
        // identity confidence, not the ladder.
        _ = try coordinator.fetch(profileID: "chatgpt-a", resetFailureBudget: true).get()
        XCTAssertEqual(coordinator.runtime(for: "chatgpt-a")?.state().identity,
                       .confirmed(account("a@example.com")), "the next confirmed read restores confidence")
    }

    func testAccountReplacementReplacesTheConfirmedIdentity() throws {
        let stub = SharedStub()
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        let coordinator = makeCoordinator(stub: stub)

        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        stub.account = account("b@example.com")
        _ = try coordinator.fetch(profileID: "chatgpt-a").get()

        let state = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")).state()
        XCTAssertEqual(state.identity, .confirmed(account("b@example.com")),
                       "a confirmed read replaces whoever was confirmed before")
    }

    func testConfirmationReadLeavesTheIdentityStateUntouched() throws {
        let stub = SharedStub()
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        let coordinator = makeCoordinator(stub: stub)

        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        stub.account = nil
        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        XCTAssertEqual(coordinator.runtime(for: "chatgpt-a")?.state().identity,
                       .previous(account("a@example.com")))

        // A confirmation read observes a fresh window: quota display moves, identity stays.
        stub.readResults = [snapshot(fiveHourRemaining: 60)]
        _ = try coordinator.fetchRateLimitsOnly(profileID: "chatgpt-a", resetFailureBudget: true).get()

        let state = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")).state()
        XCTAssertEqual(state.identity, .previous(account("a@example.com")),
                       "the confirmation path never re-attributes identity")
        XCTAssertNotNil(state.snapshot)
    }

    func testConfirmationOnReplacementConnectionInvalidatesOldIdentity() throws {
        let stub = SharedStub()
        stub.readResults = [snapshot()]
        stub.account = account("a@example.com")
        let coordinator = makeCoordinator(stub: stub)

        _ = try coordinator.fetch(profileID: "chatgpt-a").get()
        let firstEpoch = coordinator.runtime(for: "chatgpt-a")?.service.currentConnectionEpoch
        stub.isTransportRunning = false
        _ = try coordinator.fetchRateLimitsOnly(profileID: "chatgpt-a", resetFailureBudget: true).get()

        let runtime = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a"))
        XCTAssertGreaterThan(runtime.service.currentConnectionEpoch, firstEpoch ?? 0)
        XCTAssertEqual(runtime.state().identity, .unavailable,
                       "a confirmation-only read cannot re-attribute the prior connection's identity")
        XCTAssertNil(runtime.state().account)
    }

    func testIdentityStartsUnavailableBeforeAnyFetch() throws {
        let stub = SharedStub()
        let coordinator = makeCoordinator(stub: stub)
        let state = try XCTUnwrap(coordinator.runtime(for: "chatgpt-a")).state()
        XCTAssertEqual(state.identity, .unavailable)
        XCTAssertNil(state.account)
    }
}

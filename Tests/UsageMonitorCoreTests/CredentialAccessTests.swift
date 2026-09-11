import XCTest
@testable import UsageMonitorCore

/// Credential access rework (KEYCHAIN_REVISION_PLAN.md P1).
///
/// Everything here runs against an in-memory store that can be driven to produce any outcome
/// the real keychain could return, so no test needs a real keychain, a real dialog, or a real
/// credential.
@MainActor
final class CredentialAccessTests: XCTestCase {

    // MARK: - Outcome classification

    /// P1.1: only `errSecItemNotFound` means "not saved". Everything else keeps its status
    /// instead of being folded into a category that would mislead.
    func testKeychainStatusClassification() {
        let data = Data("sk-value".utf8)
        XCTAssertEqual(KeychainCredentialStore.classify(errSecSuccess, result: data as AnyObject),
                       .available("sk-value"))
        XCTAssertEqual(KeychainCredentialStore.classify(errSecItemNotFound, result: nil),
                       .missing)
        XCTAssertEqual(KeychainCredentialStore.classify(errSecInteractionNotAllowed, result: nil),
                       .interactionRequired(errSecInteractionNotAllowed))
        XCTAssertEqual(KeychainCredentialStore.classify(errSecUserCanceled, result: nil),
                       .deniedOrCancelled(errSecUserCanceled))
        XCTAssertEqual(KeychainCredentialStore.classify(errSecAuthFailed, result: nil),
                       .deniedOrCancelled(errSecAuthFailed))
        XCTAssertEqual(KeychainCredentialStore.classify(errSecNotAvailable, result: nil),
                       .unavailable(errSecNotAvailable))
    }

    /// A malformed or empty payload is never reported as an available credential.
    func testAMalformedPayloadIsNotReportedAsAvailable() {
        XCTAssertEqual(KeychainCredentialStore.classify(errSecSuccess, result: Data() as AnyObject),
                       .unavailable(errSecDecode))
        XCTAssertEqual(KeychainCredentialStore.classify(errSecSuccess, result: "not data" as AnyObject),
                       .unavailable(errSecDecode))
    }

    // MARK: - Coordinator memory state

    private func makeCoordinator(_ store: InMemoryCredentialStore) -> CredentialAccessCoordinator {
        return CredentialAccessCoordinator(store: store,
                                           queue: DispatchQueue(label: "test.credential." + UUID().uuidString))
    }

    /// P1.3: a background read is remembered, so later status queries never touch the
    /// keychain again.
    func testABlockedReadIsRememberedAndNotRetried() async {
        let store = InMemoryCredentialStore()
        store.simulate(.interactionRequired(errSecInteractionNotAllowed), for: .deepseekAPIKey)
        let coordinator = makeCoordinator(store)

        let first = await coordinator.value(for: .deepseekAPIKey, purpose: .startupPrime,
                                            interaction: .disallowed)
        XCTAssertEqual(first, .interactionRequired(errSecInteractionNotAllowed))
        XCTAssertEqual(coordinator.phase(for: .deepseekAPIKey), .needsAuthorization)

        // The next status query is answered from memory: no second access, no new dialog.
        let second = await coordinator.value(for: .deepseekAPIKey, purpose: .providerRead,
                                             interaction: .disallowed)
        XCTAssertEqual(second, .interactionRequired(errSecInteractionNotAllowed))
        XCTAssertEqual(store.loads(of: .deepseekAPIKey), 1)
    }

    /// P1.4: a read the user asked for always gets its own attempt, even right after a
    /// background read was refused, and a success clears the blocked state.
    func testAUserRequestedReadRetriesAfterABlock() async {
        let store = InMemoryCredentialStore()
        store.simulate(.interactionRequired(errSecInteractionNotAllowed), for: .deepseekAPIKey)
        let coordinator = makeCoordinator(store)

        _ = await coordinator.value(for: .deepseekAPIKey, purpose: .startupPrime,
                                    interaction: .disallowed)
        XCTAssertEqual(store.loads(of: .deepseekAPIKey), 1)

        store.seed("sk-live", for: .deepseekAPIKey)
        let outcome = await coordinator.value(for: .deepseekAPIKey, purpose: .userRequestedRead,
                                              interaction: .allowed)
        XCTAssertEqual(outcome, .available("sk-live"))
        XCTAssertEqual(coordinator.phase(for: .deepseekAPIKey), .available)
        XCTAssertEqual(store.loads(of: .deepseekAPIKey), 2)
    }

    /// P1.2: concurrent requests for the same credential coalesce onto one keychain access.
    func testConcurrentReadsOfOneCredentialCoalesce() async {
        let store = InMemoryCredentialStore()
        store.seed("sk-value", for: .deepseekAPIKey)
        store.loadDelay = 0.15
        let coordinator = makeCoordinator(store)

        async let first = coordinator.value(for: .deepseekAPIKey, purpose: .startupPrime,
                                            interaction: .disallowed)
        async let second = coordinator.value(for: .deepseekAPIKey, purpose: .providerRead,
                                             interaction: .disallowed)
        let (a, b) = await (first, second)
        XCTAssertEqual(a, .available("sk-value"))
        XCTAssertEqual(b, .available("sk-value"))
        XCTAssertEqual(store.loads(of: .deepseekAPIKey), 1,
                       "both callers must share one keychain read")
    }

    /// P1.6: the stored value lives in memory for the process lifetime and is served without
    /// another keychain access.
    func testAnAvailableValueIsServedFromMemory() async {
        let store = InMemoryCredentialStore()
        store.seed("sk-value", for: .deepseekAPIKey)
        let coordinator = makeCoordinator(store)

        _ = await coordinator.value(for: .deepseekAPIKey, purpose: .startupPrime,
                                    interaction: .disallowed)
        _ = await coordinator.value(for: .deepseekAPIKey, purpose: .providerRead,
                                    interaction: .disallowed)
        XCTAssertEqual(store.loads(of: .deepseekAPIKey), 1)
        XCTAssertEqual(coordinator.cachedSecret(for: .deepseekAPIKey), "sk-value")
    }

    /// P1.8: a removal that the keychain refused is propagated, and the memory state is not
    /// silently rewritten into "gone".
    func testARemovedCredentialThatFailsIsPropagated() async {
        let store = InMemoryCredentialStore()
        store.seed("sk-value", for: .deepseekAPIKey)
        store.deleteError = ProviderFailure.other
        let coordinator = makeCoordinator(store)

        _ = await coordinator.value(for: .deepseekAPIKey, purpose: .startupPrime,
                                    interaction: .disallowed)
        do {
            try coordinator.remove(.deepseekAPIKey)
            XCTFail("the failure must reach the caller")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .other)
        }
        XCTAssertEqual(coordinator.phase(for: .deepseekAPIKey), .available,
                       "the credential is still there, so it is not reported as gone")
        XCTAssertEqual(coordinator.cachedSecret(for: .deepseekAPIKey), "sk-value")
    }

    /// P1.8: removing an absent credential is a success, because absent is the goal.
    func testRemovingAnAbsentCredentialSucceeds() async {
        let coordinator = makeCoordinator(InMemoryCredentialStore())
        do {
            try coordinator.remove(.glmAPIKey)
        } catch {
            XCTFail("removing an absent credential must not throw: \(error)")
        }
        XCTAssertEqual(coordinator.phase(for: .glmAPIKey), .missing)
    }

    /// A credential written through the coordinator is immediately available in memory, so
    /// the following read never touches the keychain.
    func testAStoredCredentialIsKnownImmediately() async throws {
        let store = InMemoryCredentialStore()
        let coordinator = makeCoordinator(store)

        try coordinator.store("sk-new", for: .deepseekAPIKey)
        XCTAssertEqual(coordinator.phase(for: .deepseekAPIKey), .available)

        let outcome = await coordinator.value(for: .deepseekAPIKey, purpose: .providerRead,
                                              interaction: .disallowed)
        XCTAssertEqual(outcome, .available("sk-new"))
        XCTAssertEqual(store.loads(of: .deepseekAPIKey), 0,
                       "a value written moments ago needs no keychain read")
    }

    // MARK: - DeepSeek single read

    /// P1.7: one read serves the request and the account fingerprint.
    func testADeepSeekReadFetchesTheCredentialExactlyOnce() async throws {
        let store = InMemoryCredentialStore()
        store.seed("sk-single", for: .deepseekAPIKey)
        let transport = FakeTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data("""
            {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"1.00"}]}
            """.utf8))
        }
        let reading = DeepSeekReading(provider: DeepSeekProvider(transport: transport),
                                      credentials: store)
        await reading.primeCredentialState()

        let result = try await reading.read()
        XCTAssertEqual(result.accountID, DeepSeekProvider.accountFingerprint(forAPIKey: "sk-single"))
        XCTAssertEqual(store.loads(of: .deepseekAPIKey), 1,
                       "the read and the fingerprint share one credential access")
    }

    /// P1.4: a credential that needs a decision is reported as such, not as "nothing stored".
    func testABlockedDeepSeekCredentialIsNotReportedAsMissing() async throws {
        let store = InMemoryCredentialStore()
        store.simulate(.interactionRequired(errSecInteractionNotAllowed), for: .deepseekAPIKey)
        let reading = DeepSeekReading(provider: DeepSeekProvider(transport: FakeTransport()),
                                      credentials: store)
        await reading.primeCredentialState()

        XCTAssertEqual(reading.credentialState, .needsAuthorization)
        XCTAssertFalse(reading.credentialState.isConfigured)

        do {
            _ = try await reading.read()
            XCTFail("a blocked credential cannot be read")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .credentialAccessBlocked)
        }
        XCTAssertEqual(store.loads(of: .deepseekAPIKey), 1,
                       "the blocked state stops further background attempts")
    }

    // MARK: - GLM mode selection

    /// P1.7: the persisted connection mode decides which credential is loaded, and the unused
    /// one is not probed.
    func testConsoleModeDoesNotProbeAStoredAPIKey() async throws {
        let suite = "CredentialAccessTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("consoleSession", forKey: GLMReading.connectionModeKey)

        let store = InMemoryCredentialStore()
        store.seed("glm-old", for: .glmAPIKey)
        let session = GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: "c", value: "v",
                                                           domain: "bigmodel.cn", expiresAt: nil)],
            capturedAt: Date())
        try store.save(String(decoding: GLMConsoleSessionPolicy.encode(session), as: UTF8.self),
                       for: .glmConsoleSession)

        let reading = GLMReading(provider: GLMProvider(transport: FakeTransport()),
                                 credentials: store, preferences: defaults)
        await reading.primeCredentialState()

        XCTAssertEqual(reading.credentialState, .configured)
        XCTAssertEqual(reading.selectedCredential(), .consoleSession)
        XCTAssertEqual(store.loads(of: .glmAPIKey), 0,
                       "the stored API key is not read while a console session is selected")
    }

    /// A persisted mode whose credential is absent falls back to the one that exists: the app
    /// must not report "not configured" just because the selected kind was removed.
    func testAMissingPreferredCredentialFallsBackToTheAvailableOne() async throws {
        let suite = "CredentialAccessTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("consoleSession", forKey: GLMReading.connectionModeKey)

        let store = InMemoryCredentialStore()
        store.seed("glm-live", for: .glmAPIKey)

        let reading = GLMReading(provider: GLMProvider(transport: FakeTransport()),
                                 credentials: store, preferences: defaults)
        await reading.primeCredentialState()

        XCTAssertEqual(reading.credentialState, .configured)
        XCTAssertEqual(reading.selectedCredential(), .apiKey)
    }

    /// P1.8: a refusal is never reported as "nothing stored yet".
    func testARefusedGLMCredentialKeepsItsOwnState() async throws {
        let suite = "CredentialAccessTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = InMemoryCredentialStore()
        store.simulate(.deniedOrCancelled(errSecAuthFailed), for: .glmAPIKey)
        store.simulate(.deniedOrCancelled(errSecAuthFailed), for: .glmConsoleSession)
        let reading = GLMReading(provider: GLMProvider(transport: FakeTransport()),
                                 credentials: store, preferences: defaults)
        await reading.primeCredentialState()

        XCTAssertEqual(reading.credentialState, .needsAuthorization)
    }
}

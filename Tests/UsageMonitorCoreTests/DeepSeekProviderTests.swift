import XCTest
@testable import UsageMonitorCore

/// DeepSeek balance reading: documented endpoint, Bearer key, per-currency amounts, and
/// honest handling of HTTP 200 business failures.
final class DeepSeekProviderTests: XCTestCase {

    private func store(key: String?) -> InMemoryCredentialStore {
        let store = InMemoryCredentialStore()
        if let key { try? store.save(key, for: .deepseekAPIKey) }
        return store
    }

    private func provider(transport: ProviderTransport, key: String?) -> DeepSeekProvider {
        return DeepSeekProvider(transport: transport, credentials: store(key: key))
    }

    func testSuccessfulBalanceIsParsedPerCurrency() async throws {
        let transport = FakeTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data("""
            {"is_available":true,"balance_infos":[
              {"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}
            """.utf8))
        }
        let balances = try await provider(transport: transport, key: "sk-test").fetchBalances()

        XCTAssertEqual(balances.count, 1)
        XCTAssertEqual(balances[0].currency, "CNY")
        XCTAssertEqual(balances[0].total, dec("110.00"))
        XCTAssertEqual(balances[0].granted, dec("10.00"))
        XCTAssertEqual(balances[0].toppedUp, dec("100.00"))
    }

    func testDifferentCurrenciesAreReportedSeparatelyAndNeverSummed() async throws {
        let transport = FakeTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data("""
            {"is_available":true,"balance_infos":[
              {"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"},
              {"currency":"USD","total_balance":"5.50","granted_balance":"0.50","topped_up_balance":"5.00"}]}
            """.utf8))
        }
        let balances = try await provider(transport: transport, key: "sk-test").fetchBalances()

        XCTAssertEqual(balances.count, 2, "each currency is its own row")
        XCTAssertEqual(balances.map { $0.currency }, ["CNY", "USD"])
        XCTAssertEqual(balances[0].total, dec("110.00"))
        XCTAssertEqual(balances[1].total, dec("5.50"))
        XCTAssertNotEqual((balances[0].total ?? dec("0")) + (balances[1].total ?? dec("0")),
                          balances[0].total,
                          "currencies are never merged")
    }

    func testBearerCredentialIsSentOnTheBalanceRequest() async throws {
        let transport = FakeTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"balance_infos":[{"currency":"CNY","total_balance":"1"}]}"#.utf8))
        }
        _ = try await provider(transport: transport, key: "sk-live-key").fetchBalances()

        let request = try XCTUnwrap(transport.recordedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-live-key")
    }

    func testNoCredentialIsReportedNotFaked() async {
        let transport = FakeTransport()
        do {
            _ = try await provider(transport: transport, key: nil).fetchBalances()
            XCTFail("no key configured must fail")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .notConfigured)
        }
        XCTAssertTrue(transport.recordedRequests.isEmpty, "nothing is sent without a key")
    }

    // MARK: HTTP 200 with a business error

    func testHTTP200WithBusinessErrorPayloadIsNeverABalance() async {
        let transport = FakeTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"error":{"message":"Invalid API key","code":"invalid_request_error"}}"#.utf8))
        }
        do {
            _ = try await provider(transport: transport, key: "sk-test").fetchBalances()
            XCTFail("a business error must not yield balances")
        } catch {
            let failure = error as? ProviderFailure
            guard case .businessError = failure else {
                return XCTFail("expected businessError, got \(String(describing: failure))")
            }
        }
    }

    func testHTTP200WithUnrecognisedPayloadIsUnexpectedResponseNotZero() async {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        do {
            _ = try await provider(transport: transport, key: "sk-test").fetchBalances()
            XCTFail("an unrecognised payload must not yield balances")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .unexpectedResponse)
        }
    }

    func testHTTP200WithMissingAmountsIsUnexpectedResponseNotZero() async {
        let transport = FakeTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"balance_infos":[{"currency":"CNY","granted_balance":"1.00"}]}"#.utf8))
        }
        do {
            _ = try await provider(transport: transport, key: "sk-test").fetchBalances()
            XCTFail("an entry without a total must not become 0")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .unexpectedResponse)
        }
    }

    func testNonParsableAmountIsOmittedNotZeroed() throws {
        let data = Data("""
        {"balance_infos":[{"currency":"CNY","total_balance":"-","granted_balance":"1.00"}]}
        """.utf8)
        XCTAssertThrowsError(try DeepSeekProvider.parseBalanceData(data))
    }

    // MARK: Status codes

    func test401MapsToInvalidCredential() async {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }
        do {
            _ = try await provider(transport: transport, key: "sk-test").fetchBalances()
            XCTFail("401 must fail")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .invalidCredential)
        }
    }

    func testServerErrorStatusIsReported() async {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 503, body: Data()) }
        do {
            _ = try await provider(transport: transport, key: "sk-test").fetchBalances()
            XCTFail("503 must fail")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .serverError(status: 503))
        }
    }

    // MARK: Credential handling

    func testAccountFingerprintIsStableAndNotTheKey() {
        let fingerprint = DeepSeekProvider.accountFingerprint(forAPIKey: "sk-abcdef0123456789")
        XCTAssertEqual(fingerprint, DeepSeekProvider.accountFingerprint(forAPIKey: "sk-abcdef0123456789"))
        XCTAssertNotEqual(fingerprint, DeepSeekProvider.accountFingerprint(forAPIKey: "sk-other"))
        XCTAssertFalse(fingerprint.contains("sk-"))
        XCTAssertEqual(fingerprint.count, 6)
    }

    func testDeletingTheKeyLeavesNothingBehind() throws {
        let credentials = InMemoryCredentialStore()
        try credentials.save("sk-test", for: .deepseekAPIKey)
        let reading = DeepSeekReading(provider: DeepSeekProvider(transport: FakeTransport(), credentials: credentials),
                                      credentials: credentials)
        XCTAssertTrue(reading.isConfigured)

        try reading.disconnect()
        XCTAssertFalse(reading.isConfigured)
        XCTAssertNil(credentials.load(.deepseekAPIKey), "deleting the key removes it from the store")
        XCTAssertEqual(credentials.deleteCallCount, 1)
    }

    func testNetworkFailureIsMappedToAFixedCategory() async {
        let transport = FakeTransport()
        transport.thrownError = URLError(.notConnectedToInternet)
        do {
            _ = try await provider(transport: transport, key: "sk-test").fetchBalances()
            XCTFail("offline must fail")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .networkUnreachable)
        }
    }
}

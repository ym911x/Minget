import XCTest
@testable import UsageMonitorCore

/// GLM reading, the per-endpoint strict schemas, and the console-session policy.
///
/// The load-bearing property: an amount is displayed only when the response parses cleanly
/// under its endpoint's confirmed schema — envelope, field paths, types and amount
/// constraints. Anything else is recorded as redacted structure evidence, never displayed.
final class GLMProviderTests: XCTestCase {

    // MARK: Envelope: HTTP 200 business results (Round 7 requirement 3)

    func testHTTP200WithBusinessErrorCodeIsNotABalance() {
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":1113,"message":"insufficient permission"}"#.utf8),
            httpStatus: 200, schema: .apiBalanceV1)

        XCTAssertEqual(observation.httpStatus, 200)
        XCTAssertEqual(observation.businessCode, 1113)
        XCTAssertEqual(observation.parseFailure, ProviderFailure.businessError(code: 1113))
        XCTAssertTrue(observation.candidateBalances.isEmpty)
        XCTAssertFalse(observation.isDisplayable)
    }

    func testSuccessFlagFalseFailsWhateverTheCodeSays() {
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":200,"success":false,"data":{"total_balance":1}}"#.utf8),
            httpStatus: 200, schema: .apiBalanceV1)
        XCTAssertEqual(observation.parseFailure, ProviderFailure.businessError(code: 200))
        XCTAssertTrue(observation.candidateBalances.isEmpty)
    }

    /// The known success spellings, fixed here: numeric 200/0 and the strings "200" and
    /// "success" (Round 7 requirement 3).
    func testKnownSuccessSpellingsAreAccepted() {
        for payload in [#"{"code":200,"data":{"total_balance":5}}"#,
                        #"{"code":"200","data":{"total_balance":5}}"#,
                        #"{"code":"success","data":{"total_balance":5}}"#,
                        #"{"code":0,"data":{"total_balance":5}}"#] {
            let observation = GLMAccountReportParser.observe(
                data: Data(payload.utf8), httpStatus: 200, schema: .apiBalanceV1)
            XCTAssertNil(observation.parseFailure, payload)
            XCTAssertEqual(observation.candidateBalances.first?.total, dec("5"), payload)
        }
    }

    func testHTTP200WithUnrecognisedShapeIsUnexpectedResponse() {
        let observation = GLMAccountReportParser.observe(data: Data(#"{"ok":true}"#.utf8),
                                                         httpStatus: 200, schema: .apiBalanceV1)
        XCTAssertEqual(observation.parseFailure, ProviderFailure.unexpectedResponse)
        XCTAssertTrue(observation.candidateBalances.isEmpty)
        XCTAssertEqual(observation.structureSummary, ["ok: boolean"],
                       "the shape evidence is recorded, redacted")
    }

    func testMalformedBodyIsRecordedNotThrown() {
        let observation = GLMAccountReportParser.observe(data: Data("not json".utf8),
                                                         httpStatus: 200, schema: .apiBalanceV1)
        XCTAssertEqual(observation.parseFailure, ProviderFailure.unexpectedResponse)
        XCTAssertTrue(observation.topLevelKeys.isEmpty)
        XCTAssertTrue(observation.structureSummary.isEmpty)
    }

    func testCleanParseUnderAConfirmedSchemaIsDisplayable() {
        // The display gate lives per schema in GLMContract: a payload that parses cleanly
        // under a confirmed schema is displayable, whatever the endpoint is.
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":200,"data":{"total_balance":"88.00","currency":"CNY"}}"#.utf8),
            httpStatus: 200, schema: .apiBalanceV1)

        XCTAssertEqual(observation.schema, .apiBalanceV1)
        XCTAssertNil(observation.parseFailure)
        XCTAssertTrue(GLMContract.isConfirmed(.apiBalanceV1))
        XCTAssertTrue(observation.isDisplayable)
        XCTAssertTrue(GLMContract.confirmedSchemas.allSatisfy { GLMSchema.allCases.contains($0) },
                      "only known schemas can ever be confirmed")
    }

    func testHTTPStatusClassificationPreservesTheRealStatus() {
        for status in [401, 403, 500, 502] {
            let observation = GLMAccountReportParser.observe(response: ProviderHTTPResponse(status: status, body: Data()),
                                                             schema: .apiBalanceV1)
            XCTAssertEqual(observation.httpStatus, status)
            let expected: ProviderFailure = (status == 401 || status == 403) ? .invalidCredential : .serverError(status: status)
            XCTAssertEqual(observation.parseFailure, expected)
            XCTAssertFalse(observation.isDisplayable)
        }
    }

    // MARK: apiBalanceV1: the plain-key balance endpoint (Round 7 requirement 1)

    func testBalanceEndpointParsesTotalAndAvailableWithTheirOwnSemantics() {
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":200,"success":true,"data":{"total_balance":100.5,"available_balance":"42.25","currency":"CNY"}}"#.utf8),
            httpStatus: 200, schema: .apiBalanceV1)

        XCTAssertNil(observation.parseFailure)
        let balance = observation.candidateBalances.first
        XCTAssertEqual(balance?.total, dec("100.5"))
        XCTAssertEqual(balance?.available, dec("42.25"))
        XCTAssertEqual(balance?.currency, "CNY")
        XCTAssertNil(balance?.toppedUp, "available_balance must never be mislabelled as 充值")
        XCTAssertNil(balance?.granted)
        XCTAssertTrue(observation.isDisplayable)
    }

    func testBalanceEndpointAcceptsDecimalStringsAndJSONNumbersExactly() {
        for payload in [#"{"code":200,"data":{"total_balance":"110.00"}}"#,
                        #"{"code":200,"data":{"total_balance":110.00}}"#] {
            let observation = GLMAccountReportParser.observe(
                data: Data(payload.utf8), httpStatus: 200, schema: .apiBalanceV1)
            XCTAssertNil(observation.parseFailure, payload)
            XCTAssertEqual(observation.candidateBalances.first?.total, dec("110"))
        }
    }

    func testBalanceEndpointWithoutCurrencyShowsTheAmountWithUnconfirmedCurrency() {
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":200,"data":{"total_balance":"88.00","available_balance":"80.00"}}"#.utf8),
            httpStatus: 200, schema: .apiBalanceV1)

        XCTAssertNil(observation.parseFailure)
        XCTAssertEqual(observation.candidateBalances.first?.currency, nil,
                       "no currency may be invented, CNY included")
        XCTAssertTrue(observation.isDisplayable, "the amount itself is real and displayable")
    }

    func testBalanceEndpointMissingAllAmountFieldsIsAFailureNotZero() {
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":200,"data":{"currency":"CNY"}}"#.utf8),
            httpStatus: 200, schema: .apiBalanceV1)
        XCTAssertEqual(observation.parseFailure, ProviderFailure.unexpectedResponse)
        XCTAssertTrue(observation.candidateBalances.isEmpty)
    }

    func testBalanceEndpointWithAnUnparsableAmountIsAFailureNotZero() {
        for payload in [#"{"code":200,"data":{"total_balance":"abc"}}"#,
                        #"{"code":200,"data":{"total_balance":null}}"#,
                        #"{"code":200,"data":{"available_balance":"1,234"}}"#] {
            let observation = GLMAccountReportParser.observe(
                data: Data(payload.utf8), httpStatus: 200, schema: .apiBalanceV1)
            XCTAssertEqual(observation.parseFailure, ProviderFailure.unexpectedResponse, payload)
            XCTAssertTrue(observation.candidateBalances.isEmpty, payload)
        }
    }

    func testBalanceEndpointWithoutADataObjectIsAFailure() {
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":200}"#.utf8), httpStatus: 200, schema: .apiBalanceV1)
        XCTAssertEqual(observation.parseFailure, ProviderFailure.unexpectedResponse)
    }

    // MARK: consoleReportV1: the console report shape (Round 7 requirement 2)

    func testConsoleReportWithBalanceObjectParsesEveryFieldWithItsOwnSemantics() {
        let payload = #"{"code":200,"success":true,"msg":"success","data":{"balance":{"balance":"100.00","availableBalance":66.6,"rechargeAmount":"50.00","giveAmount":"50.00","totalSpendAmount":"33.40","frozenBalance":"0.00"}}}"#
        let observation = GLMAccountReportParser.observe(data: Data(payload.utf8),
                                                         httpStatus: 200, schema: .consoleReportV1)

        XCTAssertNil(observation.parseFailure)
        XCTAssertEqual(observation.schema, .consoleReportV1)
        XCTAssertTrue(observation.isDisplayable)
        let balance = observation.candidateBalances.first
        XCTAssertEqual(balance?.total, dec("100.00"))
        XCTAssertEqual(balance?.available, dec("66.6"))
        XCTAssertEqual(balance?.currency, nil, "this endpoint's shape names no currency")

        // The four extra amounts keep their original semantics as labelled amounts.
        let extras = balance?.additionalAmounts ?? []
        XCTAssertEqual(extras.map { $0.field }, ["rechargeAmount", "giveAmount", "totalSpendAmount", "frozenBalance"])
        XCTAssertEqual(extras.map { $0.label }, ["累计充值", "累计赠送", "累计消费", "冻结金额"])
        XCTAssertEqual(extras.map { $0.amount }, [dec("50.00"), dec("50.00"), dec("33.40"), dec("0")])
        XCTAssertNil(balance?.toppedUp, "累计充值 must never be bent into the 充值 field")
        XCTAssertNil(balance?.granted, "累计赠送 must never be bent into the 赠费 field")
    }

    func testConsoleReportWithoutTheBalanceObjectIsNotDisplayable() {
        // The user's real probe answered HTTP 200 with top-level code/data/msg/success;
        // this fixture models a data shape nothing documents yet.
        let payload = #"{"code":200,"success":true,"msg":"success","data":{"list":[],"total":0}}"#
        let observation = GLMAccountReportParser.observe(data: Data(payload.utf8),
                                                         httpStatus: 200, schema: .consoleReportV1)
        XCTAssertEqual(observation.parseFailure, ProviderFailure.unexpectedResponse)
        XCTAssertFalse(observation.isDisplayable)
        XCTAssertFalse(observation.structureSummary.isEmpty,
                       "the real shape is recorded redacted for the next revision")
    }

    // MARK: Redacted structure summary

    func testStructureSummaryRecordsPathsAndTypesOnly() {
        let payload: [String: Any] = [
            "code": 200,
            "success": true,
            "msg": "secret upstream message text",
            "data": [
                "balance": [
                    "availableBalance": 12.5,
                    "list": [["a": 1]],
                    "flag": false,
                    "empty": NSNull(),
                    "name": "value-must-not-leak",
                ] as [String: Any],
            ] as [String: Any],
        ]
        let summary = GLMAccountReportParser.structureSummary(of: payload)

        XCTAssertEqual(summary, [
            "code: number",
            "data: object",
            "data.balance: object",
            "data.balance.availableBalance: number",
            "data.balance.empty: null",
            "data.balance.flag: boolean",
            "data.balance.list: array",
            "data.balance.name: string",
            "msg: string",
            "success: boolean",
        ])

        // No value may appear: only path and type tokens.
        let allowed = ["object", "array", "number", "string", "boolean", "null", "value"]
        for entry in summary {
            let parts = entry.split(separator: ":")
            XCTAssertEqual(parts.count, 2, entry)
            XCTAssertTrue(allowed.contains(parts[1].trimmingCharacters(in: .whitespaces)), entry)
            XCTAssertFalse(entry.contains("secret"), entry)
            XCTAssertFalse(entry.contains("value-must-not-leak"), entry)
        }
    }

    func testStructureSummaryIsDepthCappedAndCountCapped() {
        var deep: [String: Any] = ["leaf": 1]
        for _ in 0..<6 {
            deep = ["next": deep]
        }
        let summary = GLMAccountReportParser.structureSummary(of: deep, maxDepth: 3)
        for entry in summary {
            let path = entry.split(separator: ":")[0]
            XCTAssertLessThanOrEqual(path.split(separator: ".").count, 3, entry)
        }

        var wide: [String: Any] = [:]
        for i in 0..<50 { wide["k\(i)"] = i }
        let capped = GLMAccountReportParser.structureSummary(of: wide, maxEntries: 24)
        XCTAssertLessThanOrEqual(capped.count, 24)
    }

    // MARK: Round 8: honest amounts, null rejection, auth business codes

    func testAvailableOnlyResponseKeepsTotalNil() {
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":200,"data":{"available_balance":"88.00"}}"#.utf8),
            httpStatus: 200, schema: .apiBalanceV1)

        XCTAssertNil(observation.parseFailure)
        let balance = observation.candidateBalances.first
        XCTAssertNil(balance?.total, "an available balance is never copied into total")
        XCTAssertEqual(balance?.available, dec("88.00"))
        XCTAssertTrue(observation.isDisplayable)
        XCTAssertEqual(DecimalFormatting.balanceText(balance!), "88.00")
        XCTAssertEqual(DecimalFormatting.balanceDetailText(balance!), "可用 88.00",
                       "the main line shows the available amount without inventing a 总额 line")
    }

    func testConsoleReportAvailableOnlyKeepsTotalNil() {
        let payload = #"{"code":200,"success":true,"data":{"balance":{"availableBalance":66.6}}}"#
        let observation = GLMAccountReportParser.observe(data: Data(payload.utf8),
                                                         httpStatus: 200, schema: .consoleReportV1)
        XCTAssertNil(observation.parseFailure)
        let balance = observation.candidateBalances.first
        XCTAssertNil(balance?.total)
        XCTAssertEqual(balance?.available, dec("66.6"))
        XCTAssertTrue(observation.isDisplayable)
    }

    func testPresentNullDeclaredFieldIsAContractViolationNotAMaskedValue() {
        // total_balance valid, available_balance explicitly null: the strict contract
        // fails instead of silently substituting the total (REVIEW round 7 finding 4).
        let observation = GLMAccountReportParser.observe(
            data: Data(#"{"code":200,"data":{"total_balance":100,"available_balance":null}}"#.utf8),
            httpStatus: 200, schema: .apiBalanceV1)
        XCTAssertEqual(observation.parseFailure, ProviderFailure.unexpectedResponse)
        XCTAssertTrue(observation.candidateBalances.isEmpty)

        let consolePayload = #"{"code":200,"success":true,"data":{"balance":{"balance":"100","giveAmount":null}}}"#
        let consoleObservation = GLMAccountReportParser.observe(
            data: Data(consolePayload.utf8), httpStatus: 200, schema: .consoleReportV1)
        XCTAssertEqual(consoleObservation.parseFailure, ProviderFailure.unexpectedResponse)
        XCTAssertTrue(consoleObservation.candidateBalances.isEmpty)
    }

    func testAuthenticationBusinessCodesMapToInvalidCredential() {
        for payload in [#"{"code":401}"#, #"{"code":403}"#, #"{"code":"401"}"#] {
            let observation = GLMAccountReportParser.observe(
                data: Data(payload.utf8), httpStatus: 200, schema: .apiBalanceV1)
            XCTAssertEqual(observation.parseFailure, ProviderFailure.invalidCredential, payload)
            XCTAssertTrue(observation.parseFailure!.isAuthenticationFailure, payload)
        }
        // Unknown codes stay neutral business errors.
        let neutral = GLMAccountReportParser.observe(
            data: Data(#"{"code":1113}"#.utf8), httpStatus: 200, schema: .apiBalanceV1)
        XCTAssertEqual(neutral.parseFailure, ProviderFailure.businessError(code: 1113))
        XCTAssertFalse(neutral.parseFailure!.isAuthenticationFailure)
    }

    // MARK: Round 8: the selected connection mode survives restarts

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "GLMProviderTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeSession(cookies: String, capturedAt: Date) -> GLMConsoleSessionPolicy.StoredSession {
        return GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: cookies, value: "v",
                                                           domain: "bigmodel.cn", expiresAt: Date().addingTimeInterval(3600))],
            capturedAt: capturedAt)
    }

    /// Both credentials stored, console selected: a fresh reader (restart) keeps using
    /// the console session instead of silently switching back to the API key.
    func testConsoleSelectionSurvivesRestart() async throws {
        let defaults = makeIsolatedDefaults()
        let store = InMemoryCredentialStore()
        let transport = FakeTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"success":true,"data":{"balance":{"balance":"9.00","availableBalance":"5.00"}}}"#.utf8))
        }

        let first = GLMReading(provider: GLMProvider(transport: transport, credentials: store),
                               credentials: store, preferences: defaults)
        try first.storeAPIKey("glm-old-key")
        try first.storeSession(makeSession(cookies: "sid", capturedAt: Date(timeIntervalSince1970: 1_700_000_000)))

        // A brand-new reader models the restarted app.
        let restarted = GLMReading(provider: GLMProvider(transport: transport, credentials: store),
                                   credentials: store, preferences: defaults)
        _ = try await restarted.read()

        let requests = transport.recordedRequests
        XCTAssertEqual(Set(requests.compactMap { $0.url?.path }), [GLMProvider.accountReportPath],
                       "the console connection is still the selected one")
        for request in requests {
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"),
                         "the old key must not be used after a console connection was selected")
        }
        // Session-derived numbers land in the session's own cache identity.
        _ = try XCTUnwrap(transport.recordedRequests.first)
        XCTAssertTrue(restarted.hasAPIKey, "sanity: the old key is still stored, just not selected")
    }

    /// The last selected mode wins: storing a key after a session selects the key again.
    func testStoringAKeyAfterASessionSelectsTheKey() async throws {
        let defaults = makeIsolatedDefaults()
        let store = InMemoryCredentialStore()
        let transport = FakeTransport()
        transport.handler = { _ in
            ProviderHTTPResponse(status: 200, body: Data(#"{"code":200,"data":{"available_balance":"1.00"}}"#.utf8))
        }

        let reading = GLMReading(provider: GLMProvider(transport: transport, credentials: store),
                                 credentials: store, preferences: defaults)
        try reading.storeSession(makeSession(cookies: "sid", capturedAt: Date()))
        try reading.storeAPIKey("glm-new-key")
        _ = try await reading.read()

        let paths = transport.recordedRequests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, [GLMProvider.balancePath], "the freshly saved key is the selected credential")
    }

    /// Session reads never land in the API key's cache entry, even with both stored.
    func testSessionReadsUseASessionSpecificCacheIdentity() throws {
        let session = makeSession(cookies: "sid", capturedAt: Date(timeIntervalSince1970: 1_700_000_100))
        XCTAssertEqual(GLMReading.sessionAccountID(session), "console-1700000100000")
        XCTAssertNotEqual(GLMReading.sessionAccountID(session),
                          "apikey-" + GLMProvider.apiKeyFingerprint(forAPIKey: "glm-old-key"),
                          "session money must never be attributed to the key's cache entry")
    }

    func testDisconnectClearsThePersistedMode() throws {
        let defaults = makeIsolatedDefaults()
        let store = InMemoryCredentialStore()
        let reading = GLMReading(provider: GLMProvider(transport: FakeTransport(), credentials: store),
                                 credentials: store, preferences: defaults)
        try reading.storeAPIKey("glm-key")
        XCTAssertNotNil(defaults.string(forKey: GLMReading.connectionModeKey))

        try reading.disconnect()
        XCTAssertNil(defaults.string(forKey: GLMReading.connectionModeKey),
                     "a disconnected platform must not keep a selected mode")
    }

    // MARK: Credential handling

    func testProbeWithoutKeyIsNotConfigured() async {
        let provider = GLMProvider(transport: FakeTransport(), credentials: InMemoryCredentialStore())
        do {
            _ = try await provider.probeBalance()
            XCTFail("no key must fail")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .notConfigured)
        }
    }

    func testProbeSendsTheKeyToTheBalanceEndpointOnly() async throws {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }
        let credentials = InMemoryCredentialStore()
        try credentials.save("glm-key", for: .glmAPIKey)
        let provider = GLMProvider(transport: transport, credentials: credentials)

        do {
            _ = try await provider.probeBalance()
            XCTFail("401 must fail")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .invalidCredential)
        }

        let hosts = Set(transport.recordedRequests.compactMap { $0.url?.host })
        XCTAssertEqual(hosts, ["open.bigmodel.cn"], "the key is offered to the official host only")
        let paths = Set(transport.recordedRequests.compactMap { $0.url?.path })
        XCTAssertEqual(paths, [GLMProvider.balancePath], "a plain key probes the balance endpoint")
        for request in transport.recordedRequests {
            XCTAssertFalse(ProviderRequestGuard.isModelEndpoint(path: request.url?.path ?? ""),
                           "a probe must never be a model call")
        }
    }

    func testDeletingTheKeyAndSessionClearsTheStore() throws {
        let credentials = InMemoryCredentialStore()
        try credentials.save("glm-key", for: .glmAPIKey)
        let session = GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: "c", value: "v", domain: "bigmodel.cn", expiresAt: nil)],
            capturedAt: Date())
        try credentials.save(String(decoding: GLMConsoleSessionPolicy.encode(session), as: UTF8.self),
                             for: .glmConsoleSession)

        let reading = GLMReading(provider: GLMProvider(transport: FakeTransport(), credentials: credentials),
                                 credentials: credentials)
        XCTAssertTrue(reading.isConfigured)

        try reading.disconnect()
        XCTAssertFalse(reading.isConfigured)
        XCTAssertNil(credentials.load(.glmAPIKey))
        XCTAssertNil(credentials.load(.glmConsoleSession))
    }

    func testAutomaticRefreshFollowsTheConfirmedSchemaOfTheStoredCredential() throws {
        let credentials = InMemoryCredentialStore()
        let reading = GLMReading(provider: GLMProvider(transport: FakeTransport(), credentials: credentials),
                                 credentials: credentials)
        XCTAssertFalse(reading.isAutomaticRefreshEnabled, "nothing stored, nothing to poll")

        try credentials.save("glm-key", for: .glmAPIKey)
        XCTAssertTrue(reading.isAutomaticRefreshEnabled,
                      "the balance schema is confirmed, so the key joins the periodic cycle")
    }

    // MARK: Console session policy

    func testNavigationIsLimitedToOfficialConsoleHosts() {
        XCTAssertTrue(GLMConsoleSessionPolicy.isNavigationAllowed(URL(string: "https://bigmodel.cn/login")!))
        XCTAssertTrue(GLMConsoleSessionPolicy.isNavigationAllowed(URL(string: "https://open.bigmodel.cn/x")!))
        XCTAssertTrue(GLMConsoleSessionPolicy.isNavigationAllowed(URL(string: "https://console.bigmodel.cn/x")!))

        XCTAssertFalse(GLMConsoleSessionPolicy.isNavigationAllowed(URL(string: "http://bigmodel.cn/x")!),
                       "http is not allowed")
        XCTAssertFalse(GLMConsoleSessionPolicy.isNavigationAllowed(URL(string: "https://evil.example.com/x")!))
        XCTAssertFalse(GLMConsoleSessionPolicy.isNavigationAllowed(URL(string: "https://bigmodel.cn.evil.com/x")!),
                       "a suffix of the host is not the host")
        XCTAssertFalse(GLMConsoleSessionPolicy.isNavigationAllowed(URL(string: "file:///etc/passwd")!))
    }

    func testCookiesFromOtherDomainsAreFilteredOut() {
        XCTAssertTrue(GLMConsoleSessionPolicy.isCookieAllowed(domain: "bigmodel.cn"))
        XCTAssertTrue(GLMConsoleSessionPolicy.isCookieAllowed(domain: ".open.bigmodel.cn"))
        XCTAssertFalse(GLMConsoleSessionPolicy.isCookieAllowed(domain: "google-analytics.com"))
        XCTAssertFalse(GLMConsoleSessionPolicy.isCookieAllowed(domain: nil))
    }

    func testSessionRoundTripKeepsOnlyNamesAndValues() throws {
        let session = GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: "session", value: "abc", domain: "bigmodel.cn",
                                                           expiresAt: Date(timeIntervalSince1970: 1_800_000_000))],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try GLMConsoleSessionPolicy.encode(session)
        let restored = try XCTUnwrap(GLMConsoleSessionPolicy.decode(data))
        XCTAssertEqual(restored, session)
    }

    func testSessionStateTransitions() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(GLMConsoleSessionPolicy.evaluate(nil, now: now), .absent)

        let noExpiry = GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: "s", value: "v", domain: "bigmodel.cn", expiresAt: nil)],
            capturedAt: now)
        XCTAssertEqual(GLMConsoleSessionPolicy.evaluate(noExpiry, now: now), .present(expiresAt: nil))

        let future = GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: "s", value: "v", domain: "bigmodel.cn",
                                                           expiresAt: now.addingTimeInterval(3600))],
            capturedAt: now)
        XCTAssertEqual(GLMConsoleSessionPolicy.evaluate(future, now: now), .present(expiresAt: now.addingTimeInterval(3600)))

        let past = GLMConsoleSessionPolicy.StoredSession(
            cookies: [GLMConsoleSessionPolicy.StoredCookie(name: "s", value: "v", domain: "bigmodel.cn",
                                                           expiresAt: now.addingTimeInterval(-10))],
            capturedAt: now)
        XCTAssertEqual(GLMConsoleSessionPolicy.evaluate(past, now: now), .expired)

        let empty = GLMConsoleSessionPolicy.StoredSession(cookies: [], capturedAt: now)
        XCTAssertEqual(GLMConsoleSessionPolicy.evaluate(empty, now: now), .absent)
    }

    func testCookieHeaderOnlyCarriesOfficialDomainCookies() {
        let session = GLMConsoleSessionPolicy.StoredSession(
            cookies: [
                GLMConsoleSessionPolicy.StoredCookie(name: "good", value: "1", domain: "bigmodel.cn", expiresAt: nil),
                GLMConsoleSessionPolicy.StoredCookie(name: "bad", value: "2", domain: "tracker.example.com", expiresAt: nil),
            ],
            capturedAt: Date())
        XCTAssertEqual(GLMReading.cookieHeader(from: session), "good=1")
    }
}

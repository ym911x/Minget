import XCTest
@testable import UsageMonitorCore

private actor GoogleRecordingTransport: ProviderTransport {
    var requests: [URLRequest] = []
    var responses: [ProviderHTTPResponse]
    init(_ responses: [ProviderHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ProviderTransportError.other }
        return responses.removeFirst()
    }
}

final class AntigravityProviderTests: XCTestCase {
    private func parse(_ json: String) throws -> [AntigravityQuotaGroup] {
        try AntigravityProvider.parseGroups(Data(json.utf8))
    }
    private func response(_ json: String, status: Int = 200) -> ProviderHTTPResponse {
        ProviderHTTPResponse(status: status, body: Data(json.utf8))
    }
    private var account: AntigravityAccount {
        AntigravityAccount(id: "account-a", authIndex: "index-a", label: "Google A", email: nil,
                           projectID: "project-a", disabled: false, unavailable: false)
    }
    func testFractionsPreserveZeroAndMissingAndRejectIllegalValues() throws {
        let values = ["0", "1", "0.35", "null", "true", "-1", "2", "\"\"", "\"NaN\"", "\"0.4\""]
        let expected: [Double?] = [0, 1, 0.35, nil, nil, nil, nil, nil, nil, 0.4]
        for (raw, expected) in zip(values, expected) {
            let groups = try parse("{\"groups\":[{\"displayName\":\"Gemini\",\"buckets\":[{\"window\":\"5h\",\"remainingFraction\":\(raw)}]}]}")
            XCTAssertEqual(groups[0].buckets[0].remainingFraction, expected)
        }
        let missing = try parse(#"{"groups":[{"displayName":"Gemini","buckets":[{"resetTime":"2027-01-01T00:00:00Z"}]}]}"#)
        XCTAssertNil(missing[0].buckets[0].remainingFraction)
        XCTAssertEqual(missing[0].buckets[0].percentageText, "额度未知")
    }
    func testModelResponseDoesNotInventSharedGroupsOrPeriods() throws {
        let groups = try parse(#"{"models":{"gemini-pro":{"quotaInfo":{"remainingFraction":0.6}},"gemini-flash":{"quotaInfo":{"remainingFraction":0.6,"resetTime":"bad"}}}}"#)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.id)), ["gemini-pro", "gemini-flash"])
        XCTAssertTrue(groups.allSatisfy { $0.buckets[0].kind == .unknown })
        XCTAssertTrue(groups.allSatisfy { $0.buckets[0].resetsAt == nil })
    }
    func testGroupsKeepAllPeriodsAndFractionalResetDates() throws {
        let groups = try parse(#"{"groups":[{"groupId":"gemini","displayName":"Gemini","models":["gemini-pro"],"buckets":[{"bucketId":"five","window":"5h","remainingFraction":0,"resetTime":"2027-01-01T00:00:00.123Z"},{"bucketId":"week","window":"7d","remainingFraction":0.2}]}]}"#)
        XCTAssertEqual(groups[0].id, "gemini")
        XCTAssertEqual(groups[0].models, ["gemini-pro"])
        XCTAssertEqual(groups[0].buckets.map(\.kind), [.fiveHour, .weekly])
        XCTAssertNotNil(groups[0].buckets[0].resetsAt)
        XCTAssertNil(groups[0].buckets[1].resetsAt)
    }
    func testReachedResetNeverRefillsQuota() throws {
        let group = try parse(#"{"models":{"gemini":{"quotaInfo":{"remainingFraction":0,"resetTime":"2020-01-01T00:00:00Z"}}}}"#)[0]
        XCTAssertEqual(group.buckets[0].resetText(), "已到重置时间，等待刷新")
        XCTAssertEqual(group.buckets[0].remainingFraction, 0)
    }
    func testUnconfirmedPayloadsFailClosed() {
        for raw in ["{}", "[]", "{\"models\":{}}", "{\"error\":{}}", "{\"models\":{\"gemini\":{}}}"] {
            XCTAssertThrowsError(try parse(raw))
        }
    }
    func testOnlyLiteralLoopbackHTTPOriginIsAllowed() throws {
        for address in ["http://127.0.0.1:8317", "http://127.0.0.1:9000/"] {
            XCTAssertNoThrow(try AntigravityProvider.validatedBaseURL(address))
        }
        for address in ["http://localhost:8317", "https://example.com", "http://127.0.0.1.evil.test", "http://user:secret@127.0.0.1", "http://127.0.0.1?url=x", "http://127.0.0.1/v1", "http://127.0.0.1#x"] {
            XCTAssertThrowsError(try AntigravityProvider.validatedBaseURL(address))
        }
    }
    func testDiscoveryFiltersProviderAndUsesPublicMetadataOnly() async throws {
        let transport = GoogleRecordingTransport([response(#"{"files":[{"id":"a","auth_index":"ia","type":"antigravity","email":"example@example.test","project_id":"p"},{"id":"b","auth_index":"ib","provider":"antigravity","disabled":true},{"id":"c","auth_index":"ic","provider":"codex"}]}"#)])
        let accounts = try await AntigravityProvider(transport: transport).accounts(baseURL: AntigravityProvider.defaultBaseURL, managementKey: "synthetic-key")
        XCTAssertEqual(accounts.map(\.id), ["a", "b"])
        XCTAssertEqual(accounts[0].projectID, "p")
        XCTAssertTrue(accounts[1].disabled)
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url?.path, "/v0/management/auth-files")
        XCTAssertEqual(requests[0].httpMethod, "GET")
    }
    func testQuotaForwardingHasFixedQueryAndTokenPlaceholder() async throws {
        let upstream = #"{"groups":[{"displayName":"Gemini","buckets":[{"window":"5h","remainingFraction":0.8}]}]}"#
        let envelope = try JSONSerialization.data(withJSONObject: ["status_code": 200, "body": upstream])
        let transport = GoogleRecordingTransport([ProviderHTTPResponse(status: 200, body: envelope)])
        let snapshot = try await AntigravityProvider(transport: transport).quota(account: account, baseURL: AntigravityProvider.defaultBaseURL, managementKey: "synthetic-key")
        XCTAssertEqual(snapshot.accountIdentity, account.identity)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(request.url?.host, "127.0.0.1")
        XCTAssertEqual(request.url?.path, "/v0/management/api-call")
        XCTAssertEqual(body["url"] as? String, "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")
        XCTAssertEqual(body["method"] as? String, "POST")
        XCTAssertEqual(body["auth_index"] as? String, "index-a")
        XCTAssertEqual((body["header"] as? [String: String])?["Authorization"], "Bearer $TOKEN$")
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("synthetic-key"))
    }
    func testUnsupportedSummaryFallsBackToModelQuery() async throws {
        let empty = response(#"{"status_code":404,"body":"{}"}"#)
        let upstream = #"{"models":{"gemini":{"quotaInfo":{"remainingFraction":1}}}}"#
        let data = try JSONSerialization.data(withJSONObject: ["status_code": 200, "body": upstream])
        let transport = GoogleRecordingTransport([empty, empty, empty, ProviderHTTPResponse(status: 200, body: data)])
        let snapshot = try await AntigravityProvider(transport: transport).quota(account: account, baseURL: AntigravityProvider.defaultBaseURL, managementKey: "synthetic")
        XCTAssertEqual(snapshot.groups.count, 1)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(String(decoding: requests[3].httpBody!, as: UTF8.self).contains("fetchAvailableModels"))
    }
    func testAuthenticationThrottlingAndRedirectDoNotTriggerFallback() async {
        for status in [401, 429, 302] {
            let transport = GoogleRecordingTransport([response("{\"status_code\":\(status),\"body\":\"{}\"}")])
            do {
                _ = try await AntigravityProvider(transport: transport).quota(account: account, baseURL: AntigravityProvider.defaultBaseURL, managementKey: "synthetic")
                XCTFail("status \(status) must fail")
            } catch {}
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }
    func testGoogleMenuBarShowsOnlyReportedPeriods() throws {
        let groups = try parse(#"{"groups":[{"displayName":"Gemini","buckets":[{"window":"5h","remainingFraction":0.8}]}]}"#)
        let content = MenuBarContentBuilder.make(source: .antigravity(shortLabel: "G1", group: groups[0], isCached: false), now: Date(), mode: .full)
        XCTAssertEqual(content.text, "G1 Gemini 5H 80%")
        XCTAssertEqual(content.fiveHour.segmentCount, 5)
        XCTAssertEqual(content.weekly.segmentCount, 0)
        XCTAssertFalse(content.accessibilityText.contains("周额度"))
        XCTAssertEqual(content.attention, .none)
        let missing = MenuBarContentBuilder.make(source: .antigravity(shortLabel: "G1", group: nil, isCached: true), now: Date(), mode: .full)
        XCTAssertFalse(missing.showsTimeBars)
        XCTAssertEqual(missing.attention, .warning)
    }
    func testGoogleTransportRejectsEvenSameOriginRedirects() throws {
        let delegate = RedirectGuardDelegate(refuseAllRedirects: true)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "http://127.0.0.1:8317/v0/management/auth-files")!
        let task = session.dataTask(with: URLRequest(url: original))
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var followed = true
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "http://127.0.0.1:8317/v1/messages")!)) {
            followed = $0 != nil
        }
        XCTAssertFalse(followed)
        XCTAssertTrue(delegate.refusedRedirect(for: task))
    }

    func testMissingSelectedGroupStaysUnavailable() {
        let content = MenuBarContentBuilder.make(source: .antigravity(shortLabel: "G2", group: nil,
            isCached: false, missingGroup: true), now: Date(), mode: .full)
        XCTAssertEqual(content.text, "G2 额度组不可用")
        XCTAssertEqual(content.attention, .warning)
        XCTAssertFalse(content.showsTimeBars)
    }
    func testSeparateCoordinatorsSerializeProcessWideKeychainPolicy() async {
        let store = ConcurrentAccessProbe()
        let google = CredentialAccessCoordinator(store: store)
        let existing = CredentialAccessCoordinator(store: store)
        async let first = google.value(for: .antigravityManagementKey, purpose: .providerRead, interaction: .disallowed)
        async let second = existing.value(for: .deepseekAPIKey, purpose: .userRequestedRead, interaction: .allowed)
        _ = await (first, second)
        XCTAssertEqual(store.maximumActive, 1)
        XCTAssertEqual(store.calls, 2)
    }

}

private final class ConcurrentAccessProbe: ProviderCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private(set) var maximumActive = 0
    private(set) var calls = 0
    func save(_ secret: String, for key: ProviderCredentialKey) throws {}
    func delete(_ key: ProviderCredentialKey) throws {}
    func load(_ key: ProviderCredentialKey, interaction: CredentialInteraction) -> CredentialAccessOutcome {
        lock.lock(); active += 1; calls += 1; maximumActive = max(maximumActive, active); lock.unlock()
        Thread.sleep(forTimeInterval: 0.03)
        lock.lock(); active -= 1; lock.unlock()
        return .missing
    }
}

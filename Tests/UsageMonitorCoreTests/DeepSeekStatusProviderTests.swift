import XCTest
@testable import UsageMonitorCore

final class DeepSeekStatusProviderTests: XCTestCase {

    func testOfficialHealthyHeadlineMapsToOperational() {
        XCTAssertEqual(
            DeepSeekStatusProvider.status(in: "Everything is running smoothly. All systems are operating as expected."),
            .operational
        )
    }

    func testHistoricalOutageTextDoesNotOverrideHealthyHeadline() {
        let page = "Everything is running smoothly. All systems are operating as expected. Past incidents: Major outage resolved."
        XCTAssertEqual(DeepSeekStatusProvider.status(in: page), .operational)
    }

    func testIncidentHeadlinesMapToDegradedOrOutage() {
        XCTAssertEqual(DeepSeekStatusProvider.status(in: "Some systems are experiencing issues."), .degraded)
        XCTAssertEqual(DeepSeekStatusProvider.status(in: "Major outage"), .outage)
        XCTAssertEqual(DeepSeekStatusProvider.status(in: "Scheduled maintenance"), .maintenance)
    }

    func testUnknownTextStaysUnknown() {
        XCTAssertEqual(DeepSeekStatusProvider.status(in: "The status page layout changed."), .unknown)
    }

    func testHTMLScriptsAndTagsAreRemovedBeforeParsing() {
        let html = """
        <html><script>document.body.innerText = 'Major outage'</script>
        <body><h1>Everything is running smoothly</h1><p>All systems are operating as expected.</p></body></html>
        """
        let visible = DeepSeekStatusProvider.visibleText(from: Data(html.utf8))
        XCTAssertEqual(visible, "Everything is running smoothly All systems are operating as expected.")
        XCTAssertEqual(DeepSeekStatusProvider.status(in: visible), .operational)
    }

    func testReaderUsesOfficialStatusPageWithoutAuthorization() async throws {
        let transport = FakeTransport()
        transport.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://status.deepseek.com/")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return ProviderHTTPResponse(
                status: 200,
                body: Data("<h1>Everything is running smoothly</h1>".utf8)
            )
        }
        let date = Date(timeIntervalSince1970: 123)
        let snapshot = try await DeepSeekStatusProvider(transport: transport, clock: { date }).fetchStatus()
        XCTAssertEqual(snapshot.status, .operational)
        XCTAssertEqual(snapshot.checkedAt, date)
    }

    func testNonSuccessResponseIsNotPresentedAsOperational() async {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 503, body: Data()) }
        do {
            _ = try await DeepSeekStatusProvider(transport: transport).fetchStatus()
            XCTFail("a non-success status page response must fail closed")
        } catch {
            XCTAssertEqual(error as? ProviderStatusError, .httpStatus(503))
        }
    }
}

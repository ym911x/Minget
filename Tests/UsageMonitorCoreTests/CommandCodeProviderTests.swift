import XCTest
@testable import UsageMonitorCore

final class CommandCodeProviderTests: XCTestCase {

    func testReadsOnlyTheThreeUsageEndpointsWithBearerAuthentication() async throws {
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{"monthlyCredits":"7.25"},"windowLimits":{"fiveHour":{"cap":"4","used":"1","resetAt":"1780200000"},"weekly":{"cap":20,"used":4,"resetAt":"1780300000000"}}}"#)
            case CommandCodeProvider.summaryPath:
                return response(#"{"totalTokens":"1000","totalTokensIn":800,"totalTokensOut":200,"totalCount":10,"completedCount":9,"failedCount":1,"successRate":"90","totalCost":"2.5","totalMonthlyCredits":"2.75","periodBasis":"billing-period"}"#)
            case CommandCodeProvider.subscriptionsPath:
                return response(#"{"success":true,"data":{"planId":"individual-go","currentPeriodEnd":"2026-10-01T00:00:00.000Z"}}"#)
            default: throw ProviderTransportError.pathNotAllowed
            }
        }

        let usage = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "test-command-key")

        XCTAssertEqual(Set(transport.recordedRequests.compactMap { $0.url?.path }), CommandCodeProvider.allowedPaths)
        for request in transport.recordedRequests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "api.commandcode.ai")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-command-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        }
        XCTAssertEqual(usage.windows.first(where: { $0.kind == .fiveHour })?.remaining, dec("3"))
        XCTAssertEqual(usage.windows.first(where: { $0.kind == .weekly })?.resetsAt?.timeIntervalSince1970, 1_780_300_000)
        let monthly = try XCTUnwrap(usage.windows.first(where: { $0.kind == .billingPeriod }))
        XCTAssertEqual(monthly.used, dec("2.75"))
        XCTAssertEqual(monthly.limit, dec("10"))
        XCTAssertEqual(usage.summary?.totalTokens, 1000)
        XCTAssertEqual(usage.summary?.periodBasis, .billingPeriod)
        XCTAssertEqual(usage.planName, "individual-go")
    }

    func testSubscriptionFailureDoesNotDiscardCreditsAndSummary() async throws {
        let transport = FakeTransport()
        transport.handler = { request in
            if request.url?.path == CommandCodeProvider.subscriptionsPath { return ProviderHTTPResponse(status: 503, body: Data()) }
            if request.url?.path == CommandCodeProvider.creditsPath {
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
            }
            return response(#"{"totalTokens":1}"#)
        }
        let usage = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")
        XCTAssertNil(usage.planName)
        XCTAssertEqual(usage.summary?.totalTokens, 1)
    }

    func testUnauthorizedRequiredEndpointSuspendsCredential() async {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 401, body: Data()) }
        do {
            _ = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")
            XCTFail("401 must not create usage data")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .invalidCredential)
        }
    }

    func testMissingSummaryMetricsAndBadWindowsFailClosed() async {
        let transport = FakeTransport()
        transport.handler = { request in
            if request.url?.path == CommandCodeProvider.creditsPath {
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":0,"used":0}}}"#)
            }
            return response(#"{"success":true,"data":null}"#)
        }
        do {
            _ = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")
            XCTFail("unknown fields must not be converted to zero")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .structureUnsupported)
        }
    }

    func testModelPathsAndUnlistedPathsAreLocallyRefused() {
        XCTAssertThrowsError(try ProviderHTTPClient.validate(path: "/alpha/generate", allowedPaths: CommandCodeProvider.allowedPaths)) {
            XCTAssertEqual($0 as? ProviderTransportError, .modelEndpointBlocked)
        }
        XCTAssertThrowsError(try ProviderHTTPClient.validate(path: "/provider/v1/chat/completions", allowedPaths: CommandCodeProvider.allowedPaths)) {
            XCTAssertEqual($0 as? ProviderTransportError, .modelEndpointBlocked)
        }
        XCTAssertThrowsError(try ProviderHTTPClient.validate(path: "/alpha/whoami", allowedPaths: CommandCodeProvider.allowedPaths)) {
            XCTAssertEqual($0 as? ProviderTransportError, .pathNotAllowed)
        }
    }

    func testFingerprintIsStableAndNeverContainsTheKey() {
        let key = "command-secret-key-123"
        let fingerprint = CommandCodeProvider.accountFingerprint(forAPIKey: key)
        XCTAssertEqual(fingerprint, CommandCodeProvider.accountFingerprint(forAPIKey: key))
        XCTAssertNotEqual(fingerprint, CommandCodeProvider.accountFingerprint(forAPIKey: "other-key"))
        XCTAssertFalse(fingerprint.contains("command"))
        XCTAssertEqual(fingerprint.count, 6)
    }
}

private func response(_ json: String) -> ProviderHTTPResponse {
    ProviderHTTPResponse(status: 200, body: Data(json.utf8))
}

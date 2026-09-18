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

    // MARK: - Layered tolerance (REQUIREMENTS.md §5)

    /// `credits` is the only required source. A failing summary must leave the quota windows
    /// live and simply report that the statistics are unavailable — never fail the whole read.
    func testSummaryFailureKeepsCreditsLiveAndReportsNoStatistics() async throws {
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":"4","used":"1"},"weekly":{"cap":"20","used":4}}}"#)
            case CommandCodeProvider.summaryPath:
                return ProviderHTTPResponse(status: 503, body: Data())
            case CommandCodeProvider.subscriptionsPath:
                return response(#"{"success":true,"data":{"planId":"individual-go"}}"#)
            default:
                throw ProviderTransportError.pathNotAllowed
            }
        }

        let usage = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")

        XCTAssertEqual(usage.windows.first(where: { $0.kind == .fiveHour })?.remaining, dec("3"))
        XCTAssertEqual(usage.windows.first(where: { $0.kind == .weekly })?.remaining, dec("16"))
        XCTAssertNil(usage.summary, "a failed summary must stay absent, not become zeroes")
        XCTAssertEqual(usage.planName, "individual-go", "the subscription is independent of the summary")
    }

    func testMalformedSummaryJSONKeepsTheCreditsWindows() async throws {
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
            case CommandCodeProvider.summaryPath:
                return response("not json at all")
            default:
                return ProviderHTTPResponse(status: 404, body: Data())
            }
        }

        let usage = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")

        XCTAssertEqual(usage.windows.first(where: { $0.kind == .fiveHour })?.remaining, dec("3"))
        XCTAssertNil(usage.summary)
    }

    /// An auxiliary 401/403 is not a credential verdict: the same request's credits call proved
    /// the key reads the main data, so the connection must not be suspended by the summary alone.
    func testSummaryUnauthorizedDoesNotDiscardCredits() async throws {
        for status in [401, 403] {
            let transport = FakeTransport()
            transport.handler = { request in
                switch request.url?.path {
                case CommandCodeProvider.creditsPath:
                    return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
                case CommandCodeProvider.summaryPath:
                    return ProviderHTTPResponse(status: status, body: Data())
                default:
                    return ProviderHTTPResponse(status: 503, body: Data())
                }
            }

            let usage = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")
            XCTAssertEqual(usage.windows.first(where: { $0.kind == .fiveHour })?.remaining, dec("3"),
                           "summary \(status) must not fail the read")
            XCTAssertNil(usage.summary)
        }
    }

    /// A monthly credit reported by `credits` survives a failed summary: the remaining amount is
    /// real, while the used/total pair is simply not available. Nothing is inferred from a
    /// period the service did not name (REQUIREMENTS.md §5.2).
    func testSummaryFailureKeepsTheMonthlyRemainingWithoutFabricatingUsedOrLimit() async throws {
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{"monthlyCredits":"7.25"},"windowLimits":{"fiveHour":{"cap":"4","used":"1"}}}"#)
            case CommandCodeProvider.summaryPath:
                return ProviderHTTPResponse(status: 500, body: Data())
            default:
                return ProviderHTTPResponse(status: 503, body: Data())
            }
        }

        let usage = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")
        let monthly = try XCTUnwrap(usage.windows.first(where: { $0.kind == .billingPeriod }))
        XCTAssertEqual(monthly.remaining, dec("7.25"), "the credits balance is real")
        XCTAssertNil(monthly.used, "an absent used value must not be invented")
        XCTAssertNil(monthly.limit, "an absent total must not be invented")
        XCTAssertNil(usage.summary)
    }

    /// The main source keeps its own error path: a 401/403 on credits still suspends the
    /// credential, even when the auxiliary endpoints would have answered happily.
    func testCreditsUnauthorizedStillSuspendsTheCredential() async throws {
        let transport = FakeTransport()
        transport.handler = { request in
            if request.url?.path == CommandCodeProvider.creditsPath {
                return ProviderHTTPResponse(status: 401, body: Data())
            }
            return response(#"{"totalTokens":1,"totalCount":1}"#)
        }
        do {
            _ = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")
            XCTFail("a failing credits call must fail the read")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .invalidCredential)
        }
    }

    /// An unsupported credits payload must not be reconstructed from summary or subscription:
    /// the read fails closed rather than presenting another endpoint's numbers as quota.
    func testUnsupportedCreditsStructureFailsClosedEvenWithAHealthySummary() async throws {
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{}}"#)
            case CommandCodeProvider.summaryPath:
                return response(#"{"totalTokens":"1000","totalCount":10,"periodBasis":"billing-period"}"#)
            default:
                return response(#"{"success":true,"data":{"planId":"individual-go"}}"#)
            }
        }
        do {
            _ = try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")
            XCTFail("quota cannot be assembled without credits windows")
        } catch {
            XCTAssertEqual(error as? ProviderFailure, .structureUnsupported)
        }
    }

    // MARK: - Billing cycle bounds (REVISION_SPEC.md §7.3)

    /// Runs one fetch with a credits/summary payload that always parses, plus the subscription
    /// body under test.
    private func usage(subscriptionBody: String) async throws -> ProviderUsage {
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{"monthlyCredits":"7.25"},"windowLimits":{"fiveHour":{"cap":"4","used":"1"}}}"#)
            case CommandCodeProvider.summaryPath:
                return response(#"{"totalTokens":"1000","totalCount":10}"#)
            case CommandCodeProvider.subscriptionsPath:
                return response(subscriptionBody)
            default:
                throw ProviderTransportError.pathNotAllowed
            }
        }
        return try await CommandCodeProvider(transport: transport).fetchUsage(apiKey: "key")
    }

    func testBillingPeriodStartIsParsedWhenTheServiceReportsIt() async throws {
        let parsed = try await usage(subscriptionBody: #"""
        {"success":true,"data":{"planId":"individual-go","currentPeriodStart":"2026-09-01T00:00:00.000Z","currentPeriodEnd":"2026-10-01T00:00:00.000Z"}}
        """#)
        let start = try XCTUnwrap(parsed.billingPeriodStart)
        let end = try XCTUnwrap(parsed.billingPeriodEnd)
        XCTAssertLessThan(start, end)
        XCTAssertEqual(end.timeIntervalSince(start), 30 * 24 * 3600, accuracy: 1)
    }

    func testBillingPeriodStartStaysAbsentWhenTheServiceOmitsIt() async throws {
        let parsed = try await usage(subscriptionBody: #"""
        {"success":true,"data":{"planId":"individual-go","currentPeriodEnd":"2026-10-01T00:00:00.000Z"}}
        """#)
        XCTAssertNil(parsed.billingPeriodStart,
                     "a missing start must stay missing: the monthly bar refuses to guess a cycle")
        XCTAssertNotNil(parsed.billingPeriodEnd)
    }

    func testAReversedBillingPeriodIsRejectedAsUnusable() async throws {
        let parsed = try await usage(subscriptionBody: #"""
        {"success":true,"data":{"planId":"individual-go","currentPeriodStart":"2026-10-01T00:00:00.000Z","currentPeriodEnd":"2026-09-01T00:00:00.000Z"}}
        """#)
        XCTAssertNil(parsed.billingPeriodStart, "a start after the end cannot describe a cycle")
        XCTAssertNotNil(parsed.billingPeriodEnd, "the end is still reported as the service gave it")
    }

    func testABillingPeriodStartEqualToTheEndIsRejected() async throws {
        let parsed = try await usage(subscriptionBody: #"""
        {"success":true,"data":{"currentPeriodStart":"2026-10-01T00:00:00.000Z","currentPeriodEnd":"2026-10-01T00:00:00.000Z"}}
        """#)
        XCTAssertNil(parsed.billingPeriodStart)
    }

    func testAMissingSubscriptionLeavesBothBoundsAbsent() async throws {
        let parsed = try await usage(subscriptionBody: #"{"success":true,"data":null}"#)
        XCTAssertNil(parsed.billingPeriodStart)
        XCTAssertNil(parsed.billingPeriodEnd)
    }
}

private func response(_ json: String) -> ProviderHTTPResponse {
    ProviderHTTPResponse(status: 200, body: Data(json.utf8))
}

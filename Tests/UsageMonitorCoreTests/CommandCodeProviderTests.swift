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

    // MARK: - Auxiliary throttling (REQUIREMENTS.md §4.3)

    private func throttledHandler(summaryBody: String = #"{"totalTokens":"1000","totalCount":10}"#) -> FakeTransport {
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
            case CommandCodeProvider.summaryPath:
                return response(summaryBody)
            case CommandCodeProvider.subscriptionsPath:
                return response(#"{"success":true,"data":{"planId":"individual-go"}}"#)
            default:
                throw ProviderTransportError.pathNotAllowed
            }
        }
        return transport
    }

    private func paths(of transport: FakeTransport) -> [String] {
        transport.recordedRequests.compactMap { $0.url?.path }
    }

    /// The second automatic refresh inside the reuse window only re-reads credits; the
    /// summary and subscription come from memory rather than the network.
    func testAutomaticRefreshReusesAuxiliaryPayloadsInsideFifteenMinutes() async throws {
        let cache = CommandCodeProvider.AuxiliaryCache()
        let now = Date()
        cache.now = { now }
        let transport = throttledHandler()
        let provider = CommandCodeProvider(transport: transport, auxiliaryCache: cache)

        let first = try await provider.fetchUsage(apiKey: "key")
        XCTAssertNotNil(first.summary)
        XCTAssertEqual(first.planName, "individual-go")
        XCTAssertEqual(first.summaryFreshness,
                       ProviderUsageComponentFreshness(lastSuccessfulAt: now, isLive: true))
        XCTAssertEqual(first.subscriptionFreshness,
                       ProviderUsageComponentFreshness(lastSuccessfulAt: now, isLive: true))
        let firstPaths = Set(paths(of: transport))
        XCTAssertEqual(firstPaths, CommandCodeProvider.allowedPaths)

        cache.now = { now.addingTimeInterval(5 * 60) }
        let second = try await provider.fetchUsage(apiKey: "key")
        XCTAssertEqual(second.summary, first.summary)
        XCTAssertEqual(second.planName, first.planName)
        XCTAssertEqual(second.summaryFreshness,
                       ProviderUsageComponentFreshness(lastSuccessfulAt: now, isLive: false))
        XCTAssertEqual(second.subscriptionFreshness,
                       ProviderUsageComponentFreshness(lastSuccessfulAt: now, isLive: false))
        let secondRound = paths(of: transport).dropFirst(firstPaths.count)
        XCTAssertEqual(Array(secondRound), [CommandCodeProvider.creditsPath],
                       "the throttled round must not touch summary or subscriptions")
    }

    /// A forced read (manual refresh, reconnect) bypasses the reuse window entirely.
    func testForcedReadBypassesTheAuxiliaryReuseWindow() async throws {
        let cache = CommandCodeProvider.AuxiliaryCache()
        let now = Date()
        cache.now = { now }
        let transport = throttledHandler()
        let provider = CommandCodeProvider(transport: transport, auxiliaryCache: cache)

        _ = try await provider.fetchUsage(apiKey: "key")
        let before = transport.recordedRequests.count
        cache.now = { now.addingTimeInterval(5 * 60) }
        _ = try await provider.fetchUsage(apiKey: "key", auxiliaryPolicy: .force)
        let forced = Set(paths(of: transport).dropFirst(before))
        XCTAssertEqual(forced, CommandCodeProvider.allowedPaths,
                       "a forced read must hit all three endpoints")
    }

    /// A failed auxiliary read does not start the reuse window: the next automatic
    /// refresh still retries the auxiliary endpoints.
    func testFailedAuxiliaryReadDoesNotStartTheReuseWindow() async throws {
        let cache = CommandCodeProvider.AuxiliaryCache()
        let now = Date()
        cache.now = { now }
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
            default:
                return ProviderHTTPResponse(status: 503, body: Data())
            }
        }
        let provider = CommandCodeProvider(transport: transport, auxiliaryCache: cache)

        let first = try await provider.fetchUsage(apiKey: "key")
        XCTAssertNil(first.summary)
        let before = transport.recordedRequests.count
        cache.now = { now.addingTimeInterval(5 * 60) }
        _ = try await provider.fetchUsage(apiKey: "key")
        let retried = Set(paths(of: transport).dropFirst(before))
        XCTAssertTrue(retried.contains(CommandCodeProvider.summaryPath),
                      "without a successful auxiliary read there is nothing to reuse")
    }

    func testPartialAuxiliaryFailureRetriesOnlyTheMissingComponent() async throws {
        let cache = CommandCodeProvider.AuxiliaryCache()
        let now = Date()
        cache.now = { now }
        let transport = FakeTransport()
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
            case CommandCodeProvider.summaryPath:
                return response(#"{"totalTokens":1000,"totalCount":10}"#)
            case CommandCodeProvider.subscriptionsPath:
                return ProviderHTTPResponse(status: 503, body: Data())
            default:
                throw ProviderTransportError.pathNotAllowed
            }
        }
        let provider = CommandCodeProvider(transport: transport, auxiliaryCache: cache)

        _ = try await provider.fetchUsage(apiKey: "key")
        let before = transport.recordedRequests.count
        cache.now = { now.addingTimeInterval(5 * 60) }
        _ = try await provider.fetchUsage(apiKey: "key")
        let secondRound = Set(paths(of: transport).dropFirst(before))

        XCTAssertEqual(secondRound,
                       [CommandCodeProvider.creditsPath, CommandCodeProvider.subscriptionsPath],
                       "the successful summary is reused while the failed subscription retries")
    }

    func testAuxiliaryComponentsExpireIndependently() async throws {
        let cache = CommandCodeProvider.AuxiliaryCache()
        let now = Date()
        cache.now = { now }
        let transport = FakeTransport()
        let lock = NSLock()
        var subscriptionShouldFail = true
        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
            case CommandCodeProvider.summaryPath:
                return response(#"{"totalTokens":1000,"totalCount":10}"#)
            case CommandCodeProvider.subscriptionsPath:
                let shouldFail = lock.withLock { subscriptionShouldFail }
                return shouldFail
                    ? ProviderHTTPResponse(status: 503, body: Data())
                    : response(#"{"success":true,"data":{"planId":"individual-go"}}"#)
            default:
                throw ProviderTransportError.pathNotAllowed
            }
        }
        let provider = CommandCodeProvider(transport: transport, auxiliaryCache: cache)

        _ = try await provider.fetchUsage(apiKey: "key")
        lock.withLock { subscriptionShouldFail = false }
        cache.now = { now.addingTimeInterval(5 * 60) }
        _ = try await provider.fetchUsage(apiKey: "key")

        let beforeExpiryRound = transport.recordedRequests.count
        cache.now = { now.addingTimeInterval(16 * 60) }
        _ = try await provider.fetchUsage(apiKey: "key")
        XCTAssertEqual(Set(paths(of: transport).dropFirst(beforeExpiryRound)),
                       [CommandCodeProvider.creditsPath, CommandCodeProvider.summaryPath],
                       "summary is 16 minutes old while the subscription is only 11 minutes old")
    }

    func testClockRollbackDoesNotTreatFutureAuxiliaryTimestampsAsReusable() async throws {
        let cache = CommandCodeProvider.AuxiliaryCache()
        let now = Date()
        cache.now = { now }
        let transport = throttledHandler()
        let provider = CommandCodeProvider(transport: transport, auxiliaryCache: cache)

        _ = try await provider.fetchUsage(apiKey: "key")
        let beforeRollbackRound = transport.recordedRequests.count
        cache.now = { now.addingTimeInterval(-60) }
        _ = try await provider.fetchUsage(apiKey: "key")

        XCTAssertEqual(Set(paths(of: transport).dropFirst(beforeRollbackRound)),
                       CommandCodeProvider.allowedPaths,
                       "a clock rollback must refresh rather than extend the cache window")
    }

    func testAuxiliaryCacheNeverCrossesCredentialBoundaries() async throws {
        let cache = CommandCodeProvider.AuxiliaryCache()
        let now = Date()
        cache.now = { now }
        let transport = FakeTransport()
        transport.handler = { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
            case CommandCodeProvider.summaryPath:
                return response(authorization.contains("key-a")
                    ? #"{"totalTokens":111,"totalCount":1}"#
                    : #"{"totalTokens":222,"totalCount":2}"#)
            case CommandCodeProvider.subscriptionsPath:
                return response(authorization.contains("key-a")
                    ? #"{"success":true,"data":{"planId":"plan-a"}}"#
                    : #"{"success":true,"data":{"planId":"plan-b"}}"#)
            default:
                throw ProviderTransportError.pathNotAllowed
            }
        }
        let provider = CommandCodeProvider(transport: transport, auxiliaryCache: cache)

        _ = try await provider.fetchUsage(apiKey: "key-a", auxiliaryPolicy: .force)
        cache.now = { now.addingTimeInterval(5 * 60) }
        let accountB = try await provider.fetchUsage(apiKey: "key-b")

        XCTAssertEqual(accountB.planName, "plan-b")
        XCTAssertEqual(accountB.summary?.totalTokens, 222)
        XCTAssertEqual(Set(paths(of: transport).suffix(3)), CommandCodeProvider.allowedPaths)
    }

    func testFailedForcedComponentKeepsOldValueAndDoesNotAdvanceSuccessTime() async throws {
        let cache = CommandCodeProvider.AuxiliaryCache()
        let now = Date()
        cache.now = { now }
        let transport = throttledHandler()
        let provider = CommandCodeProvider(transport: transport, auxiliaryCache: cache)
        let first = try await provider.fetchUsage(apiKey: "key")

        transport.handler = { request in
            switch request.url?.path {
            case CommandCodeProvider.creditsPath:
                return response(#"{"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1}}}"#)
            case CommandCodeProvider.summaryPath:
                return ProviderHTTPResponse(status: 503, body: Data())
            case CommandCodeProvider.subscriptionsPath:
                return response(#"{"success":true,"data":{"planId":"individual-pro"}}"#)
            default:
                throw ProviderTransportError.pathNotAllowed
            }
        }
        cache.now = { now.addingTimeInterval(5 * 60) }
        let second = try await provider.fetchUsage(apiKey: "key", auxiliaryPolicy: .force)

        XCTAssertEqual(second.summary, first.summary)
        XCTAssertEqual(second.summaryFreshness,
                       ProviderUsageComponentFreshness(lastSuccessfulAt: now, isLive: false))
        XCTAssertEqual(second.planName, "individual-pro")
        XCTAssertEqual(second.subscriptionFreshness,
                       ProviderUsageComponentFreshness(lastSuccessfulAt: now.addingTimeInterval(5 * 60), isLive: true))

        let beforeRetry = transport.recordedRequests.count
        cache.now = { now.addingTimeInterval(6 * 60) }
        _ = try await provider.fetchUsage(apiKey: "key")
        XCTAssertEqual(Set(paths(of: transport).dropFirst(beforeRetry)),
                       [CommandCodeProvider.creditsPath, CommandCodeProvider.summaryPath])
    }

    func testProviderUsageDecodesCacheWrittenBeforeComponentFreshness() throws {
        let legacy = Data(#"{"windows":[],"summary":null,"planName":"legacy","billingPeriodEnd":null,"billingPeriodStart":null}"#.utf8)
        let usage = try JSONDecoder().decode(ProviderUsage.self, from: legacy)
        XCTAssertEqual(usage.planName, "legacy")
        XCTAssertNil(usage.summaryFreshness)
        XCTAssertNil(usage.subscriptionFreshness)
    }
}

private func response(_ json: String) -> ProviderHTTPResponse {
    ProviderHTTPResponse(status: 200, body: Data(json.utf8))
}

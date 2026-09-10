import XCTest
@testable import UsageMonitorCore

/// Round 2 blocker 5: upstream error text must never reach diagnostics or UI.
/// Synthetic sentinels only; no real credentials are used anywhere in this suite.
final class DiagnosticsRedactionTests: XCTestCase {

    /// Sentinel material that looks like credentials but is fabricated for the test.
    static let syntheticBearer = "Bearer SYNTHEREDACTED0123456789abcdef0123456789"
    static let syntheticJWT = "eyJsyntheticheader000000000.eyJsyntheticpayload000000000.SYNTHETICSIGNATURE000000"
    static let syntheticKey = "sk-syntheticKey0123456789abcdef"

    func testCredentialShapedRunsAreRedacted() {
        let redacted = Diagnostics.redact("failed: \(Self.syntheticBearer)")
        XCTAssertFalse(redacted.contains("SYNTHEREDACTED0123456789"), redacted)
        XCTAssertTrue(redacted.contains("[redacted]"), redacted)

        let jwt = Diagnostics.redact("token \(Self.syntheticJWT)")
        XCTAssertFalse(jwt.contains("SYNTHETICSIGNATURE"), jwt)

        let key = Diagnostics.redact("key \(Self.syntheticKey)")
        XCTAssertFalse(key.contains("syntheticKey0123456789"), key)

        let hex = Diagnostics.redact("digest 0123456789abcdef0123456789abcdef")
        XCTAssertFalse(hex.contains("0123456789abcdef0123456789abcdef"), hex)
    }

    func testKeyedPairsAreRedacted() {
        let pair = Diagnostics.redact("error: authorization: Basic c3ludGhldGljX3VzZXI6cGFzcw==")
        XCTAssertTrue(pair.contains("[redacted]"), pair)
        XCTAssertFalse(pair.contains("c3ludGhldGljX3VzZXI6cGFzcw=="), pair)
    }

    func testServerErrorMessageNeverEntersUsageError() {
        // A server reply carrying a synthetic credential in its message must surface only
        // as a fixed category plus numeric code.
        let parser = UsageParser()
        let payload = "{\"id\":2,\"error\":{\"code\":-32603,\"message\":\"failed: \(Self.syntheticBearer)\"}}"
        XCTAssertThrowsError(try parser.parseResponse(data: Data(payload.utf8))) { error in
            guard let rpcError = error as? JSONRPCError else { return XCTFail("expected JSONRPCError") }
            let mapped = JSONRPCClient.usageError(from: rpcError)
            XCTAssertEqual(mapped, .rpcFailed(.serverError(code: -32603)))
            let summary = mapped.debugSummary
            XCTAssertFalse(summary.contains("SYNTHEREDACTED"), summary)
            XCTAssertFalse(summary.contains("failed"), summary)
            XCTAssertEqual(summary, "rpcFailed(serverError(code:-32603))")
        }
    }

    func testSignInShapedServerErrorsMapToNotSignedIn() {
        let rpcError = JSONRPCError(code: -32000, message: "user is not signed in \(Self.syntheticBearer)")
        let mapped = JSONRPCClient.usageError(from: rpcError)
        XCTAssertEqual(mapped, .codexNotSignedIn)
        XCTAssertFalse(mapped.debugSummary.contains("SYNTHEREDACTED"))
    }

    func testErrorTextForServerErrorsContainsNoUpstreamText() {
        let error = UsageError.rpcFailed(.serverError(code: -32603))
        let text = UsageFormatting.errorText(error)
        XCTAssertTrue(text.contains("Unable to read usage"))
        XCTAssertFalse(text.contains("chatgpt.com"))
        XCTAssertFalse(text.contains("SYNTHEREDACTED"))
    }

    func testLogWritesRedactedLinesOnly() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("usagemonitor-redaction-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        // The production path: a category summary that already carries no upstream text.
        Diagnostics.log("fetch failed: \(UsageError.rpcFailed(.serverError(code: -32603)).debugSummary)")
        // Defence in depth: a message that does carry sentinel material is scrubbed.
        Diagnostics.log("raw \(Self.syntheticBearer)")
        try? FileManager.default.removeItem(at: url)

        let previous = Diagnostics.fileURL
        // Re-enable logging through the same environment gate the app uses.
        setenv("USAGE_MONITOR_LOG_FILE", url.path, 1)
        Diagnostics.log("fetch failed: \(Self.syntheticBearer)")
        Diagnostics.log("fetch failed: \(UsageError.rpcFailed(.timedOut(method: "account/rateLimits/read")).debugSummary)")
        unsetenv("USAGE_MONITOR_LOG_FILE")
        _ = previous

        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(written.contains("SYNTHEREDACTED"), written)
        XCTAssertTrue(written.contains("rpcFailed(timedOut(account/rateLimits/read))"), written)
    }

    func testErrorCodeConversionNeverTraps() {
        // Previously `Int(Double)` on a huge code value could trap (Round 2 blocker 1).
        XCTAssertEqual(SafeConversion.errorCode(1e100), -1)
        XCTAssertEqual(SafeConversion.errorCode(-1e100), -1)
        XCTAssertEqual(SafeConversion.errorCode(-32603), -32603)
        XCTAssertEqual(SafeConversion.errorCode(3.9), -1, "fractional codes are not truncated")
        XCTAssertEqual(SafeConversion.errorCode(nil), -1)
        XCTAssertEqual(SafeConversion.errorCode(NSNull()), -1)
        XCTAssertEqual(SafeConversion.errorCode(true), -1)
    }
}

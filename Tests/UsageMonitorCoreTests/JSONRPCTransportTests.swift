import XCTest
@testable import UsageMonitorCore

/// Integration tests for the stdio JSON-RPC transport.
/// Fixtures are real child processes (system python3) speaking the verified
/// newline-delimited protocol, so framing, timeout, exit and cleanup are exercised
/// for real rather than being simulated.
final class JSONRPCTransportTests: XCTestCase {

    // MARK: - Fixture scripts (fixed literals, never built from user input)

    /// Replies correctly, but splits one reply across three writes and also emits
    /// non-JSON noise plus a notification, all in a single burst.
    static let noisyServer = """
    import sys, json, time
    def reply(obj):
        sys.stdout.write(json.dumps(obj) + "\\n")
        sys.stdout.flush()
    for raw in sys.stdin:
        try:
            msg = json.loads(raw)
        except Exception:
            continue
        method = msg.get("method")
        mid = msg.get("id")
        if method == "initialize":
            reply({"id": mid, "result": {"ok": True}})
        elif method == "account/rateLimits/read":
            payload = json.dumps({"id": mid, "result": {"rateLimitsByLimitId": {"codex": {"primary": {"usedPercent": 9, "windowDurationMins": 300, "resetsAt": 1788935373}, "secondary": {"usedPercent": 5, "windowDurationMins": 10080, "resetsAt": 1789453767}}}}})
            sys.stdout.write("this line is not json\\n")
            sys.stdout.write("\\n")
            sys.stdout.write(json.dumps({"method": "sessionConfigured", "params": {"noise": True}}) + "\\n")
            sys.stdout.write(payload[:60])
            sys.stdout.flush()
            time.sleep(0.05)
            sys.stdout.write(payload[60:150])
            sys.stdout.flush()
            time.sleep(0.05)
            sys.stdout.write(payload[150:] + "\\n")
            sys.stdout.flush()
        else:
            reply({"id": mid, "result": {}})
    """

    /// Replies only after a long delay: used for the timeout test.
    static let slowServer = """
    import sys, json, time
    for raw in sys.stdin:
        try:
            msg = json.loads(raw)
        except Exception:
            break
        if msg.get("method") == "initialize":
            sys.stdout.write(json.dumps({"id": msg.get("id"), "result": {}}) + "\\n")
            sys.stdout.flush()
        else:
            time.sleep(10)
            sys.stdout.write(json.dumps({"id": msg.get("id"), "result": {}}) + "\\n")
            sys.stdout.flush()
    """

    /// Writes garbage that is not JSON at all, then exits.
    static let garbageServer = """
    import sys, time
    sys.stdout.write("binary-ish output \\x01\\x02 without any json\\n")
    sys.stdout.flush()
    time.sleep(0.2)
    """

    /// Exits immediately without producing output.
    static let exitServer = """
    import sys
    sys.exit(3)
    """

    /// Never responds and never exits: proves stop() terminates the child.
    static let silentServer = """
    import sys, time
    for raw in sys.stdin:
        time.sleep(1)
    """

    /// Reports back the `CODEX_HOME` it was actually launched with, so a test can prove the
    /// environment reaches the child rather than merely being stored on the parent side.
    static let environmentEchoServer = """
    import sys, json, os
    for raw in sys.stdin:
        try:
            msg = json.loads(raw)
        except Exception:
            continue
        if msg.get("method") == "initialize":
            sys.stdout.write(json.dumps({"id": msg.get("id"), "result": {"codexHome": os.environ.get("CODEX_HOME", "")}}) + "\\n")
            sys.stdout.flush()
    """

    static let rateLimitsResult: [String: Any] = [
        "rateLimitsByLimitId": [
            "codex": [
                "primary": ["usedPercent": 9, "windowDurationMins": 300, "resetsAt": 1_788_935_373],
                "secondary": ["usedPercent": 5, "windowDurationMins": 10_080, "resetsAt": 1_789_453_767],
            ]
        ]
    ]

    func makeClient(_ script: String) throws -> JSONRPCClient {
        let client = JSONRPCClient(executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                                   arguments: ["-c", script])
        try client.start()
        return client
    }

    // MARK: - Framer

    func testFramerEmitsMultipleMessagesFromSingleChunk() {
        var framer = MessageFramer()
        let chunk = Data("{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n".utf8)
        let messages = framer.append(chunk)
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual((MessageFramer.decodeObject(messages[0])?["a"] as? Int), 1)
        XCTAssertEqual((MessageFramer.decodeObject(messages[2])?["c"] as? Int), 3)
        XCTAssertEqual(framer.pendingText, "")
    }

    func testFramerReassemblesMessageSplitAcrossChunks() {
        var framer = MessageFramer()
        let payload = Data("{\"hello\":\"world\",\"list\":[1,2,3]}".utf8)
        XCTAssertEqual(framer.append(payload[0..<10]), [])
        XCTAssertEqual(framer.append(payload[10..<25]), [])
        let messages = framer.append(payload[25...] + Data([0x0A]))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(MessageFramer.decodeObject(messages[0])?["hello"] as? String, "world")
    }

    func testFramerHandlesUTF8CharacterSplitAcrossChunks() {
        var framer = MessageFramer()
        // "剩余 78%" contains multi-byte characters; split mid-character.
        let text = "剩余 78%"
        var object: [String: Any] = ["note": text]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: []))! + Data([0x0A])
        let boundary = data.count - 8
        XCTAssertEqual(framer.append(data[0..<boundary]), [])
        let messages = framer.append(data[boundary...])
        XCTAssertEqual(messages.count, 1)
        object = MessageFramer.decodeObject(messages[0]) ?? [:]
        XCTAssertEqual(object["note"] as? String, text)
    }

    func testFramerDropsOversizedLineInsteadOfGrowingWithoutBound() {
        var framer = MessageFramer()
        let big = Data(repeating: 0x61, count: MessageFramer.maxLineBytes + 1024)
        let messages = framer.append(big + Data([0x0A]) + Data("{\"ok\":1}\n".utf8))
        XCTAssertTrue(framer.overflowed)
        XCTAssertEqual(messages.count, 1, "only the small valid line survives")
    }

    func testFramerRejectsNonJSONLines() {
        XCTAssertNil(MessageFramer.decodeObject(Data("not json".utf8)))
        XCTAssertNil(MessageFramer.decodeObject(Data("".utf8)))
        XCTAssertNil(MessageFramer.decodeObject(Data("   ".utf8)))
        XCTAssertNil(MessageFramer.decodeObject(Data("[1,2,3]".utf8)))
        XCTAssertEqual(MessageFramer.decodeObject(Data("{\"x\":null}".utf8))?["x"] as? NSNull, NSNull())
    }

    // MARK: - End to end

    func testHandshakeAndRateLimitsAcrossSplitWritesAndNoise() throws {
        let client = try makeClient(Self.noisyServer)
        defer { client.stop() }

        _ = try client.request(method: "initialize", params: ["clientInfo": ["name": "test", "version": "0"]], timeout: 10)
        try client.sendNotification(method: "initialized")
        let response = try client.request(method: "account/rateLimits/read", params: [:], timeout: 10)

        let parser = UsageParser()
        let snapshot = try parser.parseSnapshot(result: response.resultObject ?? [:])
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 9)
        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 91)
        XCTAssertEqual(snapshot.weekly?.windowDurationMinutes, 10_080)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 95)
        XCTAssertTrue(client.isRunning)
    }

    func testNonJSONOutputDoesNotBreakSubsequentRequests() throws {
        let client = try makeClient(Self.noisyServer)
        defer { client.stop() }
        _ = try client.request(method: "initialize", params: [:], timeout: 10)
        let first = try client.request(method: "account/rateLimits/read", params: [:], timeout: 10)
        let second = try client.request(method: "account/rateLimits/read", params: [:], timeout: 10)
        XCTAssertNotNil(first.resultObject)
        XCTAssertNotNil(second.resultObject)
        XCTAssertEqual((first.id as? NSNumber)?.intValue, 2)
        XCTAssertEqual((second.id as? NSNumber)?.intValue, 3)
    }

    func testRequestTimesOutAndThrowsUsageError() throws {
        let client = try makeClient(Self.slowServer)
        defer { client.stop() }
        _ = try client.request(method: "initialize", params: [:], timeout: 10)
        let start = Date()
        XCTAssertThrowsError(try client.request(method: "account/rateLimits/read", params: [:], timeout: 0.5)) { error in
            XCTAssertEqual(JSONRPCClient.usageError(from: error), .rpcFailed(.timedOut(method: "account/rateLimits/read")))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "timeout must be honoured, not waited out to the child's delay")
    }

    func testChildExitFailsPendingRequestInsteadOfHanging() throws {
        let client = try makeClient(Self.exitServer)
        let exited = expectation(description: "child exits")
        client.onExit = { _ in exited.fulfill() }
        // The fixture exits on its own; wait for the notification instead of a fixed sleep,
        // which is racy when the machine is loaded.
        wait(for: [exited], timeout: 10)
        XCTAssertFalse(client.isRunning)
        XCTAssertThrowsError(try client.request(method: "account/rateLimits/read", params: [:], timeout: 5))
        client.stop()
    }

    func testMalformedChildOutputYieldsRPCFailedNotCrash() throws {
        let client = try makeClient(Self.garbageServer)
        defer { client.stop() }
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertThrowsError(try client.request(method: "account/rateLimits/read", params: [:], timeout: 2))
    }

    func testStopTerminatesOwnedChildAndReapsIt() throws {
        let client = try makeClient(Self.silentServer)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(client.isRunning)
        let pid = client.childProcessIdentifier
        XCTAssertGreaterThan(pid, 0)
        client.stop()
        XCTAssertFalse(client.isRunning)
        XCTAssertEqual(client.childProcessIdentifier, -1)
        Thread.sleep(forTimeInterval: 0.3)
        // The reaped PID must no longer be alive; kill(2) with signal 0 probes only.
        XCTAssertEqual(kill(pid, 0), -1, "child process \(pid) should have been terminated and reaped")
        XCTAssertEqual(errno, ESRCH)
    }

    // MARK: - Child environment (1.3.0 profile isolation)

    /// The environment passed to the transport is the environment the child runs under. The
    /// fixture reports back the `CODEX_HOME` it observed, so this is the child's own view of
    /// its environment rather than the parent's bookkeeping.
    func testChildReceivesTheConfiguredEnvironmentOverride() throws {
        let codexHome = "/tmp/minget-test-home-a"
        let client = JSONRPCClient(executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                                   arguments: ["-c", Self.environmentEchoServer],
                                   environment: UsageService.childEnvironment(base: ["PATH": "/usr/bin"],
                                                                              codexHome: URL(fileURLWithPath: codexHome)))
        try client.start()
        defer { client.stop() }

        let response = try client.request(method: "initialize", params: [:], timeout: 10)
        XCTAssertEqual(response.resultObject?["codexHome"] as? String, codexHome,
                       "the child must observe the CODEX_HOME it was launched with")
    }

    /// Two profiles must reach two different children with two different isolated homes.
    /// The values are compared as strings; neither is logged anywhere.
    func testTwoTransportsReceiveDifferentCodexHomes() throws {
        func makeClient(home: String) throws -> JSONRPCClient {
            let client = JSONRPCClient(executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                                       arguments: ["-c", Self.environmentEchoServer],
                                       environment: UsageService.childEnvironment(base: ["PATH": "/usr/bin"],
                                                                                  codexHome: URL(fileURLWithPath: home)))
            try client.start()
            return client
        }

        let a = try makeClient(home: "/tmp/minget-test-home-a")
        let b = try makeClient(home: "/tmp/minget-test-home-b")
        defer { a.stop(); b.stop() }

        let homeA = try a.request(method: "initialize", params: [:], timeout: 10).resultObject?["codexHome"] as? String
        let homeB = try b.request(method: "initialize", params: [:], timeout: 10).resultObject?["codexHome"] as? String
        XCTAssertEqual(homeA, "/tmp/minget-test-home-a")
        XCTAssertEqual(homeB, "/tmp/minget-test-home-b")
        XCTAssertNotEqual(homeA, homeB, "the two account children must not share a CODEX_HOME")
        XCTAssertNotEqual(a.childEnvironment?["CODEX_HOME"], b.childEnvironment?["CODEX_HOME"])
    }
}

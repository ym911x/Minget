import XCTest
import Darwin
@testable import UsageMonitorCore

final class AntigravityCLIProcessTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let executable: URL

        init(_ body: String) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("minget-agy-process-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for name in ["home", "appdata", "work"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(name),
                                                        withIntermediateDirectories: false)
            }
            executable = root.appendingPathComponent("fixture.sh")
            try ("#!/bin/sh\n" + body + "\n").write(to: executable, atomically: true, encoding: .utf8)
            XCTAssertEqual(chmod(executable.path, 0o700), 0)
        }

        func runner(timeout: TimeInterval = 2) -> AntigravityCLIProcess {
            AntigravityCLIProcess(executable: executable,
                home: root.appendingPathComponent("home"),
                appData: root.appendingPathComponent("appdata"),
                workingDirectory: root.appendingPathComponent("work"), timeout: timeout, sandboxed: false)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private let validJSON = """
    {"status":"SUCCESS","num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"groups":[{"name":"Synthetic","buckets":[{"id":"weekly","window":"weekly","remaining_fraction":0.25}]}]}}}
    """

    func testFixedArgumentsIsolatedEnvironmentAndParsedReport() throws {
        let fixture = try Fixture("""
        test "$(basename "$HOME")" = home || exit 7
        test "$ANTIGRAVITY_APP_DATA_DIR" = "$(dirname "$HOME")/appdata" || exit 8
        test "$(basename "$(pwd)")" = work || exit 9
        test "$1" = "--log-file" && test "$2" = "/dev/null" || exit 10
        test "$3" = "--print" && test "$4" = "/usage" || exit 11
        test "$5" = "--output-format" && test "$6" = "json" || exit 12
        echo 'synthetic diagnostic' >&2
        echo '\(validJSON)'
        """)
        defer { fixture.remove() }
        let result = try fixture.runner(timeout: 5).run()
        XCTAssertEqual(result.groups.first?.buckets.first?.remainingFraction, 0.25)
        XCTAssertTrue(result.stderrWasPresent)
    }

    func testNonZeroExitCannotPublishAValidLookingReport() throws {
        let fixture = try Fixture("echo '\(validJSON)'\nexit 3")
        defer { fixture.remove() }
        XCTAssertThrowsError(try fixture.runner().run()) { error in
            XCTAssertEqual(error as? AntigravityCLIProcess.Failure, .nonZeroExit)
        }
    }

    func testTotalTimeoutCoversWaitingBeforeAnyReport() throws {
        let fixture = try Fixture("sleep 5")
        defer { fixture.remove() }
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try fixture.runner(timeout: 0.15).run()) { error in
            XCTAssertEqual(error as? AntigravityCLIProcess.Failure, .timedOut)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
    }

    func testOutputLimitAndCancellation() throws {
        let fixture = try Fixture("/usr/bin/yes x | /usr/bin/head -c 1100000")
        defer { fixture.remove() }
        XCTAssertThrowsError(try fixture.runner().run()) { error in
            XCTAssertEqual(error as? AntigravityCLIProcess.Failure, .outputTooLarge)
        }
        XCTAssertThrowsError(try fixture.runner().run(isCancelled: { true })) { error in
            XCTAssertEqual(error as? AntigravityCLIProcess.Failure, .cancelled)
        }
    }

    func testRejectsMissingDirectories() throws {
        let fixture = try Fixture("exit 0")
        defer { fixture.remove() }
        let runner = AntigravityCLIProcess(executable: fixture.executable,
            home: fixture.root.appendingPathComponent("missing"),
            appData: fixture.root.appendingPathComponent("appdata"),
            workingDirectory: fixture.root.appendingPathComponent("work"))
        XCTAssertThrowsError(try runner.run()) { error in
            XCTAssertEqual(error as? AntigravityCLIProcess.Failure, .invalidEnvironment)
        }
    }

    func testAuthenticationWaitIsStoppedBeforeTotalTimeout() throws {
        let fixture = try Fixture("echo 'Authentication required.' >&2\nsleep 5")
        defer { fixture.remove() }
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try fixture.runner(timeout: 3).run()) {
            XCTAssertEqual($0 as? AntigravityCLIProcess.Failure, .authenticationRequired)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
    }
}

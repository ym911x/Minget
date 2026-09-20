import XCTest
@testable import UsageMonitorCore

final class CommandCodeFireServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minget-commandcode-fire-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    private func executable(named name: String, script: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testArgumentsAreFixedMinimalAndDisableAutoUpdate() {
        XCTAssertEqual(CommandCodeFireService.arguments(),
                       ["--no-auto-update", "--no-session", "--no-skills", "--skip-onboarding",
                        "--permission-mode", "plan", "--max-turns", "1",
                        "--model", "deepseek/deepseek-v4-flash",
                        "--print", "Reply exactly: OK"])
        let joined = CommandCodeFireService.arguments().joined(separator: " ")
        XCTAssertFalse(joined.contains("/bin/sh"))
        XCTAssertFalse(joined.contains("/bin/zsh"))
        XCTAssertFalse(joined.contains("--yolo"))
    }

    func testSuccessfulFireUsesOnlyTheCommandCodeKeyAndDiscardsOutput() throws {
        let record = directory.appendingPathComponent("record.json")
        // The service intentionally strips arbitrary inherited variables. Give the fake the
        // record path through a fixed executable literal instead of widening production env.
        let literalCLI = try executable(named: "command-code-record", script: """
        #!/usr/bin/env python3
        import json, os, sys
        open("\(record.path)", "w").write(json.dumps({
          "argv": sys.argv[1:], "key": os.environ.get("COMMAND_CODE_API_KEY"),
          "skip": os.environ.get("COMMANDCODE_SKIP_UPDATES"),
          "track": os.environ.get("DO_NOT_TRACK"), "foreign": os.environ.get("OPENAI_API_KEY"),
          "cwd": os.getcwd(), "home": os.path.realpath(os.environ.get("HOME"))
        }))
        print("discard me")
        """)
        let isolated = CommandCodeFireService(locator: { _ in literalCLI },
                                              environment: ["PATH": "/usr/bin:/bin",
                                                            "HOME": directory.path,
                                                            "OPENAI_API_KEY": "must-not-leak"],
                                              workingDirectoryBase: directory)
        XCTAssertEqual(isolated.fire(apiKey: "cc-synthetic-key"), .requestSucceeded)

        let data = try Data(contentsOf: record)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["key"] as? String, "cc-synthetic-key")
        XCTAssertEqual(payload["skip"] as? String, "1")
        XCTAssertEqual(payload["track"] as? String, "1")
        XCTAssertTrue(payload["foreign"] is NSNull)
        XCTAssertEqual(payload["argv"] as? [String], CommandCodeFireService.arguments())
        let cwd = try XCTUnwrap(payload["cwd"] as? String)
        XCTAssertTrue(URL(fileURLWithPath: cwd).lastPathComponent.hasPrefix("minget-commandcode-fire-"))
        let home = try XCTUnwrap(payload["home"] as? String)
        XCTAssertEqual(URL(fileURLWithPath: home).resolvingSymlinksInPath(),
                       URL(fileURLWithPath: cwd).resolvingSymlinksInPath(),
                       "the fire child must not read the user's Command Code auth or settings")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwd),
                       "the isolated CLI home must be removed after the request")
    }

    func testMissingCredentialAndMissingCLIAreSeparate() {
        let service = CommandCodeFireService(locator: { _ in throw CommandCodeFireProcessOutcome.commandCodeCLINotFound },
                                             environment: [:], workingDirectoryBase: directory)
        XCTAssertEqual(service.fire(apiKey: ""), .credentialUnavailable)
        XCTAssertEqual(service.fire(apiKey: "synthetic"), .commandCodeCLINotFound)
    }

    func testNonZeroExitIsFixedFailure() throws {
        let cli = try executable(named: "command-code-fail", script: "#!/bin/sh\nexit 7\n")
        let service = CommandCodeFireService(locator: { _ in cli }, environment: ["PATH": "/usr/bin:/bin"],
                                             workingDirectoryBase: directory)
        XCTAssertEqual(service.fire(apiKey: "synthetic"), .nonZeroExit)
    }

    func testOfficialMaxTurnsExitMeansTheSingleRequestRan() throws {
        let cli = try executable(named: "command-code-max-turns", script: "#!/bin/sh\nexit 8\n")
        let service = CommandCodeFireService(locator: { _ in cli }, environment: ["PATH": "/usr/bin:/bin"],
                                             workingDirectoryBase: directory)
        XCTAssertEqual(CommandCodeFireService.maxTurnsReachedExitStatus, 8)
        XCTAssertEqual(service.fire(apiKey: "synthetic"), .requestSucceeded)
    }

    func testSparseGUIPathCanResolveNodeBesideTheLocatedCLI() throws {
        let bin = directory.appendingPathComponent("homebrew-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let node = bin.appendingPathComponent("node")
        try "#!/bin/sh\nexit 8\n".write(to: node, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let cli = bin.appendingPathComponent("command-code")
        try "#!/usr/bin/env node\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let service = CommandCodeFireService(locator: { _ in cli },
                                             environment: ["PATH": "/usr/bin:/bin"],
                                             workingDirectoryBase: directory)
        XCTAssertEqual(service.fire(apiKey: "synthetic"), .requestSucceeded,
                       "Finder's sparse PATH must still launch the CLI's env-node shebang")
    }

    func testTimeoutTerminatesOnlyOwnedChild() throws {
        let pidFile = directory.appendingPathComponent("pid")
        let cli = try executable(named: "command-code-hang", script: """
        #!/bin/sh
        trap '' TERM
        echo $$ > '\(pidFile.path)'
        while true; do :; done
        """)
        let service = CommandCodeFireService(locator: { _ in cli }, environment: ["PATH": "/usr/bin:/bin"],
                                             timeout: 1.5, terminateGrace: 0.2,
                                             workingDirectoryBase: directory)
        XCTAssertEqual(service.fire(apiKey: "synthetic"), .timedOut)
        let pidText = try String(contentsOf: pidFile)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = pid_t(try XCTUnwrap(Int(pidText)))
        XCTAssertNotEqual(kill(pid, 0), 0)
    }

    func testStopTerminatesTheOwnedChild() throws {
        let pidFile = directory.appendingPathComponent("stop-pid")
        let cli = try executable(named: "command-code-stop", script: """
        #!/usr/bin/env python3
        import os, time
        open("\(pidFile.path)", "w").write(str(os.getpid()))
        time.sleep(30)
        """)
        let service = CommandCodeFireService(locator: { _ in cli },
                                             environment: ["PATH": "/usr/bin:/bin"],
                                             timeout: 30, terminateGrace: 0.2,
                                             workingDirectoryBase: directory)
        let finished = expectation(description: "fire child reaped")
        DispatchQueue.global().async {
            _ = service.fire(apiKey: "synthetic")
            finished.fulfill()
        }
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: pidFile.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let pid = pid_t(try XCTUnwrap(Int(String(contentsOf: pidFile))))
        service.stop(terminateGrace: 0.2)
        wait(for: [finished], timeout: 3)
        XCTAssertNotEqual(kill(pid, 0), 0)
    }

    func testStopWhileLocatorIsPendingPreventsALateLaunch() throws {
        let marker = directory.appendingPathComponent("must-not-launch")
        let cli = try executable(named: "command-code-late", script: "#!/bin/sh\ntouch '\(marker.path)'\n")
        let locatorStarted = DispatchSemaphore(value: 0)
        let releaseLocator = DispatchSemaphore(value: 0)
        let service = CommandCodeFireService(locator: { _ in
            locatorStarted.signal()
            releaseLocator.wait()
            return cli
        }, environment: ["PATH": "/usr/bin:/bin"], workingDirectoryBase: directory)

        let finished = expectation(description: "pending fire exits without launching")
        DispatchQueue.global().async {
            XCTAssertEqual(service.fire(apiKey: "synthetic"), .launchFailed)
            finished.fulfill()
        }
        XCTAssertEqual(locatorStarted.wait(timeout: .now() + 2), .success)
        service.stop()
        releaseLocator.signal()
        wait(for: [finished], timeout: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testLocatorIncludesHomebrewAndHonoursOverride() throws {
        XCTAssertTrue(CommandCodeLocator.candidatePaths(environment: [:]).contains("/opt/homebrew/bin/command-code"))
        let cli = try executable(named: "custom-command-code", script: "#!/bin/sh\nexit 0\n")
        XCTAssertEqual(try CommandCodeLocator().locate(environment: ["USAGE_MONITOR_COMMAND_CODE_PATH": cli.path]), cli)
    }
}

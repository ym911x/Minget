import XCTest
@testable import UsageMonitorCore

/// Manual fire requests (REQUIREMENTS.md §7, IMPLEMENTATION_TASKS.md §6.1).
///
/// Every test uses a temporary fake executable. No real Codex CLI, no model request, and no
/// quota is ever consumed by this suite.
final class ChatGPTFireServiceTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minget-fire-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// Writes a fixed-literal executable. The shebang makes it a single launchable file, so
    /// the service can exec it directly exactly as it would exec the real CLI.
    private func writeExecutable(named name: String, script: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func path(_ name: String) -> String {
        directory.appendingPathComponent(name).path
    }

    /// Records its own PID and the environment/argv it was launched with, then exits 0.
    private var successScript: String {
        """
        #!/usr/bin/env python3
        import os, sys, json
        open(os.environ["MINGET_FIRE_PID"], "w").write(str(os.getpid()))
        open(os.environ["MINGET_FIRE_RECORD"], "w").write(json.dumps({
            "codexHome": os.environ.get("CODEX_HOME", ""),
            "argv": sys.argv[1:],
            "cwd": os.getcwd(),
        }))
        sys.exit(0)
        """
    }

    private var nonZeroScript: String {
        """
        #!/usr/bin/env python3
        import os, sys
        open(os.environ["MINGET_FIRE_PID"], "w").write(str(os.getpid()))
        open(os.environ["MINGET_FIRE_RECORD"], "w").write("ran")
        sys.exit(3)
        """
    }

    /// Sleeps far longer than the test timeout and ignores SIGTERM, so the service must
    /// escalate to SIGKILL on its own PID.
    private var hangScript: String {
        """
        #!/usr/bin/env python3
        import os, signal, sys, time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        open(os.environ["MINGET_FIRE_PID"], "w").write(str(os.getpid()))
        time.sleep(120)
        """
    }

    /// Waits for a release file to appear, then exits 0. Used to prove that two profiles run
    /// at the same time: neither can finish before the test releases them.
    private var waitingScript: String {
        """
        #!/usr/bin/env python3
        import os, sys, time
        open(os.environ["MINGET_FIRE_STARTED"], "a").write(str(os.getpid()) + "\\n")
        release = os.environ["MINGET_FIRE_RELEASE"]
        for _ in range(600):
            if os.path.exists(release):
                break
            time.sleep(0.05)
        sys.exit(0)
        """
    }

    private func environment(started: String? = nil, release: String? = nil) -> [String: String] {
        var env = [
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "MINGET_FIRE_PID": path("pid.txt"),
            "MINGET_FIRE_RECORD": path("record.json"),
        ]
        if let started { env["MINGET_FIRE_STARTED"] = started }
        if let release { env["MINGET_FIRE_RELEASE"] = release }
        return env
    }

    private let profileA = ChatGPTAccountProfile.chatGPTA
    private let profileB = ChatGPTAccountProfile.chatGPTB

    private func service(executable: URL?, timeout: TimeInterval = 5,
                         terminateGrace: TimeInterval = 2,
                         environment env: [String: String]? = nil) -> ChatGPTFireService {
        let resolved = executable
        return ChatGPTFireService(locator: { _ in
            guard let resolved else { throw UsageError.codexCLINotFound(searchedPaths: ["fake"]) }
            return resolved
        },
                                  environment: env ?? environment(),
                                  timeout: timeout,
                                  terminateGrace: terminateGrace,
                                  workingDirectoryBase: directory)
    }

    private func readRecord() throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("record.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Command boundary

    func testArgumentsAreTheFixedVerifiedList() {
        let workdir = URL(fileURLWithPath: "/tmp/minget-fire")
        XCTAssertEqual(ChatGPTFireService.arguments(workingDirectory: workdir),
                       ["exec",
                        "--ephemeral",
                        "--sandbox", "read-only",
                        "--skip-git-repo-check",
                        "-C", "/tmp/minget-fire",
                        "-m", "gpt-5.6-luna",
                        "-c", "model_reasoning_effort=\"none\"",
                        "Reply exactly: OK"])
        // The CLI is exec'd by URL: no interpreter, no script, no string-built command.
        let arguments = ChatGPTFireService.arguments(workingDirectory: workdir)
        XCTAssertEqual(arguments.first, "exec")
        let joined = arguments.joined(separator: " ")
        XCTAssertFalse(joined.contains("/bin/sh"))
        XCTAssertFalse(joined.contains("/bin/zsh"))
        XCTAssertFalse(joined.contains("bash"))
        XCTAssertFalse(joined.contains("minget-fire a"))
        XCTAssertFalse(joined.contains("fire-all"))
        // The temporary working directory is the only filesystem path in the argument list.
        let paths = arguments.filter { $0.hasPrefix("/") }
        XCTAssertEqual(paths, ["/tmp/minget-fire"])
    }

    func testMissingCLIIsReportedAndNoProcessStarts() {
        let fire = service(executable: nil)
        XCTAssertEqual(fire.fire(profile: profileA), .codexCLINotFound)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("record.json")))
    }

    // MARK: - Outcomes

    func testSuccessfulRequestReportsSuccess() throws {
        let executable = try writeExecutable(named: "codex-ok", script: successScript)
        let fire = service(executable: executable)

        XCTAssertEqual(fire.fire(profile: profileA), .requestSucceeded)

        let record = try readRecord()
        XCTAssertEqual((record["argv"] as? [String])?.first, "exec")
        XCTAssertTrue(((record["cwd"] as? String) ?? "").hasSuffix("/minget-fire"),
                      "the working directory must be the dedicated minget-fire directory")
        XCTAssertTrue(((record["codexHome"] as? String) ?? "").hasSuffix("/.codex-minget-a"),
                      "account A's child must run under account A's CODEX_HOME")
    }

    func testEachProfilePassesItsOwnCodexHomeToTheChild() throws {
        let executable = try writeExecutable(named: "codex-ok", script: successScript)
        let fire = service(executable: executable)

        XCTAssertEqual(fire.fire(profile: profileA), .requestSucceeded)
        let homeA = try XCTUnwrap(readRecord()["codexHome"] as? String)

        XCTAssertEqual(fire.fire(profile: profileB), .requestSucceeded)
        let homeB = try XCTUnwrap(readRecord()["codexHome"] as? String)

        XCTAssertNotEqual(homeA, homeB)
        XCTAssertTrue(homeA.hasSuffix("/.codex-minget-a"))
        XCTAssertTrue(homeB.hasSuffix("/.codex-minget-b"))
    }

    func testNonZeroExitIsReportedAsAFailure() throws {
        let executable = try writeExecutable(named: "codex-fail", script: nonZeroScript)
        let fire = service(executable: executable)
        XCTAssertEqual(fire.fire(profile: profileA), .nonZeroExit)
    }

    func testTimeoutTerminatesTheChildAndReportsTimeout() throws {
        let executable = try writeExecutable(named: "codex-hang", script: hangScript)
        let fire = service(executable: executable, timeout: 0.5, terminateGrace: 1)

        XCTAssertEqual(fire.fire(profile: profileA), .timedOut)

        let pidText = try String(contentsOf: directory.appendingPathComponent("pid.txt"), encoding: .utf8)
        let pid = try XCTUnwrap(pid_t(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        // SIGTERM was ignored by the fixture, so only the bounded SIGKILL escalation can have
        // removed it. Give the kernel a moment to finish reaping.
        var gone = false
        for _ in 0..<40 {
            if kill(pid, 0) == -1 && errno == ESRCH { gone = true; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(gone, "the timed-out child \(pid) must be terminated and reaped")
    }

    // MARK: - Duplicate clicks and parallel profiles

    func testASecondRequestForTheSameProfileReturnsAlreadyRunning() throws {
        let started = path("started.txt")
        let release = path("release.txt")
        let executable = try writeExecutable(named: "codex-wait", script: waitingScript)
        let fire = service(executable: executable, timeout: 30,
                           environment: environment(started: started, release: release))

        let finished = expectation(description: "first fire finishes")
        DispatchQueue.global().async {
            XCTAssertEqual(fire.fire(profile: self.profileA), .requestSucceeded)
            finished.fulfill()
        }

        XCTAssertTrue(waitForFile(started), "the first fire never started")
        // The same profile must be refused immediately: not queued, not merged.
        XCTAssertEqual(fire.fire(profile: profileA), .alreadyRunning)
        XCTAssertTrue(fire.isRunning(profileID: profileA.id))

        FileManager.default.createFile(atPath: release, contents: Data())
        wait(for: [finished], timeout: 10)
        XCTAssertFalse(fire.isRunning(profileID: profileA.id))
    }

    func testTwoProfilesCanFireAtTheSameTime() throws {
        let started = path("started.txt")
        let release = path("release.txt")
        let executable = try writeExecutable(named: "codex-wait", script: waitingScript)
        let fire = service(executable: executable, timeout: 30,
                           environment: environment(started: started, release: release))

        let both = expectation(description: "both fires finish")
        both.expectedFulfillmentCount = 2
        DispatchQueue.global().async {
            XCTAssertEqual(fire.fire(profile: self.profileA), .requestSucceeded)
            both.fulfill()
        }
        DispatchQueue.global().async {
            XCTAssertEqual(fire.fire(profile: self.profileB), .requestSucceeded)
            both.fulfill()
        }

        // Both children must be running before either is released; a serialising service
        // would leave only one start marker behind.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, startCount(started) < 2 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(startCount(started), 2, "A and B must be able to fire in parallel")

        FileManager.default.createFile(atPath: release, contents: Data())
        wait(for: [both], timeout: 15)
        XCTAssertFalse(fire.isRunning(profileID: profileA.id))
        XCTAssertFalse(fire.isRunning(profileID: profileB.id))
    }

    // MARK: - stopAll (REVISION_SPEC.md §9.1)

    /// A fire runs a blocking `Process.waitUntilExit()`, so app exit has to terminate the
    /// child explicitly. Both profiles' children must be reaped, not just the one that
    /// happened to be observed.
    func testStopAllTerminatesEveryRunningFireChild() throws {
        let started = path("started.txt")
        let release = path("release.txt")
        let executable = try writeExecutable(named: "codex-wait", script: waitingScript)
        let fire = service(executable: executable, timeout: 60,
                           environment: environment(started: started, release: release))

        let done = expectation(description: "both fires return")
        done.expectedFulfillmentCount = 2
        DispatchQueue.global().async {
            _ = fire.fire(profile: self.profileA)
            done.fulfill()
        }
        DispatchQueue.global().async {
            _ = fire.fire(profile: self.profileB)
            done.fulfill()
        }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, startCount(started) < 2 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(startCount(started), 2, "both fire children must be running")
        let pids = runningPIDs(started)
        XCTAssertEqual(pids.count, 2)

        // The app-exit moment. The release file is deliberately never created, so only an
        // explicit terminate can end these children.
        fire.stopAll(terminateGrace: 2)

        wait(for: [done], timeout: 15)
        for pid in pids {
            XCTAssertTrue(pidIsGone(pid), "fire child \(pid) survived stopAll()")
        }
        XCTAssertFalse(fire.isRunning(profileID: profileA.id))
        XCTAssertFalse(fire.isRunning(profileID: profileB.id))
    }

    func testStopAllIsIdempotentAndSafeWithNothingRunning() throws {
        let executable = try writeExecutable(named: "codex-ok", script: successScript)
        let fire = service(executable: executable)

        fire.stopAll()
        fire.stopAll()
        XCTAssertFalse(fire.isRunning(profileID: profileA.id))

        // A child that already exited on its own must not make stopAll misbehave.
        XCTAssertEqual(fire.fire(profile: profileA), .requestSucceeded)
        fire.stopAll()
        fire.stopAll()
        XCTAssertFalse(fire.isRunning(profileID: profileA.id))
    }

    /// `stopAll()` must only signal the children it owns, so an unrelated process that happens
    /// to be alive keeps running.
    func testStopAllLeavesUnrelatedProcessesAlone() throws {
        let bystander = Process()
        bystander.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        bystander.arguments = ["-c", "import time\nfor _ in range(300): time.sleep(0.1)"]
        try bystander.run()
        defer { if bystander.isRunning { bystander.terminate() }; bystander.waitUntilExit() }

        let executable = try writeExecutable(named: "codex-ok", script: successScript)
        let fire = service(executable: executable)
        fire.stopAll()

        XCTAssertTrue(bystander.isRunning, "an unrelated PID must not be terminated")
    }

    private func runningPIDs(_ path: String) -> [pid_t] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func pidIsGone(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == -1 && errno == ESRCH
    }

    // MARK: - Helpers

    private func waitForFile(_ path: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return FileManager.default.fileExists(atPath: path)
    }

    private func startCount(_ path: String) -> Int {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
    }
}

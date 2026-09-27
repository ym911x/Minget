import XCTest
import Darwin
@testable import UsageMonitorCore

final class CodexLaunchTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("minget-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func script(_ name: String, _ body: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
    private let sparse = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    func testOfficialLayoutsAndNativePriority() {
        let paths = CodexLocator.candidatePaths(environment: sparse)
        for app in ["ChatGPT", "Codex"] {
            for base in ["/Applications", "~/Applications"] {
                XCTAssertTrue(paths.contains("\(base)/\(app).app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
                XCTAssertTrue(paths.contains("\(base)/\(app).app/Contents/Resources/codex"))
            }
        }
        XCTAssertLessThan(paths.firstIndex(of: "/Applications/Codex.app/Contents/Resources/codex")!, paths.firstIndex(of: "/opt/homebrew/bin/codex")!)
    }
    func testNativeStartsWithFinderEnvironmentAndPreservesProfile() throws {
        let cli = try script("Codex.app/Contents/Resources/codex", "#!/bin/sh\nexit 0\n")
        var env = sparse; env["CODEX_HOME"] = root.appendingPathComponent("profile-a").path
        let launch = try CodexLocator().resolve(environment: env, candidatePaths: [cli.path])
        XCTAssertEqual(launch.executableURL, cli)
        XCTAssertEqual(launch.argumentPrefix, [])
        XCTAssertEqual(launch.environment, env)
    }
    func testNodeWrapperUsesAbsoluteNodeAndResolvedEntry() throws {
        let entry = try script("package/codex.js", "#!/usr/bin/env node\n// synthetic entry\n")
        let link = root.appendingPathComponent("bin/codex")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: entry)
        let node = try script("bin/node", "#!/bin/sh\n[ \"$2\" = '--version' ]\n")
        var env = sparse; env["CODEX_HOME"] = "synthetic-profile"
        let launch = try CodexLocator().resolve(environment: env, candidatePaths: [link.path], nodePaths: [node.path])
        XCTAssertEqual(launch.executableURL, node)
        XCTAssertEqual(launch.argumentPrefix, [entry.path])
        XCTAssertEqual(launch.environment["CODEX_HOME"], "synthetic-profile")
        XCTAssertTrue(launch.environment["PATH"]!.hasPrefix(node.deletingLastPathComponent().path))
    }
    func testNodeMissingHasSpecificCategory() throws {
        let cli = try script("codex", "#!/usr/bin/env node\n")
        XCTAssertThrowsError(try CodexLocator().resolve(environment: sparse, candidatePaths: [cli.path], nodePaths: [])) {
            XCTAssertEqual($0 as? UsageError, .codexNodeUnavailable)
        }
    }
    func testMissingCLIDoesNotConsultHostInstallations() {
        XCTAssertThrowsError(try CodexLocator().resolve(environment: sparse, candidatePaths: [root.appendingPathComponent("absent").path])) {
            guard case UsageError.codexCLINotFound = $0 else { return XCTFail("wrong category") }
        }
    }
    func testBrokenCandidateFallsBackButOverrideDoesNot() throws {
        let bad = try script("bad", "#!/bin/sh\nexit 7\n")
        let good = try script("good", "#!/bin/sh\nexit 0\n")
        XCTAssertEqual(try CodexLocator().resolve(environment: sparse, candidatePaths: [bad.path, good.path]).executableURL, good)
        var env = sparse; env["USAGE_MONITOR_CODEX_PATH"] = bad.path
        XCTAssertThrowsError(try CodexLocator().resolve(environment: env, candidatePaths: [good.path])) {
            XCTAssertEqual($0 as? UsageError, .appServerStartupFailed(.launchFailed))
        }
    }
    func testProbeTimeoutReapsOwnedProcess() throws {
        let pidFile = root.appendingPathComponent("pid")
        let cli = try script("hang", "#!/bin/sh\necho $$ > \"$PID_RECORD\"\nexec /bin/sleep 60\n")
        var env = sparse; env["PID_RECORD"] = pidFile.path
        let before = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try CodexLocator().resolve(environment: env, candidatePaths: [cli.path], probeTimeout: 1))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - before, 4)
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }
    func testNewResolutionSeesReplacedInstallation() throws {
        let first = try script("first", "#!/bin/sh\nexit 0\n")
        let second = try script("second", "#!/bin/sh\nexit 0\n")
        let locator = CodexLocator()
        XCTAssertEqual(try locator.resolve(environment: sparse, candidatePaths: [first.path, second.path]).executableURL, first)
        try FileManager.default.removeItem(at: first)
        XCTAssertEqual(try locator.resolve(environment: sparse, candidatePaths: [first.path, second.path]).executableURL, second)
    }
    func testFireUsesLaunchPrefixAndSeparateProfileEnvironments() throws {
        let record = root.appendingPathComponent("record")
        let node = try script("node", "#!/bin/sh\nprintf '%s\\n' \"$CODEX_HOME\" \"$1\" \"$2\" >> \"$RECORD\"\nexit 0\n")
        var env = sparse; env["RECORD"] = record.path
        let fire = ChatGPTFireService(launchResolver: { child in
            CodexLaunch(executableURL: node, argumentPrefix: ["synthetic-entry.js"], environment: child)
        }, environment: env, workingDirectoryBase: root)
        XCTAssertEqual(fire.fire(profile: .chatGPTA), .requestSucceeded)
        XCTAssertEqual(fire.fire(profile: .chatGPTB), .requestSucceeded)
        let rows = try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(rows, [ChatGPTAccountProfile.chatGPTA.codexHomeURL().path, "synthetic-entry.js", "exec",
                              ChatGPTAccountProfile.chatGPTB.codexHomeURL().path, "synthetic-entry.js", "exec"])
    }
    func testMissingNodeRecoversThroughManualRefreshWithSameService() throws {
        let cli = try script("codex.js", """
        #!/usr/bin/env node
        import json, sys
        if "--version" in sys.argv:
            sys.exit(0)
        for line in sys.stdin:
            req = json.loads(line)
            if "id" not in req:
                continue
            result = {}
            if req["method"] == "account/rateLimits/read":
                result = {"rateLimits": {"primary": {"usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1900000000}}}
            print(json.dumps({"id": req["id"], "result": result}), flush=True)
        """)
        let nodePath = root.appendingPathComponent("node").path
        let env = sparse
        let suite = "Minget.LaunchRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = UsageService(factory: {
            let launch = try CodexLocator().resolve(environment: env, candidatePaths: [cli.path], nodePaths: [nodePath])
            return CodexAppServerClient(transport: JSONRPCClient(executableURL: launch.executableURL,
                arguments: launch.argumentPrefix + ["app-server"], environment: launch.environment))
        }, cache: UsageCache(userDefaults: defaults), restartDelay: 0)
        defer { service.stop() }
        XCTAssertThrowsError(try service.fetch()) { XCTAssertEqual($0 as? UsageError, .codexNodeUnavailable) }
        _ = try script("node", "#!/bin/sh\nexec /usr/bin/python3 \"$@\"\n")
        let recovered = try service.fetch(resetFailureBudget: true)
        XCTAssertTrue(recovered.isLive)
        XCTAssertEqual(recovered.snapshot.fiveHour?.remainingPercent, 90)
    }

    func testProbeTimeoutAlsoKillsWrapperDescendant() throws {
        let childRecord = root.appendingPathComponent("child-pid")
        let cli = try script("wrapper", """
        #!/usr/bin/python3
        import os, subprocess, time
        child = subprocess.Popen(["/bin/sleep", "60"])
        with open(os.environ["CHILD_RECORD"], "w") as f:
            f.write(str(child.pid))
        time.sleep(60)
        """)
        var env = sparse; env["CHILD_RECORD"] = childRecord.path
        XCTAssertThrowsError(try CodexLocator().resolve(environment: env, candidatePaths: [cli.path], probeTimeout: 1))
        let childPID = try String(contentsOf: childRecord, encoding: .utf8)
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", childPID, "-o", "stat="]
        let pipe = Pipe(); ps.standardOutput = pipe; ps.standardError = FileHandle.nullDevice
        try ps.run(); ps.waitUntilExit()
        let status = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(status.isEmpty || status.hasPrefix("Z"), "wrapper descendant must no longer be running")
    }

}

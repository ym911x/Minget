import Foundation
import Darwin

/// A bounded, OS-restricted, read-only `/usage` invocation.
public struct AntigravityCLIProcess: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case invalidEnvironment
        case launchFailed
        case nonZeroExit
        case timedOut
        case cancelled
        case outputTooLarge
        case invalidReport
        case authenticationRequired
        case rateLimited(retryAfter: TimeInterval?)
    }

    public struct Output: Sendable {
        public let groups: [AntigravityQuotaGroup]
        public let stderrWasPresent: Bool
    }

    public static let arguments = [
        "--log-file", "/dev/null", "--print", "/usage",
        "--output-format", "json", "--print-timeout", "20s"
    ]
    public static let maximumBytes = 1_048_576

    public let executable: URL
    public let home: URL
    public let appData: URL
    public let workingDirectory: URL
    public let timeout: TimeInterval
    private let sandboxed: Bool

    public init(executable: URL, home: URL, appData: URL, workingDirectory: URL,
                timeout: TimeInterval = 30, sandboxed: Bool = true) {
        self.executable = executable
        self.home = home
        self.appData = appData
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.sandboxed = sandboxed
    }

    public func run(isCancelled: () -> Bool = { false }) throws -> Output {
        guard !isCancelled() else { throw Failure.cancelled }
        guard executable.isFileURL, home.isFileURL, appData.isFileURL,
              workingDirectory.isFileURL,
              [home, appData, workingDirectory].allSatisfy({
                  var isDirectory: ObjCBool = false
                  return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
              }) else { throw Failure.invalidEnvironment }
        if sandboxed {
            guard home.resolvingSymlinksInPath().path == home.path,
                  appData.resolvingSymlinksInPath().path == appData.path,
                  workingDirectory.resolvingSymlinksInPath().path == workingDirectory.path,
                  appData.path == home.appendingPathComponent("appdata").path,
                  workingDirectory.path == home.appendingPathComponent("workspace").path else { throw Failure.invalidEnvironment }
            try AntigravityCLILocator.validate(executable)
        }

        var outFD: [Int32] = [0, 0]
        var errFD: [Int32] = [0, 0]
        guard pipe(&outFD) == 0 else { throw Failure.launchFailed }
        guard pipe(&errFD) == 0 else {
            close(outFD[0]); close(outFD[1]); throw Failure.launchFailed
        }
        defer { close(outFD[0]); close(outFD[1]); close(errFD[0]); close(errFD[1]) }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw Failure.launchFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw Failure.launchFailed }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, outFD[1], STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, errFD[1], STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&actions, outFD[0]) == 0,
              posix_spawn_file_actions_addclose(&actions, errFD[0]) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path) == 0 else {
            throw Failure.launchFailed
        }

        let restricted = AntigravityCLIEnvironment(executable: executable, home: home)
        // Login prepares the profile. Reads never recreate a disconnected directory.
        let launchPath = sandboxed ? "/usr/bin/sandbox-exec" : executable.path
        let args = (sandboxed ? restricted.arguments(Self.arguments) : [executable.path] + Self.arguments).map { strdup($0) }
        let environmentStrings = restricted.environment(interactive: false).filter { !$0.hasPrefix("ANTIGRAVITY_APP_DATA_DIR=") } + ["ANTIGRAVITY_APP_DATA_DIR=\(appData.path)"]
        let env = environmentStrings.map { strdup($0) }
        defer { (args + env).forEach { free($0) } }
        var argv = args + [nil]
        var envp = env + [nil]
        var pid: pid_t = 0
        guard !isCancelled() else { throw Failure.cancelled }
        let launched = argv.withUnsafeMutableBufferPointer { a in
            envp.withUnsafeMutableBufferPointer { e in
                posix_spawn(&pid, launchPath, &actions, &attributes, a.baseAddress!, e.baseAddress!)
            }
        }
        guard launched == 0 else { throw Failure.launchFailed }
        close(outFD[1]); outFD[1] = -1
        close(errFD[1]); errFD[1] = -1
        _ = fcntl(outFD[0], F_SETFL, O_NONBLOCK)
        _ = fcntl(errFD[0], F_SETFL, O_NONBLOCK)

        var stdout = Data()
        var stderr = Data()
        var status: Int32 = 0
        var exited = false
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.01, timeout)
        defer {
            // The sandbox forbids forks. Only our own process group is addressed.
            _ = kill(-pid, SIGKILL)
            if !exited { while waitpid(pid, &status, 0) == -1 && errno == EINTR {} }
        }
        while true {
            if isCancelled() { throw Failure.cancelled }
            if ProcessInfo.processInfo.systemUptime >= deadline { throw Failure.timedOut }
            Self.drain(outFD[0], into: &stdout)
            Self.drain(errFD[0], into: &stderr)
            if String(decoding: stderr, as: UTF8.self).contains("Authentication required.") {
                throw Failure.authenticationRequired
            }
            if stdout.count > Self.maximumBytes || stderr.count > Self.maximumBytes {
                throw Failure.outputTooLarge
            }
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid {
                exited = true
                Self.drain(outFD[0], into: &stdout)
                Self.drain(errFD[0], into: &stderr)
                break
            }
            if waited == -1 && errno != EINTR { throw Failure.launchFailed }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard stdout.count <= Self.maximumBytes, stderr.count <= Self.maximumBytes else {
            throw Failure.outputTooLarge
        }
        if String(decoding: stderr, as: UTF8.self).contains("Authentication required.") { throw Failure.authenticationRequired }
        if let failure = Self.reportFailure(stdout) { throw failure }
        guard status == 0 else { throw Failure.nonZeroExit }
        guard let groups = try? AntigravityCLIReport.parse(stdout) else { throw Failure.invalidReport }
        return Output(groups: groups, stderrWasPresent: !stderr.isEmpty)
    }

    /// CLI 1.2.13 documents a string error, not an HTTP header or retry duration.
    /// Recognize an explicit HTTP 429 only; never infer limits from quota values.
    static func reportFailure(_ data: Data) -> Failure? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["status"] as? String == "ERROR", let error = root["error"] as? String else { return nil }
        if error.range(of: "(?i)(?:http|status(?: code)?)[ :=]+429\\b", options: .regularExpression) != nil {
            return .rateLimited(retryAfter: nil)
        }
        return nil
    }

    private static func drain(_ fd: Int32, into data: inout Data) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 { data.append(contentsOf: buffer.prefix(count)) }
            else if count == -1 && errno == EINTR { continue }
            else { break }
            if data.count > maximumBytes { break }
        }
    }
}

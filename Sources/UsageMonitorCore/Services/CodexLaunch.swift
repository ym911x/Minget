import Foundation
import Darwin

/// Shared invocation for quota reads and authorized fire requests. No shell is used.
public struct CodexLaunch: Sendable {
    public let executableURL: URL
    public let argumentPrefix: [String]
    public let environment: [String: String]

    public init(executableURL: URL, argumentPrefix: [String] = [], environment: [String: String]) {
        self.executableURL = executableURL
        self.argumentPrefix = argumentPrefix
        self.environment = environment
    }

    /// Resolve Node entry points without depending on Finder's sparse PATH.
    static func prepare(_ cli: URL, environment: [String: String], nodePaths: [String]? = nil,
                        fileManager: FileManager = .default) throws -> CodexLaunch {
        let resolved = cli.resolvingSymlinksInPath()
        let handle = try? FileHandle(forReadingFrom: resolved)
        let prefix = handle.flatMap { try? $0.read(upToCount: 256) } ?? Data()
        try? handle?.close()
        let line = String(data: prefix, encoding: .utf8)?.components(separatedBy: "\n").first ?? ""
        let isNode = line.hasPrefix("#!") && line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .contains(where: { $0 == "node" || $0.hasSuffix("/node") })
        guard isNode else { return CodexLaunch(executableURL: cli, environment: environment) }
        var candidates = nodePaths ?? [cli.deletingLastPathComponent().appendingPathComponent("node").path,
                                      resolved.deletingLastPathComponent().appendingPathComponent("node").path,
                                      "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        if nodePaths == nil {
            candidates += (environment["PATH"] ?? "").split(separator: ":")
                .filter { $0.hasPrefix("/") }.map { String($0) + "/node" }
        }
        guard let node = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw UsageError.codexNodeUnavailable
        }
        var child = environment
        let entries = [URL(fileURLWithPath: node).deletingLastPathComponent().path,
                       cli.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                       "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        child["PATH"] = entries.filter { $0.hasPrefix("/") && seen.insert($0).inserted }.joined(separator: ":")
        return CodexLaunch(executableURL: URL(fileURLWithPath: node),
                           argumentPrefix: [resolved.path], environment: child)
    }

    /// A private process group bounds the probe and any wrapper descendants. Output is
    /// discarded, and only successful termination is retained; no upstream text is logged.
    func probe(timeout: TimeInterval) -> Bool {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return false }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return false }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else { return false }
        for fd in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            guard posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", O_RDWR, 0) == 0 else { return false }
        }
        let args = ([executableURL.path] + argumentPrefix + ["--version"]).map { strdup($0) }
        let env = environment.map { strdup("\($0.key)=\($0.value)") }
        defer { (args + env).forEach { free($0) } }
        var argv = args + [nil]
        var envp = env + [nil]
        var pid: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { ap in
            envp.withUnsafeMutableBufferPointer { ep in
                posix_spawn(&pid, executableURL.path, &actions, &attributes, ap.baseAddress!, ep.baseAddress!)
            }
        }
        guard result == 0 else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.01, timeout)
        var status: Int32 = 0
        while ProcessInfo.processInfo.systemUptime < deadline {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid {
                kill(-pid, SIGKILL) // also retire any descendants left by a wrapper
                return status == 0
            }
            if waited == -1 && errno != EINTR { kill(-pid, SIGKILL); return false }
            Thread.sleep(forTimeInterval: 0.01)
        }
        kill(-pid, SIGKILL)
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        return false
    }
}

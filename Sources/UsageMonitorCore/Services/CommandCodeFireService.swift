import Foundation

/// Fixed, redacted lifecycle result for one Command Code fire child.
public enum CommandCodeFireProcessOutcome: Error, Equatable, Sendable {
    case requestSucceeded
    case credentialUnavailable
    case commandCodeCLINotFound
    case launchFailed
    case nonZeroExit
    case timedOut
    case alreadyRunning

    public var immediateResult: ChatGPTFireResult? {
        switch self {
        case .requestSucceeded: return nil
        case .credentialUnavailable: return .credentialUnavailable
        case .commandCodeCLINotFound: return .commandCodeCLINotFound
        case .launchFailed: return .launchFailed
        case .nonZeroExit: return .nonZeroExit
        case .timedOut: return .timedOut
        case .alreadyRunning: return .alreadyRunning
        }
    }
}

/// Starts Command Code's rolling window with one minimal request through the official CLI.
///
/// The user explicitly authorised this use of the app-stored Key for 1.3.2. The service:
/// - launches the CLI directly, never through a shell;
/// - disables auto-update, sessions and skills and allows at most one model turn;
/// - supplies the Key only in the child environment and never logs or persists it;
/// - drains and discards stdout/stderr;
/// - owns and terminates the exact child PID on timeout or app shutdown.
public final class CommandCodeFireService: @unchecked Sendable {
    /// The single model used by the in-app manual/scheduled fire path. Keep this in one
    /// place so the UI path and its tests cannot drift from the external launchd helper.
    public static let modelName = "deepseek/deepseek-v4.1-flash"
    public static let prompt = "Reply exactly: OK"
    public static let targetID = "commandcode"
    public static let defaultTimeout: TimeInterval = 120
    public static let defaultTerminateGrace: TimeInterval = 3
    /// Command Code print mode returns 8 when the configured turn cap is reached, even when
    /// that capped turn produced a final model response. With our fixed `--max-turns 1`, this
    /// still proves the one request needed to start a rolling window was sent.
    public static let maxTurnsReachedExitStatus: Int32 = 8

    public static func arguments(model: String = modelName) -> [String] {
        ["--no-auto-update",
         "--no-session",
         "--no-skills",
         "--skip-onboarding",
         "--permission-mode", "plan",
         "--max-turns", "1",
         "--model", model,
         "--print", prompt]
    }

    public typealias Locator = ([String: String]) throws -> URL

    private let locator: Locator
    private let environment: [String: String]
    private let timeout: TimeInterval
    private let terminateGrace: TimeInterval
    private let workingDirectoryBase: URL?
    private let model: String
    private let fileManager: FileManager

    private let lock = NSLock()
    private var running = false
    private var stopped = false
    private var activeProcess: Process?

    public init(locator: @escaping Locator = { environment in
                    try CommandCodeLocator().locate(environment: environment)
                },
                environment: [String: String] = ProcessInfo.processInfo.environment,
                timeout: TimeInterval = defaultTimeout,
                terminateGrace: TimeInterval = defaultTerminateGrace,
                workingDirectoryBase: URL? = nil,
                model: String = modelName,
                fileManager: FileManager = .default) {
        self.locator = locator
        self.environment = environment
        self.timeout = timeout
        self.terminateGrace = terminateGrace
        self.workingDirectoryBase = workingDirectoryBase
        self.model = model
        self.fileManager = fileManager
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    public func fire(apiKey: String) -> CommandCodeFireProcessOutcome {
        guard !apiKey.isEmpty else { return .credentialUnavailable }

        lock.lock()
        if stopped {
            lock.unlock()
            return .launchFailed
        }
        guard !running else {
            lock.unlock()
            return .alreadyRunning
        }
        running = true
        lock.unlock()
        defer {
            lock.lock()
            running = false
            activeProcess = nil
            lock.unlock()
        }

        let executable: URL
        do { executable = try locator(environment) }
        catch {
            Diagnostics.log("commandcode fire: CLI unavailable")
            return .commandCodeCLINotFound
        }

        let workingDirectory: URL
        do { workingDirectory = try prepareWorkingDirectory() }
        catch {
            Diagnostics.log("commandcode fire: working directory unavailable")
            return .launchFailed
        }
        defer { try? fileManager.removeItem(at: workingDirectory) }

        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(model: model)
        process.currentDirectoryURL = workingDirectory
        process.environment = childEnvironment(apiKey: apiKey,
                                               isolatedHome: workingDirectory,
                                               executable: executable)
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        Self.drainDiscarding(stdoutPipe.fileHandleForReading)
        Self.drainDiscarding(stderrPipe.fileHandleForReading)

        // Publish and launch while holding the same lock used by stop(). If shutdown won
        // while the locator or temporary HOME was being prepared, no child may start. If
        // launch wins, stop() waits for run() to return and then sees the live owned PID.
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return .launchFailed
        }
        activeProcess = process
        do { try process.run() }
        catch {
            lock.unlock()
            Diagnostics.log("commandcode fire: launch failed")
            return .launchFailed
        }
        lock.unlock()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            terminate(process, grace: terminateGrace)
            Diagnostics.log("commandcode fire: timed out")
            return .timedOut
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
            || process.terminationStatus == Self.maxTurnsReachedExitStatus
            ? .requestSucceeded
            : .nonZeroExit
    }

    public func stop(terminateGrace: TimeInterval? = nil) {
        lock.lock()
        stopped = true
        let process = activeProcess
        lock.unlock()
        guard let process, process.isRunning else { return }
        terminate(process, grace: terminateGrace ?? self.terminateGrace)
    }

    private func childEnvironment(apiKey: String,
                                  isolatedHome: URL,
                                  executable: URL) -> [String: String] {
        var child: [String: String] = [:]
        for key in ["USER", "TMPDIR", "LANG", "LC_ALL"] {
            if let value = environment[key], !value.isEmpty { child[key] = value }
        }
        // The official CLI is a `#!/usr/bin/env node` script. Finder-launched apps commonly
        // receive `/usr/bin:/bin` only, even though the locator can find Command Code at its
        // explicit Homebrew path. Put the located CLI directory and common Node locations
        // ahead of the inherited path so `env` can resolve the runtime without a shell.
        child["PATH"] = Self.runtimePath(executable: executable,
                                         inheritedPath: environment["PATH"])
        // The Key supplied below is sufficient for the authorised request. An isolated HOME
        // prevents the official CLI from consulting user-level auth or settings files.
        child["HOME"] = isolatedHome.resolvingSymlinksInPath().path
        child["COMMAND_CODE_API_KEY"] = apiKey
        child["COMMANDCODE_SKIP_UPDATES"] = "1"
        child["DO_NOT_TRACK"] = "1"
        child["COMMANDCODE_SCRATCHPAD_BASE"] = isolatedHome
            .appendingPathComponent("scratch", isDirectory: true).path
        return child
    }

    private static func runtimePath(executable: URL, inheritedPath: String?) -> String {
        var entries = [executable.deletingLastPathComponent().path,
                       "/opt/homebrew/bin",
                       "/usr/local/bin"]
        if let inheritedPath, !inheritedPath.isEmpty {
            entries.append(contentsOf: inheritedPath.split(separator: ":").map(String.init))
        }
        entries.append(contentsOf: ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])

        var seen = Set<String>()
        return entries.filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }

    private func prepareWorkingDirectory() throws -> URL {
        let base = workingDirectoryBase
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent(
            "minget-commandcode-fire-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func terminate(_ process: Process, grace: TimeInterval) {
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(grace)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning, process.processIdentifier > 0 {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func drainDiscarding(_ handle: FileHandle) {
        handle.readabilityHandler = { readable in
            if readable.availableData.isEmpty { readable.readabilityHandler = nil }
        }
    }
}

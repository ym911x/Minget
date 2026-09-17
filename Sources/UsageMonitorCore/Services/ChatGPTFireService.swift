import Foundation

/// Runs one real "5-hour window" request per ChatGPT profile by launching the official Codex
/// CLI directly (REQUIREMENTS.md §7.1).
///
/// Boundaries this type exists to enforce:
/// - the executable is located with `CodexLocator` and started through `Process.executableURL`:
///   no shell, no string concatenation, no `minget-fire`;
/// - the argument list is the fixed, verified one, so nothing user-supplied can reach the CLI;
/// - the child's `CODEX_HOME` is the profile's isolated directory. The directory's *contents*
///   are never read, listed, parsed or copied: they are passed as an environment value and
///   nothing else;
/// - stdout and stderr are drained and discarded. They are never written to a log, never
///   returned to the UI and never persisted — the previous external script recorded full CLI
///   output including the session id, which is exactly why the app does not reuse it;
/// - one fire per profile at a time; a second request returns `.alreadyRunning` immediately
///   rather than queueing, while two different profiles may run in parallel.
public final class ChatGPTFireService: @unchecked Sendable {

    /// Fixed argument list, minus the pieces that depend on the run.
    ///
    /// `model_reasoning_effort="none"` keeps its quotes: the external script let the shell
    /// strip them, and argv must carry the literal the CLI expects.
    public static let modelName = "gpt-5.6-luna"
    public static let prompt = "Reply exactly: OK"
    public static let defaultTimeout: TimeInterval = 120
    public static let defaultTerminateGrace: TimeInterval = 3

    public static func arguments(workingDirectory: URL, model: String = ChatGPTFireService.modelName) -> [String] {
        ["exec",
         "--ephemeral",
         "--sandbox", "read-only",
         "--skip-git-repo-check",
         "-C", workingDirectory.path,
         "-m", model,
         "-c", "model_reasoning_effort=\"none\"",
         prompt]
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
    private var runningProfiles: Set<String> = []
    private var activeProcesses: [String: Process] = [:]

    public init(locator: @escaping Locator = { environment in
                    try CodexLocator().locate(environment: environment)
                },
                environment: [String: String] = ProcessInfo.processInfo.environment,
                timeout: TimeInterval = ChatGPTFireService.defaultTimeout,
                terminateGrace: TimeInterval = ChatGPTFireService.defaultTerminateGrace,
                workingDirectoryBase: URL? = nil,
                model: String = ChatGPTFireService.modelName,
                fileManager: FileManager = .default) {
        self.locator = locator
        self.environment = environment
        self.timeout = timeout
        self.terminateGrace = terminateGrace
        self.workingDirectoryBase = workingDirectoryBase
        self.model = model
        self.fileManager = fileManager
    }

    /// Whether a fire is in flight for this profile. Used by the UI to disable that button
    /// and by the service itself to answer `.alreadyRunning`.
    public func isRunning(profileID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return runningProfiles.contains(profileID)
    }

    /// Terminates every fire child still running and reaps it.
    ///
    /// `fire()` is a blocking `Process.waitUntilExit()` call, so cancelling the Swift task
    /// that called it does **not** reach the child: app exit has to stop these processes
    /// explicitly or a `codex exec` survives the app (REVISION_SPEC.md §9.1).
    ///
    /// The process list is copied under the lock and released before any waiting, so a
    /// concurrent natural exit, timeout or duplicate `stopAll()` cannot deadlock against it.
    /// Only each child's own PID is signalled.
    public func stopAll(terminateGrace: TimeInterval? = nil) {
        lock.lock()
        let processes = Array(activeProcesses.values)
        lock.unlock()

        let grace = terminateGrace ?? self.terminateGrace
        for process in processes {
            guard process.isRunning else { continue }
            process.terminate()
            let deadline = Date().addingTimeInterval(grace)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning, process.processIdentifier > 0 {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
    }

    /// Runs one fire request. Blocking up to `timeout + terminateGrace`; call off the main
    /// thread. Only the fixed categories below are ever reported.
    public func fire(profile: ChatGPTAccountProfile) -> ChatGPTFireProcessOutcome {
        lock.lock()
        guard !runningProfiles.contains(profile.id) else {
            lock.unlock()
            return .alreadyRunning
        }
        runningProfiles.insert(profile.id)
        lock.unlock()
        defer {
            lock.lock()
            runningProfiles.remove(profile.id)
            activeProcesses[profile.id] = nil
            lock.unlock()
        }

        let executable: URL
        do {
            executable = try locator(environment)
        } catch {
            Diagnostics.log("fire: codex CLI unavailable")
            return .codexCLINotFound
        }

        let workingDirectory: URL
        do {
            workingDirectory = try prepareWorkingDirectory()
        } catch {
            Diagnostics.log("fire: working directory unavailable")
            return .launchFailed
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(workingDirectory: workingDirectory, model: model)
        process.currentDirectoryURL = workingDirectory
        process.environment = UsageService.childEnvironment(base: environment,
                                                            codexHome: profile.codexHomeURL())
        process.standardInput = FileHandle.nullDevice

        // Drain and discard. A child that fills a pipe it is still writing to would block
        // forever, and the raw text must not be kept anywhere.
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        Self.drainDiscarding(stdoutPipe.fileHandleForReading)
        Self.drainDiscarding(stderrPipe.fileHandleForReading)

        lock.lock(); activeProcesses[profile.id] = process; lock.unlock()

        do {
            try process.run()
        } catch {
            Diagnostics.log("fire: launch failed")
            return .launchFailed
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            // Terminate our own child only, then escalate to SIGKILL on that same PID.
            process.terminate()
            let graceDeadline = Date().addingTimeInterval(terminateGrace)
            while process.isRunning && Date() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning, process.processIdentifier > 0 {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            Diagnostics.log("fire: timed out")
            return .timedOut
        }

        process.waitUntilExit()
        return process.terminationStatus == 0 ? .requestSucceeded : .nonZeroExit
    }

    /// `$TMPDIR/minget-fire`, created on demand. The CLI is given a working directory that is
    /// not the user's project, so `--skip-git-repo-check` has nothing to discover either way.
    private func prepareWorkingDirectory() throws -> URL {
        let base = workingDirectoryBase
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("minget-fire", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Reads and throws away everything the child writes, clearing the handler at EOF.
    private static func drainDiscarding(_ handle: FileHandle) {
        handle.readabilityHandler = { readable in
            if readable.availableData.isEmpty {
                readable.readabilityHandler = nil
            }
        }
    }
}

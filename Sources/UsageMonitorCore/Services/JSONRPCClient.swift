import Foundation

/// stdio JSON-RPC transport to a child process (`codex app-server`).
///
/// Contract (IMPLEMENTATION_PLAN.md):
/// - newline-delimited JSON on stdio, one child per application, reused for its lifetime,
/// - split reads, multiple messages per read and split UTF-8 sequences are handled,
/// - request IDs are routed concurrently, each request bounded by a timeout,
/// - stderr is drained and discarded (never logged raw) so the child cannot block,
/// - the child is terminated, killed after a grace period, and reaped exactly once,
/// - the executable is launched directly by URL: no shell interpolation of any kind,
/// - failures are reported as fixed categories; upstream message text never leaves this
///   type (Round 2 blocker 5).
public final class JSONRPCClient: @unchecked Sendable {

    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]?

    private var process: Process?
    private var stdinHandle: FileHandle?

    /// Serializes launch and shutdown. `stop()` therefore cannot observe a half-launched
    /// child: it waits for an in-progress `start()` to finish and then terminates the child,
    /// which closes the window where a parent could exit leaving a survivor behind
    /// (Round 3 blocker 2).
    private let launchLock = NSLock()

    // NSLock guards all mutable transport state. A plain lock is used deliberately:
    // a concurrent DispatchQueue with `sync(flags: .barrier)` did not provide the
    // exclusion this state needs, which showed up as replies that could not be routed
    // to their waiting request.
    private let stateLock = NSLock()
    private var nextRequestID = 0
    private var pending: [Int: PendingRequest] = [:]
    private var hasExited = false

    private struct PendingRequest {
        let semaphore: DispatchSemaphore
        let responseBox: ResponseBox
    }

    /// Thread-safe single-value box shared between the reader and the caller.
    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<JSONRPCResponse, Error>?
        func fulfill(_ result: Result<JSONRPCResponse, Error>) {
            lock.lock(); defer { lock.unlock() }
            if value == nil { value = result }
        }
        var current: Result<JSONRPCResponse, Error>? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    /// Notification messages (no id); surfaced for diagnostics, never logged raw.
    public var onNotification: (([String: Any]) -> Void)?
    /// Invoked once when the child terminates.
    public var onExit: ((Int32) -> Void)?

    public init(executableURL: URL, arguments: [String] = [], environment: [String: String]? = nil) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }

    // MARK: - Lifecycle

    /// Launches the child and starts the stdout reader. Throws on spawn failure.
    public func start() throws {
        launchLock.lock()
        defer { launchLock.unlock() }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            self.failPending(.rpcFailed(.transportClosed))
            self.stateLock.lock()
            self.hasExited = true
            self.stateLock.unlock()
            self.onExit?(terminatedProcess.terminationStatus)
        }

        // Publish before run(): a stop() racing the launch must be able to reach and
        // terminate the child instead of seeing nil and returning without cleanup.
        stateLock.lock()
        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        stateLock.unlock()

        do {
            try process.run()
        } catch {
            stateLock.withLock { self.process = nil }
            throw UsageError.appServerStartupFailed(.launchFailed)
        }

        // stdout: newline-delimited replies. `readabilityHandler` delivers each chunk as it
        // arrives on a Foundation-owned queue, so no manual reader thread is required.
        let stdoutRead = stdoutPipe.fileHandleForReading
        stdoutRead.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData  // empty at EOF
            guard let self else { return }
            if chunk.isEmpty {
                stdoutRead.readabilityHandler = nil
                self.failPending(.rpcFailed(.transportClosed))
                return
            }
            for message in self.framer.append(chunk) {
                self.dispatch(message)
            }
        }

        // stderr: drain and discard so the child can never block on a full pipe.
        let stderrRead = stderrPipe.fileHandleForReading
        stderrRead.readabilityHandler = { handle in
            if handle.availableData.isEmpty { stderrRead.readabilityHandler = nil }  // EOF
        }
    }

    /// Byte accumulator for stdout; only touched on the readabilityHandler queue.
    private var framer = MessageFramer()

    public var isRunning: Bool {
        stateLock.withLock {
            guard let process, !hasExited else { return false }
            return process.isRunning
        }
    }

    /// Process identifier of the owned child, or -1. Used for lifecycle reporting only.
    public var childProcessIdentifier: pid_t {
        stateLock.withLock { process?.processIdentifier ?? -1 }
    }

    /// Terminates the child: close stdin, wait briefly, SIGTERM, then SIGKILL, then reap.
    /// Blocks until any in-progress `start()` has finished, then returns only once the
    /// child is reaped, so the caller may exit immediately afterwards.
    public func stop(reapTimeout: TimeInterval = 3.0) {
        launchLock.lock()
        defer { launchLock.unlock() }

        let process: Process? = stateLock.withLock { self.process }
        guard let process else { return }

        // 1. Close our side of stdin: many servers exit cleanly on stdin EOF.
        let stdin: FileHandle? = stateLock.withLock { self.stdinHandle }
        try? stdin?.close()
        stateLock.withLock { self.stdinHandle = nil }

        // 2. Ask nicely, then escalate. Only our own child's PID is signalled.
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(reapTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning, process.processIdentifier > 0 {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()  // reaps the child; no shell involved
        _ = process.terminationStatus

        stateLock.withLock { self.process = nil }
    }

    // MARK: - Messaging

    /// Sends a notification (no id, no reply expected).
    public func sendNotification(method: String, params: [String: Any]? = nil) throws {
        var message: [String: Any] = ["method": method]
        if let params { message["params"] = params }
        try send(message)
    }

    /// Sends a request and waits up to `timeout` for its reply.
    public func request(method: String, params: [String: Any]? = nil, timeout: TimeInterval = 5.0) throws -> JSONRPCResponse {
        let id: Int = stateLock.withLock {
            nextRequestID += 1
            return nextRequestID
        }

        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }

        let box = ResponseBox()
        let request = PendingRequest(semaphore: DispatchSemaphore(value: 0), responseBox: box)
        let registered: Bool = stateLock.withLock {
            guard !hasExited else { return false }
            pending[id] = request
            return true
        }
        guard registered else {
            throw UsageError.rpcFailed(.transportClosed)
        }
        defer { stateLock.withLock { _ = pending.removeValue(forKey: id) } }

        try send(message)

        if request.semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw UsageError.rpcFailed(.timedOut(method: method))
        }
        switch box.current {
        case .success(let response):
            return response
        case .failure(let error):
            throw Self.usageError(from: error)
        case .none:
            throw UsageError.rpcFailed(.noReply(method: method))
        }
    }

    private func send(_ message: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else {
            throw UsageError.rpcFailed(.malformedResponse)
        }
        let handle: FileHandle? = stateLock.withLock { self.stdinHandle }
        guard let handle else { throw UsageError.rpcFailed(.transportClosed) }
        do {
            try handle.write(contentsOf: data + Data([0x0A]))
        } catch {
            throw UsageError.rpcFailed(.writeFailed)
        }
    }

    // MARK: - Reader

    private func dispatch(_ line: Data) {
        guard let object = MessageFramer.decodeObject(line) else { return }  // non-JSON noise
        guard let id = object["id"], object["result"] != nil || object["error"] != nil else {
            if object["method"] is String { onNotification?(object) }
            return
        }
        guard let idKey = Self.requestID(from: id) else { return }
        guard let request: PendingRequest = stateLock.withLock({ self.pending[idKey] }) else { return }
        let result: Result<JSONRPCResponse, Error>
        if let errorObject = object["error"] as? [String: Any] {
            // Only the numeric code survives into the error type; the message text does not.
            result = .failure(JSONRPCError(code: SafeConversion.errorCode(errorObject["code"]),
                                           message: (errorObject["message"] as? String) ?? ""))
        } else {
            result = .success(JSONRPCResponse(id: id, result: object["result"] as Any))
        }
        request.responseBox.fulfill(result)
        request.semaphore.signal()
    }

    private func failPending(_ error: UsageError) {
        let all: [PendingRequest] = stateLock.withLock {
            let values = Array(pending.values)
            pending.removeAll()
            return values
        }
        for request in all {
            request.responseBox.fulfill(.failure(error))
            request.semaphore.signal()
        }
    }

    // MARK: - Error mapping (fixed categories only)

    /// Converts a reply failure into a `UsageError`. The server's message text is used
    /// only to pick a category and is then dropped, so no upstream text can reach logs
    /// or UI through this path.
    public static func usageError(from error: Error) -> UsageError {
        if let usageError = error as? UsageError { return usageError }
        if let rpcError = error as? JSONRPCError {
            if rpcError.indicatesNotSignedIn { return .codexNotSignedIn }
            return .rpcFailed(.serverError(code: rpcError.code))
        }
        return .rpcFailed(.other)
    }

    static func requestID(from value: Any) -> Int? {
        if let number = value as? NSNumber, !SafeConversion.isBoxedBool(number) {
            return SafeConversion.integer(number)
        }
        if let text = value as? String { return SafeConversion.integer(text) }
        return nil
    }
}

import Foundation

/// Speaks the verified `codex app-server` protocol over the shared transport:
/// initialize -> initialized (notification) -> account/rateLimits/read.
///
/// The initialize result is discarded immediately: only normalized usage data is
/// ever kept (PROJECT_SPEC.md §14, IMPLEMENTATION_PLAN.md protocol evidence).
public protocol CodexAppServerProviding: AnyObject {
    func start() throws
    func handshake(timeout: TimeInterval) throws
    func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot
    func stop()
    var isTransportRunning: Bool { get }
    /// Process identifier of the owned child, or -1. Lifecycle reporting only.
    var childProcessIdentifier: pid_t { get }
    /// Identity of the signed-in account, or nil when it could not be established.
    /// Declared as a requirement so a conforming type's own implementation is the one
    /// dispatched (a protocol-extension default would silently shadow test stubs).
    func readAccount(timeout: TimeInterval) throws -> CodexAccount?
}

extension CodexAppServerProviding {
    public var childProcessIdentifier: pid_t { -1 }

    /// Default for stubs and older fakes: no account identity is available, so the panel
    /// shows 账号信息暂不可用 rather than guessing.
    public func readAccount(timeout: TimeInterval) throws -> CodexAccount? { return nil }
}

public final class CodexAppServerClient: CodexAppServerProviding {
    public static let rateLimitsMethod = "account/rateLimits/read"
    public static let accountMethod = "account/read"
    public static let defaultTimeout: TimeInterval = 5.0

    private let transport: JSONRPCClient
    private let clientName: String
    private let clientVersion: String
    private let parser = UsageParser()
    private var handshakeComplete = false
    private let handshakeLock = NSLock()

    public init(transport: JSONRPCClient, clientName: String = "UsageMonitor", clientVersion: String = "1.0.0") {
        self.transport = transport
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    public var isTransportRunning: Bool { transport.isRunning }
    public var childProcessIdentifier: pid_t { transport.childProcessIdentifier }
    public var onTransportExit: ((Int32) -> Void)? {
        get { transport.onExit }
        set { transport.onExit = newValue }
    }

    /// Launches the child process.
    public func start() throws {
        try transport.start()
    }

    /// Performs the initialize/initialized handshake. Idempotent per connection.
    public func handshake(timeout: TimeInterval = CodexAppServerClient.defaultTimeout) throws {
        handshakeLock.lock()
        if handshakeComplete {
            handshakeLock.unlock()
            return
        }
        handshakeLock.unlock()
        do {
            _ = try transport.request(
                method: "initialize",
                params: ["clientInfo": ["name": clientName, "version": clientVersion]],
                timeout: timeout
            )
            try transport.sendNotification(method: "initialized")
            handshakeLock.lock()
            handshakeComplete = true
            handshakeLock.unlock()
        } catch {
            throw JSONRPCClient.usageError(from: error)
        }
    }

    /// Reads the current account identity.
    ///
    /// `refreshToken: false` is passed explicitly so the call can never trigger a token
    /// refresh: the app reads the identity that is already established and does nothing
    /// else with it. Only the normalized identity survives; the response's auth material is
    /// never decoded, stored or logged.
    public func readAccount(timeout: TimeInterval = CodexAppServerClient.defaultTimeout) throws -> CodexAccount? {
        do {
            let response = try transport.request(method: Self.accountMethod,
                                                 params: ["refreshToken": false],
                                                 timeout: timeout)
            guard let result = response.resultObject else { return nil }
            return CodexAccountParser.parse(result: result)
        } catch {
            // Identity is supplementary: a failure here must not fail the usage read.
            throw JSONRPCClient.usageError(from: error)
        }
    }

    /// Reads the rate limit snapshot and normalizes it.
    public func readRateLimits(timeout: TimeInterval = CodexAppServerClient.defaultTimeout) throws -> UsageSnapshot {
        do {
            let response = try transport.request(method: Self.rateLimitsMethod, params: [:], timeout: timeout)
            guard let result = response.resultObject else {
                throw UsageError.rpcFailed(.invalidPayload(.noRateLimitWindows))
            }
            return try parser.parseSnapshot(result: result)
        } catch {
            throw JSONRPCClient.usageError(from: error)
        }
    }

    /// Ordered shutdown of the owned child process.
    public func stop() {
        transport.stop()
        handshakeLock.lock()
        handshakeComplete = false
        handshakeLock.unlock()
    }
}

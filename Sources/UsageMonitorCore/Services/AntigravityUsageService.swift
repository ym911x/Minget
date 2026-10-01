import Foundation

public protocol AntigravityUsageReading: Sendable {
    func read(connection: AntigravityConnection, home: URL) async throws -> AntigravitySnapshot
}

private final class AntigravityCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var started = false, finished = false
    private let joined = DispatchSemaphore(value: 0)
    func begin() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }; started = true; return true
    }
    func finish() { lock.lock(); finished = true; lock.unlock(); joined.signal() }
    func cancel() {
        lock.lock(); cancelled = true; let mustJoin = started && !finished; lock.unlock()
        // The worker never needs the main actor to kill/reap its child. App shutdown
        // can therefore wait here even while AppKit is waiting for termination.
        if mustJoin { _ = joined.wait(timeout: .now() + 2) }
    }
    func value() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

public struct AntigravityUsageService: AntigravityUsageReading {
    public init() {}
    public func read(connection: AntigravityConnection, home: URL) async throws -> AntigravitySnapshot {
        let cancellation = AntigravityCancellation()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    guard cancellation.begin() else { continuation.resume(throwing: CancellationError()); return }
                    defer { cancellation.finish() }
                    do {
                        let environment = AntigravityCLIEnvironment(executable: AntigravityCLILocator.executable, home: home)
                        guard !cancellation.value() else { throw CancellationError() }
                        // A committed profile must already exist. Never recreate one after disconnect.
                        guard FileManager.default.fileExists(atPath: home.path) else { throw AntigravityCLIProcess.Failure.invalidEnvironment }
                        let output = try AntigravityCLIProcess(executable: environment.executable, home: environment.home,
                            appData: environment.appData, workingDirectory: environment.workspace).run(isCancelled: cancellation.value)
                        continuation.resume(returning: AntigravitySnapshot(accountIdentity: connection.account.identity,
                            groups: output.groups, fetchedAt: Date()))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
}

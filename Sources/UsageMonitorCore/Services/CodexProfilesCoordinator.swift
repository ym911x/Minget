import Foundation

/// Owns the runtimes of every enabled ChatGPT profile and coordinates their refreshes and
/// shutdown (REQUIREMENTS.md §4.1, IMPLEMENTATION_TASKS.md §1.1).
///
/// The properties that matter for two accounts:
/// - one long-lived `UsageService` per profile, each with its own `codex app-server` child
///   launched under that profile's `CODEX_HOME`;
/// - refreshes run in parallel, so a hung or signed-out account cannot delay the other;
/// - each service keeps its own failure budget, because they are separate objects;
/// - `stop()` drains *all* profiles concurrently and returns only once every child has been
///   reaped, so the app can exit without leaving an orphan behind.
public final class CodexProfilesCoordinator: @unchecked Sendable {

    /// Builds the service for one profile. Injectable so tests can substitute a client
    /// factory, and so the production path is one explicit expression rather than a
    /// convention spread over several call sites.
    public typealias ServiceFactory = (ChatGPTAccountProfile) -> UsageService

    /// Enabled profiles, in the fixed display order (account A left, account B right).
    public let runtimes: [CodexProfileRuntime]

    private let byID: [String: CodexProfileRuntime]

    public init(profiles: [ChatGPTAccountProfile] = ChatGPTAccountProfile.defaults,
                makeService: @escaping ServiceFactory) {
        var runtimes: [CodexProfileRuntime] = []
        var byID: [String: CodexProfileRuntime] = [:]
        for profile in profiles {
            let runtime = CodexProfileRuntime(profile: profile, service: makeService(profile))
            runtimes.append(runtime)
            byID[profile.id] = runtime
        }
        self.runtimes = runtimes
        self.byID = byID
    }

    /// Production wiring: every profile gets its own service, its own resolved `CODEX_HOME`
    /// and its own profile-scoped cache namespace.
    public convenience init(profiles: [ChatGPTAccountProfile] = ChatGPTAccountProfile.defaults,
                            cache: UsageCache = UsageCache(),
                            environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(profiles: profiles) { profile in
            UsageService(cache: cache,
                         environment: environment,
                         codexHome: profile.codexHomeURL(),
                         profileID: profile.id)
        }
    }

    public var profileIDs: [String] { runtimes.map(\.profileID) }

    public func runtime(for profileID: String) -> CodexProfileRuntime? {
        byID[profileID]
    }

    /// The `CODEX_HOME` this profile's child will run with, resolved without launching
    /// anything. Used by the isolation tests; the value itself is never logged.
    public func resolvedCodexHome(for profileID: String,
                                  homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        byID[profileID]?.profile.codexHomeURL(homeDirectory: homeDirectory)
    }

    /// The full child environment this profile will be launched with.
    public func childEnvironment(for profileID: String,
                                 base: [String: String] = ProcessInfo.processInfo.environment,
                                 homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: String]? {
        guard let profile = byID[profileID]?.profile else { return nil }
        return UsageService.childEnvironment(base: base,
                                             codexHome: profile.codexHomeURL(homeDirectory: homeDirectory))
    }

    /// Refreshes one profile and records the outcome on its runtime. Blocking: callers run
    /// it off the main thread, and two profiles may run at the same time.
    @discardableResult
    public func fetch(profileID: String,
                      resetFailureBudget: Bool = false,
                      fetchTimeout: TimeInterval = CodexAppServerClient.defaultTimeout) -> Result<UsageService.FetchResult, Error> {
        guard let runtime = byID[profileID] else {
            return .failure(UsageError.rpcFailed(.other))
        }
        runtime.recordFetchStart()
        let outcome = Result {
            try runtime.service.fetch(resetFailureBudget: resetFailureBudget, fetchTimeout: fetchTimeout)
        }
        switch outcome {
        case .success(let result):
            runtime.recordFetchSuccess(result)
        case .failure(let error):
            runtime.recordFetchFailure((error as? UsageError) ?? .rpcFailed(.other))
        }
        return outcome
    }

    // MARK: - Fire state (owned by the view model, stored per runtime)

    public func recordFireStart(profileID: String) {
        byID[profileID]?.recordFireStart()
    }

    public func recordFireFinished(profileID: String, result: ChatGPTFireResult) {
        byID[profileID]?.recordFireFinished(result)
    }

    // MARK: - Shutdown

    /// Stops every profile's service concurrently and returns only after all of them have
    /// drained. Concurrent on purpose: two bounded drains running one after the other would
    /// double how long termination can take, and nothing about one profile's child depends
    /// on the other's.
    public func stop(shutdownTimeout: TimeInterval = 8.0) {
        let group = DispatchGroup()
        for runtime in runtimes {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                runtime.service.stop(shutdownTimeout: shutdownTimeout)
                group.leave()
            }
        }
        // The per-service drain is already bounded; this outer bound only guards against a
        // worker that never got scheduled.
        _ = group.wait(timeout: .now() + shutdownTimeout + 1)
        Diagnostics.log("codex profiles stopped (\(runtimes.count) profiles)")
    }
}

import Foundation

/// Resolves the `codex` CLI without spawning a shell (no PATH string interpolation).
///
/// Finder/launchd environments have a sparse PATH, so known install locations are
/// probed explicitly. `USAGE_MONITOR_CODEX_PATH` overrides everything for QA.
public struct CodexLocator: Sendable {
    public init() {}

    /// Legacy path-only API. Production consumers use resolve() so Node arguments and
    /// environment cannot be lost. Kept for callers that only inspect installation paths.
    public func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                       fileManager: FileManager = .default) throws -> URL {
        if let override = environment["USAGE_MONITOR_CODEX_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            if isUsableExecutable(url, fileManager: fileManager) { return url }
            throw UsageError.codexCLINotFound(searchedPaths: ["USAGE_MONITOR_CODEX_PATH=\(override)"])
        }

        var searched: [String] = []
        for candidate in Self.candidatePaths(environment: environment) {
            let expanded = (candidate as NSString).expandingTildeInPath
            searched.append(expanded)
            let url = URL(fileURLWithPath: expanded)
            if isUsableExecutable(url, fileManager: fileManager) { return url }
        }
        throw UsageError.codexCLINotFound(searchedPaths: searched)
    }

    /// Every newly created connection resolves and probes afresh; failures are local
    /// startup categories, never account or network failures.
    public func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        candidatePaths: [String]? = nil, nodePaths: [String]? = nil,
                        probeTimeout: TimeInterval = 2) throws -> CodexLaunch {
        let override = environment["USAGE_MONITOR_CODEX_PATH"].flatMap { $0.isEmpty ? nil : $0 }
        let paths = override.map { [$0] } ?? candidatePaths ?? Self.candidatePaths(environment: environment)
        var failure: UsageError = .codexCLINotFound(searchedPaths: paths)
        var seen = Set<String>()
        for path in paths {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard seen.insert(url.path).inserted,
                  isUsableExecutable(url, fileManager: .default) else { continue }
            do {
                let launch = try CodexLaunch.prepare(url, environment: environment, nodePaths: nodePaths)
                guard launch.probe(timeout: probeTimeout) else {
                    throw UsageError.appServerStartupFailed(.launchFailed)
                }
                return launch
            } catch let error as UsageError {
                failure = error
                if override != nil { throw error }
            }
        }
        throw failure
    }

    static func candidatePaths(environment: [String: String]) -> [String] {
        var paths: [String] = []
        var wrappers: [String] = []
        for root in ["/Applications", "~/Applications"] {
            for app in ["ChatGPT", "Codex"] {
                let resources = "\(root)/\(app).app/Contents/Resources"
                paths += ["\(resources)/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                          "\(resources)/codex"]
                wrappers.append("\(resources)/codex-cli/bin/codex")
            }
        }
        paths += wrappers
        paths += ["~/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"]
        if let pathEnv = environment["PATH"], !pathEnv.isEmpty {
            for entry in pathEnv.split(separator: ":") {
                paths.append("\(entry)/codex")
            }
        }
        return paths
    }

    private func isUsableExecutable(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return false }
        return fileManager.isExecutableFile(atPath: url.path)
    }
}

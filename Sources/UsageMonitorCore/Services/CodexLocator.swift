import Foundation

/// Resolves the `codex` CLI without spawning a shell (no PATH string interpolation).
///
/// Finder/launchd environments have a sparse PATH, so known install locations are
/// probed explicitly. `USAGE_MONITOR_CODEX_PATH` overrides everything for QA.
public struct CodexLocator: Sendable {
    public init() {}

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

    static func candidatePaths(environment: [String: String]) -> [String] {
        var paths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",  // observed install (IMPLEMENTATION_PLAN.md)
            "/Applications/Codex.app/Contents/Resources/codex",
            "~/Applications/ChatGPT.app/Contents/Resources/codex",
            "~/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ]
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

import Foundation

/// Resolves the official Command Code CLI without invoking a shell.
///
/// Finder-launched menu bar apps receive a sparse `PATH`, so the common Apple Silicon,
/// Intel Homebrew and user-local locations are checked explicitly. The override exists for
/// deterministic QA only and is never populated from a credential.
public struct CommandCodeLocator: Sendable {
    public init() {}

    public func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                       fileManager: FileManager = .default) throws -> URL {
        if let override = environment["USAGE_MONITOR_COMMAND_CODE_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            guard isUsableExecutable(url, fileManager: fileManager) else {
                throw CommandCodeFireProcessOutcome.commandCodeCLINotFound
            }
            return url
        }

        for candidate in Self.candidatePaths(environment: environment) {
            let url = URL(fileURLWithPath: (candidate as NSString).expandingTildeInPath)
            if isUsableExecutable(url, fileManager: fileManager) { return url }
        }
        throw CommandCodeFireProcessOutcome.commandCodeCLINotFound
    }

    static func candidatePaths(environment: [String: String]) -> [String] {
        var paths = [
            "/opt/homebrew/bin/command-code",
            "/usr/local/bin/command-code",
            "~/.local/bin/command-code",
            "/usr/bin/command-code",
        ]
        if let path = environment["PATH"], !path.isEmpty {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/command-code" })
        }
        return paths
    }

    private func isUsableExecutable(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return fileManager.isExecutableFile(atPath: url.path)
    }
}

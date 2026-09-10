import Foundation

/// Optional lifecycle diagnostics for QA.
///
/// Enabled only when `USAGE_MONITOR_LOG_FILE` points at a writable path; the app
/// writes nothing by default. Only lifecycle events are logged (PROJECT_SPEC.md §14):
/// messages are additionally scrubbed so that anything resembling a credential can
/// never reach the file, even by accident (Round 2 blocker 5).
public enum Diagnostics {
    private static let lock = NSLock()

    static var fileURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["USAGE_MONITOR_LOG_FILE"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    public static func log(_ message: String) {
        guard let fileURL else { return }
        let line = "\(Date()) [UsageMonitor] \(redact(message))\n"
        let data = Data(line.utf8)
        lock.lock(); defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Redaction

    /// Credential-bearing key names, matched case-insensitively with a word boundary so
    /// ordinary identifiers that merely contain them (e.g. `sessionConfigured`) survive.
    static let sensitiveKeyPatterns = [
        "authorization", "bearer", "access[_ -]?token", "refresh[_ -]?token", "id[_ -]?token",
        "api[_ -]?key", "openai-api-key", "session[_ -]?key", "cookie", "password", "secret",
    ]

    /// Long credential-shaped runs: hex, base64url/JWT segments, API-key shapes.
    static let credentialShapedRunPattern =
        "(?:[A-Fa-f0-9]{32,})"                                              // long hex
        + "|(?:[A-Za-z0-9_-]{24,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,})" // JWT-like
        + "|(?:eyJ[A-Za-z0-9_-]{16,})"                                      // JWT header prefix
        + "|(?:sk-[A-Za-z0-9_-]{16,})"                                      // API-key shaped

    /// Replaces credential-shaped content with `[redacted]`.
    /// Callers should already pass only fixed categories; this is the last line of defence.
    public static func redact(_ message: String) -> String {
        var output = message
        let range = NSRange(output.startIndex..., in: output)

        let keyAlternation = sensitiveKeyPatterns.joined(separator: "|")
        let pairPattern = "(?i)\\b(?:\(keyAlternation))\\b[^\\n]{0,120}"
        if let pairRegex = try? NSRegularExpression(pattern: pairPattern) {
            output = pairRegex.stringByReplacingMatches(in: output, range: range, withTemplate: "[redacted]")
        }

        if let runRange = NSRange(output.startIndex..., in: output) as NSRange?,
           let runRegex = try? NSRegularExpression(pattern: credentialShapedRunPattern) {
            output = runRegex.stringByReplacingMatches(in: output, range: runRange, withTemplate: "[redacted]")
        }
        return output
    }
}

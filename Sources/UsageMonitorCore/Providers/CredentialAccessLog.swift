import Foundation
import Security

/// Call-level evidence for credential access, written to the app's own log directory.
///
/// Why this exists: the lifecycle diagnostics in `Diagnostics` need an environment variable
/// to be set before launch, so they are useless for the ordinary way a user starts the app
/// (double-click or `open`). A keychain problem therefore had no call-level evidence at all.
/// This log can be switched on from inside the app and works on a normal launch
/// (KEYCHAIN_REVISION_PLAN.md P0.4 and P0.5).
///
/// What it records: build identity, executable path, process id, monotonic and wall clock,
/// the fixed credential code, the call's purpose, whether UI was allowed, the outcome
/// category, the raw `OSStatus` when there is one, and the duration.
///
/// What it never records: key material, session contents, fingerprints, request headers,
/// response bodies, or any user text. The outcome is written through
/// `CredentialAccessOutcome.code`, which cannot carry a value. The log also never guesses
/// which button the user pressed.
public enum CredentialAccessLog {

    /// App-owned preference. Off by default; the panel's diagnostics row flips it.
    public static let enabledDefaultsKey = "UsageMonitor.diagnostics.credentialAccess"

    private static let lock = NSLock()
    private static var cachedIdentity: String?

    /// Directory name inside Application Support. Local, never a cloud-synced location.
    static let directoryName = "Minget"
    static let fileName = "credential-access.log"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey) }
    }

    /// Records one access. Cheap no-op when disabled, so callers do not need to check.
    public static func record(key: ProviderCredentialKey,
                              purpose: CredentialAccessPurpose,
                              interaction: CredentialInteraction,
                              outcome: CredentialAccessOutcome,
                              elapsed: TimeInterval) {
        guard isEnabled, let fileURL = resolvedFileURL() else { return }
        let status = outcome.osStatus.map { "\($0)" } ?? "-"
        let line = [
            timestamp(),
            "uptime=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime))",
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "identity=\(identity())",
            "key=\(key.rawValue)",
            "purpose=\(purpose.rawValue)",
            "mode=\(interaction.rawValue)",
            "outcome=\(outcome.code)",
            "osstatus=\(status)",
            "ms=\(String(format: "%.1f", elapsed * 1000))",
        ].joined(separator: " ") + "\n"

        write(line, to: fileURL)
    }

    /// Records a note that is not an access: an enable/disable toggle, a reset. Fixed text
    /// only. Written regardless of the current switch state, so a log segment always shows
    /// when diagnostics were turned off as well as on.
    public static func note(_ fixedText: String) {
        guard let fileURL = resolvedFileURL() else { return }
        write("\(timestamp()) uptime=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime)) note=\(fixedText)\n",
              to: fileURL)
    }

    /// Where the log lives, for display in the panel. Nil when the directory cannot be
    /// resolved, which the panel reports instead of inventing a path.
    public static var logFileURL: URL? { resolvedFileURL() }

    // MARK: - Internals

    private static func resolvedFileURL() -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true) else { return nil }
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(fileName)
    }

    private static func write(_ text: String, to fileURL: URL) {
        let data = Data(text.utf8)
        lock.lock(); defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    /// Build identity: version plus the designated requirement the running binary is bound
    /// to. The requirement string is what decides keychain ACL matching, so it is the one
    /// piece of evidence worth having when authorisation behaves unexpectedly.
    /// Computed once; falls back to a fixed marker when the security framework cannot
    /// describe this process.
    private static func identity() -> String {
        lock.lock(); defer { lock.unlock() }
        if let cachedIdentity { return cachedIdentity }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let identifier = Bundle.main.bundleIdentifier ?? "unknown"
        let path = Bundle.main.executablePath ?? "unknown"
        let requirement = Self.designatedRequirement()
        let value = "version=\(version) bundle=\(identifier) exec=\(path) requirement=\(requirement)"
        cachedIdentity = value
        return value
    }

    static func designatedRequirement() -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return "unavailable" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return "unavailable"
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return "unavailable" }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return "unavailable" }
        return text as String
    }
}

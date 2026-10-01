import Foundation
import Security
import CryptoKit
import SystemConfiguration

/// The CLI owns everything below this home. Minget never opens its authentication files.
public struct AntigravityCLIEnvironment: Sendable {
    public let executable: URL
    public let home: URL
    public var appData: URL { home.appendingPathComponent("appdata", isDirectory: true) }
    public var workspace: URL { home.appendingPathComponent("workspace", isDirectory: true) }
    public var temporaryDirectory: URL { home.appendingPathComponent("tmp", isDirectory: true) }

    public init(executable: URL, home: URL) {
        self.executable = executable.resolvingSymlinksInPath()
        self.home = home.resolvingSymlinksInPath()
    }

    public func prepare() throws {
        for directory in [home, appData, workspace, temporaryDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    public func environment(interactive: Bool) -> [String] {
        let proxy = Self.systemProxyEnvironment()
        return ["HOME=\(home.path)", "ANTIGRAVITY_APP_DATA_DIR=\(appData.path)",
         "TMPDIR=\(temporaryDirectory.path)", "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
         "TERM=\(interactive ? "xterm-256color" : "dumb")", "LANG=en_US.UTF-8",
         "AGY_CLI_DISABLE_AUTO_UPDATE=true", "AGY_CLI_NONINTERACTIVE_HEADLESS=true"] + proxy
    }

    /// Read only macOS network proxy settings, without inheriting arbitrary shell secrets.
    public static func systemProxyEnvironment() -> [String] {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return [] }
        return [("HTTP", "HTTP_PROXY"), ("HTTPS", "HTTPS_PROXY")].compactMap { prefix, key in
            guard (settings[prefix + "Enable"] as? NSNumber)?.boolValue == true,
                  let host = settings[prefix + "Proxy"] as? String,
                  let port = settings[prefix + "Port"] as? Int, (1...65535).contains(port),
                  host.range(of: "^[a-zA-Z0-9.-]+$", options: .regularExpression) != nil else { return nil }
            return key + "=http://" + host + ":" + String(port)
        }
    }

    public var sandbox: String {
        // Paths are arguments in Seatbelt, never shell text. Resolve /tmp and home symlinks.
        func quoted(_ url: URL) -> String {
            "\"" + url.path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        // Security.framework needs file metadata to initialize its SSL policy.
        // Deny home file contents, retaining metadata access for system certificate checks.
        let userHome = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        return """
        (version 1)
        (allow default)
        (deny process-fork)
        (deny appleevent-send)
        (deny mach-lookup (global-name-regex "^com\\\\.apple\\\\.(lsd|coreservices\\\\.launchservices)"))
        (deny file-read-data (require-all (subpath \(quoted(userHome)))
          (require-not (subpath \(quoted(home)))) (require-not (literal \(quoted(executable))))))
        (deny file-write* (require-all (require-not (subpath \(quoted(home))))
          (require-not (literal "/dev/null"))))
        """
    }

    public func arguments(_ cliArguments: [String]) -> [String] {
        ["/usr/bin/sandbox-exec", "-p", sandbox, executable.path] + cliArguments
    }
}

public enum AntigravityCLILocator {
    public static let version = "1.2.13"
    // SHA-512 of the executable extracted from the previously verified official archive.
    public static let executableSHA512 = "461ec5dcced70332d6a2a9973028e8b22c2fd164c51ddb389a2e0728ac8bc06c8e63390b38ff3275ac828bb8dfb803d21f32cc3e332aad065ce6d985b258b207"
    public static var base: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Minget/AntigravityCLI", isDirectory: true)
    }
    public static var executable: URL { base.appendingPathComponent("bin/antigravity-\(version)") }

    public static func validate(_ url: URL = executable) throws {
        #if !arch(arm64)
        throw Failure.unsupportedArchitecture
        #else
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              SHA512.hash(data: data).map({ String(format: "%02x", $0) }).joined() == executableSHA512 else {
            throw Failure.missingOrIncompatible
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString("anchor apple generic and certificate leaf[subject.OU] = EQHXZ8M8AV" as CFString,
                                             [], &requirement) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw Failure.signatureInvalid
        }
        #endif
    }
    public enum Failure: Error { case unsupportedArchitecture, missingOrIncompatible, signatureInvalid }
}

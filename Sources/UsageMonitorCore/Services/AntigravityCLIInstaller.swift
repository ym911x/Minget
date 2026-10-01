import Foundation
import CryptoKit

/// User-initiated download of the pinned Google archive. No shell installer or global configuration.
public enum AntigravityCLIInstaller {
    private static let archiveURL = URL(string: "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.2.13-6662628811079680/darwin-arm/cli_mac_arm64.tar.gz")!
    private static let archiveSHA512 = "b36641b6d6e734da0907bc02a8d35c4a093a46bdec60b6f39ebccc6976fc3f80ae357211c1cf0373f9cae722f1a64aac77ff19f5fb485c9c97a7f2afcfcb7131"
    public enum Failure: Error { case response, checksum, extraction, cancelled }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    public static func install() async throws {
        #if !arch(arm64)
        throw AntigravityCLILocator.Failure.unsupportedArchitecture
        #else
        if (try? AntigravityCLILocator.validate()) != nil { return }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (download, response) = try await session.download(from: archiveURL)
        defer { try? FileManager.default.removeItem(at: download) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url == archiveURL else { throw Failure.response }
        try Task.checkCancellation()
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        guard data.count <= 300_000_000,
              SHA512.hash(data: data).map({ String(format: "%02x", $0) }).joined() == archiveSHA512 else { throw Failure.checksum }
        let base = AntigravityCLILocator.base.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard base.resolvingSymlinksInPath().path == base.path else { throw Failure.extraction }
        let staging = base.appendingPathComponent("download-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        // Only extract the expected archive member; never materialize arbitrary archive paths.
        try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", download.path, "-C", staging.path, "antigravity"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Failure.extraction }
            let executable = staging.appendingPathComponent("antigravity")
            guard executable.resolvingSymlinksInPath().path == executable.path else { throw Failure.extraction }
            try AntigravityCLILocator.validate(executable)
        }.value
        try Task.checkCancellation()
        let target = AntigravityCLILocator.executable
        let candidate = staging.appendingPathComponent("antigravity")
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: candidate)
        } else { try FileManager.default.moveItem(at: candidate, to: target) }
        try AntigravityCLILocator.validate()
        #endif
    }
}

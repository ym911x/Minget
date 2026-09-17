import XCTest
import AppKit
import CoreGraphics
import UsageMonitorCore
@testable import UsageMonitorApp

/// Cold start of the **signed** app, checked as a real process (REVISION_SPEC.md §11.1, §14).
///
/// The defect this pins was an empty SwiftUI `Settings` scene that macOS could open at launch.
/// An in-process test cannot see that, because the XCTest host is not our app, so this test
/// launches the installed bundle and looks at the windows it really owns.
///
/// Skipped when the signed bundle is not installed on this machine (CI) — the evidence is
/// recorded from a local run instead of being faked.
@MainActor
final class StartupWindowTests: XCTestCase {

    private static let appURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Applications/Minget.app")
    private static let executableURL = appURL.appendingPathComponent("Contents/MacOS/UsageMonitor")

    override func setUpWithError() throws {
        try super.setUpWithError()
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            throw XCTSkip("Launching the signed app requires a logged-in macOS session")
        }
        guard FileManager.default.isExecutableFile(atPath: Self.executableURL.path) else {
            throw XCTSkip("\(Self.executableURL.path) is not installed; build it with scripts/build.sh")
        }
    }

    // MARK: Cold start

    func testColdStartShowsNoWindowOtherThanTheDetailPage() throws {
        let app = try launch()
        defer { terminate(app) }

        // REVISION_SPEC.md §11.1: within two seconds of a cold start there must be no visible
        // empty window. Every window the app owns must therefore be the real detail page at
        // its fixed 440 pt width — an empty Settings scene can never look like that.
        Thread.sleep(forTimeInterval: 2.0)
        let windows = onScreenWindows(ownedBy: app.processIdentifier)
        for window in windows {
            XCTAssertEqual(window.width, DetailPageLayout.pageWidth,
                           "unexpected window \(window) at cold start; the only legal window is "
                           + "the 440 pt detail page")
            XCTAssertTrue(DetailPageLayout.pageHeight(showDeepSeek: false, showCommandCode: false) <= window.height,
                          "window \(window) is smaller than the shortest legal detail page")
        }
        XCTAssertTrue(app.isRunning, "the app must stay alive after launch")
    }

    func testQuitLeavesNoOwnedCodexChildBehind() throws {
        let app = try launch()
        let children = waitForChildren(of: app.processIdentifier, timeout: 10)
        terminate(app)

        for pid in children {
            var gone = false
            for _ in 0..<100 {
                if kill(pid, 0) == -1 && errno == ESRCH { gone = true; break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            XCTAssertTrue(gone, "child \(pid) outlived the app")
        }
    }

    // MARK: Process helpers

    private func launch() throws -> Process {
        let process = Process()
        process.executableURL = Self.executableURL
        // A distinct defaults domain would need a signed bundle change; the app only reads and
        // writes its own non-secret preferences, which this run leaves untouched.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning, process.processIdentifier > 0 {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private func waitForChildren(of pid: pid_t, timeout: TimeInterval) -> [pid_t] {
        let deadline = Date().addingTimeInterval(timeout)
        var children: [pid_t] = []
        while Date() < deadline {
            children = directChildren(of: pid)
            if !children.isEmpty { return children }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return children
    }

    private func directChildren(of pid: pid_t) -> [pid_t] {
        guard let output = run("/usr/bin/pgrep", ["-P", String(pid)]) else { return [] }
        return output.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Window helpers

    private struct WindowDescription: CustomStringConvertible {
        let name: String?
        let width: CGFloat
        let height: CGFloat

        var description: String { "\(name ?? "unnamed") \(Int(width))×\(Int(height))" }
    }

    private func onScreenWindows(ownedBy pid: pid_t) -> [WindowDescription] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { entry in
            guard let owner = entry[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { return nil }
            // Menu-bar and status-item surfaces live at higher window layers; the defect was an
            // ordinary window, which is layer 0.
            if let layer = entry[kCGWindowLayer as String] as? Int, layer != 0 { return nil }
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
            return WindowDescription(name: entry[kCGWindowName as String] as? String,
                                     width: bounds.width,
                                     height: bounds.height)
        }
    }
}

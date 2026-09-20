import AppKit
import SwiftUI
import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// The Command Code card's settings entry must stay reachable for VoiceOver
/// (REVIEW.md R1).
///
/// `testTheSettingsEntryKeepsItsOwnElementAndPressAction` is the check that answers the
/// question. It walks this process's real accessibility tree and asserts three measured facts:
/// the settings entry is its own element, it is a different node from the combined identity
/// element, and pressing it runs the product's action.
///
/// Measured behaviour behind those assertions (2026-09-18, macOS 27, harness built from these
/// same sources):
/// - the shipped card exposes `AXStaticText desc="Command Code" value="未连接"` for the combined
///   identity element and a separate `AXLink desc="前往设置"` for the settings entry;
/// - with the whole header combined — the R1 shape — the tree holds a single
///   `AXButton desc="Command Code" value="未连接"` and `settingsEntryElements == 0`: the entry
///   loses its own element and its own label, so VoiceOver announces only the header;
/// - `AXPress` on the merged element still reached the action in that measurement, so the
///   observable harm is the lost entry and label rather than a dead action. The fix is still
///   the right one: VoiceOver now gets a separately labelled, separately activatable entry.
///
/// Environment limit: macOS builds a process's accessibility tree only for an AX-trusted
/// client, and an XCTest runner is not trusted — on an untrusted runner every query returns an
/// empty tree for *any* composition. The test therefore skips (never silently passes) when
/// `AXIsProcessTrusted()` is false, and a skip must be reported as "not executed", not as
/// evidence. A shell-spawned binary does inherit the terminal's trust; that is how the
/// behaviour above was measured.
@MainActor
final class CommandCodeAccessibilityTests: XCTestCase {

    private static let settingsTitle = "前往设置"
    private static let secondaryTitle = "查看设置"

    private var window: NSWindow?

    override func setUpWithError() throws {
        try super.setUpWithError()
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            throw XCTSkip("AppKit accessibility requires a logged-in macOS window server")
        }
    }

    override func tearDownWithError() throws {
        window?.orderOut(nil)
        window = nil
        try super.tearDownWithError()
    }

    // MARK: Fixtures

    /// No usage report: this is the state that draws the settings entry.
    private func emptyReport(_ connection: ProviderConnectionState = .notConfigured) -> ProviderReport {
        ProviderReport(platform: .commandcode,
                       accountID: "fixture",
                       balances: [],
                       usage: nil,
                       lastSuccessAt: nil,
                       connection: connection,
                       isLive: false,
                       error: nil,
                       consoleURL: nil)
    }

    private func reportWithUsage() -> ProviderReport {
        ProviderReport(platform: .commandcode,
                       accountID: "fixture",
                       balances: [],
                       usage: ProviderUsage(windows: [], summary: nil, planName: "individual-go"),
                       lastSuccessAt: nil,
                       connection: .connected,
                       isLive: true,
                       error: nil,
                       consoleURL: nil)
    }

    @discardableResult
    private func host<V: View>(_ view: V, size: CGSize) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        self.window = window
        return hosting
    }

    // MARK: Always-on smoke check

    /// The entry must still be drawn, and only when there is no usage report to show instead.
    /// This is a presence check, not an accessibility check: SwiftUI materialises a `Button` as
    /// an AppKit subview only for some styles, and that is unrelated to
    /// `accessibilityElement(children:)`.
    func testTheSettingsEntryIsStillDrawnAsARealControl() {
        let card = CommandCodeOverviewCard(report: emptyReport(), openSettings: {})
        let cardHost = host(card, size: CommandCodeOverviewCard.size)
        let buttons = materialisedButtons(in: cardHost)
        XCTAssertEqual(buttons.count, 1,
                       "the settings entry must still exist as its own control in the header; "
                       + "found \(buttons.map { NSStringFromClass(type(of: $0)) })")

        let withUsage = host(CommandCodeOverviewCard(report: reportWithUsage(), openSettings: {}),
                             size: CommandCodeOverviewCard.size)
        XCTAssertTrue(materialisedButtons(in: withUsage).isEmpty,
                      "a card with real usage offers no settings entry")
    }

    /// AppKit button views SwiftUI created for the link-styled settings entry. The walk stops at
    /// the first match on a branch, because a button's own descendants include its content host.
    private func materialisedButtons(in root: NSView) -> [NSView] {
        var found: [NSView] = []
        func walk(_ view: NSView) {
            if view !== root, NSStringFromClass(type(of: view)).contains("Button") {
                found.append(view)
                return
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(root)
        return found
    }

    // MARK: Real accessibility tree (requires an AX-trusted runner)

    func testTheSettingsEntryKeepsItsOwnElementAndPressAction() throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("""
                not executed: the test runner is not trusted for accessibility, so macOS never \
                builds this process's accessibility tree (AXIsProcessTrusted() == false, and a \
                self-query returns kAXErrorNotImplemented). Grant the runner access under System \
                Settings ▸ Privacy & Security ▸ Accessibility, or run the standalone harness \
                described in IMPLEMENTATION_REPORT.md §10, before treating R1 as re-verified.
                """)
        }

        // An XCTest process is not launched as a GUI app, so even when it is AX-trusted the
        // window server may attach no accessibility windows to it. Measure that first: with no
        // tree there is nothing to assert, and a skip is the only honest outcome. This is
        // reported as "not executed", never as a pass.
        host(CommandCodeOverviewCard(report: emptyReport(), openSettings: {}),
             size: CommandCodeOverviewCard.size)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let application = AXUIElementCreateApplication(getpid())
        let windows: [AXUIElement] = axAttribute(application, kAXWindowsAttribute) ?? []
        guard !windows.isEmpty else {
            throw XCTSkip("""
                not executed: this process is AX-trusted but exposes no accessibility windows \
                (kAXWindows returned none while NSApp has \(NSApp.windows.count) window(s)), so \
                there is no tree to walk. An XCTest runner is not a GUI app. Use the standalone \
                harness in IMPLEMENTATION_REPORT.md §10, or VoiceOver, to re-verify R1.
                """)
        }

        for (connection, title) in [(ProviderConnectionState.notConfigured, Self.settingsTitle),
                                    (ProviderConnectionState.unavailable, Self.secondaryTitle)] {
            var activated = 0
            let card = CommandCodeOverviewCard(report: emptyReport(connection),
                                               openSettings: { activated += 1 })
            // Each state gets its own window, and the tree is re-read from that window only:
            // reusing the pre-loop `windows` would press the previous state's entry, or none
            // at all once the previous window is closed (REVIEW.md R2).
            window?.orderOut(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let beforeWindows: [AXUIElement] = axAttribute(application, kAXWindowsAttribute) ?? []
            host(card, size: CommandCodeOverviewCard.size)
            let deadline = Date().addingTimeInterval(1)
            var currentWindow: AXUIElement?
            repeat {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let currentWindows: [AXUIElement] = axAttribute(application, kAXWindowsAttribute) ?? []
                currentWindow = currentWindows.first { candidate in
                    !beforeWindows.contains { previous in CFEqual(previous, candidate) }
                }
            } while currentWindow == nil && Date() < deadline

            guard let currentWindow else {
                throw XCTSkip("""
                    not executed: the current state exposed no new accessibility window, so there \
                    is no tree to walk for \(title). Use the standalone harness in \
                    IMPLEMENTATION_REPORT.md §10, or VoiceOver, to re-verify R1.
                    """)
            }
            let nodes = accessibilityNodes(in: [currentWindow])

            // The non-interactive identity stays one combined element.
            let identity = nodes.first { $0.description == "Command Code" }
            XCTAssertNotNil(identity, "the combined identity element must be reachable")
            XCTAssertNotEqual(identity?.description, title,
                              "the settings title must not be folded into the identity element")

            // The settings entry must be its own element, separate from that combined one.
            let entry = nodes.first { $0.description == title || $0.value == title }
            let unwrapped = try XCTUnwrap(entry,
                                          "no accessibility element carries the settings entry \(title); "
                                          + "it was merged into the header")
            XCTAssertFalse(identity.map { CFEqual($0.element, unwrapped.element) } ?? false,
                           "the settings entry must not be the combined identity element")

            // And it must actually be activatable.
            let result = AXUIElementPerformAction(unwrapped.element, kAXPressAction as CFString)
            XCTAssertEqual(result, .success, "AXPress on the settings entry must succeed")
            XCTAssertEqual(activated, 1,
                           "pressing the settings entry must run the product's action exactly once")
            window?.orderOut(nil)
        }
    }

    // MARK: AX helpers

    private struct Node {
        let element: AXUIElement
        let role: String
        let description: String
        let value: String
    }

    private func accessibilityNodes(in windows: [AXUIElement]) -> [Node] {
        var nodes: [Node] = []
        func collect(_ element: AXUIElement) {
            nodes.append(Node(element: element,
                              role: axAttribute(element, kAXRoleAttribute) ?? "-",
                              description: axAttribute(element, kAXDescriptionAttribute) ?? "",
                              value: axAttribute(element, kAXValueAttribute) ?? ""))
            let children: [AXUIElement] = axAttribute(element, kAXChildrenAttribute) ?? []
            for child in children { collect(child) }
        }
        for window in windows { collect(window) }
        return nodes
    }

    private func axAttribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}

import AppKit
import SwiftUI
import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// Explicit opt-in export of the production overview panel with synthetic accounts only.
///
/// The stored order is exercised through the same `OverviewAccountOrderPreferences` the app
/// uses, so the two images differ only by the value a real drag would write. No CLI runs, no
/// real account, Key or balance is rendered, and no application preference is changed.
@MainActor
final class OverviewReorderEvidenceTests: XCTestCase {

    func testExportOverviewBeforeAndAfterAGlobalReorder() throws {
        guard let destination = ProcessInfo.processInfo.environment["MINGET_REORDER_EVIDENCE"] else { return }
        if ProcessInfo.processInfo.environment["CI"] == "true" { throw XCTSkip("Requires a macOS window server") }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let suiteName = "OverviewReorderEvidence." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let registry = try AccountRegistry(defaults: defaults)
        for platform in [AccountPlatform.chatGPT, .chatGPT, .google, .deepseek, .commandcode] {
            var account = registry.draft(platform)
            if platform == .google {
                account.googleUUID = UUID()
                account.googleEmail = "demo\(account.ordinal)@example.com"
                account.googleVersion = AntigravityCLILocator.version
            }
            try registry.upsert(account)
        }
        let credentials = InMemoryCredentialStore()
        let google = AntigravityModel(credentials: credentials, defaults: defaults,
            store: AntigravityProfileStore(base: directory, registry: registry), registry: registry, migrateLegacy: false)
        let model = UsageViewModel(coordinator: CodexProfilesCoordinator(profiles: registry.accounts.compactMap(\.profile)), google: google,
            providerEngine: ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults)),
            menuBarPreferences: MenuBarPreferences(defaults: defaults), displayNames: DisplayNamePreferences(defaults: defaults),
            fireSchedules: FireSchedulePreferences(defaults: defaults))
        model.installAccountManagement(registry: registry, credentials: credentials, transport: ManagedAccountTests.Transport(), defaults: defaults)

        let preferences = DetailPreferences(defaults: defaults)
        preferences.showGoogle = true
        preferences.selectedTab = .all
        let order = OverviewAccountOrderPreferences(defaults: defaults)
        let height = UsagePanelView.presentationHeight(model: model, preferences: preferences)
        let size = CGSize(width: DetailPageLayout.pageWidth, height: height)

        for dark in [false, true] {
            try render(UsagePanelView(model: model, preferences: preferences, orderPreferences: order,
                                      maxHeight: height, refreshOnAppear: false), size: size, dark: dark)
                .write(to: output.appendingPathComponent(dark ? "overview-order-before-dark.png" : "overview-order-before-light.png"))
        }

        // The order a cross-platform drag produces: both API rows move above the ChatGPT rows.
        let visible = model.profileStates.map(\.id) + model.google.accounts.map(\.id)
            + model.managedAPIStates.map(\.account.id)
        XCTAssertEqual(visible.count, 5)
        let apiIDs = model.managedAPIStates.map(\.account.id)
        order.commit(apiIDs.reversed() + visible.filter { !apiIDs.contains($0) }, visibleIDs: visible)
        XCTAssertEqual(order.order.prefix(2), ArraySlice(apiIDs.reversed()), "both API rows move above the ChatGPT rows")

        for dark in [false, true] {
            try render(UsagePanelView(model: model, preferences: preferences, orderPreferences: order,
                                      maxHeight: height, refreshOnAppear: false), size: size, dark: dark)
                .write(to: output.appendingPathComponent(dark ? "overview-order-after-dark.png" : "overview-order-after-light.png"))
        }
    }

    private func render<V: View>(_ view: V, size: CGSize, dark: Bool) throws -> Data {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                                    pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

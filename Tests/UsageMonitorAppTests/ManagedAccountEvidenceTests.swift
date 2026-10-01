import AppKit
import SwiftUI
import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

@MainActor
final class ManagedAccountEvidenceTests: XCTestCase {
    func testAccountManagementAndAddSheetsRenderAtNativeWindowSize() throws {
        if ProcessInfo.processInfo.environment["CI"] == "true" { throw XCTSkip("Requires a macOS window server") }
        let defaults = UserDefaults(suiteName: "ManagedAccountEvidence." + UUID().uuidString)!
        let registry = try AccountRegistry(defaults: defaults, legacy: true)
        for platform in [AccountPlatform.chatGPT, .chatGPT, .google, .google, .google, .google, .deepseek, .commandcode] {
            var row = registry.draft(platform)
            if platform == .google {
                row.googleUUID = UUID(); row.googleEmail = "demo\(row.ordinal)@example.com"; row.googleVersion = AntigravityCLILocator.version
            }
            try registry.upsert(row)
        }
        let google = AntigravityModel(credentials: InMemoryCredentialStore(), defaults: defaults,
            store: AntigravityProfileStore(base: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), registry: registry), registry: registry, migrateLegacy: false)
        let model = UsageViewModel(coordinator: CodexProfilesCoordinator(profiles: registry.accounts.compactMap(\.profile)), google: google,
            providerEngine: ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults)), menuBarPreferences: MenuBarPreferences(defaults: defaults), displayNames: DisplayNamePreferences(defaults: defaults), fireSchedules: FireSchedulePreferences(defaults: defaults))
        model.installAccountManagement(registry: registry, credentials: InMemoryCredentialStore(), transport: ManagedAccountTests.Transport(), defaults: defaults)
        XCTAssertEqual(google.connections.map(\.email), (1...4).map { "demo\($0)@example.com" })
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MINGET_EVIDENCE_DIR"] ?? NSTemporaryDirectory() + "Minget-1.6.3-Evidence")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let navigation = SettingsNavigation(defaults: defaults); navigation.section = .accounts
        for dark in [false, true] {
            try render(MingetSettingsView(model: model, menuBarPreferences: model.menuBarPreferences, onQuit: {}, navigation: navigation), size: CGSize(width: 780, height: 640), dark: dark)
                .write(to: root.appendingPathComponent(dark ? "accounts-dark.png" : "accounts-light.png"))
            try render(AddManagedAccountSheet(model: model, platform: .deepseek), size: CGSize(width: 508, height: 350), dark: dark)
                .write(to: root.appendingPathComponent(dark ? "add-api-dark.png" : "add-api-light.png"))
        }
        XCTAssertEqual(model.managedAccounts.count, 12)
        XCTAssertEqual(model.scheduleTargets.count, 6)
    }
    private func render<V: View>(_ view: V, size: CGSize, dark: Bool) throws -> Data {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: size); hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size; hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

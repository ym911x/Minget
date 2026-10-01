import XCTest
import SwiftUI
import AppKit
@testable import UsageMonitorApp
@testable import UsageMonitorCore

/// Explicit local export only. Uses production views and isolated example profiles;
/// never launches a CLI, accesses real account data, or changes application preferences.
@MainActor
final class ReleaseScreenshotTests: XCTestCase {
    func testExportPublicGoogleScreenshots() async throws {
        guard let destination = ProcessInfo.processInfo.environment["MINGET_RELEASE_SCREENSHOTS"] else { return }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("minget-public-example-" + UUID().uuidString)
        let suite = "minget-public-example-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let store = AntigravityProfileStore(base: root)
        let emptyModel = AntigravityModel(credentials: InMemoryCredentialStore(), defaults: defaults,
                                    store: store, reader: PublicScreenshotReader(), migrateLegacy: false)
        let preferences = DetailPreferences(defaults: defaults)
        let empty = AntigravityConnectionView(google: emptyModel, preferences: preferences)
        try export(VStack(alignment: .leading, spacing: 12) {
            heading("连接 Google 双账号")
            empty
            Text("在官方页面分别授权；账号数据保存在本机独立目录。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }, dark: false, size: NSSize(width: 460, height: 360), to: output.appendingPathComponent("google-connect-light.png"))
        for slot in AntigravitySlot.allCases {
            let id = UUID(); try store.prepare(id)
            _ = try store.commit(slot: slot, uuid: id, email: slot == .a ? "account-a@example.com" : "account-b@example.com")
        }
        let model = AntigravityModel(credentials: InMemoryCredentialStore(), defaults: defaults,
                                    store: store, reader: PublicScreenshotReader(), migrateLegacy: false)
        model.start()
        defer { model.stop() }
        for _ in 0..<200 where model.isRefreshing { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.accounts.count, 2)
        XCTAssertTrue(model.accounts.allSatisfy { $0.snapshot != nil && $0.failure == nil })
        for dark in [false, true] {
            try export(VStack(alignment: .leading, spacing: 12) {
                heading("Google 双账号额度")
                ForEach(model.accounts) { state in
                    AntigravityOverviewCard(state: state, displayName: state.account.label)
                }
            }, dark: dark, size: NSSize(width: 460, height: 646),
               to: output.appendingPathComponent(dark ? "google-dual-dark.png" : "google-dual-light.png"))
        }
        try export(VStack(alignment: .leading, spacing: 12) {
            heading("管理 Google 账号")
            AntigravityConnectionView(google: model, preferences: preferences)
        }, dark: false, size: NSSize(width: 460, height: 430), to: output.appendingPathComponent("google-accounts-light.png"))
        // All sources share the real production panel, with isolated synthetic readers.
        let cache = UsageCache(userDefaults: defaults)
        let coordinator = CodexProfilesCoordinator { profile in
            UsageService(factory: { ExampleCodexClient(isA: profile.id == "chatgpt-a") }, cache: cache, profileID: profile.id)
        }
        for id in coordinator.profileIDs { _ = coordinator.fetch(profileID: id) }
        let appModel = UsageViewModel(coordinator: coordinator, google: model,
            providerEngine: ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults)),
            menuBarPreferences: MenuBarPreferences(defaults: defaults),
            displayNames: DisplayNamePreferences(defaults: defaults),
            fireSchedules: FireSchedulePreferences(defaults: defaults))
        preferences.showGoogle = true
        for dark in [false, true] {
            for selection in [DetailPreferences.ProviderTab.all, .chatGPT, .google, .commandCode] {
                preferences.selectedTab = selection
                let panel = UsagePanelView(model: appModel, preferences: preferences,
                    maxHeight: 640, refreshOnAppear: false)
                let height = DetailPageLayout.stableViewportHeight
                try export(panel, dark: dark, size: NSSize(width: 476, height: height + 68),
                    to: output.appendingPathComponent("panel-\(selection.rawValue)-\(dark ? "dark" : "light").png"))
            }
            let nav = SettingsNavigation(defaults: defaults)
            for section in SettingsSection.allCases {
                nav.section = section
                try export(MingetSettingsView(model: appModel, preferences: preferences,
                    menuBarPreferences: appModel.menuBarPreferences, onQuit: {}, navigation: nav),
                    dark: dark, size: NSSize(width: 816, height: 708),
                    to: output.appendingPathComponent("settings-\(section.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }

    }
    private func heading(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("明明有数 v1.6.1").font(.system(size: 18, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .medium))
            Text("展示副本 · 示例账号与数据").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func export<V: View>(_ content: V, dark: Bool, size: NSSize, to url: URL) throws {
        let view = VStack(spacing: 8) { Text("1.6.1 展示副本 · 示例账号与数据").font(.system(size: 11)).foregroundStyle(.secondary); content }.padding(18).frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(dark ? Color(red: 0.11, green: 0.12, blue: 0.14) : Color.white)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "zh_CN"))
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame.size = size
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000)
        try png.write(to: url)
    }
}

private final class ExampleCodexClient: CodexAppServerProviding {
    let isA: Bool
    var isTransportRunning = true
    init(isA: Bool) { self.isA = isA }
    func start() throws {}
    func handshake(timeout: TimeInterval) throws {}
    func readAccount(timeout: TimeInterval) throws -> CodexAccount? {
        CodexAccount(kind: .chatgpt, email: isA ? "account-a@example.com" : "account-b@example.com", planType: "plus")
    }
    func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
        let five = isA ? 82.45 : 56.32
        let week = isA ? 91.67 : 78.40
        return UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                usedPercent: 100 - five, remainingPercent: five, resetsAt: Date().addingTimeInterval(3 * 3600)),
            weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10080,
                usedPercent: 100 - week, remainingPercent: week, resetsAt: Date().addingTimeInterval(5 * 86400)),
            fetchedAt: Date(), source: .codexAppServer)
    }
    func stop() { isTransportRunning = false }
}

struct PublicScreenshotReader: AntigravityUsageReading {
    func read(connection: AntigravityConnection, home: URL) async throws -> AntigravitySnapshot {
        let a = connection.slot == .a
        let iso = ISO8601DateFormatter()
        let reset = Date().addingTimeInterval(3 * 3600)
        let groups = [
            AntigravityQuotaGroup(id: "gemini", label: "Gemini Models", models: [], buckets: [
                AntigravityQuotaBucket(id: "gemini-5h", label: "Five Hour Limit Remaining", window: "5h", remainingFraction: a ? 0.8245 : 0.5632, resetsAt: reset),
                AntigravityQuotaBucket(id: "gemini-weekly", label: "Weekly Limit Remaining", window: "weekly", remainingFraction: a ? 0.9167 : 0.7840, resetsAt: reset.addingTimeInterval(5 * 86400))
            ]),
            AntigravityQuotaGroup(id: "shared", label: "Claude and GPT models", models: [], buckets: [
                AntigravityQuotaBucket(id: "3p-5h", label: "Five Hour Limit Remaining", window: "5h", remainingFraction: a ? 0.7350 : 0.8820, resetsAt: reset),
                AntigravityQuotaBucket(id: "3p-weekly", label: "Weekly Limit Remaining", window: "weekly", remainingFraction: a ? 0.6475 : 0.9310, resetsAt: reset.addingTimeInterval(6 * 86400))
            ])
        ]
        return AntigravitySnapshot(accountIdentity: connection.account.identity, groups: groups,
                                   fetchedAt: iso.date(from: "2026-10-01T02:00:00Z")!)
    }
}

import AppKit
import SwiftUI
import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// A brand page's refresh button reads only that brand (docs/versions/1.6.5/REQUIREMENTS.md).
///
/// Every case here observes the reads themselves — gated clients and per-host request counts —
/// so "the other brands were not asked" is a measured fact rather than an assumption about
/// which function the button calls.
@MainActor
final class BrandRefreshTests: XCTestCase {

    // MARK: Fixtures

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "UsageMonitorAppTests.BrandRefresh.\(label)." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    /// A platform reader that counts its reads, so a brand's request is observed while the
    /// other brand's count stays put.
    private final class CountingReader: ProviderReading, @unchecked Sendable {
        let platform: ProviderPlatform
        var isConfigured = true
        var isAutomaticRefreshEnabled = true
        private let lock = NSLock()
        private var calls = 0

        init(platform: ProviderPlatform) {
            self.platform = platform
        }

        var readCount: Int {
            lock.lock(); defer { lock.unlock() }
            return calls
        }

        func read() async throws -> ProviderReadResult {
            countRead()
            return ProviderReadResult(accountID: "synthetic-\(platform.rawValue)", balances: [], usage: nil,
                                      consoleURL: nil)
        }

        private func countRead() {
            lock.lock(); calls += 1; lock.unlock()
        }

        func disconnect() throws {}
    }

    private final class GatedCodexClient: CodexAppServerProviding, @unchecked Sendable {
        private let started = DispatchSemaphore(value: 0)
        private let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls = 0
        var isTransportRunning = true

        var readCount: Int {
            lock.lock(); defer { lock.unlock() }
            return calls
        }

        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readAccount(timeout: TimeInterval) throws -> CodexAccount? {
            CodexAccount(kind: .chatgpt, email: "demo@example.com", planType: "plus")
        }
        func stop() { isTransportRunning = false }

        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            lock.lock(); calls += 1; lock.unlock()
            started.signal()
            release.wait()
            return UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                           usedPercent: 10, remainingPercent: 90,
                                                           resetsAt: Date().addingTimeInterval(3600)),
                                 weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                                         usedPercent: 50, remainingPercent: 50,
                                                         resetsAt: Date().addingTimeInterval(3 * 86400)),
                                 fetchedAt: Date(), source: .codexAppServer)
        }

        func awaitStart(timeout: TimeInterval = 5) -> Bool {
            started.wait(timeout: .now() + timeout) == .success
        }

        func releaseOnce() { release.signal() }
    }

    /// Counts requests per host and answers each platform with the smallest valid payload.
    private final class HostCountingTransport: ProviderTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            let host = request.url?.host ?? "unknown"
            countHit(host)
            if host == "api.commandcode.ai" {
                return ProviderHTTPResponse(status: 200, body: Data(#"{"credits":{"monthlyCredits":"3.50"},"windowLimits":{"fiveHour":{"cap":3,"used":0.05,"resetAt":1780000000},"weekly":{"cap":6,"used":1.57,"resetAt":1780300000}}}"#.utf8))
            }
            return ProviderHTTPResponse(status: 200, body: Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"10.00","granted_balance":"0.00","topped_up_balance":"10.00"}]}"#.utf8))
        }

        private func countHit(_ host: String) {
            lock.lock(); counts[host, default: 0] += 1; lock.unlock()
        }

        func count(_ host: String) -> Int {
            lock.lock(); defer { lock.unlock() }
            return counts[host] ?? 0
        }

        func reset() {
            lock.lock(); counts = [:]; lock.unlock()
        }
    }

    private func makeLegacyModel(_ label: String, readers: [ProviderReading]) -> UsageViewModel {
        let defaults = makeDefaults(label)
        return UsageViewModel(coordinator: CodexProfilesCoordinator(profiles: []),
                              providerEngine: ProviderRefreshEngine(readers: readers,
                                                                     cache: ProviderCache(userDefaults: defaults)),
                              menuBarPreferences: MenuBarPreferences(defaults: defaults),
                              displayNames: DisplayNamePreferences(defaults: defaults),
                              fireSchedules: FireSchedulePreferences(defaults: defaults),
                              fireConfirmDelay: 0, fireRetryDelay: 0)
    }

    // MARK: Legacy (no account registry)

    func testDeepSeekBrandRefreshNeverTouchesCommandCode() async throws {
        let deepSeek = CountingReader(platform: .deepseek)
        let commandCode = CountingReader(platform: .commandcode)
        let model = makeLegacyModel("legacy-deepseek", readers: [deepSeek, commandCode])

        model.refreshBrand(.deepSeek)
        let readDeepSeek = await waitUntil { deepSeek.readCount == 1 }
        XCTAssertTrue(readDeepSeek, "the DeepSeek page's refresh must read DeepSeek")
        let settled = await waitUntil { !model.isRefreshing(brand: .deepSeek) }
        XCTAssertTrue(settled)
        XCTAssertEqual(deepSeek.readCount, 1)
        XCTAssertEqual(commandCode.readCount, 0, "the Command Code page was never opened or refreshed")
    }

    func testCommandCodeBrandRefreshNeverTouchesDeepSeek() async throws {
        let deepSeek = CountingReader(platform: .deepseek)
        let commandCode = CountingReader(platform: .commandcode)
        let model = makeLegacyModel("legacy-commandcode", readers: [deepSeek, commandCode])

        model.refreshBrand(.commandCode)
        let readCommandCode = await waitUntil { commandCode.readCount == 1 }
        XCTAssertTrue(readCommandCode, "the Command Code page's refresh must read Command Code")
        let settled = await waitUntil { !model.isRefreshing(brand: .commandCode) }
        XCTAssertTrue(settled)
        XCTAssertEqual(commandCode.readCount, 1)
        XCTAssertEqual(deepSeek.readCount, 0)
        XCTAssertFalse(model.isRefreshing(brand: .deepSeek))
        XCTAssertFalse(model.isRefreshing(brand: .chatGPT))
    }

    // MARK: ChatGPT

    func testChatGPTBrandRefreshReadsBothProfilesAndNoProvider() async throws {
        let defaults = makeDefaults("chatgpt")
        let a = GatedCodexClient(), b = GatedCodexClient()
        let cache = UsageCache(userDefaults: defaults)
        let coordinator = CodexProfilesCoordinator(profiles: [.chatGPTA, .chatGPTB]) { profile in
            UsageService(factory: { profile.id == "chatgpt-a" ? a : b }, cache: cache,
                         profileID: profile.id, restartDelay: 0)
        }
        let deepSeek = CountingReader(platform: .deepseek)
        let model = UsageViewModel(coordinator: coordinator,
                                   providerEngine: ProviderRefreshEngine(readers: [deepSeek],
                                                                        cache: ProviderCache(userDefaults: defaults)),
                                   menuBarPreferences: MenuBarPreferences(defaults: defaults),
                                   displayNames: DisplayNamePreferences(defaults: defaults),
                                   fireSchedules: FireSchedulePreferences(defaults: defaults),
                                   fireConfirmDelay: 0, fireRetryDelay: 0)

        model.refreshBrand(.chatGPT)
        XCTAssertTrue(a.awaitStart(), "both ChatGPT profiles belong to the brand")
        XCTAssertTrue(b.awaitStart())
        XCTAssertTrue(model.isRefreshing(brand: .chatGPT))
        XCTAssertFalse(model.isRefreshing(brand: .deepSeek))
        XCTAssertFalse(model.isRefreshing(brand: .commandCode))
        XCTAssertEqual(deepSeek.readCount, 0, "a ChatGPT refresh must not read the providers")

        a.releaseOnce(); b.releaseOnce()
        let finished = await waitUntil { !model.isRefreshing(brand: .chatGPT) }
        XCTAssertTrue(finished)
        XCTAssertEqual(a.readCount, 1)
        XCTAssertEqual(b.readCount, 1)
        XCTAssertEqual(deepSeek.readCount, 0)
    }

    // MARK: Managed accounts

    func testManagedCommandCodeRefreshSkipsTheDeepSeekConnection() async throws {
        let defaults = makeDefaults("managed")
        let transport = HostCountingTransport()
        let registry = try AccountRegistry(defaults: defaults)
        let model = UsageViewModel(coordinator: CodexProfilesCoordinator(profiles: []),
                                   providerEngine: ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults)),
                                   menuBarPreferences: MenuBarPreferences(defaults: defaults),
                                   displayNames: DisplayNamePreferences(defaults: defaults),
                                   fireSchedules: FireSchedulePreferences(defaults: defaults),
                                   fireConfirmDelay: 0, fireRetryDelay: 0)
        model.installAccountManagement(registry: registry, credentials: InMemoryCredentialStore(),
                                       transport: transport, defaults: defaults)

        XCTAssertTrue(model.saveManagedAPI(registry.draft(.deepseek, name: "工作"), key: "synthetic-deepseek"))
        XCTAssertTrue(model.saveManagedAPI(registry.draft(.commandcode, name: "GO"), key: "synthetic-commandcode"))
        let ready = await waitUntil {
            model.managedAPIStates.count == 2 && model.managedAPIStates.allSatisfy { $0.report.connection == .connected }
        }
        XCTAssertTrue(ready, "both connections must be readable before the scoped refresh is measured")

        transport.reset()
        model.refreshBrand(.commandCode)
        let readCommandCode = await waitUntil { transport.count("api.commandcode.ai") > 0 }
        XCTAssertTrue(readCommandCode, "the Command Code page's refresh must read Command Code")
        let settled = await waitUntil { !model.isRefreshing(brand: .commandCode) }
        XCTAssertTrue(settled)
        XCTAssertEqual(transport.count("api.deepseek.com"), 0, "the other brand's connection is not read")
        XCTAssertGreaterThan(transport.count("api.commandcode.ai"), 0)

        // And the mirror image: the DeepSeek page reads only DeepSeek.
        transport.reset()
        model.refreshBrand(.deepSeek)
        let readDeepSeek = await waitUntil { transport.count("api.deepseek.com") > 0 }
        XCTAssertTrue(readDeepSeek)
        let deepSeekSettled = await waitUntil { !model.isRefreshing(brand: .deepSeek) }
        XCTAssertTrue(deepSeekSettled)
        XCTAssertEqual(transport.count("api.commandcode.ai"), 0)
    }

    func testBrandRefreshButtonExistsOnlyWhereThereIsSomethingToRead() {
        let model = makeLegacyModel("availability", readers: [])
        XCTAssertFalse(model.hasRefreshableAccounts(brand: .all), "the overview keeps the header's global button")
        XCTAssertFalse(model.hasRefreshableAccounts(brand: .chatGPT))
        XCTAssertFalse(model.hasRefreshableAccounts(brand: .commandCode))
        XCTAssertFalse(model.isRefreshing(brand: .deepSeek))
        XCTAssertFalse(model.isAnyRefreshInFlight)
    }

    // MARK: Evidence

    /// Explicit opt-in export of the production panel with synthetic accounts only.
    ///
    /// One image per brand page in both appearances, plus the same Command Code page while its
    /// own read is in flight: the button must appear exactly on the pages that own an account
    /// and show its progress state without moving the layout.
    func testExportBrandRefreshEvidence() async throws {
        guard let destination = ProcessInfo.processInfo.environment["MINGET_BRAND_REFRESH_EVIDENCE"] else { return }
        if ProcessInfo.processInfo.environment["CI"] == "true" { throw XCTSkip("Requires a macOS window server") }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let suiteName = "BrandRefreshEvidence." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = try AccountRegistry(defaults: defaults)
        for platform in [AccountPlatform.chatGPT, .deepseek, .commandcode] {
            try registry.upsert(registry.draft(platform))
        }
        let transport = HangingTransport()
        let model = UsageViewModel(coordinator: CodexProfilesCoordinator(profiles: registry.accounts.compactMap(\.profile)),
                                   providerEngine: ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults)),
                                   menuBarPreferences: MenuBarPreferences(defaults: defaults),
                                   displayNames: DisplayNamePreferences(defaults: defaults),
                                   fireSchedules: FireSchedulePreferences(defaults: defaults),
                                   fireConfirmDelay: 0, fireRetryDelay: 0)
        model.installAccountManagement(registry: registry, credentials: InMemoryCredentialStore(),
                                       transport: transport, defaults: defaults)

        let preferences = DetailPreferences(defaults: defaults)
        let height = UsagePanelView.presentationHeight(model: model, preferences: preferences)

        for tab in [DetailPreferences.ProviderTab.chatGPT, .deepSeek, .commandCode] {
            for dark in [false, true] {
                let name = "brand-refresh-\(tab.rawValue)-\(dark ? "dark" : "light").png"
                try render(UsagePanelView(model: model, preferences: preferences, maxHeight: height,
                                          refreshOnAppear: false), preferences: preferences, tab: tab,
                           size: height, dark: dark).write(to: output.appendingPathComponent(name))
            }
        }

        // The same Command Code page while that brand's own read is in flight: saving the
        // synthetic credential starts exactly one read through the hanging transport.
        let commandCode = try XCTUnwrap(registry.accounts.first { $0.platform == .commandcode })
        XCTAssertTrue(model.saveManagedAPI(commandCode, key: "synthetic-commandcode"))
        let started = await waitUntil { transport.count > 0 }
        XCTAssertTrue(started, "the evidence needs a real in-flight read to render")
        XCTAssertTrue(model.isRefreshing(brand: .commandCode))
        for dark in [false, true] {
            let name = "brand-refresh-commandcode-refreshing-\(dark ? "dark" : "light").png"
            try render(UsagePanelView(model: model, preferences: preferences, maxHeight: height,
                                      refreshOnAppear: false), preferences: preferences, tab: .commandCode,
                       size: height, dark: dark).write(to: output.appendingPathComponent(name))
        }
    }

    /// A transport that never answers, so one brand's read stays observably in flight.
    private final class HangingTransport: ProviderTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var hits = 0

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return hits
        }

        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            countHit()
            try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            throw URLError(.timedOut)
        }

        private func countHit() {
            lock.lock(); hits += 1; lock.unlock()
        }
    }

    private func render<V: View>(_ view: V, preferences: DetailPreferences, tab: DetailPreferences.ProviderTab,
                                 size: CGFloat, dark: Bool) throws -> Data {
        preferences.selectedTab = tab
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: DetailPageLayout.pageWidth, height: size))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                    pixelsWide: Int(DetailPageLayout.pageWidth * 2),
                                                    pixelsHigh: Int(size * 2), bitsPerSample: 8,
                                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = CGSize(width: DetailPageLayout.pageWidth, height: size)
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

import AppKit
import SwiftUI
import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

/// Renders the production detail page and the cards from fixed fixtures
/// (REVISION_SPEC.md §12).
///
/// Output goes to `$TMPDIR/Minget-1.3.0-Evidence/` only. The images are fixture renders of the
/// real view code with example accounts and balances — `demo@example.com` and synthetic
/// amounts. No real email, balance or account is ever rendered, and no historical evidence
/// directory is written.
@MainActor
final class DetailEvidenceRenderTests: XCTestCase {

    /// Captured once per test so every fixture date is relative to the same real clock
    /// reading the cards themselves use. A fixed 2027 timestamp would make every rail look
    /// expired or invalid and would prove nothing about the active state.
    private var anchor = Date()

    override func setUpWithError() throws {
        try super.setUpWithError()
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            throw XCTSkip("AppKit hosting requires a logged-in macOS window server")
        }
    }

    // MARK: Fixtures

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "UsageMonitorAppTests.Evidence.\(label)." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func snapshot(fiveHourPercent: Double, weeklyPercent: Double,
                          fiveHourRemaining: TimeInterval = 4 * 3600,
                          weeklyRemaining: TimeInterval = 3 * 86400,
                          source: UsageSource = .codexAppServer) -> UsageSnapshot {
        UsageSnapshot(fiveHour: RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300,
                                                usedPercent: 100 - fiveHourPercent,
                                                remainingPercent: fiveHourPercent,
                                                resetsAt: anchor.addingTimeInterval(fiveHourRemaining)),
                      weekly: RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080,
                                              usedPercent: 100 - weeklyPercent,
                                              remainingPercent: weeklyPercent,
                                              resetsAt: anchor.addingTimeInterval(weeklyRemaining)),
                      rateLimitResetCredits: RateLimitResetCredits(availableCount: 2,
                                                                   nearestExpiresAt: anchor.addingTimeInterval(5 * 86400)),
                      fetchedAt: anchor,
                      source: source)
    }

    private func account(_ name: String) -> CodexAccount {
        CodexAccount(kind: .chatgpt, email: name, planType: "plus")
    }

    private func profileService(_ profile: ChatGPTAccountProfile,
                                client: @escaping () -> CodexAppServerProviding,
                                cache: UsageCache) -> UsageService {
        UsageService(factory: client, cache: cache, profileID: profile.id, restartDelay: 0)
    }

    private func makeCodexCoordinator(defaults: UserDefaults, aStale: Bool) -> CodexProfilesCoordinator {
        let cache = UsageCache(userDefaults: defaults)
        let addressA = "demo@example.com"
        let addressB = "demo-b@example.com"

        if aStale {
            cache.save(snapshot(fiveHourPercent: 62, weeklyPercent: 31),
                       profileID: "chatgpt-a", accountID: addressA)
            cache.saveLastKnownAccountID(addressA, profileID: "chatgpt-a")
        }

        let coordinator = CodexProfilesCoordinator { profile in
            let isA = profile.id == "chatgpt-a"
            if isA && aStale {
                let failing = FixtureCodexClient(account: nil, snapshot: nil,
                                                 error: .rpcFailed(.timedOut(method: "account/rateLimits/read")))
                return self.profileService(profile, client: { failing }, cache: cache)
            }
            let client = FixtureCodexClient(account: self.account(isA ? addressA : addressB),
                                            snapshot: isA ? self.snapshot(fiveHourPercent: 66, weeklyPercent: 17)
                                                          : self.snapshot(fiveHourPercent: 12, weeklyPercent: 90),
                                            error: nil)
            return self.profileService(profile, client: { client }, cache: cache)
        }
        for profileID in coordinator.profileIDs {
            _ = coordinator.fetch(profileID: profileID)
        }
        return coordinator
    }

    private func makeProviderEngine(defaults: UserDefaults) async -> ProviderRefreshEngine {
        func dec(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }

        let deepSeek = FixtureReading(platform: .deepseek,
                                      result: ProviderReadResult(accountID: "deepseek-fixture",
                                                                 balances: [
                                                                    ProviderBalance(currency: "CNY", total: dec("110.00"), available: dec("110.00")),
                                                                    ProviderBalance(currency: "USD", total: dec("12.34"), available: nil),
                                                                    ProviderBalance(currency: "EUR", total: dec("5.60"), available: nil),
                                                                    ProviderBalance(currency: "JPY", total: dec("800"), available: nil),
                                                                    ProviderBalance(currency: "GBP", total: dec("3.10"), available: nil),
                                                                 ],
                                                                 usage: nil,
                                                                 consoleURL: nil))

        let usage = ProviderUsage(
            windows: [
                ProviderUsageWindow(kind: .fiveHour, used: dec("1.00"), limit: dec("4.00"),
                                    remaining: dec("3.00"),
                                    resetsAt: anchor.addingTimeInterval(2 * 3600 + 13 * 60)),
                ProviderUsageWindow(kind: .weekly, used: dec("4.00"), limit: dec("20.00"),
                                    remaining: dec("16.00"),
                                    resetsAt: anchor.addingTimeInterval(3 * 86400)),
                ProviderUsageWindow(kind: .billingPeriod, used: dec("2.75"), limit: dec("10.00"),
                                    remaining: dec("7.25"), resetsAt: nil),
            ],
            summary: ProviderUsageSummary(totalTokens: 12_345, inputTokens: 8_000, outputTokens: 4_345,
                                          totalRuns: 42, completedRuns: 40, failedRuns: 2,
                                          successRate: dec("95.24"), totalCostUSD: dec("1.234"),
                                          periodBasis: .billingPeriod),
            planName: "individual-go",
            billingPeriodEnd: anchor.addingTimeInterval(12 * 86400),
            billingPeriodStart: anchor.addingTimeInterval(-18 * 86400))
        let commandCode = FixtureReading(platform: .commandcode,
                                         result: ProviderReadResult(accountID: "commandcode-fixture",
                                                                    balances: [],
                                                                    usage: usage,
                                                                    consoleURL: nil))

        let engine = ProviderRefreshEngine(readers: [deepSeek, commandCode],
                                           cache: ProviderCache(userDefaults: defaults))
        await engine.refresh(platform: .deepseek, force: true)
        await engine.refresh(platform: .commandcode, force: true)
        return engine
    }

    private func makeModel(_ label: String, aStale: Bool = false) async -> (UsageViewModel, DetailPreferences) {
        let defaults = makeDefaults(label)
        let coordinator = makeCodexCoordinator(defaults: defaults, aStale: aStale)
        let engine = await makeProviderEngine(defaults: defaults)
        let model = UsageViewModel(coordinator: coordinator,
                                   providerEngine: engine,
                                   menuBarPreferences: MenuBarPreferences(defaults: defaults))
        return (model, DetailPreferences(defaults: defaults))
    }

    private func state(_ profile: ChatGPTAccountProfile,
                       display: UsageDisplay,
                       email: String,
                       fireResult: ChatGPTFireResult? = nil) -> CodexProfileViewState {
        CodexProfileViewState(profile: profile,
                              display: display,
                              connectionState: .connected,
                              account: account(email),
                              isRefreshing: false,
                              isFiring: false,
                              fireResult: fireResult)
    }

    // MARK: §12 Evidence

    func testRenderFullPageLightAndDark() async throws {
        // 1. 440 × 552, light, four cards, account A and B with clearly different quotas.
        let (live, livePreferences) = await makeModel("live")
        try write(try render(UsagePanelView(model: live, preferences: livePreferences),
                             size: CGSize(width: DetailPageLayout.pageWidth,
                                          height: UsagePanelView.preferredHeight(for: livePreferences)),
                             background: .light),
                  named: "01-detail-440x552-light.png")

        // 2. 440 × 552, dark, account A cached and account B live.
        let (cached, cachedPreferences) = await makeModel("cached", aStale: true)
        try write(try render(UsagePanelView(model: cached, preferences: cachedPreferences),
                             size: CGSize(width: DetailPageLayout.pageWidth,
                                          height: UsagePanelView.preferredHeight(for: cachedPreferences)),
                             background: .dark),
                  named: "02-detail-440x552-dark-a-cached.png")

        // 3. 440 × 330, light, only the two ChatGPT cards.
        livePreferences.showDeepSeek = false
        livePreferences.showCommandCode = false
        XCTAssertEqual(UsagePanelView.preferredHeight(for: livePreferences), 330)
        try write(try render(UsagePanelView(model: live, preferences: livePreferences),
                             size: CGSize(width: DetailPageLayout.pageWidth,
                                          height: UsagePanelView.preferredHeight(for: livePreferences)),
                             background: .light),
                  named: "03-detail-440x330-light.png")
    }

    func testRenderChatGPTCardStates() throws {
        // 4a. Both windows unknown: grey rails with a centred `?` and 时间未知.
        let unknown = CodexProfileViewState(profile: .chatGPTA,
                                            display: .unavailable(.rpcFailed(.other)),
                                            connectionState: .disconnected,
                                            account: nil,
                                            isRefreshing: false, isFiring: false, fireResult: nil)
        // 4b. Both reset times already reached: emptied rails and 等待刷新.
        let arrived = snapshot(fiveHourPercent: 40, weeklyPercent: 8,
                               fiveHourRemaining: -60, weeklyRemaining: -3600)
        let arrivedState = state(.chatGPTB, display: .live(arrived), email: "demo-b@example.com",
                                 fireResult: .requestSucceededWindowUnchanged)

        let stem = VStack(alignment: .leading, spacing: 8) {
            Text("未知重置时间（灰色轨道 + 中央 ?）").font(.system(size: 9)).foregroundStyle(.secondary)
            CodexProfileCard(state: unknown)
            Text("已到重置时间（空轨道 + 等待刷新）").font(.system(size: 9)).foregroundStyle(.secondary)
            CodexProfileCard(state: arrivedState)
            Text("缓存（轨道变淡）").font(.system(size: 9)).foregroundStyle(.secondary)
            CodexProfileCard(state: state(.chatGPTA,
                                          display: .stale(snapshot(fiveHourPercent: 62, weeklyPercent: 31),
                                                          .rpcFailed(.timedOut(method: "account/rateLimits/read"))),
                                          email: "demo@example.com"))
            Text("刷新前 / 点火中").font(.system(size: 9)).foregroundStyle(.secondary)
            CodexProfileCard(state: CodexProfileViewState(profile: .chatGPTA,
                                                          display: .live(snapshot(fiveHourPercent: 78, weeklyPercent: 42)),
                                                          connectionState: .connected,
                                                          account: account("demo@example.com"),
                                                          isRefreshing: false, isFiring: true,
                                                          fireResult: nil))
        }
        .padding(12)
        try write(try render(stem, size: nil, background: .light, scale: 2),
                  named: "04-chatgpt-card-states-light.png")
    }

    func testRenderCommandCodeCard() throws {
        func dec(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }

        func usage(fiveHourRemaining: String, fiveHourUsed: String) -> ProviderUsage {
            ProviderUsage(
                windows: [
                    ProviderUsageWindow(kind: .fiveHour, used: dec(fiveHourUsed), limit: dec("4.00"),
                                        remaining: dec(fiveHourRemaining),
                                        resetsAt: anchor.addingTimeInterval(2 * 3600 + 13 * 60)),
                    ProviderUsageWindow(kind: .weekly, used: dec("4.00"), limit: dec("20.00"),
                                        remaining: dec("16.00"),
                                        resetsAt: anchor.addingTimeInterval(3 * 86400)),
                    ProviderUsageWindow(kind: .billingPeriod, used: dec("2.75"), limit: dec("10.00"),
                                        remaining: dec("7.25"), resetsAt: nil),
                ],
                summary: ProviderUsageSummary(totalTokens: 12_345, inputTokens: 8_000, outputTokens: 4_345,
                                              totalRuns: 42, completedRuns: 40, failedRuns: 2,
                                              successRate: dec("95.24"), totalCostUSD: dec("1.234"),
                                              periodBasis: .billingPeriod),
                planName: "individual-go",
                billingPeriodEnd: anchor.addingTimeInterval(12 * 86400),
                billingPeriodStart: anchor.addingTimeInterval(-18 * 86400))
        }

        let full = ProviderReport(platform: .commandcode, accountID: "fixture",
                                  balances: [], usage: usage(fiveHourRemaining: "3.00", fiveHourUsed: "1.00"),
                                  lastSuccessAt: anchor, connection: .connected,
                                  isLive: true, error: nil, consoleURL: nil)
        let consumed = ProviderReport(platform: .commandcode, accountID: "fixture",
                                      balances: [], usage: usage(fiveHourRemaining: "1.00", fiveHourUsed: "3.00"),
                                      lastSuccessAt: anchor, connection: .connected,
                                      isLive: true, error: nil, consoleURL: nil)
        // No billing period start: the monthly rail must stay neutral and unmarked.
        let noStart = ProviderReport(platform: .commandcode, accountID: "fixture",
                                     balances: [],
                                     usage: ProviderUsage(windows: usage(fiveHourRemaining: "3.00", fiveHourUsed: "1.00").windows,
                                                          summary: nil, planName: nil,
                                                          billingPeriodEnd: anchor.addingTimeInterval(12 * 86400)),
                                     lastSuccessAt: anchor, connection: .connected,
                                     isLive: true, error: nil, consoleURL: nil)
        let missing = ProviderReport(platform: .commandcode, accountID: "fixture",
                                     balances: [], usage: ProviderUsage(windows: [], summary: nil),
                                     lastSuccessAt: nil, connection: .unavailable,
                                     isLive: false, error: .other, consoleURL: nil)

        let stem = VStack(alignment: .leading, spacing: 8) {
            Text("剩余 3.00 / 4.00（亮色长）").font(.system(size: 9)).foregroundStyle(.secondary)
            CommandCodeOverviewCard(report: full, openSettings: {}, now: anchor)
            Text("剩余 1.00 / 4.00（亮色从右向左收缩）").font(.system(size: 9)).foregroundStyle(.secondary)
            CommandCodeOverviewCard(report: consumed, openSettings: {}, now: anchor)
            Text("缺少计费周期开始时间（月度轨道中性，不猜进度）").font(.system(size: 9)).foregroundStyle(.secondary)
            CommandCodeOverviewCard(report: noStart, openSettings: {}, now: anchor)
            Text("缺少窗口（保留块 + — + 灰色空轨道）").font(.system(size: 9)).foregroundStyle(.secondary)
            CommandCodeOverviewCard(report: missing, openSettings: {}, now: anchor)
        }
        .padding(12)
        try write(try render(stem, size: nil, background: .light, scale: 2),
                  named: "05-commandcode-cards-light.png")
    }

    // MARK: Rendering helpers

    private enum Background {
        case light, dark
        var color: Color {
            switch self {
            case .light: return Color(red: 0.96, green: 0.96, blue: 0.96)
            case .dark: return Color(red: 0.13, green: 0.13, blue: 0.13)
            }
        }
        var appearance: NSAppearance.Name {
            switch self {
            case .light: return .aqua
            case .dark: return .darkAqua
            }
        }
    }

    private func render<V: View>(_ view: V, size: CGSize?, background: Background, scale: CGFloat = 2) throws -> Data {
        let hosted = view
            .environment(\.colorScheme, background == .dark ? .dark : .light)
            .background(background.color)
        let hosting = NSHostingView(rootView: hosted)
        hosting.appearance = NSAppearance(named: background.appearance)
        hosting.frame = NSRect(origin: .zero, size: size ?? CGSize(width: 10, height: 10))
        let target = size ?? hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: target)
        hosting.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: Int(target.width * scale),
                                                 pixelsHigh: Int(target.height * scale),
                                                 bitsPerSample: 8,
                                                 samplesPerPixel: 4,
                                                 hasAlpha: true,
                                                 isPlanar: false,
                                                 colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0,
                                                 bitsPerPixel: 0))
        rep.size = target
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func write(_ data: Data, named name: String) throws {
        let directory = try MenuBarEvidenceRenderTests.evidenceDirectory()
        try data.write(to: directory.appendingPathComponent(name))
    }

    // MARK: Stubs

    private final class FixtureCodexClient: CodexAppServerProviding {
        let account: CodexAccount?
        let snapshot: UsageSnapshot?
        let error: UsageError?
        var isTransportRunning = true

        init(account: CodexAccount?, snapshot: UsageSnapshot?, error: UsageError?) {
            self.account = account
            self.snapshot = snapshot
            self.error = error
        }

        func start() throws {}
        func handshake(timeout: TimeInterval) throws {}
        func readRateLimits(timeout: TimeInterval) throws -> UsageSnapshot {
            if let error { throw error }
            guard let snapshot else { throw UsageError.rpcFailed(.other) }
            return snapshot
        }
        func readAccount(timeout: TimeInterval) throws -> CodexAccount? { account }
        func stop() { isTransportRunning = false }
    }

    private final class FixtureReading: ProviderReading {
        let platform: ProviderPlatform
        var isConfigured: Bool { true }
        var isAutomaticRefreshEnabled: Bool { true }
        private let result: ProviderReadResult

        init(platform: ProviderPlatform, result: ProviderReadResult) {
            self.platform = platform
            self.result = result
        }

        func read() async throws -> ProviderReadResult { result }
        func disconnect() throws {}
    }
}

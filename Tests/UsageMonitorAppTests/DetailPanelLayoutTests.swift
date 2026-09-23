import XCTest
import AppKit
import SwiftUI
import UsageMonitorCore
@testable import UsageMonitorApp

/// Detail-page geometry, structure and card semantics under the 1.4.1 visual specification.
///
/// The preferred page is a 440 pt single column. A scroll region is introduced only when the
/// available viewport is shorter than that preferred page.
@MainActor
final class DetailPanelLayoutTests: XCTestCase {

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suiteName = "UsageMonitorAppTests.\(label)." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeModel(_ label: String = "layout",
                           fireService: ChatGPTFireService = ChatGPTFireService()) -> UsageViewModel {
        let defaults = makeDefaults(label)
        let cache = UsageCache(userDefaults: defaults)
        let coordinator = CodexProfilesCoordinator { profile in
            UsageService(factory: { throw UsageError.appServerStartupFailed(.launchFailed) },
                         cache: cache,
                         profileID: profile.id)
        }
        let engine = ProviderRefreshEngine(readers: [], cache: ProviderCache(userDefaults: defaults))
        return UsageViewModel(coordinator: coordinator,
                              providerEngine: engine,
                              menuBarPreferences: MenuBarPreferences(defaults: defaults),
                              fireService: fireService)
    }

    // MARK: §11.2 Page size

    func testPageIsASingleFourHundredFortyPointColumn() {
        XCTAssertEqual(DetailPageLayout.pageWidth, 440)
        XCTAssertEqual(UsagePanelView.pageWidth, 440)
        XCTAssertEqual(DetailPageLayout.margin, 12)
        XCTAssertEqual(DetailPageLayout.contentWidth, 416)
        XCTAssertEqual(DetailPageLayout.headerHeight, 36)
        XCTAssertEqual(DetailPageLayout.rowSpacing, 8)
    }

    func testTheFourPreferredPageHeights() {
        let preferences = DetailPreferences(defaults: makeDefaults("DetailPanelLayout"))
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 801)

        preferences.showDeepSeek = false
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 721, "only Command Code")

        preferences.showCommandCode = false
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 432, "neither service card")

        preferences.showDeepSeek = true
        XCTAssertEqual(UsagePanelView.preferredHeight(for: preferences), 512, "only DeepSeek")
    }

    func testTheFourPreferredPageHeightsMatchTheRowArithmetic() {
        XCTAssertEqual(DetailPageLayout.pageHeight(showDeepSeek: true, showCommandCode: true), 801)
        XCTAssertEqual(DetailPageLayout.pageHeight(showDeepSeek: false, showCommandCode: true), 721)
        XCTAssertEqual(DetailPageLayout.pageHeight(showDeepSeek: true, showCommandCode: false), 512)
        XCTAssertEqual(DetailPageLayout.pageHeight(showDeepSeek: false, showCommandCode: false), 432)
    }

    // MARK: §11.2 Row geometry

    func testCardsShareOneColumnAndNeverOverlap() {
        for (showDeepSeek, showCommandCode) in [(true, true), (false, true), (true, false), (false, false)] {
            let rows = DetailPageLayout.rows(showDeepSeek: showDeepSeek, showCommandCode: showCommandCode)
            let cards = rows.filter { $0.kind != .header }
            XCTAssertEqual(rows.first?.kind, .header)
            XCTAssertEqual(cards.map(\.kind), expectedCardOrder(showDeepSeek: showDeepSeek,
                                                                showCommandCode: showCommandCode))

            for row in rows {
                XCTAssertEqual(row.frame.minX, DetailPageLayout.margin, "\(row.kind) must share the left edge")
                XCTAssertEqual(row.frame.width, DetailPageLayout.contentWidth,
                               "\(row.kind) must be exactly one content width")
            }
            for (previous, next) in zip(rows, rows.dropFirst()) {
                XCTAssertLessThan(previous.frame.maxY, next.frame.minY,
                                  "\(previous.kind) and \(next.kind) must not touch")
            }
        }
    }

    func testCardHeightsAreTheSpecifiedOnes() {
        let rows = DetailPageLayout.rows(showDeepSeek: true, showCommandCode: true)
        let heights = Dictionary(uniqueKeysWithValues: rows.map { ($0.kind, $0.frame.height) })
        XCTAssertEqual(heights[.header], 36)
        XCTAssertEqual(heights[.chatGPTA], 178)
        XCTAssertEqual(heights[.chatGPTB], 178)
        XCTAssertEqual(heights[.deepSeek], 72)
        XCTAssertEqual(heights[.commandCode], 281)
    }

    private func expectedCardOrder(showDeepSeek: Bool, showCommandCode: Bool) -> [DetailPageLayout.Kind] {
        var kinds: [DetailPageLayout.Kind] = [.chatGPTA, .chatGPTB]
        if showDeepSeek { kinds.append(.deepSeek) }
        if showCommandCode { kinds.append(.commandCode) }
        return kinds
    }

    func testCardSizesMatchTheSpecification() {
        XCTAssertEqual(CodexProfileCard.size, CGSize(width: 416, height: 178))
        XCTAssertEqual(CodexProfileCard.contentPadding, 12)
        XCTAssertEqual(CodexProfileCard.headerHeight, 34)
        XCTAssertEqual(CodexProfileCard.accountRowHeight, 16)
        XCTAssertEqual(CodexProfileCard.rowSpacing, 4)
        XCTAssertEqual(CodexProfileCard.headerToWindowSpacing, 12)
        XCTAssertEqual(CodexProfileCard.windowBlockHeight, 32)
        XCTAssertEqual(CodexProfileCard.windowGroupSpacing, 10)
        XCTAssertEqual(CodexProfileCard.footerHeight, 16)
        XCTAssertEqual(CodexProfileCard.footerSpacing, 12)
        XCTAssertEqual(CodexProfileCard.labelWidth, 50)
        XCTAssertEqual(CodexProfileCard.valueWidth, 102)
        XCTAssertEqual(CodexProfileCard.quotaTrackHeight, 6)
        XCTAssertEqual(CodexProfileCard.logoSize, 28)
        XCTAssertEqual(CodexProfileCard.fireButtonWidth, 76)
        XCTAssertEqual(CodexProfileCard.fireButtonHeight, 22)
        XCTAssertEqual(ProviderTimeBar.height, 3)
        XCTAssertEqual(ProviderTimeBar.segmentGap, 2)
        XCTAssertEqual(DeepSeekOverviewCard.size, CGSize(width: 416, height: 72))
        XCTAssertEqual(DeepSeekOverviewCard.logoSize, 34)
        XCTAssertEqual(CommandCodeOverviewCard.size, CGSize(width: 416, height: 281))
        XCTAssertEqual(CommandCodeOverviewCard.windowGroupSpacing, 10)
        XCTAssertEqual(CommandCodeOverviewCard.headerToWindowSpacing, 12)
        XCTAssertEqual(CommandCodeOverviewCard.quotaToSummarySpacing, 12)
        XCTAssertEqual(CommandCodeOverviewCard.summaryToFooterSpacing, 12)
        XCTAssertEqual(CommandCodeOverviewCard.valueWidth, 116)
        XCTAssertEqual(CommandCodeOverviewCard.footerHeight, 16)
        XCTAssertEqual(CommandCodeOverviewCard.fireButtonWidth, 76)
    }

    func testFireDialogCopyIsTheFixedWording() {
        XCTAssertEqual(CodexProfileCard.confirmationTitle, "启动 5 小时额度窗口？")
        XCTAssertEqual(CodexProfileCard.confirmationMessage,
                       "将通过该账号执行一次真实 Codex 请求，会消耗少量额度。Minget 不会读取账号认证文件。")
        XCTAssertEqual(CodexProfileCard.confirmButtonTitle, "确认点火")
        XCTAssertEqual(CodexProfileCard.cancelButtonTitle, "取消")
        XCTAssertEqual(CodexProfileCard.fireButtonTitle, "5 小时点火")
        XCTAssertEqual(CodexProfileCard.fireButtonRunningTitle, "点火中…")
        XCTAssertEqual(CommandCodeOverviewCard.confirmationTitle, "启动 Command Code 5 小时额度窗口？")
        XCTAssertEqual(CommandCodeOverviewCard.confirmationMessage,
                       "将把钥匙串中的 Command Code Key 交给官方 CLI 执行一次最小模型请求，会消耗少量额度。输出不会保存。")
        XCTAssertEqual(CommandCodeOverviewCard.confirmButtonTitle, "确认点火")
        XCTAssertEqual(CommandCodeOverviewCard.cancelButtonTitle, "取消")
        XCTAssertEqual(CommandCodeOverviewCard.fireButtonTitle, "5 小时点火")
        XCTAssertEqual(CommandCodeOverviewCard.fireButtonRunningTitle, "点火中…")
    }

    // MARK: §4.2 Scroll only when the viewport is shorter than preferred

    func testDetailPageUsesNoScrollAtItsPreferredHeight() {
        let preferences = DetailPreferences(defaults: makeDefaults("DetailPanelLayout.NoScroll"))
        let model = makeModel()

        for (showDeepSeek, showCommandCode) in [(true, true), (false, true), (true, false), (false, false)] {
            preferences.showDeepSeek = showDeepSeek
            preferences.showCommandCode = showCommandCode

            let hosting = NSHostingView(rootView: UsagePanelView(model: model, preferences: preferences,
                                                                  maxHeight: UsagePanelView.preferredHeight(for: preferences)))
            hosting.frame = NSRect(x: 0, y: 0,
                                   width: DetailPageLayout.pageWidth,
                                   height: UsagePanelView.preferredHeight(for: preferences))
            hosting.layoutSubtreeIfNeeded()

            XCTAssertFalse(containsScrollContainer(hosting),
                           "\(showDeepSeek)/\(showCommandCode): preferred page should not scroll")
        }
    }

    func testDetailPageAddsOneScrollRegionWhenViewportIsShort() {
        let preferences = DetailPreferences(defaults: makeDefaults("DetailPanelLayout.Short"))
        let model = makeModel("short")
        let hosting = NSHostingView(rootView: UsagePanelView(model: model,
                                                              preferences: preferences,
                                                              maxHeight: 520))
        hosting.frame = NSRect(x: 0, y: 0, width: DetailPageLayout.pageWidth, height: 520)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertTrue(containsScrollContainer(hosting))
    }

    func testCardsFitTheirFixedFramesWithoutClipping() {
        let snapshot = UsageSnapshot(fiveHour: window(.fiveHour, remainingPercent: 66),
                                     weekly: window(.weekly, remainingPercent: 17),
                                     fetchedAt: Date(), source: .codexAppServer)
        let state = CodexProfileViewState(profile: .chatGPTA,
                                          display: .live(snapshot),
                                          connectionState: .connected,
                                          identity: .confirmed(CodexAccount(kind: .chatgpt, email: "demo@example.com", planType: "plus")),
                                          isRefreshing: false, isFiring: false, fireResult: nil)

        let hosting = NSHostingView(rootView: CodexProfileCard(state: state))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.fittingSize, CodexProfileCard.size,
                       "the card must lay out at exactly its declared size")
        XCTAssertFalse(containsScrollContainer(hosting))
    }

    func testSettingsPageUsesOneBoundedScrollRegionForExtensibleSchedules() {
        let model = makeModel()
        let view = MingetSettingsView(model: model,
                                      preferences: DetailPreferences(defaults: makeDefaults("Settings.NoScroll")),
                                      menuBarPreferences: MenuBarPreferences(defaults: makeDefaults("Settings.prefs")),
                                      onQuit: {})
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: MingetSettingsView.pageSize)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertTrue(containsScrollContainer(hosting))
        XCTAssertEqual(MingetSettingsView.pageSize, CGSize(width: 520, height: 700))
    }

    // MARK: §11.3 ChatGPT cards

    private func window(_ kind: RateLimitWindow.Kind, remainingPercent: Double,
                        remaining: TimeInterval = 4 * 3600) -> RateLimitWindow {
        let duration = kind == .fiveHour ? 300 : 10_080
        return RateLimitWindow(kind: kind, windowDurationMinutes: duration,
                               usedPercent: 100 - remainingPercent, remainingPercent: remainingPercent,
                               resetsAt: Date().addingTimeInterval(remaining))
    }

    func testEachWindowBlockHasASegmentedResetRailOfTheRightSize() {
        let fiveHour = ResetTimeModel.progress(expected: .fiveHour,
                                               window: window(.fiveHour, remainingPercent: 66),
                                               now: Date())
        let weekly = ResetTimeModel.progress(expected: .weekly,
                                             window: window(.weekly, remainingPercent: 17, remaining: 3 * 86400),
                                             now: Date())

        let fiveHourRail = CodexProfileCard.timeProgress(fiveHour)
        let weeklyRail = CodexProfileCard.timeProgress(weekly)
        XCTAssertEqual(fiveHourRail.segmentCount, 5, "five-hour rail has five segments")
        XCTAssertEqual(weeklyRail.segmentCount, 7, "weekly rail has seven segments")
    }

    func testUnknownArrivedAndCachedStatesRenderAsSpecified() {
        let now = Date()

        // Unknown: no window at all.
        let unknown = ResetTimeModel.progress(expected: .fiveHour, window: nil, now: now)
        XCTAssertEqual(CodexProfileCard.timeProgress(unknown), .unavailable)
        XCTAssertEqual(CodexProfileCard.resetValueText(unknown, window: nil), "时间未知")
        XCTAssertEqual(CodexProfileCard.quotaValueText(nil), "剩余 —")

        // Arrived: the reported reset has passed.
        let arrived = ResetTimeModel.progress(expected: .fiveHour,
                                              window: window(.fiveHour, remainingPercent: 10, remaining: -60),
                                              now: now)
        XCTAssertEqual(CodexProfileCard.timeProgress(arrived), .arrived)
        XCTAssertEqual(CodexProfileCard.resetValueText(arrived, window: window(.fiveHour, remainingPercent: 10)),
                       "等待刷新")

        // live: an exact local reset moment.
        let activeWindow = window(.fiveHour, remainingPercent: 66)
        let active = ResetTimeModel.progress(expected: .fiveHour, window: activeWindow, now: now)
        XCTAssertEqual(CodexProfileCard.timeProgress(active).segmentCount, 5)
        XCTAssertEqual(CodexProfileCard.resetValueText(active, window: activeWindow),
                       UsageFormatting.resetPointText(activeWindow))
    }

    func testTheTwoProfileCardsReadTheirOwnSnapshots() {
        let model = makeModel()
        XCTAssertEqual(model.profileStates.count, 2)

        let aSnapshot = UsageSnapshot(fiveHour: window(.fiveHour, remainingPercent: 66),
                                      weekly: window(.weekly, remainingPercent: 17),
                                      fetchedAt: Date(), source: .codexAppServer)
        let bSnapshot = UsageSnapshot(fiveHour: window(.fiveHour, remainingPercent: 12),
                                      weekly: window(.weekly, remainingPercent: 90),
                                      fetchedAt: Date(), source: .codexAppServer)
        let a = CodexProfileViewState(profile: .chatGPTA, display: .live(aSnapshot),
                                      connectionState: .connected,
                                      identity: .confirmed(CodexAccount(kind: .chatgpt, email: "a@example.com", planType: "plus")),
                                      isRefreshing: false, isFiring: false, fireResult: nil)
        let b = CodexProfileViewState(profile: .chatGPTB, display: .live(bSnapshot),
                                      connectionState: .connected,
                                      identity: .confirmed(CodexAccount(kind: .chatgpt, email: "b@example.com", planType: "pro")),
                                      isRefreshing: false, isFiring: false,
                                      fireResult: .requestSucceededResetUnchanged)

        XCTAssertEqual(a.snapshot?.fiveHour?.remainingPercent, 66)
        XCTAssertEqual(b.snapshot?.fiveHour?.remainingPercent, 12)
        XCTAssertNotEqual(a.displayEmail, b.displayEmail)
        XCTAssertNil(a.fireResult, "account A has no result")
        XCTAssertEqual(b.fireResult, .requestSucceededResetUnchanged, "account B keeps its own result")
    }

    func testTheTwoFireButtonsNeverShareState() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minget-fire-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("codex-wait")
        try """
        #!/usr/bin/env python3
        import os, time
        open(os.environ["MINGET_FIRE_STARTED"], "a").write(str(os.getpid()) + "\\n")
        release = os.environ["MINGET_FIRE_RELEASE"]
        for _ in range(600):
            if os.path.exists(release):
                break
            time.sleep(0.05)
        sys.exit(0)
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let started = directory.appendingPathComponent("started.txt").path
        let release = directory.appendingPathComponent("release.txt").path
        let fireService = ChatGPTFireService(locator: { _ in executable },
                                             environment: ["PATH": "/usr/bin:/bin",
                                                           "MINGET_FIRE_STARTED": started,
                                                           "MINGET_FIRE_RELEASE": release],
                                             timeout: 30,
                                             workingDirectoryBase: directory)

        let model = makeModel(fireService: fireService)
        XCTAssertFalse(model.profileStates.contains { $0.isFiring })

        model.fire(profileID: "chatgpt-a")
        let startedDeadline = Date().addingTimeInterval(5)
        while Date() < startedDeadline, startedLineCount(started) < 1 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(model.profileState("chatgpt-a")?.isFiring ?? false)
        XCTAssertFalse(model.profileState("chatgpt-b")?.isFiring ?? true,
                       "the other account's button must stay idle")

        model.fire(profileID: "chatgpt-a")
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(startedLineCount(started), 1, "a repeated click must not launch a second request")

        FileManager.default.createFile(atPath: release, contents: Data())
        let finishDeadline = Date().addingTimeInterval(10)
        while Date() < finishDeadline, model.profileState("chatgpt-a")?.isFiring ?? false {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(model.profileState("chatgpt-a")?.isFiring ?? true)
        XCTAssertNil(model.profileState("chatgpt-b")?.fireResult)
    }

    // MARK: §11.4 Command Code

    private func dec(_ raw: String) -> Decimal {
        Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func ccWindow(kind: ProviderUsageWindow.Kind,
                          used: String?, limit: String?, remaining: String?,
                          resetsAt: Date? = nil) -> ProviderUsageWindow {
        ProviderUsageWindow(kind: kind,
                            used: used.map(dec), limit: limit.map(dec),
                            remaining: remaining.map(dec), resetsAt: resetsAt)
    }

    func testCommandCodeTrackShowsRemainingNotUsage() {
        let window = ccWindow(kind: .fiveHour, used: "1", limit: "4", remaining: "3")
        XCTAssertEqual(try XCTUnwrap(window.remainingFraction), 0.75, accuracy: 0.0001,
                       "the track must show 3/4 remaining, never 1/4 used")
    }

    func testTheRemainingTrackShrinksAsCreditIsConsumed() {
        let full = ccWindow(kind: .fiveHour, used: "1", limit: "4", remaining: "3")
        let used = ccWindow(kind: .fiveHour, used: "3", limit: "4", remaining: "1")
        XCTAssertGreaterThan(try XCTUnwrap(full.remainingFraction),
                             try XCTUnwrap(used.remainingFraction),
                             "3 remaining must draw a longer bright region than 1 remaining")
    }

    func testRemainingIsDerivedFromLimitMinusUsedWhenTheServiceOmitsIt() {
        let window = ccWindow(kind: .weekly, used: "5", limit: "20", remaining: nil)
        XCTAssertEqual(window.effectiveRemaining, dec("15"))
        XCTAssertEqual(try XCTUnwrap(window.remainingFraction), 0.75, accuracy: 0.0001)
    }

    func testMissingValuesNeverBecomeZero() {
        let noLimit = ccWindow(kind: .weekly, used: "5", limit: nil, remaining: nil)
        XCTAssertNil(noLimit.effectiveRemaining)
        XCTAssertNil(noLimit.remainingFraction)
        XCTAssertEqual(CommandCodeCardPresentation.quotaText(noLimit), "—",
                       "a used-only value cannot be presented as a remaining balance")

        XCTAssertEqual(CommandCodeCardPresentation.quotaText(nil), "—")
        XCTAssertEqual(CommandCodeCardPresentation.quotaText(ccWindow(kind: .weekly, used: nil, limit: nil, remaining: nil)),
                       "—")
    }

    func testCommandCodeQuotaTextUsesTheFixedWording() {
        let window = ccWindow(kind: .fiveHour, used: "1", limit: "4", remaining: "3")
        XCTAssertEqual(CommandCodeCardPresentation.quotaText(window), "$3.00 / $4.00")

        // A computable remaining without a limit drops the percentage rather than inventing one.
        let remainingOnly = ccWindow(kind: .fiveHour, used: nil, limit: nil, remaining: "3")
        XCTAssertEqual(CommandCodeCardPresentation.quotaText(remainingOnly), "$3.00 / —")

        let limitOnly = ccWindow(kind: .fiveHour, used: nil, limit: "4", remaining: nil)
        XCTAssertEqual(CommandCodeCardPresentation.quotaText(limitOnly), "— / $4.00")
    }

    func testCommandCodeTimeRailsAreFiveSevenAndContinuous() {
        let now = Date()
        let fiveHour = ProviderTimeModel.progress(kind: .fiveHour,
                                                  window: ccWindow(kind: .fiveHour, used: "1", limit: "4",
                                                                   remaining: "3", resetsAt: now.addingTimeInterval(2 * 3600)),
                                                  billingPeriodStart: nil, billingPeriodEnd: nil, now: now)
        XCTAssertEqual(fiveHour.progress.segmentCount, 5)

        let weekly = ProviderTimeModel.progress(kind: .weekly,
                                                window: ccWindow(kind: .weekly, used: "1", limit: "20",
                                                                 remaining: "19", resetsAt: now.addingTimeInterval(3 * 86400)),
                                                billingPeriodStart: nil, billingPeriodEnd: nil, now: now)
        XCTAssertEqual(weekly.progress.segmentCount, 7)

        let monthly = ProviderTimeModel.progress(kind: .billingPeriod,
                                                 window: ccWindow(kind: .billingPeriod, used: "2", limit: "10",
                                                                  remaining: "8", resetsAt: nil),
                                                 billingPeriodStart: now.addingTimeInterval(-12 * 86400),
                                                 billingPeriodEnd: now.addingTimeInterval(12 * 86400),
                                                 now: now)
        XCTAssertEqual(monthly.progress.segmentCount, 0, "the monthly cycle is one continuous bar")
        if case .continuous(let fraction) = monthly.progress {
            XCTAssertEqual(fraction, 0.5, accuracy: 0.0001)
        } else {
            XCTFail("expected a continuous monthly bar, got \(monthly.progress)")
        }
    }

    func testMonthlyProgressIsNotInventedWithoutAStartDate() {
        let now = Date()
        let end = now.addingTimeInterval(12 * 86400)

        let endOnly = ProviderTimeModel.progress(kind: .billingPeriod,
                                                 window: ccWindow(kind: .billingPeriod, used: "2", limit: "10", remaining: "8"),
                                                 billingPeriodStart: nil, billingPeriodEnd: end, now: now)
        XCTAssertEqual(endOnly.progress, .unavailable, "no start means no honest fraction to draw")
        XCTAssertEqual(CommandCodeCardPresentation.timeText(kind: .billingPeriod,
                                                            window: nil,
                                                            usage: ProviderUsage(windows: [], summary: nil, billingPeriodEnd: end),
                                                            outcome: endOnly, now: now),
                       "时间未知")

        let reversed = ProviderTimeModel.progress(kind: .billingPeriod,
                                                  window: nil,
                                                  billingPeriodStart: end, billingPeriodEnd: now, now: now)
        XCTAssertEqual(reversed.progress, .unavailable)
    }

    func testCommandCodeTimeTextUsesTheFixedWording() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(2 * 3600 + 13 * 60)
        let window = ccWindow(kind: .fiveHour, used: "1", limit: "4", remaining: "3", resetsAt: resetsAt)
        let outcome = ProviderTimeModel.progress(kind: .fiveHour, window: window,
                                                 billingPeriodStart: nil, billingPeriodEnd: nil, now: now)
        XCTAssertEqual(CommandCodeCardPresentation.timeText(kind: .fiveHour, window: window, usage: nil,
                                                            outcome: outcome, now: now),
                       UsageFormatting.shortDateTime(resetsAt))

        let monthlyEnd = now.addingTimeInterval(12 * 86400)
        let usage = ProviderUsage(windows: [], summary: nil, billingPeriodEnd: monthlyEnd)
        let monthly = ProviderTimeModel.progress(kind: .billingPeriod, window: nil,
                                                 billingPeriodStart: now.addingTimeInterval(-5 * 86400),
                                                 billingPeriodEnd: monthlyEnd, now: now)
        XCTAssertEqual(CommandCodeCardPresentation.timeText(kind: .billingPeriod, window: nil, usage: usage,
                                                            outcome: monthly, now: now),
                       "12天 · \(UsageFormatting.shortDate(monthlyEnd))")

        let arrived = ProviderTimeModel.progress(kind: .fiveHour,
                                                 window: ccWindow(kind: .fiveHour, used: "1", limit: "4", remaining: "3",
                                                                  resetsAt: now.addingTimeInterval(-60)),
                                                 billingPeriodStart: nil, billingPeriodEnd: nil, now: now)
        XCTAssertEqual(CommandCodeCardPresentation.timeText(kind: .fiveHour, window: nil, usage: nil,
                                                            outcome: arrived, now: now),
                       "等待刷新")
    }

    func testCommandCodeKeepsThreeQuotaRowsAndTwoGroupedSummaryLines() {
        XCTAssertEqual(CommandCodeCardPresentation.windowKinds, [.fiveHour, .weekly, .billingPeriod])
        let lines = CommandCodeCardPresentation.summaryLines(nil)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.contains("—") })
        XCTAssertEqual(lines[0], "Token — · 输入 — · 输出 — · 成本 —")
        XCTAssertEqual(lines[1], "请求 — · 成功 — · 失败 — · 成功率 —")
        XCTAssertEqual(CommandCodeCardPresentation.periodText(nil), "统计暂不可用")
        XCTAssertEqual(CommandCodeCardPresentation.label(.billingPeriod), "本月")
    }

    /// A missing summary and an unnamed statistic period are different facts and must not share
    /// one sentence (REQUIREMENTS.md §5.3).
    func testMissingSummaryAndUnknownPeriodAreWordedDifferently() {
        XCTAssertEqual(CommandCodeCardPresentation.periodText(nil), "统计暂不可用")
        XCTAssertEqual(CommandCodeCardPresentation.periodText(.unknown), "统计周期未确认")
        XCTAssertEqual(CommandCodeCardPresentation.periodText(.billingPeriod), "当前计费周期")
        XCTAssertEqual(CommandCodeCardPresentation.periodText(.last30Days), "近 30 天")

        let unknownPeriod = ProviderUsageSummary(totalTokens: 10, inputTokens: 6, outputTokens: 4,
                                                totalRuns: 2, completedRuns: 2, failedRuns: 0,
                                                successRate: dec("100"), totalCostUSD: dec("0.5"),
                                                periodBasis: .unknown)
        XCTAssertTrue(CommandCodeCardPresentation.summaryLines(unknownPeriod)[0].hasPrefix("Token 10"))
        XCTAssertFalse(CommandCodeCardPresentation.summaryLines(unknownPeriod)[0].contains("暂不可用"))
    }

    // MARK: §5.4 Cache subtitle and help text

    func testTheHeaderSubtitleFollowsTheConnectionAndPlanMatrix() {
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .connected, planName: "individual-go"),
                       "individual-go")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .connected, planName: nil), "已连接")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .stale, planName: "individual-go"),
                       "individual-go · 缓存",
                       "a cached card keeps its plan name and still says it is cached")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .stale, planName: nil), "缓存数据")

        // Everything else keeps the pre-existing fixed connection wording.
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .connecting, planName: "plan"), "正在获取")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .notConfigured, planName: nil), "未连接")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .authSuspended, planName: "plan"),
                       "需要重新连接")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .needsAuthorization, planName: nil),
                       "需要重新连接")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .unavailable, planName: "plan"), "暂不可用")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .unverified, planName: nil), "暂不可用")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .connected, planName: ""), "已连接",
                       "an empty plan name is not a plan name")
        XCTAssertEqual(CommandCodeCardPresentation.subtitle(connection: .connected,
                                                            planName: "individual-go",
                                                            planIsCached: true),
                       "individual-go · 缓存",
                       "a reused plan stays visibly cached even while credits are live")

        XCTAssertEqual(CommandCodeCardPresentation.brandSubtitle(displayName: "Command Code",
                                                                 connection: .connected,
                                                                 planName: "individual-go"),
                       "individual-go")
        XCTAssertEqual(CommandCodeCardPresentation.brandSubtitle(displayName: "Command Code $1",
                                                                 connection: .connected,
                                                                 planName: "individual-go"),
                       "Command Code · individual-go")
    }

    func testComponentCacheWordingCarriesItsOwnSuccessTime() {
        let lastSuccess = Date(timeIntervalSince1970: 1_800_000_000)
        let cached = ProviderUsageComponentFreshness(lastSuccessfulAt: lastSuccess, isLive: false)
        XCTAssertEqual(CommandCodeCardPresentation.periodText(nil, isCached: true), "缓存 · 统计暂不可用")
        XCTAssertTrue(CommandCodeCardPresentation.summaryLines(nil, isCached: true)[0]
            .hasPrefix("缓存 · Token —"))
        XCTAssertEqual(CommandCodeCardPresentation.componentCacheHelpText(name: "统计",
                                                                          freshness: cached,
                                                                          fallback: nil),
                       "统计缓存 · 上次成功 \(UsageFormatting.shortDateTime(lastSuccess))")
        XCTAssertEqual(CommandCodeCardPresentation.helpText(connection: .connected,
                                                            lastSuccessAt: nil,
                                                            planFreshness: cached),
                       "套餐缓存 · 上次成功 \(UsageFormatting.shortDateTime(lastSuccess))")
        XCTAssertEqual(CommandCodeCardPresentation.accessibilitySubtitle(connection: .connected,
                                                                        planName: "individual-go",
                                                                        lastSuccessAt: nil,
                                                                        planFreshness: cached),
                       "individual-go · 缓存，套餐缓存 · 上次成功 \(UsageFormatting.shortDateTime(lastSuccess))")
    }

    func testTheCacheHelpTextCarriesTheLastSuccessTimeOrSaysItIsUnknown() {
        let lastSuccess = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(CommandCodeCardPresentation.cacheHelpText(lastSuccessAt: lastSuccess),
                       "缓存数据 · 上次成功 \(UsageFormatting.shortDateTime(lastSuccess))")
        XCTAssertEqual(CommandCodeCardPresentation.cacheHelpText(lastSuccessAt: nil),
                       "缓存数据 · 成功时间未知")

        // The tooltip follows the same rule, and only a cached card needs the extra sentence.
        XCTAssertEqual(CommandCodeCardPresentation.helpText(connection: .stale, lastSuccessAt: lastSuccess),
                       "缓存数据 · 上次成功 \(UsageFormatting.shortDateTime(lastSuccess))")
        XCTAssertEqual(CommandCodeCardPresentation.helpText(connection: .stale, lastSuccessAt: nil),
                       "缓存数据 · 成功时间未知")
        XCTAssertFalse(CommandCodeCardPresentation.helpText(connection: .connected, lastSuccessAt: lastSuccess)
            .contains("缓存"))
    }

    func testTheAccessibilityValueRepeatsTheCacheSemantics() {
        let lastSuccess = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(CommandCodeCardPresentation.accessibilitySubtitle(connection: .stale,
                                                                        planName: "individual-go",
                                                                        lastSuccessAt: lastSuccess),
                       "individual-go · 缓存，缓存数据 · 上次成功 \(UsageFormatting.shortDateTime(lastSuccess))")
        XCTAssertEqual(CommandCodeCardPresentation.accessibilitySubtitle(connection: .connected,
                                                                        planName: "individual-go",
                                                                        lastSuccessAt: lastSuccess),
                       "individual-go",
                       "a live card does not claim to be cached")
    }

    // MARK: DeepSeek strip

    private func balance(_ currency: String?, total: String?) -> ProviderBalance {
        ProviderBalance(currency: currency,
                        total: total.map { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))! },
                        available: nil)
    }

    func testUpToThreeCurrenciesAreAllShown() {
        let strip = DeepSeekBalanceRows.strip([balance("USD", total: "1"), balance("CNY", total: "2"),
                                               balance("EUR", total: "3")])
        XCTAssertEqual(strip.amounts.map(\.currency), ["CNY", "EUR", "USD"])
        XCTAssertNil(strip.overflowText)
    }

    func testMoreThanThreeCurrenciesPutTheOverflowInTheThirdSlot() {
        let strip = DeepSeekBalanceRows.strip([balance("USD", total: "1"), balance("CNY", total: "2"),
                                               balance("EUR", total: "3"), balance("JPY", total: "4"),
                                               balance("GBP", total: "5")])
        XCTAssertEqual(strip.amounts.map(\.currency), ["CNY", "EUR"])
        XCTAssertEqual(strip.overflowCount, 3)
        XCTAssertEqual(strip.overflowText, "另有 3 个币种")
    }

    func testUnnamedCurrencyBucketSortsLast() {
        let strip = DeepSeekBalanceRows.strip([balance(nil, total: "9"), balance("USD", total: "1")])
        XCTAssertEqual(strip.amounts.map(\.currency), ["USD", nil])
    }

    // MARK: Helpers

    private func startedLineCount(_ path: String) -> Int {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
    }

    private func containsScrollContainer(_ view: NSView) -> Bool {
        if view is NSScrollView || view is NSTableView || view is NSOutlineView { return true }
        return view.subviews.contains { containsScrollContainer($0) }
    }
}

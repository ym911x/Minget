import XCTest
@testable import UsageMonitorApp
@testable import UsageMonitorCore

@MainActor
final class Interface161Tests: XCTestCase {
    func testLegacyAllMigrationIsIdempotentAndLeavesSourcePreferencesUntouched() {
        let name = "Minget161Migration." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("all", forKey: "detail.displayMode.v1")
        defaults.set("commandCode", forKey: "detail.selectedTab.v1")
        defaults.set("chatgpt-b", forKey: "menubar.source.v1")
        defaults.set(true, forKey: "detail.showGoogle")
        let first = DetailPreferences(defaults: defaults)
        XCTAssertEqual(first.selectedTab, .all)
        XCTAssertTrue(first.showGoogle)
        first.selectedTab = .google
        let second = DetailPreferences(defaults: defaults)
        XCTAssertEqual(second.selectedTab, .google)
        XCTAssertEqual(defaults.string(forKey: "menubar.source.v1"), "chatgpt-b")
        first.expandedGoogleAccounts = ["a@example.com"]
        first.selectedTab = .chatGPT
        first.selectedTab = .google
        XCTAssertEqual(first.expandedGoogleAccounts, ["a@example.com"])
    }

    func testPrimaryQuotaSelectionDoesNotSubstituteSharedGroupOrDependOnOrder() throws {
        func group(_ id: String, _ label: String) -> AntigravityQuotaGroup {
            AntigravityQuotaGroup(id: id, label: label, models: [], buckets: [])
        }
        let shared = group("shared", "Claude and GPT models")
        let primary = group("Gemini Models", "Gemini Models")
        XCTAssertEqual(QuotaPresentation.primaryGroup([shared, primary]), primary)
        XCTAssertNil(QuotaPresentation.primaryGroup([shared]))
        XCTAssertEqual(QuotaPresentation.percentage(nil), "—")
        XCTAssertEqual(QuotaPresentation.percentage(0), "0.00%")
        XCTAssertEqual(QuotaPresentation.percentage(99.8187), "99.82%")
        XCTAssertEqual(QuotaPresentation.percentage(.nan), "—")
        XCTAssertEqual(QuotaPresentation.percentage(-1), "—")
        XCTAssertNil(QuotaPresentation.fraction(.infinity))
        XCTAssertNil(QuotaPresentation.fraction(101))
        XCTAssertEqual(QuotaPresentation.fraction(0), 0)
    }

    func testMissingQuotaDoesNotEraseKnownResetOrInventRenewal() {
        let now = Date()
        let reset = now.addingTimeInterval(7200)
        let bucket = AntigravityQuotaBucket(id: "a", label: "five", window: "5h", remainingFraction: nil, resetsAt: reset)
        XCTAssertNil(bucket.rateLimitWindow)
        let progress = ResetTimeModel.progress(expected: .fiveHour, resetsAt: bucket.resetsAt, durationMinutes: 300, now: now)
        XCTAssertEqual(progress.state, .active)
        XCTAssertEqual(progress.fills.count, 5)
        XCTAssertEqual(QuotaPresentation.percentage(bucket.remainingFraction), "—")
        XCTAssertEqual(ResetTimeModel.progress(expected: .fiveHour, resetsAt: now, durationMinutes: 300, now: now).state, .arrived)
        XCTAssertEqual(QuotaPresentation.reset(now, now: now), "等待刷新")
        XCTAssertEqual(ResetTimeModel.progress(expected: .fiveHour, resetsAt: reset, durationMinutes: 10080, now: now).state, .invalid)
    }

    func testSixAccountOverviewFitsWhileSmallScreenIsCapped() {
        let name = "Minget161Size." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = DetailPreferences(defaults: defaults)
        preferences.showGoogle = true
        let preferred = UsagePanelView.preferredHeight(for: preferences, googleAccountCount: 2)
        XCTAssertLessThanOrEqual(preferred, 640)
        XCTAssertLessThanOrEqual(DetailPageLayout.viewportHeight(preferredHeight: preferred, visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 400)), 384)
        preferences.selectedTab = .google
        XCTAssertLessThanOrEqual(StatusItemController.panelSize(for: preferences).height, 640)
    }
}

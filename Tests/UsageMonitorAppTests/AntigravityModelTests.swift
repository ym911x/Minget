import XCTest
import SwiftUI
import AppKit
@testable import UsageMonitorApp
@testable import UsageMonitorCore

@MainActor
final class AntigravityModelTests: XCTestCase {
    private func account(_ id: String, email: String? = nil) -> AntigravityAccount {
        AntigravityAccount(id: id, authIndex: "index-" + id, label: "Google " + id, email: email,
                           projectID: "project-" + id, disabled: false, unavailable: false)
    }
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GoogleTests." + UUID().uuidString)!
    }
    func testGoogleMenuSelectionRestoresAndMissingGroupDoesNotPickReplacement() async {
        let defaults = isolatedDefaults()
        defaults.set("chatgpt-b", forKey: "menubar.source.v1")
        let prefs = MenuBarPreferences(defaults: defaults)
        let before = prefs.selection
        let id = "account:with/slash"
        prefs.selection = .google(id)
        prefs.googleGroupIDs[id] = "removed-group"
        let restored = MenuBarPreferences(defaults: defaults)
        XCTAssertEqual(restored.selection, .google(id))
        XCTAssertEqual(restored.googleGroupIDs[id], "removed-group")
        XCTAssertNotEqual(restored.selection, before)
        let detail = DetailPreferences(defaults: defaults)
        XCTAssertFalse(detail.showGoogle)
        detail.showGoogle = true; detail.displayMode = .byProvider; detail.selectedTab = .google
        XCTAssertEqual(detail.visibleTabs, [.all, .chatGPT, .google, .deepSeek, .commandCode])
        let two = UsagePanelView.preferredHeight(for: detail, googleAccountCount: 2)
        let one = UsagePanelView.preferredHeight(for: detail, googleAccountCount: 1)
        XCTAssertEqual(two - one, AntigravityOverviewCard.height + DetailPageLayout.rowSpacing)
        detail.showGoogle = false
        XCTAssertEqual(detail.selectedTab, .all)
    }
    func testRenderGoogleCardWithTwoPeriodsAndUnknownField() throws {
        if ProcessInfo.processInfo.environment["CI"] == "true" { throw XCTSkip("Needs macOS WindowServer") }
        let groups = try AntigravityCLIReport.parse(Data(#"{"status":"SUCCESS","num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"groups":[{"name":"Gemini","buckets":[{"id":"gemini-5h","window":"5h","name":"5 小时","remaining_fraction":0.45,"reset_time":"2026-09-30T00:00:00Z"},{"id":"gemini-weekly","window":"weekly","name":"周额度","remaining_fraction":0.8,"reset_time":"2026-10-05T00:00:00Z"}]},{"name":"Claude","buckets":[{"id":"unknown","name":"模型额度"}]}]}}}"#.utf8))
        let state = AntigravityAccountState(account: account("demo"),
                    snapshot: AntigravitySnapshot(accountIdentity: account("demo").identity, groups: groups, fetchedAt: Date()),
                    isCached: false)
        for dark in [false, true] {
            let view = VStack(alignment: .leading) {
                Text("合成数据 · 布局验证").font(.caption)
                AntigravityOverviewCard(state: state, displayName: "Google 示例账号")
            }.padding(12).frame(width: 416).background(dark ? Color.black : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
            let hosting = NSHostingView(rootView: view)
            hosting.frame.size = NSSize(width: 416, height: 310)
            hosting.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dark ? "/tmp/minget-google-card-dark.png" : "/tmp/minget-google-card-light.png"))
        }
    }

}

import XCTest
import SwiftUI
import AppKit
@testable import UsageMonitorApp
@testable import UsageMonitorCore

private actor GoogleTestReader: AntigravityReading {
    var available: [AntigravityAccount]
    var discoveryError: ProviderFailure?
    var failedIDs = Set<String>()
    var slowID: String?
    var calls = 0
    init(_ accounts: [AntigravityAccount]) { available = accounts }
    func configure(accounts: [AntigravityAccount]? = nil, error: ProviderFailure? = nil,
                   failed: Set<String> = [], slow: String? = nil) {
        if let accounts { available = accounts }
        discoveryError = error; failedIDs = failed; slowID = slow
    }
    func accounts(baseURL: String, managementKey: String) async throws -> [AntigravityAccount] {
        calls += 1
        if let discoveryError { throw discoveryError }
        return available
    }
    func quota(account: AntigravityAccount, baseURL: String, managementKey: String) async throws -> AntigravitySnapshot {
        if account.id == slowID { try await Task.sleep(nanoseconds: 250_000_000) }
        if failedIDs.contains(account.id) { throw ProviderFailure.timedOut }
        let groups = try AntigravityProvider.parseGroups(Data(#"{"groups":[{"groupId":"gemini","displayName":"Gemini","buckets":[{"window":"5h","remainingFraction":0.4}]}]}"#.utf8))
        return AntigravitySnapshot(accountIdentity: account.identity, groups: groups, fetchedAt: Date())
    }
}

@MainActor
final class AntigravityModelTests: XCTestCase {
    private func account(_ id: String, email: String? = nil) -> AntigravityAccount {
        AntigravityAccount(id: id, authIndex: "index-" + id, label: "Google " + id, email: email,
                           projectID: "project-" + id, disabled: false, unavailable: false)
    }
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GoogleTests." + UUID().uuidString)!
    }
    private func wait(_ predicate: () -> Bool, timeout: TimeInterval = 3) async {
        let until = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < until { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(predicate())
    }
    func testTwoAccountsPublishIndependentlyAndFailureKeepsOwnCache() async {
        let defaults = isolatedDefaults()
        let reader = GoogleTestReader([account("a"), account("b")])
        let model = AntigravityModel(reader: reader, credentials: InMemoryCredentialStore(), defaults: defaults)
        await reader.configure(slow: "b")
        XCTAssertTrue(model.connect(baseURL: AntigravityProvider.defaultBaseURL, key: "synthetic"))
        await wait { model.accounts.first { $0.id == "a" }?.isCached == false }
        XCTAssertTrue(model.accounts.first { $0.id == "b" }?.isFetching == true)
        await wait { !model.isRefreshing }
        await reader.configure(failed: ["b"])
        model.refresh(force: true)
        await wait { !model.isRefreshing }
        XCTAssertFalse(model.accounts[0].isCached)
        XCTAssertTrue(model.accounts[1].isCached)
        XCTAssertEqual(model.accounts[1].failure, .timedOut)
        XCTAssertEqual(model.accounts[1].snapshot?.accountIdentity, account("b").identity)
        model.stop()
    }
    func testDeletionAndReusedIDNeverInheritAnotherIdentity() async {
        let defaults = isolatedDefaults()
        let reader = GoogleTestReader([account("a", email: "old@example.test"), account("b")])
        let model = AntigravityModel(reader: reader, credentials: InMemoryCredentialStore(), defaults: defaults)
        XCTAssertTrue(model.connect(baseURL: AntigravityProvider.defaultBaseURL, key: "synthetic"))
        await wait { !model.isRefreshing }
        await reader.configure(accounts: [account("a", email: "new@example.test")], failed: ["a"])
        model.refresh(force: true)
        await wait { !model.isRefreshing }
        XCTAssertEqual(model.accounts.count, 1)
        XCTAssertNil(model.accounts[0].snapshot)
        let restored = AntigravityModel(reader: reader, credentials: InMemoryCredentialStore(), defaults: defaults)
        XCTAssertTrue(restored.accounts.isEmpty)
        model.stop()
    }
    func testOfflineCacheIsMarkedAndNewConnectionClearsItImmediately() async {
        let defaults = isolatedDefaults()
        let credentials = InMemoryCredentialStore()
        let reader = GoogleTestReader([account("a"), account("b")])
        let model = AntigravityModel(reader: reader, credentials: credentials, defaults: defaults)
        XCTAssertTrue(model.connect(baseURL: AntigravityProvider.defaultBaseURL, key: "synthetic"))
        await wait { !model.isRefreshing }
        let restored = AntigravityModel(reader: reader, credentials: credentials, defaults: defaults)
        XCTAssertEqual(restored.accounts.count, 2)
        XCTAssertTrue(restored.accounts.allSatisfy(\.isCached))
        await reader.configure(error: .networkUnreachable)
        restored.start()
        await wait { !restored.isRefreshing }
        XCTAssertTrue(restored.accounts.allSatisfy { $0.isCached && $0.failure == .networkUnreachable })
        XCTAssertTrue(restored.connect(baseURL: "http://127.0.0.1:9000", key: "replacement"))
        XCTAssertTrue(restored.accounts.isEmpty)
        await wait { !restored.isRefreshing }
        restored.stop(); model.stop()
    }
    func testConcurrentManualRequestsQueueOneFollowUpAndThrottleAutomaticReads() async {
        let reader = GoogleTestReader([account("a")])
        await reader.configure(slow: "a")
        let model = AntigravityModel(reader: reader, credentials: InMemoryCredentialStore(), defaults: isolatedDefaults())
        XCTAssertTrue(model.connect(baseURL: AntigravityProvider.defaultBaseURL, key: "synthetic"))
        model.refresh(force: false)
        model.refresh(force: true); model.refresh(force: true)
        await wait { !model.isRefreshing }
        let calls = await reader.calls
        XCTAssertEqual(calls, 2)
        model.refresh(force: false)
        try? await Task.sleep(nanoseconds: 30_000_000)
        let throttled = await reader.calls
        XCTAssertEqual(throttled, calls)
        model.refresh(force: false, afterWake: true)
        await wait { !model.isRefreshing }
        let awakened = await reader.calls
        XCTAssertEqual(awakened, calls + 1)
        model.stop()
    }
    func testRejectedCredentialPausesUntilManualReadAndNeverPersistsSecret() async {
        let defaults = isolatedDefaults()
        let reader = GoogleTestReader([account("a")])
        await reader.configure(error: .invalidCredential)
        let credentials = InMemoryCredentialStore()
        let model = AntigravityModel(reader: reader, credentials: credentials, defaults: defaults)
        XCTAssertTrue(model.connect(baseURL: AntigravityProvider.defaultBaseURL, key: "synthetic-secret-never-persist"))
        await wait { !model.isRefreshing }
        model.refresh(force: false, now: Date().addingTimeInterval(600))
        try? await Task.sleep(nanoseconds: 10_000_000)
        let paused = await reader.calls
        XCTAssertEqual(paused, 1)
        await reader.configure()
        model.refresh(force: true)
        await wait { !model.isRefreshing }
        XCTAssertEqual(model.accounts.count, 1)
        XCTAssertFalse(String(describing: defaults.dictionaryRepresentation()).contains("synthetic-secret-never-persist"))
        model.disconnect()
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNil(defaults.data(forKey: "antigravity.snapshots.v1"))
        model.stop()
    }
    func testConnectionGenerationDiscardsLateReadsAfterDisconnect() async {
        let reader = GoogleTestReader([account("a")])
        await reader.configure(slow: "a")
        let model = AntigravityModel(reader: reader, credentials: InMemoryCredentialStore(), defaults: isolatedDefaults())
        XCTAssertTrue(model.connect(baseURL: AntigravityProvider.defaultBaseURL, key: "synthetic"))
        await wait { !model.accounts.isEmpty }
        model.disconnect()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertFalse(model.isRefreshing)
        model.stop()
    }
    func testKeychainRefusalIsRememberedAndBackgroundDoesNotPrompt() async {
        let credentials = InMemoryCredentialStore()
        credentials.simulate(.deniedOrCancelled(-128), for: .antigravityManagementKey)
        let reader = GoogleTestReader([])
        let model = AntigravityModel(reader: reader, credentials: credentials, defaults: isolatedDefaults())
        model.start()
        await wait { !model.isRefreshing }
        model.refresh(force: false, now: Date().addingTimeInterval(600))
        await wait { !model.isRefreshing }
        XCTAssertEqual(credentials.loadCallCount, 1)
        XCTAssertEqual(credentials.recordedLoads[0].interaction, .disallowed)
        let calls = await reader.calls
        XCTAssertEqual(calls, 0)
        model.stop()
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
        XCTAssertEqual(detail.visibleTabs.last, .google)
        let two = UsagePanelView.preferredHeight(for: detail, googleAccountCount: 2)
        let one = UsagePanelView.preferredHeight(for: detail, googleAccountCount: 1)
        XCTAssertEqual(two - one, AntigravityOverviewCard.height + DetailPageLayout.rowSpacing)
        detail.showGoogle = false
        XCTAssertEqual(detail.selectedTab, .all)
    }
    func testRenderGoogleCardWithTwoPeriodsAndUnknownField() throws {
        if ProcessInfo.processInfo.environment["CI"] == "true" { throw XCTSkip("Needs macOS WindowServer") }
        let groups = try AntigravityProvider.parseGroups(Data(#"{"groups":[{"groupId":"gemini","displayName":"Gemini","models":["gemini-pro","gemini-flash"],"buckets":[{"window":"5h","displayName":"5 小时","remainingFraction":0.45,"resetTime":"2026-09-30T00:00:00Z"},{"window":"7d","displayName":"周额度","remainingFraction":0.8,"resetTime":"2026-10-05T00:00:00Z"}]},{"displayName":"Claude","buckets":[{"displayName":"模型额度"}]}]}"#.utf8))
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

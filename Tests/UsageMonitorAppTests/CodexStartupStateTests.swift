import XCTest
import UsageMonitorCore
@testable import UsageMonitorApp

final class CodexStartupStateTests: XCTestCase {
    private func state(_ display: UsageDisplay) -> CodexProfileViewState {
        CodexProfileViewState(profile: .chatGPTA, display: display, connectionState: .disconnected,
                              isRefreshing: false, isFiring: false, fireResult: nil)
    }
    func testStartupFailureAndMissingNodeHaveActionableLabels() {
        let missing = state(.unavailable(.codexNodeUnavailable))
        XCTAssertEqual(missing.failureText, "缺少 Node 运行环境")
        XCTAssertEqual(missing.accountPlaceholder, "本机 Codex 无法启动")
        XCTAssertTrue(missing.recoveryHint!.contains("Node"))
        let failed = state(.unavailable(.appServerStartupFailed(.launchFailed)))
        XCTAssertEqual(failed.accountPlaceholder, "本机 Codex 无法启动")
        XCTAssertNotNil(failed.recoveryHint)
        let signedOut = state(.unavailable(.codexNotSignedIn))
        XCTAssertEqual(signedOut.failureText, "Codex 未登录")
    }
    func testCachedFailureRetainsSuccessTimeAndReason() {
        let snapshot = UsageSnapshot(fiveHour: nil, weekly: nil, fetchedAt: Date().addingTimeInterval(-3600), source: .cached)
        let cached = state(.stale(snapshot, .codexNodeUnavailable))
        XCTAssertTrue(cached.isStale)
        XCTAssertNotNil(cached.lastSuccessText)
        XCTAssertEqual(cached.failureText, "缺少 Node 运行环境")
        let live = state(.live(snapshot))
        XCTAssertNil(live.failureText)
        XCTAssertNil(live.recoveryHint)
    }
}

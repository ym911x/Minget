import XCTest
@testable import UsageMonitorCore

/// Pure rules behind the 1.3.2 fire display: drift measurement, fixed wording, history
/// bounds. No service, no process, no timing.
final class FireDriftTests: XCTestCase {

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testShiftNeedsBothSidesAndNeverGoesNegative() {
        let moved = Self.start.addingTimeInterval(3600)
        XCTAssertEqual(FireWindowDrift.shift(from: Self.start, to: moved) ?? -1, 3600, accuracy: 0.001)
        XCTAssertNil(FireWindowDrift.shift(from: nil, to: moved))
        XCTAssertNil(FireWindowDrift.shift(from: Self.start, to: nil))
        XCTAssertNil(FireWindowDrift.shift(from: nil, to: nil))
        XCTAssertNil(FireWindowDrift.shift(from: moved, to: Self.start),
                      "a later read that is earlier than the before-value is not a drift")
        XCTAssertEqual(FireWindowDrift.shift(from: Self.start, to: Self.start) ?? -1, 0, accuracy: 0.001)
    }

    func testDisplayTextUsesFixedChineseUnits() {
        XCTAssertEqual(FireWindowDrift.displayText(0), "+0秒")
        XCTAssertEqual(FireWindowDrift.displayText(32), "+32秒")
        XCTAssertEqual(FireWindowDrift.displayText(59), "+59秒")
        XCTAssertEqual(FireWindowDrift.displayText(59.999), "+59秒",
                       "sub-second noise must not cross the confirmation boundary in the UI")
        XCTAssertEqual(FireWindowDrift.displayText(60), "+1分0秒")
        XCTAssertEqual(FireWindowDrift.displayText(92), "+1分32秒")
        XCTAssertEqual(FireWindowDrift.displayText(6 * 3600 + 12 * 60), "+6小时12分")
        XCTAssertEqual(FireWindowDrift.displayText(6 * 3600 + 12 * 60 + 45), "+6小时12分",
                       "hour rows keep hour-minute only, matching the card's compact suffix")
    }

    func testBoundary59Versus60StillClassifiesBySixty() {
        let before = Self.start
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: before,
                                                       previousWasLive: true,
                                                       observations: [.live(resetsAt: before.addingTimeInterval(59))]),
                       .requestSucceededResetUnchanged)
        XCTAssertEqual(FireWindowConfirmation.classify(previousReset: before,
                                                       previousWasLive: true,
                                                       observations: [.live(resetsAt: before.addingTimeInterval(60))]),
                       .requestSucceededResetAdvanced)
        XCTAssertEqual(FireWindowDrift.displayText(59), "+59秒")
        XCTAssertEqual(FireWindowDrift.displayText(60), "+1分0秒")
    }

    func testHistoryEntryLinesCarryTimeResultAndDrift() {
        let at = Date(timeIntervalSince1970: 1_786_000_000)
        let confirmed = FireHistoryEntry(result: .requestSucceededResetAdvanced,
                                         finishedAt: at,
                                         driftSeconds: 6 * 3600 + 12 * 60)
        XCTAssertTrue(confirmed.displayLine.contains("请求成功，重置时间前移"))
        XCTAssertTrue(confirmed.displayLine.contains("+6小时12分"))

        let unconfirmed = FireHistoryEntry(result: .requestSucceededResetUnavailable,
                                           finishedAt: at)
        XCTAssertTrue(unconfirmed.displayLine.contains("请求成功，重置时间未知"))
        XCTAssertFalse(unconfirmed.displayLine.contains("+"),
                       "an unconfirmed request shows the request alone, never a drift")
    }

    func testRuntimeKeepsOnlyTheLastThreeFinishes() {
        let runtime = CodexProfileRuntime(profile: .chatGPTA,
                                          service: UsageService(factory: { throw UsageError.rpcFailed(.other) }))
        for _ in 0..<4 {
            runtime.recordFireFinished(.requestSucceededResetUnchanged, driftSeconds: 10)
        }
        XCTAssertEqual(runtime.state().fireHistory.count, CodexProfileRuntime.maxFireHistory)
        XCTAssertEqual(CodexProfileRuntime.maxFireHistory, 3)
    }

    func testFreshRuntimeStartsWithNoHistory() {
        let runtime = CodexProfileRuntime(profile: .chatGPTA,
                                          service: UsageService(factory: { throw UsageError.rpcFailed(.other) }))
        XCTAssertTrue(runtime.state().fireHistory.isEmpty)
        XCTAssertNil(runtime.state().fireResult)
        XCTAssertNil(runtime.state().fireDriftSeconds)
    }
}

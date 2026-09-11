import XCTest
@testable import UsageMonitorCore

/// Round 2 non-blocking finding: the snapshot's own source is authoritative for
/// live vs cached labelling.
final class UsageDisplayTests: XCTestCase {
    let fiveHour = RateLimitWindow(kind: .fiveHour, windowDurationMinutes: 300, usedPercent: 25,
                                   remainingPercent: 75, resetsAt: Date(timeIntervalSince1970: 1_788_935_373))
    let weekly = RateLimitWindow(kind: .weekly, windowDurationMinutes: 10_080, usedPercent: 58,
                                 remainingPercent: 42, resetsAt: Date(timeIntervalSince1970: 1_789_453_767))

    func snapshot(source: UsageSource) -> UsageSnapshot {
        UsageSnapshot(fiveHour: fiveHour, weekly: weekly, fetchedAt: Date(), source: source)
    }

    func testLiveResultRendersAsLive() {
        let result = UsageService.FetchResult(snapshot: snapshot(source: .codexAppServer), isLive: true, error: nil)
        let display = UsageDisplay(fetchResult: result)
        XCTAssertFalse(display.isStale)
        XCTAssertEqual(display.snapshot?.fiveHour?.remainingPercent, 75)
        XCTAssertEqual(display.snapshot?.weekly?.windowDurationMinutes, 10_080)
        XCTAssertEqual(display.menuBarTitle, "5H 75% | W 42%")
    }

    func testCachedResultWithoutErrorIsNeverLabelledLive() {
        // isLive == false with a nil error previously looked live in the view model.
        let result = UsageService.FetchResult(snapshot: snapshot(source: .cached), isLive: false, error: nil)
        let display = UsageDisplay(fetchResult: result)
        guard case .stale(_, let error) = display else {
            return XCTFail("cached data must render as stale, got \(display)")
        }
        XCTAssertTrue(display.isStale)
        XCTAssertEqual(error.debugSummary, "rpcFailed(other)")
        // v1.0.2 requirement 4: the text is marker-free; the warning is drawn in front of it.
        XCTAssertEqual(display.menuBarTitle, "5H 75% | W 42%")
    }

    func testCachedResultWithErrorShowsTheError() {
        let result = UsageService.FetchResult(snapshot: snapshot(source: .cached),
                                              isLive: false,
                                              error: .rpcFailed(.timedOut(method: "account/rateLimits/read")))
        let display = UsageDisplay(fetchResult: result)
        guard case .stale(_, let error) = display else { return XCTFail("expected stale, got \(display)") }
        XCTAssertEqual(error, .rpcFailed(.timedOut(method: "account/rateLimits/read")))
        XCTAssertEqual(display.menuBarTitle, "5H 75% | W 42%", "no trailing marker is built into the text")
        XCTAssertEqual(MenuBarContentBuilder.attention(for: display, connectionState: .connected), .warning)
    }

    func testFailedFetchWithoutCacheIsUnavailable() {
        let display = UsageDisplay(error: .codexNotSignedIn, cached: nil)
        XCTAssertNil(display.snapshot)
        XCTAssertFalse(display.isStale)
        XCTAssertEqual(UsageFormatting.errorText(.codexNotSignedIn).contains("Codex is not signed in"), true)
        XCTAssertFalse(display.isStale)
    }

    func testFailedFetchWithCacheIsStale() {
        let display = UsageDisplay(error: .codexNotSignedIn, cached: snapshot(source: .cached))
        guard case .stale(_, let error) = display else { return XCTFail("expected stale, got \(display)") }
        XCTAssertEqual(error, .codexNotSignedIn)
        XCTAssertEqual(display.menuBarTitle, "5H 75% | W 42%")
        XCTAssertEqual(MenuBarContentBuilder.attention(for: display, connectionState: .disconnected), .warning)
    }

    func testLiveFlagWithoutLiveSourceIsTreatedAsCached() {
        // Defensive: a result claiming live while the snapshot says cached stays stale.
        let result = UsageService.FetchResult(snapshot: snapshot(source: .cached), isLive: true, error: nil)
        XCTAssertTrue(UsageDisplay(fetchResult: result).isStale)
    }
}

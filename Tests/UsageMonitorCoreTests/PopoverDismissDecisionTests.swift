import XCTest
import CoreGraphics
@testable import UsageMonitorCore

/// v1.0.2 requirement 4 / §6: the click-target decision is pure geometry, so the popover
/// dismissal rule can be tested without a window server.
final class PopoverDismissDecisionTests: XCTestCase {

    /// A menu bar item near the top-right of a 1600×1000 screen, with the popover hanging
    /// below the bar. The two frames must not overlap here, exactly as on screen.
    let buttonFrame = CGRect(x: 1400, y: 976, width: 120, height: 24)
    let popoverFrame = CGRect(x: 1180, y: 500, width: 320, height: 470)

    func testClickInsideThePopoverKeepsItOpen() {
        let inside = CGPoint(x: popoverFrame.midX, y: popoverFrame.midY)
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: inside,
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .popoverContent)
    }

    func testClickOnTheStatusItemButtonIsNotTreatedAsAnOutsideClick() {
        // The toggle click must reach the button so it can close the popover itself; letting
        // the monitor close first would let the button immediately reopen it.
        let onButton = CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: onButton,
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .statusItemButton)
    }

    func testClickOnTheDesktopDismisses() {
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: CGPoint(x: 200, y: 300),
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .outside)
    }

    func testClickOnAnotherApplicationsWindowDismisses() {
        // Same decision: only the two frames matter, not which process owns the click.
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: CGPoint(x: 700, y: 700),
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .outside)
    }

    func testClickOnAnotherMenuBarItemDismisses() {
        let otherStatusItem = CGPoint(x: 1300, y: buttonFrame.midY)
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: otherStatusItem,
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .outside)
    }

    func testThePopoverWinsWhenTheFramesOverlap() {
        // Defensive: an oversized status item frame must not turn a click on the panel's own
        // controls into a dismissal.
        let overlappingButton = popoverFrame.insetBy(dx: -40, dy: -40)
        let insidePanel = CGPoint(x: popoverFrame.midX, y: popoverFrame.midY)
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: insidePanel,
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: overlappingButton), .popoverContent)
    }

    func testFrameEdgesUseTheStandardHalfOpenConvention() {
        // `CGRect.contains` is half-open: minX/minY belong to the rectangle, maxX/maxY do not.
        // AppKit hit testing uses the same convention, so a click exactly on the shared edge is
        // claimed by whichever surface owns it rather than by both.
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: CGPoint(x: popoverFrame.minX, y: popoverFrame.minY),
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .popoverContent)
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: CGPoint(x: popoverFrame.maxX, y: popoverFrame.maxY),
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .outside)

        // A pixel inside the far corner is still the popover's.
        let justInside = CGPoint(x: popoverFrame.maxX - 0.5, y: popoverFrame.maxY - 0.5)
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: justInside,
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .popoverContent)
    }

    func testJustOutsideThePopoverDismisses() {
        let justRight = CGPoint(x: popoverFrame.maxX + 1, y: popoverFrame.midY)
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: justRight,
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: buttonFrame), .outside)
    }

    func testAMissingPopoverFrameMakesEverythingOutside() {
        // With no popover on screen there is nothing to keep open.
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: CGPoint(x: 1460, y: 988),
                                                     popoverFrame: nil,
                                                     statusButtonFrame: nil), .outside)
    }

    func testAnItemWithoutAWindowDoesNotSwallowTheClick() {
        XCTAssertEqual(PopoverDismissDecision.target(clickPoint: CGPoint(x: 1460, y: 988),
                                                     popoverFrame: popoverFrame,
                                                     statusButtonFrame: nil), .outside)
    }
}

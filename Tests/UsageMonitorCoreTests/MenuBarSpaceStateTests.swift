import XCTest
import CoreGraphics
@testable import UsageMonitorCore

/// Menu bar space state machine.
///
/// These are pure-logic tests: the facts are hand-built from the same values the
/// AppKit layer reads (`NSStatusItem.button.window?.frame`, the hosting
/// `NSScreen`'s `frame`, `safeAreaInsets`, `auxiliaryTopLeftArea`,
/// `auxiliaryTopRightArea`).
///
/// Since 1.6.8 the label has one fixed width, so the machine's only question is
/// whether macOS can render the item at all. When it cannot, the caller opens
/// the detail window; the caller owns the timing guards (a settle delay after
/// its own resize, and opening only once).
final class MenuBarSpaceStateTests: XCTestCase {

    /// A wide, notch-free display: `O1 78% 42%` fits comfortably.
    private func roomyFacts(requestedWidth: CGFloat = 132) -> MenuBarSpaceFacts {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        return MenuBarSpaceFacts(itemFrame: CGRect(x: screen.maxX - 132, y: screen.maxY - 24,
                                                   width: requestedWidth, height: 24),
                                 screenFrame: screen,
                                 safeAreaTop: 0,
                                 auxiliaryTopLeftArea: CGRect(x: 0, y: 876, width: 1440, height: 24),
                                 auxiliaryTopRightArea: .zero,
                                 requestedWidth: requestedWidth)
    }

    /// A notched display: the right-hand menu bar region is narrow and the housing sits
    /// between the two auxiliary areas.
    private func notchedFacts(itemMinX: CGFloat,
                              requestedWidth: CGFloat = 132,
                              screenWidth: CGFloat = 1512) -> MenuBarSpaceFacts {
        let screen = CGRect(x: 0, y: 0, width: screenWidth, height: 982)
        let leftArea = CGRect(x: 0, y: 982 - 37, width: 400, height: 37)
        let rightArea = CGRect(x: 620, y: 982 - 37, width: screenWidth - 620, height: 37)
        return MenuBarSpaceFacts(itemFrame: CGRect(x: itemMinX, y: screen.maxY - 37,
                                                   width: requestedWidth, height: 37),
                                 screenFrame: screen,
                                 safeAreaTop: 37,
                                 auxiliaryTopLeftArea: leftArea,
                                 auxiliaryTopRightArea: rightArea,
                                 requestedWidth: requestedWidth)
    }

    // MARK: Facts

    func testNotchSpanComesFromTheAuxiliaryAreas() {
        let facts = notchedFacts(itemMinX: 1300)
        XCTAssertEqual(facts.notchSpan?.lowerBound, 400, "left auxiliary area's right edge")
        XCTAssertEqual(facts.notchSpan?.upperBound, 620, "right auxiliary area's left edge")
        XCTAssertTrue(facts.isNotchedDisplay)
    }

    func testNoNotchOnARegularDisplay() {
        XCTAssertFalse(roomyFacts().isNotchedDisplay)
        XCTAssertNil(roomyFacts().notchSpan)
        XCTAssertTrue(roomyFacts().isRendered)
    }

    func testItemUnderTheNotchIsOccluded() {
        // The item overlaps the housing: it must be reported as occluded.
        let facts = notchedFacts(itemMinX: 350, requestedWidth: 132)
        XCTAssertTrue(facts.isOccludedByNotch)
        XCTAssertFalse(facts.isRendered)
    }

    func testItemRightOfTheNotchIsVisible() {
        let facts = notchedFacts(itemMinX: 1380, requestedWidth: 132)
        XCTAssertFalse(facts.isOccludedByNotch)
        XCTAssertTrue(facts.isRendered)
    }

    func testMissingFrameMeansTheSystemHidTheItem() {
        var facts = roomyFacts()
        facts.itemFrame = nil
        XCTAssertFalse(facts.isRendered)
    }

    func testItemPushedOffTheScreenIsOutsideTheVisibleArea() {
        var facts = roomyFacts()
        facts.itemFrame = CGRect(x: 1500, y: 876, width: 132, height: 24)
        XCTAssertTrue(facts.isOutsideVisibleArea)
        XCTAssertFalse(facts.isRendered)
    }

    func testItemBelowTheMenuBarBandIsOutsideTheVisibleArea() {
        var facts = roomyFacts()
        facts.itemFrame = CGRect(x: 1300, y: 700, width: 132, height: 24)
        XCTAssertTrue(facts.isOutsideVisibleArea)
        XCTAssertFalse(facts.isRendered)
    }

    func testTruncationIsDetectedFromTheRequestedWidth() {
        var facts = roomyFacts()
        facts.itemFrame = CGRect(x: 1300, y: 876, width: 60, height: 24)
        XCTAssertTrue(facts.isTruncated)
        XCTAssertFalse(facts.isRendered)
    }

    /// v1.0.2 §3.2/§3.3: the item must not be judged truncated against a width that was never
    /// measured. `StatusItemController` passes `requestedWidth: 0` for the observation that
    /// precedes the first real measurement, so a granted frame that happens to be narrower
    /// than the fallback is not a truncation signal.
    func testNoMeasuredBaselineIsNotTruncation() {
        var facts = roomyFacts(requestedWidth: 0)
        facts.itemFrame = CGRect(x: 1300, y: 876, width: 116, height: 22)
        XCTAssertFalse(facts.isTruncated, "an unknown baseline cannot prove truncation")
        XCTAssertTrue(facts.isRendered, "a roomy menu bar must not be reported as squeezed")

        // The same frame *is* a truncation once a real, wider baseline exists.
        facts.requestedWidth = 132
        XCTAssertTrue(facts.isTruncated)
    }

    // MARK: Decisions

    func testRoomyMenuBarKeepsTheItem() {
        let machine = MenuBarSpaceStateMachine()
        for _ in 0..<10 {
            XCTAssertEqual(machine.apply(roomyFacts()), .keep)
        }
    }

    func testOccludedItemOpensTheDetailWindow() {
        XCTAssertEqual(MenuBarSpaceStateMachine().apply(notchedFacts(itemMinX: 350)),
                       .openDetailWindow)
    }

    func testHiddenItemOpensTheDetailWindow() {
        var facts = roomyFacts()
        facts.itemFrame = nil
        XCTAssertEqual(MenuBarSpaceStateMachine().apply(facts), .openDetailWindow)
    }

    func testItemOffTheScreenOpensTheDetailWindow() {
        var facts = roomyFacts()
        facts.itemFrame = CGRect(x: 1500, y: 876, width: 132, height: 24)
        XCTAssertEqual(MenuBarSpaceStateMachine().apply(facts), .openDetailWindow)
    }

    func testTruncatedItemOpensTheDetailWindow() {
        var facts = roomyFacts(requestedWidth: 132)
        facts.itemFrame = CGRect(x: 1300, y: 876, width: 90, height: 24)
        XCTAssertEqual(MenuBarSpaceStateMachine().apply(facts), .openDetailWindow)
    }

    /// The width is fixed, so there is nothing to step down to and nothing to
    /// confirm: one bad observation and one good one must give the same answer
    /// as ten of them, in any order.
    func testTheDecisionIsTheSameOnEveryObservation() {
        let machine = MenuBarSpaceStateMachine()
        for _ in 0..<5 {
            XCTAssertEqual(machine.apply(notchedFacts(itemMinX: 350)), .openDetailWindow)
            XCTAssertEqual(machine.apply(roomyFacts()), .keep)
        }
    }

    func testTheOneModeHasNoSmallerOrLargerStep() {
        XCTAssertEqual(MenuBarSpaceMode.allCases, [.fixed])
        XCTAssertEqual(MenuBarSpaceMode.fixed.description, "fixed")
    }
}

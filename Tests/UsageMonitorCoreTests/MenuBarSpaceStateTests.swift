import XCTest
import CoreGraphics
@testable import UsageMonitorCore

/// Menu bar space state machine (v1.1 requirement 1).
///
/// These are pure-logic tests: the facts are hand-built from the same values the AppKit
/// layer reads (`NSStatusItem.button.window?.frame`, the hosting `NSScreen`'s `frame`,
/// `safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`).
final class MenuBarSpaceStateTests: XCTestCase {

    /// A wide, notch-free display: `5H 78% | W 42%` fits comfortably.
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
    /// than the per-mode fallback is not a truncation signal.
    func testNoMeasuredBaselineIsNotTruncation() {
        var facts = roomyFacts(requestedWidth: 0)
        facts.itemFrame = CGRect(x: 1300, y: 876, width: 116, height: 22)
        XCTAssertFalse(facts.isTruncated, "an unknown baseline cannot prove truncation")
        XCTAssertTrue(facts.isRendered, "a roomy menu bar must not be reported as squeezed")

        // The same frame *is* a truncation once a real, wider baseline exists.
        facts.requestedWidth = 132
        XCTAssertTrue(facts.isTruncated)
    }

    // MARK: Mode changes

    func testShrinksToCompactAndNeverDropsTheSecondQuota() {
        let machine = MenuBarSpaceStateMachine(initialMode: .full)
        let decision = machine.apply(notchedFacts(itemMinX: 350))
        XCTAssertEqual(decision, .change(to: .compact, reason: .hiddenOrOccluded))
        XCTAssertEqual(machine.mode, .compact)

        let second = machine.apply(notchedFacts(itemMinX: 350))
        XCTAssertEqual(second, .keep(.compact))
        XCTAssertEqual(machine.mode, .compact)
    }

    func testStaysAtFullWhileThereIsRoom() {
        let machine = MenuBarSpaceStateMachine()
        for _ in 0..<10 {
            XCTAssertEqual(machine.apply(roomyFacts()), .keep(.full))
        }
    }

    func testGrowsBackOnlyAfterEnoughCleanObservations() {
        let machine = MenuBarSpaceStateMachine(initialMode: .compact)
        // Two clean observations are not enough with the default of three.
        XCTAssertEqual(machine.apply(roomyFacts()), .keep(.compact))
        XCTAssertEqual(machine.apply(roomyFacts()), .keep(.compact))
        XCTAssertEqual(machine.apply(roomyFacts()), .change(to: .full, reason: .confirmedRoomToGrow))
        XCTAssertEqual(machine.mode, .full)
    }

    func testShrinkingBlocksGrowthUntilASpaceEvent() {
        let machine = MenuBarSpaceStateMachine(initialMode: .full)

        // Tight menu bar: drop to compact and stop. Both quota values remain visible.
        _ = machine.apply(notchedFacts(itemMinX: 350))
        _ = machine.apply(notchedFacts(itemMinX: 350))
        XCTAssertEqual(machine.mode, .compact)

        // Space frees up again, but the block from the shrink is still in force.
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        XCTAssertEqual(machine.mode, .compact, "no growth until a space event")

        // A space event (screen change, wake, item moved) re-opens growth.
        machine.noteSpaceEvent()
        XCTAssertEqual(machine.apply(roomyFacts()), .keep(.compact))
        XCTAssertEqual(machine.apply(roomyFacts()), .keep(.compact))
        XCTAssertEqual(machine.apply(roomyFacts()), .change(to: .full, reason: .confirmedRoomToGrow))
        XCTAssertEqual(machine.mode, .full)
    }

    func testFailedGrowthAttemptShrinksBackAndBlocksAgain() {
        let machine = MenuBarSpaceStateMachine(initialMode: .compact)

        // Room appears, growth is attempted…
        machine.noteSpaceEvent()
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        XCTAssertEqual(machine.mode, .full)

        // …but the room was not really there.
        let shrink = machine.apply(notchedFacts(itemMinX: 350))
        XCTAssertEqual(shrink, .change(to: .compact, reason: .hiddenOrOccluded))

        // Visible again: the block stops a further attempt, so the mode cannot flap.
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        XCTAssertEqual(machine.mode, .compact, "no second growth attempt without a space event")
    }

    func testTruncationStepsDownInsteadOfShowingCutOffContent() {
        let machine = MenuBarSpaceStateMachine(initialMode: .full)
        var facts = roomyFacts(requestedWidth: 132)
        facts.itemFrame = CGRect(x: 1300, y: 876, width: 90, height: 24)
        let decision = machine.apply(facts)
        XCTAssertEqual(decision, .change(to: .compact, reason: .truncated))
    }

    func testModeOrderingIsLinear() {
        XCTAssertEqual(MenuBarSpaceMode.full.nextSmaller, .compact)
        XCTAssertNil(MenuBarSpaceMode.compact.nextSmaller)
        XCTAssertNil(MenuBarSpaceMode.full.nextLarger)
        XCTAssertEqual(MenuBarSpaceMode.compact.nextLarger, .full)
    }

    // MARK: Screen / wake events

    func testScreenChangeReEnablesGrowth() {
        let machine = MenuBarSpaceStateMachine(initialMode: .compact)
        machine.noteSpaceEvent()   // NSApplication.didChangeScreenParametersNotification
        XCTAssertEqual(machine.apply(roomyFacts()), .keep(.compact))
    }

    func testWakeReEnablesGrowth() {
        let machine = MenuBarSpaceStateMachine(initialMode: .compact)
        machine.noteSpaceEvent()   // NSWorkspace.didWakeNotification
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        _ = machine.apply(roomyFacts())
        XCTAssertEqual(machine.mode, .full)
    }

    func testRepeatedSpaceEventsDoNotSkipTheConfirmationWindow() {
        let machine = MenuBarSpaceStateMachine(initialMode: .compact)
        for _ in 0..<5 {
            machine.noteSpaceEvent()
            XCTAssertEqual(machine.apply(roomyFacts()), .keep(.compact),
                           "a burst of events must not collapse the confirmation window")
        }
    }
}

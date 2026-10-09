import CoreGraphics
import XCTest
@testable import UsageMonitorApp

/// The account-overview reorder rules: what the stored preference means, how a drag resolves
/// to a slot, and that the stored value survives a relaunch without ever touching a credential
/// or another surface's order.
@MainActor
final class OverviewReorderTests: XCTestCase {

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suiteName = "UsageMonitorAppTests.OverviewReorder.\(label)." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: resolve

    func testNoStoredPreferenceKeepsTheIncomingProviderGroupedOrder() {
        let current = ["chatgpt-a", "chatgpt-b", "google-1", "deepseek", "commandcode"]
        XCTAssertEqual(OverviewReorder.resolve(currentIDs: current, preferred: []), current)
    }

    func testStoredPreferenceWinsAndUnmentionedRowsAppendInIncomingOrder() {
        let current = ["chatgpt-a", "chatgpt-b", "google-1", "deepseek"]
        let resolved = OverviewReorder.resolve(currentIDs: current,
                                               preferred: ["deepseek", "google-1"])
        XCTAssertEqual(resolved, ["deepseek", "google-1", "chatgpt-a", "chatgpt-b"],
                       "a new account sinks to the bottom instead of pushing the stored rows around")
    }

    func testRemovedRowsArePrunedAndDuplicatesCollapse() {
        let resolved = OverviewReorder.resolve(currentIDs: ["chatgpt-a", "chatgpt-b"],
                                               preferred: ["chatgpt-b", "removed-account", "chatgpt-b", "chatgpt-a"])
        XCTAssertEqual(resolved, ["chatgpt-b", "chatgpt-a"])
    }

    func testResolveIsStableWhenAPreferenceNamesOnlyUnknownRows() {
        let current = ["chatgpt-a", "chatgpt-b"]
        XCTAssertEqual(OverviewReorder.resolve(currentIDs: current, preferred: ["gone-1", "gone-2"]), current)
    }

    // MARK: move

    func testMoveReordersAndClampsOutOfRangeDestinations() {
        let order = ["a", "b", "c", "d"]
        XCTAssertEqual(OverviewReorder.move(order, id: "d", to: 0), ["d", "a", "b", "c"])
        XCTAssertEqual(OverviewReorder.move(order, id: "a", to: 3), ["b", "c", "d", "a"])
        XCTAssertEqual(OverviewReorder.move(order, id: "a", to: 99), ["b", "c", "d", "a"])
        XCTAssertEqual(OverviewReorder.move(order, id: "c", to: -5), ["c", "a", "b", "d"])
    }

    func testMoveOfAnUnknownIdentifierLeavesTheOrderUntouched() {
        let order = ["a", "b"]
        XCTAssertEqual(OverviewReorder.move(order, id: "missing", to: 0), order)
    }

    // MARK: displacement

    func testRowsBetweenOriginAndDestinationSlideByOneSlot() {
        // Dragging row 0 down over row 2: rows 1 and 2 move up one slot each.
        XCTAssertEqual(OverviewReorder.displacement(index: 1, originIndex: 0, destinationIndex: 2), -1)
        XCTAssertEqual(OverviewReorder.displacement(index: 2, originIndex: 0, destinationIndex: 2), -1)
        XCTAssertEqual(OverviewReorder.displacement(index: 3, originIndex: 0, destinationIndex: 2), 0)
        // Dragging row 3 up over row 1: rows 1 and 2 move down one slot each.
        XCTAssertEqual(OverviewReorder.displacement(index: 1, originIndex: 3, destinationIndex: 1), 1)
        XCTAssertEqual(OverviewReorder.displacement(index: 2, originIndex: 3, destinationIndex: 1), 1)
        XCTAssertEqual(OverviewReorder.displacement(index: 0, originIndex: 3, destinationIndex: 1), 0)
        // No movement, no displacement.
        XCTAssertEqual(OverviewReorder.displacement(index: 2, originIndex: 2, destinationIndex: 2), 0)
    }

    // MARK: dropIndex

    func testDropIndexSnapsToTheNearestWholeSlotAndStaysInsideTheList() {
        let pitch: CGFloat = 76
        XCTAssertEqual(OverviewReorder.dropIndex(translation: 0, homeIndex: 2, pitch: pitch, count: 5), 2)
        XCTAssertEqual(OverviewReorder.dropIndex(translation: 40, homeIndex: 2, pitch: pitch, count: 5), 3)
        XCTAssertEqual(OverviewReorder.dropIndex(translation: -40, homeIndex: 2, pitch: pitch, count: 5), 1)
        XCTAssertEqual(OverviewReorder.dropIndex(translation: 1000, homeIndex: 2, pitch: pitch, count: 5), 4)
        XCTAssertEqual(OverviewReorder.dropIndex(translation: -1000, homeIndex: 2, pitch: pitch, count: 5), 0)
    }

    func testDropIndexHandlesDegenerateInputs() {
        XCTAssertEqual(OverviewReorder.dropIndex(translation: 200, homeIndex: 0, pitch: 0, count: 4), 0)
        XCTAssertEqual(OverviewReorder.dropIndex(translation: 200, homeIndex: 3, pitch: 76, count: 1), 0)
    }

    // MARK: dragOffset

    /// The held row must sit exactly under the pointer: its own slot displacement is already
    /// expressed by `destinationIndex`, so adding it here would move the row twice and make it
    /// trail. This is the regression guard for the stuttering reported on 2026-10-09.
    func testHeldRowFollowsThePointerWithoutItsOwnSlotDisplacement() {
        let pitch: CGFloat = 76
        for translation in [CGFloat(0), 20, 80, -80, 300] {
            for destination in 0...4 {
                XCTAssertEqual(OverviewReorder.dragOffset(index: 2, draggedIndex: 2, originIndex: 2,
                                                          destinationIndex: destination,
                                                          translation: translation, pitch: pitch),
                               translation)
            }
        }
    }

    func testOtherRowsSlideByWholeSlotsOnly() {
        let pitch: CGFloat = 76
        // Dragging row 0 down to slot 2: rows 1 and 2 give way by one slot each.
        XCTAssertEqual(OverviewReorder.dragOffset(index: 1, draggedIndex: 0, originIndex: 0,
                                                  destinationIndex: 2, translation: 152, pitch: pitch), -pitch)
        XCTAssertEqual(OverviewReorder.dragOffset(index: 3, draggedIndex: 0, originIndex: 0,
                                                  destinationIndex: 2, translation: 152, pitch: pitch), 0)
        // Dragging row 3 up to slot 1: rows 1 and 2 move down.
        XCTAssertEqual(OverviewReorder.dragOffset(index: 1, draggedIndex: 3, originIndex: 3,
                                                  destinationIndex: 1, translation: -152, pitch: pitch), pitch)
        XCTAssertEqual(OverviewReorder.dragOffset(index: 0, draggedIndex: 3, originIndex: 3,
                                                  destinationIndex: 1, translation: -152, pitch: pitch), 0)
    }

    func testNoRowMovesWhileTheDropSlotStillEqualsTheOrigin() {
        let pitch: CGFloat = 76
        for index in 0...4 where index != 2 {
            XCTAssertEqual(OverviewReorder.dragOffset(index: index, draggedIndex: 2, originIndex: 2,
                                                      destinationIndex: 2, translation: 30, pitch: pitch), 0)
        }
    }

    // MARK: persistence

    func testCommitPersistsOnlyVisibleRowsAndSurvivesRelaunch() {
        let defaults = makeDefaults("roundtrip")
        let preferences = OverviewAccountOrderPreferences(defaults: defaults)
        preferences.commit(["b", "a", "gone"], visibleIDs: ["a", "b"])
        XCTAssertEqual(preferences.order, ["b", "a"])

        let reloaded = OverviewAccountOrderPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.order, ["b", "a"])
        XCTAssertEqual(reloaded.resolvedOrder(currentIDs: ["a", "b", "c"]), ["b", "a", "c"])
    }

    func testAResolvedOrderWithNoStoredPreferenceDoesNotWriteAnything() {
        let defaults = makeDefaults("read-only")
        let preferences = OverviewAccountOrderPreferences(defaults: defaults)
        _ = preferences.resolvedOrder(currentIDs: ["a", "b"])
        XCTAssertNil(defaults.stringArray(forKey: OverviewAccountOrderPreferences.storageKey),
                     "reading the overview must not create a preference")
    }

    func testCommittingTheSameOrderTwiceDoesNotChangeTheStoredValue() {
        let defaults = makeDefaults("idempotent")
        let preferences = OverviewAccountOrderPreferences(defaults: defaults)
        preferences.commit(["b", "a"], visibleIDs: ["a", "b"])
        let stored = defaults.stringArray(forKey: OverviewAccountOrderPreferences.storageKey)
        preferences.commit(["b", "a"], visibleIDs: ["a", "b"])
        XCTAssertEqual(defaults.stringArray(forKey: OverviewAccountOrderPreferences.storageKey), stored)
    }

    func testStoredOrderDropsEmptyAndDuplicateIdentifiers() {
        let defaults = makeDefaults("normalized")
        defaults.set(["a", "", "a", "b"], forKey: OverviewAccountOrderPreferences.storageKey)
        let preferences = OverviewAccountOrderPreferences(defaults: defaults)
        XCTAssertEqual(preferences.order, ["a", "b"])
    }

    func testASingleRowListKeepsItsOnlyPosition() {
        let pitch: CGFloat = 76
        XCTAssertEqual(OverviewReorder.dropIndex(translation: 200, homeIndex: 0, pitch: pitch, count: 1), 0)
        XCTAssertEqual(OverviewReorder.resolve(currentIDs: ["only"], preferred: ["only"]), ["only"])
    }

    // MARK: row geometry

    func testRowPitchMatchesTheDrawGeometry() {
        XCTAssertEqual(OverviewAccountRow.height, 64)
        XCTAssertEqual(OverviewAccountRow.pitch, 64 + DetailPageLayout.rowSpacing)
        XCTAssertGreaterThan(OverviewAccountRow.dragThreshold, 0)
        XCTAssertLessThan(OverviewAccountRow.dragThreshold, OverviewAccountRow.pitch / 4,
                          "the row must start moving after a few points, not after a fraction of a slot")
    }
}

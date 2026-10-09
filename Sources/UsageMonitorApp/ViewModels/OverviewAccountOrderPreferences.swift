import CoreGraphics
import Foundation
import Combine

/// Pure ordering rules for the account overview, kept out of the view so the append, prune
/// and move behaviour is testable without hosting anything.
///
/// The overview is the only surface this order influences. Account identity, refresh, the
/// managed-account list, menu bar candidates and fire schedules keep their existing order.
enum OverviewReorder {

    /// Resolves the visible order against the stored preference.
    ///
    /// Stored identifiers that are no longer visible are dropped, and visible identifiers the
    /// preference does not know are appended in their incoming order. A missing or empty
    /// preference therefore falls back to the incoming order, and a newly added account sinks
    /// to the bottom instead of reordering everything above it.
    static func resolve(currentIDs: [String], preferred: [String]) -> [String] {
        let visible = Set(currentIDs)
        var seen = Set<String>()
        var result: [String] = []
        for id in preferred where visible.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in currentIDs where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// Moves `id` to `destination`, shifting the identifiers in between. A destination outside
    /// the list is clamped, and an unknown identifier leaves the order untouched.
    static func move(_ order: [String], id: String, to destination: Int) -> [String] {
        guard let origin = order.firstIndex(of: id) else { return order }
        var next = order
        next.remove(at: origin)
        let target = min(max(destination, 0), next.count)
        next.insert(id, at: target)
        return next
    }

    /// How far a row must be pushed from its resting place while another row is dragged.
    ///
    /// A drag that has moved a row by exactly one slot fills the gap it left behind and opens
    /// the gap the target occupies. Directions between the origin and the destination move by
    /// one row slot; every other row stays put.
    static func displacement(index: Int, originIndex: Int, destinationIndex: Int) -> Int {
        guard originIndex != destinationIndex else { return 0 }
        if originIndex < destinationIndex, index > originIndex, index <= destinationIndex { return -1 }
        if originIndex > destinationIndex, index >= destinationIndex, index < originIndex { return 1 }
        return 0
    }

    /// The slot a held row would land in for the current vertical translation.
    ///
    /// The row snaps to the nearest whole slot, so a release between two rows always resolves
    /// to one of them instead of leaving the row halfway.
    static func dropIndex(translation: CGFloat, homeIndex: Int, pitch: CGFloat, count: Int) -> Int {
        guard pitch > 0, count > 1 else { return max(0, min(homeIndex, count - 1)) }
        let steps = (translation / pitch).rounded()
        return max(0, min(homeIndex + Int(steps), count - 1))
    }

    /// The vertical offset one row draws with while a drag is in flight.
    ///
    /// The held row carries the pointer's own travel and nothing else: its slot is already
    /// expressed by `destinationIndex`, so adding that slot's displacement on top would move
    /// it twice and make the row trail the pointer. Every other row moves by whole slots.
    static func dragOffset(index: Int, draggedIndex: Int, originIndex: Int, destinationIndex: Int,
                           translation: CGFloat, pitch: CGFloat) -> CGFloat {
        guard index != draggedIndex else { return translation }
        return CGFloat(displacement(index: index, originIndex: originIndex, destinationIndex: destinationIndex)) * pitch
    }
}

/// Local order of the account overview rows, chosen by dragging a row's logo.
///
/// Only a local list of stable account identifiers is stored. No credential, balance or
/// connection reference lives here, and no other surface reads this order.
final class OverviewAccountOrderPreferences: ObservableObject {

    static let shared = OverviewAccountOrderPreferences()

    static let storageKey = "overview.accountOrder.v1"

    private let defaults: UserDefaults

    @Published private(set) var order: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
        order = Self.normalized(stored)
    }

    /// The visible order to draw: the stored preference resolved against what is currently on
    /// screen. Reading never mutates the stored value, so a fresh install keeps no preference
    /// until the user actually moves a row.
    func resolvedOrder(currentIDs: [String]) -> [String] {
        OverviewReorder.resolve(currentIDs: currentIDs, preferred: order)
    }

    /// Records a completed drag. `visibleIDs` are the identifiers currently on screen, so a
    /// row that disappeared while its drag was in flight cannot be persisted.
    func commit(_ order: [String], visibleIDs: [String]) {
        let visible = Set(visibleIDs)
        let next = order.filter { visible.contains($0) }
        guard next != self.order else { return }
        self.order = next
        persist()
    }

    private func persist() {
        if order.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(order, forKey: Self.storageKey)
        }
    }

    private static func normalized(_ stored: [String]) -> [String] {
        var seen = Set<String>()
        return stored.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

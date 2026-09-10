import Foundation
import CoreGraphics

/// How much of the two-quota title the menu bar can currently show.
/// The progression required by v1.1 is full → compact → icon.
public enum MenuBarSpaceMode: String, CaseIterable, Codable, Sendable {
    /// `5H 78% | W 42%`
    case full
    /// `78% / 42%`
    case compact
    /// Icon only.
    case icon

    public var nextSmaller: MenuBarSpaceMode? {
        switch self {
        case .full: return .compact
        case .compact: return .icon
        case .icon: return nil
        }
    }

    public var nextLarger: MenuBarSpaceMode? {
        switch self {
        case .icon: return .compact
        case .compact: return .full
        case .full: return nil
        }
    }

    /// Fixed display hint, used by tests and by the accessibility label.
    public var description: String {
        switch self {
        case .full: return "full"
        case .compact: return "compact"
        case .icon: return "icon"
        }
    }
}

/// Everything the decision needs, expressed as plain values so the whole state machine is
/// testable without AppKit.
///
/// The values come from `NSStatusItem.button.window?.frame`, the hosting `NSScreen`'s
/// `frame`, `safeAreaInsets`, `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. No
/// private API is involved and no system-wide menu bar setting is touched.
public struct MenuBarSpaceFacts: Equatable, Sendable {

    /// The status item's real frame, or nil when it has no window at all (macOS has hidden
    /// it because there is no room).
    public var itemFrame: CGRect?
    /// Frame of the screen hosting the item; nil when it cannot be determined.
    public var screenFrame: CGRect?
    /// `safeAreaInsets.top`. Non-zero on a display with a sensor housing (notch).
    public var safeAreaTop: CGFloat
    /// `auxiliaryTopLeftArea`: menu bar area left of the notch.
    public var auxiliaryTopLeftArea: CGRect
    /// `auxiliaryTopRightArea`: menu bar area right of the notch.
    public var auxiliaryTopRightArea: CGRect
    /// Width the app asked the status item to have, for the mode currently applied.
    public var requestedWidth: CGFloat

    public init(itemFrame: CGRect?,
                screenFrame: CGRect?,
                safeAreaTop: CGFloat,
                auxiliaryTopLeftArea: CGRect,
                auxiliaryTopRightArea: CGRect,
                requestedWidth: CGFloat) {
        self.itemFrame = itemFrame
        self.screenFrame = screenFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.requestedWidth = requestedWidth
    }

    /// A display has a notch when its top safe-area inset is non-zero.
    public var isNotchedDisplay: Bool { safeAreaTop > 0 }

    /// Horizontal span covered by the sensor housing, derived from the two auxiliary areas.
    /// nil on a display without a notch.
    public var notchSpan: ClosedRange<CGFloat>? {
        guard isNotchedDisplay,
              auxiliaryTopLeftArea.width > 0,
              auxiliaryTopRightArea.width > 0 else { return nil }
        let lower = auxiliaryTopLeftArea.maxX
        let upper = auxiliaryTopRightArea.minX
        guard upper >= lower else { return nil }
        return lower...upper
    }

    /// True when the status item has a real, non-degenerate frame.
    public var isItemFrameKnown: Bool {
        guard let frame = itemFrame else { return false }
        return frame.width > 1 && frame.height > 1
    }

    /// Height of the menu bar band, taken from the safe-area inset and the auxiliary areas.
    /// Falls back to the standard 24 pt when the screen reports none of them.
    public var menuBarBandHeight: CGFloat {
        let candidate = max(safeAreaTop, auxiliaryTopLeftArea.height, auxiliaryTopRightArea.height)
        return candidate > 0 ? candidate : 24
    }

    /// The item sits over the sensor housing, so part or all of it is not visible.
    public var isOccludedByNotch: Bool {
        guard let frame = itemFrame, let span = notchSpan else { return false }
        return frame.maxX > span.lowerBound && frame.minX < span.upperBound
    }

    /// The item is outside the visible menu bar band of its screen: pushed off either edge,
    /// above the bar, below it, or simply not laid out.
    public var isOutsideVisibleArea: Bool {
        guard let frame = itemFrame, let screen = screenFrame else { return true }
        let tolerance: CGFloat = 0.5
        if frame.maxX > screen.maxX + tolerance { return true }
        if frame.minX < screen.minX - tolerance { return true }
        if frame.minY > screen.maxY + tolerance { return true }
        if frame.maxY < screen.maxY - menuBarBandHeight - tolerance { return true }
        return false
    }

    /// macOS clamped the item to less room than was requested, so the content is cut off.
    public var isTruncated: Bool {
        guard let frame = itemFrame, requestedWidth > 0 else { return false }
        return frame.width < requestedWidth - 1
    }

    /// The item is actually visible in the menu bar right now.
    public var isRendered: Bool {
        return isItemFrameKnown && !isOccludedByNotch && !isOutsideVisibleArea && !isTruncated
    }

    /// Fixed-category summary for diagnostics. Geometry only, no content.
    public var diagnosticSummary: String {
        let frame = itemFrame.map { String(format: "x%.0f w%.0f", $0.minX, $0.width) } ?? "none"
        return "notch:\(isNotchedDisplay ? "y" : "n") occluded:\(isOccludedByNotch ? "y" : "n") outside:\(isOutsideVisibleArea ? "y" : "n") truncated:\(isTruncated ? "y" : "n") frame:\(frame)"
    }
}

/// Menu bar space state machine.
///
/// Two rules keep the display from flapping between modes:
/// - **Shrink immediately.** The moment the item is not rendered (hidden by macOS, over the
///   notch, off the visible area, or truncated), the state steps down one level per
///   observation, so a squeezed menu bar reaches the icon mode in consecutive steps.
/// - **Grow cautiously.** Growth is one step, only after `growConfirmations` consecutive
///   observations where the item rendered cleanly. One failed growth attempt blocks further
///   growth until a space event happens (screen change, wake, or the item's own frame
///   moving), so a tight menu bar cannot produce a grow/shrink loop.
public final class MenuBarSpaceStateMachine {

    public struct Config: Equatable, Sendable {
        /// Consecutive clean observations required before growing one step.
        public var growConfirmations: Int
        public init(growConfirmations: Int = 3) {
            self.growConfirmations = max(1, growConfirmations)
        }
        public static let standard = Config(growConfirmations: 3)
    }

    public enum Decision: Equatable, Sendable {
        case keep(MenuBarSpaceMode)
        case change(to: MenuBarSpaceMode, reason: Reason)
    }

    public enum Reason: String, Sendable {
        case hiddenOrOccluded
        case truncated
        case confirmedRoomToGrow
    }

    public let config: Config
    public private(set) var mode: MenuBarSpaceMode = .full

    private var renderedStreak = 0
    private var growthBlocked = false
    private var lastDecision: Decision?

    public init(config: Config = .standard, initialMode: MenuBarSpaceMode = .full) {
        self.config = config
        self.mode = initialMode
    }

    /// Feeds one observation and returns the decision. Pure with respect to the caller:
    /// nothing here touches AppKit.
    @discardableResult
    public func apply(_ facts: MenuBarSpaceFacts) -> Decision {
        // Truncation means macOS gave the item less room than asked: step down instead of
        // showing cut-off content. Checked before the generic not-rendered path so the
        // decision names the truncation, which is the actionable reason.
        if facts.isTruncated, let smaller = mode.nextSmaller {
            renderedStreak = 0
            growthBlocked = true
            return commit(.change(to: smaller, reason: .truncated))
        }

        guard facts.isRendered else {
            renderedStreak = 0
            growthBlocked = true
            guard let smaller = mode.nextSmaller else {
                let decision = Decision.keep(mode)
                lastDecision = decision
                return decision
            }
            return commit(.change(to: smaller, reason: .hiddenOrOccluded))
        }

        renderedStreak += 1

        if growthBlocked || renderedStreak < config.growConfirmations {
            let decision = Decision.keep(mode)
            lastDecision = decision
            return decision
        }
        guard let larger = mode.nextLarger else {
            let decision = Decision.keep(mode)
            lastDecision = decision
            return decision
        }
        // Optimistically try the larger mode; if macOS then hides the item, the next
        // observation shrinks it back and blocks growth until a space event.
        return commit(.change(to: larger, reason: .confirmedRoomToGrow))
    }

    /// Re-enables growth after a space event: the screen set changed, the display woke, or
    /// the status item moved. This is the only way out of a growth block, which is what
    /// stops the mode from flapping on a permanently tight menu bar.
    public func noteSpaceEvent() {
        growthBlocked = false
        renderedStreak = 0
    }

    /// Forces a mode, e.g. when the user picks a fixed display in settings.
    public func force(_ newMode: MenuBarSpaceMode) {
        mode = newMode
        renderedStreak = 0
        lastDecision = .keep(newMode)
    }

    private func commit(_ decision: Decision) -> Decision {
        if case .change(let newMode, _) = decision { mode = newMode }
        lastDecision = decision
        return decision
    }

    /// Reason of the last decision, for diagnostics.
    public var lastDecisionDescription: String {
        switch lastDecision {
        case .keep(let mode): return "keep(\(mode.description))"
        case .change(let mode, let reason)?: return "change(\(mode.description), \(reason.rawValue))"
        case nil: return "none"
        }
    }
}

import Foundation
import CoreGraphics

/// The menu bar label has exactly one presentation: a fixed-width item
/// whose length never changes with its content.
///
/// Earlier versions stepped the label down full → compact when the menu
/// bar ran out of room. Since 1.6.8 the item's width is constant, so
/// there is nothing left to step down to: when macOS cannot render the
/// item at all — hidden, over the sensor housing, off the visible area,
/// or clipped — the app opens the detail window instead of showing a
/// partial label.
public enum MenuBarSpaceMode: String, CaseIterable, Codable, Sendable {
    case fixed

    /// Fixed display hint used by tests and diagnostics.
    public var description: String { "fixed" }
}

/// Everything the decision needs, expressed as plain values so the
/// whole state machine is testable without AppKit.
///
/// The values come from `NSStatusItem.button.window?.frame`, the
/// hosting `NSScreen`'s `frame`, `safeAreaInsets`,
/// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. No private API
/// is involved and no system-wide menu bar setting is touched.
public struct MenuBarSpaceFacts: Equatable, Sendable {

    /// The status item's real frame, or nil when it has no window at
    /// all (macOS has hidden it because there is no room).
    public var itemFrame: CGRect?
    /// Frame of the screen hosting the item; nil when it cannot be determined.
    public var screenFrame: CGRect?
    /// `safeAreaInsets.top`. Non-zero on a display with a sensor housing (notch).
    public var safeAreaTop: CGFloat
    /// `auxiliaryTopLeftArea`: menu bar area left of the notch.
    public var auxiliaryTopLeftArea: CGRect
    /// `auxiliaryTopRightArea`: menu bar area right of the notch.
    public var auxiliaryTopRightArea: CGRect
    /// Width the app asked the status item to have, so macOS clipping
    /// the item below that width is detectable.
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

    /// Horizontal span covered by the sensor housing, derived from the
    /// two auxiliary areas. nil on a display without a notch.
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

    /// Height of the menu bar band, taken from the safe-area inset and
    /// the auxiliary areas. Falls back to the standard 24 pt when the
    /// screen reports none of them.
    public var menuBarBandHeight: CGFloat {
        let candidate = max(safeAreaTop, auxiliaryTopLeftArea.height, auxiliaryTopRightArea.height)
        return candidate > 0 ? candidate : 24
    }

    /// The item sits over the sensor housing, so part or all of it is not visible.
    public var isOccludedByNotch: Bool {
        guard let frame = itemFrame, let span = notchSpan else { return false }
        return frame.maxX > span.lowerBound && frame.minX < span.upperBound
    }

    /// The item is outside the visible menu bar band of its screen:
    /// pushed off either edge, above the bar, below it, or simply not
    /// laid out.
    public var isOutsideVisibleArea: Bool {
        guard let frame = itemFrame, let screen = screenFrame else { return true }
        let tolerance: CGFloat = 0.5
        if frame.maxX > screen.maxX + tolerance { return true }
        if frame.minX < screen.minX - tolerance { return true }
        if frame.minY > screen.maxY + tolerance { return true }
        if frame.maxY < screen.maxY - menuBarBandHeight - tolerance { return true }
        return false
    }

    /// macOS clamped the item to less room than was requested, so the
    /// content is cut off.
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
/// The label's width is constant (1.6.8), so one geometry observation
/// can only answer whether macOS can currently render the item at
/// all. When it cannot, the caller opens the detail window; the
/// caller owns the timing guards — a settle delay after its own
/// resize, and opening the window only once — which keeps a transient
/// layout pass from popping a window.
public final class MenuBarSpaceStateMachine {

    public enum Decision: Equatable, Sendable {
        case keep
        case openDetailWindow
    }

    public init() {}

    /// Feeds one observation and returns the decision. Pure with
    /// respect to the caller: nothing here touches AppKit.
    @discardableResult
    public func apply(_ facts: MenuBarSpaceFacts) -> Decision {
        facts.isRendered ? .keep : .openDetailWindow
    }
}

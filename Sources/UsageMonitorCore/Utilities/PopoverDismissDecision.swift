import CoreGraphics

/// Where a mouse-down landed, relative to the surfaces the status item owns.
///
/// v1.0.2 requirement 4 (popover dismissal): a click outside the transient popover must
/// close it, and the same click must still reach whatever it was aimed at. Deciding that
/// needs only two frames and a point, so the decision is a pure function here rather than
/// AppKit code that cannot be tested without a window server.
public enum PopoverClickTarget: Equatable, Sendable {
    /// Inside the popover: keep it open, the click belongs to its content.
    case popoverContent
    /// On the status item's button: keep it open and let the button's own action decide, so
    /// the toggle click cannot be both a dismissal and a re-open.
    case statusItemButton
    /// Anywhere else: dismiss, without consuming the event.
    case outside
}

/// Pure click-target resolution. All rectangles and the point are in the same coordinate
/// space; `StatusItemController` converts AppKit window coordinates to screen space before
/// calling in.
public enum PopoverDismissDecision {

    /// - Parameters:
    ///   - clickPoint: the click location in screen coordinates.
    ///   - popoverFrame: the popover's window frame, or nil when it is not on screen.
    ///   - statusButtonFrame: the status item button's frame, or nil when it has no window.
    public static func target(clickPoint: CGPoint,
                              popoverFrame: CGRect?,
                              statusButtonFrame: CGRect?) -> PopoverClickTarget {
        // The popover is checked first: an oversized status item frame that overlaps the
        // popover must not turn a click inside the content into a dismissal.
        if let popoverFrame, popoverFrame.contains(clickPoint) {
            return .popoverContent
        }
        if let statusButtonFrame, statusButtonFrame.contains(clickPoint) {
            return .statusItemButton
        }
        return .outside
    }
}

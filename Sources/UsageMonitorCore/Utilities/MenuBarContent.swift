import Foundation

/// The one abnormal marker the menu bar status item may show.
///
/// v1.0.2 requirement 4: at most one marker, always in front of the quota text, never at the
/// end. The decision lives in exactly one place (`MenuBarContentBuilder`) so no caller can
/// append a second one and no caller can lose the cached-data hint.
public enum MenuBarAttention: String, Equatable, Sendable {
    /// Normal operation. The brand mark is gone, so nothing occupies the leading slot.
    case none
    /// Cached data on display, or a read that has definitely failed.
    case warning

    /// SF Symbol drawn in front of the text. A template symbol is used instead of the ⚠
    /// emoji so its size and tint follow the menu bar appearance; the two are never combined.
    public var symbolName: String? {
        self == .warning ? "exclamationmark.triangle.fill" : nil
    }

    /// Plain-text fallback used for accessibility and for text-only surfaces.
    public var textMarker: String? {
        self == .warning ? "⚠" : nil
    }
}

/// Everything the status item needs for one frame of one mode, fully resolved.
///
/// The view is a pure function of this value, which is what lets the layout, the two time
/// rows and the warning be tested without a window server.
public struct MenuBarContent: Equatable, Sendable {

    public let mode: MenuBarSpaceMode
    /// The quota text only. Never contains a marker, in any mode.
    public let text: String
    public let attention: MenuBarAttention
    /// Full and compact show both rows; the minimal space fallback shows none.
    public let showsTimeBars: Bool
    public let fiveHour: ResetTimeProgress
    public let weekly: ResetTimeProgress
    /// The numbers come from the cache, so the rows are drawn dimmer.
    public let isCached: Bool

    public init(mode: MenuBarSpaceMode,
                text: String,
                attention: MenuBarAttention,
                showsTimeBars: Bool,
                fiveHour: ResetTimeProgress,
                weekly: ResetTimeProgress,
                isCached: Bool) {
        self.mode = mode
        self.text = text
        self.attention = attention
        self.showsTimeBars = showsTimeBars
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.isCached = isCached
    }

    /// Identity of everything that can change the item's width: the mode, the quota text and
    /// the warning marker. Time is deliberately excluded, so the once-a-second countdown
    /// redraws without re-measuring the status item (v1.0.2 §4.4).
    public var sizeSignature: String {
        "\(mode.rawValue)#\(text)#\(attention.rawValue)"
    }

    /// Spoken description. It names each row's state, so an unknown or expired row is never
    /// announced as an ordinary countdown.
    public var accessibilityText: String {
        var parts = ["明明有数 · Minget 菜单栏"]
        if attention == .warning { parts.append("异常提示") }
        parts.append(text)
        if showsTimeBars {
            parts.append(fiveHour.stateText(windowName: UsageFormatting.windowName(.fiveHour)))
            parts.append(weekly.stateText(windowName: UsageFormatting.windowName(.weekly)))
        }
        return parts.joined(separator: "，")
    }
}

/// The only place the menu bar's text, warning marker and time rows are decided.
public enum MenuBarContentBuilder {

    /// - Parameters:
    ///   - display: the Codex display state the panel already uses.
    ///   - connectionState: used to tell "no data yet" apart from "the read failed".
    ///   - now: the single clock reading shared by both rows.
    ///   - mode: which of the three width modes is being drawn.
    public static func make(display: UsageDisplay,
                            connectionState: UsageService.ConnectionState,
                            now: Date,
                            mode: MenuBarSpaceMode) -> MenuBarContent {
        let snapshot = display.snapshot
        let rows = ResetTimeModel.rows(snapshot: snapshot, now: now)
        return MenuBarContent(mode: mode,
                              text: text(for: mode, snapshot: snapshot),
                              attention: attention(for: display, connectionState: connectionState),
                              showsTimeBars: mode != .icon,
                              fiveHour: rows.fiveHour,
                              weekly: rows.weekly,
                              isCached: display.isStale)
    }

    /// `5H 78% | W 42%` (full), `5H 78% W 42%` (compact), `5H` (minimal fallback).
    ///
    /// The minimal fallback shows the 5H label with no numbers and no rows: at that point the
    /// menu bar has no room for two legible rows, and the detail panel is a click away
    /// (v1.0.2 §3.3).
    public static func text(for mode: MenuBarSpaceMode, snapshot: UsageSnapshot?) -> String {
        let fiveHour = snapshot?.fiveHour
        let weekly = snapshot?.weekly
        switch mode {
        case .full:
            return UsageFormatting.menuBarTitle(fiveHour: fiveHour, weekly: weekly)
        case .compact:
            return UsageFormatting.compactMenuBarTitle(fiveHour: fiveHour, weekly: weekly)
        case .icon:
            return UsageFormatting.minimalMenuBarTitle()
        }
    }

    /// Cached data and a definitely failed read warn; a first load that has not produced a
    /// verdict yet does not (v1.0.2 §5.2.3). A row whose reset time is merely unknown is
    /// reported by that row's own state, not by an extra warning (§5.2.4).
    public static func attention(for display: UsageDisplay,
                                 connectionState: UsageService.ConnectionState) -> MenuBarAttention {
        switch display {
        case .live:
            return .none
        case .stale:
            return .warning
        case .unavailable:
            // `.disconnected` is set only by a fetch attempt that failed and has not been
            // followed by a success, so it is evidence of a real failure rather than of a
            // launch that is still in flight.
            return connectionState == .disconnected ? .warning : .none
        }
    }
}

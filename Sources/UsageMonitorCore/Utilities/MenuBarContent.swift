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
    /// Both production modes show both rows.
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

/// The DeepSeek half of the menu bar, already reduced to what the item draws.
///
/// `amount` is the resolved single balance; `nil` means nothing attributable is on display,
/// which the item reports as `DS —` with a warning rather than as a zero balance.
public struct MenuBarDeepSeekContent: Equatable, Sendable {
    public let currency: String?
    public let amount: Decimal?
    public let isCached: Bool

    public init(currency: String?, amount: Decimal?, isCached: Bool) {
        self.currency = currency
        self.amount = amount
        self.isCached = isCached
    }

    public var hasAmount: Bool { amount != nil }
}

/// Exactly one source feeds the menu bar at a time (REQUIREMENTS.md §6.1).
///
/// A ChatGPT source carries its short label so the item always names the account it shows;
/// the DeepSeek source carries no time rows at all, because the balance endpoint has no
/// window to draw.
public enum MenuBarSource: Equatable, Sendable {
    case chatGPT(shortLabel: String,
                 display: UsageDisplay,
                 connectionState: UsageService.ConnectionState)
    case deepSeek(MenuBarDeepSeekContent)
}

/// The only place the menu bar's text, warning marker and time rows are decided.
public enum MenuBarContentBuilder {

    /// - Parameters:
    ///   - source: the already-resolved menu bar source (one ChatGPT profile, or DeepSeek).
    ///   - now: the single clock reading shared by both rows.
    ///   - mode: which of the two production width modes is being drawn.
    public static func make(source: MenuBarSource,
                            now: Date,
                            mode: MenuBarSpaceMode) -> MenuBarContent {
        switch source {
        case .chatGPT(let shortLabel, let display, let connectionState):
            let snapshot = display.snapshot
            let rows = ResetTimeModel.rows(snapshot: snapshot, now: now)
            return MenuBarContent(mode: mode,
                                  text: text(for: mode, shortLabel: shortLabel, snapshot: snapshot),
                                  attention: attention(for: display, connectionState: connectionState),
                                  showsTimeBars: true,
                                  fiveHour: rows.fiveHour,
                                  weekly: rows.weekly,
                                  isCached: display.isStale)

        case .deepSeek(let content):
            return MenuBarContent(mode: mode,
                                  text: text(for: mode, content: content),
                                  attention: deepSeekAttention(for: content),
                                  // The balance endpoint reports no window, so the two
                                  // reset-time rows are absent rather than drawn empty.
                                  showsTimeBars: false,
                                  fiveHour: ResetTimeProgress(state: .invalid, fills: []),
                                  weekly: ResetTimeProgress(state: .invalid, fills: []),
                                  isCached: content.isCached)
        }
    }

    /// `A 5H 78% | W 42%` (full) or `A 78% 42%` (compact).
    public static func text(for mode: MenuBarSpaceMode,
                            shortLabel: String,
                            snapshot: UsageSnapshot?) -> String {
        switch mode {
        case .full:
            return UsageFormatting.labeledMenuBarTitle(shortLabel: shortLabel,
                                                       fiveHour: snapshot?.fiveHour,
                                                       weekly: snapshot?.weekly)
        case .compact:
            return UsageFormatting.labeledCompactMenuBarTitle(shortLabel: shortLabel,
                                                              fiveHour: snapshot?.fiveHour,
                                                              weekly: snapshot?.weekly)
        }
    }

    /// `DS CNY 123.45` in both semantic modes; the full and compact views use different
    /// typography and spacing. With no balance both modes show `DS —`.
    public static func text(for mode: MenuBarSpaceMode, content: MenuBarDeepSeekContent) -> String {
        switch mode {
        case .full:
            return UsageFormatting.deepSeekMenuBarTitle(currency: content.currency, amount: content.amount)
        case .compact:
            return UsageFormatting.compactDeepSeekMenuBarTitle(currency: content.currency, amount: content.amount)
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

    /// DeepSeek has one warning at most: a cached amount keeps its text and adds the marker,
    /// and a missing amount is always marked. A zero balance can never be produced here;
    /// `amount == nil` is the only "nothing to show" state.
    public static func deepSeekAttention(for content: MenuBarDeepSeekContent) -> MenuBarAttention {
        guard content.hasAmount else { return .warning }
        return content.isCached ? .warning : .none
    }
}

/// Picks the single DeepSeek amount the menu bar shows from a multi-currency response.
///
/// Deterministic and documented (REQUIREMENTS.md §6.3): a saved currency that is still
/// present, then CNY, then USD, then the first currency code in ascending order, then the
/// currency-unknown bucket. Nothing is converted, nothing is summed, and a currency that is
/// absent is reported as unnamed rather than guessed.
public enum DeepSeekMenuBarResolver {

    public struct Resolution: Equatable, Sendable {
        public let currency: String?
        public let amount: Decimal?
        public init(currency: String?, amount: Decimal?) {
            self.currency = currency
            self.amount = amount
        }
        public var hasAmount: Bool { amount != nil }
    }

    public static func resolve(balances: [ProviderBalance], savedCurrency: String?) -> Resolution {
        guard !balances.isEmpty else { return Resolution(currency: nil, amount: nil) }

        let named = balances
            .filter { !($0.currency?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty }
            .sorted { ($0.currency ?? "") < ($1.currency ?? "") }

        var chosen: ProviderBalance?
        if let savedCurrency {
            chosen = named.first { $0.currency?.caseInsensitiveCompare(savedCurrency) == .orderedSame }
        }
        if chosen == nil {
            chosen = named.first { $0.currency?.uppercased() == "CNY" }
        }
        if chosen == nil {
            chosen = named.first { $0.currency?.uppercased() == "USD" }
        }
        if chosen == nil {
            chosen = named.first
        }
        if chosen == nil {
            // Only currency-unknown buckets remain: the amount is real, the code is not.
            chosen = balances.first
        }

        guard let balance = chosen else { return Resolution(currency: nil, amount: nil) }
        // `available` first, then `total`, matching the detail card's amount semantics.
        let amount = balance.available ?? balance.total
        let currency = (balance.currency?.isEmpty == false) ? balance.currency : nil
        return Resolution(currency: currency, amount: amount)
    }
}

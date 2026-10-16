import AppKit
import SwiftUI
import UsageMonitorCore

/// The status item's drawing, driven by an already-decided `MenuBarContent`.
///
/// v1.0.2 requirement 1 and 2: the quota text sits on top and the two time rows
/// sit below it. Since 1.6.8 the whole drawing is pinned to one fixed width
/// (`MenuBarLabelMetrics.labelWidth`) — exactly the widest quota label, `O1 100%
/// 100%` — so no value, no source and no warning marker can change the item's
/// length: the marker shares the text's line, every other line shrinks inside the
/// budget, and both time rows span that same budget.
///
/// 1.3.0 adds two more sources behind the same content type (UI_SPEC.md §8):
/// - ChatGPT `O1` / `O2` and Gemini `G1`…, which keep both quota values and both
///   time rows and are told apart by the account code the content carries;
/// - DeepSeek `DS1`, which has no window at all, so `showsTimeBars` is false and
///   the single balance line is centred in the status item band instead of being
///   pinned to the top of a stack that would otherwise reserve an empty second row.
///
/// `MenuBarLabelView` owns the model observation; this type owns the drawing.
/// Splitting them means the exact production layout can be rendered from a fixed
/// fixture as well as from live data, which is how the layout was visually
/// checked without a window server.
struct MenuBarLabelContent: View {

    let content: MenuBarContent

    /// v1.0.2 §3.2: the 11 pt baseline size is kept.
    static let fontSize: CGFloat = 11
    /// Gap between the text and the first row of segments.
    static let labelToBarsSpacing: CGFloat = 1
    /// Gap between the abnormal marker and the text it precedes.
    static let markerSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Self.labelToBarsSpacing) {
            if content.showsTimeBars {
                // The marker shares the text's line instead of occupying a reserved
                // leading slot: an always-present slot cost visible blank space, and a
                // baseline-less placeholder in this aligned stack pushed the time rows
                // out of the menu bar band entirely.
                HStack(alignment: .firstTextBaseline, spacing: Self.markerSpacing) {
                    if let symbol = content.attention.symbolName {
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .accessibilityHidden(true)
                    }
                    Text(content.text)
                        .font(.system(size: Self.fontSize))
                        .lineLimit(1)
                        .minimumScaleFactor(MenuBarLabelMetrics.textShrinkFactor)
                }
                ResetTimeBarsView(fiveHour: content.fiveHour,
                                  weekly: content.weekly,
                                  width: MenuBarLabelMetrics.textBudget,
                                  isCached: content.isCached)
            } else {
                // DeepSeek has no time rails, so use the available menu-bar height for a
                // larger balance line, fitted to the same fixed budget.
                balanceLine
            }
        }
        .frame(width: MenuBarLabelMetrics.labelWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .allowsTightening(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityText)
    }

    /// The DeepSeek balance line: `DS1 CNY 89.67`, with the currency code
    /// omitted and the type size reduced only when the line cannot fit the
    /// fixed budget. The amount itself is never truncated.
    private var balanceLine: some View {
        let fitted = Self.fittedBalanceText(content.text)
        return HStack(spacing: MenuBarLabelMetrics.deepSeekSpacing) {
            ForEach(Array(fitted.text.split(separator: " ").enumerated()), id: \.offset) { _, token in
                Text(String(token))
                    .lineLimit(1)
            }
        }
        .font(.system(size: MenuBarLabelMetrics.deepSeekFontSize * fitted.scale,
                      weight: .medium))
        .frame(width: MenuBarLabelMetrics.textBudget, alignment: .leading)
    }

    /// The balance line, fitted to the fixed text budget. The currency code is the
    /// first thing to go — the user may omit it — and only then does the line shrink,
    /// by measurement, so a long amount loses no digit to truncation.
    static func fittedBalanceText(_ text: String) -> (text: String, scale: CGFloat) {
        var candidates: [String] = [text]
        let tokens = text.split(separator: " ").map(String.init)
        // `CODE CCY AMOUNT`: dropping the middle token keeps the code and the
        // amount, which is the documented abbreviation.
        if tokens.count == 3, tokens[1].count == 3 {
            candidates.append(tokens[0] + " " + tokens[2])
        }
        let usable = MenuBarLabelMetrics.textBudget - MenuBarLabelMetrics.balanceSafetyMargin
        for candidate in candidates where estimatedBalanceWidth(candidate) <= usable {
            return (candidate, 1)
        }
        // Nothing fits at full size: solve for the scale that makes the chosen form fit.
        // Only the glyphs scale with the font — the gap between tokens is fixed — so the
        // spacing has to be taken out of the budget before the ratio is computed.
        let chosen = candidates.last ?? text
        let spacing = Self.balanceSpacingWidth(tokenCount: chosen.split(separator: " ").count)
        let glyphWidth = estimatedBalanceWidth(chosen) - spacing
        let glyphBudget = usable - spacing
        guard glyphWidth > glyphBudget, glyphBudget > 0 else { return (chosen, 1) }
        return (chosen, max(MenuBarLabelMetrics.balanceMinimumFactor, glyphBudget / glyphWidth))
    }

    /// Width of a balance line, including the token spacing it draws with. The glyphs
    /// scale with the font; the spacing between tokens does not.
    static func estimatedBalanceWidth(_ text: String, scale: CGFloat = 1) -> CGFloat {
        let font = NSFont.systemFont(ofSize: MenuBarLabelMetrics.deepSeekFontSize * scale,
                                     weight: .medium)
        let tokens = text.split(separator: " ")
        let glyphs = tokens.reduce(0) { $0 + ceil((String($1) as NSString).size(withAttributes: [.font: font]).width) }
        return glyphs + Self.balanceSpacingWidth(tokenCount: tokens.count)
    }

    private static func balanceSpacingWidth(tokenCount: Int) -> CGFloat {
        MenuBarLabelMetrics.deepSeekSpacing * CGFloat(max(0, tokenCount - 1))
    }

    /// Width of a quota line at the 11 pt size the quota text draws with.
    static func estimatedTextWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// The fixed geometry of the status item's content.
///
/// The width is a constant of the label, not a function of its content: the
/// marker slot is always reserved, and the text budget is the widest text any
/// source can draw, measured with the same fonts the label draws with. That is
/// what makes the item's length identical for every source, every value and
/// every warning state.
enum MenuBarLabelMetrics {

    /// Padding between the label drawing and the item's edges.
    static let horizontalPadding: CGFloat = 12
    /// The 13 pt size of the DeepSeek balance line.
    static let deepSeekFontSize: CGFloat = 13
    /// Kept clear of the budget edge: the real layout adds a little to the measured
    /// width, and a balance must never lose a digit to rounding.
    static let balanceSafetyMargin: CGFloat = 2
    /// The smallest type the balance line may shrink to before it would have to give
    /// up more of itself.
    static let balanceMinimumFactor: CGFloat = 0.75

    /// How far a quota or fallback line may shrink before it would truncate. The Gemini
    /// fallbacks, the unavailable messages and a long balance fit by shrinking inside the
    /// budget instead of widening the item.
    static let textShrinkFactor: CGFloat = 0.85
    /// Token spacing inside the DeepSeek balance line.
    static let deepSeekSpacing: CGFloat = 7

    /// The fixed text width: exactly the widest quota label the menu bar can show — both
    /// percentages at 100 % behind a two-character code (`O1 100% 100%`) — plus a 2 pt
    /// rounding margin. Nothing else widens it: every other text either fits, shrinks, or
    /// (for DeepSeek) loses its currency code.
    static let textBudget: CGFloat = ceil(MenuBarLabelContent.estimatedTextWidth("O1 100% 100%")) + 2

    /// The fixed width of the label drawing: one width for every source, every value and
    /// every warning state.
    static let labelWidth: CGFloat = textBudget
    /// The width requested from the system status bar.
    static let itemWidth: CGFloat = labelWidth + horizontalPadding
}

/// What the status item actually hosts. Observing the model here is what makes
/// the countdown advance once a second without the controller doing any
/// status-item work.
struct MenuBarLabelView: View {

    @ObservedObject var model: UsageViewModel

    var body: some View {
        MenuBarLabelContent(content: model.menuBarContent(now: Date()))
    }
}

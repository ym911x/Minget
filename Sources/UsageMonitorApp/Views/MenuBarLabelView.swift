import AppKit
import SwiftUI
import UsageMonitorCore

/// The status item's drawing, driven by an already-decided `MenuBarContent`.
///
/// v1.0.2 requirement 1 and 2: the quota text sits on top and the two time rows sit below it,
/// both spanning exactly the text's measured width. The `M²` brand mark is gone from the menu
/// bar; the only leading element that may remain is the single abnormal marker from
/// `MenuBarContent`, which is laid out beside the text so it cannot change the rows' meaning.
///
/// `MenuBarLabelView` owns the model observation; this type owns the drawing. Splitting them
/// means the exact production layout can be rendered from a fixed fixture as well as from live
/// data, which is how the layout was visually checked without a window server.
struct MenuBarLabelContent: View {

    let content: MenuBarContent

    /// Measured width of the quota text. `0` until the first measurement lands.
    @State private var measuredTextWidth: CGFloat = 0

    /// v1.0.2 §3.2: the 11 pt baseline size is kept.
    static let fontSize: CGFloat = 11
    /// Gap between the warning marker and the text.
    static let markerSpacing: CGFloat = 3
    /// Gap between the text and the first row of segments.
    static let labelToBarsSpacing: CGFloat = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.markerSpacing) {
            if let symbol = content.attention.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Self.labelToBarsSpacing) {
                Text(content.text)
                    .font(.system(size: Self.fontSize))
                    .lineLimit(1)
                    .fixedSize()
                    .background(MenuBarTextWidthReader())
                if content.showsTimeBars {
                    ResetTimeBarsView(fiveHour: content.fiveHour,
                                      weekly: content.weekly,
                                      width: resolvedTextWidth(for: content.text),
                                      isCached: content.isCached)
                }
            }
        }
        .fixedSize()
        .allowsTightening(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityText)
        .onPreferenceChange(MenuBarTextWidthKey.self) { width in
            guard width > 0, abs(width - measuredTextWidth) > 0.5 else { return }
            measuredTextWidth = width
        }
    }

    /// The real measurement once it exists; a close synchronous estimate before that, so the
    /// very first layout is never zero-width and the item is never measured as hundreds of
    /// points wide.
    private func resolvedTextWidth(for text: String) -> CGFloat {
        measuredTextWidth > 0 ? measuredTextWidth : Self.estimatedTextWidth(text)
    }

    /// Same font as the `Text` above, so the first frame is already the right size. Only used
    /// until the real measurement arrives.
    static func estimatedTextWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// What the status item actually hosts. Observing the model here is what makes the countdown
/// advance once a second without the controller re-measuring anything.
struct MenuBarLabelView: View {

    @ObservedObject var model: UsageViewModel
    var mode: MenuBarSpaceMode = .full

    var body: some View {
        MenuBarLabelContent(content: model.menuBarContent(for: mode, now: Date()))
    }
}

/// Reports the quota text's own width. Because it lives in the text's `background`, the value
/// it publishes cannot be influenced by the rows underneath it.
private struct MenuBarTextWidthReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: MenuBarTextWidthKey.self, value: proxy.size.width)
        }
    }
}

private struct MenuBarTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

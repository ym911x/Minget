import SwiftUI
import UsageMonitorCore

/// The two rows of thin segments drawn under the menu bar quota text.
///
/// v1.0.2 requirement 2: the upper row has 5 segments for the five-hour window, the lower row
/// 7 for the weekly window, and both rows span exactly the same width, which is the measured
/// width of the quota text. Segments are laid out from the left; the bright part of the last
/// active segment recedes as the window drains, so the bright region shrinks towards the left
/// and the row is empty once the reset time is reached.
///
/// The view only consumes an already-decided width. Nothing here measures, expands or asks for
/// unlimited room, so the status item cannot be sized by the bars.
struct ResetTimeBarsView: View {

    let fiveHour: ResetTimeProgress
    let weekly: ResetTimeProgress
    /// Width of the quota text. Both rows use exactly this value.
    let width: CGFloat
    /// Cached data is drawn dimmer so it is never mistaken for a live countdown.
    let isCached: Bool

    /// v1.0.2 §3.2 starting values. The gap between the rows was widened from 1 pt to 2 pt:
    /// at 1 pt the two 1.5 pt lines merged into one thick band on a Retina menu bar, which
    /// made the two windows read as a single bar.
    static let barHeight: CGFloat = 1.5
    static let segmentGap: CGFloat = 2
    static let rowGap: CGFloat = 2
    /// Smallest segment we will draw, so a very narrow item degrades instead of collapsing.
    static let minimumSegmentWidth: CGFloat = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            row(fiveHour)
            row(weekly)
        }
        .frame(width: width, alignment: .leading)
        .overlay {
            if needsStateBadge { stateBadge }
        }
        .accessibilityHidden(true)   // the containing label already speaks both rows
    }

    @ViewBuilder
    private func row(_ progress: ResetTimeProgress) -> some View {
        let count = progress.segmentCount
        if count > 0 {
            HStack(spacing: Self.segmentGap) {
                ForEach(0..<count, id: \.self) { index in
                    segment(fill: index < progress.fills.count ? progress.fills[index] : 0,
                            progress: progress)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    /// Whether any row needs the state badge.
    ///
    /// v1.0.2 §4.3 asks for a small `?` over the middle of a row whose reset time is unknown,
    /// so that state is never confused with a countdown that reached zero.
    ///
    /// The two rows together are only `1.5 + 2 + 1.5 = 5 pt` tall, while a legible `?` is about
    /// 9.5 pt. One badge therefore covers the whole block whichever row it is anchored to, and
    /// drawing one per row only produced two overlapping glyphs. The badge is drawn once,
    /// horizontally centred over the block, which does overlap the offending row; which row is
    /// unknown is carried by that row's fainter track and, exhaustively, by the accessibility
    /// text. Recorded as a deviation in the 1.0.2 implementation report.
    private var needsStateBadge: Bool {
        needsBadge(fiveHour) || needsBadge(weekly)
    }

    private var stateBadge: some View {
        Text("?")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(isCached ? 0.6 : 0.75))
            // The status item is only 22 pt tall, which leaves ~1.5 pt above and below the 19 pt
            // label. A glyph centred on the block would poke past the button and be clipped, so
            // it is nudged up into the empty part of the text's line box instead.
            .offset(y: -0.5)
    }

    private func segment(fill: Double, progress: ResetTimeProgress) -> some View {
        let segmentWidth = Self.segmentWidth(count: progress.segmentCount, totalWidth: width)
        let isDimmed = needsBadge(progress)
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(trackOpacity(isDimmed: isDimmed)))
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(brightOpacity))
                .frame(width: max(0, segmentWidth * min(max(fill, 0), 1)))
        }
        .frame(width: segmentWidth, height: Self.barHeight)
    }

    /// `segmentWidth = (L - (segmentCount - 1) × gap) / segmentCount` (v1.0.2 §3.2).
    /// Five and seven segments therefore have different segment lengths but the same total.
    static func segmentWidth(count: Int, totalWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let available = totalWidth - CGFloat(count - 1) * segmentGap
        return max(minimumSegmentWidth, available / CGFloat(count))
    }

    /// v1.0.2 §3.2 / §4.3 starting opacities.
    private var brightOpacity: Double {
        isCached ? 0.45 : 0.85
    }

    private func trackOpacity(isDimmed: Bool) -> Double {
        if isDimmed { return isCached ? 0.10 : 0.12 }
        return isCached ? 0.15 : 0.20
    }

    /// A `?` distinguishes "we do not know the reset time" from "the countdown reached zero".
    /// It is a state label, not an extra warning marker.
    private func needsBadge(_ progress: ResetTimeProgress) -> Bool {
        progress.state == .unknown || progress.state == .invalid
    }
}

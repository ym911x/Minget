import SwiftUI
import UsageMonitorCore

/// One usage row: name, bar, remaining percent, reset time.
/// Colour never carries the information alone; the percentage text is always shown.
struct UsageRowView: View {
    let window: RateLimitWindow
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(UsageFormatting.windowName(window.kind))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(UsageFormatting.remainingText(window))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: barWidth(in: geometry.size.width))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            Text(UsageFormatting.resetText(window, now: now))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(UsageFormatting.windowName(window.kind))，\(UsageFormatting.remainingText(window))，\(UsageFormatting.resetText(window, now: now))")
    }

    private var color: Color {
        switch UsageFormatting.usageLevel(remainingPercent: window.remainingPercent) {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        let fraction = max(0, min(100, window.remainingPercent)) / 100
        return max(4, width * CGFloat(fraction))
    }
}

/// Placeholder row for a window the server did not report (spec §13 E/F).
struct MissingWindowRowView: View {
    let kind: RateLimitWindow.Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(UsageFormatting.windowName(kind))
                .font(.system(size: 13, weight: .semibold))
            Text(UsageFormatting.errorText(.windowUnavailable(kind: kind)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

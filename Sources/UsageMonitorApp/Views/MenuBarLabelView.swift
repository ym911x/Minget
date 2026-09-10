import SwiftUI
import UsageMonitorCore

/// Status item content. The mode is chosen by `MenuBarSpaceStateMachine`; each mode is
/// measured on its own so the item never asks for more room than it needs.
///
/// Only Codex appears here: DeepSeek and GLM are detail-panel-only for this release
/// (v1.1 requirement 7).
struct MenuBarLabelView: View {
    @ObservedObject var model: UsageViewModel
    var mode: MenuBarSpaceMode = .full

    var body: some View {
        Group {
            switch mode {
            case .full:
                HStack(spacing: 4) {
                    icon(size: 12)
                    Text(model.menuBarTitle)
                        .font(.system(size: 11))
                }
            case .compact:
                HStack(spacing: 3) {
                    icon(size: 11)
                    Text(UsageFormatting.compactMenuBarTitle(fiveHour: model.currentSnapshot?.fiveHour,
                                                             weekly: model.currentSnapshot?.weekly,
                                                             isStale: model.isStale))
                        .font(.system(size: 11))
                }
            case .icon:
                icon(size: 15)
            }
        }
        .fixedSize()
        .lineLimit(1)
        .allowsTightening(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func icon(size: CGFloat) -> some View {
        Text("M²")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(model.isStale ? Color.orange : Color.primary)
    }

    private var accessibilityText: String {
        let staleness = model.isStale ? "，数据为缓存" : ""
        return "明明有数 · Minget 菜单栏，\(model.menuBarTitle)\(staleness)"
    }
}

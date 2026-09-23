import AppKit
import SwiftUI
import UsageMonitorCore

/// One ChatGPT account card, driven entirely by a `CodexProfileViewState`
/// (REVISION_SPEC.md §5).
///
/// Restores the 1.2.1 information hierarchy: every window is a *pair* of tracks — the quota
/// remainder above, and its own segmented reset-time rail directly below, five segments for
/// the five-hour window and seven for the weekly one. The previous version kept only the quota
/// bar and an absolute reset moment, which is what the user rejected.
struct CodexProfileCard: View {

    static let size = CGSize(width: DetailPageLayout.contentWidth, height: DetailPageLayout.codexCardHeight)
    static let contentPadding: CGFloat = 12
    /// Space between the quota rail and its reset-time rail inside one period group.
    static let rowSpacing: CGFloat = 4
    static let windowGroupSpacing: CGFloat = 10
    static let headerHeight: CGFloat = 34
    static let accountRowHeight: CGFloat = 16
    static let headerToWindowSpacing: CGFloat = 12
    static let windowBlockHeight: CGFloat = 32
    static let footerHeight: CGFloat = 16
    static let footerSpacing: CGFloat = 12
    static let labelWidth: CGFloat = 50
    static let valueWidth: CGFloat = 102
    static let quotaTrackHeight: CGFloat = 6
    static let logoSize: CGFloat = 28

    static let fireButtonWidth: CGFloat = 76
    static let fireButtonHeight: CGFloat = 22
    static let fireButtonTitle = "5 小时点火"
    static let fireButtonRunningTitle = "点火中…"

    /// Fixed confirmation copy (UI_SPEC.md §9). Held as constants so a test can pin the exact
    /// wording rather than a paraphrase of it.
    static let confirmationTitle = "启动 5 小时额度窗口？"
    static let confirmationMessage = "将通过该账号执行一次真实 Codex 请求，会消耗少量额度。Minget 不会读取账号认证文件。"
    static let confirmButtonTitle = "确认点火"
    static let cancelButtonTitle = "取消"

    let state: CodexProfileViewState
    let displayName: String
    /// Invoked only after the user confirms the fixed dialog.
    var onFire: (() -> Void)?

    init(state: CodexProfileViewState,
         displayName: String? = nil,
         onFire: (() -> Void)? = nil) {
        self.state = state
        self.displayName = displayName ?? state.profile.displayName
        self.onFire = onFire
    }

    @State private var showsFireConfirmation = false
    /// One clock reading per body evaluation, shared by both reset rails.
    private let now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow.frame(height: Self.headerHeight + Self.accountRowHeight)
            Spacer().frame(height: Self.headerToWindowSpacing)
            windowBlock(label: "5 小时", kind: .fiveHour, window: snapshot?.fiveHour)
                .frame(height: Self.windowBlockHeight)
            Spacer().frame(height: Self.windowGroupSpacing)
            windowBlock(label: "周额度", kind: .weekly, window: snapshot?.weekly)
                .frame(height: Self.windowBlockHeight)
            Spacer().frame(height: Self.footerSpacing)
            footer.frame(height: Self.footerHeight)
        }
        .padding(Self.contentPadding)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .confirmationDialog(Self.confirmationTitle,
                            isPresented: $showsFireConfirmation,
                            titleVisibility: .visible) {
            Button(Self.confirmButtonTitle) { onFire?() }
            Button(Self.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(Self.confirmationMessage)
        }
    }

    private var snapshot: UsageSnapshot? { state.snapshot }

    // MARK: Header

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                BrandMark()
                    .frame(width: Self.logoSize, height: Self.logoSize)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 5) {
                        Text(state.displayPlanType ?? "套餐暂不可用")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        connectionIndicator
                    }
                }

                Spacer(minLength: 6)

                fireButton
            }
            HStack(spacing: 6) {
                // Per-card last-success line: the header must never imply every card is
                // fresh, so a stale or failed card states when it last succeeded (1.4.2 §5).
                if let lastSuccess = state.lastSuccessText {
                    Text(lastSuccess)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityLabel("上次成功")
                        .accessibilityValue(lastSuccess)
                }
                Spacer(minLength: 0)
                if let identityLabel = state.identityLabel {
                    Text(identityLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .accessibilityLabel(identityLabel)
                }
                Text(state.displayEmail ?? "账号暂不可用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel("账号")
                    .accessibilityValue(state.displayEmail ?? "账号暂不可用")
            }
        }
    }

    private var fireButton: some View {
        Button {
            showsFireConfirmation = true
        } label: {
            HStack(spacing: 4) {
                if state.isFiring {
                    ProgressView().controlSize(.small)
                }
                Text(state.isFiring ? Self.fireButtonRunningTitle : Self.fireButtonTitle)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .frame(width: Self.fireButtonWidth, height: Self.fireButtonHeight)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(state.isFiring)
        .accessibilityLabel("\(displayName) \(Self.fireButtonTitle)")
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        if state.isConnectionHealthy {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .accessibilityLabel("已连接")
        } else {
            Text(state.connectionText)
                .font(.system(size: 11))
                .foregroundStyle(connectionColor)
                .lineLimit(1)
                .accessibilityLabel(state.connectionText)
        }
    }

    private var connectionColor: Color {
        if state.isConnectionHealthy { return .green }
        if state.isConnectionCached { return .orange }
        return .secondary
    }

    // MARK: Window block: quota remainder above its own reset-time rail

    private func windowBlock(label: String, kind: RateLimitWindow.Kind, window: RateLimitWindow?) -> some View {
        let progress = ResetTimeModel.progress(expected: kind, window: window, now: now)
        return VStack(spacing: Self.rowSpacing) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: Self.labelWidth, alignment: .leading)
                QuotaRemainderBar(fraction: fraction(window), color: quotaColor(window))
                    .frame(maxWidth: .infinity)
                Text(Self.quotaValueText(window))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(window == nil ? Color.secondary : quotaColor(window))
                    .lineLimit(1)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Text("重置时间")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth, alignment: .leading)
                ProviderTimeBar(progress: Self.timeProgress(progress),
                                isCached: state.isStale,
                                tint: .blue)
                    .frame(maxWidth: .infinity)
                Text(Self.resetValueText(progress, window: window))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(Self.quotaValueText(window))，\(Self.resetValueText(progress, window: window))")
    }

    /// Maps the Codex reset countdown onto the shared rail drawing, so the card and the
    /// provider cards cannot drift apart on what "unknown" or "arrived" looks like.
    static func timeProgress(_ progress: ResetTimeProgress) -> ProviderTimeProgress {
        switch progress.state {
        case .active: return .segments(progress.fills)
        case .arrived: return .arrived
        case .unknown, .invalid: return .unavailable
        }
    }

    /// `剩余 66%`, or `—` for a window the service did not report. Never a fabricated 0%.
    static func quotaValueText(_ window: RateLimitWindow?) -> String {
        guard let window else { return "剩余 —" }
        return "剩余 \(Int(window.remainingPercent.rounded()))%"
    }

    /// The exact local reset moment; an expired one says the app is waiting for the service
    /// instead of inventing a new window.
    static func resetValueText(_ progress: ResetTimeProgress, window: RateLimitWindow?) -> String {
        switch progress.state {
        case .active:
            guard let window else { return "时间未知" }
            return UsageFormatting.resetPointText(window)
        case .arrived: return "等待刷新"
        case .unknown: return "时间未知"
        case .invalid: return "时间不可用"
        }
    }

    private func fraction(_ window: RateLimitWindow?) -> Double {
        guard let window, window.remainingPercent.isFinite else { return 0 }
        return min(max(window.remainingPercent / 100, 0), 1)
    }

    private func quotaColor(_ window: RateLimitWindow?) -> Color {
        guard let window, window.remainingPercent.isFinite else { return .secondary }
        switch UsageFormatting.usageLevel(remainingPercent: window.remainingPercent) {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(UsageFormatting.rateLimitResetText(snapshot?.rateLimitResetCredits,
                                                    source: snapshot?.source ?? .cached))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .accessibilityLabel("可用重置")

            Spacer(minLength: 4)

            Text(state.fireResultText)
                .font(.system(size: 11))
                .foregroundStyle(fireResultColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("点火状态")
                .accessibilityValue(state.fireResult == nil ? "未点火" : state.fireStatusText)
                .help(state.fireHistoryLines.isEmpty
                      ? state.fireStatusText
                      : state.fireHistoryLines.joined(separator: "\n"))
            if let drift = state.fireDriftText {
                Text("· \(drift)")
                    .font(.system(size: 11))
                    .foregroundStyle(fireResultColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var fireResultColor: Color {
        guard let result = state.fireResult else { return .secondary }
        if result.isSuccess { return .green }
        if result.isFailure { return .orange }
        return .secondary
    }
}

/// The quota remainder track: bright from the left, shrinking towards the left as the quota is
/// consumed (1.2.1 behaviour).
struct QuotaRemainderBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                Capsule(style: .continuous)
                    .fill(color.opacity(0.86))
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: CodexProfileCard.quotaTrackHeight)
        .accessibilityHidden(true)
    }
}

/// Uses a UI derivative of the official OpenAI SVG whose viewBox follows the visible blossom.
/// The untouched downloaded assets remain in `assets/brand`; cropping at the vector viewBox
/// keeps the small mark sharp and avoids scaling an already-laid-out SwiftUI image.
struct BrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .scaledToFit()
            } else {
                Image(systemName: "circle.hexagongrid.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var image: NSImage? {
        let variant = colorScheme == .dark ? "White" : "Black"
        for resourceName in [
            "OAI_OpenAI-Blossom_\(variant)-UI.svg",
            "OAI_OpenAI-Blossom_\(variant).svg",
            "OAI_OpenAI-Blossom_\(variant).png"
        ] {
            let parts = resourceName.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let path = Bundle.main.path(forResource: parts[0], ofType: parts[1]),
                  let image = NSImage(contentsOfFile: path) else { continue }
            image.isTemplate = true
            return image
        }
        return nil
    }
}

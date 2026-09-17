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
    static let contentPadding: CGFloat = 10
    static let rowSpacing: CGFloat = 1
    static let windowGroupSpacing: CGFloat = 4
    static let headerHeight: CGFloat = 26
    static let accountRowHeight: CGFloat = 13
    static let windowBlockHeight: CGFloat = 25
    static let footerHeight: CGFloat = 13
    static let labelWidth: CGFloat = 46
    static let valueWidth: CGFloat = 92
    static let quotaTrackHeight: CGFloat = 6

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
    /// Invoked only after the user confirms the fixed dialog.
    var onFire: (() -> Void)?

    @State private var showsFireConfirmation = false
    /// One clock reading per body evaluation, shared by both reset rails.
    private let now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            headerRow.frame(height: Self.headerHeight)
            accountRow.frame(height: Self.accountRowHeight)
            windowBlock(label: "5 小时", kind: .fiveHour, window: snapshot?.fiveHour)
                .frame(height: Self.windowBlockHeight)
                .padding(.bottom, Self.windowGroupSpacing - Self.rowSpacing)
            windowBlock(label: "周额度", kind: .weekly, window: snapshot?.weekly)
                .frame(height: Self.windowBlockHeight)
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
        HStack(alignment: .center, spacing: 8) {
            BrandMark()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(state.profile.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(state.displayPlanType ?? "套餐暂不可用")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            fireButton
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
        .accessibilityLabel("\(state.profile.displayName) \(Self.fireButtonTitle)")
    }

    // MARK: Account row

    private var accountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(state.connectionText)
                .font(.system(size: 9))
                .foregroundStyle(connectionColor)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            Text(state.displayEmail ?? "账号暂不可用")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .accessibilityLabel("账号")
                .accessibilityValue(state.displayEmail ?? "账号暂不可用")
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
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: Self.labelWidth, alignment: .leading)
                QuotaRemainderBar(fraction: fraction(window), color: quotaColor(window))
                    .frame(maxWidth: .infinity)
                Text(Self.quotaValueText(window))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(window == nil ? Color.secondary : quotaColor(window))
                    .lineLimit(1)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Text("重置时间")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth, alignment: .leading)
                ProviderTimeBar(progress: Self.timeProgress(progress),
                                isCached: state.isStale,
                                tint: .blue)
                    .frame(maxWidth: .infinity)
                Text(Self.resetValueText(progress, window: window))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)
                .accessibilityLabel("可用重置")

            Spacer(minLength: 4)

            // The fire result keeps its full text; the credits line gives up room first.
            Text(state.fireResult?.displayText ?? "")
                .font(.system(size: 9))
                .foregroundStyle(fireResultColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .accessibilityLabel("点火状态")
                .accessibilityValue(state.fireResult?.displayText ?? "未点火")
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

/// The OpenAI Blossom mark, at the card's 26 pt canvas.
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
        for resourceName in ["OAI_OpenAI-Blossom_\(variant).svg", "OAI_OpenAI-Blossom_\(variant).png"] {
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

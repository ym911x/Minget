import AppKit
import SwiftUI
import UsageMonitorCore

/// The same quota composition used for Gemini, with provider-specific actions below it.
struct CodexProfileCard: View {
    static let size = CGSize(width: DetailPageLayout.contentWidth, height: DetailPageLayout.codexCardHeight)
    static let contentPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 4
    static let windowGroupSpacing: CGFloat = 12
    static let headerHeight: CGFloat = 34
    static let accountRowHeight: CGFloat = 16
    static let headerToWindowSpacing: CGFloat = 12
    static let windowBlockHeight: CGFloat = 40
    static let footerHeight: CGFloat = 28
    static let footerSpacing: CGFloat = 12
    static let labelWidth: CGFloat = 50
    static let valueWidth: CGFloat = 122
    static let quotaTrackHeight: CGFloat = 6
    static let logoSize: CGFloat = 28
    static let fireButtonWidth: CGFloat = 96
    static let fireButtonHeight: CGFloat = 26
    static let fireButtonTitle = "5 小时点火"
    static let fireButtonRunningTitle = "点火中…"
    static let confirmationTitle = "启动 5 小时额度窗口？"
    static let confirmationMessage = "将通过该账号执行一次真实 Codex 请求，会消耗少量额度。Minget 不会读取账号认证文件。"
    static let confirmButtonTitle = "确认点火"
    static let cancelButtonTitle = "取消"

    let state: CodexProfileViewState
    let displayName: String
    var onFire: (() -> Void)?
    @State private var showsFireConfirmation = false

    init(state: CodexProfileViewState, displayName: String? = nil, onFire: (() -> Void)? = nil) {
        self.state = state
        self.displayName = displayName ?? state.profile.displayName
        self.onFire = onFire
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AccountCardHeader(service: .chatGPT, name: displayName,
                              subtitle: state.displayPlanType ?? "套餐暂不可用",
                              identity: identityText, status: state.connectionText, isCached: state.isStale)
                .frame(height: 50)
            QuotaWindowBlock(label: "5 小时", kind: .fiveHour, window: state.snapshot?.fiveHour, isCached: state.isStale)
            QuotaWindowBlock(label: "周额度", kind: .weekly, window: state.snapshot?.weekly, isCached: state.isStale)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.snapshot.map { "最近成功 " + $0.fetchedAt.formatted(date: .omitted, time: .shortened) } ?? "尚未成功读取")
                        .foregroundStyle(.secondary)
                    Text(state.fireResult == nil
                         ? UsageFormatting.rateLimitResetText(state.snapshot?.rateLimitResetCredits, source: state.snapshot?.source ?? .cached)
                         : state.fireStatusText)
                        .foregroundStyle(state.fireResult?.isFailure == true ? Color.orange : Color.secondary)
                        .help(state.fireHistoryLines.joined(separator: "\n"))
                        .accessibilityLabel("点火状态")
                        .accessibilityValue(state.fireResult == nil ? "未点火" : state.fireStatusText)
                }.font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 4)
                Button(state.isFiring ? Self.fireButtonRunningTitle : Self.fireButtonTitle) { showsFireConfirmation = true }
                    .buttonStyle(.bordered).controlSize(.small)
                    .frame(width: Self.fireButtonWidth, height: Self.fireButtonHeight)
                    .disabled(state.isFiring || onFire == nil)
                    .accessibilityLabel("\(displayName) \(Self.fireButtonTitle)")
            }.frame(height: Self.footerHeight)
        }
        .quotaCardSurface()
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .confirmationDialog(Self.confirmationTitle, isPresented: $showsFireConfirmation, titleVisibility: .visible) {
            Button(Self.confirmButtonTitle) { onFire?() }
            Button(Self.cancelButtonTitle, role: .cancel) {}
        } message: { Text(Self.confirmationMessage) }
    }

    private var identityText: String {
        [state.identityLabel, state.failureText ?? state.displayEmail ?? state.accountPlaceholder]
            .compactMap { $0 }.joined(separator: " · ")
    }

    static func timeProgress(_ progress: ResetTimeProgress) -> ProviderTimeProgress {
        switch progress.state {
        case .active: return .segments(progress.fills)
        case .arrived: return .arrived
        case .unknown, .invalid: return .unavailable
        }
    }
    static func quotaValueText(_ window: RateLimitWindow?) -> String {
        "剩余 " + QuotaPresentation.percentage(window?.remainingPercent)
    }
    static func resetValueText(_ progress: ResetTimeProgress, window: RateLimitWindow?) -> String {
        switch progress.state {
        case .active: return QuotaPresentation.reset(window?.resetsAt)
        case .arrived: return "等待刷新"
        case .unknown: return "时间未知"
        case .invalid: return "时间不可用"
        }
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

import AppKit
import SwiftUI
import UsageMonitorCore

/// The compact daily overview shown from the menu bar and the regular detail window.
///
/// Connection forms and diagnostics live in `MingetSettingsView`; this view answers the
/// everyday questions first: how much Codex capacity remains, when it resets, and which
/// connected balances are available.
struct UsagePanelView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject private var preferences: DetailPreferences
    var onSettings: (() -> Void)?

    init(model: UsageViewModel,
         preferences: DetailPreferences = .shared,
         onSettings: (() -> Void)? = nil) {
        self.model = model
        _preferences = ObservedObject(wrappedValue: preferences)
        self.onSettings = onSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            codexCard
            providerCards
        }
        .padding(16)
        // The detail page is deliberately a single, non-scrolling surface. Keep the
        // provider-enabled height leaves room for the full Codex card, reset summary and
        // DeepSeek card, including the two-currency balance state, without a trailing blank
        // region that would make the detail page look unfinished.
        .frame(width: 420, height: preferredHeight, alignment: .top)
        .background(.regularMaterial)
        .onAppear { model.panelWillOpen() }
    }

    static func preferredHeight(for preferences: DetailPreferences) -> CGFloat {
        preferences.showDeepSeek ? 420 : 320
    }

    private var preferredHeight: CGFloat {
        Self.preferredHeight(for: preferences)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.productName())
                    .font(.system(size: 22, weight: .bold))
                    .fixedSize()
                Text("v\(appVersion)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Spacer(minLength: 8)

            Button {
                model.refreshNow()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.isRefreshing || model.isProviderRefreshing || model.isDeepSeekStatusRefreshing
                          ? "arrow.triangle.2.circlepath"
                          : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text(updateStatusText)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing || model.isProviderRefreshing || model.isDeepSeekStatusRefreshing)
            .accessibilityLabel("刷新，\(updateStatusText)")

            Button {
                onSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(onSettings == nil)
            .accessibilityLabel("设置")
        }
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.2"
    }

    static func productName(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let preferred = preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("en") ? "Minget" : "明明有数"
    }

    private var updateStatusText: String {
        _ = model.tick
        if model.isRefreshing || model.isProviderRefreshing || model.isDeepSeekStatusRefreshing { return "刷新中…" }

        let visibleReports = model.providerReports.filter { report in
            switch report.platform {
            case .deepseek: return preferences.showDeepSeek
            case .codex: return false
            }
        }
        let hasProviderProblem = visibleReports.contains { report in
            switch report.connection {
            case .stale, .unavailable, .authSuspended, .needsAuthorization, .unverified: return true
            case .notConfigured, .connecting, .connected: return false
            }
        }
        if model.isStale || hasProviderProblem { return "部分数据未更新" }

        var dates: [Date] = []
        if let snapshot = model.currentSnapshot { dates.append(snapshot.fetchedAt) }
        dates.append(contentsOf: visibleReports.compactMap(\.lastSuccessAt))
        guard let fetchedAt = dates.min() else { return "等待更新" }
        return UsageFormatting.updatedText(fetchedAt: fetchedAt)
    }

    // MARK: Codex

    private var codexCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 9) {
                BrandImage(asset: .openAIBlossom, fallbackSystemName: "circle.hexagongrid.circle")
                    .frame(width: 50, height: 50)
                    // The supplied Blossom canvas contains transparent padding. Offset the
                    // original artwork so its visible left edge aligns with the whale mark.
                    .offset(x: -7)

                Text(model.codexAccount?.displayPlanType ?? "套餐暂不可用")
                    .font(.system(size: 20, weight: .bold))

                Spacer(minLength: 8)

                Text(model.codexAccount?.displayEmail ?? "账号暂不可用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel("Codex 套餐")
                    .accessibilityValue(model.codexAccount?.displayEmail ?? "账号暂不可用")
            }

            let snapshot = model.currentSnapshot
            CodexQuotaGrid(fiveHour: snapshot?.fiveHour,
                           weekly: snapshot?.weekly,
                           now: Date())

            Text(UsageFormatting.rateLimitResetText(snapshot?.rateLimitResetCredits,
                                                    source: snapshot?.source ?? .cached))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("OpenAI 可用重置")

            if case .unavailable(let error) = model.displayState {
                Text(UsageFormatting.errorText(error).replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Provider cards

    @ViewBuilder
    private var providerCards: some View {
        let deepSeek = report(for: .deepseek)
        let showDeepSeek = preferences.showDeepSeek

        VStack(spacing: 12) {
            if showDeepSeek {
                DeepSeekOverviewCard(report: deepSeek,
                                     status: model.deepSeekStatus,
                                     openSettings: { onSettings?() })
            }
        }
    }

    private func report(for platform: ProviderPlatform) -> ProviderReport {
        model.providerReports.first { $0.platform == platform }
            ?? ProviderReport(platform: platform,
                              accountID: nil,
                              balances: [],
                              lastSuccessAt: nil,
                              connection: .notConfigured,
                              isLive: false,
                              error: nil,
                              consoleURL: nil)
    }
}

// MARK: - Codex quota grid

private struct CodexQuotaGrid: View {
    let fiveHour: RateLimitWindow?
    let weekly: RateLimitWindow?
    let now: Date

    private let labelWidth: CGFloat = 70
    private let valueWidth: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            quotaRow(label: "5 小时", window: fiveHour, color: quotaColor(fiveHour))
            resetRow(window: fiveHour, count: ResetTimeModel.fiveHourSegmentCount)
            quotaRow(label: "周额度", window: weekly, color: quotaColor(weekly))
            resetRow(window: weekly, count: ResetTimeModel.weeklySegmentCount)
        }
        .accessibilityElement(children: .contain)
    }

    private func quotaRow(label: String,
                           window: RateLimitWindow?,
                           color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: labelWidth, alignment: .leading)

            DetailQuotaBar(fraction: fraction(window), color: color)
                .frame(maxWidth: .infinity)

            Text(window.map { "剩余 \(Int($0.remainingPercent.rounded()))%" } ?? "剩余 —")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(window.map { "剩余 \(Int($0.remainingPercent.rounded()))%" } ?? "额度不可用")")
    }

    private func resetRow(window: RateLimitWindow?, count: Int) -> some View {
        let progress = ResetTimeModel.progress(expected: count == 5 ? .fiveHour : .weekly,
                                               window: window,
                                               now: now)
        let resetText: String
        switch progress.state {
        case .active:
            resetText = window.map(UsageFormatting.resetPointText) ?? "时间未知"
        case .arrived:
            resetText = "等待刷新"
        case .unknown:
            resetText = "时间未知"
        case .invalid:
            resetText = "时间不可用"
        }
        return HStack(spacing: 8) {
            Text("重置时间")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)

            DetailResetBar(progress: progress)
                .frame(maxWidth: .infinity)

            Text(resetText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("重置时间，\(resetText)")
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
}

private struct DetailQuotaBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                Capsule(style: .continuous)
                    .fill(color.opacity(0.86))
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct DetailResetBar: View {
    let progress: ResetTimeProgress

    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let count = progress.fills.count
            let width = count > 0
                ? max(0, (geometry.size.width - CGFloat(count - 1) * gap) / CGFloat(count))
                : 0
            HStack(spacing: gap) {
                ForEach(Array(progress.fills.enumerated()), id: \.offset) { _, fill in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                        Capsule(style: .continuous)
                            .fill(Color.blue)
                            .frame(width: width * min(max(fill, 0), 1))
                    }
                    .frame(width: width, height: 6)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Provider branding and cards

private enum BrandAsset {
    case openAIBlossom
    case deepSeekWhale
}

private struct BrandImage: View {
    let asset: BrandAsset
    let fallbackSystemName: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = image {
            if case .deepSeekWhale = asset {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .colorInvertIfNeeded(colorScheme == .dark)
                    .blendMode(colorScheme == .dark ? .screen : .multiply)
                    .accessibilityHidden(true)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .scaledToFit()
                    .accessibilityHidden(true)
            }
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        }
    }

    private var image: NSImage? {
        let resourceNames: [String]
        switch asset {
        case .openAIBlossom:
            let variant = colorScheme == .dark ? "White" : "Black"
            resourceNames = ["OAI_OpenAI-Blossom_\(variant).svg",
                             "OAI_OpenAI-Blossom_\(variant).png"]
        case .deepSeekWhale:
            resourceNames = ["deepseek-whale-black.png"]
        }
        for resourceName in resourceNames {
            let parts = resourceName.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let path = Bundle.main.path(forResource: parts[0], ofType: parts[1]),
                  let image = NSImage(contentsOfFile: path) else {
                continue
            }
            if case .openAIBlossom = asset {
                image.isTemplate = true
            }
            return image
        }
        return nil
    }
}

private struct DeepSeekWordmarkImage: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .colorInvertIfNeeded(colorScheme == .dark)
                .accessibilityLabel("DeepSeek")
        } else {
            Image(systemName: "textformat")
                .font(.system(size: 15, weight: .medium))
                .accessibilityLabel("DeepSeek")
        }
    }

    private var image: NSImage? {
        guard let path = Bundle.main.path(forResource: "deepseek-wordmark-text-transparent", ofType: "png") else {
            return nil
        }
        return NSImage(contentsOfFile: path)
    }
}

private extension View {
    @ViewBuilder
    func colorInvertIfNeeded(_ shouldInvert: Bool) -> some View {
        if shouldInvert {
            colorInvert()
        } else {
            self
        }
    }
}

private struct DeepSeekOverviewCard: View {
    let report: ProviderReport
    let status: DeepSeekStatusSnapshot
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // There is no verified DeepSeek account field. Put the real balance directly in
            // this brand row so the card does not reserve an empty account slot or a second
            // blank row before the status information.
            // Centering the frames compensates for the whale PNG's internal whitespace and
            // keeps the visible whale, wordmark and amount on one visual axis.
            HStack(alignment: .center, spacing: 10) {
                BrandImage(asset: .deepSeekWhale, fallbackSystemName: "drop.fill")
                    .frame(width: 38, height: 36)

                DeepSeekWordmarkImage()
                    .frame(width: 128, height: 28, alignment: .leading)

                Spacer(minLength: 12)

                balanceSummary
            }

            serviceStatusRow
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var balanceSummary: some View {
        if !report.balances.isEmpty,
           report.connection == .connected || report.connection == .stale {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(Array(report.balances.enumerated()), id: \.offset) { _, balance in
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(DecimalFormatting.overviewBalanceLabel(balance))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(DecimalFormatting.overviewBalanceText(balance))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                Button(report.connection == .notConfigured ? "前往设置" : "查看设置") {
                    openSettings()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    private var serviceStatusRow: some View {
        HStack(spacing: 5) {
            Text(connectionText)
                .font(.system(size: 10))
                .foregroundStyle(connectionColor)
                .fixedSize(horizontal: true, vertical: false)
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(status.status.displayTitle)
                .font(.system(size: 10))
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: true, vertical: false)
            Button("状态页") {
                NSWorkspace.shared.open(DeepSeekStatusProvider.statusPageURL)
            }
            .buttonStyle(.link)
            .font(.system(size: 10))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var connectionText: String {
        switch report.connection {
        case .connected: return "已连接"
        case .stale: return "缓存数据"
        case .connecting: return "正在获取"
        case .notConfigured: return "未连接"
        case .authSuspended, .needsAuthorization: return "需要重新连接"
        case .unavailable, .unverified: return "暂不可用"
        }
    }

    private var connectionColor: Color {
        switch report.connection {
        case .connected: return .green
        case .stale: return .orange
        default: return .secondary
        }
    }

    private var statusColor: Color {
        switch status.status {
        case .operational: return .green
        case .degraded, .maintenance: return .orange
        case .outage: return .red
        case .unknown: return .secondary
        }
    }
}

// MARK: - Provider overview card

private struct ProviderOverviewCard: View {
    let report: ProviderReport
    let icon: String
    let tint: Color
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.platform.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }

            if !report.balances.isEmpty,
               report.connection == .connected || report.connection == .stale {
                ForEach(Array(report.balances.enumerated()), id: \.offset) { _, balance in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(DecimalFormatting.overviewBalanceText(balance))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(DecimalFormatting.overviewBalanceLabel(balance))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button(report.connection == .notConfigured ? "前往设置" : "查看设置") {
                    openSettings()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch report.connection {
        case .connected: return "● 已连接"
        case .stale: return "● 缓存数据"
        case .connecting: return "正在获取…"
        case .notConfigured: return "未连接"
        case .authSuspended, .needsAuthorization: return "需要重新连接"
        case .unavailable, .unverified: return "暂不可用"
        }
    }

    private var statusColor: Color {
        switch report.connection {
        case .connected: return .green
        case .stale: return .orange
        default: return .secondary
        }
    }
}

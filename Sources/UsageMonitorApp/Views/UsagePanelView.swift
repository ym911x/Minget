import AppKit
import SwiftUI
import UsageMonitorCore

/// Fixed geometry of the detail page, as one pure model the view and the tests both read.
///
/// The page is a single 440 pt column — one card per row, top to bottom
/// ChatGPT A, ChatGPT B, DeepSeek, Command Code — and every state fits on one screen with no
/// scroll container. Keeping the arithmetic here means the layout tests assert the same
/// numbers the view lays out, instead of re-deriving them.
enum DetailPageLayout {

    static let pageWidth: CGFloat = 440
    static let margin: CGFloat = 12
    static let contentWidth: CGFloat = 416
    static let headerHeight: CGFloat = 36
    /// Every vertical gap on the page is this.
    static let rowSpacing: CGFloat = 6

    static let codexCardHeight: CGFloat = 129
    static let deepSeekCardHeight: CGFloat = 48
    static let commandCodeCardHeight: CGFloat = 162

    enum Kind: String, Equatable, Sendable {
        case header, chatGPTA, chatGPTB, deepSeek, commandCode
    }

    struct Row: Equatable {
        let kind: Kind
        let frame: CGRect
    }

    /// The visible rows, in draw order, with the frame each one occupies.
    static func rows(showDeepSeek: Bool, showCommandCode: Bool) -> [Row] {
        var rows: [Row] = []
        var y = margin
        func append(_ kind: Kind, _ height: CGFloat) {
            rows.append(Row(kind: kind,
                            frame: CGRect(x: margin, y: y, width: contentWidth, height: height)))
            y += height + rowSpacing
        }
        append(.header, headerHeight)
        append(.chatGPTA, codexCardHeight)
        append(.chatGPTB, codexCardHeight)
        if showDeepSeek { append(.deepSeek, deepSeekCardHeight) }
        if showCommandCode { append(.commandCode, commandCodeCardHeight) }
        return rows
    }

    /// 552 with both service cards, 498 with only Command Code, 384 with only DeepSeek,
    /// 330 with neither.
    static func pageHeight(showDeepSeek: Bool, showCommandCode: Bool) -> CGFloat {
        guard let last = rows(showDeepSeek: showDeepSeek, showCommandCode: showCommandCode).last else {
            return margin * 2
        }
        return last.frame.maxY + margin
    }
}

/// The daily overview shown from the menu bar and the regular detail window.
///
/// One column, four cards, no scroll container of any kind. The popover and the regular
/// detail window render this same view at this same size, so the two presentations cannot
/// drift apart.
struct UsagePanelView: View {

    // Convenience aliases so existing call sites and tests keep reading the page constants
    // from the view. The values live in `DetailPageLayout`.
    static var pageWidth: CGFloat { DetailPageLayout.pageWidth }
    static var margin: CGFloat { DetailPageLayout.margin }
    static var contentWidth: CGFloat { DetailPageLayout.contentWidth }
    static var headerHeight: CGFloat { DetailPageLayout.headerHeight }
    static var rowSpacing: CGFloat { DetailPageLayout.rowSpacing }
    static var pageHeightWithServices: CGFloat { DetailPageLayout.pageHeight(showDeepSeek: true, showCommandCode: true) }
    static var pageHeightWithoutServices: CGFloat { DetailPageLayout.pageHeight(showDeepSeek: false, showCommandCode: false) }

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
        VStack(alignment: .leading, spacing: DetailPageLayout.rowSpacing) {
            header
            ForEach(model.profileStates) { state in
                CodexProfileCard(state: state) {
                    model.fire(profileID: state.profile.id)
                }
            }
            if preferences.showDeepSeek {
                DeepSeekOverviewCard(report: report(for: .deepseek),
                                     status: model.deepSeekStatus,
                                     openSettings: { onSettings?() })
            }
            if preferences.showCommandCode {
                CommandCodeOverviewCard(report: report(for: .commandcode),
                                        openSettings: { onSettings?() })
            }
        }
        .padding(DetailPageLayout.margin)
        .frame(width: DetailPageLayout.pageWidth, height: preferredHeight, alignment: .top)
        .background(.regularMaterial)
        .onAppear { model.panelWillOpen() }
    }

    static func preferredHeight(for preferences: DetailPreferences) -> CGFloat {
        DetailPageLayout.pageHeight(showDeepSeek: preferences.showDeepSeek,
                                    showCommandCode: preferences.showCommandCode)
    }

    private var preferredHeight: CGFloat {
        Self.preferredHeight(for: preferences)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.productName())
                    .font(.system(size: 20, weight: .bold))
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
                    Image(systemName: isAnyRefreshInFlight
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
            .disabled(isAnyRefreshInFlight)
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
        .frame(height: DetailPageLayout.headerHeight)
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.0"
    }

    static func productName(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let preferred = preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("en") ? "Minget" : "明明有数"
    }

    private var isAnyRefreshInFlight: Bool {
        model.isRefreshing || model.isProviderRefreshing || model.isDeepSeekStatusRefreshing
    }

    /// The global line aggregates every visible source: both ChatGPT profiles and every
    /// displayed provider card. Reporting only account A would hide a stalled account B.
    private var updateStatusText: String {
        _ = model.tick
        if isAnyRefreshInFlight { return "刷新中…" }

        let hasProviderProblem = visibleReports.contains { report in
            switch report.connection {
            case .stale, .unavailable, .authSuspended, .needsAuthorization, .unverified: return true
            case .notConfigured, .connecting, .connected: return false
            }
        }
        if model.isStale || hasProviderProblem { return "部分数据未更新" }

        var dates: [Date] = model.codexSnapshotDates
        dates.append(contentsOf: visibleReports.compactMap(\.lastSuccessAt))
        guard let fetchedAt = dates.min() else { return "等待更新" }
        return UsageFormatting.updatedText(fetchedAt: fetchedAt)
    }

    private var visibleReports: [ProviderReport] {
        model.providerReports.filter { report in
            switch report.platform {
            case .deepseek: return preferences.showDeepSeek
            case .commandcode: return preferences.showCommandCode
            case .codex: return false
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

// MARK: - Shared track drawing

/// The empty track plus the filled remainder, drawn from the left so the bright region shrinks
/// from the right as the resource is consumed. Used by the provider cards.
struct ProviderTrackBar: View {
    /// `0...1` remaining, or nil when the value cannot be computed: then only the empty track
    /// is drawn, never a pretend zero.
    let fraction: Double?
    let tint: Color
    let height: CGFloat
    let isCached: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                if let fraction {
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isCached ? 0.45 : 0.86))
                        .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The provider time rail: segments for the 5-hour and weekly windows, one continuous bar for
/// the monthly cycle, and a grey rail with a centred `?` when there is no usable time.
struct ProviderTimeBar: View {
    let progress: ProviderTimeProgress
    let isCached: Bool
    /// Blue on the ChatGPT cards (1.2.1), system indigo on the Command Code card so the two
    /// rails are told apart from that provider's purple credit track.
    var tint: Color = .indigo

    static let height: CGFloat = 3
    static let segmentGap: CGFloat = 2

    var body: some View {
        Group {
            switch progress {
            case .segments(let fills):
                segmented(fills)
            case .continuous(let fraction):
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous).fill(Color.secondary.opacity(0.16))
                        Capsule(style: .continuous)
                            .fill(tint.opacity(isCached ? 0.45 : 0.85))
                            .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                    }
                }
            case .arrived:
                // Emptied out: the app is waiting for the service, not refilling locally.
                Capsule(style: .continuous).fill(Color.secondary.opacity(0.16))
            case .unavailable:
                ZStack {
                    Capsule(style: .continuous).fill(Color.secondary.opacity(0.16))
                    Text("?")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    private func segmented(_ fills: [Double]) -> some View {
        GeometryReader { geometry in
            let count = max(fills.count, 1)
            let width = max(0, (geometry.size.width - CGFloat(count - 1) * Self.segmentGap) / CGFloat(count))
            HStack(spacing: Self.segmentGap) {
                ForEach(Array(fills.enumerated()), id: \.offset) { _, fill in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous).fill(Color.secondary.opacity(0.16))
                        Capsule(style: .continuous)
                            .fill(tint.opacity(isCached ? 0.45 : 0.85))
                            .frame(width: width * min(max(fill, 0), 1))
                    }
                    .frame(width: width)
                }
            }
        }
    }
}

// MARK: - DeepSeek balance strip

/// Selection and ordering of the balances shown in the DeepSeek card.
///
/// REVISION_SPEC.md §6: currency codes ascending with the unknown bucket last, at most three
/// slots, and beyond three the third slot becomes a fixed overflow line. Nothing is converted,
/// nothing is summed.
enum DeepSeekBalanceRows {

    static let stripSlots = 3

    struct Strip: Equatable {
        let amounts: [ProviderBalance]
        let overflowCount: Int

        /// Fixed overflow wording; nil when every balance fits.
        var overflowText: String? {
            guard overflowCount > 0 else { return nil }
            return "另有 \(overflowCount) 个币种"
        }
    }

    static func strip(_ balances: [ProviderBalance]) -> Strip {
        let sorted = ordered(balances)
        guard sorted.count > stripSlots else { return Strip(amounts: sorted, overflowCount: 0) }
        let amountSlots = stripSlots - 1
        return Strip(amounts: Array(sorted.prefix(amountSlots)),
                     overflowCount: sorted.count - amountSlots)
    }

    /// Currency code ascending; a bucket whose currency the response did not name goes last.
    /// Ties keep the provider's own order, so re-rendering cannot reshuffle equal codes.
    static func ordered(_ balances: [ProviderBalance]) -> [ProviderBalance] {
        balances.enumerated().sorted { lhs, rhs in
            let left = normalizedCode(lhs.element.currency)
            let right = normalizedCode(rhs.element.currency)
            switch (left, right) {
            case let (l?, r?): return l == r ? lhs.offset < rhs.offset : l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func normalizedCode(_ currency: String?) -> String? {
        guard let currency, !currency.isEmpty else { return nil }
        return currency.uppercased()
    }
}

// MARK: - Provider branding

private enum BrandAsset {
    case deepSeekWhale
}

private struct BrandImage: View {
    let asset: BrandAsset
    let fallbackSystemName: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .colorInvertIfNeeded(colorScheme == .dark)
                .blendMode(colorScheme == .dark ? .screen : .multiply)
                .accessibilityHidden(true)
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        }
    }

    private var image: NSImage? {
        guard case .deepSeekWhale = asset else { return nil }
        guard let path = Bundle.main.path(forResource: "deepseek-whale-black", ofType: "png") else {
            return nil
        }
        return NSImage(contentsOfFile: path)
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

// MARK: - DeepSeek card (416 × 48)

/// Internal rather than private so the evidence-render tests can compose the card at its fixed
/// size from a fixture report, without standing up a provider engine.
struct DeepSeekOverviewCard: View {

    static let size = CGSize(width: DetailPageLayout.contentWidth, height: DetailPageLayout.deepSeekCardHeight)

    let report: ProviderReport
    let status: DeepSeekStatusSnapshot
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            BrandImage(asset: .deepSeekWhale, fallbackSystemName: "drop.fill")
                .frame(width: 22, height: 22)
            DeepSeekWordmarkImage()
                .frame(width: 66, height: 18, alignment: .leading)

            Button {
                NSWorkspace.shared.open(DeepSeekStatusProvider.statusPageURL)
            } label: {
                HStack(spacing: 4) {
                    Text(connectionText)
                        .font(.system(size: 9))
                        .foregroundStyle(connectionColor)
                        .lineLimit(1)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.system(size: 9))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .lineLimit(1)
            .truncationMode(.tail)
            .help("打开 DeepSeek 状态页")

            Spacer(minLength: 2)
            balanceStrip
                .layoutPriority(2)
        }
        .padding(10)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var balanceStrip: some View {
        if balances.isEmpty {
            Button(report.connection == .notConfigured ? "前往设置" : "查看设置") { openSettings() }
                .buttonStyle(.link)
                .font(.system(size: 10))
        } else {
            ViewThatFits(in: .horizontal) {
                let strip = DeepSeekBalanceRows.strip(balances)
                balanceRow(amounts: strip.amounts, overflowText: strip.overflowText)

                let primary = Array(DeepSeekBalanceRows.ordered(balances).prefix(1))
                balanceRow(amounts: primary,
                           overflowText: balances.count > 1 ? "另有 \(balances.count - 1) 个币种" : nil)
            }
        }
    }

    private func balanceRow(amounts: [ProviderBalance], overflowText: String?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(Array(amounts.enumerated()), id: \.offset) { _, balance in
                Text("\(amountText(balance)) \(balance.currency ?? "币种未确认")")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("\(balance.currency ?? "币种未确认") \(amountText(balance))")
            }
            if let overflowText {
                Text(overflowText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// The main amount prefers `available`, then `total`. A balance with neither is not a
    /// zero: it shows the placeholder.
    private func amountText(_ balance: ProviderBalance) -> String {
        guard let main = balance.available ?? balance.total else { return "—" }
        return DecimalFormatting.amountText(main)
    }

    /// Only a connected or cached report may show amounts at all.
    private var balances: [ProviderBalance] {
        guard report.connection == .connected || report.connection == .stale else { return [] }
        return report.balances
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

    /// The single-line card keeps the official state meaningful without spending the width
    /// of the previous second row. The unknown state is the only provider title shortened.
    private var statusText: String {
        status.status == .unknown ? "状态未知" : status.status.displayTitle
    }
}

// MARK: - Command Code card (416 × 162)

/// Internal rather than private for the same reason as the DeepSeek card.
struct CommandCodeOverviewCard: View {

    static let size = CGSize(width: DetailPageLayout.contentWidth, height: DetailPageLayout.commandCodeCardHeight)
    static let windowBlockHeight: CGFloat = 25
    static let windowGroupSpacing: CGFloat = 4
    static let headerHeight: CGFloat = 24
    static let summaryHeight: CGFloat = 33
    static let valueWidth: CGFloat = 116

    let report: ProviderReport
    let openSettings: () -> Void
    /// Injected so the render tests can pin one clock reading.
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header.frame(height: Self.headerHeight)
            ForEach(CommandCodeCardPresentation.windowKinds, id: \.self) { kind in
                windowBlock(kind)
                    .frame(height: Self.windowBlockHeight)
                    .padding(.bottom, kind == .billingPeriod ? 0 : Self.windowGroupSpacing - 1)
            }
            summary.frame(height: Self.summaryHeight)
        }
        .padding(10)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    /// Cached numbers stay on display but every track is drawn fainter.
    private var isCached: Bool { report.connection == .stale }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            CommandCodeLogomark()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text("Command Code").font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text(report.usage?.planName ?? connectionText)
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if report.usage == nil {
                Button(report.connection == .notConfigured ? "前往设置" : "查看设置") { openSettings() }
                    .buttonStyle(.link).font(.system(size: 10))
            }
        }
    }

    // MARK: Window rows

    /// One window: a remaining-credit track above its own reset-time rail
    /// (REVISION_SPEC.md §7.1–§7.3).
    private func windowBlock(_ kind: ProviderUsageWindow.Kind) -> some View {
        let window = window(kind)
        let time = ProviderTimeModel.progress(kind: kind,
                                             window: window,
                                             billingPeriodStart: report.usage?.billingPeriodStart,
                                             billingPeriodEnd: report.usage?.billingPeriodEnd,
                                             now: now)
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(CommandCodeCardPresentation.label(kind))
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 46, alignment: .leading)
                ProviderTrackBar(fraction: window?.remainingFraction,
                                 tint: .purple,
                                 height: 5,
                                 isCached: isCached)
                    .frame(maxWidth: .infinity)
                Text(CommandCodeCardPresentation.quotaText(window))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("重置时间")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)
                ProviderTimeBar(progress: time.progress, isCached: isCached)
                    .frame(maxWidth: .infinity)
                Text(CommandCodeCardPresentation.timeText(kind: kind,
                                                          window: window,
                                                          usage: report.usage,
                                                          outcome: time,
                                                          now: now))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
        }
    }

    private func window(_ kind: ProviderUsageWindow.Kind) -> ProviderUsageWindow? {
        report.usage?.windows.first { $0.kind == kind }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(CommandCodeCardPresentation.summaryLines(report.usage?.summary).enumerated()),
                    id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 11, alignment: .leading)
            }
        }
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
}

/// Pure text rules for the Command Code card, kept out of the view so the fixed three-row
/// structure, the remaining-credit wording and the placeholder rules are testable without
/// AppKit.
enum CommandCodeCardPresentation {

    /// Fixed quota-row order (UI_SPEC.md §6).
    static let windowKinds: [ProviderUsageWindow.Kind] = [.fiveHour, .weekly, .billingPeriod]

    static func label(_ kind: ProviderUsageWindow.Kind) -> String {
        switch kind {
        case .fiveHour: return "5 小时"
        case .weekly: return "周额度"
        case .billingPeriod: return "本月"
        }
    }

    /// `$3.00 / $4.00`, built only from values the service actually reported. The track carries
    /// the approximate proportion, so the compact right-hand text does not repeat a percentage.
    static func quotaText(_ window: ProviderUsageWindow?) -> String {
        guard let window else { return "—" }
        if let remaining = window.effectiveRemaining {
            if let limit = window.limit {
                return "\(UsageFormatting.usdAmount(remaining)) / \(UsageFormatting.usdAmount(limit))"
            }
            return "\(UsageFormatting.usdAmount(remaining)) / —"
        }
        if let limit = window.limit { return "— / \(UsageFormatting.usdAmount(limit))" }
        return "—"
    }

    /// Five-hour and weekly windows show only the reset point. The monthly cycle keeps the
    /// remaining-day context because its span is substantially longer.
    static func timeText(kind: ProviderUsageWindow.Kind,
                         window: ProviderUsageWindow?,
                         usage: ProviderUsage?,
                         outcome: ProviderTimeModel.Outcome,
                         now: Date) -> String {
        switch outcome.progress {
        case .unavailable:
            return "时间未知"
        case .arrived:
            return "等待刷新"
        case .segments, .continuous:
            if kind == .billingPeriod {
                let remainingText = ProviderTimeFormatting.dayText(outcome.remainingSeconds)
                guard let absolute = usage?.billingPeriodEnd.map(UsageFormatting.shortDate) else {
                    return "剩余 \(remainingText)"
                }
                return "剩余 \(remainingText) · \(absolute)"
            }
            return window?.resetsAt.map(UsageFormatting.shortDateTime) ?? "时间未知"
        }
    }

    /// Exactly three single-line summaries, in the fixed order. Any field the service did not
    /// report is a `—`, never a fabricated zero and never an extra line.
    static func summaryLines(_ summary: ProviderUsageSummary?) -> [String] {
        [
            "\(periodText(summary?.periodBasis)) · Token \(count(summary?.totalTokens)) · 请求 \(count(summary?.totalRuns))",
            "输入 \(count(summary?.inputTokens)) · 输出 \(count(summary?.outputTokens)) · 成功 \(count(summary?.completedRuns)) · 失败 \(count(summary?.failedRuns))",
            "成功率 \(percent(summary?.successRate)) · 成本 \(UsageFormatting.usdAmount(summary?.totalCostUSD))",
        ]
    }

    static func periodText(_ period: ProviderUsageSummary.PeriodBasis?) -> String {
        switch period {
        case .billingPeriod: return "当前计费周期"
        case .last30Days: return "近 30 天"
        case .unknown, .none: return "统计周期未确认"
        }
    }

    static func count(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    static func percent(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return NSDecimalNumber(decimal: value).stringValue + "%"
    }
}

private struct CommandCodeLogomark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let resource = colorScheme == .dark ? "commandcode-symbol" : "commandcode-symbol-black"
        Group {
            if let url = Bundle.main.url(forResource: resource, withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(Color.purple)
            }
        }
        .accessibilityLabel("Command Code")
    }
}

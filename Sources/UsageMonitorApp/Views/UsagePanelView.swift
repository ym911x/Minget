import AppKit
import SwiftUI
import UsageMonitorCore

/// Fixed geometry of the detail page, as one pure model the view and the tests both read.
///
/// The page is a single 440 pt column — one card per row, top to bottom
/// ChatGPT A, ChatGPT B, DeepSeek, Command Code. The preferred height describes the complete
/// page; callers may provide a smaller viewport and the card stack will then scroll.
enum DetailPageLayout {

    static let pageWidth: CGFloat = 440
    static let margin: CGFloat = 12
    static let contentWidth: CGFloat = 416
    static let headerHeight: CGFloat = 36
    /// The gap between the header and cards, and between cards.
    static let rowSpacing: CGFloat = 8

    static let codexCardHeight: CGFloat = 178
    static let deepSeekCardHeight: CGFloat = 72
    static let commandCodeCardHeight: CGFloat = 281

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

    /// Complete preferred height with both service cards is 801 pt. A shorter viewport is
    /// intentionally supported by `UsagePanelView` for small screens.
    static func pageHeight(showDeepSeek: Bool, showCommandCode: Bool) -> CGFloat {
        guard let last = rows(showDeepSeek: showDeepSeek, showCommandCode: showCommandCode).last else {
            return margin * 2
        }
        return last.frame.maxY + margin
    }

    static func viewportHeight(preferredHeight: CGFloat, visibleFrame: CGRect?, inset: CGFloat = 8) -> CGFloat {
        guard let visibleFrame, visibleFrame.height > 0 else { return preferredHeight }
        return min(preferredHeight, max(280, visibleFrame.height - inset * 2))
    }
}

/// The daily overview shown from the menu bar and the regular detail window.
///
/// One column, four cards. The popover and the regular detail window render this same view;
/// only a viewport that cannot contain the preferred page gets a vertical scroll region.
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
    @ObservedObject private var displayNames: DisplayNamePreferences
    var onSettings: (() -> Void)?
    private let maxHeight: CGFloat?

    init(model: UsageViewModel,
         preferences: DetailPreferences = .shared,
         displayNames: DisplayNamePreferences? = nil,
         maxHeight: CGFloat? = nil,
         onSettings: (() -> Void)? = nil) {
        self.model = model
        _preferences = ObservedObject(wrappedValue: preferences)
        _displayNames = ObservedObject(wrappedValue: displayNames ?? model.displayNames)
        self.maxHeight = maxHeight
        self.onSettings = onSettings
    }

    var body: some View {
        let preferred = Self.preferredHeight(for: preferences)
        let viewport = min(preferred, maxHeight ?? preferred)
        let cardViewport = max(0, viewport - DetailPageLayout.margin * 2 - DetailPageLayout.headerHeight)

        VStack(alignment: .leading, spacing: 0) {
            header
            if viewport < preferred {
                ScrollView(.vertical, showsIndicators: true) {
                    cardStack
                }
                .frame(height: cardViewport)
            } else {
                cardStack
            }
        }
        .padding(DetailPageLayout.margin)
        .frame(width: DetailPageLayout.pageWidth, height: viewport, alignment: .top)
        .background(.regularMaterial)
        .onAppear { model.panelWillOpen() }
    }

    @ViewBuilder
    private var cardStack: some View {
        VStack(alignment: .leading, spacing: DetailPageLayout.rowSpacing) {
            ForEach(model.profileStates) { state in
                CodexProfileCard(state: state,
                                 displayName: displayNames.displayName(for: state.profile.id)) {
                    model.fire(profileID: state.profile.id)
                }
            }
            if preferences.showDeepSeek {
                DeepSeekOverviewCard(report: report(for: .deepseek),
                                     status: model.deepSeekStatus,
                                     displayName: displayNames.displayName(for: DisplayNamePreferences.ServiceID.deepSeek),
                                     openSettings: { onSettings?() })
            }
            if preferences.showCommandCode {
                CommandCodeOverviewCard(report: report(for: .commandcode),
                                        displayName: displayNames.displayName(for: DisplayNamePreferences.ServiceID.commandCode),
                                        fireState: model.commandCodeFireState,
                                        onFire: { model.fireCommandCode() },
                                        openSettings: { onSettings?() })
            }
        }
        .padding(.top, DetailPageLayout.rowSpacing)
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
            HStack(alignment: .lastTextBaseline, spacing: 6) {
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4.1"
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
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(colorScheme == .dark
                    ? Color.white
                    : Color(red: 2 / 255, green: 13 / 255, blue: 54 / 255))
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
        guard let path = Bundle.main.path(forResource: "deepseek-whale-ui", ofType: "png"),
              let image = NSImage(contentsOfFile: path) else {
            return nil
        }
        image.isTemplate = true
        return image
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

// MARK: - DeepSeek card (416 × 72)

/// Internal rather than private so the evidence-render tests can compose the card at its fixed
/// size from a fixture report, without standing up a provider engine.
struct DeepSeekOverviewCard: View {

    static let size = CGSize(width: DetailPageLayout.contentWidth, height: DetailPageLayout.deepSeekCardHeight)
    static let logoSize: CGFloat = 34

    let report: ProviderReport
    let status: DeepSeekStatusSnapshot
    var displayName: String = "DeepSeek"
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandImage(asset: .deepSeekWhale, fallbackSystemName: "drop.fill")
                .frame(width: Self.logoSize, height: Self.logoSize)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    balanceStrip
                        .layoutPriority(2)
                }

                HStack(spacing: 5) {
                    DeepSeekWordmarkImage()
                        .frame(width: 66, height: 16, alignment: .leading)
                    connectionIndicator
                    Spacer(minLength: 4)
                    Button {
                        NSWorkspace.shared.open(DeepSeekStatusProvider.statusPageURL)
                    } label: {
                        HStack(spacing: 5) {
                            Text(statusText)
                                .font(.system(size: 11))
                                .foregroundStyle(statusColor)
                                .lineLimit(1)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("打开 DeepSeek 状态页")
                }
            }
        }
        .padding(12)
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("\(balance.currency ?? "币种未确认") \(amountText(balance))")
            }
            if let overflowText {
                Text(overflowText)
                    .font(.system(size: 10))
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

    @ViewBuilder
    private var connectionIndicator: some View {
        if report.connection == .connected {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .accessibilityLabel("已连接")
        } else {
            Text(connectionText)
                .font(.system(size: 11))
                .foregroundStyle(connectionColor)
                .lineLimit(1)
                .accessibilityLabel(connectionText)
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

    /// The status link keeps the official state meaningful without adding a third row.
    private var statusText: String {
        switch status.status {
        case .operational: return "服务器正常"
        case .degraded: return "服务器有波动"
        case .outage: return "服务器中断"
        case .maintenance: return "服务器维护中"
        case .unknown: return "服务器状态暂不可用"
        }
    }
}

// MARK: - Command Code card (416 × 281)

/// Internal rather than private for the same reason as the DeepSeek card.
struct CommandCodeOverviewCard: View {

    static let size = CGSize(width: DetailPageLayout.contentWidth, height: DetailPageLayout.commandCodeCardHeight)
    static let windowBlockHeight: CGFloat = 32
    static let windowGroupSpacing: CGFloat = 10
    static let headerHeight: CGFloat = 36
    static let headerToWindowSpacing: CGFloat = 12
    static let quotaToSummarySpacing: CGFloat = 12
    static let summaryHeadingHeight: CGFloat = 17
    static let summaryLineHeight: CGFloat = 18
    static let summaryToFooterSpacing: CGFloat = 12
    static let footerHeight: CGFloat = 16
    static let valueWidth: CGFloat = 116
    static let fireButtonWidth: CGFloat = 76
    static let fireButtonTitle = "5 小时点火"
    static let fireButtonRunningTitle = "点火中…"
    static let confirmationTitle = "启动 Command Code 5 小时额度窗口？"
    static let confirmationMessage = "将把钥匙串中的 Command Code Key 交给官方 CLI 执行一次最小模型请求，会消耗少量额度。输出不会保存。"
    static let confirmButtonTitle = "确认点火"
    static let cancelButtonTitle = "取消"

    let report: ProviderReport
    var displayName: String = "Command Code"
    var fireState = CommandCodeFireViewState()
    var onFire: (() -> Void)? = nil
    let openSettings: () -> Void
    /// Injected so the render tests can pin one clock reading.
    var now: Date = Date()
    @State private var showsFireConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.frame(height: Self.headerHeight)
            Spacer().frame(height: Self.headerToWindowSpacing)
            ForEach(CommandCodeCardPresentation.windowKinds, id: \.self) { kind in
                windowBlock(kind)
                    .frame(height: Self.windowBlockHeight)
                if kind != .billingPeriod {
                    Spacer().frame(height: Self.windowGroupSpacing)
                }
            }
            Spacer().frame(height: Self.quotaToSummarySpacing)
            summary
            Spacer().frame(height: Self.summaryToFooterSpacing)
            fireFooter.frame(height: Self.footerHeight)
        }
        .padding(12)
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

    /// Report-level cache state applies to every row. Auxiliary components retain their own
    /// freshness because a live credits read may legitimately reuse older enrichment data.
    private var isCached: Bool { report.connection == .stale }
    private var summaryFreshness: ProviderUsageComponentFreshness? { report.usage?.summaryFreshness }
    private var subscriptionFreshness: ProviderUsageComponentFreshness? { report.usage?.subscriptionFreshness }
    private var planFreshness: ProviderUsageComponentFreshness? {
        guard report.usage?.planName?.isEmpty == false else { return nil }
        return subscriptionFreshness
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            CommandCodeHeaderIdentity(displayName: displayName,
                                      connection: report.connection,
                                      planName: report.usage?.planName,
                                      lastSuccessAt: report.lastSuccessAt,
                                      planFreshness: planFreshness)
            Spacer(minLength: 8)
            if report.usage == nil && report.connection == .notConfigured {
                Button(report.connection == .notConfigured ? "前往设置" : "查看设置") { openSettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            } else {
                Button {
                    showsFireConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        if fireState.isFiring { ProgressView().controlSize(.small) }
                        Text(fireState.isFiring ? Self.fireButtonRunningTitle : Self.fireButtonTitle)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .frame(width: Self.fireButtonWidth, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(fireState.isFiring)
                .accessibilityLabel("\(displayName) \(Self.fireButtonTitle)")
            }
        }
        // The cached state must be readable, not just implied by the fainter tracks.
        .help(CommandCodeCardPresentation.helpText(connection: report.connection,
                                                   lastSuccessAt: report.lastSuccessAt,
                                                   planFreshness: planFreshness))
    }

    // MARK: Window rows

    /// One window: a remaining-credit track above its own reset-time rail
    /// (REVISION_SPEC.md §7.1–§7.3).
    private func windowBlock(_ kind: ProviderUsageWindow.Kind) -> some View {
        let window = window(kind)
        let usesCachedSummary = summaryFreshness?.isCached == true
            && window?.used != nil
        let usesCachedSubscription = subscriptionFreshness?.isCached == true
            && (report.usage?.billingPeriodStart != nil || report.usage?.billingPeriodEnd != nil)
        let rowIsCached = isCached || (kind == .billingPeriod
            && (usesCachedSummary || usesCachedSubscription))
        let time = ProviderTimeModel.progress(kind: kind,
                                             window: window,
                                             billingPeriodStart: report.usage?.billingPeriodStart,
                                             billingPeriodEnd: report.usage?.billingPeriodEnd,
                                             now: now)
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(CommandCodeCardPresentation.label(kind))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 46, alignment: .leading)
                ProviderTrackBar(fraction: window?.remainingFraction,
                                 tint: .purple,
                                 height: 5,
                                 isCached: rowIsCached)
                    .frame(maxWidth: .infinity)
                Text(CommandCodeCardPresentation.quotaText(window))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(rowIsCached ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("重置时间")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)
                ProviderTimeBar(progress: time.progress, isCached: rowIsCached)
                    .frame(maxWidth: .infinity)
                Text(CommandCodeCardPresentation.timeText(kind: kind,
                                                          window: window,
                                                          usage: report.usage,
                                                          outcome: time,
                                                          now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(rowIsCached ? Color.orange : Color.secondary)
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
        let summaryIsCached = isCached || summaryFreshness?.isCached == true
        return VStack(alignment: .leading, spacing: 0) {
            Text(CommandCodeCardPresentation.periodText(report.usage?.summary?.periodBasis,
                                                        isCached: summaryIsCached))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(summaryIsCached ? Color.orange : Color.secondary)
                .lineLimit(1)
                .frame(height: Self.summaryHeadingHeight, alignment: .leading)
            ForEach(Array(CommandCodeCardPresentation.summaryLines(report.usage?.summary,
                                                                    isCached: summaryIsCached).enumerated()),
                    id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(summaryIsCached ? Color.orange : Color.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: Self.summaryLineHeight, alignment: .leading)
            }
        }
        .help(summaryIsCached
              ? CommandCodeCardPresentation.componentCacheHelpText(name: "统计",
                                                                    freshness: summaryFreshness,
                                                                    fallback: report.lastSuccessAt)
              : "实时统计")
        .accessibilityElement(children: .combine)
        .accessibilityValue(summaryIsCached
                            ? CommandCodeCardPresentation.componentCacheHelpText(name: "统计",
                                                                                 freshness: summaryFreshness,
                                                                                 fallback: report.lastSuccessAt)
                            : "实时统计")
    }

    private var fireFooter: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(fireState.resultText)
                .font(.system(size: 9))
                .foregroundStyle(fireResultColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("点火状态")
                .accessibilityValue(fireState.result == nil ? "未点火" : fireState.statusText)
                .help(fireState.history.isEmpty
                      ? fireState.statusText
                      : fireState.history.map(\.displayLine).joined(separator: "\n"))
            if let drift = fireState.driftText {
                Text("· \(drift)")
                    .font(.system(size: 9))
                    .foregroundStyle(fireResultColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityHidden(true)
            }
        }
    }

    private var fireResultColor: Color {
        guard let result = fireState.result else { return .secondary }
        if result.isSuccess { return .green }
        if result.isFailure { return .orange }
        return .secondary
    }
}

/// The non-interactive part of the Command Code header: logomark, product name and the status
/// line.
///
/// It is a view of its own for two reasons, both about accessibility (REVIEW.md R1):
/// - it is the only part of the header that may be combined into a single accessibility
///   element. Combining a container that holds a `Button` folds the entry into the
///   container: the measured harm is the lost entry element and its own label (VoiceOver
///   only announces the header), so the settings button must stay *outside* this type;
/// - a test can host it alone and assert that no interactive control lives inside it.
struct CommandCodeHeaderIdentity: View {
    var displayName: String = "Command Code"
    let connection: ProviderConnectionState
    let planName: String?
    let lastSuccessAt: Date?
    let planFreshness: ProviderUsageComponentFreshness?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CommandCodeLogomark()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(CommandCodeCardPresentation.brandSubtitle(displayName: displayName,
                                                                     connection: connection,
                                                                     planName: planName,
                                                                     planIsCached: planFreshness?.isCached == true))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        // Only these non-interactive parts are combined, so VoiceOver reads
        // "Command Code, <subtitle>" as one element instead of three fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayName)
        .accessibilityValue(CommandCodeCardPresentation.accessibilitySubtitle(connection: connection,
                                                                              planName: planName,
                                                                              lastSuccessAt: lastSuccessAt,
                                                                              planFreshness: planFreshness))
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

    // MARK: Header subtitle and cache wording

    /// The card's one-line subtitle (REQUIREMENTS.md §5.4). A plan name is only ever appended
    /// to, never replaced: a cached report with a plan says `<套餐> · 缓存`, so the cache state
    /// stays visible instead of being hidden behind the plan name.
    static func subtitle(connection: ProviderConnectionState, planName: String?,
                         planIsCached: Bool = false) -> String {
        let plan = planName.flatMap { $0.isEmpty ? nil : $0 }
        switch connection {
        case .connected:
            return plan.map { planIsCached ? "\($0) · 缓存" : $0 } ?? "已连接"
        case .stale:
            return plan.map { "\($0) · 缓存" } ?? "缓存数据"
        case .connecting: return "正在获取"
        case .notConfigured: return "未连接"
        case .authSuspended, .needsAuthorization: return "需要重新连接"
        case .unavailable, .unverified: return "暂不可用"
        }
    }

    /// A custom card name keeps the fixed brand visible on the second line. When the card uses
    /// the default brand name, the second line shows only the plan or connection state so the
    /// same words are not repeated directly underneath each other.
    static func brandSubtitle(displayName: String,
                              connection: ProviderConnectionState, planName: String?,
                              planIsCached: Bool = false) -> String {
        let detail = subtitle(connection: connection, planName: planName, planIsCached: planIsCached)
        if displayName == "Command Code" { return detail }
        return detail == "已连接" ? "Command Code" : "Command Code · \(detail)"
    }

    /// Fixed cache help text. `MM-dd HH:mm` in the local time zone; no relative time and no
    /// upstream error text. A missing success time is stated rather than guessed.
    static func cacheHelpText(lastSuccessAt: Date?) -> String {
        guard let lastSuccessAt else { return "缓存数据 · 成功时间未知" }
        return "缓存数据 · 上次成功 \(UsageFormatting.shortDateTime(lastSuccessAt))"
    }

    /// Tooltip for the header. Only a cached report needs anything beyond its own subtitle.
    static func helpText(connection: ProviderConnectionState, lastSuccessAt: Date?,
                         planFreshness: ProviderUsageComponentFreshness? = nil) -> String {
        if connection == .stale { return cacheHelpText(lastSuccessAt: lastSuccessAt) }
        if planFreshness?.isCached == true {
            return componentCacheHelpText(name: "套餐", freshness: planFreshness, fallback: lastSuccessAt)
        }
        return subtitle(connection: connection, planName: nil)
    }

    /// Accessibility value: the subtitle always, plus the cache wording when cached, so the
    /// cache semantics survive into assistive technology.
    static func accessibilitySubtitle(connection: ProviderConnectionState,
                                      planName: String?,
                                      lastSuccessAt: Date?,
                                      planFreshness: ProviderUsageComponentFreshness? = nil) -> String {
        let planIsCached = planFreshness?.isCached == true
        let base = subtitle(connection: connection, planName: planName, planIsCached: planIsCached)
        if connection == .stale { return "\(base)，\(cacheHelpText(lastSuccessAt: lastSuccessAt))" }
        guard planIsCached else { return base }
        return "\(base)，\(componentCacheHelpText(name: "套餐", freshness: planFreshness, fallback: lastSuccessAt))"
    }

    static func componentCacheHelpText(name: String,
                                       freshness: ProviderUsageComponentFreshness?,
                                       fallback: Date?) -> String {
        guard let successfulAt = freshness?.lastSuccessfulAt ?? fallback else {
            return "\(name)缓存 · 成功时间未知"
        }
        return "\(name)缓存 · 上次成功 \(UsageFormatting.shortDateTime(successfulAt))"
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
                    return remainingText
                }
                return "\(remainingText) · \(absolute)"
            }
            return window?.resetsAt.map(UsageFormatting.shortDateTime) ?? "时间未知"
        }
    }

    /// Two summary groups keep token/cost data separate from request outcome data. Any field
    /// the service did not report is a `—`, never a fabricated zero.
    static func summaryLines(_ summary: ProviderUsageSummary?, isCached: Bool = false) -> [String] {
        let cachePrefix = isCached ? "缓存 · " : ""
        return [
            "\(cachePrefix)Token \(count(summary?.totalTokens)) · 输入 \(count(summary?.inputTokens)) · 输出 \(count(summary?.outputTokens)) · 成本 \(UsageFormatting.usdAmount(summary?.totalCostUSD))",
            "请求 \(count(summary?.totalRuns)) · 成功 \(count(summary?.completedRuns)) · 失败 \(count(summary?.failedRuns)) · 成功率 \(percent(summary?.successRate))",
        ]
    }

    static func periodText(_ period: ProviderUsageSummary.PeriodBasis?, isCached: Bool = false) -> String {
        let prefix = isCached ? "缓存 · " : ""
        return prefix + periodText(period)
    }

    /// Three fixed period labels. A missing summary is not the same fact as a summary whose
    /// cycle the service did not name: the first says the statistics could not be read at all,
    /// the second says the numbers are real but their window is unconfirmed
    /// (REQUIREMENTS.md §5.3).
    static func periodText(_ period: ProviderUsageSummary.PeriodBasis?) -> String {
        switch period {
        case .billingPeriod: return "当前计费周期"
        case .last30Days: return "近 30 天"
        case .unknown: return "统计周期未确认"
        case .none: return "统计暂不可用"
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

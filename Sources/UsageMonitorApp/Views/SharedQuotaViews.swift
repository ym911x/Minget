import AppKit
import SwiftUI
import UsageMonitorCore

/// How one quota row paints its usage bar and its "剩余" percentage.
///
/// `levels` is the traffic light every card has used since 1.0: green above 50 %, orange
/// from 20 %, red below. `claudeModels` belongs to the Antigravity shared pool that covers
/// Claude and GPT models: that usage is drawn in Claude's own brand orange, and the only
/// band that survives is the critical one.
enum QuotaUsageTint: Equatable {
    case levels
    case claudeModels

    /// Claude brand orange (#D97757).
    static let claudeOrange = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)

    func color(_ percent: Double?) -> Color {
        guard let percent, percent.isFinite, (0...100).contains(percent) else { return .secondary }
        switch self {
        case .levels:
            switch UsageFormatting.usageLevel(remainingPercent: percent) {
            case .normal: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        case .claudeModels:
            return UsageFormatting.usageLevel(remainingPercent: percent) == .critical ? .red : Self.claudeOrange
        }
    }
}

enum QuotaPresentation {
    static func percentage(_ percent: Double?) -> String {
        guard let percent, percent.isFinite, (0...100).contains(percent) else { return "—" }
        return String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), percent)
    }

    static func fraction(_ percent: Double?) -> Double? {
        guard let percent, percent.isFinite, (0...100).contains(percent) else { return nil }
        return percent / 100
    }

    static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "时间未知" }
        if date <= now { return "等待刷新" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func color(_ percent: Double?) -> Color { QuotaUsageTint.levels.color(percent) }

    static func timeProgress(kind: RateLimitWindow.Kind, window: RateLimitWindow?,
                             resetDate: Date? = nil, now: Date) -> ProviderTimeProgress {
        let progress = window.map { ResetTimeModel.progress(expected: kind, window: $0, now: now) }
            ?? ResetTimeModel.progress(expected: kind, resetsAt: resetDate,
                                      durationMinutes: kind == .fiveHour ? 300 : 10080, now: now)
        return CodexProfileCard.timeProgress(progress)
    }

    /// Only the documented primary group is selected. An absent primary is not replaced
    /// with a different shared pool, including when server ordering changes.
    static func primaryGroup(_ groups: [AntigravityQuotaGroup]) -> AntigravityQuotaGroup? {
        groups.first { $0.label == "Gemini Models" || $0.id == "gemini" }
    }

    /// The groups drawn after the primary one, in the order the service reported them.
    static func otherGroups(_ groups: [AntigravityQuotaGroup]) -> [AntigravityQuotaGroup] {
        groups.filter { $0.id != primaryGroup(groups)?.id }
    }

    /// The shared pool that covers Claude and GPT models carries Claude's own colour; the
    /// primary group keeps the level colours every other card uses.
    static func tint(for group: AntigravityQuotaGroup) -> QuotaUsageTint {
        group.id == primaryGroup([group])?.id ? .levels : .claudeModels
    }
}

struct QuotaWindowBlock: View {
    let label: String
    let kind: RateLimitWindow.Kind
    let window: RateLimitWindow?
    var isCached = false
    var resetDate: Date? = nil
    var now = Date()
    var tint: QuotaUsageTint = .levels

    var body: some View {
        let date = resetDate ?? window?.resetsAt
        let progress = QuotaPresentation.timeProgress(kind: kind, window: window, resetDate: date, now: now)
        let usageColor = tint.color(window?.remainingPercent)
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 13, weight: .semibold))
                    .frame(width: 50, alignment: .leading)
                ProviderTrackBar(fraction: QuotaPresentation.fraction(window?.remainingPercent),
                                 tint: usageColor, height: 6,
                                 isCached: isCached)
                Text("剩余 " + QuotaPresentation.percentage(window?.remainingPercent))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(usageColor)
                    .frame(width: 122, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("重置时间").frame(width: 50, alignment: .leading)
                ProviderTimeBar(progress: progress,
                                isCached: isCached, tint: .blue)
                Text(QuotaPresentation.reset(date, now: now))
                    .monospacedDigit().frame(width: 122, alignment: .trailing)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(height: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，剩余 \(QuotaPresentation.percentage(window?.remainingPercent))，重置 \(QuotaPresentation.reset(date, now: now))\(isCached ? "，缓存数据" : "")")
    }
}

enum ServiceSymbol { case chatGPT, gemini, deepSeek, commandCode }

struct ServiceMark: View {
    let service: ServiceSymbol
    var body: some View {
        Group {
            switch service {
            case .chatGPT: BrandMark()
            case .gemini:
                Image(systemName: "sparkles").resizable().scaledToFit().foregroundStyle(.blue)
            case .deepSeek:
                if let path = Bundle.main.path(forResource: "deepseek-whale-ui", ofType: "png"),
                   let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
                } else { Image(systemName: "water.waves").resizable().scaledToFit() }
            case .commandCode:
                CommandCodeLogomark()
            }
        }.frame(width: 28, height: 28).accessibilityHidden(true)
    }
}

struct AccountCardHeader: View {
    let service: ServiceSymbol
    let name: String
    let subtitle: String
    let identity: String
    let status: String
    var isCached = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ServiceMark(service: service)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(name)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(status).font(.system(size: 11)).foregroundStyle(isCached ? Color.orange : Color.secondary)
                    .lineLimit(1).help(status)
            }
            Text(identity).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).help(identity).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func quotaCardSurface() -> some View {
        self.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
    }
}

/// Typed presentation inputs preserve missing quotas independently from known reset dates.
struct OverviewQuotaWindow {
    let kind: RateLimitWindow.Kind
    let window: RateLimitWindow?
    var resetDate: Date? = nil

    var resetsAt: Date? { resetDate ?? window?.resetsAt }
    var percentage: String { QuotaPresentation.percentage(window?.remainingPercent) }
    var fraction: Double? { QuotaPresentation.fraction(window?.remainingPercent) }
    var color: Color { QuotaPresentation.color(window?.remainingPercent) }
    var label: String { kind == .fiveHour ? "5H" : "周" }

    func progress(now: Date) -> ProviderTimeProgress {
        QuotaPresentation.timeProgress(kind: kind, window: window, resetDate: resetsAt, now: now)
    }

    func description(now: Date) -> String {
        "\(kind == .fiveHour ? "5 小时" : "周额度")，剩余 \(percentage)，重置 \(QuotaPresentation.reset(resetsAt, now: now))"
    }
}

/// One Command Code credit column in the overview row.
///
/// That provider is credit-based, so its columns carry money instead of a percentage: the
/// same `$remaining / $limit` wording the detail card uses, with the monthly cycle taking its
/// reset point and its time rail from the reported billing period rather than from the window
/// itself (which carries no reset of its own).
struct OverviewCreditWindow {
    let kind: ProviderUsageWindow.Kind
    let window: ProviderUsageWindow?
    var billingPeriodStart: Date? = nil
    var billingPeriodEnd: Date? = nil
    /// True when the numbers behind this column came from a cached auxiliary payload.
    var isCached = false

    /// Short label for the overview's compact two-column layout.
    var label: String {
        switch kind {
        case .fiveHour: return "5H"
        case .weekly: return "周"
        case .billingPeriod: return "月"
        }
    }

    /// Full name for hover and assistive text, matching the detail card's row labels.
    var fullLabel: String {
        switch kind {
        case .fiveHour: return "5 小时"
        case .weekly: return "周额度"
        case .billingPeriod: return "本月"
        }
    }

    var amountText: String { CommandCodeCardPresentation.quotaText(window) }
    var fraction: Double? { window?.remainingFraction }
    var resetsAt: Date? { kind == .billingPeriod ? billingPeriodEnd : window?.resetsAt }

    func progress(now: Date) -> ProviderTimeProgress {
        ProviderTimeModel.progress(kind: kind, window: window,
                                   billingPeriodStart: billingPeriodStart,
                                   billingPeriodEnd: billingPeriodEnd,
                                   now: now).progress
    }

    func description(now: Date) -> String {
        let outcome = ProviderTimeModel.progress(kind: kind, window: window,
                                                 billingPeriodStart: billingPeriodStart,
                                                 billingPeriodEnd: billingPeriodEnd,
                                                 now: now)
        let time = CommandCodeCardPresentation.timeText(kind: kind, window: window,
                                                        billingPeriodEnd: billingPeriodEnd,
                                                        outcome: outcome)
        return "\(fullLabel) \(amountText)，重置时间 \(time)"
    }
}

enum OverviewUsageSummary {
    case quotas(fiveHour: OverviewQuotaWindow, weekly: OverviewQuotaWindow)
    case balances([ProviderBalance])
    /// Command Code: the five-hour column is always drawn. The second column is the monthly
    /// credit window when the service reported one, the weekly window as the fallback, and
    /// nothing when neither is usable — a missing window never becomes an empty box.
    case credits(fiveHour: OverviewCreditWindow, second: OverviewCreditWindow?)

    static func codex(_ snapshot: UsageSnapshot?) -> Self {
        .quotas(fiveHour: OverviewQuotaWindow(kind: .fiveHour, window: snapshot?.fiveHour),
                weekly: OverviewQuotaWindow(kind: .weekly, window: snapshot?.weekly))
    }

    static func gemini(_ groups: [AntigravityQuotaGroup]) -> Self {
        let primary = QuotaPresentation.primaryGroup(groups)
        let five = primary?.buckets.first { $0.kind == .fiveHour }
        let week = primary?.buckets.first { $0.kind == .weekly }
        return .quotas(fiveHour: OverviewQuotaWindow(kind: .fiveHour, window: five?.rateLimitWindow, resetDate: five?.resetsAt),
                       weekly: OverviewQuotaWindow(kind: .weekly, window: week?.rateLimitWindow, resetDate: week?.resetsAt))
    }

    /// The monthly remaining credit is the number that decides the month's budget, and it
    /// arrives on the required credits read; the weekly window is a coarser view of the same
    /// allowance, so it is only the fallback. A monthly window without a real remainder is
    /// not shown as an invented number (REQUIREMENTS.md §5.2).
    static func commandCode(_ usage: ProviderUsage?) -> Self {
        let fiveHour = OverviewCreditWindow(kind: .fiveHour,
                                            window: usage?.windows.first { $0.kind == .fiveHour })
        let monthly = usage?.windows.first { $0.kind == .billingPeriod }
        if let monthly, monthly.effectiveRemaining != nil {
            let monthlyIsCached = usage?.summaryFreshness?.isCached == true
                || usage?.subscriptionFreshness?.isCached == true
            return .credits(fiveHour: fiveHour,
                            second: OverviewCreditWindow(kind: .billingPeriod,
                                                         window: monthly,
                                                         billingPeriodStart: usage?.billingPeriodStart,
                                                         billingPeriodEnd: usage?.billingPeriodEnd,
                                                         isCached: monthlyIsCached))
        }
        let weekly = usage?.windows.first { $0.kind == .weekly }
        return .credits(fiveHour: fiveHour,
                        second: weekly.map { OverviewCreditWindow(kind: .weekly, window: $0) })
    }

    /// Fixed width of the row's quota graphic. Two columns always take the 224 pt the
    /// two-credit Command Code row uses, so every two-column row draws bars of the same
    /// length; a row with a single column keeps the 1.6.2 width.
    var graphicWidth: CGFloat {
        switch self {
        case .quotas: return 224
        case .credits(_, let second): return second == nil ? 164 : 224
        case .balances: return 164
        }
    }

    func description(now: Date) -> String {
        switch self {
        case .quotas(let five, let week):
            return five.description(now: now) + "；" + week.description(now: now)
        case .balances(let balances):
            guard !balances.isEmpty else { return "余额暂不可用" }
            return balances.map { DecimalFormatting.overviewBalanceLabel($0) + " " + DecimalFormatting.overviewBalanceText($0) }.joined(separator: "；")
        case .credits(let five, let second):
            let columns = [five, second].compactMap { $0 }
            return columns.map { $0.description(now: now) }.joined(separator: "；")
        }
    }
}

private struct OverviewQuotaGraphic: View {
    let quota: OverviewQuotaWindow
    let isCached: Bool
    let now: Date

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 2) {
                Text(quota.label).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(quota.percentage).monospacedDigit().foregroundStyle(quota.color)
            }.font(.system(size: 11))
                .lineLimit(1).fixedSize(horizontal: false, vertical: true)
            ProviderTrackBar(fraction: quota.fraction, tint: quota.color, height: 4, isCached: isCached)
            ProviderTimeBar(progress: quota.progress(now: now), isCached: isCached, tint: .blue)
        }.help(quota.description(now: now))
    }
}

private struct OverviewCreditGraphic: View {
    let credit: OverviewCreditWindow
    let isCached: Bool
    let now: Date

    /// The row's cache state and the column's own auxiliary cache state both fade the track
    /// and turn the amount orange, exactly like the detail card's monthly row.
    private var showsCached: Bool { isCached || credit.isCached }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(credit.label).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(credit.amountText).monospacedDigit()
                    .foregroundStyle(showsCached ? Color.orange : Color.secondary)
            }.font(.system(size: 11))
                .lineLimit(1).fixedSize(horizontal: false, vertical: true)
            ProviderTrackBar(fraction: credit.fraction, tint: .purple, height: 4, isCached: showsCached)
            ProviderTimeBar(progress: credit.progress(now: now), isCached: showsCached)
        }.help(credit.description(now: now))
    }
}

private struct OverviewUsageGraphic: View {
    let summary: OverviewUsageSummary
    let isCached: Bool
    let now: Date

    var body: some View {
        Group {
            switch summary {
            case .quotas(let five, let week):
                HStack(spacing: 12) {
                    OverviewQuotaGraphic(quota: five, isCached: isCached, now: now)
                    OverviewQuotaGraphic(quota: week, isCached: isCached, now: now)
                }
            case .balances(let balances):
                Text(balances.isEmpty ? "—" : balances.map { DecimalFormatting.overviewBalanceText($0) }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .foregroundStyle(isCached ? Color.orange : Color.primary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .trailing)
            case .credits(let five, let second):
                HStack(spacing: 12) {
                    OverviewCreditGraphic(credit: five, isCached: isCached, now: now)
                    if let second {
                        OverviewCreditGraphic(credit: second, isCached: isCached, now: now)
                    }
                }
            }
        }.frame(width: summary.graphicWidth).help(summary.description(now: now))
    }
}

struct OverviewAccountRow: View {
    static let height: CGFloat = 64
    /// The vertical distance one row occupies in the overview stack. The card stack uses
    /// `DetailPageLayout.rowSpacing`, so a reorder target is a whole number of these apart.
    static var pitch: CGFloat { height + DetailPageLayout.rowSpacing }
    let service: ServiceSymbol
    let name: String
    let status: String
    let summary: OverviewUsageSummary
    var isCached = false
    /// Fixed reference time is only used by deterministic local presentation previews.
    var referenceDate: Date? = nil
    /// True only for a real account row in the overview: the left logo becomes the drag
    /// handle. The empty Gemini placeholder keeps `false` so it can never be reordered.
    var isReorderable = false
    /// Reports the live vertical drag in window coordinates. The first call of a gesture also
    /// starts the drag, so a press that moves takes hold without any hold delay.
    var onReorderDragChanged: ((CGFloat) -> Void)?
    /// Reports the end of a drag. `true` commits the drop position; `false` cancels.
    var onReorderDragEnded: ((Bool) -> Void)?
    /// Keyboard and VoiceOver alternatives to dragging, wired to the same order store.
    var onReorderStep: ((_ up: Bool) -> Void)?
    let onOpen: () -> Void

    var body: some View {
        if let referenceDate {
            row(now: referenceDate)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                row(now: context.date)
            }
        }
    }

    private func row(now: Date) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                if isReorderable {
                    reorderHandle
                } else {
                    ServiceMark(service: service)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(name)
                    // The quota graphic takes 224 pt of the 408 pt row, which leaves this
                    // column about 92 pt: the name keeps its size and truncates, and the
                    // small status line gives way first by shrinking, then by truncating.
                    Text(status).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(isCached ? Color.orange : Color.secondary).help(status)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(-1)
                OverviewUsageGraphic(summary: summary, isCached: isCached, now: now)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary).frame(width: 10).accessibilityHidden(true)
            }.padding(.horizontal, 12).frame(height: Self.height)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .help("\(name)，\(status)，\(summary.description(now: now))，查看完整额度")
            .accessibilityLabel("\(name)，\(status)，\(summary.description(now: now))\(isCached ? "，缓存数据" : "")，查看详情")
    }

    /// The logo as a drag handle.
    ///
    /// A plain click still opens the row: the drag only takes over once the pointer has moved
    /// past `dragThreshold`, which a click never does. The gesture has high priority so the
    /// surrounding row button cannot claim the same press first.
    private var reorderHandle: some View {
        ServiceMark(service: service)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle().inset(by: -4))
            .help("拖动可排序")
            .accessibilityLabel("拖动排序：\(name)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onReorderStep?(false)
                case .decrement: onReorderStep?(true)
                @unknown default: break
                }
            }
            .highPriorityGesture(reorderGesture)
            .onDisappear { onReorderDragEnded?(false) }
    }

    /// The drag translation is measured in the window's coordinate space on purpose.
    ///
    /// A local space is measured against the handle's own moving frame: the row follows the
    /// pointer while the gesture keeps reporting the distance from a frame that is itself
    /// moving, so the two feed back into each other and the row stutters and trails. Window
    /// coordinates do not move with the row, so the reported distance is the pointer's alone.
    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: Self.dragThreshold, coordinateSpace: .global)
            .onChanged { value in
                onReorderDragChanged?(value.translation.height)
            }
            .onEnded { value in
                onReorderDragChanged?(value.translation.height)
                onReorderDragEnded?(true)
            }
    }

    /// How far the pointer must travel before a press becomes a reorder instead of a click.
    /// Small enough that the row starts moving at once, large enough that a click on the logo
    /// still opens the row.
    static let dragThreshold: CGFloat = 3
}

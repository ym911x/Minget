import AppKit
import SwiftUI
import UsageMonitorCore

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

    static func color(_ percent: Double?) -> Color {
        guard let percent, fraction(percent) != nil else { return .secondary }
        switch UsageFormatting.usageLevel(remainingPercent: percent) {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

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
}

struct QuotaWindowBlock: View {
    let label: String
    let kind: RateLimitWindow.Kind
    let window: RateLimitWindow?
    var isCached = false
    var resetDate: Date? = nil
    var now = Date()

    var body: some View {
        let date = resetDate ?? window?.resetsAt
        let progress = QuotaPresentation.timeProgress(kind: kind, window: window, resetDate: date, now: now)
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 13, weight: .semibold))
                    .frame(width: 50, alignment: .leading)
                ProviderTrackBar(fraction: QuotaPresentation.fraction(window?.remainingPercent),
                                 tint: QuotaPresentation.color(window?.remainingPercent), height: 6,
                                 isCached: isCached)
                Text("剩余 " + QuotaPresentation.percentage(window?.remainingPercent))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(QuotaPresentation.color(window?.remainingPercent))
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

enum OverviewUsageSummary {
    case quotas(fiveHour: OverviewQuotaWindow, weekly: OverviewQuotaWindow)
    case balances([ProviderBalance])
    case credits(ProviderUsageWindow?)

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

    func description(now: Date) -> String {
        switch self {
        case .quotas(let five, let week):
            return five.description(now: now) + "；" + week.description(now: now)
        case .balances(let balances):
            guard !balances.isEmpty else { return "余额暂不可用" }
            return balances.map { DecimalFormatting.overviewBalanceLabel($0) + " " + DecimalFormatting.overviewBalanceText($0) }.joined(separator: "；")
        case .credits(let window):
            return "5 小时 " + CommandCodeCardPresentation.quotaText(window)
                + "，重置 " + QuotaPresentation.reset(window?.resetsAt, now: now)
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
            case .credits(let window):
                VStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Text("5H").foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(CommandCodeCardPresentation.quotaText(window)).monospacedDigit()
                            .foregroundStyle(isCached ? Color.orange : Color.secondary)
                    }.font(.system(size: 11)).lineLimit(1)
                    ProviderTrackBar(fraction: window?.remainingFraction, tint: .purple, height: 4, isCached: isCached)
                    ProviderTimeBar(progress: ProviderTimeModel.progress(kind: .fiveHour, window: window,
                        billingPeriodStart: nil, billingPeriodEnd: nil, now: now).progress, isCached: isCached)
                }
            }
        }.frame(width: 164).help(summary.description(now: now))
    }
}

struct OverviewAccountRow: View {
    let service: ServiceSymbol
    let name: String
    let status: String
    let summary: OverviewUsageSummary
    var isCached = false
    /// Fixed reference time is only used by deterministic local presentation previews.
    var referenceDate: Date? = nil
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
                ServiceMark(service: service)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(name)
                    Text(status).font(.system(size: 11)).lineLimit(1)
                        .foregroundStyle(isCached ? Color.orange : Color.secondary).help(status)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(-1)
                OverviewUsageGraphic(summary: summary, isCached: isCached, now: now)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary).frame(width: 10).accessibilityHidden(true)
            }.padding(.horizontal, 12).frame(height: 64)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .help("\(name)，\(status)，\(summary.description(now: now))，查看完整额度")
            .accessibilityLabel("\(name)，\(status)，\(summary.description(now: now))\(isCached ? "，缓存数据" : "")，查看详情")
    }
}

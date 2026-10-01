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
        let progress = window.map { ResetTimeModel.progress(expected: kind, window: $0, now: now) }
            ?? ResetTimeModel.progress(expected: kind, resetsAt: date, durationMinutes: kind == .fiveHour ? 300 : 10080, now: now)
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
                ProviderTimeBar(progress: CodexProfileCard.timeProgress(progress),
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

struct OverviewAccountRow: View {
    let service: ServiceSymbol
    let name: String
    let status: String
    let values: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                ServiceMark(service: service)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(values).font(.system(size: 12)).monospacedDigit().lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }.padding(.horizontal, 12).frame(height: 64)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).help("查看 \(name) 的完整额度")
            .accessibilityLabel("\(name)，\(status)，\(values)，查看详情")
    }
}

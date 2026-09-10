import SwiftUI
import UsageMonitorCore

/// Explicit failure state. Distinguishes missing CLI, not signed in, startup failure,
/// RPC failure and missing windows (PROJECT_SPEC.md §13).
struct ErrorStateView: View {
    let error: UsageError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(header)
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: iconName)
                    .foregroundStyle(.orange)
            }
            Text(UsageFormatting.errorText(error))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var header: String {
        switch error {
        case .codexCLINotFound: return "数据不可用"
        case .codexNotSignedIn: return "数据不可用"
        case .appServerStartupFailed: return "数据不可用"
        case .rpcFailed: return "数据不可用"
        case .windowUnavailable: return "部分窗口不可用"
        }
    }

    private var iconName: String {
        switch error {
        case .windowUnavailable: return "info.circle"
        default: return "exclamationmark.triangle"
        }
    }

    private var hint: String {
        switch error {
        case .codexCLINotFound: return "请确认已安装 ChatGPT/Codex 桌面应用或 codex CLI。"
        case .codexNotSignedIn: return "请在 Codex 中登录后再试。"
        case .appServerStartupFailed, .rpcFailed: return "可点击“立即刷新”重试。"
        case .windowUnavailable: return "服务端未返回该窗口数据。"
        }
    }
}

/// Banner shown when the panel displays cached data after a failed refresh.
struct StaleBannerView: View {
    let error: UsageError
    let fetchedAt: Date
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(UsageFormatting.stalenessText(fetchedAt: fetchedAt, now: now))
                    .font(.system(size: 11, weight: .medium))
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.orange)
            }
            Text(UsageFormatting.errorText(error))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("缓存数据：\(UsageFormatting.stalenessText(fetchedAt: fetchedAt, now: now))")
    }
}

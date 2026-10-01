import AppKit
import SwiftUI
import UsageMonitorCore

/// One connection surface for first launch and later account management.
struct AccountManagementView: View {
    @ObservedObject var model: UsageViewModel
    let firstRun: Bool
    let onDone: () -> Void
    @StateObject private var deepSeekForm: ConnectionFormState
    @StateObject private var commandCodeForm: ConnectionFormState

    init(model: UsageViewModel, firstRun: Bool, onDone: @escaping () -> Void) {
        self.model = model
        self.firstRun = firstRun
        self.onDone = onDone
        _deepSeekForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .deepseek))
        _commandCodeForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .commandcode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(firstRun ? "连接你的第一个账号" : "管理账号")
                .font(.system(size: 20, weight: .bold))
            Text("选择一个服务开始。其他账号以后仍可在这里连接。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.profileStates) { state in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(model.displayNames.displayName(for: state.profile.id)).font(.headline)
                                Text("ChatGPT").font(.system(size: 10)).foregroundStyle(.secondary)
                                Spacer()
                                if model.activeLoginProfile == state.profile.id {
                                    Button("取消登录") { model.cancelChatGPTLogin() }
                                } else {
                                    Button(state.snapshot == nil ? "连接" : "重新连接") {
                                        model.connectChatGPT(profileID: state.profile.id)
                                    }
                                    .disabled(model.activeLoginProfile != nil)
                                }
                            }
                            Text(model.loginStatus[state.profile.id] ?? state.failureText ??
                                 (state.snapshot == nil ? "未连接或额度暂不可用" : state.isStale ? "上次额度，连接待确认" : "已连接，额度已更新"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            if let hint = state.recoveryHint {
                                Text(hint).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }.connectionCard()
                    }

                    AntigravityConnectionView(google: model.google)
                    providerRow(.deepseek, title: "DeepSeek", form: deepSeekForm)
                    providerRow(.commandcode, title: "Command Code", form: commandCodeForm)
                }
            }
            HStack {
                Spacer()
                Button(firstRun && !hasConnectedSource ? "稍后再说" : "完成") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520, height: 580)
    }

    private var hasConnectedSource: Bool {
        !model.google.connections.isEmpty
        || model.profileStates.contains { !$0.isStale && $0.snapshot != nil }
        || model.providerReports.contains { $0.connection == .connected && $0.isLive }
    }

    private func providerRow(_ platform: ProviderPlatform, title: String,
                             form: ConnectionFormState) -> some View {
        let report = model.providerReports.first { $0.platform == platform }
        let serviceID = platform == .deepseek
            ? DisplayNamePreferences.ServiceID.deepSeek : DisplayNamePreferences.ServiceID.commandCode
        let accountName = model.displayNames.displayName(for: serviceID)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.headline)
                if accountName != title {
                    Text(accountName).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(form.isExpanded ? "收起" : "连接或管理") { form.toggle() }
            }
            Text(providerStatus(report)).font(.system(size: 11)).foregroundStyle(.secondary)
            CredentialFeedbackView(feedback: model.credentialFeedback(for: platform))
            if form.isExpanded {
                if platform == .deepseek { DeepSeekSettingsView(form: form) }
                else { CommandCodeSettingsView(form: form) }
            }
        }.connectionCard()
    }

    private func providerStatus(_ report: ProviderReport?) -> String {
        guard let report else { return "正在检查连接状态…" }
        switch report.connection {
        case .connected:
            if report.isLive { return "连接成功，额度已更新" }
            return report.lastSuccessAt == nil ? "已保存，正在读取额度…" : "已连接，上次额度可用"
        case .stale: return "上次额度可用，当前读取失败"
        case .connecting: return report.lastSuccessAt == nil ? "正在读取额度…" : "正在读取额度，显示上次数据"
        case .notConfigured: return "未连接"
        case .authSuspended, .needsAuthorization: return "需要重新连接"
        case .unavailable, .unverified: return report.error?.displayText ?? "额度暂不可用"
        }
    }
}

private extension View {
    func connectionCard() -> some View {
        self.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

final class AccountsWindowController: NSWindowController {
    private let model: UsageViewModel
    private let onDone: () -> Void
    init(model: UsageViewModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "管理账号"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    func show(firstRun: Bool) {
        window?.contentView = NSHostingView(rootView: AccountManagementView(model: model, firstRun: firstRun) { [weak self] in
            self?.window?.orderOut(nil)
            self?.onDone()
        })
        showWindow(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

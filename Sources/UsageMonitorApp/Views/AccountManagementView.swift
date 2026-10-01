import AppKit
import SwiftUI
import UsageMonitorCore

struct AccountManagementRow<Actions: View>: View {
    let service: ServiceSymbol
    let name: String
    let identity: String
    let status: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ServiceMark(service: service)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(name)
                if !identity.isEmpty { Text(identity).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled) }
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            actions().controlSize(.regular)
        }.frame(minHeight: 64).accessibilityElement(children: .contain)
    }
}

struct AccountNameSheet: View {
    let defaultName: String
    let onSave: (String) -> Bool
    @State private var draft: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(name: String, defaultName: String, onSave: @escaping (String) -> Bool) {
        self.defaultName = defaultName; self.onSave = onSave; _draft = State(initialValue: name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("显示名称").font(.headline)
            TextField(defaultName, text: $draft).textFieldStyle(.roundedBorder)
            Text(error ?? "最多 40 个字符，仅修改本地显示文字。")
                .font(.system(size: 11)).foregroundStyle(error == nil ? Color.secondary : .red)
            HStack {
                Button("恢复默认") { if onSave("") { dismiss() } }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 { error = "名称最多 40 个字符" }
                    else if onSave(draft) { dismiss() }
                    else { error = "名称无法保存" }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 400)
    }
}

/// Reused in the settings account pane and first-run guide. No second window or reader.
struct AccountManagementView: View {
    @ObservedObject var model: UsageViewModel
    let firstRun: Bool
    let onDone: () -> Void
    @StateObject private var deepSeekForm: ConnectionFormState
    @StateObject private var commandCodeForm: ConnectionFormState
    @State private var editingName: String?

    init(model: UsageViewModel, firstRun: Bool, onDone: @escaping () -> Void) {
        self.model = model; self.firstRun = firstRun; self.onDone = onDone
        _deepSeekForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .deepseek))
        _commandCodeForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .commandcode))
    }
    @ViewBuilder var body: some View {
        if model.accountManagementUnavailable { Text(model.accountMessage).padding(24) }
        else if model.accountRegistry != nil { ManagedAccountManagementView(model: model, firstRun: firstRun, onDone: onDone) }
        else { legacyBody }
    }
    private var legacyBody: some View {
        Form {
            if firstRun {
                Section {
                    Text("连接你的第一个账号").font(.headline)
                    Text("选择一个服务开始，其他账号以后仍可在这里连接。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("ChatGPT") {
                ForEach(model.profileStates) { state in
                    AccountManagementRow(service: .chatGPT, name: model.displayNames.displayName(for: state.id),
                        identity: [state.identityLabel, state.displayEmail].compactMap { $0 }.joined(separator: " · "),
                        status: model.loginStatus[state.id] ?? state.failureText ?? state.connectionText) {
                        if model.activeLoginProfile == state.id {
                            Button("取消登录") { model.cancelChatGPTLogin() }
                        } else {
                            Button(state.isConnectionHealthy || state.isConnectionCached ? "重新登录" : "登录") {
                                model.connectChatGPT(profileID: state.id)
                            }.disabled(model.activeLoginProfile != nil)
                        }
                        Menu {
                            Button("显示名称…") { editingName = state.id }
                        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel("\(model.displayNames.displayName(for: state.id)) 更多管理操作")
                    }
                    if let hint = state.recoveryHint { Text(hint).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            Section("Gemini · Google / Antigravity") { AntigravityConnectionView(google: model.google) }
            Section("API 服务") {
                providerRow(.deepseek, title: "DeepSeek", form: deepSeekForm)
                providerRow(.commandcode, title: "Command Code", form: commandCodeForm)
            }
            if firstRun {
                Section {
                    Button(hasConnectedSource ? "完成并查看额度" : "稍后再说", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }.formStyle(.grouped)
        .sheet(isPresented: Binding(get: { editingName != nil }, set: { if !$0 { editingName = nil } })) {
            if let id = editingName {
                AccountNameSheet(name: model.displayNames.displayName(for: id), defaultName: model.displayNames.defaultName(for: id)) {
                    model.displayNames.setDisplayName($0, for: id)
                }
            }
        }
    }
    private var hasConnectedSource: Bool {
        !model.google.connections.isEmpty || model.profileStates.contains { !$0.isStale && $0.snapshot != nil }
            || model.providerReports.contains { $0.connection == .connected && $0.isLive }
    }
    private func providerRow(_ platform: ProviderPlatform, title: String, form: ConnectionFormState) -> some View {
        let report = model.providerReports.first { $0.platform == platform }
        let id = platform == .deepseek ? DisplayNamePreferences.ServiceID.deepSeek : DisplayNamePreferences.ServiceID.commandCode
        let name = model.displayNames.displayName(for: id)
        return AccountManagementRow(service: platform == .deepseek ? .deepSeek : .commandCode, name: name,
            identity: title + " · API Key", status: providerStatus(report)) {
            Button((report?.connection ?? .notConfigured) == .notConfigured ? "连接" : "管理") { form.toggle() }
            Menu { Button("显示名称…") { editingName = id } }
                label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("\(name) 更多管理操作")
        }.sheet(isPresented: Binding(get: { form.isExpanded }, set: { if !$0 { form.collapse() } })) {
            VStack(alignment: .leading, spacing: 16) {
                Text("管理 " + name).font(.headline)
                CredentialFeedbackView(feedback: model.credentialFeedback(for: platform))
                if platform == .deepseek { DeepSeekSettingsView(form: form) }
                else { CommandCodeSettingsView(form: form) }
            }.padding(24).frame(width: 460)
        }
    }
    private func providerStatus(_ report: ProviderReport?) -> String {
        guard let report else { return "正在检查连接状态…" }
        switch report.connection {
        case .connected: return report.isLive ? "已连接 · 额度已更新" : "已连接 · 上次额度"
        case .stale: return "已保存 · 读取失败，显示上次额度"
        case .connecting: return "正在读取额度…"
        case .notConfigured: return "未连接"
        case .authSuspended, .needsAuthorization: return "需要重新连接"
        case .unavailable, .unverified: return report.error?.displayText ?? "额度暂不可用"
        }
    }
}

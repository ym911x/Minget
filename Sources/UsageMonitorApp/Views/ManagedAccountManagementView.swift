import AppKit
import SwiftUI
import UsageMonitorCore

struct ManagedAccountManagementView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var google: AntigravityModel
    let firstRun: Bool
    let onDone: () -> Void
    @State private var editingName: ManagedAccount?
    @State private var editingAPI: ManagedAccount?
    @State private var removing: ManagedAccount?

    init(model: UsageViewModel, firstRun: Bool, onDone: @escaping () -> Void) {
        self.model = model; self.google = model.google; self.firstRun = firstRun; self.onDone = onDone
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(firstRun ? "连接你的第一个账号" : "管理你的账号").font(.headline)
                        Text("每个账号独立保存连接和额度，可随时添加更多账号。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.addingPlatform = nil; model.showAddAccount = true } label: { Label("添加账号", systemImage: "plus") }
                }
                if !model.accountMessage.isEmpty { Text(model.accountMessage).font(.system(size: 12)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 24).padding(.bottom, 12)
            Form {
            ForEach(AccountPlatform.allCases, id: \.self) { platform in
                Section {
                    let rows = model.managedAccounts.filter { $0.platform == platform }
                    ForEach(rows) { row in accountRow(row) }
                    if rows.isEmpty { Text("尚未添加账号").foregroundStyle(.secondary) }
                    Button { model.addingPlatform = platform; model.showAddAccount = true } label: { Label("添加 " + platform.title + " 账号", systemImage: "plus") }
                } header: { Text(platform.title) }
            }
            if firstRun { Section { Button(model.managedAccounts.isEmpty ? "稍后再说" : "完成并查看额度", action: onDone) } }
            }.formStyle(.grouped)
        }
        .sheet(isPresented: $model.showAddAccount) { AddManagedAccountSheet(model: model, platform: model.addingPlatform) }
        .sheet(item: $editingAPI) { row in AddManagedAccountSheet(model: model, platform: row.platform, existing: row) }
        .sheet(item: $editingName) { row in
            AccountNameSheet(name: model.accountName(row), defaultName: row.platform.title + " 账号 \(row.ordinal)") {
                model.renameManagedAccount(row.id, name: $0)
            }
        }
        .confirmationDialog("移除这个账号？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("移除本机账号", role: .destructive) { if let row = removing { model.removeManagedAccount(row.id) }; removing = nil }
            Button("取消", role: .cancel) { removing = nil }
        } message: { Text("移除该账号在 Minget 的本机连接、额度缓存和应用内点火计划。不会删除服务商账户或影响其他账号。当前菜单栏显示此账号时，将提示重新选择。") }
    }
    private func symbol(_ platform: AccountPlatform) -> ServiceSymbol {
        switch platform { case .chatGPT: return .chatGPT; case .google: return .gemini; case .deepseek: return .deepSeek; case .commandcode: return .commandCode }
    }
    private func identity(_ row: ManagedAccount) -> String {
        if row.platform == .chatGPT { return model.profileState(row.id)?.displayEmail ?? "未确认账号身份" }
        if row.platform == .google { return row.googleEmail ?? "未登录" }
        return row.platform.title + " · API Key"
    }
    private func status(_ row: ManagedAccount) -> String {
        if row.removalPending { return "移除未完成 · 连接已停用" }
        if row.platform == .chatGPT { return model.loginStatus[row.id] ?? model.profileState(row.id)?.connectionText ?? "等待连接" }
        if row.platform == .google { return google.accounts.first { $0.account.email == row.googleEmail }?.statusText ?? "等待连接" }
        guard let state = model.managedAPIStates.first(where: { $0.id == row.id }) else { return "等待连接" }
        return CredentialFeedback(report: state.report).displayText
    }
    private func accountRow(_ row: ManagedAccount) -> some View {
        AccountManagementRow(service: symbol(row.platform), name: model.accountName(row), identity: identity(row), status: status(row)) {
            if row.removalPending { Button("重试移除") { model.removeManagedAccount(row.id) } }
            else {
                if row.platform == .chatGPT && model.activeLoginProfile == row.id {
                    Button("取消登录") { model.cancelChatGPTLogin() }
                } else {
                    Button(row.platform.apiPlatform == nil ? "重新登录" : "管理连接") {
                        switch row.platform {
                        case .chatGPT: model.connectChatGPT(profileID: row.id)
                        case .google: if let slot = row.googleSlot { google.login(.init(rawValue: slot)) }
                        case .deepseek, .commandcode: editingAPI = row
                        }
                    }.disabled((row.platform == .chatGPT && model.activeLoginProfile != nil) || (row.platform == .google && google.activeLoginSlot != nil))
                }
                Menu {
                    Button("显示名称…") { editingName = row }
                    Button("刷新额度") {
                        switch row.platform { case .chatGPT: model.refreshNow(); case .google: google.refresh(force: true)
                        case .deepseek, .commandcode: model.refreshManagedAPI(id: row.id, force: true) }
                    }
                    Button("移除账号…", role: .destructive) { removing = row }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel(model.accountName(row) + " 更多管理操作")
            }
        }
    }
}

struct AddManagedAccountSheet: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var google: AntigravityModel
    let existing: ManagedAccount?
    @State private var platform: AccountPlatform?
    @State private var name: String
    @State private var key = ""
    @State private var startedID: String?
    @Environment(\.dismiss) private var dismiss
    init(model: UsageViewModel, platform: AccountPlatform?, existing: ManagedAccount? = nil) {
        self.model = model; google = model.google; self.existing = existing
        _platform = State(initialValue: platform); _name = State(initialValue: existing.map { model.accountName($0) } ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "添加账号" : "管理连接").font(.headline)
            if existing == nil {
                Picker("平台", selection: $platform) {
                    Text("请选择平台").tag(Optional<AccountPlatform>.none)
                    ForEach(AccountPlatform.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }.disabled(startedID != nil)
            }
            if let platform {
                TextField("显示名称（留空使用默认名称）", text: $name).textFieldStyle(.roundedBorder).disabled(startedID != nil)
                Text("最多 40 个字符，账号连接互相独立。") .font(.system(size: 11)).foregroundStyle(.secondary)
                if platform.apiPlatform != nil {
                    SecureField(existing == nil ? "API Key" : "输入新的 API Key", text: $key).textFieldStyle(.roundedBorder)
                    Text("仅保存到 macOS 钥匙串，通过官方只读接口读取额度。") .font(.system(size: 11)).foregroundStyle(.secondary)
                } else if platform == .google {
                    Text(google.isPreparingCLI ? google.feedback : "使用官方 CLI 在独立窗口登录新的 Google 账号。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button(google.isPreparingCLI ? "准备中…" : "准备官方登录组件") { google.prepareCLI() }.disabled(google.isPreparingCLI)
                } else {
                    Text(startedID.flatMap { model.loginStatus[$0] } ?? "将在官方页面登录，请选择要添加的 ChatGPT 账号。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if !model.accountMessage.isEmpty { Text(model.accountMessage).font(.system(size: 12)).foregroundStyle(.secondary) }
            HStack {
                Button("取消") { cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(buttonTitle) { submit() }.keyboardShortcut(.defaultAction)
                    .disabled(platform == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 || (platform?.apiPlatform != nil && key.isEmpty) || model.activeLoginProfile != nil || google.activeLoginSlot != nil || google.isPreparingCLI)
            }
        }.padding(24).frame(width: 460)
        .onChange(of: model.managedAccounts) { rows in
            if let id = startedID, rows.contains(where: { $0.id == id }) { startedID = nil; dismiss() }
        }
        .onDisappear { key = ""; if startedID != nil { cancel() } }
    }
    private var buttonTitle: String { platform?.apiPlatform != nil ? "保存并读取额度" : startedID == nil ? "开始官方登录" : "重试登录" }
    private func cancel() {
        if let id = startedID, model.pendingChatGPTAccount?.id == id { model.cancelChatGPTLogin(); model.cancelPendingChatGPT() }
        startedID = nil; key = ""
    }
    private func submit() {
        guard let platform, let registry = model.accountRegistry else { return }
        model.accountMessage = ""
        if platform.apiPlatform != nil {
            var draft = existing ?? registry.draft(platform, name: name)
            if let existing { draft.name = name.isEmpty ? existing.name : name.trimmingCharacters(in: .whitespacesAndNewlines) }
            if model.saveManagedAPI(draft, key: key) { key = ""; dismiss() }
        } else if platform == .google {
            model.beginAddAccount(platform, name: name)
            if google.activeLoginSlot != nil { dismiss() }
        } else {
            if let id = startedID { model.connectChatGPT(profileID: id) }
            else { model.beginAddAccount(platform, name: name); startedID = model.pendingChatGPTAccount?.id }
        }
    }
}

import AppKit
import SwiftUI
import UsageMonitorCore

/// Compact 1.1.2 settings surface. Supported services share one module so their status,
/// visibility and connection controls cannot drift into duplicate lists.
struct MingetSettingsView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var preferences: DetailPreferences
    var onDetailWindow: (() -> Void)?
    var onQuit: () -> Void

    @StateObject private var deepSeekForm: ConnectionFormState
    @State private var showsAbout = false

    init(model: UsageViewModel, preferences: DetailPreferences = .shared,
         onDetailWindow: (() -> Void)? = nil, onQuit: @escaping () -> Void) {
        self.model = model
        self.preferences = preferences
        self.onDetailWindow = onDetailWindow
        self.onQuit = onQuit
        _deepSeekForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .deepseek))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置").font(.system(size: 20, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text("服务").font(.system(size: 13, weight: .semibold)).padding(.bottom, 8)
                ServiceStatusRow(title: "OpenAI Codex", subtitle: codexStatus,
                                 detail: "详情页固定显示")
                Divider().padding(.vertical, 9)
                ServiceStatusRow(title: "DeepSeek", subtitle: providerStatus(.deepseek),
                                 detail: nil, toggle: $preferences.showDeepSeek,
                                 buttonTitle: deepSeekForm.isExpanded ? "收起" : "管理") {
                    deepSeekForm.toggle()
                }
                if deepSeekForm.isExpanded {
                    DeepSeekSettingsView(form: deepSeekForm).padding(.top, 8)
                }
            }
            .settingsGroupBackground()

            DisclosureGroup("高级诊断") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(get: { model.isCredentialDiagnosticOn },
                                         set: { model.setCredentialDiagnostics($0) })) {
                        Text("记录钥匙串访问诊断").font(.system(size: 11))
                    }
                    .controlSize(.small)
                    if model.isCredentialDiagnosticOn, let path = model.credentialDiagnosticPath {
                        Text(path).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                    }
                }.padding(.top, 7)
            }.font(.system(size: 11))

            Spacer(minLength: 2)
            HStack(spacing: 12) {
                Text("版本 \(appVersion)").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if let onDetailWindow { Button("打开详情窗口") { onDetailWindow() } }
                Button("关于") { showsAbout = true }
                    .popover(isPresented: $showsAbout, arrowEdge: .bottom) { MingetAboutView() }
                Button("退出明明有数") { onQuit() }
            }.controlSize(.small)
        }
        .padding(18).frame(width: 440, height: 390)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.2"
    }
    private var codexStatus: String {
        model.codexAccountAvailable ? "已连接" : "等待更新"
    }
    private func providerStatus(_ platform: ProviderPlatform) -> String {
        guard let report = model.providerReports.first(where: { $0.platform == platform }) else { return "等待更新" }
        switch report.connection {
        case .connected: return "已连接"
        case .stale: return "已连接，数据已过期"
        case .connecting: return "正在获取…"
        case .notConfigured: return "未连接"
        case .authSuspended: return "需要重新连接"
        case .needsAuthorization: return "需要授权"
        case .unavailable, .unverified: return "暂不可用"
        }
    }
}

private struct ServiceStatusRow: View {
    let title: String; let subtitle: String; let detail: String?
    var toggle: Binding<Bool>? = nil; var buttonTitle: String? = nil; var action: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail ?? subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if let toggle { Toggle("", isOn: toggle).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            if let buttonTitle, let action { Button(buttonTitle, action: action).controlSize(.small) }
        }.padding(.vertical, 6)
    }
}

private extension View {
    func settingsGroupBackground() -> some View {
        padding(12).background(Color(NSColor.controlBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1) }
    }
}

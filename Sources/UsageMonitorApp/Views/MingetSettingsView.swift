import AppKit
import SwiftUI
import UsageMonitorCore

/// The deliberately small 1.1.0 settings surface. It exposes the two new display choices
/// and moves existing connection/diagnostic actions out of the daily overview.
struct MingetSettingsView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var preferences: DetailPreferences
    var onDetailWindow: (() -> Void)?
    var onQuit: () -> Void

    @StateObject private var deepSeekForm: ConnectionFormState
    @StateObject private var glmForm: ConnectionFormState
    @State private var showsAbout = false

    init(model: UsageViewModel,
         preferences: DetailPreferences = .shared,
         onDetailWindow: (() -> Void)? = nil,
         onQuit: @escaping () -> Void) {
        self.model = model
        self.preferences = preferences
        self.onDetailWindow = onDetailWindow
        self.onQuit = onQuit
        _deepSeekForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .deepseek))
        _glmForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .glm))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
                Text("设置")
                    .font(.system(size: 20, weight: .bold))

                VStack(alignment: .leading, spacing: 0) {
                    Text("详情页显示")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.bottom, 8)

                    SettingsToggleRow(title: "DeepSeek",
                                      subtitle: providerStatus(.deepseek),
                                      isOn: $preferences.showDeepSeek)
                    Divider()
                    SettingsToggleRow(title: "智谱 GLM",
                                      subtitle: providerStatus(.glm),
                                      isOn: $preferences.showGLM)
                }
                .settingsGroupBackground()

                VStack(alignment: .leading, spacing: 0) {
                    Text("服务连接")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.bottom, 8)

                    ConnectionSettingsRow(title: "DeepSeek",
                                          subtitle: providerStatus(.deepseek),
                                          buttonTitle: deepSeekForm.isExpanded ? "收起" : "管理") {
                        toggleDeepSeekForm()
                    }
                    if deepSeekForm.isExpanded {
                        DeepSeekSettingsView(form: deepSeekForm)
                            .padding(.top, 8)
                    }

                    Divider().padding(.vertical, 9)

                    ConnectionSettingsRow(title: "智谱 GLM",
                                          subtitle: providerStatus(.glm),
                                          buttonTitle: glmForm.isExpanded ? "收起" : "管理") {
                        toggleGLMForm()
                    }
                    if glmForm.isExpanded {
                        GLMSettingsView(form: glmForm)
                            .padding(.top, 8)
                    }
                }
                .settingsGroupBackground()

                DisclosureGroup("高级诊断") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(get: { model.isCredentialDiagnosticOn },
                                             set: { model.setCredentialDiagnostics($0) })) {
                            Text("记录钥匙串访问诊断")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)

                        if model.isCredentialDiagnosticOn, let path = model.credentialDiagnosticPath {
                            Text(path)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }

                        if let observation = model.glmObservation {
                            Text("智谱最近一次脱敏响应")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            CredentialObservationView(observation: observation)
                        }

                        if !model.consoleObservations.isEmpty {
                            ConsoleObservationView(observations: model.consoleObservations)
                        }
                    }
                    .padding(.top, 7)
                }
                .font(.system(size: 11))

                Spacer(minLength: 2)

                HStack(spacing: 12) {
                    Text("版本 \(appVersion)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let onDetailWindow {
                        Button("打开详情窗口") { onDetailWindow() }
                    }
                    Button("关于") { showsAbout = true }
                    Button("退出") { onQuit() }
                }
                .controlSize(.small)
        }
        .padding(18)
        .frame(width: 440, height: 420)
        .sheet(isPresented: $showsAbout) {
            MingetAboutView()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
    }

    private func toggleDeepSeekForm() {
        if deepSeekForm.isExpanded {
            deepSeekForm.collapse()
        } else {
            glmForm.collapse()
            deepSeekForm.toggle()
        }
    }

    private func toggleGLMForm() {
        if glmForm.isExpanded {
            glmForm.collapse()
        } else {
            deepSeekForm.collapse()
            glmForm.toggle()
        }
    }

    private func providerStatus(_ platform: ProviderPlatform) -> String {
        let report = model.providerReports.first { $0.platform == platform }
        guard let report else { return "等待更新" }
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

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

private struct ConnectionSettingsRow: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle, action: action)
                .controlSize(.small)
        }
    }
}

private extension View {
    func settingsGroupBackground() -> some View {
        padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.82),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

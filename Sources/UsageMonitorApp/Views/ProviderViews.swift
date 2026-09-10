import SwiftUI
import UsageMonitorCore

/// Balance rows for a provider. Currencies are shown separately and are never converted,
/// summed or rounded through a float (v1.1 requirements 3 and 6).
struct ProviderBalanceView: View {
    let report: ProviderReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.balances.isEmpty {
                Text(report.connection == .stale ? "暂无余额数据" : "尚未获取到余额")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(report.balances.enumerated()), id: \.offset) { _, balance in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DecimalFormatting.balanceText(balance))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .textSelection(.enabled)
                        Text(DecimalFormatting.balanceDetailText(balance))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
                if report.balances.contains(where: { $0.currency == nil }) {
                    // The response named no currency: the amount shows bare, never a
                    // guessed code (Round 7 requirement 1).
                    Text("币种未确认：响应未标注币种，金额按原始值显示。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            ProviderUpdatedFooter(report: report)
        }
    }
}

/// Redacted probe evidence: status, business code, schema and — when the payload matched
/// no known shape — the structural path/type summary. Values, array contents, upstream
/// text, keys and cookies never appear (Round 7 requirement 2).
struct CredentialObservationView: View {
    let observation: GLMAccountReportObservation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summaryLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !observation.structureSummary.isEmpty {
                Text(observation.structureSummary.joined(separator: "\n"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                    .textSelection(.enabled)
                    .accessibilityLabel("响应结构摘要")
            }
        }
    }

    private var summaryLine: String {
        var parts = ["探测: HTTP \(observation.httpStatus)"]
        if let code = observation.businessCode { parts.append("业务码 \(code)") }
        if let schema = observation.schema { parts.append("合同 \(schema.rawValue)") }
        if let failure = observation.parseFailure { parts.append(failure.displayText) }
        return parts.joined(separator: " · ")
    }
}

/// GLM section body.
///
/// A balance appears only when the response parsed cleanly under its endpoint's confirmed
/// schema. When the real structure matches nothing known, the panel says so and shows the
/// redacted structure summary so the difference can be pinned without exposing a value
/// (v1.1 requirement 4, Round 7 requirement 2).
struct GLMReportView: View {
    let report: ProviderReport
    let observation: GLMAccountReportObservation?
    var consoleObservations: [GLMConsoleResponseObserver.Observation] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.balances.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if observation?.parseFailure == .structureUnsupported {
                        Text("已连接，但当前响应结构暂不支持")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("响应结构与已知合同不匹配，本应用不会估算或伪造余额。结构摘要如下，供后续适配。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("暂无法连接，未显示余额")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("接口字段与金额口径尚未确认，本应用不会估算或伪造余额。请通过官方控制台查看。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Link("打开智谱官方控制台", destination: GLMProvider.consoleURL)
                        .font(.system(size: 11))
                }
            } else {
                ProviderBalanceView(report: report)
            }

            if let observation, report.balances.isEmpty {
                DisclosureGroup("连接诊断") {
                    CredentialObservationView(observation: observation)
                }
                .font(.system(size: 10))
            }

            if !consoleObservations.isEmpty {
                DisclosureGroup("高级诊断") {
                    ScrollView {
                        ConsoleObservationView(observations: consoleObservations)
                    }
                    .frame(maxHeight: 180)
                }
                .font(.system(size: 10))
            }

            // The balance view already renders the update footer on success.
            if report.balances.isEmpty {
                ProviderUpdatedFooter(report: report)
            }
        }
    }
}

/// The console login window's observed JSON responses, redacted to paths, types and
/// request header names (Round 8). This is the evidence a real console contract gets
/// pinned from; values, bodies and cookies never appear.
struct ConsoleObservationView: View {
    let observations: [GLMConsoleResponseObserver.Observation]

    var body: some View {
        Group {
            if !observations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("控制台窗口响应结构（脱敏：仅路径、类型与请求头名）")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(Array(observations.enumerated()), id: \.offset) { _, observation in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(observation.method) \(observation.urlPath)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if !observation.requestHeaderNames.isEmpty {
                                Text("请求头名: \(observation.requestHeaderNames.joined(separator: ", "))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Text(observation.entries.joined(separator: "\n"))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(14)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

/// One line of fixed-vocabulary credential feedback (Round 6 requirement 2). Shown the
/// moment a save/verify/delete cycle starts and until the next cycle replaces it.
struct CredentialFeedbackView: View {
    let feedback: CredentialFeedback?

    var body: some View {
        Group {
            if let feedback {
                Text(feedback.displayText)
                    .font(.system(size: 10))
                    .foregroundStyle(feedback.needsAttention ? Color.orange : Color.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }
}

/// DeepSeek API key management: entry, replacement and deletion (v1.1 requirement 3).
///
/// All save/collapse rules live in `ConnectionFormState`; the verification feedback is
/// rendered by the always-visible provider section, so a successful save can collapse the
/// form without hiding what happened (Round 7 requirements 3-5).
struct DeepSeekSettingsView: View {
    @ObservedObject var form: ConnectionFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SecureField("sk-…", text: $form.draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("保存") { form.save() }
                    .disabled(!form.canSave)
            }
            HStack {
                Button("删除 Key") { form.deleteCredential() }
                Spacer()
                Button("关闭") { form.collapse() }
            }
            .controlSize(.small)
            Text("Key 保存在 macOS 钥匙串，仅用于读取余额，不用于任何模型调用。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// GLM connection management: API key, console session, disconnect.
struct GLMSettingsView: View {
    @ObservedObject var form: ConnectionFormState
    @State private var showsConsoleLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("通过智谱官方控制台登录并读取余额")
                .font(.system(size: 11))


            HStack {
                Button("控制台登录") { showsConsoleLogin = true }
                Button("探测一次") { form.probe() }
                Button("断开连接") { form.deleteCredential() }
                Spacer()
                Button("关闭") { form.collapse() }
            }
            .controlSize(.small)

            DisclosureGroup("API Key（兼容入口，尚未实测确认）") {
                HStack {
                    SecureField("API Key", text: $form.draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    Button("保存") { form.save() }
                        .disabled(!form.canSave)
                }
            }
            .font(.system(size: 10))

            Text("仅使用本窗口产生的会话，不读取任何现有浏览器 Cookie。会话只用于 bigmodel.cn，断开即清除。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showsConsoleLogin) {
            GLMConsoleConnectView(model: form.modelForConsoleLogin)
        }
    }
}

/// In-app official console login (v1.1 requirement 4).
///
/// The webview uses a data store this app created, so no existing browser cookie is present.
/// Navigation is restricted to bigmodel.cn / open.bigmodel.cn by `GLMConsoleSessionPolicy`,
/// which is also what keeps the captured session from ever being offered to another origin.
///
/// Completion (REVIEW round 8 finding 1): the button performs an **awaited fresh capture**
/// from the app-owned cookie store — SPA/fetch logins can set cookies without a document
/// navigation, so a stale earlier capture is never saved. A storage failure keeps the
/// window open with a fixed status line instead of closing silently.
struct GLMConsoleConnectView: View {
    @ObservedObject var model: UsageViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cookieCapture = ConsoleCookieCapture()
    @State private var statusText = "请在下方页面完成登录和验证码，然后点击“完成连接”。"
    @State private var isCompleting = false

    var body: some View {
        VStack(spacing: 10) {
            Text("连接智谱官方控制台")
                .font(.system(size: 14, weight: .semibold))
            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ConsoleWebView(baseURL: GLMConsoleSessionPolicy.consoleBaseURL,
                           capture: cookieCapture,
                           onCapture: { count in
                               statusText = "已捕获 \(count) 个会话 Cookie，仅来自本窗口"
                           },
                           onConsoleObservation: { observation in
                               model.recordConsoleObservation(observation)
                           })

            HStack {
                Button("完成连接") { completeConnection() }
                    .disabled(cookieCapture.latestSession == nil || isCompleting)

                Button("取消") { dismiss() }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 560, height: 560)
    }

    private func completeConnection() {
        isCompleting = true
        statusText = "正在保存会话…"
        Task {
            // A fresh look at the store, not the possibly stale poll snapshot.
            let session = await cookieCapture.freshSession()
            guard let session else {
                statusText = "未捕获到会话 Cookie，请先完成登录"
                isCompleting = false
                return
            }
            let saved = model.saveGLMConsoleSession(session)
            guard saved else {
                // Storage failure propagates: the window stays open for retry.
                statusText = "会话保存失败，本机钥匙串写入未成功，请重试"
                isCompleting = false
                return
            }
            dismiss()
        }
    }
}

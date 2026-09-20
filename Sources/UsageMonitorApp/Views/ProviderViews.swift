import AppKit
import SwiftUI
import UsageMonitorCore

struct ProviderBalanceView: View {
    let report: ProviderReport
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.balances.isEmpty {
                Text(report.connection == .stale ? "暂无余额数据" : "尚未获取到余额")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(report.balances.enumerated()), id: \.offset) { _, balance in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DecimalFormatting.balanceText(balance)).font(.system(size: 13, weight: .semibold, design: .rounded)).textSelection(.enabled)
                        Text(DecimalFormatting.balanceDetailText(balance)).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            ProviderUpdatedFooter(report: report)
        }
    }
}

struct CredentialFeedbackView: View {
    let feedback: CredentialFeedback?
    var body: some View {
        Group { if let feedback { Text(feedback.displayText).font(.system(size: 10)).foregroundStyle(feedback.needsAttention ? Color.orange : Color.secondary).lineLimit(2).textSelection(.enabled) } }
    }
}

struct ProviderUpdatedFooter: View {
    let report: ProviderReport
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let lastSuccessAt = report.lastSuccessAt { Text(UsageFormatting.updatedText(fetchedAt: lastSuccessAt)).font(.system(size: 10)).foregroundStyle(.secondary) }
            if let error = report.error { Text(error.displayText).font(.system(size: 10)).foregroundStyle(report.connection == .stale ? Color.orange : Color.secondary).lineLimit(2) }
        }
    }
}

struct DeepSeekSettingsView: View {
    @ObservedObject var form: ConnectionFormState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { SecureField("sk-…", text: $form.draft).textFieldStyle(.roundedBorder).font(.system(size: 11)); Button("保存") { form.save() }.disabled(!form.canSave) }
            HStack { Button("删除 Key") { form.deleteCredential() }; Spacer(); Button("关闭") { form.collapse() } }.controlSize(.small)
            Text("Key 保存在 macOS 钥匙串，仅用于读取余额，不用于任何模型调用。").font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(8).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CommandCodeSettingsView: View {
    @ObservedObject var form: ConnectionFormState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { SecureField("Command Code API Key", text: $form.draft).textFieldStyle(.roundedBorder).font(.system(size: 11)); Button("保存") { form.save() }.disabled(!form.canSave) }
            HStack {
                Button("删除 Key") { form.deleteCredential() }
                Spacer()
                Button("打开 Studio") { NSWorkspace.shared.open(URL(string: "https://commandcode.ai/studio/")!) }
                Button("关闭") { form.collapse() }
            }.controlSize(.small)
            Text("Key 保存在 macOS 钥匙串，用于读取额度；仅在手动或已启用的定时点火时交给官方 CLI 发起最小模型请求。不读取浏览器 Cookie。")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(8).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

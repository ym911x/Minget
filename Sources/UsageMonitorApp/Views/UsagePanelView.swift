import SwiftUI
import UsageMonitorCore

/// Detail panel, grouped Codex / DeepSeek / GLM (v1.1 requirement 7).
///
/// The same view is hosted by the status item's popover and by the standalone detail window,
/// so there is exactly one place where the numbers are laid out.
struct UsagePanelView: View {
    @ObservedObject var model: UsageViewModel
    var onDetailWindow: (() -> Void)?
    var onQuit: () -> Void

    /// One collapsible form per provider. `StateObject` keeps the draft and the expansion
    /// stable across refresh-driven re-renders, so a background balance update can never
    /// interrupt typing (Round 7 requirement 4).
    @StateObject private var deepSeekForm: ConnectionFormState
    @StateObject private var glmForm: ConnectionFormState

    init(model: UsageViewModel,
         onDetailWindow: (() -> Void)? = nil,
         onQuit: @escaping () -> Void) {
        self.model = model
        self.onDetailWindow = onDetailWindow
        self.onQuit = onQuit
        _deepSeekForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .deepseek))
        _glmForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .glm))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                codexSection
                Divider()
                providerSection(.deepseek, form: deepSeekForm) {
                    ProviderBalanceView(report: deepSeekReport)
                }
                Divider()
                providerSection(.glm, form: glmForm) {
                    GLMReportView(report: glmReport,
                                  observation: model.glmObservation,
                                  consoleObservations: model.consoleObservations)
                }

                Divider()
                footer
            }
            .padding(14)
        }
        .frame(width: 320, height: 470)
        .onAppear { model.panelWillOpen() }
    }

    private var deepSeekReport: ProviderReport {
        model.providerReports.first { $0.platform == .deepseek } ?? Self.placeholder(.deepseek)
    }

    private var glmReport: ProviderReport {
        model.providerReports.first { $0.platform == .glm } ?? Self.placeholder(.glm)
    }

    static func placeholder(_ platform: ProviderPlatform) -> ProviderReport {
        return ProviderReport(platform: platform, accountID: nil, balances: [],
                              lastSuccessAt: nil, connection: .notConfigured,
                              isLive: false, error: nil,
                              consoleURL: platform == .glm ? GLMProvider.consoleURL : nil)
    }

    // MARK: Codex

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Codex", subtitle: "Codex 账号额度（不含其他 ChatGPT 模型的消息额度）")

            accountRow

            switch model.displayState {
            case .live(let snapshot):
                content(snapshot: snapshot, error: nil)
            case .stale(let snapshot, let error):
                content(snapshot: snapshot, error: error)
            case .unavailable(let error):
                ErrorStateView(error: error)
            }

            if let snapshot = model.currentSnapshot {
                Text(UsageFormatting.updatedText(fetchedAt: snapshot.fetchedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("从未成功获取数据")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Account email from `account/read`. When it could not be established, the panel says so
    /// instead of inventing one, and no address is ever hard-coded (v1.1 requirement 2).
    @ViewBuilder
    private var accountRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let email = model.codexAccount?.displayEmail {
                Text(email)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("账号信息暂不可用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(snapshot: UsageSnapshot, error: UsageError?) -> some View {
        if let error {
            StaleBannerView(error: error, fetchedAt: snapshot.fetchedAt)
        }

        if let fiveHour = snapshot.fiveHour {
            UsageRowView(window: fiveHour)
        } else {
            MissingWindowRowView(kind: .fiveHour)
        }

        Divider()

        if let weekly = snapshot.weekly {
            UsageRowView(window: weekly)
        } else {
            MissingWindowRowView(kind: .weekly)
        }
    }

    // MARK: Providers

    @ViewBuilder
    private func providerSection<Content: View>(
        _ platform: ProviderPlatform,
        form: ConnectionFormState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let report = platform == .deepseek ? deepSeekReport : glmReport
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title: platform.displayName,
                              subtitle: subtitle(for: report))
                Spacer()
                Button(form.isExpanded ? "收起" : "连接") { form.toggle() }
                    .controlSize(.small)
            }
            content()
            // The feedback line lives in the section, outside the collapsible form, so a
            // successful save that collapses the form still leaves the verification state
            // on display (Round 7 requirement 3).
            CredentialFeedbackView(feedback: model.credentialFeedback(for: platform))
            if form.isExpanded {
                settingsForm(for: platform, form: form)
            }
        }
    }

    @ViewBuilder
    private func settingsForm(for platform: ProviderPlatform, form: ConnectionFormState) -> some View {
        switch platform {
        case .deepseek: DeepSeekSettingsView(form: form)
        case .glm: GLMSettingsView(form: form)
        case .codex: EmptyView()
        }
    }

    private func subtitle(for report: ProviderReport) -> String {
        switch report.connection {
        case .notConfigured: return "未连接"
        case .connecting: return "正在获取…"
        case .connected: return "已连接"
        case .stale: return "已连接（数据已过期）"
        case .unavailable: return "无法连接"
        case .authSuspended: return "需要重新连接"
        case .unverified: return "暂无法连接"
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    model.refreshNow()
                } label: {
                    if model.isRefreshing || model.isProviderRefreshing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("刷新中…")
                        }
                    } else {
                        Text("全部刷新")
                    }
                }
                .disabled(model.isRefreshing || model.isProviderRefreshing)

                if let onDetailWindow {
                    Spacer()
                    Button("详情窗口") { onDetailWindow() }
                }

                Spacer()
                Button("退出") { onQuit() }
            }
            .controlSize(.small)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

/// Reusable footer line for a provider: last successful update, or the failure's fixed text.
struct ProviderUpdatedFooter: View {
    let report: ProviderReport

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let lastSuccessAt = report.lastSuccessAt {
                Text(UsageFormatting.updatedText(fetchedAt: lastSuccessAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let error = report.error {
                Text(error.displayText)
                    .font(.system(size: 10))
                    .foregroundStyle(report.connection == .stale ? Color.orange : Color.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

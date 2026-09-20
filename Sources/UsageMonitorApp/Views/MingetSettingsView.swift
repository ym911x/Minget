import AppKit
import SwiftUI
import UsageMonitorCore

/// 1.4.0 settings surface. The daily fire list is user-extensible, so the content scrolls
/// inside a bounded window while the title and footer remain reachable.
///
/// Top to bottom: title, the "菜单栏显示" radio group, the service group, advanced
/// diagnostics, footer. The service group lists both ChatGPT profiles read-only plus the two
/// credential-backed providers, whose connection forms open one at a time.
struct MingetSettingsView: View {

    static let pageSize = CGSize(width: 520, height: 700)
    static let margin: CGFloat = 18

    @ObservedObject var model: UsageViewModel
    @ObservedObject var preferences: DetailPreferences
    @ObservedObject var menuBarPreferences: MenuBarPreferences
    var onDetailWindow: (() -> Void)?
    var onQuit: () -> Void

    @StateObject private var deepSeekForm: ConnectionFormState
    @StateObject private var commandCodeForm: ConnectionFormState
    @State private var showsAbout = false

    init(model: UsageViewModel,
         preferences: DetailPreferences = .shared,
         menuBarPreferences: MenuBarPreferences = .shared,
         onDetailWindow: (() -> Void)? = nil,
         onQuit: @escaping () -> Void) {
        self.model = model
        self.preferences = preferences
        self.menuBarPreferences = menuBarPreferences
        self.onDetailWindow = onDetailWindow
        self.onQuit = onQuit
        _deepSeekForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .deepseek))
        _commandCodeForm = StateObject(wrappedValue: ConnectionFormState(model: model, platform: .commandcode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置").font(.system(size: 20, weight: .bold))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    menuBarGroup
                    FireScheduleSettingsView(preferences: model.fireSchedules)
                    serviceGroup

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
                    }
                    .font(.system(size: 11))
                }
                .padding(.trailing, 4)
            }

            footer
        }
        .padding(Self.margin)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
    }

    // MARK: - Menu bar source

    private var menuBarGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("菜单栏显示").font(.system(size: 13, weight: .semibold))
            // A vertical radio group in the fixed order account A, account B, DeepSeek. Only
            // one source can be selected; the stored value is a stable profile id, never an
            // index (REQUIREMENTS.md §6.1).
            Picker("菜单栏显示", selection: $menuBarPreferences.selection) {
                ForEach(model.coordinator.profileIDs, id: \.self) { profileID in
                    Text(profileName(profileID)).tag(MenuBarPreferences.Selection.profile(profileID))
                }
                Text("DeepSeek").tag(MenuBarPreferences.Selection.deepSeek)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            deepSeekCurrencyRow
            lowUsageRefreshSettings

            Text("菜单栏显示与详情页显示相互独立：隐藏详情卡不会停止该来源的刷新。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .settingsGroupBackground()
    }

    @ViewBuilder
    private var deepSeekCurrencyRow: some View {
        if menuBarPreferences.selection == .deepSeek {
            let currencies = model.deepSeekCurrencies
            if currencies.count >= 2 {
                HStack(spacing: 8) {
                    Text("菜单栏币种").font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("菜单栏币种", selection: $menuBarPreferences.deepSeekCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(Optional(currency))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            } else if currencies.count == 1 {
                Text("币种 \(currencies[0])").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("等待余额数据").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var lowUsageRefreshSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("低额度时提高菜单栏刷新频率",
                   isOn: $menuBarPreferences.lowUsageRefreshEnabled)
                .font(.system(size: 11))
                .controlSize(.small)

            Picker("加速周期", selection: $menuBarPreferences.lowUsageRefreshIntervalSeconds) {
                ForEach(MenuBarPreferences.supportedRefreshIntervalSeconds, id: \.self) { seconds in
                    Text("每 " + String(seconds) + " 秒").tag(seconds)
                }
            }
            .font(.system(size: 11))
            .disabled(!menuBarPreferences.lowUsageRefreshEnabled)

            HStack(spacing: 8) {
                Text("5 小时阈值").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $menuBarPreferences.chatGPTFiveHourThresholdPercent,
                        in: 0...100,
                        step: 1) {
                    Text("低于 " + String(menuBarPreferences.chatGPTFiveHourThresholdPercent) + "%")
                        .monospacedDigit()
                }
                .controlSize(.small)
                .disabled(!menuBarPreferences.lowUsageRefreshEnabled)
            }

            HStack(spacing: 8) {
                Text("周额度阈值").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $menuBarPreferences.chatGPTWeeklyThresholdPercent,
                        in: 0...100,
                        step: 1) {
                    Text("低于 " + String(menuBarPreferences.chatGPTWeeklyThresholdPercent) + "%")
                        .monospacedDigit()
                }
                .controlSize(.small)
                .disabled(!menuBarPreferences.lowUsageRefreshEnabled)
            }

            HStack(spacing: 8) {
                Text("DeepSeek CNY 阈值").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                TextField("15.00", text: $menuBarPreferences.deepSeekBalanceThresholdCNYText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)
                    .multilineTextAlignment(.trailing)
                    .disabled(!menuBarPreferences.lowUsageRefreshEnabled)
                Text("元").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if menuBarPreferences.deepSeekBalanceThresholdCNY == nil {
                Text("请输入大于等于 0 的数字；无效时 DeepSeek 加速会暂停。")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.menuBarRefreshStatusText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("恢复默认") {
                    menuBarPreferences.resetMenuBarRefreshSettings()
                }
                .controlSize(.small)
            }
            Text("阈值采用“剩余量严格低于”判断；只加快当前菜单栏选中的账号或余额来源。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func profileName(_ profileID: String) -> String {
        model.profileState(profileID)?.profile.displayName ?? profileID
    }

    // MARK: - Services

    private var serviceGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("服务").font(.system(size: 13, weight: .semibold)).padding(.bottom, 6)
            ForEach(Array(model.profileStates.enumerated()), id: \.element.id) { index, state in
                if index > 0 { Divider().padding(.vertical, 6) }
                ServiceStatusRow(title: state.profile.displayName,
                                 subtitle: state.connectionText,
                                 detail: "CODEX_HOME \(state.profile.codexHomeDisplaySuffix)")
            }
            Divider().padding(.vertical, 6)
            ServiceStatusRow(title: "DeepSeek", subtitle: providerStatus(.deepseek),
                             detail: menuBarPreferences.selection == .deepSeek
                                 ? "菜单栏正在显示，隐藏详情卡不影响余额刷新"
                                 : nil,
                             toggle: $preferences.showDeepSeek,
                             buttonTitle: deepSeekForm.isExpanded ? "收起" : "管理") {
                toggleForm(.deepseek)
            }
            if deepSeekForm.isExpanded {
                DeepSeekSettingsView(form: deepSeekForm).padding(.top, 8)
            }
            Divider().padding(.vertical, 6)
            ServiceStatusRow(title: "Command Code", subtitle: providerStatus(.commandcode),
                             detail: nil, toggle: $preferences.showCommandCode,
                             buttonTitle: commandCodeForm.isExpanded ? "收起" : "管理") {
                toggleForm(.commandcode)
            }
            if commandCodeForm.isExpanded {
                CommandCodeSettingsView(form: commandCodeForm).padding(.top, 8)
            }
        }
        .settingsGroupBackground()
    }

    /// Single-open accordion: expanding one connection form collapses the other, so the fixed
    /// page height cannot be overflowed by two open forms at once.
    private func toggleForm(_ platform: ProviderPlatform) {
        switch platform {
        case .deepseek:
            let willExpand = !deepSeekForm.isExpanded
            commandCodeForm.collapse()
            deepSeekForm.isExpanded = willExpand
        case .commandcode:
            let willExpand = !commandCodeForm.isExpanded
            deepSeekForm.collapse()
            commandCodeForm.isExpanded = willExpand
        case .codex:
            return
        }
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

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text("版本 \(appVersion)").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            if let onDetailWindow { Button("打开详情窗口") { onDetailWindow() } }
            Button("关于") { showsAbout = true }
                .popover(isPresented: $showsAbout, arrowEdge: .bottom) { MingetAboutView() }
            Button("退出明明有数") { onQuit() }
        }.controlSize(.small)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4.0"
    }
}

private struct FireScheduleSettingsView: View {
    @ObservedObject var preferences: FireSchedulePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("5 小时点火计划").font(.system(size: 13, weight: .semibold))
            Text("每日本地时间，勾选后生效；睡眠或启动错过时最多补跑 10 分钟。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            ForEach(FireScheduleTarget.allCases) { target in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(target.displayName).font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button {
                            preferences.add(target: target)
                        } label: {
                            Label("添加时间", systemImage: "plus")
                        }
                        .controlSize(.small)
                    }

                    if preferences.entries(for: target).isEmpty {
                        Text("尚未添加").font(.system(size: 9)).foregroundStyle(.tertiary)
                    } else {
                        ForEach(preferences.entries(for: target)) { entry in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { entry.isEnabled },
                                    set: { preferences.setEnabled($0, for: entry.id) }
                                ))
                                .labelsHidden()
                                .controlSize(.small)

                                DatePicker("", selection: dateBinding(entry), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .datePickerStyle(.field)
                                    .frame(width: 92)

                                Text(entry.isEnabled ? "已启用" : "未启用")
                                    .font(.system(size: 9))
                                    .foregroundStyle(entry.isEnabled ? Color.green : Color.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    preferences.remove(entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("删除 \(target.displayName) \(timeText(entry.minuteOfDay))")
                            }
                        }
                    }

                    if preferences.hasSubFiveHourGap(for: target) {
                        Text("相邻已启用时间小于 5 小时：仍会发起请求，但通常不会开启新窗口。")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                if target != FireScheduleTarget.allCases.last { Divider() }
            }

            Text("Command Code 使用钥匙串中的 Key 调用官方 CLI 最小请求，会消耗少量额度。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .settingsGroupBackground()
    }

    private func dateBinding(_ entry: FireScheduleEntry) -> Binding<Date> {
        Binding(get: {
            var components = DateComponents()
            components.calendar = Calendar.current
            components.year = 2001
            components.month = 1
            components.day = 1
            components.hour = entry.minuteOfDay / 60
            components.minute = entry.minuteOfDay % 60
            return components.date ?? Date(timeIntervalSinceReferenceDate: 0)
        }, set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            preferences.setMinute((components.hour ?? 0) * 60 + (components.minute ?? 0), for: entry.id)
        })
    }

    private func timeText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

private struct ServiceStatusRow: View {
    let title: String; let subtitle: String; let detail: String?
    var toggle: Binding<Bool>? = nil; var buttonTitle: String? = nil; var action: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail ?? subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if detail != nil {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let toggle { Toggle("", isOn: toggle).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            if let buttonTitle, let action { Button(buttonTitle, action: action).controlSize(.small) }
        }.padding(.vertical, 5)
    }
}

private extension View {
    func settingsGroupBackground() -> some View {
        padding(12).background(Color(NSColor.controlBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1) }
    }
}

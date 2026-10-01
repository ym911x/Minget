import AppKit
import SwiftUI
import UsageMonitorCore

/// One native settings window with shared account management and grouped preferences.
struct MingetSettingsView: View {

    static let pageSize = CGSize(width: 780, height: 640)
    static let margin: CGFloat = 18

    @ObservedObject var model: UsageViewModel
    @ObservedObject var preferences: DetailPreferences
    @ObservedObject var menuBarPreferences: MenuBarPreferences
    @ObservedObject var displayNames: DisplayNamePreferences
    var onDetailWindow: (() -> Void)?
    var onQuit: () -> Void
    @ObservedObject var navigation: SettingsNavigation
    var onDone: () -> Void


    init(model: UsageViewModel,
         preferences: DetailPreferences = .shared,
         menuBarPreferences: MenuBarPreferences = .shared,
         displayNames: DisplayNamePreferences? = nil,
         onDetailWindow: (() -> Void)? = nil,
         onQuit: @escaping () -> Void,
         navigation: SettingsNavigation? = nil,
         onDone: @escaping () -> Void = {}) {
        self.model = model
        self.preferences = preferences
        self.menuBarPreferences = menuBarPreferences
        _displayNames = ObservedObject(wrappedValue: displayNames ?? model.displayNames)
        self.onDetailWindow = onDetailWindow
        self.onQuit = onQuit
        self.navigation = navigation ?? SettingsNavigation()
        self.onDone = onDone
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsSection?>(get: { navigation.section }, set: { if let section = $0 { navigation.section = section } })) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(navigation.section.title).font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
                settingsPane
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(minWidth: 700, minHeight: 520)
    }

    @ViewBuilder private var settingsPane: some View {
        if navigation.section == .accounts {
            AccountManagementView(model: model, firstRun: navigation.firstRun, onDone: onDone)
        } else {
            Form {
                switch navigation.section {
                case .menuBar:
                    Section { menuBarGroup }
                case .detail:
                    Section("可见服务") { detailDisplayGroup }
                    Section { Text("概览显示所有账号摘要；选择服务后查看完整额度。隐藏卡片不会改变菜单栏来源或停止刷新。") }
                case .schedules:
                    Section("菜单栏低额度刷新") { lowUsageRefreshSettings }
                    Section { FireScheduleSettingsView(preferences: model.fireSchedules, displayNames: displayNames) }
                case .about:
                    Section("明明有数 · Minget") {
                        LabeledContent("版本", value: appVersion)
                        Link("GitHub 项目", destination: URL(string: "https://github.com/ym911x/Minget")!)
                        if let onDetailWindow { Button("打开独立详情窗口", action: onDetailWindow) }
                    }
                    Section("高级诊断") {
                        Toggle("记录钥匙串访问诊断", isOn: Binding(get: { model.isCredentialDiagnosticOn }, set: { model.setCredentialDiagnostics($0) }))
                        if model.isCredentialDiagnosticOn, let path = model.credentialDiagnosticPath {
                            Text(path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                case .accounts: EmptyView()
                }
            }.formStyle(.grouped)
        }
    }

    // MARK: - Menu bar source

    private var detailDisplayGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("显示 Gemini", isOn: $preferences.showGoogle)
            Toggle("显示 DeepSeek", isOn: $preferences.showDeepSeek)
            Toggle("显示 Command Code", isOn: $preferences.showCommandCode)
            Text("ChatGPT 两个账号始终保留；更多账号信息在“账号”页管理。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

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
                Text(displayNames.displayName(for: DisplayNamePreferences.ServiceID.deepSeek))
                    .tag(MenuBarPreferences.Selection.deepSeek)
                ForEach(model.google.accounts) { state in
                    Text(model.google.displayName(state.account) + " · Google")
                        .tag(MenuBarPreferences.Selection.google(state.id))
                }
                if case .google(let id) = menuBarPreferences.selection,
                   !model.google.accounts.contains(where: { $0.id == id }) {
                    Text("Google 账号暂不可用").tag(MenuBarPreferences.Selection.google(id))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            googleGroupPicker
            deepSeekCurrencyRow

            Text("菜单栏显示与详情页显示相互独立：隐藏详情卡不会停止该来源的刷新。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

    }


    @ViewBuilder
    private var googleGroupPicker: some View {
        if case .google(let id) = menuBarPreferences.selection {
            let groups = model.google.accounts.first { $0.id == id }?.snapshot?.groups ?? []
            let selected = menuBarPreferences.googleGroupIDs[id]
            Picker("模型或额度组", selection: Binding<String?>(
                get: { menuBarPreferences.googleGroupIDs[id] },
                set: { menuBarPreferences.googleGroupIDs[id] = $0 })) {
                Text("请选择额度组").tag(Optional<String>.none)
                ForEach(groups) { group in Text(group.label).tag(Optional(group.id)) }
                if let selected, !groups.contains(where: { $0.id == selected }) {
                    Text("所选额度组已不可用").tag(Optional(selected))
                }
            }
            .font(.system(size: 13))
            Text("Google 额度每 5 分钟刷新，支持手动刷新。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var deepSeekCurrencyRow: some View {
        if menuBarPreferences.selection == .deepSeek {
            let currencies = model.deepSeekCurrencies
            if currencies.count >= 2 {
                HStack(spacing: 8) {
                    Text("菜单栏币种").font(.system(size: 13)).foregroundStyle(.secondary)
                    Picker("菜单栏币种", selection: $menuBarPreferences.deepSeekCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(Optional(currency))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            } else if currencies.count == 1 {
                Text("币种 \(currencies[0])").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                Text("等待余额数据").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private var lowUsageRefreshSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("低额度时提高菜单栏刷新频率",
                   isOn: $menuBarPreferences.lowUsageRefreshEnabled)
                .font(.system(size: 13))
                .controlSize(.small)

            Picker("加速周期", selection: $menuBarPreferences.lowUsageRefreshIntervalSeconds) {
                ForEach(MenuBarPreferences.supportedRefreshIntervalSeconds, id: \.self) { seconds in
                    Text("每 " + String(seconds) + " 秒").tag(seconds)
                }
            }
            .font(.system(size: 13))
            .disabled(!menuBarPreferences.lowUsageRefreshEnabled)

            HStack(spacing: 8) {
                Text("5 小时阈值").font(.system(size: 13)).foregroundStyle(.secondary)
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
                Text("周额度阈值").font(.system(size: 13)).foregroundStyle(.secondary)
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
                Text("DeepSeek CNY 阈值").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                TextField("15.00", text: $menuBarPreferences.deepSeekBalanceThresholdCNYText)
                    .textFieldStyle(.roundedBorder).labelsHidden().accessibilityLabel("DeepSeek 低余额阈值")
                    .frame(width: 78)
                    .multilineTextAlignment(.trailing)
                    .disabled(!menuBarPreferences.lowUsageRefreshEnabled)
                Text("元").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if menuBarPreferences.deepSeekBalanceThresholdCNY == nil {
                Text("请输入大于等于 0 的数字；无效时 DeepSeek 加速会暂停。")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.menuBarRefreshStatusText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("恢复默认") {
                    menuBarPreferences.resetMenuBarRefreshSettings()
                }
                .controlSize(.small)
            }
            Text("阈值采用“剩余量严格低于”判断；只加快当前菜单栏选中的账号或余额来源。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func profileName(_ profileID: String) -> String {
        displayNames.displayName(for: profileID)
    }

    private var appVersion: String {
        guard Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "Minget" else { return "1.6.1" }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.6.1"
    }
}

private struct FireScheduleSettingsView: View {
    @ObservedObject var preferences: FireSchedulePreferences
    @ObservedObject var displayNames: DisplayNamePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("5 小时点火计划").font(.system(size: 13, weight: .semibold))
            Text("每日本地时间，勾选后生效；睡眠或启动错过时最多补跑 10 分钟。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            ForEach(FireScheduleTarget.allCases) { target in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(displayName(for: target)).font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button {
                            preferences.add(target: target)
                        } label: {
                            Label("添加时间", systemImage: "plus")
                        }
                        .controlSize(.small)
                    }

                    if preferences.entries(for: target).isEmpty {
                        Text("尚未添加").font(.system(size: 13)).foregroundStyle(.tertiary)
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
                                    .font(.system(size: 13))
                                    .foregroundStyle(entry.isEnabled ? Color.green : Color.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    preferences.remove(entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                    .accessibilityLabel("删除 \(displayName(for: target)) \(timeText(entry.minuteOfDay))")
                            }
                        }
                    }

                    if preferences.hasSubFiveHourGap(for: target) {
                        Text("相邻已启用时间小于 5 小时：仍会发起请求，但通常不会开启新窗口。")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                    }
                }
                if target != FireScheduleTarget.allCases.last { Divider() }
            }

            Text("Command Code 使用钥匙串中的 Key 调用官方 CLI 最小请求，会消耗少量额度。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }

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

    private func displayName(for target: FireScheduleTarget) -> String {
        if let profileID = target.profileID {
            return displayNames.displayName(for: profileID)
        }
        return displayNames.displayName(for: DisplayNamePreferences.ServiceID.commandCode)
    }
}

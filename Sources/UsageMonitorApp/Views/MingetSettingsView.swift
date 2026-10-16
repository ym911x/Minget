import AppKit
import SwiftUI
import UsageMonitorCore

/// The settings window's own visual constants.
///
/// They live in one place so the five panes read as a single surface: one title level, one
/// note level, one sidebar mark, one set of page margins. New sizes belong here instead of
/// inline, which is how this window drifted into a mix of 11, 12, and 13 pt text.
enum SettingsStyle {
    static let pageTitleSize: CGFloat = 20
    static let pagePadding: CGFloat = 22
    static let headerTopPadding: CGFloat = 22
    static let headerBottomPadding: CGFloat = 14
    /// Section footers, the line under the page title, and other quiet explanations.
    static let noteSize: CGFloat = 11
    /// The sidebar mark: a rounded colour tile with a white glyph.
    static let markSize: CGFloat = 22
    static let markCorner: CGFloat = 6
    static let markGlyphSize: CGFloat = 12
}

extension SettingsSection {
    /// The single line under the pane title. A reminder about one control belongs in that
    /// section's footer, not in a second title.
    var subtitle: String {
        switch self {
        case .accounts: return "每个账号独立保存连接与额度缓存，可随时添加或移除。"
        case .menuBar: return "选择菜单栏显示哪一个来源。"
        case .detail: return "选择概览与详情里显示哪些服务。"
        case .schedules: return "低额度加速刷新的阈值，以及 5 小时点火计划。"
        case .about: return "版本、项目入口与钥匙串访问诊断。"
        }
    }

    /// The colour of this pane's sidebar tile. System colours only: the Claude orange stays
    /// reserved for the Antigravity pool that actually covers Claude and GPT models.
    var tint: Color {
        switch self {
        case .accounts: return .blue
        case .menuBar: return .indigo
        case .detail: return .teal
        case .schedules: return .orange
        case .about: return .gray
        }
    }
}

/// One sidebar row: a coloured tile with a white glyph, then the pane name. The tile keeps
/// its colour while the row is selected, the way the system settings sidebar does.
struct SettingsSectionRow: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: SettingsStyle.markCorner, style: .continuous)
                .fill(section.tint)
                .frame(width: SettingsStyle.markSize, height: SettingsStyle.markSize)
                .overlay {
                    Image(systemName: section.symbol)
                        .font(.system(size: SettingsStyle.markGlyphSize, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
            Text(section.title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section.title)
    }
}

/// One native settings window with shared account management and grouped preferences.
struct MingetSettingsView: View {

    static let pageSize = CGSize(width: 780, height: 640)

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
                    SettingsSectionRow(section: section).tag(section)
                }
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                paneHeader
                settingsPane
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(minWidth: 700, minHeight: 520)
    }

    /// One title level for every pane, plus that pane's single primary action when it has one.
    private var paneHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(navigation.section.title)
                    .font(.system(size: SettingsStyle.pageTitleSize, weight: .semibold))
                Text(navigation.section.subtitle)
                    .font(.system(size: SettingsStyle.noteSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Account feedback is transient status, so it sits with the title of the pane
                // that produced it instead of inside one of the grouped cards.
                if navigation.section == .accounts, !model.accountMessage.isEmpty {
                    Text(model.accountMessage)
                        .font(.system(size: SettingsStyle.noteSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if navigation.section == .accounts, model.accountRegistry != nil {
                Button { model.addingPlatform = nil; model.showAddAccount = true } label: {
                    Label("添加账号", systemImage: "plus")
                }
                .help("添加 ChatGPT、Google、DeepSeek 或 Command Code 账号")
            }
        }
        .padding(.horizontal, SettingsStyle.pagePadding)
        .padding(.top, SettingsStyle.headerTopPadding)
        .padding(.bottom, SettingsStyle.headerBottomPadding)
    }

    /// The one note style every section footer uses.
    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: SettingsStyle.noteSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var settingsPane: some View {
        if navigation.section == .accounts {
            AccountManagementView(model: model, firstRun: navigation.firstRun, onDone: onDone)
        } else {
            Form {
                switch navigation.section {
                case .menuBar: menuBarSections
                case .detail: detailSections
                case .schedules: scheduleSections
                case .about: aboutSections
                case .accounts: EmptyView()
                }
            }.formStyle(.grouped)
        }
    }

    // MARK: - Menu bar source

    @ViewBuilder private var menuBarSections: some View {
        Section {
            // A vertical radio group in the fixed order ChatGPT accounts,
            // DeepSeek, then Gemini. Each row carries the account code
            // (`O1`, `DS1`, `G1`) in front of its name — the same code the
            // menu bar shows, resolved through the one method, so the list
            // and the menu bar can never disagree. Only one source can be
            // selected; the stored value is a stable profile id, never an
            // index (REQUIREMENTS.md §6.1).
            Picker("菜单栏显示", selection: $menuBarPreferences.selection) {
                ForEach(model.coordinator.profileIDs, id: \.self) { profileID in
                    Text("\(model.menuBarCode(for: .profile(profileID))) " + profileName(profileID))
                        .tag(MenuBarPreferences.Selection.profile(profileID))
                }
                if model.accountRegistry == nil {
                    Text("\(model.menuBarCode(for: .deepSeek)) " + displayNames.displayName(for: DisplayNamePreferences.ServiceID.deepSeek))
                        .tag(MenuBarPreferences.Selection.deepSeek)
                } else {
                    ForEach(model.managedAccounts.filter { $0.platform == .deepseek && !$0.removalPending }) { row in
                        let selection = row.id == "deepseek" ? MenuBarPreferences.Selection.deepSeek : .apiAccount(row.id)
                        Text("\(model.menuBarCode(for: selection)) " + model.accountName(row))
                            .tag(selection)
                    }
                    if case .profile(let id) = menuBarPreferences.selection, !model.coordinator.profileIDs.contains(id) {
                        Text("\(model.menuBarCode(for: .profile(id))) 账号已移除，请重新选择")
                            .tag(MenuBarPreferences.Selection.profile(id))
                    }
                    if case .apiAccount(let id) = menuBarPreferences.selection, !model.managedAccounts.contains(where: { $0.id == id && !$0.removalPending }) {
                        Text("\(model.menuBarCode(for: .apiAccount(id))) 账号已移除，请重新选择")
                            .tag(MenuBarPreferences.Selection.apiAccount(id))
                    }
                    if menuBarPreferences.selection == .deepSeek, !model.managedAccounts.contains(where: { $0.id == "deepseek" && !$0.removalPending }) {
                        Text("\(model.menuBarCode(for: .deepSeek)) 账号已移除，请重新选择")
                            .tag(MenuBarPreferences.Selection.deepSeek)
                    }
                }
                ForEach(model.google.accounts) { state in
                    Text("\(model.menuBarCode(for: .google(state.id))) " + model.google.displayName(state.account) + " · Google")
                        .tag(MenuBarPreferences.Selection.google(state.id))
                }
                if case .google(let id) = menuBarPreferences.selection,
                   !model.google.accounts.contains(where: { $0.id == id }) {
                    Text("\(model.menuBarCode(for: .google(id))) Google 账号暂不可用")
                        .tag(MenuBarPreferences.Selection.google(id))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            googleGroupPicker
            deepSeekCurrencyRow
        } header: {
            Text("菜单栏显示")
        } footer: {
            sectionNote("菜单栏显示与详情页显示相互独立：隐藏详情卡不会停止该来源的刷新。")
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
            Text("Google 额度每 5 分钟刷新，支持手动刷新。")
                .font(.system(size: SettingsStyle.noteSize)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var deepSeekCurrencyRow: some View {
        if menuBarPreferences.selection == .deepSeek {
            let currencies = model.deepSeekCurrencies
            if currencies.count >= 2 {
                LabeledContent("菜单栏币种") {
                    Picker("菜单栏币种", selection: $menuBarPreferences.deepSeekCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(Optional(currency))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            } else if currencies.count == 1 {
                LabeledContent("菜单栏币种", value: currencies[0])
            } else {
                LabeledContent("菜单栏币种", value: "等待余额数据")
            }
        }
    }

    // MARK: - Detail display

    @ViewBuilder private var detailSections: some View {
        Section {
            Toggle("显示 Gemini", isOn: $preferences.showGoogle)
            Toggle("显示 DeepSeek", isOn: $preferences.showDeepSeek)
            Toggle("显示 Command Code", isOn: $preferences.showCommandCode)
        } header: {
            Text("可见服务")
        } footer: {
            sectionNote("概览显示所有账号摘要；选择服务后查看完整额度。更多账号可在“账号”页添加和管理。隐藏卡片不会改变菜单栏来源或停止刷新。")
        }
    }

    // MARK: - Refresh and fire

    @ViewBuilder private var scheduleSections: some View {
        Section {
            lowUsageRefreshRows
        } header: {
            Text("菜单栏低额度刷新")
        } footer: {
            sectionNote("阈值按“剩余量严格低于”判断；只加快当前菜单栏选中的账号或余额来源。")
        }

        Section {
            FireScheduleSettingsView(preferences: model.fireSchedules, displayNames: displayNames, targets: model.scheduleTargets)
        } header: {
            Text("5 小时点火计划")
        } footer: {
            sectionNote("每日本地时间，勾选后生效；睡眠或启动错过时最多补跑 10 分钟。Command Code 使用钥匙串中的 Key 调用官方 CLI 最小请求，会消耗少量额度。")
        }
    }

    @ViewBuilder private var lowUsageRefreshRows: some View {
        Toggle("低额度时提高菜单栏刷新频率",
               isOn: $menuBarPreferences.lowUsageRefreshEnabled)

        LabeledContent("加速周期") {
            Picker("加速周期", selection: $menuBarPreferences.lowUsageRefreshIntervalSeconds) {
                ForEach(MenuBarPreferences.supportedRefreshIntervalSeconds, id: \.self) { seconds in
                    Text("每 " + String(seconds) + " 秒").tag(seconds)
                }
            }
            .labelsHidden()
            .frame(width: 140)
        }
        .disabled(!menuBarPreferences.lowUsageRefreshEnabled)

        thresholdRow("5 小时阈值", value: $menuBarPreferences.chatGPTFiveHourThresholdPercent)
        thresholdRow("周额度阈值", value: $menuBarPreferences.chatGPTWeeklyThresholdPercent)

        LabeledContent("DeepSeek CNY 阈值") {
            HStack(spacing: 6) {
                TextField("15.00", text: $menuBarPreferences.deepSeekBalanceThresholdCNYText)
                    .textFieldStyle(.roundedBorder).labelsHidden().accessibilityLabel("DeepSeek 低余额阈值")
                    .frame(width: 78)
                    .multilineTextAlignment(.trailing)
                Text("元").foregroundStyle(.secondary)
            }
        }
        .disabled(!menuBarPreferences.lowUsageRefreshEnabled)

        if menuBarPreferences.deepSeekBalanceThresholdCNY == nil {
            Text("请输入大于等于 0 的数字；无效时 DeepSeek 加速会暂停。")
                .font(.system(size: SettingsStyle.noteSize))
                .foregroundStyle(.red)
        }

        LabeledContent("当前策略") {
            HStack(spacing: 10) {
                Text(model.menuBarRefreshStatusText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Button("恢复默认") {
                    menuBarPreferences.resetMenuBarRefreshSettings()
                }
                .controlSize(.small)
            }
        }
    }

    /// A numeric threshold row: the value reads first and the stepper sits behind it, which
    /// is how macOS pairs a number with its stepper.
    private func thresholdRow(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("低于 " + String(value.wrappedValue) + "%").monospacedDigit()
                Stepper("", value: value, in: 0...100, step: 1)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel("\(title)，当前低于 \(value.wrappedValue)%")
            }
        }
        .disabled(!menuBarPreferences.lowUsageRefreshEnabled)
    }

    // MARK: - About

    @ViewBuilder private var aboutSections: some View {
        Section {
            LabeledContent("版本") { Text(Self.appVersion()).monospacedDigit() }
        } header: {
            Text("明明有数 · Minget")
        } footer: {
            sectionNote("你的 AI 使用，心里有数。 · Your AI usage, at a glance.")
        }

        Section {
            Link("GitHub 项目", destination: URL(string: "https://github.com/ym911x/Minget")!)
            if let onDetailWindow { Button("打开独立详情窗口", action: onDetailWindow) }
        } header: {
            Text("入口")
        }

        Section {
            Toggle("记录钥匙串访问诊断", isOn: Binding(get: { model.isCredentialDiagnosticOn }, set: { model.setCredentialDiagnostics($0) }))
            if model.isCredentialDiagnosticOn, let path = model.credentialDiagnosticPath {
                Text(path)
                    .font(.system(size: SettingsStyle.noteSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
        } header: {
            Text("高级诊断")
        } footer: {
            sectionNote("只记录 Minget 自身钥匙串访问的类别与结果，不包含 Key 内容、请求或用户文本。")
        }
    }

    private func profileName(_ profileID: String) -> String {
        displayNames.displayName(for: profileID)
    }

    /// The bundle's own version. A host without the app's Info.plist reports an unknown
    /// version instead of a stale hard-coded number.
    static func appVersion(bundle: Bundle = .main) -> String {
        guard bundle.object(forInfoDictionaryKey: "CFBundleName") as? String == "Minget",
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else { return "—" }
        return version
    }
}

private struct FireScheduleSettingsView: View {
    @ObservedObject var preferences: FireSchedulePreferences
    @ObservedObject var displayNames: DisplayNamePreferences
    let targets: [FireScheduleTarget]

    var body: some View {
        ForEach(targets) { target in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(displayName(for: target)).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Button {
                        preferences.add(target: target)
                    } label: {
                        Label("添加时间", systemImage: "plus")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("为 \(displayName(for: target)) 添加点火时间")
                }

                if preferences.entries(for: target).isEmpty {
                    Text("尚未添加").font(.system(size: SettingsStyle.noteSize)).foregroundStyle(.tertiary)
                } else {
                    ForEach(preferences.entries(for: target)) { entry in
                        entryRow(entry, target: target)
                    }
                }

                if preferences.hasSubFiveHourGap(for: target) {
                    Text("相邻已启用时间小于 5 小时：仍会发起请求，但通常不会开启新窗口。")
                        .font(.system(size: SettingsStyle.noteSize))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func entryRow(_ entry: FireScheduleEntry, target: FireScheduleTarget) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { preferences.setEnabled($0, for: entry.id) }
            ))
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("启用 \(displayName(for: target)) \(timeText(entry.minuteOfDay)) 的点火")

            DatePicker("", selection: dateBinding(entry), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: 92)
                .accessibilityLabel("\(displayName(for: target)) 的点火时间")

            Text(entry.isEnabled ? "已启用" : "未启用")
                .font(.system(size: 12))
                .foregroundStyle(entry.isEnabled ? Color.green : Color.secondary)
            Spacer(minLength: 8)
            Button(role: .destructive) {
                preferences.remove(entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除 \(displayName(for: target)) \(timeText(entry.minuteOfDay))")
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
        return displayNames.displayName(for: target.rawValue)
    }
}

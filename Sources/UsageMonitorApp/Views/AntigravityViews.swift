import SwiftUI
import UsageMonitorCore

struct AntigravityConnectionView: View {
    @ObservedObject var google: AntigravityModel
    @ObservedObject var preferences: DetailPreferences = .shared
    @State private var editingSlot: AntigravitySlot?
    @State private var disconnectSlot: AntigravitySlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AntigravitySlot.allCases, id: \.self) { slot in
                let connection = google.connection(for: slot)
                let state = google.accounts.first { $0.id == connection?.email }
                let name = state.map { google.displayName($0.account) } ?? "Google 账号 " + slot.rawValue
                AccountManagementRow(service: .gemini, name: name, identity: connection?.email ?? "未登录",
                    status: google.activeLoginSlot == slot ? "登录进行中" :
                        (connection == nil ? "等待连接" : google.loginStatus(for: slot).hasPrefix("授权失效") ? "需要重新登录" : "已登录")
                        + (state.map { " · " + $0.statusText } ?? "")) {
                    if google.activeLoginSlot == slot {
                        Button("继续登录") { google.login(slot) }
                        Button("取消") { google.cancelLogin() }
                    } else {
                        Button(connection == nil ? "登录" : "重新登录") { google.login(slot) }
                            .disabled(google.activeLoginSlot != nil || google.isPreparingCLI)
                    }
                    Menu {
                        Button("显示名称…") { editingSlot = slot }.disabled(connection == nil)
                        Button("断开本机…", role: .destructive) { disconnectSlot = slot }
                            .disabled(connection == nil || google.activeLoginSlot != nil)
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("\(name) 更多管理操作")
                }
                if slot == .a { Divider() }

            }
            DisclosureGroup("连接准备") {
            HStack {
                Text(google.feedback).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(google.isPreparingCLI ? "准备中…" : "准备官方登录组件") { google.prepareCLI() }
                    .disabled(google.isPreparingCLI)
            }
            }.font(.system(size: 11))
            Text("登录状态与额度读取状态分别显示。")
                .font(.system(size: 11)).foregroundStyle(.secondary)

        }
        .sheet(isPresented: Binding(get: { editingSlot != nil }, set: { if !$0 { editingSlot = nil } })) {
            if let slot = editingSlot, let connection = google.connection(for: slot),
               let state = google.accounts.first(where: { $0.id == connection.email }) {
                AccountNameSheet(name: google.displayName(state.account), defaultName: state.account.label) {
                    google.setName($0, accountID: state.id); return true
                }
            }
        }
        .confirmationDialog("断开这个 Google 账号？", isPresented: Binding(get: { disconnectSlot != nil }, set: { if !$0 { disconnectSlot = nil } }), titleVisibility: .visible) {
            Button("断开本机", role: .destructive) { if let slot = disconnectSlot { google.disconnect(slot) }; disconnectSlot = nil }
            Button("取消", role: .cancel) { disconnectSlot = nil }
        } message: { Text("移除 Minget 的本机连接，之后可以重新登录。不会替你切换菜单栏账号或额度组。") }
    }
}

struct AntigravityOverviewCard: View {
    /// The card with both reported pools on screen: 16 pt padding twice, the 50 pt header,
    /// the primary pool's two 40 pt rows, the second pool's label and its two rows, and one
    /// 12 pt gap between each of those blocks.
    static let height: CGFloat = 318
    let state: AntigravityAccountState
    let displayName: String
    var showClaudeGPTQuota = true
    var showArgonQuota = true
    static func height(showClaudeGPTQuota: Bool) -> CGFloat {
        showClaudeGPTQuota ? height : 186
    }
    private var groups: [AntigravityQuotaGroup] { state.snapshot?.groups ?? [] }
    private var primary: AntigravityQuotaGroup? { QuotaPresentation.primaryGroup(groups) }

    private var planHelp: String {
        guard let plan = state.snapshot?.plan else { return "刷新后可核对 Google 套餐" }
        let time = UsageFormatting.shortDateTime(plan.checkedAt)
        return plan.name == nil ? "上次尝试核对套餐：\(time)" : "套餐核对时间：\(time)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AccountCardHeader(service: .gemini, name: displayName, subtitle: "Gemini · " + (state.snapshot?.plan?.name ?? "套餐暂未确认"),
                              identity: state.account.email ?? "账号暂不可用", status: state.statusText,
                              isCached: state.hasCachedData)
                .frame(height: 50)
                .help(planHelp)
            quotaRows(primary, tint: .levels)
            if let failure = state.failure {
                HStack {
                    Text(failure.displayText).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if failure == .accountRegionUnavailable {
                        Spacer(minLength: 8)
                        Link("官方说明", destination: URL(string: "https://www.antigravity.google/docs/faq/#what-is-google-antigravitys-geographical-availability")!)
                    }
                }.font(.system(size: 11))
            }
            // Every other reported pool is drawn in place, directly under the primary one.
            ForEach(QuotaPresentation.otherGroups(groups, showClaudeGPTQuota: showClaudeGPTQuota, showArgonQuota: showArgonQuota)) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.label).font(.system(size: 13, weight: .semibold))
                    quotaRows(group, tint: QuotaPresentation.tint(for: group))
                    if !group.models.isEmpty {
                        Text(group.models.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }.quotaCardSurface()
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func quotaRows(_ group: AntigravityQuotaGroup?, tint: QuotaUsageTint) -> some View {
        let reportedOnly = group?.label == QuotaPresentation.argonGroupName
        let fiveHour = group?.buckets.first { $0.kind == .fiveHour }
        let weekly = group?.buckets.first { $0.kind == .weekly }
        if !reportedOnly || fiveHour != nil {
            QuotaWindowBlock(label: "5 小时", kind: .fiveHour, window: fiveHour?.rateLimitWindow,
                             isCached: state.hasCachedData, resetDate: fiveHour?.resetsAt, tint: tint)
        }
        if !reportedOnly || weekly != nil {
            QuotaWindowBlock(label: "周额度", kind: .weekly, window: weekly?.rateLimitWindow,
                             isCached: state.hasCachedData, resetDate: weekly?.resetsAt, tint: tint)
        }
        ForEach(group?.buckets.filter { $0.kind == .unknown } ?? []) { bucket in
            HStack {
                Text(bucket.label)
                Spacer()
                Text(bucket.percentageText).monospacedDigit()
            }.font(.system(size: 13))
            Text(bucket.resetText()).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

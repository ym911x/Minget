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
    static let height: CGFloat = 264
    let state: AntigravityAccountState
    let displayName: String
    var expanded: Binding<Bool>? = nil
    @State private var localExpanded = false
    private var expansion: Binding<Bool> { expanded ?? $localExpanded }
    private var groups: [AntigravityQuotaGroup] { state.snapshot?.groups ?? [] }
    private var primary: AntigravityQuotaGroup? { QuotaPresentation.primaryGroup(groups) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AccountCardHeader(service: .gemini, name: displayName, subtitle: "Gemini · Google / Antigravity",
                              identity: state.account.email ?? "账号暂不可用", status: state.statusText,
                              isCached: state.isCached)
                .frame(height: 50)
            quotaRows(primary)
            HStack {
                Text(state.snapshot.map { "最近成功 " + $0.fetchedAt.formatted(date: .omitted, time: .shortened) } ?? "尚未成功读取")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if state.isCached { Text("缓存数据").font(.system(size: 11)).foregroundStyle(.orange) }
            }
            if let failure = state.failure {
                Text(failure.displayText).font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let other = groups.filter { $0.id != primary?.id }
            if !other.isEmpty {
                DisclosureGroup("其他额度组", isExpanded: expansion) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(other) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.label).font(.system(size: 13, weight: .semibold))
                                quotaRows(group)
                                if !group.models.isEmpty {
                                    Text(group.models.joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(.top, 12)
                }.font(.system(size: 12))
            }
        }.quotaCardSurface().frame(minHeight: DetailPageLayout.codexCardHeight)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func quotaRows(_ group: AntigravityQuotaGroup?) -> some View {
        QuotaWindowBlock(label: "5 小时", kind: .fiveHour,
                         window: group?.buckets.first { $0.kind == .fiveHour }?.rateLimitWindow,
                         isCached: state.isCached, resetDate: group?.buckets.first { $0.kind == .fiveHour }?.resetsAt)
        QuotaWindowBlock(label: "周额度", kind: .weekly,
                         window: group?.buckets.first { $0.kind == .weekly }?.rateLimitWindow,
                         isCached: state.isCached, resetDate: group?.buckets.first { $0.kind == .weekly }?.resetsAt)
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

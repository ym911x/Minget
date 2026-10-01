import SwiftUI
import UsageMonitorCore

struct AntigravityConnectionView: View {
    @ObservedObject var google: AntigravityModel
    @ObservedObject var preferences: DetailPreferences = .shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Google / Antigravity").font(.headline)
                Spacer()
                Button(google.isPreparingCLI ? "准备中…" : "准备官方 CLI") { google.prepareCLI() }
                    .disabled(google.isPreparingCLI)
            }
            Text(google.feedback).font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(AntigravitySlot.allCases, id: \.self) { slot in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Google 账号 " + slot.rawValue).font(.subheadline.bold())
                        Spacer()
                        if google.activeLoginSlot == slot {
                            Button("继续登录") { google.login(slot) }
                            Button("取消登录") { google.cancelLogin() }
                        } else {
                            Button(google.connection(for: slot) == nil ? "登录 Google 账号" : "重新登录") { google.login(slot) }
                                .disabled(google.activeLoginSlot != nil || google.isPreparingCLI)
                        }
                        if google.connection(for: slot) != nil {
                            Button("断开本机") { google.disconnect(slot) }.disabled(google.activeLoginSlot != nil)
                        }
                    }
                    Text(google.loginStatus(for: slot)).font(.system(size: 11)).foregroundStyle(.secondary)
                    if let connection = google.connection(for: slot), let state = google.accounts.first(where: { $0.id == connection.email }) {
                        Text("额度：" + state.statusText).font(.system(size: 10)).foregroundStyle(.secondary)
                        TextField("账号显示名称", text: Binding(get: { google.names[state.id] ?? state.account.label },
                            set: { google.setName($0, accountID: state.id) })).textFieldStyle(.roundedBorder)
                    }
                }.padding(.vertical, 4)
            }
            if !google.connections.isEmpty { Button("刷新 Google 额度") { google.refresh(force: true) } }
            Text("在官方页面分别登录两个账号。授权数据由官方 CLI 保存在这台 Mac 的独立账号目录中。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(12).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AntigravityOverviewCard: View {
    static let height: CGFloat = 264
    let state: AntigravityAccountState
    let displayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("G").font(.system(size: 24, weight: .semibold)).foregroundStyle(.blue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("Google · Antigravity").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(state.failure == nil && !state.isCached ? Color.green : Color.orange)
                    .frame(width: 6, height: 6).accessibilityHidden(true)
            }
            Text(state.statusText).font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(2)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(state.snapshot?.groups ?? []) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.label).font(.system(size: 12, weight: .semibold))
                            ForEach(group.buckets) { bucket in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(bucket.label).font(.system(size: 11))
                                        Spacer()
                                        Text(bucket.percentageText).font(.system(size: 12, weight: .medium)).monospacedDigit()
                                    }
                                    if let fraction = bucket.remainingFraction {
                                        ProgressView(value: fraction, total: 1)
                                            .tint(state.isCached ? .secondary : .blue)
                                            .accessibilityLabel(bucket.label + "剩余额度")
                                    }
                                    Text(bucket.resetText()).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                            if !group.models.isEmpty {
                                DisclosureGroup("模型范围") {
                                    Text(group.models.joined(separator: "\n"))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }.font(.system(size: 10))
                            }
                        }
                    }
                    if state.snapshot?.groups.isEmpty != false {
                        Text("暂无可确认的模型额度").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if let date = state.snapshot?.fetchedAt {
                Text("\(state.isCached ? "缓存 · " : "")最近成功 \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

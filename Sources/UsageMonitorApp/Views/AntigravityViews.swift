import SwiftUI
import UsageMonitorCore

struct AntigravityConnectionView: View {
    @ObservedObject var google: AntigravityModel
    @ObservedObject var preferences: DetailPreferences = .shared
    @State private var address: String
    @State private var key = ""
    @State private var expanded = false

    init(google: AntigravityModel, preferences: DetailPreferences = .shared) {
        self.google = google
        self.preferences = preferences
        _address = State(initialValue: google.baseURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Google / Antigravity").font(.headline)
                Spacer()
                Button(expanded ? "收起" : "连接或管理") { expanded.toggle() }
            }
            Text(google.feedback).font(.system(size: 11)).foregroundStyle(.secondary)
            if expanded {
                TextField("本机代理地址", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Antigravity 本机代理地址")
                SecureField("管理密钥", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Antigravity 管理密钥")
                HStack {
                    Button("保存并连接") {
                        if google.connect(baseURL: address, key: key) {
                            key = ""
                            preferences.showGoogle = true
                        }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("授权读取 / 刷新") { google.refresh(force: true) }
                    Spacer()
                    Button("断开连接") { google.disconnect(); key = "" }
                }
                Text("使用 8317 管理面板的管理密钥。Google 登录和账号启停在代理面板中管理。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(google.accounts) { state in
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("账号显示名称", text: Binding(
                            get: { google.names[state.id] ?? state.account.label },
                            set: { google.setName($0, accountID: state.id) }))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Google 账号显示名称")
                        Text(state.statusText).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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

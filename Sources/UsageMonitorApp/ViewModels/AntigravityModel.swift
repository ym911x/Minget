import Foundation
import Combine
import UsageMonitorCore

public struct AntigravityAccountState: Identifiable, Equatable {
    public let account: AntigravityAccount
    public var snapshot: AntigravitySnapshot?
    public var isCached = true
    public var isFetching = false
    public var failure: ProviderFailure?
    public var id: String { account.id }
    public var hasCachedData: Bool { isCached && snapshot != nil }
    public var statusText: String {
        if account.disabled { return "账号已停用" }
        if isFetching { return snapshot == nil ? "正在读取额度…" : "正在刷新，显示上次数据" }
        if let failure { return (snapshot == nil ? "" : "缓存 · ") + failure.displayText }
        if snapshot == nil { return "额度暂不可用" }
        return isCached ? "缓存 · 上次额度" : "额度已更新"
    }
}

/// Official CLI connections. Each UUID owns its task, cache and authentication failure.
@MainActor
public final class AntigravityModel: ObservableObject {
    @Published public private(set) var accounts: [AntigravityAccountState] = []
    @Published public private(set) var connections: [AntigravityConnection] = []
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var feedback = "请登录 Google 账号"
    @Published public private(set) var names: [String: String]
    @Published public private(set) var activeLoginSlot: AntigravitySlot?
    @Published public private(set) var isPreparingCLI = false
    let store: AntigravityProfileStore
    let registry: AccountRegistry?
    private let reader: AntigravityUsageReading
    private let defaults: UserDefaults
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var pending = Set<UUID>()
    private var attempts: [UUID: Date] = [:]
    private var suspended = Set<UUID>()
    private var retryUntil: [UUID: Date] = [:]
    private var stopped = false
    private var epoch = UUID()
    private var loginWindow: AntigravityLoginWindowController?
    private var installTask: Task<Void, Never>?
    private struct Entry: Codable { let uuid: UUID; let email: String; let snapshot: AntigravitySnapshot }
    private static let cacheKey = "antigravity.cli.snapshots.v1"
    private static let namesKey = "antigravity.cli.names.v1"

    public init(credentials: ProviderCredentialStoring = KeychainCredentialStore(), defaults: UserDefaults = .standard,
                store: AntigravityProfileStore = AntigravityProfileStore(),
                reader: AntigravityUsageReading = AntigravityUsageService(), registry: AccountRegistry? = nil, migrateLegacy: Bool = true) {
        self.registry = registry
        self.store = store; self.reader = reader; self.defaults = defaults
        names = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        if migrateLegacy {
            // Delete only our obsolete proxy key; never read its value or touch CPA.
            do {
                try credentials.delete(.antigravityManagementKey)
                for key in ["antigravity.baseURL.v1", "antigravity.connection.v1", "antigravity.snapshots.v1"] {
                    defaults.removeObject(forKey: key)
                }
            } catch { feedback = "旧代理密钥清理失败，下次启动重试；可继续登录 Google" }
        }
        reloadConnections()
        if feedback == "请登录 Google 账号", !connections.isEmpty { feedback = "Google 账号已连接" }
        if let data = defaults.data(forKey: Self.cacheKey), let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            for index in accounts.indices {
                guard let connection = connections.first(where: { $0.email == accounts[index].id }),
                      let entry = entries.first(where: { $0.uuid == connection.uuid && $0.email == connection.email }),
                      entry.snapshot.accountIdentity == connection.account.identity else { continue }
                accounts[index].snapshot = entry.snapshot
            }
        }
    }
    public func displayName(_ account: AntigravityAccount) -> String {
        registry?.accounts.first { $0.googleEmail == account.email }?.name ?? names[account.id] ?? account.label
    }
    public var slots: [AntigravitySlot] {
        if let registry { return registry.accounts.filter { $0.platform == .google }.compactMap { $0.googleSlot.map(AntigravitySlot.init(rawValue:)) } }
        return connections.isEmpty ? AntigravitySlot.allCases : Array(Set(connections.map(\.slot) + AntigravitySlot.allCases)).sorted { $0.rawValue < $1.rawValue }
    }
    var pendingAccount: ManagedAccount?
    public var onAccountsChanged: (() -> Void)?
    func addAccount(_ row: ManagedAccount) { pendingAccount = row; store.pendingAccount = row; login(.init(rawValue: row.googleSlot!)) }

    public func setName(_ name: String, accountID: String) {
        let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if value.isEmpty { names.removeValue(forKey: accountID) } else { names[accountID] = value }
        defaults.set(names, forKey: Self.namesKey)
        if let registry, var row = registry.accounts.first(where: { $0.googleEmail == accountID }) {
            row.name = value.isEmpty ? "Google 账号 \(row.ordinal)" : value; try? registry.upsert(row)
        }
    }
    public func connection(for slot: AntigravitySlot) -> AntigravityConnection? { connections.first { $0.slot == slot } }
    public func loginStatus(for slot: AntigravitySlot) -> String {
        guard let connection = connection(for: slot) else { return "未登录" }
        return suspended.contains(connection.uuid) ? "授权失效，请重新登录" : "已登录：" + connection.email
    }
    public func prepareCLI() {
        guard installTask == nil else { return }
        isPreparingCLI = true; feedback = "正在从 Google 官方准备 CLI…"
        installTask = Task { [weak self] in
            guard let self else { return }
            do { try await AntigravityCLIInstaller.install(); feedback = "官方 CLI 已准备，可以登录账号" }
            catch { feedback = "官方 CLI 准备失败，请检查网络、磁盘或签名兼容性" }
            isPreparingCLI = false; installTask = nil
        }
    }
    public func login(_ slot: AntigravitySlot) {
        guard activeLoginSlot == nil else { loginWindow?.present(); return }
        do { try AntigravityCLILocator.validate() }
        catch { feedback = "请先点击准备官方 CLI"; return }
        activeLoginSlot = slot
        loginWindow = AntigravityLoginWindowController(slot: slot, store: store, completion: { [weak self] connection in
            guard let self else { return }
            self.didLogin(connection); self.feedback = "登录成功，正在读取额度"
            DetailPreferences.shared.showGoogle = true
            self.refresh(force: true)
        }, onClose: { [weak self] in self?.activeLoginSlot = nil; self?.loginWindow = nil; self?.pendingAccount = nil; self?.store.pendingAccount = nil })
        loginWindow?.present()
    }
    func didLogin(_ connection: AntigravityConnection) {
        if var row = pendingAccount, row.googleSlot == connection.slot.rawValue {
            row.googleUUID = connection.uuid; row.googleEmail = connection.email; row.googleVersion = connection.sourceVersion
            do { try registry?.upsert(row); pendingAccount = nil; store.pendingAccount = nil } catch { feedback = "账号记录保存失败，请重试"; return }
        }
        let old = connections.first { $0.slot == connection.slot && $0.uuid != connection.uuid }
        let previous = old.flatMap { tasks[$0.uuid] }
        reloadConnections(); persist(); onAccountsChanged?()
        if names[connection.email] == nil, let legacy = defaults.dictionary(forKey: "antigravity.names.v1") as? [String: String],
           let name = legacy[connection.email] { setName(name, accountID: connection.email) }
        if let old {
            Task { [store] in
                await previous?.value
                try? store.removeProfile(old.uuid)
            }
        }
    }
    public func cancelLogin() { loginWindow?.close(); pendingAccount = nil; store.pendingAccount = nil }
    func removeConnection(_ connection: AntigravityConnection) async throws {
        if activeLoginSlot == connection.slot { cancelLogin() }
        let previous = tasks.removeValue(forKey: connection.uuid); previous?.cancel()
        pending.remove(connection.uuid); suspended.insert(connection.uuid)
        await previous?.value
        try store.disconnect(connection)
        names.removeValue(forKey: connection.email); defaults.set(names, forKey: Self.namesKey)
        reloadConnections(); persist(); onAccountsChanged?()
    }
    public func disconnect(_ slot: AntigravitySlot) {
        guard let connection = connection(for: slot) else { return }
        let previous = tasks.removeValue(forKey: connection.uuid)
        previous?.cancel(); pending.remove(connection.uuid)
        // Remove presentation immediately; delete CLI-owned files only after the reader joins.
        connections.removeAll { $0.uuid == connection.uuid }; accounts.removeAll { $0.id == connection.email }
        persist(); updateRefreshing()
        Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do { try store.disconnect(connection); reloadConnections(); persist(); feedback = "已移除本机账号"; onAccountsChanged?() }
            catch { reloadConnections(); feedback = "本机账号清理失败，请重试" }
        }
    }
    public func reloadConnections() {
        do {
            let stored = try store.connections()
            let next = registry == nil ? stored.sorted { $0.slot.rawValue < $1.slot.rawValue } : stored
            for old in connections where !next.contains(old) {
                tasks.removeValue(forKey: old.uuid)?.cancel(); pending.remove(old.uuid)
                attempts.removeValue(forKey: old.uuid); suspended.remove(old.uuid); retryUntil.removeValue(forKey: old.uuid)
            }
            accounts = next.map { connection in
                guard connections.contains(connection), let old = accounts.first(where: { $0.id == connection.email }) else {
                    return AntigravityAccountState(account: connection.account)
                }
                return old
            }
            connections = next; updateRefreshing()
        } catch { feedback = "本机账号记录无法读取，请检查目录权限" }
    }
    public func start() { stopped = false; refresh(force: false) }
    public func stop() {
        stopped = true; epoch = UUID(); tasks.values.forEach { $0.cancel() }; tasks = [:]; pending = []
        for index in accounts.indices { accounts[index].isFetching = false }
        cancelLogin(); installTask?.cancel(); updateRefreshing()
    }
    public func refresh(force: Bool, now: Date = Date(), afterWake: Bool = false) {
        guard !stopped else { return }
        for connection in connections where registry?.accounts.first(where: { $0.googleSlot == connection.slot.rawValue })?.removalPending != true {
            if tasks[connection.uuid] != nil { if force { pending.insert(connection.uuid) }; continue }
            if suspended.contains(connection.uuid) && !force { continue }
            if let until = retryUntil[connection.uuid], now < until { continue }
            if !force, !afterWake, let last = attempts[connection.uuid], now.timeIntervalSince(last) < 300 {
                let crossedReset = accounts.first(where: { $0.id == connection.email })?.snapshot?.groups
                    .flatMap(\.buckets).contains { bucket in
                        guard let reset = bucket.resetsAt else { return false }
                        return reset > last && reset <= now
                    } ?? false
                if !crossedReset { continue }
            }
            launch(connection, now: now)
        }
    }
    private func launch(_ connection: AntigravityConnection, now: Date) {
        let id = connection.uuid, currentEpoch = epoch
        attempts[id] = now
        if let index = accounts.firstIndex(where: { $0.id == connection.email }) { accounts[index].isFetching = true }
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            let result: Result<AntigravitySnapshot, Error>
            do { result = .success(try await reader.read(connection: connection, home: store.home(id))) }
            catch { result = .failure(error) }
            guard epoch == currentEpoch, !stopped, !Task.isCancelled, registry?.accounts.first(where: { $0.googleSlot == connection.slot.rawValue })?.removalPending != true, connections.contains(connection),
                  let index = accounts.firstIndex(where: { $0.id == connection.email }) else { return }
            accounts[index].isFetching = false
            switch result {
            case .success(let snapshot):
                if snapshot.accountIdentity == connection.account.identity {
                    accounts[index].snapshot = snapshot; accounts[index].failure = nil
                    accounts[index].isCached = false; suspended.remove(id); retryUntil.removeValue(forKey: id)
                } else { accounts[index].failure = .unexpectedResponse; accounts[index].isCached = true }
            case .failure(let error):
                let failure: ProviderFailure
                if let error = error as? AntigravityCLIProcess.Failure {
                    switch error {
                    case .authenticationRequired: failure = .invalidCredential
                    case .accountRegionUnavailable: failure = .accountRegionUnavailable
                    case .rateLimited(let retryAfter):
                        failure = .serverError(status: 429)
                        // No fabricated Retry-After: an absent duration uses the normal five-minute cadence.
                        if let retryAfter, retryAfter.isFinite, retryAfter > 0 { retryUntil[id] = Date().addingTimeInterval(retryAfter) }
                        pending.remove(id)
                    case .timedOut: failure = .timedOut
                    case .cancelled: failure = .cancelled
                    case .invalidReport, .outputTooLarge: failure = .structureUnsupported
                    default: failure = .other
                    }
                } else { failure = error as? ProviderFailure ?? .other }
                accounts[index].failure = failure; accounts[index].isCached = true
                if failure.isAuthenticationFailure { suspended.insert(id) }
            }
            persist(); tasks[id] = nil; updateRefreshing()
            if pending.remove(id) != nil && !suspended.contains(id) && registry?.accounts.first(where: { $0.googleSlot == connection.slot.rawValue })?.removalPending != true { launch(connection, now: Date()) }
        }
        updateRefreshing()
    }
    private func updateRefreshing() { isRefreshing = !tasks.isEmpty }
    private func persist() {
        let entries = connections.compactMap { connection -> Entry? in
            guard let snapshot = accounts.first(where: { $0.id == connection.email })?.snapshot else { return nil }
            return Entry(uuid: connection.uuid, email: connection.email, snapshot: snapshot)
        }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.cacheKey) }
    }
}

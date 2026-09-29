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
    public var statusText: String {
        if account.disabled { return "账号已在代理中停用" }
        if isFetching { return snapshot == nil ? "正在读取额度…" : "正在刷新，显示上次数据" }
        if let failure { return (snapshot == nil ? "" : "缓存 · ") + failure.displayText }
        if snapshot == nil { return "额度暂不可用" }
        return isCached ? "缓存 · 上次额度" : "额度已更新"
    }
}

/// All requests share one discovery cycle and publish each account as soon as it finishes.
/// A connection generation prevents replaced keys/accounts from publishing late results.
@MainActor
public final class AntigravityModel: ObservableObject {
    @Published public private(set) var accounts: [AntigravityAccountState] = []
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var feedback = "未连接本机代理"
    @Published public private(set) var baseURL: String
    @Published public private(set) var names: [String: String]
    private let defaults: UserDefaults
    private let access: CredentialAccessCoordinator
    private let reader: AntigravityReading
    private var generation = UUID()
    private var namespace: String
    private var task: Task<Void, Never>?
    private var pendingManual = false
    private var stopped = false
    private var authSuspended = false
    private var lastAttempt: Date?

    private enum Key {
        static let base = "antigravity.baseURL.v1"
        static let namespace = "antigravity.connection.v1"
        static let cache = "antigravity.snapshots.v1"
        static let names = "antigravity.names.v1"
    }
    private struct CacheEntry: Codable {
        let namespace: String
        let account: AntigravityAccount
        let snapshot: AntigravitySnapshot
    }

    public init(reader: AntigravityReading = AntigravityProvider(),
                credentials: ProviderCredentialStoring = KeychainCredentialStore(),
                defaults: UserDefaults = .standard) {
        self.reader = reader
        self.defaults = defaults
        access = CredentialAccessCoordinator(store: credentials)
        baseURL = defaults.string(forKey: Key.base) ?? AntigravityProvider.defaultBaseURL
        namespace = defaults.string(forKey: Key.namespace) ?? UUID().uuidString
        names = defaults.dictionary(forKey: Key.names) as? [String: String] ?? [:]
        if let data = defaults.data(forKey: Key.cache),
           let entries = try? JSONDecoder().decode([CacheEntry].self, from: data) {
            accounts = entries.filter { $0.namespace == namespace && $0.snapshot.accountIdentity == $0.account.identity }
                .map { AntigravityAccountState(account: $0.account, snapshot: $0.snapshot) }
        }
    }

    public func displayName(_ account: AntigravityAccount) -> String {
        names[account.id] ?? account.label
    }
    public func setName(_ name: String, accountID: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if name.isEmpty { names.removeValue(forKey: accountID) } else { names[accountID] = name }
        defaults.set(names, forKey: Key.names)
    }

    @discardableResult
    public func connect(baseURL: String, key: String) -> Bool {
        do {
            let url = try AntigravityProvider.validatedBaseURL(baseURL)
            let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !key.contains("\r"), !key.contains("\n") else {
                feedback = "请输入有效管理密钥"; return false
            }
            try access.store(key, for: .antigravityManagementKey)
            invalidate()
            self.baseURL = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            namespace = UUID().uuidString
            defaults.set(self.baseURL, forKey: Key.base)
            defaults.set(namespace, forKey: Key.namespace)
            feedback = "管理密钥已保存，正在发现账号…"
            refresh(force: true)
            return true
        } catch {
            feedback = "连接未保存，请检查本机地址和钥匙串权限"
            return false
        }
    }

    public func disconnect() {
        do {
            try access.remove(.antigravityManagementKey)
            invalidate()
            namespace = UUID().uuidString
            defaults.set(namespace, forKey: Key.namespace)
            feedback = "已断开本应用连接"
        } catch { feedback = "无法删除钥匙串密钥，连接尚未断开" }
    }

    private func invalidate() {
        generation = UUID()
        task?.cancel(); task = nil
        pendingManual = false; isRefreshing = false
        accounts = []; authSuspended = false; lastAttempt = nil
        defaults.removeObject(forKey: Key.cache)
    }

    public func start() { stopped = false; refresh(force: false) }
    public func stop() {
        stopped = true; generation = UUID(); task?.cancel(); task = nil
        pendingManual = false; isRefreshing = false
    }
    public func refresh(force: Bool, now: Date = Date(), afterWake: Bool = false) {
        guard !stopped else { return }
        if task != nil { if force { pendingManual = true }; return }
        if !force {
            guard !authSuspended else { return }
            if !afterWake, let lastAttempt, now.timeIntervalSince(lastAttempt) >= 0,
               now.timeIntervalSince(lastAttempt) < 300 { return }
        }
        let current = generation
        lastAttempt = now
        isRefreshing = true
        let base = baseURL
        task = Task { [weak self] in
            guard let self else { return }
            let outcome = await access.value(for: .antigravityManagementKey,
                                             purpose: force ? .userRequestedRead : .providerRead,
                                             interaction: force ? .allowed : .disallowed)
            guard current == generation, !stopped else { return }
            guard let key = outcome.secret else {
                let failure: ProviderFailure = outcome.isMissing ? .notConfigured : .credentialAccessBlocked
                if outcome.isMissing { accounts = []; defaults.removeObject(forKey: Key.cache) }
                else { markFailure(failure) }
                feedback = failure.displayText
                finish(current: current)
                return
            }
            do {
                let discovered = try await reader.accounts(baseURL: base, managementKey: key)
                guard current == generation, !stopped else { return }
                accounts = discovered.map { account in
                    let old = self.accounts.first { $0.account.identity == account.identity }
                    return AntigravityAccountState(account: account, snapshot: old?.snapshot,
                        isCached: true, isFetching: !account.disabled,
                        failure: account.disabled ? .suspended : nil)
                }
                // Successful discovery removes deleted/replaced accounts before any quota request.
                persist()
                authSuspended = false
                feedback = discovered.isEmpty ? "本机代理没有 Antigravity 账号" : "已发现 \(discovered.count) 个 Google 账号"
                await withTaskGroup(of: (String, Result<AntigravitySnapshot, ProviderFailure>).self) { group in
                    for account in discovered where !account.disabled {
                        let reader = self.reader
                        group.addTask {
                            do { return (account.identity, .success(try await reader.quota(account: account, baseURL: base, managementKey: key))) }
                            catch { return (account.identity, .failure((error as? ProviderFailure) ?? (error is CancellationError ? .cancelled : .other))) }
                        }
                    }
                    for await (identity, result) in group {
                        guard current == self.generation, !self.stopped,
                              let index = self.accounts.firstIndex(where: { $0.account.identity == identity }) else { continue }
                        self.accounts[index].isFetching = false
                        switch result {
                        case .success(let snapshot):
                            guard snapshot.accountIdentity == identity else {
                                self.accounts[index].failure = .unexpectedResponse; continue
                            }
                            self.accounts[index].snapshot = snapshot
                            self.accounts[index].isCached = false
                            self.accounts[index].failure = nil
                        case .failure(let error):
                            self.accounts[index].isCached = true
                            self.accounts[index].failure = error
                        }
                        self.persist()
                    }
                }
            } catch {
                guard current == generation, !stopped else { return }
                let error = (error as? ProviderFailure) ?? .other
                authSuspended = error.isAuthenticationFailure
                markFailure(error)
                feedback = error.displayText
            }
            finish(current: current)
        }
    }

    private func markFailure(_ failure: ProviderFailure) {
        for index in accounts.indices {
            accounts[index].isCached = true
            accounts[index].isFetching = false
            accounts[index].failure = failure
        }
    }
    private func finish(current: UUID) {
        guard generation == current else { return }
        task = nil; isRefreshing = false
        if pendingManual { pendingManual = false; refresh(force: true) }
    }
    private func persist() {
        let entries = accounts.compactMap { state -> CacheEntry? in
            guard let snapshot = state.snapshot else { return nil }
            return CacheEntry(namespace: namespace, account: state.account, snapshot: snapshot)
        }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Key.cache) }
    }
}

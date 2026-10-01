import AppKit
import Foundation
import UsageMonitorCore

struct APIAccountState: Identifiable {
    let account: ManagedAccount
    let report: ProviderReport
    var id: String { account.id }
}

final class APIAccountRuntime {
    let id: String
    let platform: ProviderPlatform
    let engine: ProviderRefreshEngine
    let fireService: CommandCodeFireService
    init(account: ManagedAccount, credentials: ProviderCredentialStoring, transport: ProviderTransport,
         defaults: UserDefaults = .standard, legacyEngine: ProviderRefreshEngine? = nil,
         fireService: CommandCodeFireService = CommandCodeFireService()) {
        id = account.id; platform = account.platform.apiPlatform!; self.fireService = fireService
        if let legacyEngine {
            engine = legacyEngine
            if let fingerprint = account.keyFingerprint { engine.restoreCachedAccount(platform: platform, accountID: fingerprint) }
            return
        }
        let key = ProviderCredentialKey(rawValue: account.credentialAccount!)
        let reader: ProviderReading = platform == .deepseek
            ? DeepSeekReading(provider: DeepSeekProvider(transport: transport), credentials: credentials, credentialKey: key)
            : CommandCodeReading(provider: CommandCodeProvider(transport: transport), credentials: credentials, credentialKey: key)
        engine = ProviderRefreshEngine(readers: [reader], cache: ProviderCache(userDefaults: defaults, namespace: id))
        if let fingerprint = account.keyFingerprint { engine.restoreCachedAccount(platform: platform, accountID: fingerprint) }
    }
}

extension UsageViewModel {
    func installAccountManagement(registry: AccountRegistry, credentials: ProviderCredentialStoring,
                                  transport: ProviderTransport, defaults: UserDefaults = .standard) {
        accountDefaults = defaults
        accountRegistry = registry; accountCredentials = credentials; accountTransport = transport
        for account in registry.accounts where account.platform.apiPlatform != nil {
            let legacy = account.id == "deepseek" || account.id == "commandcode"
            apiRuntimes[account.id] = APIAccountRuntime(account: account, credentials: credentials, transport: transport,
                defaults: defaults, legacyEngine: legacy ? providerEngine : nil,
                fireService: account.id == "commandcode" ? commandCodeFireService : CommandCodeFireService())
        }
        google.onAccountsChanged = { [weak self] in self?.reloadManagedAccounts() }
        reloadManagedAccounts()
    }
    func reloadManagedAccounts() {
        guard let registry = accountRegistry else { return }
        managedAccounts = registry.accounts
        for row in managedAccounts { displayNames.register(row.id, defaultName: row.name) }
        publishManagedAPIStates(); publishProfileStates(); tick += 1
    }
    func accountName(_ row: ManagedAccount) -> String { displayNames.displayName(for: row.id) }
    var scheduleTargets: [FireScheduleTarget] {
        if accountRegistry == nil { return FireScheduleTarget.allCases }
        return managedAccounts.filter { !$0.removalPending && ($0.platform == .chatGPT || $0.platform == .commandcode) }
            .map { .init(rawValue: $0.id) }
    }
    func publishManagedAPIStates() {
        managedAPIStates = managedAccounts.compactMap { account in
            guard let runtime = apiRuntimes[account.id] else { return nil }
            return APIAccountState(account: account, report: runtime.engine.report(for: runtime.platform))
        }
        providerReports = managedAPIStates.map(\.report)
        for state in managedAPIStates where state.report.connection == .connected && state.report.accountID != nil && state.account.keyFingerprint != state.report.accountID {
            var row = state.account; row.keyFingerprint = state.report.accountID; try? accountRegistry?.upsert(row)
        }
    }
    func primeManagedCredentials() {
        guard accountRegistry != nil else { return }
        for runtime in apiRuntimes.values where accountRegistry?.account(runtime.id)?.removalPending == false {
            Task { [weak self] in
                await runtime.engine.primeCredentials(); self?.publishManagedAPIStates()
                self?.refreshManagedAPI(id: runtime.id, force: false)
            }
        }
    }
    func refreshManagedAPIs(force: Bool) {
        for row in managedAccounts where row.platform.apiPlatform != nil && !row.removalPending {
            refreshManagedAPI(id: row.id, force: force)
        }
    }
    func refreshManagedAPI(id: String, force: Bool) {
        guard !isStopped, accountRegistry?.account(id)?.removalPending == false, let runtime = apiRuntimes[id] else { return }
        // Engine single-flight and credential generations continue to own request coalescing.
        isProviderRefreshing = true
        managedAPITasks[id] = Task { [weak self] in
            _ = await runtime.engine.refresh(platform: runtime.platform, force: force)
            guard !Task.isCancelled, let self, self.accountRegistry?.account(id)?.removalPending == false else { return }
            self.managedAPITasks[id] = nil; self.finishProviderRefresh()
        }
    }
    func saveManagedAPI(_ input: ManagedAccount, key: String) -> Bool {
        var draft = input
        guard !input.removalPending else { accountMessage = "该账号正在移除，请先完成清理"; return false }
        guard let registry = accountRegistry, let credentials = accountCredentials, let transport = accountTransport,
              let platform = draft.platform.apiPlatform else { accountMessage = "账号管理尚未准备完成"; return false }
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { accountMessage = "请输入 API Key"; return false }
        let fingerprint = platform == .deepseek ? DeepSeekProvider.accountFingerprint(forAPIKey: secret) : CommandCodeProvider.accountFingerprint(forAPIKey: secret)
        if registry.accounts.contains(where: { $0.id != draft.id && $0.platform == draft.platform && $0.keyFingerprint == fingerprint }) || managedAPIStates.contains(where: { $0.id != draft.id && $0.report.platform == platform && $0.report.accountID == fingerprint }) {
            accountMessage = "这个连接已添加，请管理已有账号"; return false
        }
        draft.keyFingerprint = fingerprint
        do { try registry.validateForUpsert(draft) }
        catch { accountMessage = "账号名称或连接记录无效，请检查后重试"; return false }
        let runtime = apiRuntimes[draft.id] ?? APIAccountRuntime(account: draft, credentials: credentials, transport: transport, defaults: accountDefaults)
        do {
            if let reader = runtime.engine.reading(for: platform) as? DeepSeekReading { try reader.storeAPIKey(secret) }
            else if let reader = runtime.engine.reading(for: platform) as? CommandCodeReading { try reader.storeAPIKey(secret) }
            else { throw AccountRegistry.Failure.invalidMetadata }
            try registry.upsert(draft)
        } catch { accountMessage = "保存失败，请检查本机钥匙串后重试"; return false }
        runtime.engine.invalidateAttribution(platform: platform)
        apiRuntimes[draft.id] = runtime; accountMessage = "已保存，正在读取额度"; reloadManagedAccounts()
        Task { [weak self] in
            _ = await runtime.engine.connectAfterCredentialChange(platform: platform)
            guard let self, self.accountRegistry?.account(draft.id)?.removalPending == false else { return }
            self.finishProviderRefresh()
        }
        return true
    }
    func beginAddAccount(_ platform: AccountPlatform, name: String) {
        guard let registry = accountRegistry, !isStopped else { return }
        let draft = registry.draft(platform, name: name)
        switch platform {
        case .chatGPT:
            guard activeLoginProfile == nil else { accountMessage = "请先完成或取消当前登录"; return }
            pendingChatGPTAccount = draft; displayNames.register(draft.id, defaultName: draft.name)
            coordinator.add(draft.profile!); connectChatGPT(profileID: draft.id)
        case .google: google.addAccount(draft)
        case .deepseek, .commandcode: break
        }
    }
    func cancelPendingChatGPT() {
        guard let row = pendingChatGPTAccount else { return }
        pendingChatGPTAccount = nil
        let runtime = coordinator.detach(row.id); displayNames.unregister(row.id)
        Task.detached { try? runtime?.service.logoutManagedAccount(); runtime?.service.stop() }
        publishProfileStates()
    }
    func completePendingChatGPT(profileID: String) {
        guard let row = pendingChatGPTAccount, row.id == profileID else { return }
        let identity: String?
        if case .confirmed(let account) = coordinator.runtime(for: row.id)?.state().identity { identity = account.cacheAccountID?.lowercased() }
        else { identity = nil }
        if let identity, coordinator.runtimes.contains(where: { $0.profileID != row.id && $0.state().account?.cacheAccountID?.lowercased() == identity }) {
            accountMessage = "这个 ChatGPT 账号已添加，请选择其他账号"
            let runtime = coordinator.detach(row.id); pendingChatGPTAccount = nil
            Task.detached { try? runtime?.service.logoutManagedAccount() }; return
        }
        do { try accountRegistry?.upsert(row); pendingChatGPTAccount = nil; accountMessage = "账号已添加"; reloadManagedAccounts() }
        catch { accountMessage = "账号记录保存失败，请重试" }
    }
    func renameManagedAccount(_ id: String, name: String) -> Bool {
        guard let registry = accountRegistry, var row = registry.account(id) else { return false }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 40 else { return false }
        row.name = value.isEmpty ? row.platform.title + " 账号 \(row.ordinal)" : value
        do { try registry.upsert(row); displayNames.resetDisplayName(for: id); reloadManagedAccounts(); google.objectWillChange.send(); return true }
        catch { accountMessage = "名称无法保存"; return false }
    }
    func removeManagedAccount(_ id: String) {
        guard let registry = accountRegistry, var row = registry.account(id) else { return }
        row.removalPending = true
        do { try registry.upsert(row) } catch { accountMessage = "无法保存移除状态，请重试"; return }
        fireSchedules.disableAccount(id)
        if activeLoginProfile == id { cancelChatGPTLogin() }
        fireTasks[id]?.cancel(); managedAPITasks[id]?.cancel()
        let runtime = apiRuntimes[id]
        runtime?.engine.invalidateAttribution(platform: runtime!.platform)
        let codex = coordinator.detach(id) ?? removedChatGPTRuntimes[id]
        if let codex { removedChatGPTRuntimes[id] = codex }
        reloadManagedAccounts(); accountMessage = "正在移除本机连接…"
        let fire = fireService
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    if let codex { fire.stop(profileID: id); try codex.service.logoutManagedAccount() }
                    if let runtime { runtime.fireService.stop(); if runtime.engine.disconnect(platform: runtime.platform) != nil { throw AccountRegistry.Failure.invalidMetadata } }
                }.value
                guard let self else { return }
                if row.platform == .google, let slot = row.googleSlot,
                   let connection = self.google.connection(for: .init(rawValue: slot)) {
                    try await self.google.removeConnection(connection)
                }
                try registry.remove(id); self.fireSchedules.removeAccount(id)
                self.apiRuntimes.removeValue(forKey: id); self.removedChatGPTRuntimes.removeValue(forKey: id)
                self.additionalFireStates.removeValue(forKey: id); self.displayNames.unregister(id)
                self.accountMessage = "账号已移除"; self.reloadManagedAccounts()
            } catch { self?.accountMessage = "移除未完成，连接已停用，请重试"; self?.reloadManagedAccounts() }
        }
    }
    func resumePendingRemovals() {
        for row in managedAccounts where row.removalPending { removeManagedAccount(row.id) }
    }
    func managedCommandFireState(_ id: String) -> CommandCodeFireViewState {
        additionalFireStates[id] ?? (id == "commandcode" ? commandCodeFireState : CommandCodeFireViewState())
    }
    @discardableResult func fireManagedCommandCode(id: String, userInitiated: Bool = true) -> Bool {
        if accountRegistry == nil { return id == "commandcode" ? fireCommandCode(userInitiated: userInitiated) : false }
        guard !isStopped, accountRegistry?.account(id)?.removalPending == false,
              !additionalFireStates.values.contains(where: \.isFiring), !commandCodeFireState.isFiring,
              let runtime = apiRuntimes[id], let reader = runtime.engine.reading(for: .commandcode) as? CommandCodeReading else { return false }
        let report = runtime.engine.report(for: .commandcode)
        let previous = report.usage?.windows.first { $0.kind == .fiveHour }?.resetsAt
        additionalFireStates[id, default: .init()].start()
        fireTasks[id] = Task { [weak self] in
            let outcome = await reader.fireCredential(userInitiated: userInitiated)
            guard !Task.isCancelled, let self, self.accountRegistry?.account(id)?.removalPending == false else { return }
            guard let secret = outcome.secret else { self.finishManagedCommandFire(id, result: .credentialUnavailable); return }
            let result = await Task.detached { runtime.fireService.fire(apiKey: secret) }.value
            guard !Task.isCancelled, self.accountRegistry?.account(id)?.removalPending == false else { return }
            if let immediate = result.immediateResult { self.finishManagedCommandFire(id, result: immediate); return }
            var observations: [FireWindowConfirmation.Observation] = []
            for delay in [self.fireConfirmDelay, self.fireRetryDelay] {
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
                guard self.accountRegistry?.account(id)?.removalPending == false else { return }
                if let reset = try? await reader.fiveHourResetForFire(userInitiated: userInitiated) { observations.append(.live(resetsAt: reset)) }
                else { observations.append(.noEvidence) }
                if report.connection == .connected, case .live(let reset) = observations.last!, FireWindowConfirmation.observesAdvancedReset(live: reset, previous: previous) { break }
            }
            let classification = FireWindowConfirmation.classify(previousReset: previous, previousWasLive: report.connection == .connected, observations: observations)
            self.additionalFireStates[id, default: .init()].finish(classification, driftSeconds: Self.fireDrift(result: classification, previous: previous, observations: observations))
            self.fireTasks[id] = nil; self.tick += 1; self.refreshManagedAPI(id: id, force: false)
        }
        return true
    }
    private func finishManagedCommandFire(_ id: String, result: ChatGPTFireResult) {
        guard accountRegistry?.account(id)?.removalPending == false else { return }
        additionalFireStates[id, default: .init()].finish(result, driftSeconds: nil); fireTasks[id] = nil; tick += 1
    }
}

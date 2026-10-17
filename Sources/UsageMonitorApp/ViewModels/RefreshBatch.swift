import Foundation
import UsageMonitorCore

/// One account a page's refresh batch can read: the four kinds of account the app holds.
///
/// The menu bar source and the page batches are expressed in these keys, so the two can be
/// compared without either side knowing how the other is stored.
enum RefreshTarget: Hashable {
    case chatGPTProfile(String)
    case googleAccount(String)
    case apiAccount(String)
    /// The single-connection (no registry) mode, where the platform itself is the account.
    case providerPlatform(ProviderPlatform)

    var chatGPTProfileID: String? {
        if case .chatGPTProfile(let id) = self { return id }
        return nil
    }

    var googleAccountID: String? {
        if case .googleAccount(let id) = self { return id }
        return nil
    }

    /// True when a read of this account is only meaningful once the credential pass has
    /// settled: the API connections. The launch read happens after priming for these, and
    /// immediately for the others.
    var isCredentialGated: Bool {
        switch self {
        case .providerPlatform, .apiAccount: return true
        case .chatGPTProfile, .googleAccount: return false
        }
    }
}

/// Every account the current launch can read, grouped the way the pages present them.
struct RefreshInventory: Equatable {
    var chatGPTProfileIDs: [String] = []
    var googleAccountIDs: [String] = []
    var managedDeepSeekIDs: [String] = []
    var managedCommandCodeIDs: [String] = []
    /// Registry-less mode: the platform connection itself is the account, and only a
    /// configured credential makes it worth reading.
    var legacyDeepSeek = false
    var legacyCommandCode = false

    var chatGPTTargets: [RefreshTarget] { chatGPTProfileIDs.map(RefreshTarget.chatGPTProfile) }
    var googleTargets: [RefreshTarget] { googleAccountIDs.map(RefreshTarget.googleAccount) }
    var deepSeekTargets: [RefreshTarget] {
        managedDeepSeekIDs.map(RefreshTarget.apiAccount)
            + (legacyDeepSeek ? [.providerPlatform(.deepseek)] : [])
    }
    var commandCodeTargets: [RefreshTarget] {
        managedCommandCodeIDs.map(RefreshTarget.apiAccount)
            + (legacyCommandCode ? [.providerPlatform(.commandcode)] : [])
    }
    var allTargets: [RefreshTarget] { chatGPTTargets + googleTargets + deepSeekTargets + commandCodeTargets }
}

/// Which page a batch belongs to. Named for the page rather than the tab enum so the rule
/// can be tested without the preferences object.
enum RefreshBatchScope: Equatable {
    case overview
    case chatGPT
    case google
    case deepSeek
    case commandCode

    init(tab: DetailPreferences.ProviderTab) {
        switch tab {
        case .all: self = .overview
        case .chatGPT: self = .chatGPT
        case .google: self = .google
        case .deepSeek: self = .deepSeek
        case .commandCode: self = .commandCode
        }
    }

    /// The overview and the DeepSeek page both show the DeepSeek card, which carries the
    /// public status line.
    var showsDeepSeekStatus: Bool { self == .overview || self == .deepSeek }
}

/// When a read was last started for each account, memory only.
///
/// Lock-guarded rather than main-actor state on purpose: a fetch task records its own
/// attempt the moment it dispatches, so a busy main thread can never delay or block a read.
/// Only the attempt time is kept; no credential, cache or provider value passes through here.
final class RefreshAttemptLedger: @unchecked Sendable {

    private let lock = NSLock()
    private var attempts: [RefreshTarget: Date] = [:]

    func record(_ target: RefreshTarget, at date: Date = Date()) {
        lock.lock(); attempts[target] = date; lock.unlock()
    }

    /// The attempt time of one account, or nil when it has never been read.
    func lastAttempt(for target: RefreshTarget) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return attempts[target]
    }
}

/// The 1.6.9 refresh-scope rules as pure functions: what one page reads, and when it may
/// read it again without a manual refresh.
///
/// The menu bar displays exactly one source. That source is the only account refreshed on
/// its own schedule; every other account is read once when a page shows it, and only after
/// the batch age has passed since the page's accounts were last attempted.
enum RefreshBatchPolicy {

    /// A page's batch is skipped while every member was already attempted within this age.
    static let batchAge: TimeInterval = 5 * 60

    /// The account the menu bar displays. It is never part of a page's batch: its own loop,
    /// the manual paths and the fire confirmation own it.
    static func menuBarTarget(selection: MenuBarPreferences.Selection,
                              isRegistryMode: Bool) -> RefreshTarget {
        switch selection {
        case .profile(let id): return .chatGPTProfile(id)
        case .google(let email): return .googleAccount(email)
        case .apiAccount(let id): return .apiAccount(id)
        // The registry keeps the legacy DeepSeek connection under this fixed id, which is
        // the same id the menu bar's own refresh path uses.
        case .deepSeek: return isRegistryMode ? .apiAccount("deepseek") : .providerPlatform(.deepseek)
        }
    }

    /// The members of one page's batch: the page's accounts minus the menu bar source.
    static func members(scope: RefreshBatchScope,
                        selection: MenuBarPreferences.Selection,
                        inventory: RefreshInventory,
                        isRegistryMode: Bool) -> [RefreshTarget] {
        let displayed = menuBarTarget(selection: selection, isRegistryMode: isRegistryMode)
        let candidates: [RefreshTarget]
        switch scope {
        case .overview: candidates = inventory.allTargets
        case .chatGPT: candidates = inventory.chatGPTTargets
        case .google: candidates = inventory.googleTargets
        case .deepSeek: candidates = inventory.deepSeekTargets
        case .commandCode: candidates = inventory.commandCodeTargets
        }
        return candidates.filter { $0 != displayed }
    }

    /// True when at least one member needs a read: an account with no recorded attempt has
    /// never been read, so the batch runs. The decision is whole-batch by design, so a
    /// partially stale page reads all of its members together.
    static func needsRefresh(_ members: [RefreshTarget],
                             attempts: [RefreshTarget: Date],
                             now: Date) -> Bool {
        members.contains { target in
            guard let attemptedAt = attempts[target] else { return true }
            let elapsed = now.timeIntervalSince(attemptedAt)
            return elapsed < 0 || elapsed >= batchAge
        }
    }
}

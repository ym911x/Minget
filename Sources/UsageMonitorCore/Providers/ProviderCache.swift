import Foundation

/// One provider-reported amount in persisted form.
public struct PersistedLabeledAmount: Codable, Equatable, Sendable {
    public var field: String
    public var label: String
    public var amount: String

    public init(field: String, label: String, amount: String) {
        self.field = field
        self.label = label
        self.amount = amount
    }

    public init(_ amount: ProviderLabeledAmount) {
        self.field = amount.field
        self.label = amount.label
        self.amount = amount.amount.description
    }

    public var labeledAmount: ProviderLabeledAmount? {
        guard let amount = SafeConversion.decimal(from: amount) else { return nil }
        return ProviderLabeledAmount(field: field, label: label, amount: amount)
    }
}

/// Persisted balance for one provider, one account. Amounts are stored as the exact
/// decimal text the provider reported, never as a float.
///
/// Extended backward-compatibly in Round 7: `currency` became optional (a response that
/// does not name a currency is stored as absent, never guessed), and `available` plus
/// `additionalAmounts` were added. Older entries without the new keys decode with nil
/// there, and a present String still decodes into the optional currency.
public struct PersistedBalance: Codable, Equatable, Sendable {
    public var currency: String?
    public var total: String?
    public var available: String?
    public var granted: String?
    public var toppedUp: String?
    public var additionalAmounts: [PersistedLabeledAmount]?

    public init(currency: String?,
                total: String?,
                available: String? = nil,
                granted: String?,
                toppedUp: String?,
                additionalAmounts: [PersistedLabeledAmount]? = nil) {
        self.currency = currency
        self.total = total
        self.available = available
        self.granted = granted
        self.toppedUp = toppedUp
        self.additionalAmounts = additionalAmounts
    }

    public init(_ balance: ProviderBalance) {
        self.currency = balance.currency
        self.total = balance.total.map { $0.description }
        self.available = balance.available.map { $0.description }
        self.granted = balance.granted.map { $0.description }
        self.toppedUp = balance.toppedUp.map { $0.description }
        self.additionalAmounts = balance.additionalAmounts.map { $0.map { PersistedLabeledAmount($0) } }
    }

    public var balance: ProviderBalance? {
        let total = total.flatMap { SafeConversion.decimal(from: $0) }
        let available = available.flatMap { SafeConversion.decimal(from: $0) }
        // At least one real amount must survive the round trip.
        guard total != nil || available != nil else { return nil }
        let extras = additionalAmounts?.compactMap { $0.labeledAmount }
        return ProviderBalance(currency: currency,
                               total: total,
                               available: available,
                               granted: granted.flatMap { SafeConversion.decimal(from: $0) },
                               toppedUp: toppedUp.flatMap { SafeConversion.decimal(from: $0) },
                               additionalAmounts: (extras?.isEmpty == false) ? extras : nil)
    }
}

/// One cache entry, bound to the account it belongs to.
public struct ProviderCacheEntry: Codable, Equatable, Sendable {
    public var accountID: String
    public var balances: [PersistedBalance]
    public var lastSuccessAt: Date

    public init(accountID: String, balances: [PersistedBalance], lastSuccessAt: Date) {
        self.accountID = accountID
        self.balances = balances
        self.lastSuccessAt = lastSuccessAt
    }

    public var providerBalances: [ProviderBalance] {
        return balances.compactMap { $0.balance }
    }
}

/// Business cache for provider balances.
///
/// Entries are keyed by platform *and* account, so two accounts on one platform never share
/// numbers, and an entry written before accounts were identified cannot be attributed to a
/// later one. Credentials are never stored here: this file is business data only, and the
/// credential lives in the keychain (v1.1 requirement 6).
public final class ProviderCache: @unchecked Sendable {

    /// Data older than this is refreshed when the panel opens.
    public static let maxAgeForPanelOpenRefresh: TimeInterval = 60

    private let userDefaults: UserDefaults
    private let storageKey = "UsageMonitor.providerBalances.v2"
    private let queue = DispatchQueue(label: "usagemonitor.provider-cache")

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func save(platform: ProviderPlatform, accountID: String, balances: [ProviderBalance], lastSuccessAt: Date) {
        guard !accountID.isEmpty else { return }
        queue.sync {
            var entries = loadEntries()
            entries[Self.key(platform: platform, accountID: accountID)] =
                ProviderCacheEntry(accountID: accountID,
                                   balances: balances.map { PersistedBalance($0) },
                                   lastSuccessAt: lastSuccessAt)
            saveEntries(entries)
        }
    }

    /// Returns the entry only when it belongs to `accountID`. A different account's entry,
    /// or an entry with no account attribution, is never returned.
    public func load(platform: ProviderPlatform, accountID: String) -> ProviderCacheEntry? {
        guard !accountID.isEmpty else { return nil }
        return queue.sync {
            loadEntries()[Self.key(platform: platform, accountID: accountID)]
        }
    }

    @discardableResult
    public func clear(platform: ProviderPlatform, accountID: String) -> Bool {
        return queue.sync {
            var entries = loadEntries()
            let removed = entries.removeValue(forKey: Self.key(platform: platform, accountID: accountID)) != nil
            if removed { saveEntries(entries) }
            return removed
        }
    }

    /// Removes every entry of one platform, whatever account it belonged to. Used when the
    /// user disconnects the platform: once the credential is gone, its cached numbers must
    /// not survive it (v1.1 requirement 5).
    public func clear(platform: ProviderPlatform) {
        queue.sync {
            let prefix = platform.rawValue + "#"
            var entries = loadEntries()
            guard entries.keys.contains(where: { $0.hasPrefix(prefix) }) else { return }
            entries = entries.filter { !$0.key.hasPrefix(prefix) }
            saveEntries(entries)
        }
    }

    public func clearAll() {
        queue.sync {
            userDefaults.removeObject(forKey: storageKey)
        }
    }

    /// Storage keys currently held. Diagnostics and tests only; it exposes identifiers,
    /// never credentials.
    public func allKeys() -> [String] {
        return queue.sync { Array(loadEntries().keys).sorted() }
    }

    // MARK: - Storage

    private struct Store: Codable {
        var entries: [String: ProviderCacheEntry]
    }

    private static func key(platform: ProviderPlatform, accountID: String) -> String {
        return "\(platform.rawValue)#\(accountID)"
    }

    private func loadEntries() -> [String: ProviderCacheEntry] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [:] }
        do {
            return try JSONDecoder().decode(Store.self, from: data).entries
        } catch {
            // Corrupt cache: drop it rather than surface garbage.
            userDefaults.removeObject(forKey: storageKey)
            return [:]
        }
    }

    private func saveEntries(_ entries: [String: ProviderCacheEntry]) {
        guard let data = try? JSONEncoder().encode(Store(entries: entries)) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

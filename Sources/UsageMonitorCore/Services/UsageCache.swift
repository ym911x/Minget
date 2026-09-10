import Foundation

/// Persists the most recent successful snapshot as normalized numbers only
/// (PROJECT_SPEC.md §11, §14: no auth payloads, no raw RPC responses).
///
/// v1.1 adds account attribution: an entry can be stored for a specific Codex account and
/// is only ever returned to that account. The pre-existing unattributed store is kept for
/// the no-account-known case and is deliberately never served when an account is known, so
/// a v1.0 cache can never be presented as the current account's data.
public final class UsageCache: @unchecked Sendable {
    public static let maxAgeForPanelOpenRefresh: TimeInterval = 30
    public static let stalenessWarnThreshold: TimeInterval = 10 * 60

    private let userDefaults: UserDefaults
    private let storageKey = "UsageMonitor.lastSnapshot.v1"
    private let accountStorageKey = "UsageMonitor.lastSnapshotByAccount.v2"
    private let accountIDKey = "UsageMonitor.lastAccountID.v2"
    private let queue = DispatchQueue(label: "usagemonitor.cache")

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public static func isStale(fetchedAt: Date, now: Date = Date(), maxAge: TimeInterval = UsageCache.maxAgeForPanelOpenRefresh) -> Bool {
        return now.timeIntervalSince(fetchedAt) > maxAge
    }

    // MARK: Unattributed store (v1.0 compatibility)

    public func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot.persisted) else { return }
        queue.sync {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    /// Returns the cached snapshot, or nil when absent/corrupt.
    /// The snapshot is always tagged `.cached` so the UI can never present it as live data.
    public func load() -> UsageSnapshot? {
        var result: UsageSnapshot?
        queue.sync {
            guard let data = userDefaults.data(forKey: storageKey) else { return }
            do {
                let persisted = try JSONDecoder().decode(UsageSnapshot.Persisted.self, from: data)
                result = UsageSnapshot.from(persisted: persisted)
            } catch {
                // Corrupt cache: drop it, never surface garbage as data.
                userDefaults.removeObject(forKey: storageKey)
                result = nil
            }
        }
        return result
    }

    public func clear() {
        queue.sync {
            userDefaults.removeObject(forKey: storageKey)
        }
    }

    // MARK: Account-scoped store (v1.1)

    /// Stores a snapshot for exactly one account.
    public func save(_ snapshot: UsageSnapshot, accountID: String) {
        guard !accountID.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(snapshot.persisted) else { return }
        queue.sync {
            var entries = loadAccountEntries()
            entries[accountID] = data
            if let encoded = try? JSONEncoder().encode(entries) {
                userDefaults.set(encoded, forKey: accountStorageKey)
            }
        }
    }

    /// Returns the snapshot stored for `accountID`, and only that account's. A nil or
    /// empty account identifier never resolves to anything.
    public func load(accountID: String?) -> UsageSnapshot? {
        guard let accountID, !accountID.isEmpty else { return nil }
        var result: UsageSnapshot?
        queue.sync {
            guard let data = loadAccountEntries()[accountID] else { return }
            do {
                let persisted = try JSONDecoder().decode(UsageSnapshot.Persisted.self, from: data)
                result = UsageSnapshot.from(persisted: persisted)
            } catch {
                removeAccountEntry(accountID)
                result = nil
            }
        }
        return result
    }

    @discardableResult
    public func clear(accountID: String) -> Bool {
        return queue.sync {
            var entries = loadAccountEntries()
            let removed = entries.removeValue(forKey: accountID) != nil
            if removed, let encoded = try? JSONEncoder().encode(entries) {
                userDefaults.set(encoded, forKey: accountStorageKey)
            }
            return removed
        }
    }

    private func loadAccountEntries() -> [String: Data] {
        guard let data = userDefaults.data(forKey: accountStorageKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: Data].self, from: data)
        } catch {
            userDefaults.removeObject(forKey: accountStorageKey)
            return [:]
        }
    }

    private func removeAccountEntry(_ accountID: String) {
        var entries = loadAccountEntries()
        entries.removeValue(forKey: accountID)
        if let encoded = try? JSONEncoder().encode(entries) {
            userDefaults.set(encoded, forKey: accountStorageKey)
        }
    }

    // MARK: Last known account

    /// Remembers which account produced the last successful read, so a subsequent failure
    /// (including one before the next `account/read` completes) can serve that account's
    /// own cache instead of nothing. An identifier, not a credential.
    public func saveLastKnownAccountID(_ accountID: String) {
        guard !accountID.isEmpty else { return }
        queue.sync {
            userDefaults.set(accountID, forKey: accountIDKey)
        }
    }

    public func loadLastKnownAccountID() -> String? {
        return queue.sync {
            let value = userDefaults.string(forKey: accountIDKey)
            return (value?.isEmpty == false) ? value : nil
        }
    }
}

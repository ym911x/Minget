import Foundation

/// Persists the most recent successful snapshot as normalized numbers only
/// (PROJECT_SPEC.md §11, §14: no auth payloads, no raw RPC responses).
///
/// Three generations of storage coexist here, each deliberately unable to serve another's
/// data:
/// - v1: unattributed, kept only for the no-account-known case;
/// - v2 (1.1+): keyed by Codex account, for the single-account wiring;
/// - v3 (1.3.0): keyed by `profileID + accountID`, which is what two long-lived ChatGPT
///   profiles need. A v2 entry is never served to a profile; it is retired by the one-time
///   migration in `migrateLegacyCacheIfNeeded(profileID:resolvedAccountID:)`.
public final class UsageCache: @unchecked Sendable {
    public static let maxAgeForPanelOpenRefresh: TimeInterval = 30
    public static let stalenessWarnThreshold: TimeInterval = 10 * 60

    private let userDefaults: UserDefaults
    private let storageKey = "UsageMonitor.lastSnapshot.v1"
    private let accountStorageKey = "UsageMonitor.lastSnapshotByAccount.v2"
    private let accountIDKey = "UsageMonitor.lastAccountID.v2"
    private let profileStorageKey = "UsageMonitor.lastSnapshotByProfileAccount.v3"
    private let profileAccountIDKey = "UsageMonitor.lastAccountIDByProfile.v3"
    private let legacyMigrationKey = "UsageMonitor.legacyCacheMigration.v3"
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

    // MARK: Profile-scoped store (1.3.0)

    /// Stores a snapshot for exactly one `profileID + accountID` pair.
    ///
    /// A nil `accountID` is a real state, not a wildcard: it is how a profile whose identity
    /// could not be established yet keeps its own entry. Two profiles therefore never share
    /// a bucket, even while neither knows which account it is signed in as.
    public func save(_ snapshot: UsageSnapshot, profileID: String, accountID: String?) {
        guard !profileID.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(snapshot.persisted) else { return }
        queue.sync {
            var entries = loadProfileEntries()
            entries[Self.profileCacheKey(profileID: profileID, accountID: accountID)] = data
            persistProfileEntries(entries)
        }
    }

    /// Returns the snapshot stored for this profile and account, and only that one.
    /// A known account is never served the profile's unattributed entry, and vice versa.
    public func load(profileID: String, accountID: String?) -> UsageSnapshot? {
        guard !profileID.isEmpty else { return nil }
        var result: UsageSnapshot?
        queue.sync {
            let entries = loadProfileEntries()
            guard let data = entries[Self.profileCacheKey(profileID: profileID, accountID: accountID)] else { return }
            do {
                let persisted = try JSONDecoder().decode(UsageSnapshot.Persisted.self, from: data)
                result = UsageSnapshot.from(persisted: persisted)
            } catch {
                // Corrupt entry: drop it, never surface garbage as data.
                var updated = entries
                updated.removeValue(forKey: Self.profileCacheKey(profileID: profileID, accountID: accountID))
                persistProfileEntries(updated)
                result = nil
            }
        }
        return result
    }

    @discardableResult
    public func clear(profileID: String, accountID: String?) -> Bool {
        guard !profileID.isEmpty else { return false }
        return queue.sync {
            var entries = loadProfileEntries()
            let removed = entries.removeValue(forKey: Self.profileCacheKey(profileID: profileID, accountID: accountID)) != nil
            if removed { persistProfileEntries(entries) }
            return removed
        }
    }

    /// Remembers the account one profile last read successfully.
    ///
    /// Per profile on purpose: a single global value is exactly what let two long-lived
    /// profiles overwrite each other's attribution before 1.3.0.
    public func saveLastKnownAccountID(_ accountID: String, profileID: String) {
        guard !accountID.isEmpty, !profileID.isEmpty else { return }
        queue.sync {
            var entries = loadProfileAccountIDs()
            entries[profileID] = accountID
            if let encoded = try? JSONEncoder().encode(entries) {
                userDefaults.set(encoded, forKey: profileAccountIDKey)
            }
        }
    }

    public func loadLastKnownAccountID(profileID: String) -> String? {
        guard !profileID.isEmpty else { return nil }
        return queue.sync {
            let value = loadProfileAccountIDs()[profileID]
            return (value?.isEmpty == false) ? value : nil
        }
    }

    // MARK: 1.2.1 -> 1.3.0 migration

    /// One-time migration of the v2 account cache, run the first time profile A completes a
    /// successful `account/read` (REQUIREMENTS.md §4.3).
    ///
    /// Rules, all enforced here:
    /// - nothing is displayed from the v2 store before this runs, because 1.3.0 only ever
    ///   reads the v3 namespace;
    /// - the v2 entry moves to `chatgpt-a` only when its `accountID` is *identical* to the
    ///   account A actually resolved;
    /// - a mismatch, or a missing v2 entry, deletes the v2 entry outright rather than leaving
    ///   it to be picked up later;
    /// - account B is never a migration target, whatever the v2 entry says;
    /// - the v1 unattributed store is retired at the same moment, so no pre-1.3.0 number can
    ///   reappear through the legacy accessors.
    public func migrateLegacyCacheIfNeeded(profileID: String, resolvedAccountID: String) {
        guard profileID == ChatGPTAccountProfile.chatGPTA.id else { return }
        guard !resolvedAccountID.isEmpty else { return }
        queue.sync {
            guard !userDefaults.bool(forKey: legacyMigrationKey) else { return }

            let legacyAccountID = {
                let value = userDefaults.string(forKey: accountIDKey)
                return (value?.isEmpty == false) ? value : nil
            }()
            let legacyEntries = loadAccountEntries()

            if let legacyAccountID,
               legacyAccountID == resolvedAccountID,
               let data = legacyEntries[legacyAccountID] {
                var entries = loadProfileEntries()
                entries[Self.profileCacheKey(profileID: profileID, accountID: legacyAccountID)] = data
                persistProfileEntries(entries)
                var accountIDs = loadProfileAccountIDs()
                accountIDs[profileID] = legacyAccountID
                if let encoded = try? JSONEncoder().encode(accountIDs) {
                    userDefaults.set(encoded, forKey: profileAccountIDKey)
                }
            }

            // Retired either way: migrated or not, the v2 and v1 stores must never be read
            // again by this app.
            userDefaults.removeObject(forKey: accountStorageKey)
            userDefaults.removeObject(forKey: accountIDKey)
            userDefaults.removeObject(forKey: storageKey)
            userDefaults.set(true, forKey: legacyMigrationKey)
        }
    }

    /// Whether the one-time v2 retirement has already happened. Test and diagnostic seam.
    public var hasCompletedLegacyMigration: Bool {
        queue.sync { userDefaults.bool(forKey: legacyMigrationKey) }
    }

    private func loadProfileEntries() -> [String: Data] {
        guard let data = userDefaults.data(forKey: profileStorageKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: Data].self, from: data)
        } catch {
            userDefaults.removeObject(forKey: profileStorageKey)
            return [:]
        }
    }

    private func persistProfileEntries(_ entries: [String: Data]) {
        if entries.isEmpty {
            userDefaults.removeObject(forKey: profileStorageKey)
            return
        }
        if let encoded = try? JSONEncoder().encode(entries) {
            userDefaults.set(encoded, forKey: profileStorageKey)
        }
    }

    private func loadProfileAccountIDs() -> [String: String] {
        guard let data = userDefaults.data(forKey: profileAccountIDKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            userDefaults.removeObject(forKey: profileAccountIDKey)
            return [:]
        }
    }

    /// `profileID|accountID`. The separator is a unit separator, which cannot occur in either
    /// a profile identifier or an account identifier, so two pairs can never collide.
    static func profileCacheKey(profileID: String, accountID: String?) -> String {
        "\(profileID)\u{1F}\(accountID ?? "")"
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

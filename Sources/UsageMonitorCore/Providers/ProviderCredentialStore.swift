import Foundation
import Security

/// Persistence for provider credentials.
///
/// Only the macOS Keychain may implement this in production (v1.1 requirement 6):
/// a credential can never reach source, `UserDefaults`, logs, snapshots or docs. The
/// protocol exists so tests can substitute an in-memory store and never touch the real
/// keychain, and so this codebase can assert that nothing else reads the secret.
///
/// `Sendable` is required so the provider clients, which hold one, can be `Sendable`
/// themselves.
public protocol ProviderCredentialStoring: AnyObject, Sendable {
    func save(_ secret: String, for key: ProviderCredentialKey) throws
    func load(_ key: ProviderCredentialKey) -> String?
    /// Returns true when something was actually removed.
    @discardableResult
    func delete(_ key: ProviderCredentialKey) -> Bool
}

/// macOS Keychain generic-password store.
///
/// One service name, one account per credential key. `kSecAttrAccessibleAfterFirstUnlock`
/// is used so a menu bar app works before the first unlock of a session, and so the item
/// is not readable by other processes without the user's authorisation.
public final class KeychainCredentialStore: ProviderCredentialStoring, @unchecked Sendable {

    /// Keychain service namespace. Distinct from the bundle id so a rename of the app
    /// bundle does not orphan stored credentials.
    public static let defaultService = "local.usagemonitor.credentials"

    private let service: String
    /// Serialises read-modify-write so a concurrent save and delete cannot leave a stale item.
    private let lock = NSLock()

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    public func save(_ secret: String, for key: ProviderCredentialKey) throws {
        guard !secret.isEmpty else {
            throw ProviderFailure.notConfigured
        }
        let data = Data(secret.utf8)
        lock.lock(); defer { lock.unlock() }

        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query(for: key) as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ProviderFailure.other
        }

        var add = baseQuery(for: key)
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            // A pre-existing item from an older build can make Add fail with duplicate.
            if addStatus == errSecDuplicateItem {
                let replaced = SecItemUpdate(query(for: key) as CFDictionary, update as CFDictionary)
                if replaced == errSecSuccess { return }
            }
            throw ProviderFailure.other
        }
    }

    public func load(_ key: ProviderCredentialKey) -> String? {
        lock.lock(); defer { lock.unlock() }
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func delete(_ key: ProviderCredentialKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let status = SecItemDelete(query(for: key) as CFDictionary)
        return status == errSecSuccess
    }

    private func baseQuery(for key: ProviderCredentialKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        if #available(macOS 13.0, *) {
            // Shared across this app only; not synchronised to other devices, so a
            // credential never leaves the machine by way of the keychain.
            query[kSecAttrSynchronizable as String] = false
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        }
        return query
    }

    private func query(for key: ProviderCredentialKey) -> [String: Any] {
        return baseQuery(for: key)
    }
}

/// In-memory store for tests and previews. Never used by the app target's production path.
public final class InMemoryCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProviderCredentialKey: String] = [:]
    public private(set) var deleteCallCount = 0

    public init() {}

    public func save(_ secret: String, for key: ProviderCredentialKey) throws {
        lock.lock(); defer { lock.unlock() }
        guard !secret.isEmpty else { throw ProviderFailure.notConfigured }
        values[key] = secret
    }

    public func load(_ key: ProviderCredentialKey) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    @discardableResult
    public func delete(_ key: ProviderCredentialKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        deleteCallCount += 1
        return values.removeValue(forKey: key) != nil
    }
}

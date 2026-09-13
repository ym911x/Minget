import Foundation
import Security

/// Persistence for provider credentials.
///
/// Only the macOS Keychain may implement this in production (v1.1 requirement 6): a
/// credential can never reach source, `UserDefaults`, logs, snapshots or docs. The protocol
/// exists so tests can substitute an in-memory store and never touch the real keychain, and
/// so this codebase can assert that nothing else reads the secret.
///
/// Every read takes an explicit `CredentialInteraction`. Reads that are not started by the
/// user pass `.disallowed`, so a background read can never put a dialog on screen
/// (KEYCHAIN_REVISION_PLAN.md P1.4).
///
/// `Sendable` is required so the provider clients, which hold one, can be `Sendable`
/// themselves.
public protocol ProviderCredentialStoring: AnyObject, Sendable {
    func save(_ secret: String, for key: ProviderCredentialKey) throws
    /// One read. The outcome keeps the framework's distinction between an item that does not
    /// exist, a decision that is required, and any other failure.
    func load(_ key: ProviderCredentialKey, interaction: CredentialInteraction) -> CredentialAccessOutcome
    /// Removes the item. Absent counts as removed; any other failure is thrown, so a caller
    /// can never report a disconnect that did not happen.
    func delete(_ key: ProviderCredentialKey) throws
    /// Removes only the two account names used by pre-1.1.1 GLM builds. This is a retirement
    /// seam, deliberately separate from supported runtime credentials.
    func deleteRetiredGLMCredentials() throws
}

public extension ProviderCredentialStoring {
    /// Convenience for the interactive case: a read the user is waiting for.
    func load(_ key: ProviderCredentialKey) -> CredentialAccessOutcome {
        return load(key, interaction: .allowed)
    }
    func deleteRetiredGLMCredentials() throws {}
}

/// macOS Keychain generic-password store.
///
/// One service name, one account per credential key. `kSecAttrAccessibleAfterFirstUnlock`
/// is used so a menu bar app works before the first unlock of a session, and so the item
/// is not readable by other processes without the user's authorisation.
///
/// The background policy uses `SecKeychainSetUserInteractionAllowed`. That API is deprecated
/// (macOS 10.10) but is still the documented process-wide switch for the file-based keychain;
/// the Data Protection keychain and its `kSecUseAuthenticationUI` key are a different backend
/// and cannot be assumed to apply here. It is only safe because
/// `CredentialAccessCoordinator` serialises every keychain call in this process, so the window
/// with interaction disabled can never overlap a user-initiated read, and the previous value
/// is always restored. Real-dialog behaviour still has to be confirmed on a real launch
/// (KEYCHAIN_REVISION_PLAN.md P1.5).
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

    public func load(_ key: ProviderCredentialKey, interaction: CredentialInteraction) -> CredentialAccessOutcome {
        lock.lock(); defer { lock.unlock() }
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        switch interaction {
        case .disallowed:
            let restore = Self.disallowUserInteraction()
            defer { restore() }
            return Self.classify(SecItemCopyMatching(query as CFDictionary, &result), result: result)
        case .allowed:
            return Self.classify(SecItemCopyMatching(query as CFDictionary, &result), result: result)
        }
    }

    public func delete(_ key: ProviderCredentialKey) throws {
        lock.lock(); defer { lock.unlock() }
        let status = SecItemDelete(query(for: key) as CFDictionary)
        // Absent is the intended end state, so it counts as removed.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderFailure.other
        }
    }

    public func deleteRetiredGLMCredentials() throws {
        lock.lock(); defer { lock.unlock() }
        for account in ["glm.api-key", "glm.console-session"] {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ProviderFailure.other }
        }
    }

    /// Turns off keychain UI for the duration of one call and returns the closure that puts
    /// the previous value back. The previous value is read first, so a nested or interrupted
    /// call can never leave the process with interaction permanently disabled.
    static func disallowUserInteraction() -> () -> Void {
        // The getter takes `DarwinBoolean` while the setter takes `Bool`; both are the same
        // C `Boolean`, so the round trip is done in `Bool`.
        var previous = DarwinBoolean(true)
        let readStatus = SecKeychainGetUserInteractionAllowed(&previous)
        _ = SecKeychainSetUserInteractionAllowed(false)
        return {
            guard readStatus == errSecSuccess else {
                // The previous state could not be read: restore the documented default
                // instead of leaving interaction disabled.
                _ = SecKeychainSetUserInteractionAllowed(true)
                return
            }
            _ = SecKeychainSetUserInteractionAllowed(previous.boolValue)
        }
    }

    /// Maps one `OSStatus` onto the fixed outcome vocabulary. Only `errSecItemNotFound` means
    /// the item does not exist; every other failure keeps its status instead of being
    /// reported as "nothing saved".
    static func classify(_ status: OSStatus, result: AnyObject?) -> CredentialAccessOutcome {
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let text = String(data: data, encoding: .utf8),
                  !text.isEmpty else {
                // A malformed or empty payload is not a usable credential and must never be
                // reported as available.
                return .unavailable(errSecDecode)
            }
            return .available(text)
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed:
            return .interactionRequired(status)
        case errSecUserCanceled, errSecAuthFailed:
            // The framework does not distinguish "the user said no" from "the request was
            // cancelled" for a file-based item, so both land here; the raw status is kept so
            // the diagnostics log can tell them apart.
            return .deniedOrCancelled(status)
        default:
            return .unavailable(status)
        }
    }

    private func baseQuery(for key: ProviderCredentialKey) -> [String: Any] {
        baseQuery(account: key.rawValue)
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
///
/// Tests drive it to produce any outcome the real keychain could return, including the
/// refusal and "interaction required" statuses, without a real keychain and without a dialog.
public final class InMemoryCredentialStore: ProviderCredentialStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var values: [ProviderCredentialKey: String] = [:]
    /// When a key has an entry here, that outcome is returned instead of consulting
    /// `values`, so a test can simulate a refusal or a raw `OSStatus`.
    private var simulated: [ProviderCredentialKey: CredentialAccessOutcome] = [:]
    private var recorded: [(key: ProviderCredentialKey, interaction: CredentialInteraction)] = []

    public private(set) var loadCallCount = 0
    public private(set) var saveCallCount = 0
    public private(set) var deleteCallCount = 0
    /// Artificial latency, so a test can hold two callers in the same in-flight read.
    public var loadDelay: TimeInterval = 0
    /// Simulated write failures.
    public var saveError: Error?
    public var deleteError: Error?

    public init() {}

    // MARK: Test control

    public func seed(_ secret: String, for key: ProviderCredentialKey) {
        lock.lock(); values[key] = secret; simulated[key] = nil; lock.unlock()
    }

    /// Forces reads of `key` to return `outcome` until it is cleared.
    public func simulate(_ outcome: CredentialAccessOutcome?, for key: ProviderCredentialKey) {
        lock.lock(); simulated[key] = outcome; lock.unlock()
    }

    /// Every load in order, so a test can assert both the count and the interaction mode.
    public var recordedLoads: [(key: ProviderCredentialKey, interaction: CredentialInteraction)] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    public func loads(of key: ProviderCredentialKey,
                      interaction: CredentialInteraction? = nil) -> Int {
        lock.lock(); defer { lock.unlock() }
        return recorded.filter { $0.key == key && (interaction == nil || $0.interaction == interaction) }.count
    }

    // MARK: ProviderCredentialStoring

    public func save(_ secret: String, for key: ProviderCredentialKey) throws {
        lock.lock()
        saveCallCount += 1
        let error = saveError
        lock.unlock()
        if let error { throw error }
        guard !secret.isEmpty else { throw ProviderFailure.notConfigured }
        lock.lock(); values[key] = secret; simulated[key] = nil; lock.unlock()
    }

    public func load(_ key: ProviderCredentialKey, interaction: CredentialInteraction) -> CredentialAccessOutcome {
        lock.lock()
        loadCallCount += 1
        recorded.append((key, interaction))
        let override = simulated[key]
        let value = values[key]
        let delay = loadDelay
        lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        if let override { return override }
        guard let value else { return .missing }
        return .available(value)
    }

    public func delete(_ key: ProviderCredentialKey) throws {
        lock.lock()
        deleteCallCount += 1
        let error = deleteError
        lock.unlock()
        if let error { throw error }
        lock.lock(); values.removeValue(forKey: key); simulated[key] = nil; lock.unlock()
    }
}

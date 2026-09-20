import Foundation

/// Why a credential was accessed.
///
/// A fixed vocabulary, because the value reaches the diagnostic log: it must never carry
/// user text or anything derived from a secret.
public enum CredentialAccessPurpose: String, Sendable, CaseIterable {
    /// First read after launch, to learn which providers are worth connecting.
    case startupPrime = "startup-prime"
    /// The user explicitly asked for a read (the 授权读取 button, or 探测一次).
    case userRequestedRead = "user-read"
    /// A provider read: the periodic cycle, a panel-open refresh, or 全部刷新. Note there is
    /// deliberately no "status query" purpose: a status question is answered from memory and
    /// must never reach the keychain (KEYCHAIN_REVISION_PLAN.md P1.3).
    case providerRead = "provider-read"
    /// A user-confirmed Command Code fire. It may retry a blocked Keychain read.
    case manualFire = "manual-fire"
    /// A timer-originated Command Code fire. It must never show a Keychain dialog.
    case scheduledFire = "scheduled-fire"
    /// A credential was just saved and is being exercised.
    case connect = "connect"
    case save = "save"
    case delete = "delete"
}

/// True when this purpose may make a fresh attempt on a credential that is currently blocked
/// or was refused before. Only a purpose the user originated may do that: an automatic read
/// (startup prime, scheduled cycle, status-driven read) must report the remembered refusal
/// instead of asking again, which is what stops a prompt loop
/// (KEYCHAIN_REVISION_PLAN.md P1.4 and P1.6).
public extension CredentialAccessPurpose {
    var mayRetryBlocked: Bool {
        switch self {
        case .userRequestedRead, .connect, .manualFire: return true
        case .startupPrime, .providerRead, .scheduledFire, .save, .delete: return false
        }
    }
}

/// Whether this access may put a dialog on screen.
///
/// A menu bar app that interrupts with a keychain prompt on a timer is unusable, so
/// anything not started by the user is background. Background reads are the only reason
/// a self-signed build could loop on authorisation: each one that is refused must be
/// remembered as refused instead of being retried forever
/// (KEYCHAIN_REVISION_PLAN.md P1.4 and P1.6).
public enum CredentialInteraction: String, Sendable {
    /// The security framework may show its authorisation dialog.
    case allowed = "interactive"
    /// The security framework must not show UI. A read that needs a decision reports it
    /// instead of asking.
    case disallowed = "background"
}

/// Result of exactly one credential access.
///
/// Deliberately conservative: only states the security framework can actually distinguish
/// are separated, and anything else keeps its raw `OSStatus` for redacted diagnostics
/// rather than being bent into a category that would mislead
/// (KEYCHAIN_REVISION_PLAN.md P1.1).
public enum CredentialAccessOutcome: Equatable, Sendable {

    case available(String)
    /// The item does not exist. The only status mapped here is `errSecItemNotFound`.
    case missing
    /// A decision by the user is needed before the item can be read. The raw status is kept
    /// because the framework cannot be asked later why it refused.
    case interactionRequired(Int32)
    /// The user refused or cancelled the request. The raw status is kept for the same reason.
    case deniedOrCancelled(Int32)
    /// Anything else, with the raw status preserved. Never reported as "not saved".
    case unavailable(Int32)

    /// Fixed, log-safe code. `available` never carries the value through this property.
    public var code: String {
        switch self {
        case .available: return "available"
        case .missing: return "missing"
        case .interactionRequired: return "interactionRequired"
        case .deniedOrCancelled: return "deniedOrCancelled"
        case .unavailable: return "unavailable"
        }
    }

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var isMissing: Bool { self == .missing }

    /// The item exists but could not be read without a decision, or the decision was no.
    public var isBlocked: Bool {
        switch self {
        case .interactionRequired, .deniedOrCancelled: return true
        default: return false
        }
    }

    /// The raw status behind the outcome, when there is one. Written to the diagnostics log.
    public var osStatus: Int32? {
        switch self {
        case .missing: return nil
        case .interactionRequired(let status): return status
        case .deniedOrCancelled(let status): return status
        case .unavailable(let status): return status
        case .available: return nil
        }
    }

    /// The secret, when there is one. Never logged, never persisted, never echoed.
    public var secret: String? {
        if case .available(let value) = self { return value }
        return nil
    }
}

/// What the coordinator currently knows about one credential, without touching the
/// keychain again. This is the only thing `isConfigured`-style questions may read
/// (KEYCHAIN_REVISION_PLAN.md P1.3).
public enum ProviderCredentialPhase: String, Equatable, Sendable {
    /// Nothing has been read yet in this process.
    case unknown
    /// A value was read and is held in memory.
    case available
    /// The item was confirmed absent.
    case missing
    /// Reading needs the user's decision, or the user declined. Not retried automatically.
    case needsAuthorization
    /// The read failed for another reason; the raw status is remembered for diagnostics.
    case unavailable

    public var isConfigured: Bool { self == .available }
}

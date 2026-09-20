import Foundation

/// DeepSeek reader wired to the keychain-backed key.
/// Credential state is memory-backed; keychain reads are limited to explicit lifecycle or
/// user actions through `CredentialAccessCoordinator`.
public final class DeepSeekReading: ProviderReading, @unchecked Sendable {
    public let platform: ProviderPlatform = .deepseek
    public var isAutomaticRefreshEnabled: Bool { true }

    private let provider: DeepSeekProvider
    private let access: CredentialAccessCoordinator

    public init(provider: DeepSeekProvider, credentials: ProviderCredentialStoring,
                accessQueue: DispatchQueue? = nil) {
        self.provider = provider
        self.access = accessQueue.map { CredentialAccessCoordinator(store: credentials, queue: $0) }
            ?? CredentialAccessCoordinator(store: credentials)
    }

    public var credentialState: ProviderCredentialState {
        ProviderCredentialState(phase: access.phase(for: .deepseekAPIKey))
    }
    public var isConfigured: Bool { credentialState.isConfigured }
    public var onCredentialPhaseChange: (() -> Void)? {
        get { access.onPhaseChange }
        set { access.onPhaseChange = newValue }
    }
    public func primeCredentialState() async { await access.prime([.deepseekAPIKey]) }
    @discardableResult public func authorizeCredentialAccess() async -> Bool {
        await access.value(for: .deepseekAPIKey, purpose: .userRequestedRead, interaction: .allowed).isAvailable
    }
    public func read() async throws -> ProviderReadResult {
        let outcome = await access.value(for: .deepseekAPIKey, purpose: .providerRead, interaction: .allowed)
        guard let key = outcome.secret, !key.isEmpty else { throw Self.failure(for: outcome) }
        let balances = try await provider.fetchBalances(apiKey: key)
        return ProviderReadResult(accountID: DeepSeekProvider.accountFingerprint(forAPIKey: key), balances: balances, consoleURL: nil)
    }
    public func storeAPIKey(_ key: String) throws { try access.store(key, for: .deepseekAPIKey) }
    public func disconnect() throws { try access.remove(.deepseekAPIKey) }
    static func failure(for outcome: CredentialAccessOutcome) -> ProviderFailure {
        switch outcome {
        case .available: return .other
        case .missing: return .notConfigured
        case .interactionRequired, .deniedOrCancelled: return .credentialAccessBlocked
        case .unavailable: return .other
        }
    }
}

/// Command Code reader. It owns only an app-provided API key and never reads browser
/// cookies or Command Code CLI configuration.
///
/// The auxiliary enrichment (summary, subscriptions) is throttled inside the provider:
/// automatic refreshes reuse the last auxiliary payloads for 15 minutes and only
/// re-read credits, while explicit user actions force a full read.
public final class CommandCodeReading: ProviderReading, @unchecked Sendable {
    public let platform: ProviderPlatform = .commandcode
    public var isAutomaticRefreshEnabled: Bool { true }

    private let provider: CommandCodeProvider
    private let access: CredentialAccessCoordinator

    public init(provider: CommandCodeProvider, credentials: ProviderCredentialStoring, accessQueue: DispatchQueue? = nil) {
        self.provider = provider
        self.access = accessQueue.map { CredentialAccessCoordinator(store: credentials, queue: $0) }
            ?? CredentialAccessCoordinator(store: credentials)
    }

    public var credentialState: ProviderCredentialState { ProviderCredentialState(phase: access.phase(for: .commandCodeAPIKey)) }
    public var isConfigured: Bool { credentialState.isConfigured }
    public var onCredentialPhaseChange: (() -> Void)? {
        get { access.onPhaseChange }
        set { access.onPhaseChange = newValue }
    }
    public func primeCredentialState() async { await access.prime([.commandCodeAPIKey]) }
    @discardableResult public func authorizeCredentialAccess() async -> Bool {
        await access.value(for: .commandCodeAPIKey, purpose: .userRequestedRead, interaction: .allowed).isAvailable
    }
    public func read() async throws -> ProviderReadResult {
        try await read(auxiliaryPolicy: .automatic)
    }

    /// The policy belongs to this exact read. Keeping it out of mutable one-shot state stops
    /// an older credential generation from consuming a newer reconnect's forced refresh.
    public func read(auxiliaryPolicy: CommandCodeProvider.AuxiliaryPolicy) async throws -> ProviderReadResult {
        let outcome = await access.value(for: .commandCodeAPIKey, purpose: .providerRead, interaction: .allowed)
        guard let key = outcome.secret, !key.isEmpty else { throw DeepSeekReading.failure(for: outcome) }
        let usage = try await provider.fetchUsage(apiKey: key, auxiliaryPolicy: auxiliaryPolicy)
        return ProviderReadResult(accountID: CommandCodeProvider.accountFingerprint(forAPIKey: key), balances: [], usage: usage, consoleURL: URL(string: "https://commandcode.ai/studio/"))
    }

    /// Returns the already app-owned Key for an explicitly authorised fire. Scheduled work
    /// is background-only and can never open a Keychain prompt; a manual button may ask once.
    public func fireCredential(userInitiated: Bool) async -> CredentialAccessOutcome {
        await access.value(for: .commandCodeAPIKey,
                           purpose: userInitiated ? .manualFire : .scheduledFire,
                           interaction: userInitiated ? .allowed : .disallowed)
    }

    /// One live credits-only observation after a fire. It shares the same interaction rule
    /// as the request that caused it and never touches summary/subscription.
    public func fiveHourResetForFire(userInitiated: Bool) async throws -> Date? {
        let outcome = await fireCredential(userInitiated: userInitiated)
        guard let key = outcome.secret, !key.isEmpty else { throw DeepSeekReading.failure(for: outcome) }
        return try await provider.fetchFiveHourReset(apiKey: key)
    }
    public func storeAPIKey(_ key: String) throws { try access.store(key, for: .commandCodeAPIKey) }
    public func disconnect() throws { try access.remove(.commandCodeAPIKey) }
}

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

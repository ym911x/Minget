import Foundation

/// One-way 1.1.1 cleanup for the retired GLM integration. It owns no credential values and
/// only addresses identifiers created by this app's earlier releases. A failed Keychain
/// deletion intentionally leaves the migration marker unset, so the next launch retries.
public final class ProviderRetirementMigration: @unchecked Sendable {
    private static let completedKey = "UsageMonitor.1.1.1.glmRetirementComplete"
    private let credentials: ProviderCredentialStoring
    private let cache: ProviderCache
    private let defaults: UserDefaults

    public init(credentials: ProviderCredentialStoring, cache: ProviderCache,
                defaults: UserDefaults = .standard) {
        self.credentials = credentials
        self.cache = cache
        self.defaults = defaults
    }

    public func run() {
        guard !defaults.bool(forKey: Self.completedKey) else { return }
        do {
            try credentials.deleteRetiredGLMCredentials()
        } catch {
            return
        }
        cache.removeRetiredGLMEntries()
        defaults.removeObject(forKey: "UsageMonitor.glm.connectionMode")
        defaults.removeObject(forKey: "detail.showGLM")
        defaults.set(true, forKey: Self.completedKey)
    }
}

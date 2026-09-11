import Foundation
import CryptoKit

/// DeepSeek platform balance reader.
///
/// Official, publicly documented read-only endpoint (see PROVIDER_ENDPOINTS.md):
/// `GET https://api.deepseek.com/user/balance` with `Authorization: Bearer <api key>`.
///
/// Only this path may be issued by this client. Nothing here talks to a model endpoint,
/// and the API key is never used to "test" a model call: the balance endpoint is itself
/// the credential check, so a wrong key is detected without any inference request.
public struct DeepSeekProvider: Sendable {

    public static let apiBaseURL = URL(string: "https://api.deepseek.com")!
    /// The only path this client is allowed to request.
    public static let balancePath = "/user/balance"
    public static let allowedPaths: Set<String> = [balancePath]

    public let client: ProviderHTTPClient

    /// No credential store here on purpose: the key is passed in by the caller, which read it
    /// exactly once through `CredentialAccessCoordinator`. One business read must not fetch
    /// the same key twice (KEYCHAIN_REVISION_PLAN.md P1.7).
    public init(transport: ProviderTransport) {
        self.client = ProviderHTTPClient(baseURL: Self.apiBaseURL,
                                         allowedPaths: Self.allowedPaths,
                                         transport: transport,
                                         defaultHeaders: ["Accept": "application/json"])
    }

    /// Stable, non-secret identifier used to isolate the business cache. A 6-hex-character
    /// SHA-256 prefix of the key: replacing the key invalidates the old cache, and the
    /// value cannot be turned back into the key. Never logged, never written to the
    /// keychain.
    public static func accountFingerprint(forAPIKey key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    /// Fetches the balance with a key the caller already read. Blocking network work; call
    /// from a background task.
    public func fetchBalances(apiKey: String, timeout: TimeInterval = 15) async throws -> [ProviderBalance] {
        guard !apiKey.isEmpty else {
            throw ProviderFailure.notConfigured
        }
        let response: ProviderHTTPResponse
        do {
            response = try await client.get(path: Self.balancePath,
                                            headers: ["Authorization": "Bearer \(apiKey)"],
                                            timeout: timeout)
        } catch let transport as ProviderTransportError {
            throw ProviderFailure.from(transport)
        }
        return try Self.parseBalancePayload(response: response)
    }

    /// HTTP transport → currency buckets, or a fixed failure.
    public static func parseBalancePayload(response: ProviderHTTPResponse) throws -> [ProviderBalance] {
        guard response.isOK else {
            if response.status == 401 || response.status == 403 {
                throw ProviderFailure.invalidCredential
            }
            throw ProviderFailure.serverError(status: response.status)
        }
        return try parseBalanceData(response.body)
    }

    public static func parseBalanceData(_ data: Data) throws -> [ProviderBalance] {
        guard let object = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any] else {
            throw ProviderFailure.unexpectedResponse
        }
        if let failure = businessError(in: object) { throw failure }

        // balance_infos: one entry per currency. Currencies are reported separately and
        // are never converted or summed.
        guard let entries = object["balance_infos"] as? [[String: Any]], !entries.isEmpty else {
            throw ProviderFailure.unexpectedResponse
        }

        var balances: [ProviderBalance] = []
        for entry in entries {
            guard let currency = Self.currency(in: entry) else { continue }
            guard let total = SafeConversion.decimal(entry["total_balance"]) else { continue }
            balances.append(ProviderBalance(currency: currency,
                                            total: total,
                                            granted: SafeConversion.decimal(entry["granted_balance"]),
                                            toppedUp: SafeConversion.decimal(entry["topped_up_balance"])))
        }
        guard !balances.isEmpty else {
            throw ProviderFailure.unexpectedResponse
        }
        return balances
    }

    /// DeepSeek reports a failure as HTTP 200 with an error object. Recognised by shape so
    /// a renamed error field degrades to "unexpected response" instead of a fake balance.
    static func businessError(in object: [String: Any]) -> ProviderFailure? {
        if let errorObject = object["error"] as? [String: Any] {
            return .businessError(code: SafeConversion.errorCode(errorObject["code"] ?? errorObject["status_code"]))
        }
        if object["error_message"] is String { return .businessError(code: -1) }
        return nil
    }

    static func currency(in entry: [String: Any]) -> String? {
        guard let raw = entry["currency"] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

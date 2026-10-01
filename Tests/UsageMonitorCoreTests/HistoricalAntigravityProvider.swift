import Foundation
import CoreFoundation
@testable import UsageMonitorCore

// Historical proxy prototype regression fixture. Not included in the application.
public protocol AntigravityReading: Sendable {
    func accounts(baseURL: String, managementKey: String) async throws -> [AntigravityAccount]
    func quota(account: AntigravityAccount, baseURL: String, managementKey: String) async throws -> AntigravitySnapshot
}

/// The management key only reaches a literal loopback address. Google tokens stay in CPA.
/// This client exposes no arbitrary forwarding, OAuth download, mutation or generation API.
public struct AntigravityProvider: AntigravityReading, Sendable {
    public static let defaultBaseURL = "http://127.0.0.1:8317"
    public static let quotaHosts = ["daily-cloudcode-pa.googleapis.com",
                                    "daily-cloudcode-pa.sandbox.googleapis.com",
                                    "cloudcode-pa.googleapis.com"]
    private let transport: ProviderTransport
    public init(transport: ProviderTransport = URLSessionProviderTransport(refuseAllRedirects: true)) {
        self.transport = transport
    }

    public static func validatedBaseURL(_ text: String) throws -> URL {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "http", c.host == "127.0.0.1", c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
              c.port.map({ (1...65535).contains($0) }) ?? true,
              let url = c.url else { throw ProviderFailure.unexpectedResponse }
        return url
    }

    private func request(baseURL: String, key: String, path: String, body: Data? = nil) async throws -> Data {
        guard path == "/v0/management/auth-files" || path == "/v0/management/api-call" else {
            throw ProviderFailure.unexpectedResponse
        }
        let base = try Self.validatedBaseURL(baseURL)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw ProviderFailure.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let response: ProviderHTTPResponse
        do { response = try await transport.send(request) }
        catch let error as ProviderTransportError { throw ProviderFailure.from(error) }
        catch { throw ProviderFailure.other }
        try Self.checkStatus(response.status, credential: true)
        return response.body
    }

    public func accounts(baseURL: String, managementKey: String) async throws -> [AntigravityAccount] {
        let data = try await request(baseURL: baseURL, key: managementKey, path: "/v0/management/auth-files")
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = object["files"] as? [[String: Any]] else { throw ProviderFailure.structureUnsupported }
        var result: [AntigravityAccount] = []
        var seen = Set<String>()
        for file in files {
            guard (Self.text(file["provider"]) ?? Self.text(file["type"]))?.lowercased() == "antigravity",
                  let id = Self.text(file["id"]) ?? Self.text(file["name"]),
                  let index = Self.text(file["auth_index"]), seen.insert(id).inserted else { continue }
            let email = Self.text(file["email"])
            result.append(AntigravityAccount(id: id, authIndex: index,
                          label: Self.text(file["label"]) ?? email ?? "Google 账号",
                          email: email, projectID: Self.text(file["project_id"]),
                          disabled: file["disabled"] as? Bool ?? false,
                          unavailable: file["unavailable"] as? Bool ?? false))
        }
        return result.sorted { $0.id < $1.id }
    }

    public func quota(account: AntigravityAccount, baseURL: String, managementKey: String) async throws -> AntigravitySnapshot {
        guard !account.disabled else { throw ProviderFailure.suspended }
        // No auth-file download fallback. Current CPA exposes project_id in account metadata.
        let data = try JSONSerialization.data(withJSONObject: account.projectID.map { ["project": $0] } ?? [:])
        let dataText = String(decoding: data, as: UTF8.self)
        var failure: ProviderFailure = .structureUnsupported
        for method in ["retrieveUserQuotaSummary", "fetchAvailableModels"] {
            for host in Self.quotaHosts {
                try Task.checkCancellation()
                let payload: [String: Any] = ["auth_index": account.authIndex, "method": "POST",
                    "url": "https://" + host + "/v1internal:" + method,
                    "header": ["Authorization": "Bearer $TOKEN$", "Content-Type": "application/json",
                               "User-Agent": "antigravity/cli/1.0.13 (aidev_client; os_type=darwin; arch=arm64)"],
                    "data": dataText]
                let body = try JSONSerialization.data(withJSONObject: payload)
                let response = try await request(baseURL: baseURL, key: managementKey,
                                                  path: "/v0/management/api-call", body: body)
                guard let envelope = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
                      let status = envelope["status_code"] as? Int else { throw ProviderFailure.structureUnsupported }
                if !(200..<300).contains(status) {
                    // Never try another endpoint after authentication or throttling failures.
                    if (300..<400).contains(status) || status == 401 || status == 429 { try Self.checkStatus(status, credential: false) }
                    failure = .serverError(status: status)
                    continue
                }
                let upstream: Data
                if let text = envelope["body"] as? String { upstream = Data(text.utf8) }
                else if let object = envelope["body"] as? [String: Any] {
                    upstream = try JSONSerialization.data(withJSONObject: object)
                } else { throw ProviderFailure.structureUnsupported }
                do {
                    let groups = try Self.parseGroups(upstream)
                    return AntigravitySnapshot(accountIdentity: account.identity, groups: groups, fetchedAt: Date())
                } catch let error as ProviderFailure { failure = error }
            }
        }
        throw failure
    }

    /// Preserves unknown fields as unknown values, never synthesizes shared model pools.
    public static func parseGroups(_ data: Data) throws -> [AntigravityQuotaGroup] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil else {
            throw ProviderFailure.structureUnsupported
        }
        if let groups = object["groups"] as? [[String: Any]], !groups.isEmpty {
            var seen = Set<String>()
            let parsed = groups.enumerated().compactMap { index, group -> AntigravityQuotaGroup? in
                let label = text(group["displayName"] ?? group["display_name"]) ?? "额度组 \(index + 1)"
                let id = text(group["groupId"] ?? group["group_id"] ?? group["id"]) ?? label
                guard seen.insert(id).inserted, let buckets = group["buckets"] as? [[String: Any]] else { return nil }
                var bucketIDs = Set<String>()
                let values = buckets.enumerated().compactMap { offset, bucket -> AntigravityQuotaBucket? in
                    let window = text(bucket["window"])
                    let bid = text(bucket["bucketId"] ?? bucket["bucket_id"] ?? bucket["id"]) ?? "\(id):\(window ?? String(offset))"
                    guard bucketIDs.insert(bid).inserted else { return nil }
                    return parseBucket(bucket, id: bid,
                              label: text(bucket["displayName"] ?? bucket["display_name"]) ?? window ?? "额度", window: window)
                }
                return AntigravityQuotaGroup(id: id, label: label, models: (group["models"] as? [String]) ?? [], buckets: values)
            }
            if !parsed.isEmpty { return parsed }
        }
        if let models = object["models"] as? [String: [String: Any]], !models.isEmpty {
            let parsed = models.keys.sorted().compactMap { id -> AntigravityQuotaGroup? in
                guard let model = models[id], let info = (model["quotaInfo"] ?? model["quota_info"]) as? [String: Any] else { return nil }
                let label = text(model["displayName"] ?? model["display_name"]) ?? id
                return AntigravityQuotaGroup(id: id, label: label, models: [id], buckets: [parseBucket(info, id: id, label: label, window: text(info["window"]))])
            }
            if !parsed.isEmpty { return parsed }
        }
        throw ProviderFailure.structureUnsupported
    }

    private static func parseBucket(_ object: [String: Any], id: String, label: String, window: String?) -> AntigravityQuotaBucket {
        let raw = object["remainingFraction"] ?? object["remaining_fraction"] ?? object["remaining"]
        var number: Double?
        if let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { number = value.doubleValue }
        else if let value = raw as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { number = Double(value) }
        if let value = number, !value.isFinite || !(0...1).contains(value) { number = nil }
        let reset = text(object["resetTime"] ?? object["reset_time"])
        let formatter = ISO8601DateFormatter()
        var date = reset.flatMap(formatter.date)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = reset.flatMap(formatter.date)
        }
        return AntigravityQuotaBucket(id: id, label: label, window: window, remainingFraction: number, resetsAt: date)
    }
    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func checkStatus(_ status: Int, credential: Bool) throws {
        if (300..<400).contains(status) { throw ProviderFailure.crossDomainRedirectBlocked }
        if status == 401 || (credential && status == 403) { throw ProviderFailure.invalidCredential }
        guard (200..<300).contains(status) else { throw ProviderFailure.serverError(status: status) }
    }
}

import Foundation
import CryptoKit

/// 智谱 GLM (bigmodel.cn) account funds reader.
///
/// Evidence status (see PROVIDER_ENDPOINTS.md for the full, redacted record):
/// - `/api/paas/v4/balance` is used by multiple independent open-source implementations
///   with a plain API key, but has no official public documentation this project could
///   consult: evidence level "third-party implementations + user verification pending".
/// - `/api/biz/account/query-customer-account-report` is an undocumented console interface;
///   the user's real probe answered HTTP 200 with top-level `code/data/msg/success`.
///
/// Because of that, display is governed by **per-endpoint strict schemas**, not by one
/// global boolean (Round 7 requirement 2): a response is displayed only when it matches
/// the confirmed envelope, field paths, types and amount constraints of its endpoint's
/// schema. Anything else is recorded as a redacted structure observation, never guessed.
public struct GLMProvider: Sendable {

    public static let openAPIBaseURL = URL(string: "https://open.bigmodel.cn")!
    /// Read-only balance endpoint for a plain API key (Round 7 requirement 1). The primary
    /// balance path; no model inference is reachable through it or any other path.
    public static let balancePath = "/api/paas/v4/balance"
    /// Candidate official endpoint for console account/funds reporting. Kept for console
    /// sessions and as the API-key fallback (Round 7 requirement 2).
    public static let accountReportPath = "/api/biz/account/query-customer-account-report"
    public static let allowedPaths: Set<String> = [balancePath, accountReportPath]

    public static let balanceSchema: GLMSchema = .apiBalanceV1
    public static let consoleReportSchema: GLMSchema = .consoleReportV1

    /// Console entry the panel offers whenever the app cannot or may not read the account.
    public static let consoleURL = URL(string: "https://bigmodel.cn/console")!
    public static let consoleHosts: [String] = ["bigmodel.cn", "open.bigmodel.cn"]

    public let consoleClient: ProviderHTTPClient
    public let client: ProviderHTTPClient

    /// No credential store here on purpose: the key is passed in by the caller, which read it
    /// exactly once through `CredentialAccessCoordinator`, and only when the selected
    /// connection mode actually needs it (KEYCHAIN_REVISION_PLAN.md P1.7).
    public init(transport: ProviderTransport) {
        self.consoleClient = ProviderHTTPClient(baseURL: URL(string: "https://bigmodel.cn")!,
                                                allowedPaths: [Self.accountReportPath],
                                                transport: transport,
                                                defaultHeaders: ["Accept": "application/json"])
        self.client = ProviderHTTPClient(baseURL: Self.openAPIBaseURL,
                                         allowedPaths: Self.allowedPaths,
                                         transport: transport,
                                         defaultHeaders: ["Accept": "application/json"])
    }

    // MARK: - API key

    /// Stable, non-secret identifier for cache isolation: a 6-hex-character SHA-256 prefix
    /// of the key. Replacing the key invalidates the old cache; the value cannot be
    /// reversed into the key. Never logged, never stored in the keychain.
    public static func apiKeyFingerprint(forAPIKey key: String) -> String {
        return String(SHA256.hash(data: Data(key.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined())
    }

    /// Probes the read-only balance endpoint with the API key. Read-only, no model call,
    /// no third-party hop: the request goes to `open.bigmodel.cn` or nowhere.
    ///
    /// Returns an *observation*, not a balance, and never throws for an HTTP outcome: a
    /// rejection or a business error is classified into the observation (with the real
    /// HTTP status preserved) so the caller can publish it. Two `Authorization` spellings
    /// have existed across GLM API generations; both are tried, and neither is treated as
    /// accepted until a payload survives the schema gate.
    public func probeBalanceObservation(apiKey: String, timeout: TimeInterval = 15) async -> GLMAccountReportObservation {
        guard !apiKey.isEmpty else {
            return GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                               businessCode: nil, candidateBalances: [],
                                               parseFailure: .notConfigured)
        }

        var last: GLMAccountReportObservation = GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                                                            businessCode: nil, candidateBalances: [],
                                                                            parseFailure: .unexpectedResponse)
        for scheme in GLMHeaderScheme.allCases {
            do {
                let response = try await client.get(path: Self.balancePath,
                                                    headers: ["Authorization": scheme.headerValue(for: apiKey)],
                                                    timeout: timeout)
                let observation = GLMAccountReportParser.observe(response: response, schema: Self.balanceSchema)
                if observation.parseFailure == nil {
                    // A payload that parsed cleanly is the best evidence available.
                    return observation
                }
                last = observation
            } catch let transport as ProviderTransportError {
                last = GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                                   businessCode: nil, candidateBalances: [],
                                                   parseFailure: ProviderFailure.from(transport))
            } catch {
                last = GLMAccountReportObservation(httpStatus: 0, topLevelKeys: [],
                                                   businessCode: nil, candidateBalances: [],
                                                   parseFailure: .other)
            }
        }
        return last
    }

    /// Throwing form of the probe, for callers that want a failure instead of an
    /// observation. The classification comes from the same observation the non-throwing
    /// form publishes, so the two can never disagree.
    public func probeBalance(apiKey: String, timeout: TimeInterval = 15) async throws -> GLMAccountReportObservation {
        let observation = await probeBalanceObservation(apiKey: apiKey, timeout: timeout)
        if let failure = observation.parseFailure { throw failure }
        return observation
    }
}

/// Authorization header spellings that have existed across GLM API generations.
public enum GLMHeaderScheme: CaseIterable, Sendable {
    case bearer
    case apiKeyPrefix

    public func headerValue(for key: String) -> String {
        switch self {
        case .bearer: return "Bearer \(key)"
        case .apiKeyPrefix: return "ApiKey \(key)"
        }
    }
}

/// The two GLM endpoints, each with its own strict payload schema (Round 7 requirement 2).
/// A response is only ever displayed under the schema of the endpoint that produced it.
public enum GLMSchema: String, CaseIterable, Sendable {
    /// `GET /api/paas/v4/balance` — `data.total_balance`, `data.available_balance`,
    /// `data.currency` (amounts as JSON number or decimal string).
    case apiBalanceV1
    /// `GET /api/biz/account/query-customer-account-report` — `data.balance` object with
    /// `balance`, `availableBalance`, `rechargeAmount`, `giveAmount`, `totalSpendAmount`,
    /// `frozenBalance`.
    case consoleReportV1
}

/// The display gate, per schema. Replaces the former single global boolean: opening a
/// schema is a reviewed decision that requires the evidence recorded in
/// PROVIDER_ENDPOINTS.md and the schema's parser pinned by tests. It is never a runtime
/// adaptation.
public enum GLMContract {
    /// Schemas whose envelope, field paths, types and amount constraints are pinned by
    /// tests. Current evidence: third-party implementations plus the user's real probe,
    /// not official documentation — recorded as such in PROVIDER_ENDPOINTS.md.
    public static let confirmedSchemas: Set<GLMSchema> = [.apiBalanceV1, .consoleReportV1]

    public static func isConfirmed(_ schema: GLMSchema) -> Bool {
        return confirmedSchemas.contains(schema)
    }
}

/// HTTP 200 bodies carry business results here, so a success status alone proves nothing.
///
/// The success spellings are fixed here and pinned by tests (Round 7 requirement 3):
/// numeric `200` or `0`, or the strings `"200"` / `"success"`. A `success` flag of
/// `false` always fails, whatever the code says.
public enum GLMEnvelope {

    public static let successCodes: Set<String> = ["200", "0", "success"]

    /// The code in its normalised text form (numbers and numeric strings become their
    /// digits; text is lowercased). Nil when the payload carries no code at all.
    public static func rawCode(in object: [String: Any]) -> String? {
        if let raw = object["code"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty ? nil : trimmed
        }
        if let code = SafeConversion.integer(object["code"]) {
            return String(code)
        }
        if let error = object["error"] as? [String: Any] {
            if let raw = error["code"] as? String, !raw.isEmpty { return raw.lowercased() }
            if let code = SafeConversion.integer(error["code"]) { return String(code) }
        }
        return nil
    }

    public static func isBusinessSuccess(in object: [String: Any]) -> Bool {
        if let flag = object["success"] as? Bool, !flag { return false }
        guard let raw = rawCode(in: object) else { return false }
        return successCodes.contains(raw)
    }

    /// Numeric form of the business code, for the redacted observation line. A text code
    /// like "success" is not a number and stays nil there.
    public static func businessCode(in object: [String: Any]) -> Int? {
        if let code = SafeConversion.integer(object["code"]) { return code }
        if let error = object["error"] as? [String: Any] {
            return SafeConversion.integer(error["code"])
        }
        return nil
    }

    /// Business codes that mirror the HTTP authentication statuses. The evidence-backed
    /// set is deliberately minimal: a body code literally equal to 401/403 means the same
    /// thing the status would. Unknown codes stay neutral business errors (REVIEW round 7
    /// finding 2).
    public static let authenticationBusinessCodes: Set<Int> = [401, 403]

    public static func isAuthenticationBusinessCode(_ code: Int) -> Bool {
        return authenticationBusinessCodes.contains(code)
    }
}

/// What one GLM response contained, classified under the endpoint's schema. Key names,
/// codes and structure only: no upstream text, no values, no key material.
public struct GLMAccountReportObservation: Equatable, Sendable {
    public let httpStatus: Int
    public let topLevelKeys: [String]
    public let businessCode: Int?
    /// Amounts the strict parser confirmed under the schema. Candidates only; they are
    /// never rendered unless the schema is confirmed.
    public let candidateBalances: [ProviderBalance]
    public let parseFailure: ProviderFailure?
    /// The schema the response was classified under; nil when no schema could apply
    /// (transport failure, non-2xx status, unparseable body).
    public let schema: GLMSchema?
    /// Redacted structure evidence: `path: type` entries, depth ≤ 3, count capped. Never
    /// carries values, array contents, upstream messages, keys or cookies.
    public let structureSummary: [String]

    public init(httpStatus: Int,
                topLevelKeys: [String],
                businessCode: Int?,
                candidateBalances: [ProviderBalance],
                parseFailure: ProviderFailure?,
                schema: GLMSchema? = nil,
                structureSummary: [String] = []) {
        self.httpStatus = httpStatus
        self.topLevelKeys = topLevelKeys
        self.businessCode = businessCode
        self.candidateBalances = candidateBalances
        self.parseFailure = parseFailure
        self.schema = schema
        self.structureSummary = structureSummary
    }

    /// True when the payload parsed cleanly under a confirmed schema, so amounts may be
    /// shown. The single point where a parsed response becomes display data.
    public var isDisplayable: Bool {
        guard let schema, GLMContract.isConfirmed(schema) else { return false }
        return parseFailure == nil && !candidateBalances.isEmpty
    }
}

/// Response → observation classification for both GLM endpoints.
public enum GLMAccountReportParser {

    /// Classifies a raw HTTP outcome under `schema`. Only a 2xx body is parsed; a
    /// rejection keeps its real status (401/403 are credential rejections, anything else
    /// is a server error), so the published observation always says what actually happened
    /// on the wire. A business-successful body that matches no known shape is recorded
    /// with a redacted structure summary, never rendered as a balance.
    public static func observe(response: ProviderHTTPResponse, schema: GLMSchema) -> GLMAccountReportObservation {
        guard response.isOK else {
            let failure: ProviderFailure
            if response.status == 401 || response.status == 403 {
                failure = .invalidCredential
            } else {
                failure = .serverError(status: response.status)
            }
            return GLMAccountReportObservation(httpStatus: response.status, topLevelKeys: [],
                                               businessCode: nil, candidateBalances: [],
                                               parseFailure: failure)
        }
        return observe(data: response.body, httpStatus: response.status, schema: schema)
    }

    /// Builds an observation without ever throwing: a payload the parser does not
    /// recognise is recorded as an observation with structure evidence, not rendered as a
    /// balance.
    public static func observe(data: Data, httpStatus: Int, schema: GLMSchema) -> GLMAccountReportObservation {
        guard let object = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) else {
            return GLMAccountReportObservation(httpStatus: httpStatus, topLevelKeys: [],
                                               businessCode: nil, candidateBalances: [],
                                               parseFailure: .unexpectedResponse)
        }
        let keys = (object as? [String: Any])?.keys.sorted() ?? []
        let summary = structureSummary(of: object)

        guard let object = object as? [String: Any] else {
            // A JSON array or scalar root is not a shape any schema describes.
            return GLMAccountReportObservation(httpStatus: httpStatus, topLevelKeys: keys,
                                               businessCode: nil, candidateBalances: [],
                                               parseFailure: .unexpectedResponse,
                                               schema: schema, structureSummary: summary)
        }

        // HTTP 200 can still carry a business error, so the envelope is read first. A
        // payload with no code at all is not a business error; it is a shape the app does
        // not know, recorded with its structure evidence.
        if !GLMEnvelope.isBusinessSuccess(in: object) {
            let code = GLMEnvelope.businessCode(in: object)
            let failure: ProviderFailure
            if let code, GLMEnvelope.isAuthenticationBusinessCode(code) {
                // An HTTP 200 body whose business code is an authentication code (401/403)
                // is a credential rejection, not a neutral business error: it suspends
                // automatic retry exactly like a real 401/403 status (REVIEW round 7).
                failure = .invalidCredential
            } else if GLMEnvelope.rawCode(in: object) != nil || object["error"] != nil {
                failure = .businessError(code: code ?? -1)
            } else {
                failure = .unexpectedResponse
            }
            return GLMAccountReportObservation(httpStatus: httpStatus, topLevelKeys: keys,
                                               businessCode: code,
                                               candidateBalances: [],
                                               parseFailure: failure,
                                               schema: schema, structureSummary: summary)
        }

        // The strict parse decodes the raw body straight through JSONDecoder: a
        // JSONSerialization object round trip would corrupt number literals (66.6
        // re-encodes as 66.599999999999994 on this Foundation, verified empirically).
        // The JSONSerialization object is passed alongside for the strict null checks.
        let parsed: Result<[ProviderBalance], ProviderFailure>
        switch schema {
        case .apiBalanceV1:
            parsed = GLMBalanceParser.parse(data: data, object: object)
        case .consoleReportV1:
            parsed = GLMConsoleReportParser.parse(data: data, object: object)
        }
        switch parsed {
        case .success(let balances):
            return GLMAccountReportObservation(httpStatus: httpStatus, topLevelKeys: keys,
                                               businessCode: GLMEnvelope.businessCode(in: object),
                                               candidateBalances: balances,
                                               parseFailure: nil,
                                               schema: schema, structureSummary: summary)
        case .failure(let failure):
            return GLMAccountReportObservation(httpStatus: httpStatus, topLevelKeys: keys,
                                               businessCode: GLMEnvelope.businessCode(in: object),
                                               candidateBalances: [],
                                               parseFailure: failure,
                                               schema: schema, structureSummary: summary)
        }
    }

    // MARK: Structure summary

    /// Redacted structural summary: JSON paths and types only, at most `maxDepth` levels
    /// deep and `maxEntries` entries. Never values, array contents (only the first
    /// element's shape), upstream messages, keys or cookies (Round 7 requirement 2).
    public static func structureSummary(of value: Any,
                                        maxDepth: Int = 3,
                                        maxEntries: Int = 24) -> [String] {
        var entries: [String] = []

        func jsonType(_ v: Any) -> String {
            // Booleans reach JSONSerialization as boxed booleans (a NSNumber subtype), so
            // the boxed check must come first — `NSNumber(1) is Bool` is unreliable.
            if let number = v as? NSNumber {
                return SafeConversion.isBoxedBool(number) ? "boolean" : "number"
            }
            if v is String { return "string" }
            if v is NSNull { return "null" }
            if v is [String: Any] { return "object" }
            if v is [Any] { return "array" }
            return "value"
        }

        func walk(_ v: Any, path: String, depth: Int) {
            guard entries.count < maxEntries else { return }
            if !path.isEmpty {
                entries.append("\(path): \(jsonType(v))")
            }
            guard depth < maxDepth, entries.count < maxEntries else { return }
            if let object = v as? [String: Any] {
                for key in object.keys.sorted() where entries.count < maxEntries {
                    walk(object[key] ?? NSNull(), path: path.isEmpty ? key : "\(path).\(key)", depth: depth + 1)
                }
            } else if let array = v as? [Any], let first = array.first {
                // Element shape only: no contents, no count.
                walk(first, path: "\(path)[]", depth: depth + 1)
            }
        }

        if value is [String: Any] {
            walk(value, path: "", depth: 0)
        } else {
            entries.append("root: \(jsonType(value))")
            walk(value, path: "root", depth: 1)
        }
        return entries
    }
}

/// A JSON amount that may arrive as a number literal or a decimal string, decoded to
/// `Decimal` without any `Double` round trip: the JSONDecoder Decimal path parses the
/// number's source text, so `66.6` stays exactly `66.6` (Round 7 requirement 1). A present
/// but invalid value throws, which the parsers map to a definite failure - never 0.
public struct StrictAmount: Decodable, Sendable {
    public let value: Decimal

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }
        if let text = try? container.decode(String.self) {
            guard let parsed = SafeConversion.decimal(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a strict money literal")
            }
            value = parsed
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "amount must be a number or a decimal string")
    }
}

/// Strict parser for `GET /api/paas/v4/balance` (schema `apiBalanceV1`).
///
/// Known shape (third-party implementations, pending user confirmation):
/// `{"code": 200, "success": true, "msg": "…", "data": {"total_balance": …,
/// "available_balance": …, "currency": "…"}}`. Amounts may be JSON numbers or decimal
/// strings; both convert directly to `Decimal`, never through a `Double`. A missing
/// currency stays nil (币种未确认) — no default is ever invented.
public enum GLMBalanceParser {

    /// The strict decoding shape. Optional fields mean "absent"; a present field that
    /// cannot decode as a strict amount throws, which is a definite failure.
    private struct Payload: Decodable {
        let data: DataObject?
        struct DataObject: Decodable {
            let total_balance: StrictAmount?
            let available_balance: StrictAmount?
            let currency: String?
        }
    }

    public static func parse(data: Data, object: [String: Any]) -> Result<[ProviderBalance], ProviderFailure> {
        // Strict contract: a declared amount field that is present but null is a
        // violation, not an absent field — another field must not mask it
        // (REVIEW round 7 finding 4).
        if let dataObject = object["data"] as? [String: Any] {
            if dataObject["total_balance"] is NSNull || dataObject["available_balance"] is NSNull {
                return .failure(.unexpectedResponse)
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let dataObject = payload.data else {
            return .failure(.unexpectedResponse)
        }
        guard dataObject.total_balance != nil || dataObject.available_balance != nil else {
            return .failure(.unexpectedResponse)
        }
        let total = dataObject.total_balance?.value
        let available = dataObject.available_balance?.value

        // An available-only response keeps total nil: an available balance is never
        // copied into the total slot (REVIEW round 7 finding 3).
        return .success([ProviderBalance(currency: Self.currency(dataObject.currency),
                                         total: total,
                                         available: available)])
    }

    static func currency(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Strict parser for `GET /api/biz/account/query-customer-account-report`
/// (schema `consoleReportV1`).
///
/// Known shape (user probe saw top-level `code/data/msg/success`; nested shape from
/// independent implementations, pending user confirmation): `data.balance` is an object
/// with `balance` (总额), `availableBalance` (可用), `rechargeAmount` (累计充值),
/// `giveAmount` (累计赠送), `totalSpendAmount` (累计消费), `frozenBalance` (冻结金额).
/// Every field keeps its original semantics; the recharge/gift/spend/frozen amounts are
/// carried as labelled amounts and are never bent into DeepSeek's 充值/赠费 vocabulary.
public enum GLMConsoleReportParser {

    private struct Payload: Decodable {
        let data: DataObject?
        struct DataObject: Decodable {
            let balance: BalanceObject?
            let currency: String?
            private enum CodingKeys: String, CodingKey { case balance, currency }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                currency = try container.decodeIfPresent(String.self, forKey: .currency)
                // Official console source reads scalar amounts directly under data.
                // Retain the older nested fixture shape for compatibility.
                if let nested = try? container.decode(BalanceObject.self, forKey: .balance) {
                    balance = nested
                } else {
                    balance = try BalanceObject(from: decoder)
                }
            }
        }
        struct BalanceObject: Decodable {
            let balance: StrictAmount?
            let availableBalance: StrictAmount?
            let rechargeAmount: StrictAmount?
            let giveAmount: StrictAmount?
            let totalSpendAmount: StrictAmount?
            let frozenBalance: StrictAmount?
            let currency: String?
        }
    }

    public static func parse(data: Data, object: [String: Any]) -> Result<[ProviderBalance], ProviderFailure> {
        // Strict contract: a declared amount field that is present but null is a
        // violation (REVIEW round 7 finding 4).
        if let dataObject = object["data"] as? [String: Any] {
            let balance = (dataObject["balance"] as? [String: Any]) ?? dataObject
            let declared = ["balance", "availableBalance", "rechargeAmount",
                            "giveAmount", "totalSpendAmount", "frozenBalance"]
            if declared.contains(where: { balance[$0] is NSNull }) {
                return .failure(.unexpectedResponse)
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let dataObject = payload.data,
              let balance = dataObject.balance else {
            return .failure(.unexpectedResponse)
        }
        guard balance.balance != nil || balance.availableBalance != nil else {
            return .failure(.unexpectedResponse)
        }
        let total = balance.balance?.value
        let available = balance.availableBalance?.value

        // The four extra amounts keep their original semantics as labelled amounts; they
        // are never bent into the 充值/赠费 vocabulary.
        var extras: [ProviderLabeledAmount] = []
        let knownExtras: [(field: String, label: String, amount: StrictAmount?)] = [
            ("rechargeAmount", "累计充值", balance.rechargeAmount),
            ("giveAmount", "累计赠送", balance.giveAmount),
            ("totalSpendAmount", "累计消费", balance.totalSpendAmount),
            ("frozenBalance", "冻结金额", balance.frozenBalance),
        ]
        for known in knownExtras {
            if let amount = known.amount {
                extras.append(ProviderLabeledAmount(field: known.field, label: known.label, amount: amount.value))
            }
        }

        // An available-only response keeps total nil (REVIEW round 7 finding 3).
        let isOfficialFlatShape = (object["data"] as? [String: Any])?["balance"] is NSNumber
            || (object["data"] as? [String: Any])?["balance"] is String
        // Official console renders financeData.balance with ¥ and balanceUnit in 元.
        let currency = GLMBalanceParser.currency(balance.currency)
            ?? GLMBalanceParser.currency(dataObject.currency) ?? (isOfficialFlatShape ? "CNY" : nil)
        return .success([ProviderBalance(currency: currency,
                                         total: total,
                                         available: available,
                                         additionalAmounts: extras.isEmpty ? nil : extras)])
    }
}

extension String {
    /// Lowercased hex SHA-256. Used only for non-secret fingerprints of stored keys.
    var sha256Hex: String {
        SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

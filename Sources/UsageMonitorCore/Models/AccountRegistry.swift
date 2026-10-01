import Foundation

public enum AccountPlatform: String, Codable, CaseIterable, Sendable {
    case chatGPT, google, deepseek, commandcode
    public var title: String {
        switch self { case .chatGPT: return "ChatGPT"; case .google: return "Google / Antigravity"
        case .deepseek: return "DeepSeek"; case .commandcode: return "Command Code" }
    }
    public var apiPlatform: ProviderPlatform? {
        switch self { case .deepseek: return .deepseek; case .commandcode: return .commandcode; default: return nil }
    }
}

/// Local metadata only. Authentication remains owned by the official CLI or Keychain.
public struct ManagedAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let platform: AccountPlatform
    public let ordinal: Int
    public var name: String
    public var codexHomeRelativePath: String?
    public var googleSlot: String?
    public var googleUUID: UUID?
    public var googleEmail: String?
    public var googleVersion: String?
    public var credentialAccount: String?
    public var keyFingerprint: String?
    public var removalPending: Bool = false
    public init(id: String, platform: AccountPlatform, ordinal: Int, name: String) {
        self.id = id; self.platform = platform; self.ordinal = ordinal; self.name = name
    }
    public var profile: ChatGPTAccountProfile? {
        guard platform == .chatGPT, let path = codexHomeRelativePath else { return nil }
        return .init(id: id, displayName: name, shortLabel: ordinal <= 26 ? String(UnicodeScalar(64 + ordinal)!) : "\(ordinal)", codexHomeRelativePath: path)
    }
}

public final class AccountRegistry: @unchecked Sendable {
    public enum Failure: Error { case invalidMetadata, duplicate, missing, invalidName }
    public static let removedSelectionsKey = "accounts.removedSelections.v1"
    public static func storedProfileIDs(defaults: UserDefaults) -> [String] {
        guard let data = defaults.data(forKey: storageKey), let document = try? JSONDecoder().decode(Document.self, from: data) else { return [] }
        return document.accounts.filter { $0.platform == .chatGPT }.map(\.id) + (defaults.stringArray(forKey: removedSelectionsKey) ?? []).filter { $0.hasPrefix("chatgpt-") }
    }
    public static let storageKey = "accounts.registry.v1"
    private struct Document: Codable { var accounts: [ManagedAccount]; var nextOrdinals: [String: Int] }
    private let defaults: UserDefaults
    private let lock = NSRecursiveLock()
    private var document: Document
    public init(defaults: UserDefaults = .standard, legacy: Bool = false,
                googleConnections: [AntigravityConnection] = []) throws {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            document = try JSONDecoder().decode(Document.self, from: data)
            try Self.validate(document.accounts)
        } else {
            document = Document(accounts: [], nextOrdinals: [:])
            if legacy {
                let names = defaults.dictionary(forKey: "detail.displayNames.v1") as? [String: String] ?? [:]
                for (index, profile) in ChatGPTAccountProfile.defaults.enumerated() {
                    var row = ManagedAccount(id: profile.id, platform: .chatGPT, ordinal: index + 1, name: names[profile.id] ?? profile.displayName)
                    row.codexHomeRelativePath = profile.codexHomeRelativePath; document.accounts.append(row)
                }
                for platform in [AccountPlatform.deepseek, .commandcode] {
                    var row = ManagedAccount(id: platform.rawValue, platform: platform, ordinal: 1, name: names[platform.rawValue] ?? platform.title)
                    row.credentialAccount = platform == .deepseek ? "deepseek.api-key" : "commandcode.api-key"
                    document.accounts.append(row)
                }
            }
            let googleNames = defaults.dictionary(forKey: "antigravity.cli.names.v1") as? [String: String] ?? [:]
            for (index, connection) in googleConnections.sorted(by: { $0.slot.rawValue < $1.slot.rawValue }).enumerated() {
                var row = ManagedAccount(id: "google-" + connection.slot.rawValue, platform: .google, ordinal: index + 1,
                                         name: googleNames[connection.email] ?? connection.account.label)
                row.googleSlot = connection.slot.rawValue; row.googleUUID = connection.uuid
                row.googleEmail = connection.email; row.googleVersion = connection.sourceVersion
                document.accounts.append(row)
            }
            for platform in AccountPlatform.allCases {
                document.nextOrdinals[platform.rawValue] = (document.accounts.filter { $0.platform == platform }.map(\.ordinal).max() ?? 0) + 1
            }
            try Self.validate(document.accounts)
            try persist()
        }
    }
    public var accounts: [ManagedAccount] {
        lock.lock(); defer { lock.unlock() }
        return AccountPlatform.allCases.flatMap { platform in document.accounts.filter { $0.platform == platform }.sorted { $0.ordinal < $1.ordinal } }
    }
    public func account(_ id: String) -> ManagedAccount? { accounts.first { $0.id == id } }
    public func draft(_ platform: AccountPlatform, name: String = "") -> ManagedAccount {
        lock.lock(); defer { lock.unlock() }
        let number = document.nextOrdinals[platform.rawValue] ?? 1
        let id = platform.rawValue.lowercased() + "-" + UUID().uuidString.lowercased()
        var row = ManagedAccount(id: id, platform: platform, ordinal: number, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        if row.name.isEmpty { row.name = platform.title + " 账号 \(number)" }
        if platform == .chatGPT { row.codexHomeRelativePath = "Library/Application Support/Minget/CodexProfiles/" + id }
        if platform == .google { row.googleSlot = id }
        if let api = platform.apiPlatform { row.credentialAccount = api.rawValue + ".api-key." + id }
        return row
    }
    public func upsert(_ row: ManagedAccount) throws {
        lock.lock(); defer { lock.unlock() }
        var next = document
        next.accounts.removeAll { $0.id == row.id }; next.accounts.append(row)
        next.nextOrdinals[row.platform.rawValue] = max(next.nextOrdinals[row.platform.rawValue] ?? 1, row.ordinal + 1)
        try Self.validate(next.accounts)
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.storageKey); document = next
    }
    /// Check metadata before a caller mutates the Keychain or starts a connection.
    public func validateForUpsert(_ row: ManagedAccount) throws {
        lock.lock(); defer { lock.unlock() }
        try Self.validate(document.accounts.filter { $0.id != row.id } + [row])
    }
    public func remove(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var next = document
        if let row = next.accounts.first(where: { $0.id == id }) {
            var removed = Set(defaults.stringArray(forKey: Self.removedSelectionsKey) ?? [])
            removed.insert(row.id)
            if let email = row.googleEmail { removed.insert("antigravity:" + Data(email.utf8).base64EncodedString()) }
            if row.platform == .deepseek && row.id != "deepseek" { removed.insert("api:" + row.id) }
            defaults.set(Array(removed), forKey: Self.removedSelectionsKey)
        }
        next.accounts.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(next); defaults.set(data, forKey: Self.storageKey); document = next
    }
    private func persist() throws { defaults.set(try JSONEncoder().encode(document), forKey: Self.storageKey) }
    private static func validate(_ rows: [ManagedAccount]) throws {
        guard Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ !$0.id.isEmpty && $0.id.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil && $0.ordinal > 0 && !$0.name.isEmpty && $0.name.count <= 40 }),
              Set(rows.compactMap(\.credentialAccount)).count == rows.compactMap(\.credentialAccount).count,
              Set(rows.compactMap(\.googleSlot)).count == rows.compactMap(\.googleSlot).count,
              Set(rows.compactMap(\.googleUUID)).count == rows.compactMap(\.googleUUID).count,
              Set(rows.compactMap(\.googleEmail)).count == rows.compactMap(\.googleEmail).count,
              rows.allSatisfy({ row in
                  if let api = row.platform.apiPlatform {
                      return row.credentialAccount == api.rawValue + ".api-key." + row.id || (row.id == api.rawValue && row.credentialAccount == api.rawValue + ".api-key")
                  }
                  if row.platform == .google {
                      return row.googleEmail != nil && row.googleSlot != nil && row.googleUUID != nil && row.googleVersion == AntigravityCLILocator.version && row.googleEmail.flatMap(AntigravityTerminal.normalizedEmail) == row.googleEmail
                  }
                  return true
              }),
              rows.allSatisfy({ row in
                  guard let path = row.codexHomeRelativePath else { return row.platform != .chatGPT }
                  return row.platform == .chatGPT && !path.hasPrefix("/") && !path.split(separator: "/").contains("..") && ((row.id == "chatgpt-a" && path == ".codex-minget-a") || (row.id == "chatgpt-b" && path == ".codex-minget-b") || path == "Library/Application Support/Minget/CodexProfiles/" + row.id)
              }) else { throw Failure.invalidMetadata }
    }
}

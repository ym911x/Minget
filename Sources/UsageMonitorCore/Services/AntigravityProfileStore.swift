import Foundation

public struct AntigravitySlot: RawRepresentable, Codable, Hashable, CaseIterable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let a = Self(rawValue: "A"), b = Self(rawValue: "B")
    public static let allCases: [Self] = [.a, .b]
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
}

public struct AntigravityConnection: Codable, Equatable, Sendable {
    public let slot: AntigravitySlot
    public let uuid: UUID
    public let email: String
    public let sourceVersion: String
    public var account: AntigravityAccount {
        AntigravityAccount(id: email, authIndex: uuid.uuidString, label: "Google 账号 \(slot.rawValue)",
                          email: email, projectID: nil, disabled: false, unavailable: false)
    }
}

/// Only connections.json is read here. All other files are opaque CLI-owned data.
public final class AntigravityProfileStore: @unchecked Sendable {
    public enum Failure: Error { case duplicateIdentity, invalidIdentity, invalidProfile }
    public let base: URL
    private let lock = NSRecursiveLock()
    private let registry: AccountRegistry?
    public var pendingAccount: ManagedAccount?
    public init(base: URL = AntigravityCLILocator.base, registry: AccountRegistry? = nil) { self.base = base.resolvingSymlinksInPath(); self.registry = registry }
    private var metadata: URL { base.appendingPathComponent("connections.json") }
    private var profiles: URL { base.appendingPathComponent("profiles", isDirectory: true) }
    public func home(_ uuid: UUID) -> URL { base.appendingPathComponent("profiles/\(uuid.uuidString)") }
    public func connections() throws -> [AntigravityConnection] {
        lock.lock(); defer { lock.unlock() }
        return try readConnections()
    }
    private func readConnections() throws -> [AntigravityConnection] {
        if let registry {
            return registry.accounts.filter { $0.platform == .google }.compactMap { row in
                guard let slot = row.googleSlot, let uuid = row.googleUUID, let email = row.googleEmail, let version = row.googleVersion else { return nil }
                return AntigravityConnection(slot: .init(rawValue: slot), uuid: uuid, email: email, sourceVersion: version)
            }
        }
        guard FileManager.default.fileExists(atPath: metadata.path) else { return [] }
        guard metadata.resolvingSymlinksInPath().path == metadata.path,
              profiles.resolvingSymlinksInPath().path == profiles.path,
              let size = try FileManager.default.attributesOfItem(atPath: metadata.path)[.size] as? NSNumber,
              size.intValue <= 65_536 else { throw Failure.invalidProfile }
        let rows = try JSONDecoder().decode([AntigravityConnection].self, from: Data(contentsOf: metadata))
        guard Set(rows.map(\.slot)).count == rows.count,
              Set(rows.map(\.uuid)).count == rows.count, Set(rows.map(\.email)).count == rows.count,
              rows.allSatisfy({ AntigravityTerminal.normalizedEmail($0.email) == $0.email && $0.sourceVersion == AntigravityCLILocator.version && home($0.uuid).resolvingSymlinksInPath().path == home($0.uuid).path }) else {
            throw Failure.invalidIdentity
        }
        return rows
    }
    public func prepare(_ uuid: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        guard profiles.resolvingSymlinksInPath().path == profiles.path,
              home(uuid).resolvingSymlinksInPath().path == home(uuid).path else { throw Failure.invalidProfile }
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: profiles.path)
        try AntigravityCLIEnvironment(executable: AntigravityCLILocator.executable, home: home(uuid)).prepare()
    }
    public func commit(slot: AntigravitySlot, uuid: UUID, email: String) throws -> AntigravityConnection {
        lock.lock(); defer { lock.unlock() }
        guard let email = AntigravityTerminal.normalizedEmail(email) else { throw Failure.invalidIdentity }
        guard home(uuid).resolvingSymlinksInPath().path == home(uuid).path,
              FileManager.default.fileExists(atPath: home(uuid).path) else { throw Failure.invalidProfile }
        var rows = try readConnections()
        guard !rows.contains(where: { $0.slot != slot && ($0.email == email || $0.uuid == uuid) }) else { throw Failure.duplicateIdentity }
        let new = AntigravityConnection(slot: slot, uuid: uuid, email: email, sourceVersion: AntigravityCLILocator.version)
        rows.removeAll { $0.slot == slot }; rows.append(new)
        if let registry {
            var row = registry.accounts.first { $0.googleSlot == slot.rawValue } ?? pendingAccount ?? registry.draft(.google)
            row.googleSlot = slot.rawValue; row.googleUUID = uuid; row.googleEmail = email; row.googleVersion = new.sourceVersion
            try registry.upsert(row)
        } else { try save(rows) }
        return new
    }
    public func disconnect(_ connection: AntigravityConnection) throws {
        lock.lock(); defer { lock.unlock() }
        pendingAccount = nil
        let rows = try readConnections().filter { $0.uuid != connection.uuid }
        // Delete only the exact UUID directory; reject symlink substitution of its ancestors.
        try removeProfile(connection.uuid)
        if let registry, let row = registry.accounts.first(where: { $0.googleSlot == connection.slot.rawValue }) { try registry.remove(row.id) }
        else { try save(rows) }
    }
    public func removeProfile(_ uuid: UUID) throws {
        let directory = home(uuid)
        guard directory.resolvingSymlinksInPath().path == directory.path,
              base.appendingPathComponent("profiles").resolvingSymlinksInPath().path == base.appendingPathComponent("profiles").path else {
            throw Failure.invalidProfile
        }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func save(_ rows: [AntigravityConnection]) throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        try JSONEncoder().encode(rows).write(to: metadata, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path)
    }
}

import Foundation

public enum AntigravitySlot: String, Codable, CaseIterable, Sendable { case a = "A", b = "B" }

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
    public init(base: URL = AntigravityCLILocator.base) { self.base = base.resolvingSymlinksInPath() }
    private var metadata: URL { base.appendingPathComponent("connections.json") }
    private var profiles: URL { base.appendingPathComponent("profiles", isDirectory: true) }
    public func home(_ uuid: UUID) -> URL { base.appendingPathComponent("profiles/\(uuid.uuidString)") }
    public func connections() throws -> [AntigravityConnection] {
        lock.lock(); defer { lock.unlock() }
        return try readConnections()
    }
    private func readConnections() throws -> [AntigravityConnection] {
        guard FileManager.default.fileExists(atPath: metadata.path) else { return [] }
        guard metadata.resolvingSymlinksInPath().path == metadata.path,
              profiles.resolvingSymlinksInPath().path == profiles.path,
              let size = try FileManager.default.attributesOfItem(atPath: metadata.path)[.size] as? NSNumber,
              size.intValue <= 65_536 else { throw Failure.invalidProfile }
        let rows = try JSONDecoder().decode([AntigravityConnection].self, from: Data(contentsOf: metadata))
        guard rows.count <= 2, Set(rows.map(\.slot)).count == rows.count,
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
        try save(rows)
        return new
    }
    public func disconnect(_ connection: AntigravityConnection) throws {
        lock.lock(); defer { lock.unlock() }
        let rows = try readConnections().filter { $0.uuid != connection.uuid }
        // Delete only the exact UUID directory; reject symlink substitution of its ancestors.
        try removeProfile(connection.uuid)
        try save(rows)
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

import Foundation

/// One ChatGPT account profile: the identity a card shows plus the isolated `CODEX_HOME`
/// that one dedicated `codex app-server` child runs under.
///
/// 1.3.0 ships exactly two fixed, read-only profiles and offers no add/remove/rename UI.
/// The type is deliberately extensible — a stable `id`, no dependence on array position —
/// so a later version can add a third profile without touching the business logic
/// (REQUIREMENTS.md §3, §10).
///
/// Only the *relative* path is stored. The absolute `CODEX_HOME` is resolved at the moment
/// a child is about to be launched, so no personal absolute path appears in defaults, logs
/// or public documentation.
public struct ChatGPTAccountProfile: Equatable, Hashable, Sendable, Identifiable, Codable {

    /// Stable, non-sensitive identifier. Business logic keys on this, never on position.
    public let id: String
    /// Name shown in the detail card and the settings window.
    public let displayName: String
    /// Menu bar short label. One visible character by design.
    public let shortLabel: String
    /// Isolated Codex home, relative to the current user's home directory.
    public let codexHomeRelativePath: String

    public init(id: String,
                displayName: String,
                shortLabel: String,
                codexHomeRelativePath: String) {
        self.id = id
        self.displayName = displayName
        self.shortLabel = shortLabel
        self.codexHomeRelativePath = codexHomeRelativePath
    }

    /// The two profiles 1.3.0 always enables, left to right.
    public static let chatGPTA = ChatGPTAccountProfile(
        id: "chatgpt-a",
        displayName: "Codex 账号",
        shortLabel: "A",
        codexHomeRelativePath: ".codex-minget-a")

    public static let chatGPTB = ChatGPTAccountProfile(
        id: "chatgpt-b",
        displayName: "Hermes / OpenClaw 账号",
        shortLabel: "B",
        codexHomeRelativePath: ".codex-minget-b")

    /// Default profile set, in the fixed display order account A, account B.
    public static let defaults: [ChatGPTAccountProfile] = [chatGPTA, chatGPTB]

    /// The isolated Codex home, resolved for the current user only when it is needed.
    ///
    /// `homeDirectory` is injectable so a test can prove the resolution is relative to the
    /// home directory rather than to a baked-in personal path.
    public func codexHomeURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent(codexHomeRelativePath, isDirectory: true)
    }

    /// Last path component of the relative home. The settings window shows this read-only
    /// suffix instead of the user's absolute path.
    public var codexHomeDisplaySuffix: String {
        (codexHomeRelativePath as NSString).lastPathComponent
    }

    /// Lookup by stable identifier. Returns nil for an unknown id, so a caller can never
    /// silently fall back to a different account.
    public static func profile(withID id: String,
                               in profiles: [ChatGPTAccountProfile] = defaults) -> ChatGPTAccountProfile? {
        profiles.first { $0.id == id }
    }
}

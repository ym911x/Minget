import Foundation
import Combine
import UsageMonitorCore

/// User-facing names for the four fixed detail-page sources.
///
/// Names are display metadata only. The stable service/profile IDs remain the keys used by
/// refresh, cache, menu-bar selection and fire scheduling. No credential or account data is
/// stored here.
public final class DisplayNamePreferences: ObservableObject {

    public static let shared = DisplayNamePreferences()
    public static let maximumLength = 40

    enum ServiceID {
        static let deepSeek = "deepseek"
        static let commandCode = "commandcode"

        static var all: [String] {
            ChatGPTAccountProfile.defaults.map(\.id) + [deepSeek, commandCode]
        }
    }

    private enum Key {
        static let names = "detail.displayNames.v1"
    }

    private let defaults: UserDefaults
    private let defaultNames: [String: String]

    @Published private(set) var names: [String: String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let defaultNames = Self.makeDefaultNames()
        self.defaultNames = defaultNames

        let stored = defaults.dictionary(forKey: Key.names) as? [String: String] ?? [:]
        var loadedNames: [String: String] = [:]
        for item in stored {
            guard ServiceID.all.contains(item.key),
                  Self.isValid(item.value) else { continue }
            let trimmed = Self.normalized(item.value)
            if !trimmed.isEmpty, trimmed != defaultNames[item.key] {
                loadedNames[item.key] = trimmed
            }
        }
        self.names = loadedNames
    }

    public func displayName(for serviceID: String) -> String {
        names[serviceID] ?? defaultName(for: serviceID)
    }

    public func defaultName(for serviceID: String) -> String {
        defaultNames[serviceID] ?? serviceID
    }

    public var customizedServiceIDs: Set<String> { Set(names.keys) }

    /// Saves a trimmed display name. Empty input restores the source default.
    /// Returns false when the value exceeds the documented 40-character limit.
    @discardableResult
    public func setDisplayName(_ rawValue: String, for serviceID: String) -> Bool {
        guard ServiceID.all.contains(serviceID) else { return false }
        let value = Self.normalized(rawValue)
        guard Self.isValid(value) else { return false }

        if value.isEmpty || value == defaultName(for: serviceID) {
            names.removeValue(forKey: serviceID)
        } else {
            names[serviceID] = value
        }
        persist()
        return true
    }

    public func resetDisplayName(for serviceID: String) {
        guard ServiceID.all.contains(serviceID) else { return }
        names.removeValue(forKey: serviceID)
        persist()
    }

    public func resetAll() {
        names.removeAll()
        persist()
    }

    private func persist() {
        if names.isEmpty {
            defaults.removeObject(forKey: Key.names)
        } else {
            defaults.set(names, forKey: Key.names)
        }
    }

    private static func makeDefaultNames() -> [String: String] {
        var result = Dictionary(uniqueKeysWithValues: ChatGPTAccountProfile.defaults.map {
            ($0.id, $0.displayName)
        })
        result[ServiceID.deepSeek] = "DeepSeek"
        result[ServiceID.commandCode] = "Command Code"
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValid(_ value: String) -> Bool {
        value.count <= maximumLength
    }
}

import Foundation

/// Checks only Minget-owned preference keys. Call before building AppContainer, whose
/// migration may itself write defaults on launch.
enum FirstRunGate {
    static let key = "onboarding.presented.v1"
    static let legacyPrefixes = ["UsageMonitor.", "detail.", "menubar.", "fireSchedule.", "displayName."]

    static func shouldPresent(defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: key) { return false }
        return !defaults.dictionaryRepresentation().keys.contains { storedKey in
            legacyPrefixes.contains { storedKey.hasPrefix($0) }
        }
    }

    static func markPresented(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}

import Foundation
import Combine
import UsageMonitorCore

enum FireScheduleTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatGPTA = "chatgpt-a"
    case chatGPTB = "chatgpt-b"
    case commandCode = "commandcode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatGPTA: return "OpenAI 账号 A"
        case .chatGPTB: return "OpenAI 账号 B"
        case .commandCode: return "Command Code"
        }
    }

    var profileID: String? {
        switch self {
        case .chatGPTA, .chatGPTB: return rawValue
        case .commandCode: return nil
        }
    }
}

struct FireScheduleEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let target: FireScheduleTarget
    var minuteOfDay: Int
    var isEnabled: Bool

    init(id: UUID = UUID(), target: FireScheduleTarget, minuteOfDay: Int, isEnabled: Bool = false) {
        self.id = id
        self.target = target
        self.minuteOfDay = min(max(minuteOfDay, 0), 23 * 60 + 59)
        self.isEnabled = isEnabled
    }
}

struct DueFireOccurrence: Equatable, Sendable {
    let entry: FireScheduleEntry
    let scheduledAt: Date
}

struct CommandCodeFireViewState: Equatable, Sendable {
    var isFiring = false
    var result: ChatGPTFireResult?
    var driftSeconds: TimeInterval?
    var history: [FireHistoryEntry] = []

    var resultText: String { result?.displayText ?? "" }

    var driftText: String? {
        guard let result, let driftSeconds else { return nil }
        switch result {
        case .requestSucceededWindowConfirmed, .requestSucceededWindowUnchanged:
            return FireWindowDrift.displayText(driftSeconds)
        default:
            return nil
        }
    }

    var statusText: String {
        guard !resultText.isEmpty else { return "" }
        guard let driftText else { return resultText }
        return "\(resultText) · \(driftText)"
    }

    mutating func start() {
        isFiring = true
        result = nil
        driftSeconds = nil
    }

    mutating func finish(_ result: ChatGPTFireResult,
                         driftSeconds: TimeInterval?,
                         finishedAt: Date = Date()) {
        isFiring = false
        self.result = result
        self.driftSeconds = driftSeconds
        history.insert(FireHistoryEntry(result: result,
                                        finishedAt: finishedAt,
                                        driftSeconds: driftSeconds), at: 0)
        if history.count > 3 { history = Array(history.prefix(3)) }
    }
}

/// Non-secret daily fire preferences and their duplicate-suppression ledger.
///
/// Schedules are local-wall-clock values. A due time may be caught up for ten minutes after
/// wake/start; anything older is skipped, because silently moving a five-hour window by hours
/// would be more surprising than missing it. The last scheduled occurrence is persisted per
/// row so app relaunches and repeated clock ticks cannot execute it twice.
@MainActor
public final class FireSchedulePreferences: ObservableObject {
    public static let shared = FireSchedulePreferences()
    nonisolated static let catchUpWindow: TimeInterval = 10 * 60

    private enum Key {
        static let entries = "fireSchedule.entries.v1"
        static let lastOccurrences = "fireSchedule.lastOccurrences.v1"
    }

    @Published private(set) var entries: [FireScheduleEntry]

    private let defaults: UserDefaults
    private var lastOccurrences: [String: TimeInterval]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.entries),
           let decoded = try? JSONDecoder().decode([FireScheduleEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
        lastOccurrences = defaults.dictionary(forKey: Key.lastOccurrences)?
            .compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
        normalizeAndPersist()
    }

    func entries(for target: FireScheduleTarget) -> [FireScheduleEntry] {
        entries.filter { $0.target == target }
            .sorted { lhs, rhs in
                lhs.minuteOfDay == rhs.minuteOfDay
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.minuteOfDay < rhs.minuteOfDay
            }
    }

    @discardableResult
    func add(target: FireScheduleTarget, preferredMinute: Int = 9 * 60) -> UUID {
        let used = Set(entries(for: target).map(\.minuteOfDay))
        var minute = min(max(preferredMinute, 0), 23 * 60 + 59)
        for _ in 0..<(24 * 60) {
            if !used.contains(minute) { break }
            minute = (minute + 1) % (24 * 60)
        }
        let entry = FireScheduleEntry(target: target, minuteOfDay: minute)
        entries.append(entry)
        persistEntries()
        return entry.id
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        lastOccurrences[id.uuidString] = nil
        persistEntries()
        persistOccurrences()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        update(id) { $0.isEnabled = enabled }
    }

    func setMinute(_ minute: Int, for id: UUID) {
        update(id) { $0.minuteOfDay = min(max(minute, 0), 23 * 60 + 59) }
    }

    func dueOccurrences(at now: Date,
                        calendar: Calendar = .current,
                        catchUpWindow: TimeInterval = FireSchedulePreferences.catchUpWindow) -> [DueFireOccurrence] {
        guard catchUpWindow > 0 else { return [] }
        return entries.compactMap { entry in
            guard entry.isEnabled else { return nil }
            let hour = entry.minuteOfDay / 60
            let minute = entry.minuteOfDay % 60
            guard let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
                return nil
            }
            let lateness = now.timeIntervalSince(scheduled)
            guard lateness >= 0, lateness < catchUpWindow else { return nil }
            if let previous = lastOccurrences[entry.id.uuidString],
               scheduled.timeIntervalSince1970 <= previous + 0.5 {
                return nil
            }
            return DueFireOccurrence(entry: entry, scheduledAt: scheduled)
        }
        .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func markFired(_ occurrence: DueFireOccurrence) {
        lastOccurrences[occurrence.entry.id.uuidString] = occurrence.scheduledAt.timeIntervalSince1970
        persistOccurrences()
    }

    func hasSubFiveHourGap(for target: FireScheduleTarget) -> Bool {
        let enabled = entries(for: target).filter(\.isEnabled).map(\.minuteOfDay)
        guard enabled.count > 1 else { return false }
        let sorted = enabled.sorted()
        let wrapped = sorted + [sorted[0] + 24 * 60]
        return zip(wrapped, wrapped.dropFirst()).contains { pair in pair.1 - pair.0 < 5 * 60 }
    }

    private func update(_ id: UUID, mutate: (inout FireScheduleEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
        persistEntries()
    }

    private func normalizeAndPersist() {
        entries = entries.map {
            FireScheduleEntry(id: $0.id, target: $0.target,
                              minuteOfDay: $0.minuteOfDay, isEnabled: $0.isEnabled)
        }
        persistEntries()
    }

    private func persistEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Key.entries)
        }
        objectWillChange.send()
    }

    private func persistOccurrences() {
        defaults.set(lastOccurrences, forKey: Key.lastOccurrences)
    }
}

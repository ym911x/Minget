import XCTest
@testable import UsageMonitorApp

@MainActor
final class FireSchedulePreferencesTests: XCTestCase {
    private func defaults(_ label: String) -> UserDefaults {
        let name = "UsageMonitorAppTests.FireSchedules.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func date(_ text: String, timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private func calendar(_ timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    func testMultipleTargetsTimesAndChecksPersistWithoutSecrets() throws {
        let store = defaults("persist")
        let first = FireSchedulePreferences(defaults: store)
        let a = first.add(target: .chatGPTA, preferredMinute: 8 * 60 + 15)
        let b = first.add(target: .chatGPTA, preferredMinute: 13 * 60 + 45)
        let command = first.add(target: .commandCode, preferredMinute: 21 * 60)
        first.setEnabled(true, for: a)
        first.setEnabled(true, for: command)

        let restored = FireSchedulePreferences(defaults: store)
        XCTAssertEqual(restored.entries(for: .chatGPTA).map(\.minuteOfDay), [495, 825])
        XCTAssertEqual(restored.entries(for: .chatGPTA).map(\.isEnabled), [true, false])
        XCTAssertEqual(restored.entries(for: .commandCode).first?.id, command)
        XCTAssertFalse(String(data: try XCTUnwrap(store.data(forKey: "fireSchedule.entries.v1")),
                              encoding: .utf8)?.contains("API") ?? true)
        XCTAssertNotEqual(a, b)
    }

    func testDueOccurrenceCatchesUpTenMinutesAndThenStops() {
        let prefs = FireSchedulePreferences(defaults: defaults("due"))
        let id = prefs.add(target: .chatGPTB, preferredMinute: 9 * 60)
        prefs.setEnabled(true, for: id)
        let cal = calendar()

        XCTAssertEqual(prefs.dueOccurrences(at: date("2026-09-19 09:09:59"), calendar: cal).count, 1)
        XCTAssertTrue(prefs.dueOccurrences(at: date("2026-09-19 09:10:00"), calendar: cal).isEmpty)
        XCTAssertTrue(prefs.dueOccurrences(at: date("2026-09-19 08:59:59"), calendar: cal).isEmpty)
    }

    func testMarkingAnOccurrenceSuppressesTicksAndRelaunchForThatDay() {
        let store = defaults("dedupe")
        let prefs = FireSchedulePreferences(defaults: store)
        let id = prefs.add(target: .commandCode, preferredMinute: 9 * 60)
        prefs.setEnabled(true, for: id)
        let now = date("2026-09-19 09:00:30")
        let due = prefs.dueOccurrences(at: now, calendar: calendar())
        XCTAssertEqual(due.count, 1)
        prefs.markFired(due[0])
        XCTAssertTrue(prefs.dueOccurrences(at: date("2026-09-19 09:05:00"), calendar: calendar()).isEmpty)

        let restored = FireSchedulePreferences(defaults: store)
        XCTAssertTrue(restored.dueOccurrences(at: date("2026-09-19 09:09:59"), calendar: calendar()).isEmpty)
        XCTAssertEqual(restored.dueOccurrences(at: date("2026-09-20 09:00:01"), calendar: calendar()).count, 1)
    }

    func testDisabledRowsNeverRunAndRemovingDeletesTheRow() {
        let prefs = FireSchedulePreferences(defaults: defaults("disabled"))
        let id = prefs.add(target: .chatGPTA, preferredMinute: 9 * 60)
        XCTAssertTrue(prefs.dueOccurrences(at: date("2026-09-19 09:00:01"), calendar: calendar()).isEmpty)
        prefs.remove(id)
        XCTAssertTrue(prefs.entries(for: .chatGPTA).isEmpty)
    }

    func testSubFiveHourWarningIncludesTheMidnightWrap() {
        let prefs = FireSchedulePreferences(defaults: defaults("warning"))
        let late = prefs.add(target: .chatGPTA, preferredMinute: 23 * 60)
        let early = prefs.add(target: .chatGPTA, preferredMinute: 2 * 60)
        prefs.setEnabled(true, for: late)
        prefs.setEnabled(true, for: early)
        XCTAssertTrue(prefs.hasSubFiveHourGap(for: .chatGPTA))
        XCTAssertFalse(prefs.hasSubFiveHourGap(for: .commandCode))
    }

    func testAddingAtTheSameMinuteChoosesANonDuplicateMinute() {
        let prefs = FireSchedulePreferences(defaults: defaults("duplicates"))
        _ = prefs.add(target: .commandCode, preferredMinute: 540)
        _ = prefs.add(target: .commandCode, preferredMinute: 540)
        XCTAssertEqual(prefs.entries(for: .commandCode).map(\.minuteOfDay), [540, 541])
    }
}

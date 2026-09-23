import XCTest
import Foundation
@testable import UsageMonitorCore
@testable import UsageMonitorApp

/// Command Code fire coverage at the view-model boundary. The executable and network are
/// both local fakes: these tests never spend credits or use a real Keychain item.
@MainActor
final class CommandCodeFireLifecycleTests: XCTestCase {
    private final class RecordingTransport: ProviderTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URLRequest] = []
        private var creditsReads = 0
        let oldReset: Date
        let newReset: Date

        init(oldReset: Date, newReset: Date) {
            self.oldReset = oldReset
            self.newReset = newReset
        }

        var recordedRequests: [URLRequest] { lock.withLock { requests } }

        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            let path = request.url?.path
            let creditsRead: Int = lock.withLock {
                requests.append(request)
                if path == CommandCodeProvider.creditsPath { creditsReads += 1 }
                return creditsReads
            }
            switch path {
            case CommandCodeProvider.creditsPath:
                // The initial provider read sees the old reset. The first post-CLI
                // confirmation sees the moved reset and can finish without a retry.
                let reset = creditsRead == 1 ? oldReset : newReset
                return response("""
                {"credits":{},"windowLimits":{"fiveHour":{"cap":4,"used":1,"resetAt":\(reset.timeIntervalSince1970)}}}
                """)
            case CommandCodeProvider.summaryPath:
                return response("{\"totalTokens\":10,\"totalCount\":1}")
            case CommandCodeProvider.subscriptionsPath:
                return response("{\"success\":true,\"data\":{\"planId\":\"individual-go\"}}")
            default:
                throw ProviderTransportError.pathNotAllowed
            }
        }

        private func response(_ body: String) -> ProviderHTTPResponse {
            ProviderHTTPResponse(status: 200, body: Data(body.utf8))
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minget-commandcode-life-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    private func defaults(_ label: String) -> UserDefaults {
        let suite = "UsageMonitorAppTests.CommandCodeFire.\(label).\(UUID().uuidString)"
        let value = UserDefaults(suiteName: suite)!
        value.removePersistentDomain(forName: suite)
        return value
    }

    private func successfulCLI() throws -> URL {
        let url = directory.appendingPathComponent("command-code")
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func emptyCoordinator() -> CodexProfilesCoordinator {
        CodexProfilesCoordinator(profiles: []) { _ in
            fatalError("no ChatGPT profile is used by Command Code fire tests")
        }
    }

    private func waitForResult(_ model: UsageViewModel,
                               timeout: TimeInterval = 3) async -> ChatGPTFireResult? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !model.commandCodeFireState.isFiring,
               let result = model.commandCodeFireState.result {
                return result
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return model.commandCodeFireState.result
    }

    func testSuccessfulCLIFireConfirmsWithCreditsOnlyAndRecordsDrift() async throws {
        let oldReset = Date(timeIntervalSince1970: 1_800_000_000)
        let movedReset = oldReset.addingTimeInterval(5 * 3600)
        let transport = RecordingTransport(oldReset: oldReset, newReset: movedReset)
        let credentialStore = InMemoryCredentialStore()
        credentialStore.seed("synthetic-command-key", for: .commandCodeAPIKey)
        let reading = CommandCodeReading(provider: CommandCodeProvider(transport: transport),
                                         credentials: credentialStore)
        await reading.primeCredentialState()
        let testDefaults = defaults("success")
        let engine = ProviderRefreshEngine(readers: [reading],
                                           cache: ProviderCache(userDefaults: testDefaults))
        _ = await engine.refresh(platform: .commandcode, force: true)
        XCTAssertEqual(engine.report(for: .commandcode).connection, .connected)

        let cli = try successfulCLI()
        let fireService = CommandCodeFireService(locator: { _ in cli },
                                                 environment: ["PATH": "/usr/bin:/bin"],
                                                 workingDirectoryBase: directory)
        let model = UsageViewModel(coordinator: emptyCoordinator(),
                                   providerEngine: engine,
                                   menuBarPreferences: MenuBarPreferences(defaults: testDefaults),
                                   commandCodeFireService: fireService,
                                   fireConfirmDelay: 0,
                                   fireRetryDelay: 0)

        XCTAssertTrue(model.fireCommandCode())
        let result = await waitForResult(model)
        XCTAssertEqual(result, .requestSucceededResetAdvanced)
        let drift = try XCTUnwrap(model.commandCodeFireState.driftSeconds)
        XCTAssertEqual(drift, 5 * 3600, accuracy: 0.01)
        XCTAssertEqual(model.commandCodeFireState.history.count, 1)

        let followUp = transport.recordedRequests.dropFirst(3)
        XCTAssertFalse(followUp.isEmpty)
        XCTAssertTrue(followUp.allSatisfy { $0.url?.path == CommandCodeProvider.creditsPath },
                      "confirmation and the cache-window refresh must remain credits-only")
        XCTAssertTrue(followUp.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-command-key"
        })
    }

    func testMissingCredentialFailsWithoutLaunchingCLI() async throws {
        let store = InMemoryCredentialStore()
        let reading = CommandCodeReading(provider: CommandCodeProvider(transport: RecordingTransport(
            oldReset: Date(), newReset: Date().addingTimeInterval(3600))), credentials: store)
        let testDefaults = defaults("missing")
        let engine = ProviderRefreshEngine(readers: [reading],
                                           cache: ProviderCache(userDefaults: testDefaults))
        let launchMarker = directory.appendingPathComponent("launched")
        let cli = directory.appendingPathComponent("must-not-run")
        try "#!/bin/sh\ntouch '\(launchMarker.path)'\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let model = UsageViewModel(coordinator: emptyCoordinator(),
                                   providerEngine: engine,
                                   menuBarPreferences: MenuBarPreferences(defaults: testDefaults),
                                   commandCodeFireService: CommandCodeFireService(locator: { _ in cli },
                                                                                  environment: [:],
                                                                                  workingDirectoryBase: directory),
                                   fireConfirmDelay: 0,
                                   fireRetryDelay: 0)

        XCTAssertTrue(model.fireCommandCode(userInitiated: true))
        let result = await waitForResult(model)
        XCTAssertEqual(result, .credentialUnavailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: launchMarker.path))
        XCTAssertEqual(store.recordedLoads.last?.interaction, .allowed)
    }

    func testScheduledFireUsesBackgroundCredentialPolicy() async throws {
        let store = InMemoryCredentialStore()
        store.simulate(.interactionRequired(-25308), for: .commandCodeAPIKey)
        let reading = CommandCodeReading(provider: CommandCodeProvider(transport: RecordingTransport(
            oldReset: Date(), newReset: Date().addingTimeInterval(3600))), credentials: store)
        let testDefaults = defaults("scheduled")
        let schedule = FireSchedulePreferences(defaults: testDefaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19,
                                                      hour: 8, minute: 5, second: 0))!
        let row = schedule.add(target: .commandCode, preferredMinute: 8 * 60)
        schedule.setEnabled(true, for: row)
        let model = UsageViewModel(coordinator: emptyCoordinator(),
                                   providerEngine: ProviderRefreshEngine(
                                    readers: [reading], cache: ProviderCache(userDefaults: testDefaults)),
                                   menuBarPreferences: MenuBarPreferences(defaults: testDefaults),
                                   commandCodeFireService: CommandCodeFireService(environment: [:]),
                                   fireSchedules: schedule,
                                   fireConfirmDelay: 0,
                                   fireRetryDelay: 0)

        model.evaluateFireSchedules(at: now, calendar: calendar)
        let result = await waitForResult(model)
        XCTAssertEqual(result, .credentialUnavailable)
        XCTAssertEqual(store.recordedLoads.last?.interaction, .disallowed,
                       "a timer-originated fire must never open a Keychain prompt")
        XCTAssertTrue(schedule.dueOccurrences(at: now, calendar: calendar).isEmpty,
                      "the accepted scheduled occurrence must be persisted before the next tick")
    }
}

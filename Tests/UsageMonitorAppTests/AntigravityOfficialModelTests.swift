import XCTest
@testable import UsageMonitorApp
@testable import UsageMonitorCore

private actor OfficialFixtureReader: AntigravityUsageReading {
    var counts: [UUID: Int] = [:]
    var failures: [UUID: ProviderFailure] = [:]
    var cliFailures: [UUID: AntigravityCLIProcess.Failure] = [:]
    func failCLI(_ id: UUID, with failure: AntigravityCLIProcess.Failure) { cliFailures[id] = failure }
    var delays: [UUID: UInt64] = [:]
    var resets: [UUID: Date] = [:]
    func setReset(_ id: UUID, date: Date) { resets[id] = date }
    func configure(_ id: UUID, failure: ProviderFailure? = nil, delay: UInt64 = 0) {
        failures[id] = failure; delays[id] = delay
    }
    func count(_ id: UUID) -> Int { counts[id, default: 0] }
    func read(connection: AntigravityConnection, home: URL) async throws -> AntigravitySnapshot {
        counts[connection.uuid, default: 0] += 1
        let failure = failures[connection.uuid], delay = delays[connection.uuid, default: 0]
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) } // Deliberately ignores cancellation: test late publication.
        if let failure { throw failure }
        if let failure = cliFailures[connection.uuid] { throw failure }
        let data = Data("""
        {"status":"SUCCESS","num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"groups":[{"name":"Synthetic","buckets":[{"id":"5h","window":"5h","remaining_fraction":0}]}]}}}
        """.utf8)
        var groups = try AntigravityCLIReport.parse(data)
        if let reset = resets[connection.uuid] {
            groups = groups.map { group in
                AntigravityQuotaGroup(id: group.id, label: group.label, models: group.models,
                    buckets: group.buckets.map { bucket in
                        AntigravityQuotaBucket(id: bucket.id, label: bucket.label, window: bucket.window,
                            remainingFraction: bucket.remainingFraction, resetsAt: reset)
                    })
            }
        }
        return AntigravitySnapshot(accountIdentity: connection.account.identity, groups: groups, fetchedAt: Date())
    }
}

@MainActor
final class AntigravityOfficialModelTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let store: AntigravityProfileStore
        let defaults: UserDefaults
        let suite: String
        let a: AntigravityConnection
        let b: AntigravityConnection
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("minget-official-test-" + UUID().uuidString)
            store = AntigravityProfileStore(base: root)
            suite = "minget-official-test-" + UUID().uuidString; defaults = UserDefaults(suiteName: suite)!
            let idA = UUID(), idB = UUID(); try store.prepare(idA); try store.prepare(idB)
            a = try store.commit(slot: .a, uuid: idA, email: "a@synthetic.example")
            b = try store.commit(slot: .b, uuid: idB, email: "b@synthetic.example")
        }
        func cleanup() { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        @MainActor func model(_ reader: OfficialFixtureReader) -> AntigravityModel {
            AntigravityModel(credentials: InMemoryCredentialStore(), defaults: defaults, store: store, reader: reader, migrateLegacy: false)
        }
    }
    private func settle(_ model: AntigravityModel) async {
        for _ in 0..<200 {
            if !model.isRefreshing { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Refresh did not settle")
    }
    func testTwoAccountsPublishIndependentlyAndAuthenticationFailureIsIsolated() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let reader = OfficialFixtureReader()
        await reader.configure(f.a.uuid, failure: .invalidCredential)
        await reader.configure(f.b.uuid, delay: 120_000_000)
        let model = f.model(reader); model.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.accounts.first?.failure, .invalidCredential)
        XCTAssertTrue(model.accounts.last?.isFetching == true)
        await settle(model)
        XCTAssertEqual(model.accounts.last?.snapshot?.groups.first?.buckets.first?.remainingFraction, 0)
        model.refresh(force: false, now: Date().addingTimeInterval(400)); await settle(model)
        let aCount = await reader.count(f.a.uuid), bCount = await reader.count(f.b.uuid)
        XCTAssertEqual(aCount, 1); XCTAssertEqual(bCount, 2)
    }
    func testRegionIneligibleAccountHasNoFalseCacheAndDoesNotBreakAnotherAccount() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let reader = OfficialFixtureReader(); await reader.failCLI(f.a.uuid, with: .accountRegionUnavailable)
        let model = f.model(reader); model.start(); await settle(model)
        let restricted = try XCTUnwrap(model.accounts.first)
        XCTAssertEqual(restricted.failure, .accountRegionUnavailable)
        XCTAssertEqual(restricted.statusText, "Google 账号地区不支持 Antigravity")
        XCTAssertNil(restricted.snapshot)
        XCTAssertFalse(restricted.hasCachedData)
        XCTAssertFalse(ProviderFailure.accountRegionUnavailable.isAuthenticationFailure)
        XCTAssertNotNil(model.accounts.last?.snapshot)
        let restored = f.model(reader)
        XCTAssertFalse(restored.accounts.first?.hasCachedData == true)
        XCTAssertTrue(restored.accounts.last?.hasCachedData == true)
    }
    func testManualRequestsQueueExactlyOneFollowUpPerAccount() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let reader = OfficialFixtureReader()
        await reader.configure(f.a.uuid, delay: 50_000_000); await reader.configure(f.b.uuid, delay: 50_000_000)
        let model = f.model(reader); model.start()
        for _ in 0..<10 { model.refresh(force: true) }
        await settle(model)
        let aCount = await reader.count(f.a.uuid), bCount = await reader.count(f.b.uuid)
        XCTAssertEqual(aCount, 2); XCTAssertEqual(bCount, 2)
        model.refresh(force: false); await settle(model)
        let throttled = await reader.count(f.a.uuid); XCTAssertEqual(throttled, 2)
    }
    func testDisconnectWaitsForReadAndRejectsLatePublication() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let reader = OfficialFixtureReader(); await reader.configure(f.a.uuid, delay: 200_000_000)
        let model = f.model(reader); model.start()
        try await Task.sleep(nanoseconds: 10_000_000)
        model.disconnect(.a)
        XCTAssertFalse(model.accounts.contains { $0.id == f.a.email })
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(model.accounts.contains { $0.id == f.a.email })
        XCTAssertEqual(try f.store.connections(), [f.b])
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.home(f.a.uuid).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.store.home(f.b.uuid).path))
    }
    func testCacheBelongsToUUIDAndEmailAndReplacementNeverInheritsIt() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let reader = OfficialFixtureReader(); let model = f.model(reader)
        model.start(); await settle(model)
        let restored = f.model(reader)
        XCTAssertTrue(restored.accounts.allSatisfy { $0.isCached && $0.snapshot != nil })
        let replacement = UUID(); try f.store.prepare(replacement)
        _ = try f.store.commit(slot: .a, uuid: replacement, email: f.a.email)
        let changed = f.model(reader)
        XCTAssertNil(changed.accounts.first?.snapshot)
        XCTAssertNotNil(changed.accounts.last?.snapshot)
    }
    func testResetCrossingTriggersOneReadWithoutFillingQuota() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let reader = OfficialFixtureReader(), now = Date()
        await reader.setReset(f.a.uuid, date: now.addingTimeInterval(10))
        let model = f.model(reader); model.refresh(force: true, now: now); await settle(model)
        model.refresh(force: false, now: now.addingTimeInterval(11)); await settle(model)
        let afterReset = await reader.count(f.a.uuid); XCTAssertEqual(afterReset, 2)
        XCTAssertEqual(model.accounts.first?.snapshot?.groups.first?.buckets.first?.remainingFraction, 0)
        model.refresh(force: false, now: now.addingTimeInterval(12)); await settle(model)
        let repeated = await reader.count(f.a.uuid); XCTAssertEqual(repeated, 2)
    }
    func testFailureRetainsOwnCacheAndStopRejectsOldResults() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let reader = OfficialFixtureReader(); let model = f.model(reader)
        model.start(); await settle(model)
        let old = model.accounts.first?.snapshot
        await reader.configure(f.a.uuid, failure: .serverError(status: 429))
        model.refresh(force: true); await settle(model)
        XCTAssertEqual(model.accounts.first?.snapshot, old)
        XCTAssertTrue(model.accounts.first?.isCached == true)
        await reader.configure(f.a.uuid, delay: 100_000_000)
        model.refresh(force: true); model.stop()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.accounts.first?.snapshot, old)
        XCTAssertFalse(model.isRefreshing)
    }
}

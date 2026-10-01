import XCTest
@testable import UsageMonitorCore

final class AntigravityCLIReportTests: XCTestCase {
    private func report(_ buckets: [[String: Any]]) -> [String: Any] {
        ["status": "SUCCESS", "num_turns": 0,
         "response": "Rounded text is intentionally ignored: 100%",
         "usage": ["input_tokens": 0, "output_tokens": 0, "thinking_tokens": 0,
                   "cache_read_tokens": 0, "total_tokens": 0],
         "command": ["name": "usage", "data": ["groups": [["name": "Synthetic shared group", "buckets": buckets]]]]]
    }
    private func parse(_ value: [String: Any]) throws -> [AntigravityQuotaGroup] {
        try AntigravityCLIReport.parse(JSONSerialization.data(withJSONObject: value))
    }
    func testReadsExactFractionsAndBothWindowsWithoutParsingRoundedText() throws {
        let groups = try parse(report([
            ["id": "week", "name": "Weekly", "window": "weekly", "remaining_fraction": 0.321234,
             "reset_time": "2027-01-01T00:00:00Z"],
            ["id": "five", "window": "5h", "remaining_fraction": 0.765432,
             "reset_time": "2027-01-01T00:00:00.123Z"]]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].buckets.map(\.kind), [.weekly, .fiveHour])
        XCTAssertEqual(groups[0].buckets.map(\.remainingFraction), [0.321234, 0.765432])
        XCTAssertTrue(groups[0].buckets.allSatisfy { $0.resetsAt != nil })
        XCTAssertTrue(groups[0].models.isEmpty)
    }
    func testZeroMissingAndInvalidFieldsRemainDistinct() throws {
        let groups = try parse(report([
            ["id": "zero", "remaining_fraction": 0, "reset_time": "2020-01-01T00:00:00Z"],
            ["id": "missing"], ["id": "boolean", "remaining_fraction": true],
            ["id": "range", "remaining_fraction": 1.1],
            ["id": "string", "remaining_fraction": "0.5", "reset_time": "bad"]]))
        XCTAssertEqual(groups[0].buckets.map(\.remainingFraction), [0, nil, nil, nil, nil])
        XCTAssertTrue(groups[0].buckets.allSatisfy { $0.kind == .unknown })
        XCTAssertNil(groups[0].buckets.last?.resetsAt)
        XCTAssertEqual(groups[0].buckets[0].resetText(), "已到重置时间，等待刷新")
    }
    func testRejectsModelResponsesErrorsAndMissingCommand() {
        for change in [["status": "ERROR"], ["num_turns": 1], ["num_turns": false],
                       ["conversation_id": "synthetic-model-session"],
                       ["command": ["name": "model"]], ["usage": ["total_tokens": 1]],
                       ["error": "failed"]] as [[String: Any]] {
            var root = report([["id": "bucket"]])
            root.merge(change) { _, new in new }
            XCTAssertThrowsError(try parse(root))
        }
    }
    func testRejectsAmbiguousBucketIdentity() {
        XCTAssertThrowsError(try parse(report([["id": "same"], ["id": "same"]])))
        XCTAssertThrowsError(try parse(report([["window": "weekly"]])))
        XCTAssertThrowsError(try parse(report([])))
    }

    func testRejectsDuplicateGroupAndOversizedOutput() throws {
        var root = report([["id": "weekly"]])
        root["command"] = ["name": "usage", "data": ["groups": [
            ["name": "Same", "buckets": [["id": "weekly"]]],
            ["name": "Same", "buckets": [["id": "five"]]]]]]
        XCTAssertThrowsError(try parse(root))
        var data = try JSONSerialization.data(withJSONObject: report([["id": "weekly"]]))
        data.append(Data(repeating: 0x20, count: 1_048_577))
        XCTAssertThrowsError(try AntigravityCLIReport.parse(data))
    }
}

import Foundation
import CoreFoundation

/// Parses the built-in `/usage` command from Google-signed Antigravity CLI 1.2.13.
/// The report has no account identity. Callers must bind it to the isolated login
/// generation that launched the process; never infer an account from quota values.
public enum AntigravityCLIReport {
    public static func parse(_ data: Data) throws -> [AntigravityQuotaGroup] {
        guard data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["status"] as? String == "SUCCESS", root["error"] == nil,
              number(root["num_turns"]) == 0,
              (root["conversation_id"] == nil || root["conversation_id"] is NSNull ||
               root["conversation_id"] as? String == ""),
              let usage = root["usage"] as? [String: Any],
              ["input_tokens", "output_tokens", "thinking_tokens", "cache_read_tokens", "total_tokens"]
                .allSatisfy({ number(usage[$0]) == 0 }),
              let command = root["command"] as? [String: Any], command["name"] as? String == "usage",
              let payload = command["data"] as? [String: Any],
              let groups = payload["groups"] as? [[String: Any]], !groups.isEmpty else {
            throw ProviderFailure.structureUnsupported
        }
        var groupIDs = Set<String>()
        return try groups.map { group in
            guard let name = text(group["name"]), groupIDs.insert(name).inserted,
                  let rawBuckets = group["buckets"] as? [[String: Any]], !rawBuckets.isEmpty else {
                throw ProviderFailure.structureUnsupported
            }
            var bucketIDs = Set<String>()
            let buckets = try rawBuckets.map { bucket -> AntigravityQuotaBucket in
                guard let id = text(bucket["id"]), bucketIDs.insert(id).inserted else {
                    throw ProviderFailure.structureUnsupported
                }
                let fraction = number(bucket["remaining_fraction"]).flatMap { (0...1).contains($0) ? $0 : nil }
                let reset = text(bucket["reset_time"]).flatMap { value -> Date? in
                    let formatter = ISO8601DateFormatter()
                    if let date = formatter.date(from: value) { return date }
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return formatter.date(from: value)
                }
                return AntigravityQuotaBucket(id: id, label: text(bucket["name"]) ?? id,
                    window: text(bucket["window"]), remainingFraction: fraction, resetsAt: reset)
            }
            // The CLI reports shared groups explicitly; its prose model description
            // is not a machine-readable model list and is deliberately not split.
            return AntigravityQuotaGroup(id: name, label: name, models: [], buckets: buckets)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

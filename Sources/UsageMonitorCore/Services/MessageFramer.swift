import Foundation

/// Accumulates raw stdout bytes and emits newline-delimited messages.
///
/// Split chunks, multiple messages in one read and UTF-8 characters split across
/// chunk boundaries are all handled: bytes are only decoded into a String after a
/// full line has been assembled.
public struct MessageFramer: Sendable {
    /// Hard ceiling so a misbehaving child cannot exhaust memory.
    public static let maxLineBytes = 4 * 1024 * 1024

    private var buffer = Data()
    private(set) var overflowed = false

    public init() {}

    /// Append a chunk and return every complete message now available.
    public mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var messages: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            if line.count > Self.maxLineBytes {
                overflowed = true
                continue
            }
            messages.append(line)
        }
        if buffer.count > Self.maxLineBytes {
            // No newline in sight: drop rather than grow without bound.
            overflowed = true
            buffer.removeAll(keepingCapacity: false)
        }
        return messages
    }

    /// Bytes that arrived without a trailing newline. Decoded leniently (never throws).
    public var pendingText: String { String(decoding: buffer, as: UTF8.self) }

    /// Decode one message Data into a JSON object. Returns nil for anything that is
    /// not a JSON object (progress bars, banners, blank lines, invalid JSON).
    public static func decodeObject(_ data: Data) -> [String: Any]? {
        // Parse directly instead of pre-checking with isValidJSONObject: Foundation's
        // pre-check rejects dictionaries that contain NSNull and misjudges slices.
        let trimmed = Data(data.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D })
        guard !trimmed.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: trimmed, options: [.fragmentsAllowed])) as? [String: Any]
    }
}

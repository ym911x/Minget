import Foundation

/// The public service state published by DeepSeek's status page.
///
/// This is deliberately smaller than the provider's incident model. The detail panel needs
/// a compact, honest answer to "今天服务正常吗？" and a link to the official page for the
/// incident timeline. It must never turn an unavailable status page into a green status.
public enum DeepSeekServiceStatus: String, Equatable, Sendable {
    case operational
    case degraded
    case outage
    case maintenance
    case unknown

    public var displayTitle: String {
        switch self {
        case .operational: return "服务正常"
        case .degraded: return "服务有波动"
        case .outage: return "服务中断"
        case .maintenance: return "维护中"
        case .unknown: return "状态暂不可用"
        }
    }
}

/// A single public status-page observation. `checkedAt` is local observation time, not a
/// claim that the provider published an incident at that exact instant.
public struct DeepSeekStatusSnapshot: Equatable, Sendable {
    public let status: DeepSeekServiceStatus
    public let checkedAt: Date

    public init(status: DeepSeekServiceStatus, checkedAt: Date) {
        self.status = status
        self.checkedAt = checkedAt
    }

    public static func unavailable(at date: Date = Date()) -> Self {
        Self(status: .unknown, checkedAt: date)
    }
}

/// Public, unauthenticated status-page reader. It has no access to a provider credential and
/// never calls a model endpoint.
public protocol DeepSeekStatusReading: Sendable {
    func fetchStatus() async throws -> DeepSeekStatusSnapshot
}

/// Reads the current headline from the official DeepSeek status page.
///
/// DeepSeek's public page is a FlashDuty-rendered HTML page rather than the old Atlassian
/// `/api/v2` JSON contract. We intentionally parse only the stable headline phrases and do
/// not scrape provider incident text into the app. When the page changes or cannot be read,
/// the result is `unknown` and the UI offers the official page link.
public struct DeepSeekStatusProvider: DeepSeekStatusReading, Sendable {

    public static let statusPageURL = URL(string: "https://status.deepseek.com/")!
    public static let statusPagePath = "/"
    public static let allowedPaths: Set<String> = [statusPagePath]

    private let client: ProviderHTTPClient
    private let clock: @Sendable () -> Date

    public init(transport: ProviderTransport,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.client = ProviderHTTPClient(baseURL: Self.statusPageURL,
                                         allowedPaths: Self.allowedPaths,
                                         transport: transport,
                                         defaultHeaders: [
                                            "Accept": "text/html, text/plain;q=0.9",
                                            "Accept-Language": "en-US,en;q=0.8",
                                         ])
        self.clock = clock
    }

    public func fetchStatus() async throws -> DeepSeekStatusSnapshot {
        let response: ProviderHTTPResponse
        do {
            response = try await client.get(path: Self.statusPagePath, timeout: 15)
        } catch let transport as ProviderTransportError {
            throw transport
        }
        guard response.isOK else { throw ProviderStatusError.httpStatus(response.status) }
        let text = Self.visibleText(from: response.body)
        guard !text.isEmpty else { throw ProviderStatusError.emptyPage }
        return DeepSeekStatusSnapshot(status: Self.status(in: text), checkedAt: clock())
    }

    /// Exposed for fixture tests and kept pure so parsing can be audited without network
    /// access. It checks the healthy headline first because historical incident text may also
    /// contain words such as "outage" further down the page.
    public static func status(in visibleText: String) -> DeepSeekServiceStatus {
        let text = visibleText.lowercased()
        if containsAny(text, [
            "everything is running smoothly",
            "all systems are operating as expected",
            "all systems operational",
            "一切运行顺利",
            "所有系统运行正常",
        ]) {
            return .operational
        }
        if containsAny(text, [
            "major outage",
            "full outage",
            "critical outage",
            "重大中断",
            "完全中断",
            "服务中断",
        ]) {
            return .outage
        }
        if containsAny(text, [
            "degraded performance",
            "partial outage",
            "some systems are experiencing issues",
            "性能下降",
            "部分中断",
            "服务有波动",
        ]) {
            return .degraded
        }
        if containsAny(text, ["maintenance", "scheduled maintenance", "维护中", "计划维护"]) {
            return .maintenance
        }
        return .unknown
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    /// Turns the HTML response into the small amount of visible text needed by the headline
    /// parser. Scripts and styles are removed first so an embedded historical payload cannot
    /// accidentally become the current status.
    static func visibleText(from data: Data) -> String {
        let source = String(decoding: data, as: UTF8.self)
        let withoutScripts = source.replacingOccurrences(
            of: #"(?is)<(script|style)[^>]*>.*?</\1>"#,
            with: " ",
            options: .regularExpression
        )
        let withoutTags = withoutScripts.replacingOccurrences(
            of: #"(?s)<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ProviderStatusError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case emptyPage
}

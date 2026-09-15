import Foundation

/// Normalized information about earned rate-limit reset credits.
///
/// The identifier and backend-provided copy are deliberately discarded.  The UI only needs
/// the authoritative available count and, when supplied, the closest future expiry.
public struct RateLimitResetCredits: Equatable, Sendable {
    public let availableCount: Int
    public let nearestExpiresAt: Date?

    public init(availableCount: Int, nearestExpiresAt: Date? = nil) {
        self.availableCount = availableCount
        self.nearestExpiresAt = nearestExpiresAt
    }
}

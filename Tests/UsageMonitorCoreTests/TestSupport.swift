import Foundation
@testable import UsageMonitorCore

/// Locale-pinned `Decimal` for test assertions, so results never depend on the machine's
/// regional settings.
func dec(_ raw: String) -> Decimal {
    return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))!
}

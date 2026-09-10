import Foundation

/// Locale-stable money and decimal text.
///
/// A fixed `en_US_POSIX` formatter is used deliberately: the panel prints the currency
/// code next to the amount, so a per-locale symbol would add nothing and would make the
/// text depend on the machine's settings instead of the provider's data.
public enum DecimalFormatting {

    /// Shared formatter; `NumberFormatter` is expensive, so all call sites serialise
    /// through this one instance.
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.minimumIntegerDigits = 1
        formatter.maximumIntegerDigits = 42
        return formatter
    }()

    /// Decimal places as written by the provider. `Decimal("110.00")` keeps the scale its
    /// source string had, so the panel can echo it rather than inventing precision.
    public static func fractionDigits(of value: Decimal) -> Int {
        return max(0, -value.exponent)
    }

    /// `110` → `110.00`, `110.5` → `110.50`, `0.005` → `0.005`.
    public static func amountText(_ value: Decimal, minimumFractionDigits: Int = 2) -> String {
        let digits = max(minimumFractionDigits, fractionDigits(of: value), 0)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let number = NSDecimalNumber(decimal: value)
        return formatter.string(from: number) ?? "\(value)"
    }

    /// `110.00 CNY`, or `88.00` when the response named no currency (the panel says
    /// 币种未确认 separately; no code is ever guessed). The main amount prefers the
    /// available balance, which is what a user needs to see first (Round 7 requirement 1).
    public static func balanceText(_ balance: ProviderBalance) -> String {
        guard let main = balance.available ?? balance.total else { return "" }
        guard let currency = balance.currency else { return amountText(main) }
        return "\(amountText(main)) \(currency)"
    }

    /// `总额 110.00 CNY · 可用 42.25 · 充值 100.00 · 赠费 10.00`, or with provider-specific
    /// labels (`累计充值 …`) carried verbatim from the endpoint's own semantics. Only
    /// reported parts appear; `available_balance` is labelled 可用, never 充值, and an
    /// available-only response shows 可用 without inventing a 总额 line.
    public static func balanceDetailText(_ balance: ProviderBalance) -> String {
        let currency = balance.currency.map { " \($0)" } ?? ""
        var parts: [String] = []
        if let total = balance.total {
            parts.append("总额 \(amountText(total))\(currency)")
        }
        if let available = balance.available, available != balance.total {
            parts.append("可用 \(amountText(available))")
        }
        if let toppedUp = balance.toppedUp {
            parts.append("充值 \(amountText(toppedUp))")
        }
        if let granted = balance.granted {
            parts.append("赠费 \(amountText(granted))")
        }
        if let extras = balance.additionalAmounts {
            parts.append(contentsOf: extras.map { "\($0.label) \(amountText($0.amount))" })
        }
        return parts.joined(separator: " · ")
    }
}

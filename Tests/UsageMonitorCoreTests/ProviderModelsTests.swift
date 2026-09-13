import XCTest
@testable import UsageMonitorCore

/// Money handling: exact Decimal parsing, per-currency display, and the refusal to invent
/// a number when a payload cannot be trusted (v1.1 requirements 3 and 6).
final class ProviderModelsTests: XCTestCase {

    // MARK: Decimal parsing

    func testDecimalParsesMoneyStringsExactly() {
        XCTAssertEqual(SafeConversion.decimal(from: "110.00"), dec("110.00"))
        XCTAssertEqual(SafeConversion.decimal(from: "0.01"), dec("0.01"))
        XCTAssertEqual(SafeConversion.decimal(from: "-12.5"), dec("-12.5"))
        XCTAssertEqual(SafeConversion.decimal(from: "1234567890123456.78"), dec("1234567890123456.78"))
        // The value is exact, never a Double rounding. `Decimal` stores a canonical form,
        // so trailing fractional zeros are not representable ("110.00" and "110" are the
        // same stored value); the two-decimal presentation is DecimalFormatting's job.
        XCTAssertEqual(SafeConversion.decimal(from: "110.00"), dec("110"))
        XCTAssertEqual(SafeConversion.decimal(from: "0.005")?.description, "0.005")
    }

    func testDecimalRejectsNonMoneyTextInsteadOfProducingZero() {
        XCTAssertNil(SafeConversion.decimal(from: ""))
        XCTAssertNil(SafeConversion.decimal(from: "   "))
        XCTAssertNil(SafeConversion.decimal(from: "abc"))
        XCTAssertNil(SafeConversion.decimal(from: "1,234.00"), "a thousands separator must not be reinterpreted")
        XCTAssertNil(SafeConversion.decimal(from: "¥110"))
        XCTAssertNil(SafeConversion.decimal(from: "110 CNY"))
        XCTAssertNil(SafeConversion.decimal(from: "-"))
    }

    func testDecimalRejectsBooleansAndOtherTypes() {
        XCTAssertNil(SafeConversion.decimal(true))
        XCTAssertNil(SafeConversion.decimal(false))
        XCTAssertNil(SafeConversion.decimal(nil))
        XCTAssertNil(SafeConversion.decimal([1, 2]))
    }

    func testDecimalFromJSONNumberUsesTheSenderValue() {
        // A bare JSON number reaches the parser as an NSNumber; its own textual form is
        // used rather than a Double rounding.
        let object = try? JSONSerialization.jsonObject(with: Data(#"{"v": 110.00}"#.utf8)) as? [String: Any]
        XCTAssertEqual(object?["v"].flatMap { SafeConversion.decimal($0) }, dec("110"))
        // The string form parses exactly, through the same strict literal path.
        let stringForm = try? JSONSerialization.jsonObject(with: Data(#"{"v": "110.00"}"#.utf8)) as? [String: Any]
        XCTAssertEqual(stringForm?["v"].flatMap { SafeConversion.decimal($0) }, dec("110.00"))
        XCTAssertEqual(stringForm?["v"].flatMap { SafeConversion.decimal($0) },
                       SafeConversion.decimal(from: "110.00"))
    }

    // MARK: Amount formatting

    func testAmountTextKeepsTwoDecimalsByDefault() {
        XCTAssertEqual(DecimalFormatting.amountText(dec("110")), "110.00")
        XCTAssertEqual(DecimalFormatting.amountText(dec("110.5")), "110.50")
        XCTAssertEqual(DecimalFormatting.amountText(dec("0.005")), "0.005")
        XCTAssertEqual(DecimalFormatting.amountText(dec("-12.5")), "-12.50")
    }

    func testBalanceTextAlwaysShowsTheProviderCurrencyCode() {
        let balance = ProviderBalance(currency: "CNY",
                                      total: dec("110.00"),
                                      granted: dec("10.00"),
                                      toppedUp: dec("100.00"))
        XCTAssertEqual(DecimalFormatting.balanceText(balance), "110.00 CNY")
        XCTAssertEqual(DecimalFormatting.balanceDetailText(balance),
                       "总额 110.00 CNY · 充值 100.00 · 赠费 10.00")
    }

    func testBalanceDetailOmitsPartsTheProviderDidNotReport() {
        let balance = ProviderBalance(currency: "USD", total: dec("5"), granted: nil, toppedUp: nil)
        XCTAssertEqual(DecimalFormatting.balanceDetailText(balance), "总额 5.00 USD")
    }

    // MARK: Persisted round trip

    func testPersistedBalanceRoundTripsExactly() throws {
        let original = ProviderBalance(currency: "CNY",
                                       total: dec("1234567890123456.78"),
                                       granted: dec("0.01"),
                                       toppedUp: dec("999.99"))
        let persisted = PersistedBalance(original)
        let restored = try XCTUnwrap(persisted.balance)
        XCTAssertEqual(restored, original)
    }

    func testPersistedBalanceWithUnparsableAmountYieldsNilNotZero() {
        var persisted = PersistedBalance(currency: "CNY", total: "not-a-number", granted: nil, toppedUp: nil)
        XCTAssertNil(persisted.balance)
        persisted.total = ""
        XCTAssertNil(persisted.balance)
    }

    func testPersistedBalanceRoundTripsAvailableAndLabelledAmounts() throws {
        let original = ProviderBalance(currency: nil,
                                       total: dec("100.00"),
                                       available: dec("66.6"),
                                       additionalAmounts: [
                                        ProviderLabeledAmount(field: "rechargeAmount", label: "累计充值", amount: dec("50.00")),
                                        ProviderLabeledAmount(field: "frozenBalance", label: "冻结金额", amount: dec("1.23")),
                                       ])
        let restored = try XCTUnwrap(PersistedBalance(original).balance)
        XCTAssertEqual(restored, original)
    }

    /// A cache entry written by the Round 6 build (no available/additionalAmounts keys,
    /// currency always present) must still decode (Round 7 requirement 1, backward
    /// compatible cache format).
    func testPersistedBalanceDecodesEntriesWrittenByOlderBuilds() throws {
        let oldJSON = #"{"currency":"CNY","total":"110.00","granted":"10.00","toppedUp":"100.00"}"#
        let persisted = try JSONDecoder().decode(PersistedBalance.self, from: Data(oldJSON.utf8))
        let restored = try XCTUnwrap(persisted.balance)
        XCTAssertEqual(restored.currency, "CNY")
        XCTAssertEqual(restored.total, dec("110.00"))
        XCTAssertNil(restored.available)
        XCTAssertNil(restored.additionalAmounts)
    }

    // MARK: Available-balance display (Round 7 requirement 1)

    func testBalanceTextPrefersTheAvailableAmount() {
        let balance = ProviderBalance(currency: "CNY",
                                      total: dec("100.00"),
                                      available: dec("42.25"))
        XCTAssertEqual(DecimalFormatting.balanceText(balance), "42.25 CNY",
                       "the main amount is the available balance")
        XCTAssertEqual(DecimalFormatting.balanceDetailText(balance),
                       "总额 100.00 CNY · 可用 42.25")
    }

    func testOverviewBalanceUsesFieldSemanticsAndCNYSymbol() {
        let totalOnly = ProviderBalance(currency: "CNY", total: dec("122.1"))
        XCTAssertEqual(DecimalFormatting.overviewBalanceText(totalOnly), "¥122.10")
        XCTAssertEqual(DecimalFormatting.overviewBalanceLabel(totalOnly), "余额")

        let available = ProviderBalance(currency: "CNY", total: dec("100"), available: dec("22.29921165"))
        XCTAssertEqual(DecimalFormatting.overviewBalanceText(available), "¥22.30")
        XCTAssertEqual(DecimalFormatting.overviewBalanceLabel(available), "可用余额")

        let dollars = ProviderBalance(currency: "USD", total: dec("5"))
        XCTAssertEqual(DecimalFormatting.overviewBalanceText(dollars), "5.00 USD")

        let tiny = ProviderBalance(currency: "CNY", total: dec("0.001"))
        XCTAssertEqual(DecimalFormatting.overviewBalanceText(tiny), "< ¥0.01")
    }

    func testBalanceWithoutACurrencyShowsNoInventedCode() {
        let balance = ProviderBalance(currency: nil, total: dec("88"))
        XCTAssertEqual(DecimalFormatting.balanceText(balance), "88.00")
        XCTAssertEqual(DecimalFormatting.balanceDetailText(balance), "总额 88.00")
    }

    func testLabelledAmountsAppearWithTheirOwnSemantics() {
        let balance = ProviderBalance(currency: nil,
                                      total: dec("100"),
                                      additionalAmounts: [
                                        ProviderLabeledAmount(field: "rechargeAmount", label: "累计充值", amount: dec("50")),
                                        ProviderLabeledAmount(field: "giveAmount", label: "累计赠送", amount: dec("50")),
                                      ])
        XCTAssertEqual(DecimalFormatting.balanceDetailText(balance),
                       "总额 100.00 · 累计充值 50.00 · 累计赠送 50.00")
    }

    // MARK: Report shape

    func testReportMarkedCachedDowngradesConnectedToStale() {
        let report = ProviderReport(platform: .deepseek, accountID: "a1",
                                    balances: [ProviderBalance(currency: "CNY", total: dec("1"), granted: nil, toppedUp: nil)],
                                    lastSuccessAt: Date(), connection: .connected,
                                    isLive: true, error: nil, consoleURL: nil)
        let cached = report.markedCached()
        XCTAssertFalse(cached.isLive)
        XCTAssertEqual(cached.connection, .stale)
        XCTAssertEqual(cached.balances.count, 1, "a cached report keeps its numbers")
    }

    func testProviderFailureCategoriesCarryNoUpstreamText() {
        // Every category has a fixed summary and a fixed display string, so no server text
        // can reach the log or the panel.
        for failure in [ProviderFailure.notConfigured, .invalidCredential, .networkUnreachable,
                        .timedOut, .serverError(status: 502), .businessError(code: 1113),
                        .unexpectedResponse, .structureUnsupported, .contractUnconfirmed,
                        .crossDomainRedirectBlocked, .suspended, .cancelled, .other] {
            XCTAssertFalse(failure.debugSummary.isEmpty)
            XCTAssertFalse(failure.displayText.isEmpty)
        }
        XCTAssertEqual(ProviderFailure.serverError(status: 502).debugSummary, "serverError(status:502)")
        XCTAssertEqual(ProviderFailure.businessError(code: 1113).debugSummary, "businessError(code:1113)")
    }
}

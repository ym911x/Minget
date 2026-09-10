import XCTest
@testable import UsageMonitorCore

final class GLMOfficialConsoleTests: XCTestCase {
    func testOfficialFlatReportPreservesDecimalAndCNY() throws {
        let body = Data(#"{"code":200,"success":true,"data":{"balance":66.6,"availableBalance":60.12,"rechargeAmount":100,"giveAmount":0,"totalSpendAmount":33.4,"frozenBalance":6.48}}"#.utf8)
        let observed = GLMAccountReportParser.observe(data: body, httpStatus: 200, schema: .consoleReportV1)
        XCTAssertTrue(observed.isDisplayable)
        let balance = try XCTUnwrap(observed.candidateBalances.first)
        XCTAssertEqual(balance.total, Decimal(string: "66.6"))
        XCTAssertEqual(balance.available, Decimal(string: "60.12"))
        XCTAssertEqual(balance.currency, "CNY")
        XCTAssertNil(balance.toppedUp)
        XCTAssertEqual(balance.additionalAmounts?.count, 4)
    }

    func testFlatReportDoesNotHideNullOrBusinessFailure() {
        for json in [#"{"code":200,"data":{"balance":100,"availableBalance":null}}"#,
                     #"{"code":401,"data":{"balance":100}}"#,
                     #"{"code":200,"success":false,"data":{"balance":100}}"#] {
            let observed = GLMAccountReportParser.observe(data: Data(json.utf8), httpStatus: 200, schema: .consoleReportV1)
            XCTAssertFalse(observed.isDisplayable)
        }
    }

    func testConsoleTokenBecomesAuthorizationAndScopeSurvivesStorage() throws {
        let session = GLMConsoleSessionPolicy.StoredSession(cookies: [
            .init(name: "bigmodel_token_production", value: "synthetic%2Btoken", domain: ".bigmodel.cn", expiresAt: nil)
        ], capturedAt: Date(), organizationID: "fixture-org", projectID: "fixture-project")
        let restored = try XCTUnwrap(GLMConsoleSessionPolicy.decode(GLMConsoleSessionPolicy.encode(session)))
        let headers = GLMConsoleSessionPolicy.requestHeaders(for: restored)
        XCTAssertEqual(headers["Authorization"], "synthetic+token")
        XCTAssertEqual(headers["Bigmodel-Organization"], "fixture-org")
        XCTAssertEqual(headers["Bigmodel-Project"], "fixture-project")
        XCTAssertTrue(GLMConsoleSessionPolicy.isCookieAllowed(domain: ".bigmodel.cn"))
        XCTAssertFalse(GLMConsoleSessionPolicy.isCookieAllowed(domain: "bigmodel.cn.evil.test"))
    }

    func testEncodedHeaderInjectionIsRejected() {
        let session = GLMConsoleSessionPolicy.StoredSession(cookies: [
            .init(name: "bigmodel_token_production", value: "fixture%0D%0Abad", domain: ".bigmodel.cn", expiresAt: nil)
        ], capturedAt: Date())
        XCTAssertNil(GLMConsoleSessionPolicy.requestHeaders(for: session)["Authorization"])
    }
}

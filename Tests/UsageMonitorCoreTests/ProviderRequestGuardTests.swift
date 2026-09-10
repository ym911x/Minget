import XCTest
@testable import UsageMonitorCore

/// Network-layer admissibility: which paths may be requested, which are model endpoints and
/// must never be, and which redirects are refused.
final class ProviderRequestGuardTests: XCTestCase {

    // MARK: Model endpoints are unreachable

    func testModelEndpointsAreBlocked() {
        let paths = ["/chat/completions", "/v1/chat/completions", "/completions", "/responses",
                     "/embeddings", "/moderations", "/beta/messages", "/chat/turn", "/rerank"]
        for path in paths {
            XCTAssertThrowsError(try ProviderHTTPClient.validate(path: path, allowedPaths: ["/user/balance"])) {
                XCTAssertEqual($0 as? ProviderTransportError, .modelEndpointBlocked, "path \(path)")
            }
            XCTAssertTrue(ProviderRequestGuard.isModelEndpoint(path: path), "path \(path)")
        }
    }

    func testModelEndpointBlockIsIndependentOfTheAllowList() {
        // Even a misconfigured allow-list cannot turn the client into an inference client.
        XCTAssertThrowsError(try ProviderHTTPClient.validate(path: "/chat/completions",
                                                             allowedPaths: ["/chat/completions"]))
    }

    func testPathsOutsideTheAllowListAreRefused() {
        XCTAssertThrowsError(try ProviderHTTPClient.validate(path: "/user/info", allowedPaths: ["/user/balance"])) {
            XCTAssertEqual($0 as? ProviderTransportError, .pathNotAllowed)
        }
        XCTAssertNoThrow(try ProviderHTTPClient.validate(path: "/user/balance", allowedPaths: ["/user/balance"]))
    }

    func testDeepSeekClientMayOnlyAskForTheBalancePath() {
        XCTAssertEqual(DeepSeekProvider.allowedPaths, [DeepSeekProvider.balancePath])
        XCTAssertEqual(DeepSeekProvider.balancePath, "/user/balance")
    }

    func testGLMClientMayOnlyAskForTheTwoGLMPaths() {
        XCTAssertEqual(GLMProvider.allowedPaths, [GLMProvider.balancePath, GLMProvider.accountReportPath])
        XCTAssertEqual(GLMProvider.balancePath, "/api/paas/v4/balance")
    }

    // MARK: Redirects

    func testSameOriginRedirectIsAllowed() {
        let original = URL(string: "https://api.deepseek.com/user/balance")!
        let redirect = URL(string: "https://api.deepseek.com/user/balance?v=2")!
        XCTAssertFalse(ProviderRequestGuard.isCrossDomainRedirect(from: ProviderOrigin(url: original)!,
                                                                  to: redirect))
    }

    func testCrossHostRedirectIsRefused() {
        let original = URL(string: "https://api.deepseek.com/user/balance")!
        for target in ["https://evil.example.com/user/balance",
                       "http://api.deepseek.com/user/balance",
                       "https://api.deepseek.com:8443/user/balance"] {
            let redirect = URL(string: target)!
            XCTAssertTrue(ProviderRequestGuard.isCrossDomainRedirect(from: ProviderOrigin(url: original)!,
                                                                     to: redirect),
                          "target \(target) must be refused")
        }
    }

    func testRedirectWithoutAnOriginIsRefused() {
        let original = URL(string: "https://api.deepseek.com/user/balance")!
        let relative = URL(string: "/elsewhere", relativeTo: original)!
        XCTAssertTrue(ProviderRequestGuard.isCrossDomainRedirect(from: ProviderOrigin(url: original)!, to: relative))
    }

    func testURLSessionDelegateRefusesACrossDomainRedirectAndReportsIt() throws {
        let delegate = RedirectGuardDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let originalURL = URL(string: "https://api.deepseek.com/user/balance")!
        let request = URLRequest(url: originalURL)
        let task = session.dataTask(with: request)
        defer { task.cancel() }

        let redirectRequest = URLRequest(url: URL(string: "https://evil.example.com/user/balance")!)
        let response = HTTPURLResponse(url: originalURL, statusCode: 302, httpVersion: nil, headerFields: nil)!

        var handedDown: URLRequest?
        let expectation = expectation(description: "redirect decision")
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: redirectRequest) { nextRequest in
            handedDown = nextRequest
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertNil(handedDown, "the redirect must not be followed")
        XCTAssertTrue(delegate.refusedRedirect(for: task), "the refusal must be reportable")
    }

    func testURLSessionDelegateAllowsASameOriginRedirect() throws {
        let delegate = RedirectGuardDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let originalURL = URL(string: "https://api.deepseek.com/user/balance")!
        let task = session.dataTask(with: URLRequest(url: originalURL))
        defer { task.cancel() }

        let sameOrigin = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance?v=2")!)
        let response = HTTPURLResponse(url: originalURL, statusCode: 307, httpVersion: nil, headerFields: nil)!

        var handedDown: URLRequest?
        let expectation = expectation(description: "redirect decision")
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: sameOrigin) { nextRequest in
            handedDown = nextRequest
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(handedDown?.url, sameOrigin.url)
        XCTAssertFalse(delegate.refusedRedirect(for: task))
    }

    // MARK: Refusal isolation (one task's refusal must not classify another request)

    func testARefusedRedirectDoesNotPolluteOtherTasks() throws {
        let delegate = RedirectGuardDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let originalURL = URL(string: "https://api.deepseek.com/user/balance")!
        let refusedTask = session.dataTask(with: URLRequest(url: originalURL))
        let laterTask = session.dataTask(with: URLRequest(url: originalURL))
        defer {
            refusedTask.cancel()
            laterTask.cancel()
        }

        let redirect = URLRequest(url: URL(string: "https://evil.example.com/user/balance")!)
        let response = HTTPURLResponse(url: originalURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
        delegate.urlSession(session, task: refusedTask, willPerformHTTPRedirection: response,
                            newRequest: redirect) { _ in }

        XCTAssertTrue(delegate.refusedRedirect(for: refusedTask))
        XCTAssertFalse(delegate.refusedRedirect(for: laterTask),
                       "one cross-domain redirect must not mark an unrelated task as refused")
    }

    /// End to end through a real `URLSession` driven by an in-process `URLProtocol`: a
    /// cross-domain redirect is refused, and the refusal is reported as exactly that.
    /// End to end through a real `URLSession` driven by an in-process `URLProtocol`: a
    /// cross-domain redirect is refused, and the refusal is reported as exactly that.
    func testTransportRefusesACrossDomainRedirectEndToEnd() async {
        RedirectStubProtocol.reset { _ in .redirect(to: "https://evil.example.com/user/balance") }
        let transport = URLSessionProviderTransport(timeout: 5, protocolClasses: [RedirectStubProtocol.self])

        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!))
            XCTFail("a cross-domain redirect must surface as a refusal")
        } catch {
            XCTAssertEqual(error as? ProviderTransportError, .crossDomainRedirectBlocked)
        }
        XCTAssertTrue(RedirectStubProtocol.recordedRequests.allSatisfy { $0.url?.host != "evil.example.com" },
                      "the redirected request must never be issued")
    }

    /// A plain response still flows through the delegate-based path unchanged.
    func testTransportReturnsAPlainResponse() async throws {
        RedirectStubProtocol.reset { _ in .plain(status: 200, body: Data("balance".utf8)) }
        let transport = URLSessionProviderTransport(timeout: 5, protocolClasses: [RedirectStubProtocol.self])

        let response = try await transport.send(URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!))
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data("balance".utf8))
    }

    /// A same-origin redirect is followed and the final response is returned.
    func testTransportFollowsASameOriginRedirect() async throws {
        RedirectStubProtocol.reset { request in
            if request.url?.query == nil {
                return .redirect(to: "https://api.deepseek.com/user/balance?v=2")
            }
            return .plain(status: 200, body: Data())
        }
        let transport = URLSessionProviderTransport(timeout: 5, protocolClasses: [RedirectStubProtocol.self])

        let response = try await transport.send(URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!))
        XCTAssertEqual(response.status, 200)
    }

    /// The load-bearing isolation property at transport level: after one request has been
    /// refused a redirect, the next request through the same transport that fails for
    /// network reasons must be reported as that network failure, never as a blocked
    /// redirect. Refusal state is per task and task identifiers are unique per session, so
    /// both requests here deliberately share one transport, like real provider flows do.
    func testAnUnrelatedNetworkFailureIsNotMisclassifiedAfterARefusal() async {
        RedirectStubProtocol.reset { _ in .redirect(to: "https://evil.example.com/user/balance") }
        let transport = URLSessionProviderTransport(timeout: 5, protocolClasses: [RedirectStubProtocol.self])

        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!))
            XCTFail("the refused request must fail")
        } catch {
            XCTAssertEqual(error as? ProviderTransportError, .crossDomainRedirectBlocked)
        }

        // An unrelated later request fails at the network layer (in-process stub, no
        // external network involved) and must be classified on its own merits.
        RedirectStubProtocol.reset { _ in .fail(.cannotConnectToHost) }
        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!))
            XCTFail("the second request must fail")
        } catch {
            let transportError = error as? ProviderTransportError
            XCTAssertNotEqual(transportError, .crossDomainRedirectBlocked,
                              "a later network failure must not inherit an earlier task's refusal")
            XCTAssertEqual(transportError, .networkUnreachable)
        }
    }

    // MARK: Client behaviour

    func testClientRefusesAPathThatIsNotAllowListedWithoutCallingTheTransport() async {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 200, body: Data()) }
        let client = ProviderHTTPClient(baseURL: DeepSeekProvider.apiBaseURL,
                                        allowedPaths: DeepSeekProvider.allowedPaths,
                                        transport: transport)
        do {
            _ = try await client.get(path: "/chat/completions")
            XCTFail("the request must be refused")
        } catch {
            XCTAssertEqual(error as? ProviderTransportError, .modelEndpointBlocked)
        }
        XCTAssertTrue(transport.recordedRequests.isEmpty, "a refused request must never leave the process")
    }

    func testClientRefusesAPathPointingAtAnotherHost() async {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 200, body: Data()) }
        let client = ProviderHTTPClient(baseURL: DeepSeekProvider.apiBaseURL,
                                        allowedPaths: DeepSeekProvider.allowedPaths,
                                        transport: transport)
        do {
            _ = try await client.get(path: "https://evil.example.com/user/balance")
            XCTFail("an absolute URL on another host must be refused")
        } catch {
            XCTAssertEqual(error as? ProviderTransportError, .invalidURL)
        }
        XCTAssertTrue(transport.recordedRequests.isEmpty)
    }

    func testClientSendsTheCredentialHeaderOnlyOnTheConfiguredOrigin() async throws {
        let transport = FakeTransport()
        transport.handler = { _ in ProviderHTTPResponse(status: 200, body: Data()) }
        let client = ProviderHTTPClient(baseURL: DeepSeekProvider.apiBaseURL,
                                        allowedPaths: DeepSeekProvider.allowedPaths,
                                        transport: transport)
        _ = try await client.get(path: DeepSeekProvider.balancePath, headers: ["Authorization": "Bearer test-key"])
        XCTAssertEqual(transport.recordedRequests.count, 1)
        XCTAssertEqual(transport.recordedRequests.first?.url?.host, "api.deepseek.com")
        XCTAssertEqual(transport.recordedRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testURLErrorsMapToFixedCategories() {
        XCTAssertEqual(ProviderHTTPClient.transportError(from: URLError(.timedOut)), .timedOut)
        XCTAssertEqual(ProviderHTTPClient.transportError(from: URLError(.notConnectedToInternet)), .networkUnreachable)
        XCTAssertEqual(ProviderHTTPClient.transportError(from: URLError(.cancelled)), .cancelled)
        XCTAssertEqual(ProviderHTTPClient.transportError(from: URLError(.badURL)), .other)
    }
}

/// Injectable transport used across the provider tests. Nothing here touches the network.
final class FakeTransport: ProviderTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    var handler: ((URLRequest) throws -> ProviderHTTPResponse)?
    /// When set, the transport throws this instead of consulting the handler.
    var thrownError: Error?

    var recordedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
        record(request)

        if let thrownError { throw thrownError }
        if let handler { return try handler(request) }
        return ProviderHTTPResponse(status: 200, body: Data())
    }

    /// Synchronous helper: `lock` is unavailable from async contexts.
    private func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
    }
}

/// In-process `URLProtocol` stub so the real `URLSession` pipeline (delegate, redirect
/// decision, body accumulation) is exercised without a network. One maker serves every
/// request of a test.
///
/// A custom URLProtocol must report a redirect through `urlProtocol(_:wasRedirectedTo:)`
/// for the session to engage its own redirect machinery; a bare 302 response is otherwise
/// delivered as the final response (verified against this macOS's Foundation).
final class RedirectStubProtocol: URLProtocol {

    enum Outcome {
        case plain(status: Int, body: Data)
        /// A 3xx with a Location header, reported to the session as a real redirect.
        case redirect(to: String)
        /// Fails the request with the given URLError code, as an unreachable network would.
        case fail(URLError.Code)
    }

    private static let lock = NSLock()
    private static var maker: ((URLRequest) -> Outcome)?
    private static var requests: [URLRequest] = []

    /// Every request the stub saw. A refused redirect must never appear here a second time
    /// with a different host.
    static var recordedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    static func reset(_ responseMaker: @escaping (URLRequest) -> Outcome) {
        lock.lock()
        maker = responseMaker
        requests.removeAll()
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let maker = Self.maker
        Self.lock.unlock()
        guard let maker, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch maker(request) {
        case .plain(let status, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty {
                client?.urlProtocol(self, didLoad: body)
            }
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let location):
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": location])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let target = URL(string: location) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            }
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

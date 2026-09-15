import Foundation

/// Origin string used to compare a request with a redirect target.
public struct ProviderOrigin: Equatable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int?

    public init?(url: URL) {
        // A relative URL has no origin of its own: the authority it appears to carry is
        // borrowed from its base, so it must not be mistaken for a resolved target. A
        // redirect that cannot be pinned to an absolute origin is refused by the caller.
        guard url.baseURL == nil,
              let scheme = url.scheme?.lowercased(), !scheme.isEmpty,
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port ?? Self.defaultPort(for: scheme)
    }

    public static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    public var identity: String { "\(scheme)://\(host):\(port.map(String.init) ?? "0")" }
}

/// Request admissibility rules shared by every provider client.
///
/// Two independent gates protect credentials:
/// 1. a per-client path allow-list, so a provider client cannot be talked into calling a
///    method it was never meant to call,
/// 2. a permanent model-endpoint block, so no amount of allow-list misconfiguration can
///    ever turn a balance lookup into an inference call.
/// Redirects to another origin are refused outright rather than followed, because a
/// redirect is the one place a `URLSession` would otherwise re-send credentials.
public enum ProviderRequestGuard {

    /// Fragments that identify model inference endpoints. Matched against the path only,
    /// never against query strings, so `?model=` cannot smuggle a match or an escape.
    public static let modelEndpointFragments: [String] = [
        "chat/completions",
        "chatcompletions",
        "completions",
        "responses",
        "embeddings",
        "rerank",
        "moderations",
        "messages",
        "generations",
        "generate",
        "async-task",
        "/chat/",
    ]

    public static func isModelEndpoint(path: String) -> Bool {
        let lowered = path.lowercased()
        return modelEndpointFragments.contains { lowered.contains($0) }
    }

    /// Only an exact allow-listed path is issued. Query strings are permitted and are not
    /// part of the comparison.
    public static func isPathAllowed(path: String, allowedPaths: Set<String>) -> Bool {
        guard let components = URLComponents(string: path) else { return false }
        let cleanPath = components.path.isEmpty ? path : components.path
        return allowedPaths.contains(cleanPath)
    }

    /// True when following `to` would move the request off the origin it was sent to.
    /// A scheme change counts: http → https is a different origin for credential purposes.
    public static func isCrossDomainRedirect(from origin: ProviderOrigin, to redirect: URL) -> Bool {
        guard let target = ProviderOrigin(url: redirect) else { return true }
        return target != origin
    }
}

/// Minimal response shape. Status and body only: headers are deliberately not surfaced,
/// so nothing that arrives from the wire can be logged by accident.
public struct ProviderHTTPResponse: Equatable, Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public var isOK: Bool { (200..<300).contains(status) }
}

/// Injectable transport. Production uses `URLSession`; tests substitute a closure, so
/// provider behaviour is verified without a live network.
public protocol ProviderTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ProviderHTTPResponse
}

/// Errors raised by the transport itself, before any parsing happens.
public enum ProviderTransportError: Error, Equatable, Sendable {
    case crossDomainRedirectBlocked
    case pathNotAllowed
    case modelEndpointBlocked
    case invalidURL
    case networkUnreachable
    case timedOut
    case cancelled
    case other
}

/// The one place provider HTTP requests are made.
///
/// Every request is checked against the guard rules before it leaves the process, and the
/// redirect delegate re-checks the origin so a same-host-then-elsewhere redirect chain
/// cannot smuggle credentials out.
public struct ProviderHTTPClient: Sendable {

    public let baseURL: URL
    public let allowedPaths: Set<String>
    public let transport: ProviderTransport
    /// Header name → value for every request. Only non-secret headers belong here;
    /// the credential header is supplied per call by the provider client.
    public let defaultHeaders: [String: String]

    public init(baseURL: URL,
                allowedPaths: Set<String>,
                transport: ProviderTransport,
                defaultHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.allowedPaths = allowedPaths
        self.transport = transport
        self.defaultHeaders = defaultHeaders
    }

    /// Issues a GET. Throws `ProviderTransportError` for rule violations, so a caller can
    /// distinguish "refused locally" from "the server said no".
    public func get(path: String,
                    headers: [String: String] = [:],
                    timeout: TimeInterval = 15) async throws -> ProviderHTTPResponse {
        guard let url = URL(string: path, relativeTo: baseURL), let absolute = URL(string: url.absoluteString) else {
            throw ProviderTransportError.invalidURL
        }
        try Self.validate(path: path, allowedPaths: allowedPaths)

        // The request may only leave for the configured origin. A relative path therefore
        // cannot be talked into pointing at a third-party host by a hostile config value.
        guard let requestOrigin = ProviderOrigin(url: absolute),
              requestOrigin == ProviderOrigin(url: baseURL) else {
            throw ProviderTransportError.invalidURL
        }

        var request = URLRequest(url: absolute)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in defaultHeaders { request.setValue(value, forHTTPHeaderField: key) }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        do {
            return try await transport.send(request)
        } catch let error as ProviderTransportError {
            throw error
        } catch let urlError as URLError {
            throw Self.transportError(from: urlError)
        } catch {
            throw ProviderTransportError.other
        }
    }

    /// Validates a path against both gates. Split out so tests can pin each rule down
    /// without a transport.
    public static func validate(path: String, allowedPaths: Set<String>) throws {
        if ProviderRequestGuard.isModelEndpoint(path: path) {
            throw ProviderTransportError.modelEndpointBlocked
        }
        guard ProviderRequestGuard.isPathAllowed(path: path, allowedPaths: allowedPaths) else {
            throw ProviderTransportError.pathNotAllowed
        }
    }

    public static func transportError(from urlError: URLError) -> ProviderTransportError {
        switch urlError.code {
        case .timedOut, .cannotFindHost:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            return .networkUnreachable
        case .cancelled:
            return .cancelled
        default:
            return .other
        }
    }
}

/// Production transport. `URLSession` is created with a delegate that refuses any redirect
/// leaving the origin of the original request, which is the only reliable way to keep a
/// credential header from being replayed somewhere else.
///
/// The response is read through the delegate rather than `session.data(for:)` so the
/// refusal state can be tied to the exact task that failed. A transport-wide flag would
/// let one refused redirect misclassify every later, unrelated network error.
public final class URLSessionProviderTransport: NSObject, ProviderTransport, @unchecked Sendable {

    private let session: URLSession
    let delegate: RedirectGuardDelegate

    /// - Parameter protocolClasses: test seam. A registered `URLProtocol` lets the
    ///   redirect and response behaviour be exercised without a live network.
    public init(timeout: TimeInterval = 15, protocolClasses: [AnyClass]? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        let delegate = RedirectGuardDelegate()
        self.delegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        super.init()
    }

    public func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
        let task = session.dataTask(with: request)
        let outcome = await delegate.waitForCompletion(of: task)
        switch outcome {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

/// Refuses redirects instead of following them. `URLSession` drops the `Authorization`
/// header on a cross-host redirect by itself, but for credentials "dropped" is not enough:
/// the request is refused so the caller reports a refusal instead of a quiet success.
///
/// Refusal state lives per task. One transport serves every provider flow, so a shared
/// "refused" flag would leak one request's refusal into an unrelated later failure —
/// exactly the misclassification this class exists to prevent.
final class RedirectGuardDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    /// Outcome of one task, built from the delegate callbacks and handed to exactly one
    /// awaiting `send`.
    private struct Outcome {
        let continuation: CheckedContinuation<Result<ProviderHTTPResponse, ProviderTransportError>, Never>
        var body = Data()
        var response: HTTPURLResponse?
    }

    private let lock = NSLock()
    private var outcomes: [Int: Outcome] = [:]   // keyed by `URLSessionTask.identifier`
    /// Refusals are kept per task identifier and outlive the task itself, so the record
    /// stays queryable after completion. The set only grows on refusals, which are rare.
    private var refusedTaskIDs: Set<Int> = []

    /// Registers the awaiting continuation and starts the task. Called before `resume()`,
    /// so no callback can arrive before the outcome exists.
    func waitForCompletion(of task: URLSessionTask) async -> Result<ProviderHTTPResponse, ProviderTransportError> {
        return await withCheckedContinuation { continuation in
            lock.lock()
            outcomes[task.taskIdentifier] = Outcome(continuation: continuation)
            lock.unlock()
            task.resume()
        }
    }

    /// True when *this task* was refused a redirect. Never reflects any other task.
    func refusedRedirect(for task: URLSessionTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return refusedTaskIDs.contains(task.taskIdentifier)
    }

    private func withOutcome<T>(_ task: URLSessionTask, _ mutate: (inout Outcome) -> T) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard var outcome = outcomes[task.taskIdentifier] else { return nil }
        let result = mutate(&outcome)
        outcomes[task.taskIdentifier] = outcome
        return result
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // The original request's origin decides. If even that cannot be pinned to an
        // absolute origin, following anything would be an unreviewed credential hop.
        guard let originalURL = task.originalRequest?.url, let origin = ProviderOrigin(url: originalURL) else {
            markRefused(task)
            completionHandler(nil)
            return
        }
        if let target = request.url, ProviderRequestGuard.isCrossDomainRedirect(from: origin, to: target) {
            markRefused(task)
            // Handing back nil ends the redirect; the task then completes normally with
            // the 3xx response, and `didCompleteWithError` reports the refusal instead.
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            withOutcome(dataTask) { $0.response = http }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        withOutcome(dataTask) { $0.body.append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let outcome = outcomes.removeValue(forKey: task.taskIdentifier)
        let refused = refusedTaskIDs.contains(task.taskIdentifier)
        lock.unlock()

        let result: Result<ProviderHTTPResponse, ProviderTransportError>
        if refused {
            // The refusal is this task's answer, whatever bytes arrived beside it.
            result = .failure(.crossDomainRedirectBlocked)
        } else if let error {
            if let urlError = error as? URLError {
                result = .failure(ProviderHTTPClient.transportError(from: urlError))
            } else {
                result = .failure(.other)
            }
        } else if let outcome, let http = outcome.response {
            result = .success(ProviderHTTPResponse(status: http.statusCode, body: outcome.body))
        } else {
            result = .failure(.other)
        }
        if let outcome { outcome.continuation.resume(returning: result) }
    }

    private func markRefused(_ task: URLSessionTask) {
        lock.lock(); defer { lock.unlock() }
        refusedTaskIDs.insert(task.taskIdentifier)
    }
}

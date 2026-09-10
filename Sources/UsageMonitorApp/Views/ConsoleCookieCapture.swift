import Foundation
import WebKit
import UsageMonitorCore

/// Owns cookie capture for one console webview (REVIEW round 8 finding 1).
///
/// Capturing only at navigation-response time misses SPA logins: a fetch/XHR login can
/// set the authenticated cookies without another document navigation. This object
/// therefore
/// - observes the app-owned `WKHTTPCookieStore` on a short poll while the window is open,
///   so the captured session and the button state track the store continuously, and
/// - offers `freshSession()`, an **awaited** capture straight from the store that the
///   完成连接 button uses, so completion always saves the latest cookies.
///
/// Only this app's own non-persistent store is touched; no browser cookie is read.
@MainActor
final class ConsoleCookieCapture: ObservableObject {

    @Published private(set) var latestSession: GLMConsoleSessionPolicy.StoredSession?
    @Published private(set) var cookieCount = 0

    private var cookieStore: WKHTTPCookieStore?
    private var pollTimer: Timer?
    var readAccountContext: (() async -> [String: String])?

    static let pollInterval: TimeInterval = 1.0

    func attach(_ store: WKHTTPCookieStore) {
        guard cookieStore !== store else { return }
        detach()
        cookieStore = store
        captureNow()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func detach() {
        pollTimer?.invalidate()
        pollTimer = nil
        cookieStore = nil
        readAccountContext = nil
    }

    deinit {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// One capture pass from the store; keeps `latestSession` current between polls.
    func captureNow() {
        Task { [weak self] in
            await self?.freshSession()
        }
    }

    /// An awaited capture straight from the cookie store — the fresh look the completion
    /// button must use instead of a possibly stale earlier capture.
    func freshSession() async -> GLMConsoleSessionPolicy.StoredSession? {
        guard let cookieStore else { return latestSession }
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        guard self.cookieStore === cookieStore else { return nil }
        var session = Self.session(from: cookies)
        let context = await readAccountContext?() ?? [:]
        guard self.cookieStore === cookieStore else { return nil }
        session?.organizationID = context["organization"]
        session?.projectID = context["project"]
        publish(session: session)
        return session
    }

    /// Publishes a capture result (also used by the webview's navigation hook).
    func publish(session: GLMConsoleSessionPolicy.StoredSession?) {
        latestSession = session
        cookieCount = session?.cookies.count ?? 0
    }

    /// The deterministic part: host policy filtering and session building.
    static func session(from cookies: [HTTPCookie]) -> GLMConsoleSessionPolicy.StoredSession? {
        let stored: [GLMConsoleSessionPolicy.StoredCookie] = cookies
            .filter { GLMConsoleSessionPolicy.isCookieAllowed(domain: $0.domain) }
            .map { GLMConsoleSessionPolicy.StoredCookie(name: $0.name,
                                                        value: $0.value,
                                                        domain: $0.domain,
                                                        expiresAt: $0.expiresDate) }
        guard !stored.isEmpty else { return nil }
        return GLMConsoleSessionPolicy.StoredSession(cookies: stored, capturedAt: Date())
    }
}

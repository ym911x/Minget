import SwiftUI
import WebKit
import UsageMonitorCore

/// WebKit host for the official console login.
///
/// Guarantees, and where they live:
/// - **No existing browser cookie is read.** The webview is given its own
///   `WKWebsiteDataStore.nonPersistent()`, created by this app. Nothing is imported from
///   Safari or Chrome and no shared cookie store is consulted.
/// - **The session stays with bigmodel.cn.** `GLMConsoleSessionPolicy.isNavigationAllowed`
///   cancels any navigation off the official console hosts, so the captured cookies can
///   never be delivered to a third party by following a link.
/// - **Captcha and login stay with the user.** Nothing here fills forms, runs scripts to
///   bypass a challenge, or talks to a model.
/// - **The console's data source is observed, not guessed** (Round 8): the injected
///   `GLMConsoleResponseObserver` script reports redacted path/type summaries of the JSON
///   responses the page itself loads, so the real balance resource and its header
///   mechanism can be identified from evidence. Values never leave the page.
struct ConsoleWebView: NSViewRepresentable {
    let baseURL: URL
    /// Owns cookie capture for this window: store polling plus the awaited fresh capture
    /// the completion button uses (REVIEW round 8 finding 1).
    @ObservedObject var capture: ConsoleCookieCapture
    var onCapture: ((Int) -> Void)?
    /// Redacted structure observations from the page's own JSON responses.
    var onConsoleObservation: ((GLMConsoleResponseObserver.Observation) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let userContentController = WKUserContentController()
        userContentController.addUserScript(
            WKUserScript(source: GLMConsoleResponseObserver.userScriptSource,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false))
        userContentController.add(context.coordinator,
                                  name: GLMConsoleResponseObserver.messageHandlerName)
        configuration.userContentController = userContentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: baseURL))
        context.coordinator.webView = webView
        // The app-owned store is observed for the window's whole lifetime, so cookies set
        // by SPA/fetch logins without a document navigation are picked up too.
        capture.attach(configuration.websiteDataStore.httpCookieStore)
        capture.readAccountContext = { [weak webView] in
            guard let webView, let url = webView.url,
                  GLMConsoleSessionPolicy.isNavigationAllowed(url) else { return [:] }
            // Only the two official account-scope keys from this app's own page.
            let script = "({organization: localStorage.getItem('Bigmodel-Organization') || '', project: localStorage.getItem('Bigmodel-Project') || ''})"
            return (try? await webView.evaluateJavaScript(script)) as? [String: String] ?? [:]
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    /// The user content controller retains its message handler; dismantle must release
    /// it, or every dismissed login sheet leaks a coordinator.
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeAllUserScripts()
        nsView.configuration.userContentController.removeAllScriptMessageHandlers()
        coordinator.parent.capture.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ConsoleWebView
        weak var webView: WKWebView?

        init(parent: ConsoleWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == GLMConsoleResponseObserver.messageHandlerName else { return }
            guard let observation = GLMConsoleResponseObserver.observation(from: message.body) else { return }
            let callback = parent.onConsoleObservation
            DispatchQueue.main.async {
                callback?(observation)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  GLMConsoleSessionPolicy.isNavigationAllowed(url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            guard let url = navigationResponse.response.url,
                  GLMConsoleSessionPolicy.isNavigationAllowed(url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            captureCookies(from: webView)
        }

        func captureCookies(from webView: WKWebView) {
            let capture = parent.capture
            let callback = parent.onCapture
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let session = ConsoleCookieCapture.session(from: cookies)
                DispatchQueue.main.async {
                    capture.publish(session: session)
                    if let session { callback?(session.cookies.count) }
                }
            }
        }
    }
}

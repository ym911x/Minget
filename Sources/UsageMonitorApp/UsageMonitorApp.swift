import SwiftUI
import UsageMonitorCore

/// Composition root. One instance owns the Codex service, the provider engine and the
/// status item, so a refresh started at launch and cleanup at exit cannot diverge.
///
/// The credential store and the transport are injectable so the wiring tests can run this
/// exact production composition path with an in-memory store and an in-process transport —
/// no real keychain, no network (Round 6 requirement 7).
@MainActor
final class AppContainer {

    let codexService: UsageService
    let providerCache: ProviderCache
    let providerEngine: ProviderRefreshEngine
    let glmReading: GLMReading
    let model: UsageViewModel
    let statusItem: StatusItemController

    /// Credentials live only in the macOS Keychain. The in-memory store is never used here.
    init(credentials: ProviderCredentialStoring = KeychainCredentialStore(),
         transport: ProviderTransport = URLSessionProviderTransport()) {
        codexService = UsageService()
        providerCache = ProviderCache()
        let deepSeek = DeepSeekReading(provider: DeepSeekProvider(transport: transport,
                                                                  credentials: credentials),
                                       credentials: credentials)
        let glm = GLMReading(provider: GLMProvider(transport: transport,
                                                   credentials: credentials),
                             credentials: credentials)
        glmReading = glm
        providerEngine = ProviderRefreshEngine(readers: [deepSeek, glm], cache: providerCache)
        model = UsageViewModel(service: codexService, providerEngine: providerEngine)
        statusItem = StatusItemController()
    }
}

/// Single application-lifetime container.
@MainActor
enum AppLifecycle {
    static let container = AppContainer()
    static var model: UsageViewModel { container.model }
    static var statusItem: StatusItemController { container.statusItem }
}

/// UsageMonitor — macOS menu bar app.
///
/// One long-lived `codex app-server` child is created for the app's lifetime and terminated
/// when the app exits (PROJECT_SPEC.md §8.2). The status item shows the Codex windows only;
/// DeepSeek and GLM appear in the detail panel (v1.1 requirement 7).
@main
struct UsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalHandlers: [Int32: DispatchSourceSignal] = [:]
    /// Upper bound for waiting on shutdown; generous but finite.
    private let shutdownTimeout: TimeInterval = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
        Diagnostics.log("applicationDidFinishLaunching")
        MainActor.assumeIsolated {
            let model = AppLifecycle.model
            model.start()
            AppLifecycle.statusItem.install(model: model)

            // The detail window must open when the menu bar icon is hidden, otherwise the
            // user has no way to reach the data after a relaunch (v1.1 requirement 1).
            DispatchQueue.main.asyncAfter(deadline: .now() + StatusItemController.initialLayoutDelay + 0.5) {
                MainActor.assumeIsolated {
                    AppLifecycle.statusItem.openDetailWindowIfItemIsHidden()
                }
            }
        }
        installSignalHandlers()
    }

    /// Defers termination until the in-flight fetch and the owned child are quiescent.
    /// The join runs on a background queue, so the bounded wait here cannot deadlock the
    /// main actor (Round 3 blocker 2). PROJECT_SPEC.md §3.2: leave no orphaned
    /// `codex app-server` behind.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let quiescent = DispatchSemaphore(value: 0)
        Diagnostics.log("termination requested")
        AppLifecycle.model.stop { quiescent.signal() }
        if quiescent.wait(timeout: .now() + shutdownTimeout) == .timedOut {
            Diagnostics.log("termination proceeded after shutdown timeout")
        }
        return .terminateNow
    }

    /// Last-resort sweep in case termination was forced by another path.
    /// `stop()` is idempotent and returns immediately once already quiescent;
    /// `uninstall()` removes the item from the system status bar and closes the popover
    /// and the detail window (v1.1 requirement 1).
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppLifecycle.container.codexService.stop()
            AppLifecycle.statusItem.uninstall()
        }
    }

    /// SIGTERM/SIGINT (e.g. `pkill UsageMonitor`) still clean up the child process.
    private func installSignalHandlers() {
        for signo in [SIGTERM, SIGINT] {
            signal(signo, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signo, queue: .main)
            source.setEventHandler {
                Task { @MainActor in
                    NSApp.terminate(nil)   // routed through applicationShouldTerminate
                }
            }
            source.resume()
            signalHandlers[signo] = source
        }
    }
}

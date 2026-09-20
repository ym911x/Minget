import AppKit
import UsageMonitorCore

/// Composition root. One instance owns the ChatGPT profile coordinator, the provider engine
/// and the status item, so a refresh started at launch and cleanup at exit cannot diverge.
///
/// The credential store and the transport are injectable so the wiring tests can run this
/// exact production composition path with an in-memory store and an in-process transport —
/// no real keychain, no network (Round 6 requirement 7).
@MainActor
final class AppContainer {

    /// Both ChatGPT profiles, each with its own `codex app-server` child and `CODEX_HOME`.
    /// Replaces the single `codexService` of 1.2.1 (IMPLEMENTATION_TASKS.md §2).
    let codexProfiles: CodexProfilesCoordinator
    let providerCache: ProviderCache
    let providerEngine: ProviderRefreshEngine
    let model: UsageViewModel
    let statusItem: StatusItemController

    /// Credentials live only in the macOS Keychain. The in-memory store is never used here.
    ///
    /// The providers no longer hold a credential store: each reader owns a
    /// `CredentialAccessCoordinator`, and the key is passed into the request that needs it
    /// (KEYCHAIN_REVISION_PLAN.md P1.2 and P1.7).
    init(credentials: ProviderCredentialStoring = KeychainCredentialStore(),
         transport: ProviderTransport = URLSessionProviderTransport(),
         menuBarPreferences: MenuBarPreferences = .shared) {
        codexProfiles = CodexProfilesCoordinator()
        providerCache = ProviderCache()
        let deepSeek = DeepSeekReading(provider: DeepSeekProvider(transport: transport),
                                       credentials: credentials)
        let commandCode = CommandCodeReading(provider: CommandCodeProvider(transport: transport),
                                              credentials: credentials)
        ProviderRetirementMigration(credentials: credentials, cache: providerCache).run()
        providerEngine = ProviderRefreshEngine(readers: [deepSeek, commandCode], cache: providerCache)
        model = UsageViewModel(coordinator: codexProfiles,
                               providerEngine: providerEngine,
                               menuBarPreferences: menuBarPreferences,
                               fireSchedules: .shared,
                               deepSeekStatusReader: DeepSeekStatusProvider(transport: transport))
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
/// One long-lived `codex app-server` child per ChatGPT profile is created for the app's
/// lifetime and terminated when the app exits (PROJECT_SPEC.md §8.2). The status item shows
/// exactly one selected source: account A, account B, or the DeepSeek balance.
///
/// The entry point is explicit AppKit rather than a SwiftUI `App` (REVISION_SPEC.md §3).
/// A SwiftUI `Settings { EmptyView() }` scene is still a real scene: macOS may restore or
/// open it, which showed the user an empty “设置” window at cold start. Declaring no scene at
/// all removes that failure mode structurally instead of closing the window after the fact.
@main
enum MingetMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
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
            AppLifecycle.container.codexProfiles.stop()
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

import Foundation
import UsageMonitorCore

/// QA smoke diagnostic: drives the SAME production path as the app
/// (CodexLocator -> JSONRPCClient -> CodexAppServerClient -> UsageParser -> UsageCache)
/// and prints only normalized usage plus child lifecycle events.
///
/// It never prints raw RPC responses, account identifiers or credential material.
/// Exit codes are fail-closed so they can serve as review evidence (Round 2):
/// 0 success, 2 codex not found, 3 launch failure, 4 read failure,
/// 5 no usable window, 6 cache round-trip failure, 7 child cleanup failure.
@main
struct UsageMonitorCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let options = Options(arguments: arguments)
        if options.help {
            printHelp()
            exit(0)
        }

        print("UsageMonitor smoke diagnostic")
        print("mode: production service (no mock data)")

        // 1. Locate codex, exactly as the app does.
        let executable: URL
        do {
            executable = try CodexLocator().locate()
        } catch let error as UsageError {
            fail(2, error)
        } catch {
            print("result: FAIL"); print("error: \(error)"); exit(2)
        }
        print("codex executable: \(executable.path)")

        // 2. One child process, owned and reaped by this run.
        let transport = JSONRPCClient(executableURL: executable, arguments: ["app-server"])
        let client = CodexAppServerClient(transport: transport)
        var childPID: pid_t = -1
        transport.onExit = { status in
            print("child lifecycle: terminated (status \(status))")
        }

        do {
            try transport.start()
            childPID = transport.childProcessIdentifier
            print("child lifecycle: started `codex app-server` (pid \(childPID))")
        } catch let error as UsageError {
            fail(3, error)
        } catch {
            print("result: FAIL"); print("error: \(error)"); exit(3)
        }

        // 3. Handshake + rate limits through the production client.
        let started = Date()
        let snapshot: UsageSnapshot
        do {
            try client.handshake(timeout: options.timeout)
            print("handshake: initialize + initialized ok")
            snapshot = try client.readRateLimits(timeout: options.timeout)
        } catch let error as UsageError {
            print("error detail: \(error.debugSummary)")
            client.stop()
            print("child lifecycle: stop() issued after failure")
            reportCleanup(childPID: childPID)
            exit(4)
        } catch {
            print("result: FAIL"); print("error: \(error)")
            client.stop()
            reportCleanup(childPID: childPID)
            exit(4)
        }
        let elapsed = Date().timeIntervalSince(started)

        // 4. Normalized output only (no raw payload, no account identifiers).
        print("--- normalized usage ---")
        printWindow("5H", snapshot.fiveHour)
        printWindow("W", snapshot.weekly)
        for unknown in snapshot.unknownWindows {
            print("unknown window: \(unknown.windowDurationMinutes) mins (ignored by UI, kept for diagnostics)")
        }
        print("source: \(snapshot.source == .codexAppServer ? "codex app-server (live)" : "cache")")
        print("fetchedAt: \(formatFullDate(snapshot.fetchedAt))")

        // 5. Cache round trip through the same storage the app uses (fail-closed).
        let suite = "UsageMonitorCLI.Smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let cache = UsageCache(userDefaults: defaults)
        cache.save(snapshot)
        let restored = cache.load()
        let cacheOK = restored != nil
            && restored?.source == .cached
            && restored?.fiveHour?.usedPercent == snapshot.fiveHour?.usedPercent
            && restored?.weekly?.windowDurationMinutes == snapshot.weekly?.windowDurationMinutes
        print("cache: \(cacheOK ? "round trip ok (stored as normalized numbers only, tagged cached)" : "FAILED (values did not survive)")")
        defaults.removePersistentDomain(forName: suite)

        print("rpc duration: \(String(format: "%.2f", elapsed))s")
        let hasWindow = snapshot.fiveHour != nil || snapshot.weekly != nil
        print("result: \(hasWindow && cacheOK ? "PASS" : "FAIL")")

        // 6. Ordered shutdown + verification that nothing is left behind (fail-closed).
        client.stop()
        print("child lifecycle: stop() issued (close stdin, SIGTERM, SIGKILL if needed, reap)")
        let cleanupOK = cleanupVerified(childPID: childPID)
        print("child cleanup: \(cleanupOK ? "verified (pid \(childPID) no longer exists, reaped)" : "FAILED (pid \(childPID) still alive)")")

        if !hasWindow { exit(5) }
        if !cacheOK { exit(6) }
        if !cleanupOK { exit(7) }
        exit(0)
    }

    static func fail(_ code: Int32, _ error: UsageError) -> Never {
        print("result: FAIL")
        print("error: \(UsageFormatting.errorText(error).replacingOccurrences(of: "\n", with: " | "))")
        print("error detail: \(error.debugSummary)")
        exit(code)
    }

    static func printWindow(_ label: String, _ window: RateLimitWindow?) {
        guard let window else {
            print("\(label): unavailable")
            return
        }
        let reset: String
        if let resetsAt = window.resetsAt {
            reset = formatFullDate(resetsAt) + (resetsAt < Date() ? " (already reset)" : "")
        } else {
            reset = "unknown"
        }
        print("\(label): remaining \(Int(window.remainingPercent.rounded()))% (used \(Int(window.usedPercent.rounded()))%), window \(window.windowDurationMinutes) mins, resets \(reset)")
    }

    /// Proves the child was terminated and reaped: signal 0 must fail with ESRCH.
    static func cleanupVerified(childPID: pid_t) -> Bool {
        guard childPID > 0 else { return true }
        Thread.sleep(forTimeInterval: 0.2)
        return kill(childPID, 0) == -1 && errno == ESRCH
    }

    static func reportCleanup(childPID: pid_t) {
        let ok = cleanupVerified(childPID: childPID)
        print("child cleanup: \(ok ? "verified (pid \(childPID) no longer exists, reaped)" : "FAILED (pid \(childPID) still alive)")")
    }

    static func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        return formatter.string(from: date)
    }

    static func printHelp() {
        print("""
        Usage: UsageMonitorCLI [--timeout <seconds>] [--help]

        Connects to the local `codex app-server` using the same production code path as
        the menu bar app and prints normalized usage plus child lifecycle events.
        No raw RPC payloads, account identifiers or credential material are printed.
        Exit codes: 0 ok, 2 no codex, 3 launch failure, 4 read failure,
        5 no usable window, 6 cache failure, 7 child cleanup failure.
        """)
    }

    struct Options {
        var timeout: TimeInterval = 5
        var help = false

        init(arguments: [String]) {
            var index = 0
            while index < arguments.count {
                switch arguments[index] {
                case "--timeout", "-t":
                    index += 1
                    if index < arguments.count, let value = TimeInterval(arguments[index]), value > 0 {
                        timeout = value
                    }
                case "--help", "-h":
                    help = true
                default:
                    break
                }
                index += 1
            }
        }
    }
}

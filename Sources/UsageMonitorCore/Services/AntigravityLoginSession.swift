import Foundation
import Darwin

/// The user sees the official onboarding screen. The only inputs are navigation,
/// confirmation, and a one-time code; no arbitrary prompt can be sent to a model.
public final class AntigravityLoginSession: @unchecked Sendable {
    public enum Event: Sendable {
        case screen(String, URL?)
        case stage(Stage)
        case identity(String)
        case failed(Failure)
    }
    public enum Failure: Error, Sendable { case launch, timedOut, exited, outputLimit, unsupportedPrompt, authenticationRejected, authenticationTransport, licenseUnavailable, inputFailed, confirmationTimedOut }
    public enum Navigation { case up, down, left, right, toggle, confirm }
    public enum Stage: String, Sendable { case starting, onboarding, awaitingCode, verifying, ready, failed, cancelled }
    private var stage: Stage = .starting
    private let lock = NSLock()
    private var master: Int32 = -1
    private var cancelled = false
    private var inputFailed = false
    private var codeSubmitted = false
    private var bracketedPaste = false
    private var submittedAt: TimeInterval?
    public let environment: AntigravityCLIEnvironment
    private let testArguments: [String]?

    public init(environment: AntigravityCLIEnvironment) { self.environment = environment; self.testArguments = nil }
    internal init(testEnvironment: AntigravityCLIEnvironment, arguments: [String]) { self.environment = testEnvironment; self.testArguments = arguments }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func navigate(_ navigation: Navigation) {
        lock.lock(); defer { lock.unlock() }
        guard master >= 0, !cancelled, stage == .onboarding else { return }
        let input: String
        switch navigation { case .up: input = "\u{1B}[A"; case .down: input = "\u{1B}[B"; case .left: input = "\u{1B}[D"; case .right: input = "\u{1B}[C"; case .toggle: input = "\r"; case .confirm: input = "\r" }
        _ = writeLocked(input)
    }
    @discardableResult public func submit(code: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard master >= 0, !cancelled, stage == .awaitingCode, !codeSubmitted,
              !code.isEmpty, code.utf8.count <= 16_384,
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_/+.=".contains($0)) }) else { return false }
        let input = bracketedPaste ? "\u{1B}[200~" + code + "\u{1B}[201~" : code
        guard writeLocked(input) else { inputFailed = true; return false }
        // Deliver confirmation after the paste event has reached the official TUI.
        Thread.sleep(forTimeInterval: 0.1)
        guard writeLocked(bracketedPaste ? "\r" : "\n") else { inputFailed = true; return false }
        codeSubmitted = true; stage = .verifying
        submittedAt = ProcessInfo.processInfo.systemUptime
        return true
    }
    private func writeLocked(_ input: String) -> Bool {
        // A nonblocking PTY write may consume only a prefix of a long pasted code.
        // Send every byte, bounded in time, without saving any input or output.
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        return input.utf8CString.withUnsafeBufferPointer { bytes in
            var offset = 0
            while offset < bytes.count - 1 {
                let count = write(master, bytes.baseAddress! + offset, min(512, bytes.count - 1 - offset))
                if count > 0 { offset += count; continue }
                if count == -1 && errno == EINTR { continue }
                guard count == -1 && (errno == EAGAIN || errno == EWOULDBLOCK),
                      ProcessInfo.processInfo.systemUptime < deadline else { return false }
                var descriptor = pollfd(fd: master, events: Int16(POLLOUT), revents: 0)
                _ = poll(&descriptor, 1, 10)
            }
            return true
        }
    }
    public static func onboardingDisplay(_ screen: String) -> String? {
        let text = screen.lowercased()
        let title: String
        let choices: [(String, String)]
        if text.contains("select login method:") && text.contains("google oauth") {
            title = "官方 CLI：请选择 Google OAuth 登录"; choices = [("google oauth", "Google OAuth"), ("google cloud project", "Google Cloud project（本功能不使用）")]
        } else if text.contains("choose") && text.contains("theme") || text.contains("select a theme") || text.contains("choose your color scheme:") && !text.contains("terms of service") {
            title = "官方 CLI：选择外观"; choices = [("terminal", "Terminal"), ("solarized light", "Solarized Light"), ("colorblind-friendly light", "Colorblind Light"), ("solarized dark", "Solarized Dark"), ("colorblind-friendly dark", "Colorblind Dark"), ("tokyo night", "Tokyo Night"), ("dark", "Dark"), ("light", "Light"), ("system", "System")]
        } else if text.contains("terms of service") || text.contains("improve") && (text.contains("interaction") || text.contains("data")) {
            title = "官方 CLI：服务条款与可选数据收集。请关闭改进产品的数据选项，再确认条款。"
            choices = [("improve", "允许使用交互数据改进产品（可选，请关闭）"), ("agree", "同意条款"), ("accept", "接受条款"), ("decline", "拒绝"), ("done", "完成引导（确认条款）"), ("previous", "上一步")]
        } else if text.contains("trust") && (text.contains("directory") || text.contains("folder") || text.contains("workspace")) {
            title = "官方 CLI：确认 Minget 专用工作目录"
            choices = [("trust", "信任此专用目录"), ("yes", "是"), ("no,", "否"), ("cancel", "取消")]
        } else { return nil }
        let rows = screen.components(separatedBy: "\n").compactMap { line -> String? in
            let lower = line.lowercased()
            if title.contains("服务条款"), lower.contains("previous"), lower.contains("done") {
                func selected(_ label: String) -> Bool {
                    lower.range(of: "[>❯›▸▶]\\s*\\[?" + label, options: .regularExpression) != nil
                }
                return (selected("previous") ? "→ " : "  ") + "上一步\n"
                    + (selected("done") ? "→ " : "  ") + "完成引导（确认条款）"
            }
            let choice: (String, String)?
            if text.contains("choose your color scheme:") && !text.contains("terms of service") {
                let left = lower.components(separatedBy: "│").first!.trimmingCharacters(in: CharacterSet(charactersIn: " >❯›▸▶"))
                choice = choices.first(where: { left == $0.0 })
            } else { choice = choices.first(where: { lower.contains($0.0) }) }
            guard let choice else { return nil }
            let marker = line.contains("❯") || line.contains("›") || line.contains("▸") || line.contains("▶") || line.contains(">") ? "→ " : "  "
            let check = line.contains("[x]") || line.contains("[X]") || line.contains("☑") || line.contains("✓") || line.contains("◉") || line.contains("☒") ? "[已勾选] " : line.contains("[ ]") || line.contains("☐") || line.contains("○") ? "[未勾选] " : ""
            return marker + check + choice.1
        }
        return ([title] + rows).joined(separator: "\n")
    }
    public static func safeFailureContext(_ screen: String) -> String {
        let text = screen.lowercased()
        let markers: [(String, String)] = [
            ("license selection failed", "官方套餐选择失败"),
            ("license fetch failed", "官方套餐读取失败"),
            ("secpolicycreatessl", "系统证书策略初始化失败"),
            ("token exchange failed", "官方令牌交换失败"),
            ("permission denied", "官方返回权限不足"),
            ("http 403", "官方返回 HTTP 403"), ("http 429", "官方返回 HTTP 429"),
            ("timed out", "官方请求超时"), ("deadline exceeded", "官方请求超时"),
            ("press enter to return", "官方要求按 Enter 返回"),
            ("press enter to continue", "官方要求按 Enter 继续"),
            ("select an option", "官方要求选择选项"),
            ("terms of service", "官方显示服务条款"),
            ("trust", "官方显示目录信任提示")
        ]
        let found = markers.filter { text.contains($0.0) }.map { $0.1 }
        return found.isEmpty ? "官方出现未适配提示，账号未提交。" : Array(Set(found)).sorted().joined(separator: "\n")
    }
    private static func hasUnknownPrompt(_ screen: String) -> Bool {
        let text = screen.lowercased()
        return text.contains("press enter to") || text.contains("select an option")
    }
    public func run(timeout: TimeInterval = 300, confirmationTimeout: TimeInterval = 45, receive: @escaping @Sendable (Event) -> Void) {
        var finalEvent: Event?
        defer { if let finalEvent { receive(finalEvent) } }
        do { try environment.prepare(); if testArguments == nil { try AntigravityCLILocator.validate(environment.executable) } }
        catch { finalEvent = .failed(.launch); return }
        var primary: Int32 = -1, secondary: Int32 = -1
        var size = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &secondary, nil, nil, &size) == 0 else { finalEvent = .failed(.launch); return }
        defer { lock.lock(); master = -1; close(primary); close(secondary); lock.unlock() }
        // Do not echo the pasted authorization code back into the terminal stream.
        var settings = termios()
        if tcgetattr(secondary, &settings) == 0 { settings.c_lflag &= ~tcflag_t(ECHO | ICANON); _ = tcsetattr(secondary, TCSANOW, &settings) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0, posix_spawnattr_init(&attributes) == 0 else { finalEvent = .failed(.launch); return }
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        // Each CLI UI must be able to reopen /dev/tty in its own session.
        // Duplicating a PTY without a controlling terminal leaves later UI input unreliable.
        guard let slaveName = ttyname(secondary) else { finalEvent = .failed(.launch); return }
        let slavePath = String(cString: slaveName)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, slavePath, O_RDWR, 0)
        for fd in [STDOUT_FILENO, STDERR_FILENO] { posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, fd) }
        posix_spawn_file_actions_addclose(&actions, secondary)
        posix_spawn_file_actions_addclose(&actions, primary)
        posix_spawn_file_actions_addchdir_np(&actions, environment.workspace.path)
        let launchPath = testArguments == nil ? "/usr/bin/sandbox-exec" : environment.executable.path
        let args = (testArguments.map { [environment.executable.path] + $0 } ?? environment.arguments(["--log-file", "/dev/null"])).map { strdup($0) }
        let env = environment.environment(interactive: true).map { strdup($0) }
        defer { (args + env).forEach { free($0) } }
        var argv = args + [nil], envp = env + [nil], pid: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { a in envp.withUnsafeMutableBufferPointer { e in
            posix_spawn(&pid, launchPath, &actions, &attributes, a.baseAddress!, e.baseAddress!)
        } }
        guard result == 0 else { finalEvent = .failed(.launch); return }
        close(secondary); secondary = -1
        _ = fcntl(primary, F_SETFL, O_NONBLOCK)
        lock.lock(); master = primary; lock.unlock()
        var status: Int32 = 0, exited = false
        defer { _ = kill(-pid, SIGKILL); if !exited { while waitpid(pid, &status, 0) == -1 && errno == EINTR {} } }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var raw = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        var previous = "", url: URL?, previousURL: URL?
        while true {
            lock.lock(); let stop = cancelled, submitted = codeSubmitted, codeTime = submittedAt, currentStage = stage, failedInput = inputFailed; lock.unlock()
            if stop { return }
            if failedInput { finalEvent = .failed(.inputFailed); return }
            if currentStage == .verifying, let codeTime,
               ProcessInfo.processInfo.systemUptime - codeTime >= confirmationTimeout {
                finalEvent = .failed(.confirmationTimedOut); return
            }
            if ProcessInfo.processInfo.systemUptime >= deadline { finalEvent = .failed(.timedOut); return }
            let count = read(primary, &buffer, buffer.count)
            if count > 0 {
                raw.append(contentsOf: buffer.prefix(count))
                guard raw.count <= 524_288 else { finalEvent = .failed(.outputLimit); return }
                let terminal = String(decoding: raw, as: UTF8.self)
                let enabled = terminal.range(of: "\u{1B}[?2004h", options: .backwards)
                let disabled = terminal.range(of: "\u{1B}[?2004l", options: .backwards)
                lock.lock(); bracketedPaste = enabled != nil && (disabled == nil || enabled!.lowerBound > disabled!.lowerBound); lock.unlock()
                let screen = AntigravityTerminal.screen(raw)
                // Only recognized onboarding screens accept navigation. Never forward input
                // to the model prompt. After code submission, show curated onboarding labels
                // instead of any terminal text which could contain a code echo or fragment.
                let lower = screen.lowercased()
                if submitted && (lower.contains("secpolicycreatessl") || lower.contains("token exchange failed") && !lower.contains("invalid_grant")) {
                    finalEvent = .failed(.authenticationTransport); return
                }
                if submitted && ["invalid_grant", "invalid authorization code", "authentication failed", "failed to authenticate"].contains(where: lower.contains) {
                    finalEvent = .failed(.authenticationRejected); return
                }
                if submitted && (lower.contains("license selection failed") || lower.contains("license fetch failed")) {
                    receive(.screen(Self.safeFailureContext(screen), nil))
                    finalEvent = .failed(.licenseUnavailable); return
                }
                let onboarding = Self.onboardingDisplay(screen)
                let identity = AntigravityTerminal.identity(in: screen)
                let next: Stage
                if onboarding != nil { next = .onboarding; url = nil }
                else if identity != nil { next = .ready; url = nil }
                else if submitted { next = .verifying; url = nil }
                else {
                    url = AntigravityTerminal.authenticationURL(in: AntigravityTerminal.plainText(raw))
                    next = url == nil ? .starting : .awaitingCode
                }
                lock.lock()
                if next == .verifying && stage == .onboarding { submittedAt = ProcessInfo.processInfo.systemUptime }
                stage = next; lock.unlock()
                receive(.stage(next))
                if let email = identity, next == .ready { finalEvent = .identity(email); return }
                let display = onboarding ?? (submitted ? "授权码已提交，正在等待官方身份确认…" : AntigravityTerminal.redacted(screen))
                if display != previous || url != previousURL { previous = display; previousURL = url; receive(.screen(display, url)) }
                if (next == .starting || next == .verifying) && Self.hasUnknownPrompt(screen) {
                    receive(.screen(Self.safeFailureContext(screen), nil))
                    finalEvent = .failed(.unsupportedPrompt); return
                }
            }
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { exited = true; finalEvent = .failed(.exited); return }
            if waited == -1 && errno != EINTR { finalEvent = .failed(.exited); return }
            Thread.sleep(forTimeInterval: 0.03)
        }
    }
}

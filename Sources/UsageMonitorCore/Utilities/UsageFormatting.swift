import Foundation

/// Pure text formatting for the menu bar and the panel. Kept in core so it can be
/// unit tested without launching the UI.
public enum UsageFormatting {

    // MARK: Menu bar

    /// `5H 78% | W 42%`. A window with no data shows `–`. A stale snapshot adds `⚠`.
    public static func menuBarTitle(fiveHour: RateLimitWindow?, weekly: RateLimitWindow?, isStale: Bool) -> String {
        let five = fiveHour.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "–"
        let week = weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "–"
        var title = "5H \(five) | W \(week)"
        if isStale { title += " ⚠" }
        return title
    }

    /// Compact variant used when menu bar space is tight: `78% / 42%`.
    public static func compactMenuBarTitle(fiveHour: RateLimitWindow?, weekly: RateLimitWindow?, isStale: Bool) -> String {
        let five = fiveHour.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "–"
        let week = weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "–"
        var title = "\(five) / \(week)"
        if isStale { title += " ⚠" }
        return title
    }

    // MARK: Panel

    /// Chinese display name for a window kind.
    public static func windowName(_ kind: RateLimitWindow.Kind) -> String {
        switch kind {
        case .fiveHour: return "5 小时额度"
        case .weekly: return "周额度"
        case .unknown: return "其他窗口"
        }
    }

    /// Short name used by the menu bar: `5H` / `W`.
    public static func windowShortName(_ kind: RateLimitWindow.Kind) -> String {
        switch kind {
        case .fiveHour: return "5H"
        case .weekly: return "W"
        case .unknown: return "?"
        }
    }

    /// `剩余 78%` — always explicit that the number is *remaining* (PROJECT_SPEC.md §5).
    public static func remainingText(_ window: RateLimitWindow) -> String {
        "剩余 \(Int(window.remainingPercent.rounded()))%"
    }

    /// Reset time: `重置 14:35` for today, `重置 09-13 11:20` otherwise.
    /// A reset already in the past is rendered as a past time, never as a future one.
    public static func resetText(_ window: RateLimitWindow, now: Date = Date()) -> String {
        guard let resetsAt = window.resetsAt else { return "重置时间未知" }
        let time = formatClock(resetsAt)
        if resetsAt < now {
            return "已于 \(formatDate(resetsAt)) \(time) 重置"
        }
        if Calendar.current.isDateInToday(resetsAt) {
            return "重置 \(time)"
        }
        return "重置 \(formatDate(resetsAt)) \(time)"
    }

    /// Error text for the panel (PROJECT_SPEC.md §13 A-F). Fixed labels only: upstream
    /// message text never reaches the UI (Round 2 blocker 5).
    public static func errorText(_ error: UsageError) -> String {
        switch error {
        case .codexCLINotFound:
            return "未找到 Codex 命令行\nCodex CLI not found"
        case .codexNotSignedIn:
            return "Codex 未登录\nCodex is not signed in"
        case .appServerStartupFailed:
            return "无法启动 Codex app-server\nUnable to start Codex app-server"
        case .rpcFailed(let reason):
            return "无法读取用量\nUnable to read usage" + reasonSuffix(reason)
        case .windowUnavailable(let kind):
            switch kind {
            case .fiveHour: return "5 小时额度不可用\n5-hour usage unavailable"
            case .weekly: return "周额度不可用\nWeekly usage unavailable"
            case .unknown: return "该窗口不可用"
            }
        }
    }

    /// Short, fixed hint appended for known RPC reasons. No upstream text.
    private static func reasonSuffix(_ reason: RPCFailureReason) -> String {
        switch reason {
        case .timedOut: return "\n（请求超时）"
        case .serverError: return "\n（服务返回错误）"
        case .transportClosed: return "\n（连接已断开）"
        case .malformedResponse, .invalidPayload: return "\n（返回数据格式不可用）"
        case .writeFailed, .launchFailed: return "\n（本地通信失败）"
        case .shutdown, .noReply, .other: return ""
        }
    }

    /// Stale banner: how old the displayed data is.
    public static func stalenessText(fetchedAt: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(fetchedAt).rounded()))
        if seconds < 60 { return "当前无法获取最新数据，显示 \(seconds) 秒前的数据" }
        let minutes = Int((Double(seconds) / 60).rounded())
        return "当前无法获取最新数据，显示 \(minutes) 分钟前的数据"
    }

    /// `更新于 10 秒前`.
    public static func updatedText(fetchedAt: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(fetchedAt).rounded()))
        if seconds < 5 { return "刚刚更新" }
        if seconds < 60 { return "更新于 \(seconds) 秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "更新于 \(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "更新于 \(hours) 小时前" }
        return "更新于 \(hours / 24) 天前"
    }

    /// Colour bucket from PROJECT_SPEC.md §12.3.
    public static func usageLevel(remainingPercent: Double) -> UsageLevel {
        if remainingPercent > 50 { return .normal }
        if remainingPercent >= 20 { return .warning }
        return .critical
    }

    public enum UsageLevel: String, Sendable {
        case normal, warning, critical
    }

    // MARK: Helpers

    static func formatClock(_ date: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "zh_CN")) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func formatDate(_ date: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "zh_CN")) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }
}

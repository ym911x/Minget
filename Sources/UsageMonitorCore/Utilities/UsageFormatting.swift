import Foundation

/// Pure text formatting for the menu bar and the panel. Kept in core so it can be
/// unit tested without launching the UI.
public enum UsageFormatting {

    // MARK: Menu bar

    /// `5H 78% | W 42%`. A window with no data shows `–`.
    ///
    /// v1.0.2 requirement 4: the quota text carries no marker at all. The single abnormal
    /// marker is decided by `MenuBarContentBuilder` and drawn in front of this text, so a
    /// cached snapshot can never produce a trailing `⚠` on top of a leading one.
    public static func menuBarTitle(fiveHour: RateLimitWindow?, weekly: RateLimitWindow?) -> String {
        "5H \(percent(fiveHour)) | W \(percent(weekly))"
    }

    /// Compact variant used when menu bar space is tight: `5H 78% W 42%`.
    ///
    /// Still starts with `5H` and still carries both numbers; only the separator and the
    /// padding are dropped (v1.0.2 §3.3).
    public static func compactMenuBarTitle(fiveHour: RateLimitWindow?, weekly: RateLimitWindow?) -> String {
        "5H \(percent(fiveHour)) W \(percent(weekly))"
    }

    /// Rounded remaining percent, or `–` when the window is missing. Never a fabricated 0.
    private static func percent(_ window: RateLimitWindow?) -> String {
        guard let window else { return "–" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    // MARK: 1.3.0 labelled menu bar content

    /// Placeholder for a missing number in the 1.3.0 menu bar formats. UI_SPEC.md §8 writes
    /// these as an em dash, distinct from the en dash the 1.0.2 panel helpers use.
    public static let menuBarPlaceholder = "—"

    /// Rounded remaining percent with the 1.3.0 placeholder, never a fabricated 0.
    public static func menuBarPercentText(_ window: RateLimitWindow?) -> String {
        guard let window else { return menuBarPlaceholder }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    /// Full ChatGPT menu bar text: `A 5H 78% | W 42%` (UI_SPEC.md §8).
    ///
    /// A window with no data shows `A 5H — | W —`; the account's short label is always
    /// present, so the user can tell which account the item is showing.
    public static func labeledMenuBarTitle(shortLabel: String,
                                           fiveHour: RateLimitWindow?,
                                           weekly: RateLimitWindow?) -> String {
        let prefix = shortLabel.isEmpty ? "" : "\(shortLabel) "
        return "\(prefix)5H \(menuBarPercentText(fiveHour)) | W \(menuBarPercentText(weekly))"
    }

    /// Compact ChatGPT menu bar text: `A 78% 42%`. Both quota values survive; only the
    /// separator and the `5H`/`W` words are dropped.
    public static func labeledCompactMenuBarTitle(shortLabel: String,
                                                  fiveHour: RateLimitWindow?,
                                                  weekly: RateLimitWindow?) -> String {
        let prefix = shortLabel.isEmpty ? "" : "\(shortLabel) "
        return "\(prefix)\(menuBarPercentText(fiveHour)) \(menuBarPercentText(weekly))"
    }

    /// Fixed two decimals with no grouping, as UI_SPEC.md §8 requires for the DeepSeek menu
    /// bar amount. Display-only: the underlying `Decimal` is not changed.
    public static func menuBarAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? menuBarPlaceholder
    }

    /// Full DeepSeek menu bar text: `DS CNY 123.45`. With no currency reported the
    /// position is kept but explicitly unnamed: `DS — 123.45`. No code is ever guessed.
    public static func deepSeekMenuBarTitle(currency: String?, amount: Decimal?) -> String {
        guard let amount else { return "DS \(menuBarPlaceholder)" }
        let text = menuBarAmount(amount)
        guard let currency, !currency.isEmpty else { return "DS \(menuBarPlaceholder) \(text)" }
        return "DS \(currency) \(text)"
    }

    /// Compact DeepSeek menu bar text: `DS CNY 123.45`.
    public static func compactDeepSeekMenuBarTitle(currency: String?, amount: Decimal?) -> String {
        guard let amount else { return "DS \(menuBarPlaceholder)" }
        let text = menuBarAmount(amount)
        guard let currency, !currency.isEmpty else { return "DS \(menuBarPlaceholder) \(text)" }
        return "DS \(currency) \(text)"
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
    ///
    /// A reset time that has been reached is reported as waiting for a refresh. The app only
    /// knows the clock passed the time the service once reported; it does not know the
    /// service has renewed the window, so it never claims `已于 … 重置` (v1.0.2 §4.3).
    public static func resetText(_ window: RateLimitWindow, now: Date = Date()) -> String {
        guard let resetsAt = window.resetsAt else { return "重置时间未知" }
        if resetsAt <= now {
            return "已到重置时间，等待刷新确认"
        }
        let time = formatClock(resetsAt)
        if Calendar.current.isDateInToday(resetsAt) {
            return "重置 \(time)"
        }
        return "重置 \(formatDate(resetsAt)) \(time)"
    }

    /// Absolute reset point used by the compact detail card. The segmented bar carries the
    /// approximate remaining-time shape; this label gives the user the exact local time.
    /// A missing reset is kept explicit and a passed reset is still shown as a date because
    /// the service has not necessarily supplied a new window yet.
    public static func resetPointText(_ window: RateLimitWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "时间未知" }
        return "\(formatDate(resetsAt)) \(formatClock(resetsAt))"
    }

    /// `09-30`. Used where a date appears without a time (the monthly cycle end).
    public static func shortDate(_ date: Date) -> String {
        formatDate(date)
    }

    /// `09-17 05:35`. Used where a date and a clock time appear together.
    public static func shortDateTime(_ date: Date) -> String {
        "\(formatDate(date)) \(formatClock(date))"
    }

    /// Displays the optional earned-reset summary. Cached snapshots intentionally do not
    /// claim that a reset is currently available because the credit may have been consumed
    /// elsewhere after the snapshot was written.
    public static func rateLimitResetText(_ credits: RateLimitResetCredits?,
                                          source: UsageSource,
                                          now: Date = Date()) -> String {
        guard source == .codexAppServer, let credits else { return "重置信息暂不可用" }
        let countText = "可用重置 \(credits.availableCount) 次"
        guard let expiry = credits.nearestExpiresAt, expiry > now else { return countText }
        return "\(countText) · 最近到期 \(formatDate(expiry)) \(formatClock(expiry))"
    }

    /// USD values in the Command Code card use a fixed two-decimal presentation.
    /// The underlying Decimal remains unchanged; rounding is display-only.
    public static func usdAmount(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value)).map { "$" + $0 } ?? "—"
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

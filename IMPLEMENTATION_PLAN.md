# Implementation plan and verified protocol

## Baseline 2026-09-09
Only the supplied v1.0 specification existed; no application or graph index.
macOS arm64, Xcode at /Applications/Xcode.app/Contents/Developer, Swift 6.3.3.
Codex CLI 0.153.4: /Applications/ChatGPT.app/Contents/Resources/codex.
Claude Code 2.1.220, configured provider https://open.bigmodel.cn/api/anthropic; explicitly request glm-5.3-flash. Configuration identifies requested model, not independent proof of provider internals.

## Protocol evidence
Official source fetched: https://learn.chatgpt.com/docs/app-server (Rate limits, Initialization).
Live local probe succeeded with newline-delimited JSON on stdio:
{"id":1,"method":"initialize","params":{"clientInfo":{"name":"usage_monitor_probe","version":"0.1.0"}}}
Then {"method":"initialized"}, then {"id":2,"method":"account/rateLimits/read","params":{}}.
No experimental capability required. Response result has rateLimits and rateLimitsByLimitId.codex. Prefer codex map entry, fall back to legacy only when appropriate; never accidentally select another bucket.
Observed primary usedPercent=9, windowDurationMins=300, resetsAt=1788935373; secondary usedPercent=5, windowDurationMins=10080, resetsAt=1789453767. This is a historical sample, not a fixture for live UI.
Probe terminated and reaped its own child. Do not persist full responses/account IDs/reset-credit IDs. No authentication response needed.

## Design decisions
Scope: macOS MVP only, title Codex 用量; clarify these are Codex account limits, not every ChatGPT model's message allowance.
Use native SwiftUI MenuBarExtra with clean Chinese text, approximately 300 pt panel, explicit remaining labels, system colors/accessibility labels.
Separate parser, transport, service/cache, view model, UI. Prefer dependency-free Swift Package for core/tests and build a runnable .app with Info.plist LSUIElement; provide xcodebuild-compatible validation if possible. No Xcode project generator downloads required.
Resolve executable via explicit override/environment or known installation paths including observed ChatGPT.app path; Finder PATH is sparse. Do not execute arbitrary shell interpolation.
Long-lived child per application, newline buffer handles split UTF-8 and multiple messages, concurrent request ID routing, 5 second timeout, stderr drained without logging raw content. Bounded buffer, safe non-JSON handling, no continuation leaks, no main-thread blocking. At most one automatic restart for app-server failure, no periodic infinite restart loop. Close pipes, terminate then bounded kill only owned PID, reap.
All missing/null fields are unavailable, never zero. Classify by 300/10080 durations, clamp finite values. Unknown duration preserved for diagnostics. Prefer codex map and avoid mixing buckets. Reject invalid payloads without destroying valid cached snapshot.
60 second refresh; on panel open refresh if older than 30 sec; manual refresh; single in-flight request; cache marked stale until successful network response; fetchedAt retains actual successful time. Cache only normalized usage data. Distinguish missing CLI, not signed in, startup/RPC errors and missing windows. Do not show past reset as a future reset.

## Delivery and review
Round 1: Claude implements app, meaningful parser/transport/cache/lifecycle tests, build/bundle scripts, README and report.
Codex independently reviews scope, build, tests, runtime, real data, correctness, security, cleanup, UI and DoD in that order.
Rounds 2-5 only for specific findings. Final evidence must include app visible, real fetch, official Usage UI comparison including resets, manual/automatic refresh and owned child cleanup. Missing UI access is an explicit blocker, never PASS.

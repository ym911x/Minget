# ROUND 1 REPORT — UsageMonitor macOS MVP

日期：2026-09-09  
实施者：Claude Code（GLM-5.3-Flash）  
依据：PROJECT_SPEC.md、AGENTS.md、IMPLEMENTATION_PLAN.md、ROUND_1_TASK.md  
状态：Round 1 完成，等待 Codex Review。不宣布整体 COMPLETE。

---

## 1. 本轮完成内容

1. Swift Package（无第三方依赖）：核心库 `UsageMonitorCore`、菜单栏应用 `UsageMonitorApp`、QA 诊断 `UsageMonitorCLI`。
2. 传输层：stdio JSON-RPC 客户端，支持换行分帧、分片重组（含跨块 UTF-8）、一次读取多条消息、并发请求 ID 路由、超时、子进程退出处理、stderr 排空丢弃、有序关闭（close stdin → SIGTERM → SIGKILL → reap）。
3. 解析层：`UsageParser` 将 `account/rateLimits/read` 的 result 归一化为 `UsageSnapshot`。优先取 `rateLimitsByLimitId.codex`，禁止混用其他 bucket；按 `windowDurationMins` 分类（300 → fiveHour，10080 → weekly，其他 → unknown 并保留用于诊断）；缺失/null/非有限数值一律视为不可用，不当作 0；`remainingPercent = max(0, min(100, 100 - usedPercent))`。
4. 服务层：`UsageService` 单请求在途、失败返回缓存并标记 `.cached`、每次失败最多自动重启一次、`fetchedAt` 保留最近一次成功时间；`UsageCache` 仅存归一化数字；`CodexLocator` 支持 `USAGE_MONITOR_CODEX_PATH` 覆盖与已知安装路径探测（无 shell 插值）。
5. UI：SwiftUI `MenuBarExtra`（`menuBarExtraStyle(.window)`，300 pt 面板），菜单栏 `5H 78% | W 42%`（缓存时追加 ⚠），面板含 5 小时/周额度条形、剩余百分比文字、重置时间、更新时间、立即刷新、退出；错误状态按 PROJECT_SPEC.md §13 A–F 区分；颜色仅作辅助，百分比文字始终保留；带无障碍标签。
6. 刷新策略：启动立即刷新、每 60 秒、打开面板时超过 30 秒刷新、手动强制刷新（spec §10）。
7. 构建：`scripts/build.sh` 产出 `dist/UsageMonitor.app`（Info.plist 含 `LSUIElement`，ad-hoc 签名，内含 `UsageMonitorCLI`）。
8. 测试：54 个测试，覆盖规范要求的 10 个用例及分帧、多 bucket 优先级、空值、超时/退出、缓存新鲜度。

## 2. 文件清单

新增：

```
Package.swift
README.md
scripts/build.sh
Sources/UsageMonitorCore/Models/RateLimitWindow.swift
Sources/UsageMonitorCore/Models/UsageSnapshot.swift
Sources/UsageMonitorCore/Models/UsageError.swift
Sources/UsageMonitorCore/Services/CodexLocator.swift
Sources/UsageMonitorCore/Services/JSONRPCClient.swift
Sources/UsageMonitorCore/Services/MessageFramer.swift
Sources/UsageMonitorCore/Services/CodexAppServerClient.swift
Sources/UsageMonitorCore/Services/UsageParser.swift
Sources/UsageMonitorCore/Services/UsageService.swift
Sources/UsageMonitorCore/Services/UsageCache.swift
Sources/UsageMonitorCore/Utilities/UsageFormatting.swift
Sources/UsageMonitorCore/Utilities/Diagnostics.swift
Sources/UsageMonitorApp/UsageMonitorApp.swift
Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift
Sources/UsageMonitorApp/Views/UsagePanelView.swift
Sources/UsageMonitorApp/Views/UsageRowView.swift
Sources/UsageMonitorApp/Views/ErrorStateView.swift
Sources/UsageMonitorCLI/UsageMonitorCLI.swift
Tests/UsageMonitorCoreTests/UsageParserTests.swift        (20 tests)
Tests/UsageMonitorCoreTests/UsageSnapshotTests.swift      (4 tests)
Tests/UsageMonitorCoreTests/JSONRPCTransportTests.swift   (11 tests)
Tests/UsageMonitorCoreTests/UsageServiceTests.swift       (13 tests)
Tests/UsageMonitorCoreTests/UsageFormattingTests.swift    (6 tests)
```

未改动：PROJECT_SPEC.md、IMPLEMENTATION_PLAN.md、ROUND_1_TASK.md、REVIEW.md。（`git status` 显示的 `AGENTS.md`、`REVIEW.md` 修改与 `ACCEPTANCE.md`、`ROUND_1_CONTINUE.md` 为本轮开始前已存在的仓库状态，非我所改。）

## 3. 构建结果

| 命令 | 结果 |
| --- | --- |
| `swift build --package-path .` | Build complete，0 warning，0 error |
| `./scripts/build.sh` | 生成 `dist/UsageMonitor.app`，`codesign --verify` 通过，`plutil -lint Info.plist` OK |
| `xcodebuild -scheme UsageMonitor-Package -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |

## 4. 测试结果

| 命令 | 结果 |
| --- | --- |
| `swift test --package-path .` | `Executed 54 tests, with 0 failures (0 unexpected)` |
| `xcodebuild -scheme UsageMonitor-Package -destination 'platform=macOS' test` | `** TEST SUCCEEDED **`，`Executed 54 tests, with 0 failures` |

规范 10 个必测用例对应：

| 用例 | 测试 |
| --- | --- |
| Test 1 usedPercent 25 → 75 | `testUsedPercent25YieldsRemaining75` |
| Test 2 300 → fiveHour | `test300MinutesClassifiesFiveHour` |
| Test 3 10080 → weekly | `test10080MinutesClassifiesWeekly` |
| Test 4 primary/secondary 互换 | `testPrimarySecondarySwappedStillClassifiedByDuration`（强制项，已实现） |
| Test 5 只有 300 | `testOnlyFiveHourWindowLeavesWeeklyNil` |
| Test 6 只有 10080 | `testOnlyWeeklyWindowLeavesFiveHourNil` |
| Test 7 43800 不崩溃 | `testUnknownDurationPreservedAsUnknownWithoutCrash` |
| Test 8 -5 / 110 钳制 | `testOutOfRangeUsedPercentClampsRemainingTo0Through100` |
| Test 9 RPC 超时保留缓存 | `testTimeoutRetainsCachedSnapshotAndMarksItStale`、`testTimeoutWithoutCacheThrowsInsteadOfFabricatingData` |
| Test 10 Malformed JSON | `testMalformedJSONDoesNotCrash` |

附加：分帧（`testFramerEmitsMultipleMessagesFromSingleChunk`、`testFramerReassemblesMessageSplitAcrossChunks`、`testFramerHandlesUTF8CharacterSplitAcrossChunks`、`testFramerDropsOversizedLineInsteadOfGrowingWithoutBound`）、多 bucket 优先级（`testPrefersCodexBucketFromRateLimitsByLimitId`、`testForeignBucketIsNeverSelectedAccidentally`、`testDoesNotMixWindowsAcrossBuckets`）、空值（`testNullAndNonFiniteValuesAreUnavailable`）、超时/退出（`testRequestTimesOutAndThrowsUsageError`、`testChildExitFailsPendingRequestInsteadOfHanging`、`testStopTerminatesOwnedChildAndReapsIt`）、缓存新鲜度（`testPanelOpenRefreshPolicyUsesThirtySecondThreshold`）。

传输层集成测试使用系统 python3 作为真实子进程（固定字面量脚本，无用户输入参与），因此分帧、超时、退出、回收均为实测。

## 5. 运行时结果（真实数据，非 mock）

### 5.1 首次成功获取（10:42:31 +08:00）

```
$ dist/UsageMonitor.app/Contents/MacOS/UsageMonitorCLI
codex executable: /Applications/ChatGPT.app/Contents/Resources/codex
child lifecycle: started `codex app-server` (pid 18143)
handshake: initialize + initialized ok
--- normalized usage ---
5H: remaining 7% (used 93%), window 300 mins, resets 2026-09-09 14:29:33 +08:00
W: remaining 82% (used 18%), window 10080 mins, resets 2026-09-15 14:29:27 +08:00
source: codex app-server (live)
fetchedAt: 2026-09-09 10:42:31 +08:00
cache: round trip ok (stored as normalized numbers only, tagged cached)
rpc duration: 1.75s
result: PASS
child lifecycle: terminated (status 15)
child lifecycle: stop() issued (close stdin, SIGTERM, SIGKILL if needed, reap)
child cleanup: verified (pid 18143 no longer exists, reaped)
```

第二次运行同样 PASS（`rpc duration: 1.10s`）。

### 5.2 应用运行时（真实子进程与回收）

```
$ USAGE_MONITOR_LOG_FILE=/tmp/um.log dist/UsageMonitor.app/Contents/MacOS/UsageMonitor
2026-09-09 10:51:05 applicationDidFinishLaunching
2026-09-09 10:51:05 viewmodel start
2026-09-09 10:51:05 refresh requested (isRefreshing=false)
2026-09-09 10:51:05 starting app-server child
2026-09-09 10:51:05 app-server child started
2026-09-09 10:51:06 fetch ok windows=5h:true/weekly:true
2026-09-09 10:51:06 apply success isLive=true error=none

$ ps -axo pid,ppid,command | grep "codex app-server"
19127  19124  /Applications/ChatGPT.app/Contents/Resources/codex app-server   # 父进程即 UsageMonitor

$ kill -TERM 19124
app exited
child reaped（pid 19127 不复存在）
```

缓存内容（`defaults read local.usagemonitor.UsageMonitor`）只含归一化字段：

```json
{
  "fiveHourUsedPercent": 93,
  "fiveHourWindowDurationMinutes": 300,
  "fiveHourResetsAtEpochSeconds": 1788935373,
  "weeklyUsedPercent": 18,
  "weeklyWindowDurationMinutes": 10080,
  "weeklyResetsAtEpochSeconds": 1789453767,
  "fetchedAtEpochSeconds": 1788922266.699
}
```

### 5.3 上游故障时的降级（10:58 之后）

上游 `chatgpt.com/backend-api/wham/usage` 临时不可用，应用侧日志：

```
2026-09-09 11:03:56 fetch failed: rpcFailed(timed out after 5s waiting for account/rateLimits/read)
2026-09-09 11:04:02 apply success isLive=false error=rpcFailed(detail: "timed out after 5s waiting for account/rateLimits/read")
```

即：返回最近一次成功快照并标记 `.cached`，菜单栏显示 `5H 7% | W 82% ⚠`，面板显示过期横幅，60 秒后自动重试，每次失败最多重启一次子进程。原始错误（JSON-RPC -32603 `failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)`）由服务端返回，仅作为错误细节展示，不含凭证。

## 6. 安全检查

- 未读取任何认证文件，未打印任何 token、Cookie、authorization 头或 `auth.json` 内容。
- stderr 只被排空丢弃（`JSONRPCClient.start()`），不落日志。
- 缓存仅含归一化数字（见 5.2）。
- 子进程以 `executableURL + arguments` 直接启动，无 shell 插值；`kill` 仅作用于自己拥有的子 PID。
- 诊断日志默认关闭，需设置 `USAGE_MONITOR_LOG_FILE`，且只写生命周期事件。
- 未修改全局配置，未执行账号重置/登录/登出方法，未做发布。

## 7. 已知问题与限制

1. 上游接口偶发超时或返回 -32603（本机网络或服务端原因）。此时应用显示缓存数据加 ⚠ 与过期横幅，符合 spec §11；数据准确性依赖上游恢复。
2. 菜单栏标题在「某一窗口缺失」时以 `–` 占位（例如 `5H 7% | W –`），面板对应行显示「周额度不可用」；此行为与 spec §13 E/F 一致，但菜单栏的 `–` 表现未在真实缺失场景下人工核对（真实数据两个窗口都存在）。
3. 传输层曾出现的并发缺陷已修复：`DispatchQueue.sync(flags: .barrier)` 在并发队列上不产生真正的 barrier，导致 pending 表读取到过期状态；现改为 `NSLock` 保护并配合 `FileHandle.readabilityHandler` 读取 stdout。
4. `.build/` 位于 iCloud Drive 路径下，极端情况下增量构建可能出现产物未更新的情况；遇到可疑结果请先 `swift package clean` 再构建。
5. `Diagnostics.log` 的 `Date()` 输出为 UTC 表示的本地时间字符串，仅用于 QA 排查，非 UI 内容。

## 8. 尚未完成 / 留给 Codex 验收的事项

1. **与官方 Usage UI 对照**（spec §17「正确性」、§28）：需要人工打开 ChatGPT/Codex Settings → Usage 核对 5H、Weekly 与重置时间。我无法访问该 UI，此项按 IMPLEMENTATION_PLAN.md 的要求必须由 Codex 实测后才能判定 PASS。
2. **菜单栏视觉核查**：菜单栏条目、面板布局与中文文案需 Codex 实机查看确认（我可执行的部分已通过日志与进程证据验证）。
3. **第二阶段 iPhone Widget**：不在本轮范围（spec §18）。
4. 低额度通知、历史趋势、Launch at Login 等后续可选功能（spec §19）。

## 9. 复现命令

```bash
cd "<项目目录>"
swift test                                   # 54 tests, 0 failures
./scripts/build.sh                           # dist/UsageMonitor.app
open dist/UsageMonitor.app                   # 菜单栏显示，60 秒自动刷新
dist/UsageMonitor.app/Contents/MacOS/UsageMonitorCLI --timeout 10
USAGE_MONITOR_LOG_FILE=/tmp/um.log open dist/UsageMonitor.app   # 可选诊断日志
```

## 10. 结论

Round 1 范围内的编码、构建、测试、真实数据链路与子进程生命周期验证已完成；spec §17 的「正确性（对照官方 UI）」与「UI 实机核查」两项验收证据需 Codex 实测补充。整体完成判定权在 Codex，本轮不宣布 COMPLETE。

# ROUND 2 REPORT — UsageMonitor 修订

日期：2026-09-09  
实施者：Claude Code（GLM-5.3-Flash）  
依据：REVIEW.md「REVIEW ROUND 1 (2026-09-09 14:35 +08:00)」、PROJECT_SPEC.md、IMPLEMENTATION_PLAN.md、artifacts/ReviewProbe.swift 及探针日志  
状态：Round 2 修订完成，等待 Codex Review。官方 UI 对照仍未验证。不宣布整体 COMPLETE。

---

## 1. 逐项修复情况

### Blocker 1（P1）数值转换导致崩溃 — 已修复

来源：`artifacts/codex-review-1-overflow.log`（`exit: -5`，`Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max`）、`codex-review-1-probes.log`（`bool accepted remaining: 99`、`fractional duration kind: fiveHour`）。

修复（新增 `Sources/UsageMonitorCore/Utilities/SafeConversion.swift`）：

- `SafeConversion.integer`：只接受有限、绝对值不超过 2^53 且数学上为整数的值；`1e100`、`-1e100`、`Double.greatestFiniteMagnitude`、`300.9`、`0`、负值全部返回 nil，不再发生 `Int(Double)` 陷阱。
- `SafeConversion.double`：拒绝装箱布尔值（用 `CFGetTypeID(number) == CFBooleanGetTypeID()` 判定）。实现中发现两个陷阱并已处理：`NSNumber(value: 1) is Bool` 在 Foundation 里为 true（0/1 可动态转换成 Bool），且 `number === kCFBooleanTrue` 的指针比较会误判；两者都不能用来识别布尔。
- `UsageParser.windowDuration`：要求正整数，`300.9`、`0`、`true` 均不可用。
- `UsageParser.usedPercent`：布尔与不可解析文本不可用；超界数值仍保留并只在显示时钳制（保留 spec Test 8 行为）。
- `JSONRPCClient.requestID` 与 `SafeConversion.errorCode`：JSON-RPC 错误码同样走安全转换，超大或小数错误码返回 `-1`，不再陷阱。

回归测试：`UsageParserTests.testHugeDurationDoesNotTrapAndIsRejected`、`testFractionalDurationIsRejectedInsteadOfTruncated`、`testNonPositiveDurationIsRejected`、`testHugeUsedPercentDoesNotTrap`、布尔用例并入 `testNullAndNonFiniteValuesAreUnavailable`；`DiagnosticsRedactionTests.testErrorCodeConversionNeverTraps`。

### Blocker 2（P1）自动重启预算按次重置 — 已修复

来源：探针 `three failed automatic fetches create clients: 6`。

修复（`Sources/UsageMonitorCore/Services/UsageService.swift`）：

- 引入「失败段」状态：`failureEpisodeActive` / `restartsUsedInEpisode` / `failureEpisodeOpenedAt`。一段连续失败只允许 1 次启动尝试 + 1 次自动重启；失败段打开期间，后续定时刷新直接短路（不启动子进程），返回缓存快照并携带已记录错误。
- 失败段在成功后关闭；冷却（默认 600 秒）结束后允许新一轮尝试；`fetch(resetFailureBudget: true)`（对应 UI「立即刷新」）立即重置。
- 成功路径清零预算与失败段；非可重启错误（未找到 CLI、未登录）不消耗预算。

回归测试：`testThreeConsecutiveFailingFetchesCreateAtMostTwoClients`（期望 2，探针曾测得 6）、`testOpenEpisodeShortCircuitsWithoutLaunchingAndServesCache`、`testEpisodeCooldownReopensTheAttemptBudget`、`testManualRetryResetsTheFailureBudget`、`testSuccessClosesTheFailureEpisode`、`testNonRestartableErrorsNeverConsumeTheBudget`。

### Blocker 3（P1）stop 与 start 竞态、未取消在途任务 — 已修复

来源：探针 `client running after stop raced with start: true`；`UsageService.swift:133-158`、`UsageViewModel.swift:70/102`。

修复：

- `UsageService` 引入 `generation` 代计数与 `startingClient` 槽位：`stop()` 递增 generation、停止当前与启动中的子进程并置 `stopped`；`acquireClient` 在工厂返回后、`start()` 前后都检查 generation，迟到的启动结果不会发布，且会立即被 `stop()` 清理。
- `fetch()` 在每个阶段（启动、握手、读取、重启前）检查 `isStale(generationAtStart)`，停止后立即以固定类别 `.rpcFailed(.shutdown)` 结束，不重启、不覆盖缓存；shutdown 错误不被缓存掩盖。
- `stop()` 幂等，可安全多次调用；`stop()` 之后的 `fetch()` 直接抛 `.shutdown`，不会启动子进程；`resume()` 显式恢复。
- `UsageViewModel`：在途刷新改为持有的 `Task`，`stop()` 会 cancel 并放弃该任务，`apply()` 在已停止或任务被取消时不发布任何状态；定时器一并取消。

回归测试：`testStopDuringStartLeavesNoRunningClient`（对应探针场景：start 阻塞时 stop，释放后断言 `isTransportRunning == false` 且 late child 被停止）、`testStopDuringRestartDelayPreventsLateRestart`、`testFetchAfterStopThrowsShutdownWithoutLaunchingAChild`、`testResumeAllowsFetchingAgain`、`testStopIsIdempotent`、`testShutdownDuringFetchIsNotRetried`。

### Blocker 4（P2）bucket 身份未校验 — 已修复

来源：探针 `foreign bucket accepted: true`（`rateLimits.limitId = "other"` 被当作 Codex）。

修复（`UsageParser.resolveBucket`）：

- `rateLimitsByLimitId` 存在且含 `codex` 时，该条目即权威来源：为空或 null 时返回 `.unavailable(.codexBucketEmpty)`，不再回退到 legacy 对象。
- `rateLimitsByLimitId` 存在但只有其他 limitId：返回 `.unavailable(.foreignLimitBucket)`，拒绝猜测。
- legacy `rateLimits` 带 `limitId` 时必须等于 `codex` 才接受；未标注 limitId 的旧形态仍接受。空的 `rateLimitsByLimitId`（无任何键）视为缺失，允许 legacy 回退。
- 顶层退化形态也要求无 `limitId` 或 `limitId == codex`。
- 不同 bucket 的窗口永不合并。

回归测试：`testForeignLegacyLimitIdIsRejected`、`testEmptyCodexBucketDoesNotFallBackToLegacy`、`testNullCodexEntryDoesNotFallBackToLegacy`、`testForeignBucketWithoutCodexEntryIsNeverSelected`、`testDegenerateTopLevelWindowWithForeignLimitIdIsRejected`、`testForeignBucketIsNeverMixedIntoCodexSnapshot`、`testLegacySnapshotWithoutLimitIdIsAccepted`、`testLegacyCodexLimitIdIsAccepted`。

### Blocker 5（P2）远程错误文本进入诊断 — 已修复

来源：`JSONRPCClient` 错误规范化将服务器 message 原样写入 `debugSummary` 与日志。

修复：

- `UsageError.rpcFailed` / `.appServerStartupFailed` 的负载改为固定类别枚举 `RPCFailureReason`（`timedOut` / `noReply` / `transportClosed` / `malformedResponse` / `invalidPayload` / `serverError(code:)` / `writeFailed` / `shutdown` / `launchFailed` / `other`），payload 问题用 `PayloadProblem` 固定枚举表达。
- 上游 `JSONRPCError.message` 只在传输层用于判断「未登录」这一类别，随后丢弃；`UsageError.debugSummary` 与 `UsageFormatting.errorText` 只输出固定文案与数值码。
- `Diagnostics.log` 增加兜底过滤：凭据形状的长十六进制 / JWT 形 / `sk-` 形以及 `authorization`、`token`、`cookie`、`secret` 等键值对一律替换为 `[redacted]`。

回归测试（全部使用合成哨兵，无真实凭据）：`DiagnosticsRedactionTests.testCredentialShapedRunsAreRedacted`、`testKeyedPairsAreRedacted`、`testServerErrorMessageNeverEntersUsageError`、`testSignInShapedServerErrorsMapToNotSignedIn`、`testErrorTextForServerErrorsContainsNoUpstreamText`、`testLogWritesRedactedLinesOnly`。

### 评审附带发现 — 已处理

1. **CLI fail closed**：缓存往返（数值一致性校验）或子进程清理失败分别以退出码 6 / 7 结束，不再打印 PASS；`scripts/build.sh` 的 codesign 签名与验证失败改为非零退出，不再吞掉。
2. **未经证实的因果表述**：`JSONRPCClient` 中关于 barrier 的注释改为只陈述观察结果（并发队列 + `sync(flags: .barrier)` 未提供所需互斥，表现为回复无法路由到等待中的请求）与已验证的修复（NSLock），不再断言因果机制。
3. **source 权威化**：新增 `UsageDisplay`（core，可测），`isLive == false` 一律渲染为 `stale`，即使 error 为 nil；`isLive == true` 但 `source == .cached` 也按缓存处理。回归测试：`UsageDisplayTests` 六项。

## 2. 用评审探针复测（独立证据）

Codex 的 `artifacts/ReviewProbe.swift` 以临时 target 方式对本轮修复后的源码复测（仅两处机械适配：补 `import UsageMonitorCore`；`UsageError.rpcFailed(detail:)` 改为新的固定类别 API，foreign 用例因现在会被正确拒绝而用 `try?` 捕获以便打印全部场景）。结果对照：

| 探针输出 | Round 1（缺陷） | Round 2（修复后） |
| --- | --- | --- |
| `ReviewProbe overflow`（`windowDurationMins = 1e100`） | `exit: -5`，Swift fatal error | `exit: 0`，无崩溃 |
| `bool accepted remaining` | `Optional(99.0)` | `nil` |
| `fractional duration kind`（300.9） | `Optional(fiveHour)` | `nil` |
| `foreign bucket accepted` | `true` | `false` |
| `three failed automatic fetches create clients` | `6` | `2` |
| `client running after stop raced with start` | `true` | `false` |

探针为 QA 工具，属 Codex 所有，未保留在本仓库构建目标中（临时 target 已移除，`Package.swift` 还原）。

## 3. 构建与测试结果

| 命令 | 结果 |
| --- | --- |
| `swift build --package-path .` | Build complete，0 warning，0 error |
| `swift test --package-path .` | `Executed 86 tests, with 0 failures (0 unexpected)` |
| `xcodebuild -scheme UsageMonitor-Package -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| `xcodebuild -scheme UsageMonitor-Package -destination 'platform=macOS' test` | `** TEST SUCCEEDED **`，`Executed 86 tests, with 0 failures` |
| `./scripts/build.sh` | 生成 `dist/UsageMonitor.app`，`codesign --verify` 与 `plutil -lint` 通过，脚本退出码 0 |

测试规模从 54 增至 86（新增 32 项回归测试：数值边界 5、bucket 身份 8、失败预算 5、停止竞态 6、错误净化 7、显示状态 6，其余为既有用例适配新 API）。

## 4. 真实数据与生命周期验证（非 mock）

### 4.1 一次性冒烟（生产服务，release bundle）

```
$ dist/UsageMonitor.app/Contents/MacOS/UsageMonitorCLI --timeout 12
codex executable: /Applications/ChatGPT.app/Contents/Resources/codex
child lifecycle: started `codex app-server` (pid 64184)
handshake: initialize + initialized ok
--- normalized usage ---
5H: remaining 84% (used 16%), window 300 mins, resets 2026-09-09 19:33:56 +08:00
W: remaining 79% (used 21%), window 10080 mins, resets 2026-09-15 14:29:26 +08:00
source: codex app-server (live)
fetchedAt: 2026-09-09 15:13:33 +08:00
cache: round trip ok (stored as normalized numbers only, tagged cached)
rpc duration: 1.13s
result: PASS
child lifecycle: terminated (status 15)
child lifecycle: stop() issued (close stdin, SIGTERM, SIGKILL if needed, reap)
child cleanup: verified (pid 64184 no longer exists, reaped)
SMOKE EXIT: 0
```

### 4.2 应用运行时与退出竞态

```
$ USAGE_MONITOR_LOG_FILE=/tmp/um5.log dist/UsageMonitor.app/Contents/MacOS/UsageMonitor
07:16:05 applicationDidFinishLaunching
07:16:05 viewmodel start
07:16:05 starting app-server child
07:16:05 app-server child started pid 64810
07:16:06 fetch ok windows=5h:true/weekly:true
07:16:06 display live

$ kill -TERM <app pid>          # 在子进程存活期间发送
07:16:16 service stopped (generation 1)
07:16:16 viewmodel stopped
$ ps -axo pid,ppid,command | grep "codex app-server" | grep -v -- "--listen"
（无输出：UsageMonitor 启动的子进程已回收，无孤儿进程）
```

## 5. 修改文件

```
Sources/UsageMonitorCore/Utilities/SafeConversion.swift      新增：安全数值转换
Sources/UsageMonitorCore/Utilities/UsageDisplay.swift        新增：以 source 为权威的显示状态
Sources/UsageMonitorCore/Models/UsageError.swift             重写：固定类别 RPCFailureReason / PayloadProblem
Sources/UsageMonitorCore/Services/UsageParser.swift          数值校验 + bucket 身份
Sources/UsageMonitorCore/Services/UsageService.swift         失败预算 + 无竞态生命周期
Sources/UsageMonitorCore/Services/JSONRPCClient.swift        固定类别错误、安全错误码、注释表述修正
Sources/UsageMonitorCore/Services/CodexAppServerClient.swift 错误映射、childProcessIdentifier
Sources/UsageMonitorCore/Services/CodexLocator.swift         无行为变化（错误类型适配）
Sources/UsageMonitorCore/Utilities/Diagnostics.swift         凭据形状过滤
Sources/UsageMonitorCore/Utilities/UsageFormatting.swift     固定错误文案
Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift      任务取消/停止后不发布/手动刷新重置预算
Sources/UsageMonitorApp/UsageMonitorApp.swift                无行为变化
Sources/UsageMonitorApp/Views/*.swift                        适配 UsageDisplay
Sources/UsageMonitorCLI/UsageMonitorCLI.swift                fail closed 退出码、缓存与清理校验
Tests/UsageMonitorCoreTests/*.swift                          新增 32 项回归测试并适配新 API
scripts/build.sh                                             codesign/验证失败改为非零退出
README.md                                                    行为、退出码、安全说明更新
```

未改动：PROJECT_SPEC.md、IMPLEMENTATION_PLAN.md、REVIEW.md（Codex 所有）、验收标准。

## 6. 遗留限制

1. **官方 Usage UI 对照仍未完成**（spec §17「正确性」、§28）：需要用户截图或用户主导的已登录浏览器核对 5H、Weekly 与重置时间。本轮两处真实数据（4.1）来自同一后端接口，按评审要求不能据此宣称通过。此项仍是显式 blocker。
2. **可见 UI 人工核查仍未完成**：菜单栏条目、面板与「立即刷新」按钮的实机验证仍需 Codex 或用户确认（上一轮 CUA 两次 -10005 超时）。
3. 失败段打开期间自动刷新不再启动子进程，最迟 10 分钟冷却后自动重试；期间菜单栏显示缓存数据加 ⚠。这是对「停止反复启动」与「上游恢复后自动恢复」之间的取舍，已写入 README。
4. 传输层集成测试依赖系统 python3 作为固定字面量子进程；若未来测试环境缺少 `/usr/bin/python3`，相关 11 项用例会失败（属环境依赖，非产品缺陷）。
5. `.build/` 位于 iCloud Drive 路径下，偶发增量构建产物未更新；可疑结果请先 `swift package clean`。

## 7. 结论

Round 2 的 5 个 code blocker 与 3 项附带发现均已修复并配齐回归测试；Codex 探针的全部缺陷场景复测通过；构建、86 项测试、真实冒烟与 owned-child 清理验证均通过。官方 UI 对照与可见 UI 实机核查仍未验证，项目整体完成判定权在 Codex，本轮不宣布 COMPLETE。

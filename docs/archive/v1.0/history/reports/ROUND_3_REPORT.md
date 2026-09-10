# ROUND 3 REPORT — UsageMonitor 修订

日期：2026-09-09  
实施者：Claude Code（GLM-5.3-Flash）  
依据：REVIEW.md「REVIEW ROUND 2 (2026-09-09 15:25 +08:00)」、PROJECT_SPEC.md、IMPLEMENTATION_PLAN.md、artifacts/codex-review-2-probes.log  
状态：Round 3 修订完成，等待 Codex Review。官方 UI 对照仍未验证。不宣布整体 COMPLETE。

---

## 1. Blocker 1：统一的有界恢复状态机，移除冷却自动重置 — 已修复

来源：`artifacts/codex-review-2-probes.log` → `three launch failures attempts: 3 breaker: false`；`UsageService.swift:176` 在处理重启预算的 do/catch 之外调用 `acquireClient`，导致 `start()` 抛错时不进入熔断。

修复（`Sources/UsageMonitorCore/Services/UsageService.swift`）：

- `performFetch` 重构为单一循环：工厂/启动、握手、读取三类失败全部进入同一个恢复判定 `mayRetryAfter(_:)`，共用同一个失败段预算（1 次启动尝试 + 1 次自动重启）。
- 不可重启错误（未找到 CLI、未登录）按评审要求单独分类：不消耗重启次数，但同样打开失败段，使后续定时刷新不再重复同类失败。
- 移除 600 秒冷却自动重置：失败段只由「成功」或显式 `fetch(resetFailureBudget: true)`（UI「立即刷新」）关闭；注入时钟推进任意时长都不会重开预算。`clock` 注入保留用于失败段时间戳与回归测试。
- `stop()` 后的 `fetch()` 仍立即抛 `.rpcFailed(.shutdown)`；`resume()` 显式恢复。

回归测试（`Tests/UsageMonitorCoreTests/UsageServiceTests.swift`）：

| 测试 | 断言 |
| --- | --- |
| `testStartThrowIsBoundedAcrossScheduledFetches` | 3 次调度刷新后 `start()` 调用 2 次、熔断打开（探针曾测得 3 次、breaker false） |
| `testFactoryThrowIsBoundedAcrossScheduledFetches` | 工厂抛错 3 次刷新只调用工厂 1 次 |
| `testRestartableStartFailureThenManualRetryIsBoundedAgain` | 手动重试后再加 2 次调度刷新，启动次数不再增加 |
| `testClockAdvancementNeverReopensTheBudgetAutomatically` | 注入时钟推进 5 × 600 秒，启动次数保持 2 |
| `testSuccessIsOnlyReachableThroughManualRetryAfterExhaustion` | 上游恢复后自动刷新仍只回缓存/已记录错误；仅手动重试拿到 live 数据并关闭失败段 |
| `testNonRestartableErrorsNeverConsumeTheBudget` | 未登录错误打开失败段且不启动重启（按新语义更新） |

## 2. Blocker 2：关闭等待在途工作与子进程清理完成 — 已修复

来源：`fetch finished when stop returned: false`；`JSONRPCClient.start()` 在 `Process.run()` 之后才发布 `self.process`，关闭在那个窗口会拿到 nil 而漏掉子进程；仅取消 Task 无法中断同步 fetch。

### 2.1 传输层

- `JSONRPCClient` 新增 `launchLock`，`start()` 与 `stop()` 串行化：`stop()` 会等待正在进行的 `start()` 结束，然后终止并回收子进程。
- 子进程在 `Process.run()` 之前就登记到 `self.process`，因此关闭总能触及该子进程；`run()` 抛错时回滚登记。`isRunning` 在启动前本来就返回 false，行为不变。

### 2.2 服务层（有界排空）

- `UsageService.stop(shutdownTimeout:)`：先停已知与启动中的子进程，然后有界等待在途 fetch 退出（默认上限 8 秒；每 50ms 轮询 + 信号量），再做一次迟到子进程清扫；之后才返回。若 fetch 运行在调用线程上则跳过等待以避免自死锁。
- fetch 在启动、握手、读取、重启前都检查 generation，停止后以 `.rpcFailed(.shutdown)` 结束且不重启、不覆盖缓存。

### 2.3 应用层（终止前静默）

- `UsageViewModel.stop(completion:)`：主线程只做标志位与定时器取消，join（取消 Task、`service.stop()`）放到专用串行 join queue，`completion` 从该队列回调。
  首次实现曾把 completion 跳回主队列，导致 `applicationShouldTerminate` 阻塞主线程等待一个永远不会执行的 main-queue 任务（10 秒超时才退出）。已修正为从 join 队列回调；实机验证空闲退出 0.3 秒。
- `AppDelegate.applicationShouldTerminate` 发起关闭并以信号量有界等待（上限 10 秒）后返回 `.terminateNow`；`applicationWillTerminate` 保留一次幂等的最终清扫。SIGTERM/SIGINT 处理改为只调用 `NSApp.terminate(nil)`，统一走同一条关闭路径。主线程等待的是后台 join，不请求主 actor，因此无主 actor 死锁。

回归测试（新增 `Tests/UsageMonitorCoreTests/ShutdownDrainTests.swift`，使用固定字面量 python3 子进程，无凭据）：

| 测试 | 断言 |
| --- | --- |
| `testStopReturnsOnlyAfterInFlightFetchCompletes` | `stop()` 返回时 fetch 已结束（探针测得相反结果） |
| `testParentExitRightAfterShutdownLeavesNoChildSurvivor` | 真实子进程在读取进行中被关闭：`stop()` 返回后 `kill(pid,0)` 立即 ESRCH，等价于父进程此刻退出无幸存者 |
| `testStopDuringLaunchStillTerminatesTheChild` | 启动与关闭竞态：`stop()` 不会阻塞在启动上，且子进程被回收 |
| `testServiceStopDuringChildLaunchLeavesNoSurvivor` | 服务级同场景同样无幸存者 |

## 3. 非阻塞项 — 已处理

- `UsageParser.swift:87` 的 `Any? -> Any` 可选隐式转换已显式消除：`windows(in value: Any?)`，入口处 `guard let value`。直接以 `swiftc -typecheck` 编译 core 无 warning。
- 误导性注释已修正：`UsageViewModel` 的 stop 文档改为描述实际的 join 语义（后台 join queue + 有界排空），并说明为何不能在主 actor 上等待；`UsageService.stop` 文档与实际行为一致。

## 4. 构建与测试结果

| 命令 | 结果 |
| --- | --- |
| `swift build --package-path .` | Build complete，0 warning，0 error |
| `swift test --package-path .` | `Executed 95 tests, with 0 failures (0 unexpected)` |
| `xcodebuild -scheme UsageMonitor-Package -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| `xcodebuild -scheme UsageMonitor-Package -destination 'platform=macOS' test` | `** TEST SUCCEEDED **`，`Executed 95 tests, with 0 failures` |
| `./scripts/build.sh` | `dist/UsageMonitor.app` 构建并签名验证通过，退出码 0 |

测试规模 86 → 95（新增 9 项：启动/工厂失败预算 4、时钟推进 1、成功关闭路径 1、真实进程关闭排空 4，另有若干既有用例按新语义调整；`failureEpisodeCooldown` 参数随冷却机制移除）。

## 5. 真实数据与关闭验证（非 mock）

### 5.1 一次性冒烟（生产服务，release bundle）

```
$ dist/UsageMonitor.app/Contents/MacOS/UsageMonitorCLI --timeout 12
codex executable: /Applications/ChatGPT.app/Contents/Resources/codex
child lifecycle: started `codex app-server` (pid 69834)
handshake: initialize + initialized ok
--- normalized usage ---
5H: remaining 71% (used 29%), window 300 mins, resets 2026-09-09 19:33:56 +08:00
W: remaining 77% (used 23%), window 10080 mins, resets 2026-09-15 14:29:26 +08:00
source: codex app-server (live)
fetchedAt: 2026-09-09 15:39:52 +08:00
cache: round trip ok (stored as normalized numbers only, tagged cached)
rpc duration: 1.27s
result: PASS
child lifecycle: terminated (status 15)
child lifecycle: stop() issued (close stdin, SIGTERM, SIGKILL if needed, reap)
child cleanup: verified (pid 69834 no longer exists, reaped)
SMOKE EXIT: 0
```

### 5.2 应用空闲关闭

```
app=70124 child=70131
kill -TERM 70124
exit took 0.3s
app exited
child reaped (pid 70131)
log: termination requested → service stopped (generation 1, drained=no) → viewmodel stopped
```

### 5.3 应用在途关闭（首次 fetch 进行中发送 SIGTERM）

```
app=70199 child=70201
kill -TERM 70199   # fetch 仍在进行
exit took 0.3s
app exited
child reaped (pid 70201)
log: termination requested
     fetch failed: rpcFailed(shutdown)
     service stopped (generation 1, drained=yes)
     viewmodel stopped
     service stopped (generation 2, drained=no)   # 幂等的最终清扫
--- any orphan from us? --- (无输出)
```

两次实机关闭均在 0.3 秒内退出且子进程已回收；修复前的实现因主队列回调死锁要等 10 秒超时。

## 6. 修改文件

```
Sources/UsageMonitorCore/Services/UsageService.swift        统一恢复状态机；移除冷却自动重置；有界排空 stop
Sources/UsageMonitorCore/Services/JSONRPCClient.swift       launchLock 串行化启动/关闭；Process 提前登记
Sources/UsageMonitorCore/Services/UsageParser.swift         消除 Any? -> Any 隐式转换
Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift     join queue + completion 语义；注释修正
Sources/UsageMonitorApp/UsageMonitorApp.swift               applicationShouldTerminate 有界等待；SIGTERM 统一路径
Tests/UsageMonitorCoreTests/UsageServiceTests.swift         预算/时钟推进回归测试（更新）
Tests/UsageMonitorCoreTests/ShutdownDrainTests.swift        新增：真实进程关闭排空回归
README.md                                                   失败预算与关闭语义说明更新
```

未改动：PROJECT_SPEC.md、IMPLEMENTATION_PLAN.md、REVIEW.md（Codex 所有）、验收标准、Round 1/2 已验证的解析与错误处理行为。

## 7. 遗留限制

1. **官方 Usage UI 对照仍未完成**（spec §17「正确性」、§28）：需要用户截图或经许可的已登录 UI 访问。两次后端调用不能替代 UI 对照，本报告不声称该项通过。
2. **可见 UI / 手动刷新的实机验收仍未完成**：菜单栏条目、面板与「立即刷新」按钮仍需 Codex 或用户确认（此前 CUA 两次 -10005 超时）。
3. 失败段打开期间自动刷新不再启动子进程，也不再随时间自动恢复；恢复路径是用户点击「立即刷新」，或一次成功关闭失败段。这是评审明确要求的有界行为，代价是持续故障期间菜单栏会一直显示缓存数据加 ⚠。
4. 关闭排空依赖子进程对 stdin EOF / SIGTERM 的响应；`JSONRPCClient.stop` 内部以 SIGKILL 与 `waitUntilExit` 兜底，`applicationShouldTerminate` 另有 10 秒上限，超时后仍会退出并记录诊断（此时理论上可能留下子进程，日志会写明 `termination proceeded after shutdown timeout`）。
5. 传输层集成测试依赖系统 python3 作为固定字面量子进程；环境缺少 `/usr/bin/python3` 时相关用例会跳过或失败（环境依赖，非产品缺陷）。
6. `.build/` 位于 iCloud Drive 路径下，偶发增量构建产物未更新；可疑结果请先 `swift package clean`。

## 8. 结论

Round 3 的两个 code blocker（启动/工厂失败纳入有界预算并移除冷却自动重置；关闭等待在途工作与子进程清理完成）与非阻塞项（可选隐式转换、误导性注释）均已修复并配齐回归测试，包括真实子进程的关闭排空验证。构建、95 项测试、真实冒烟、空闲与在途两种关闭场景均通过。官方 UI 对照与可见 UI 实机核查仍未验证，整体完成判定权在 Codex，本轮不宣布 COMPLETE。

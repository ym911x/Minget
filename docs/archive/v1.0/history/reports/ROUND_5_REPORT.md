# Round 5 report — v1.1 revision (executed)

Status: implementation complete. This round **actually ran** the full test suite, the
release build and a launch/exit cleanup check; every number below comes from a real
command in this round's environment. Nothing was committed or pushed. The 192 tests from
Round 4 are all preserved (212 total now, no old test deleted).

## 0. Round 5 任务清单与本轮处置

| # | 任务 | 处置 |
|---|---|---|
| 1 | `StatusItemController` 不得用 `NSStatusItem()` 直接创建；改为系统状态栏注册 + 退出清理 | 已修复并接线（§1.1） |
| 2 | 保存 GLM API Key 后立即只读探测并发布脱敏 observation；合同未确认不交 `read()` | 已修复并接线（§1.2） |
| 3 | 保存 GLM 控制台会话后立即 Cookie 探测；401/403、过期会话、HTTP 200 业务错误准确分类；认证失败暂停自动重试 | 已修复并接线（§1.3） |
| 4 | `RedirectGuardDelegate.refusedRedirect` 跨请求污染 | 已重写为按 task 隔离（§1.4） |
| 5 | 应用接线测试（状态项注册/清理、保存即探测、重定向不污染） | 新增 `UsageMonitorAppTests` 目标，15 条接线测试（§2） |
| 6 | 完整复核边界要求 | 已复核（§4） |
| 7 | 真实 `swift test`、`./scripts/build.sh`、启动/退出/子进程检查 | 全部执行通过（§3、§5） |
| 8 | 本轮报告 | 即本文件 |

## 1. 修复详情

### 1.1 状态项注册与退出清理（`StatusItemController.swift`、`UsageMonitorApp.swift`）

- `statusItem` 从 `let statusItem = NSStatusItem()` 改为 `private(set) var statusItem: NSStatusItem?`，
  在 `install(model:)` 中通过 `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`
  注册到系统菜单栏，随后仍设置稳定 `autosaveName`（`UsageMonitor.StatusItem.v1`）、
  accessibility 标签、点击动作，并应用实测宽度。全源码扫描确认不再有任何 `NSStatusItem()` 直接构造。
- 新增 `uninstall()`：停止 `MenuBarSpaceMonitor`（timer + 通知观察者）、移除 Combine 订阅、
  关闭 popover、收起并释放详情窗口、移除按钮内容、`NSStatusBar.system.removeStatusItem(item)`。
  幂等，可重复调用；卸载后可重新安装。
- `AppDelegate.applicationWillTerminate` 从只 `closePanel()` 改为调用 `uninstall()`，
  SIGTERM 路径经 `NSApp.terminate` 同样走到这里。
- 几何检测、full/compact/icon 状态机、`objectWillChange` 立即重测宽度的逻辑保持不变。

### 1.2 保存 GLM API Key 后立即探测（`GLMProvider.swift`、`ProviderReadings.swift`、`ProviderRefreshEngine.swift`、`UsageViewModel.swift`）

- 新增 `GLMProvider.probeAccountReportObservation()`：不抛错的探测路径。401/403 保留真实
  HTTP 状态并分类为 `invalidCredential`；其他非 2xx → `serverError(status:)`；HTTP 200
  按业务码/字段解析；两种 Authorization 拼写都尝试，解析干净的结果优先。
  `probeAccountReport()`（抛错版）改为同一 observation 的薄包装，两者分类永远一致。
- 新增 `GLMAccountReportParser.observe(response:)`：只有 2xx 才解析 body，认证拒绝保留真实状态码。
- `GLMReading.storeAPIKey(_:)` 统一管理 key 写入（仍只进 Keychain），并记录"最近保存的凭证"。
- 引擎新增 `connectAfterCredentialChange(platform:)`：合同未确认时执行只读探测（经新协议
  `ProviderProbeReading.probeForConnection()`），探测结果按固定失败类别记录（认证失败置
  `authSuspended`）；合同确认后才是普通强制 `read()`。`UsageViewModel.saveGLMAPIKey` 改走该流程。
- 观测发布：`GLMReading.lastObservation` + `onObservation` 不变，面板"探测: HTTP n · 业务码 n ·
  字段 …"照旧显示脱敏字段名；合同未确认时 `isDisplayable` 恒为 false，面板无任何金额。

### 1.3 保存控制台会话后立即探测与错误分类（同上文件）

- `UsageViewModel.saveGLMConsoleSession` 保存后立即走 `connectAfterCredentialChange`，
  用户无需再点"探测一次"。
- 探测凭证选择按"最近保存"：同时存有 API Key 时，保存会话后探测用会话（Cookie 头，
  无 Authorization 头），保存 Key 后探测用 Key。`GLMReading.disconnect()` 清除该偏好。
- 分类规则：会话被 401/403 拒绝 → `invalidCredential`（带真实状态码）；其他非 2xx →
  `serverError(status:)`；HTTP 200 业务码 → `businessError(code:)`；硬过期会话不重放——
  不发任何请求，observation 记 HTTP 0 + `invalidCredential`。
- 认证失败 → 引擎 `authSuspended`，自动重试暂停；重新保存凭证（重连）清除暂停。
  `探测一次`（`probeGLM`）改为经 `recordProbeOutcome` 记录结果，面板状态与观测一致。

### 1.4 重定向拒绝的跨请求隔离（`ProviderRequestGuard.swift`）

- 根因：`RedirectGuardDelegate` 用单个共享 `refused: Bool` 记录拒绝，一个传输服务所有请求，
  一次跨域重定向会让之后任何无关网络错误被误报为 `crossDomainRedirectBlocked`。
- 修复：拒绝状态按 `URLSessionTask.taskIdentifier` 隔离（`refusedTaskIDs: Set<Int>`），
  `refusedRedirect(for:)` 只回答该 task 自己的问题。传输层从 `session.data(for:)` 改为
  委托驱动的异步桥接（`waitForCompletion(of:)` 注册 per-task continuation），错误分类直接
  取自该请求自己的状态，不再查询传输级标志。
- 顺带修复一个旧隐患：拒绝重定向不再用 `task.cancel()` 逼入错误分支，`completionHandler(nil)`
  后由 `didCompleteWithError` 直接给出 `crossDomainRedirectBlocked`，拒绝路径永远不会把 3xx
  当成正常响应返回；原始请求无法钉定 origin 时同样拒绝。
- `URLSessionProviderTransport` 新增测试用 `protocolClasses` 注入（生产路径不变）。

## 2. 测试（212 条，实际执行）

Round 4 的 192 条全部保留；本轮新增 20 条：

| 测试 | 覆盖 |
|---|---|
| `ProviderRequestGuardTests` 新增 5 条 | 委托级拒绝按 task 隔离；URLProtocol 端到端拒绝跨域重定向（被拒请求永不发出）；纯 200 响应路径；同源重定向跟随；**同一传输上先拒绝后网络失败，分类不串** |
| `UsageMonitorAppTests.StatusItemWiringTests` 6 条（新目标） | 系统状态栏注册（autosaveName、动作接线、监视器启动）、卸载（item 移除、监视器停止、popover 关闭、无渲染）、卸载幂等、卸载后重装、实测宽度非 0 且 accessibility 标签正确、应用边界上的传输分类隔离 |
| `UsageMonitorAppTests.GLMConnectWiringTests` 9 条（新目标） | 保存 Key 立即探测并发布 observation（官方主机 + Bearer 头）；401 带真实状态且 authSuspended；HTTP 200 业务码分类；保存会话立即用 Cookie 探测（无 Authorization 头）；Key+会话并存时探测最近保存者；会话 403 → authSuspended；硬过期会话零请求不重放；重连清除暂停；断开清除凭证与数字 |

接线测试直接驱动真实 `UsageViewModel`、`ProviderRefreshEngine`、`StatusItemController`
（AppKit 在 XCTest 宿主内运行），Codex 服务用不可启动的 factory，凭证用内存 store，
网络用进程内 URLProtocol stub——不触碰真实钥匙串、不联网、不产生子进程。

```
命令：swift test
结果：Executed 212 tests, with 0 failures (0 unexpected) in 6.494s
     Test Suite 'All tests' passed
退出码：0；编译 0 error / 0 warning（release 重建亦 0 warning）
```

### 本轮测试过程中发现并修复的真实问题

1. **URLProtocol 桩的 302 不会触发会话重定向**（实测发现）：自定义 URLProtocol 必须显式
   `urlProtocol(_:wasRedirectedTo:redirectResponse:)` 上报重定向，会话才会调用委托的
   `willPerformHTTPRedirection`；仅返回 302 响应会被当作最终响应。桩已按此实现，
   并在两个测试目标中各留注释记录该平台行为。
2. **taskIdentifier 只在会话内唯一**：首轮隔离测试用第二个 URLSession 制造"另一个请求"，
   结果两个会话各自从 1 开始编号，恰好复现了串号。这反向确认了实现必须（也确实）以
   "同一会话内 identifier 唯一"为前提；测试已改为单会话双请求的真实形态。
3. release 编译暴露 2 个既存警告（冗余 `await`、`stop()` 闭包内死写 `self = nil`），已修复。

## 3. 构建结果（实际执行）

```
命令：./scripts/build.sh
结果：swift build (release) complete，0 warning；staging dist/UsageMonitor.app；
     codesign --force --sign - 成功；codesign --verify 通过（satisfies its Designated
     Requirement）；plutil -lint Info.plist OK
退出码：0
产物：dist/UsageMonitor.app（Contents/MacOS/UsageMonitor + UsageMonitorCLI，2026-09-10 00:58 重建）
```

## 4. v1.1 边界复核（源代码检查，未读取任何真实凭证）

- **菜单栏**：注册/清理/autosaveName/状态机见 §1.1；几何事实仍只来自公开 API。
- **Codex 账号**：`account/read` + `refreshToken: false` 与账号归属缓存未改动，原测试全过。
- **DeepSeek**：`/user/balance` 白名单、Bearer、Decimal 解析、币种分行未改动。
- **GLM**：探测仍只打 `open.bigmodel.cn` + `accountReportPath`（测试断言 hosts 集合）；
  `GLMContract.confirmed` 仍为空，`isDisplayable` 门槛未动，未确认时不轮询、不显示任何金额。
- **Keychain**：凭证只经 `ProviderCredentialStoring` 进 Keychain；本轮新增
  `storeAPIKey` 未改变存储介质；缓存（UserDefaults）只含 accountID + 金额 + 时间戳。
- **刷新与缓存隔离**：并发去重、失败保留旧值、401 暂停 + 重连恢复、断开清凭证清缓存
  原样保留；GLM 探测不写业务缓存。
- **跨域重定向**：拒绝按 task 隔离（§1.4），拒绝的请求永不把 3xx 当成功返回。
- **禁止模型端点**：模型片段黑名单未动；全源码扫描模型端点片段仅出现在守卫定义文件；
  传输级测试断言任何 provider 流量不触模型路径。
- **无凭证外泄**：无硬编码 Key/邮箱；`auth.json`、`HTTPCookieStorage.shared`、
  `WKWebsiteDataStore.default` 全源码零命中；控制台 webview 仍用应用自建 `nonPersistent()` store。

## 5. 启动与退出清理检查（实际执行）

```
命令（要点）：
  dist/UsageMonitor.app/Contents/MacOS/UsageMonitor &
  ps 确认 app PID 与其子进程（恰好一个 codex app-server，ppid == app PID）
  kill -TERM <app>
结果：
  - 应用启动正常，仅创建一个自有 codex 子进程（/Applications/ChatGPT.app/.../codex）；
  - SIGTERM 后约 500ms 内退出，进程消失；
  - 子进程被回收，无孤儿；系统中其他 codex 进程未受影响、未被触碰。
```

## 6. 已知问题

1. `GLMContract.confirmed` 为空，GLM 余额在设计上不可能显示；本轮改动让探测证据更完整
   （真实 HTTP 状态保留到 observation），contract 仍需真实凭证 + 人工评审才能打开。
2. 状态项真实渲染、刘海遮挡等只能在实机确认；本轮新增的 AppKit 接线测试在 XCTest 宿主
   内验证了注册/清理与标签接线，但不验证 macOS 菜单栏的实际布局行为。
3. `UsageMonitor 2.app` 是 iCloud 同步产生的旧副本，与本轮无关，未触碰。

## 7. 待用户实机核对项

Round 4 报告 §7 的清单全部沿用（Codex 邮箱、账号隔离、DeepSeek 线上余额、GLM 双凭证
探测、刘海机型、菜单栏抖动、手动刷新与详情窗口、官方 UI 对照），本轮新增两点：

1. **保存即探测**：录入 GLM API Key 后，面板应立即出现"探测: HTTP …"行（无需点击
   "探测一次"）；保存控制台会话后同样立即出现。若凭证被拒（401/403），状态为
   "需要重新连接"；重新录入有效凭证后自动恢复。
2. **退出清理**：菜单栏图标在退出后立即消失；再次启动恢复正常位置（autosaveName 生效）。

## 8. 本轮实际执行的命令

```bash
swift build                     # PASS（多次迭代，最终 0 error / 0 warning）
swift build --build-tests       # PASS（测试目标编译 0 error / 0 warning）
swift test                      # PASS：212 tests, 0 failures, exit 0
./scripts/build.sh              # PASS：dist/UsageMonitor.app 重建、签名校验通过、0 warning
dist/UsageMonitor.app/Contents/MacOS/UsageMonitor   # 启动检查：SIGTERM 后退出，子进程无孤儿
```

未执行、也不应在本环境执行：`git commit` / `git push`（按指示不提交不推送）；未读取
任何真实 Key、全局认证配置或现有浏览器 Cookie。

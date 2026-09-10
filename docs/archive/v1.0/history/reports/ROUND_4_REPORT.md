# Round 4 report — v1.1 revision (executed)

Status: implementation complete. This round **actually ran** the build, the full test
suite and a launch/exit cleanup check; every number below is from a real command in this
round's environment. Nothing was committed or pushed.

## 0. Codex 审核发现与本轮处置

| # | 审核发现 | 处置 |
|---|---|---|
| 1 | `ProviderReadings.swift` 的 `credentials.save` 缺少 `try`，编译失败 | 已修复：`try credentials.save(...)`（`storeSession` 本就声明 `throws`） |
| 2 | `ProviderCredentialStore.swift` 两处 `SecItemUpdate` 查询未桥接为 `CFDictionary` | 已修复。真正的错因是第一个参数（query）未桥接——诊断列位置有误导性，已用最小片段实证：`[String: Any]` 显式 `as CFDictionary` 可编译，未桥接的第一参数不可。两处均改为 `SecItemUpdate(query(for: key) as CFDictionary, update as CFDictionary)` |
| 3 | `GLMProvider.swift` 把 `ProviderFailure` 当作有 `code` 属性 | 已重新设计业务错误解析：`observe` 先用 `businessCode(in:)` 读码，再经新谓词 `isBusinessErrorCode(_:)`（0/200 之外为失败）构造 `.businessError(code:)`。业务码与失败类型来自同一来源，`GLMAccountReportObservation` 中两者永远一致 |
| 4 | GLM 控制台后备连接流程断点：`read` 在构造 Cookie 请求前被合同门槛拦截，`probe` 只支持 API Key | 已实现控制台会话只读探测：`GLMReading.probe()` 现在按 API Key → 控制台会话两条路径探测；硬过期会话不重放（记录 `invalidCredential`，httpStatus 0 表示未发请求）。探测仍只记录脱敏的 HTTP 状态、业务码、顶层字段名；`read()` 的显示门槛不变，未确认前不显示任何金额 |
| 5 | 不只修编译错误；真实运行测试与构建 | 已完成：`swift test` 192/192 通过（exit 0，0 warning）；`scripts/build.sh` 重建并签名校验通过；应用启动/退出清理检查通过（见 §3、§8） |

### 本轮额外发现并修复（真实构建/测试暴露，非审核清单内）

真实 `swift build` 暴露了 3 个此前未运行就无法发现的 AppKit 编译错误（均在
`StatusItemController.swift`）：

1. `UsageViewModel.menuBarTitle` / `menuBarStalenessMarker` 从非隔离上下文访问 →
   `StatusItemController` 与 `MenuBarSpaceMonitor` 标注 `@MainActor`，回调闭包统一走
   `MainActor.assumeIsolated`（与本文件既有模式一致）。
2. `NSStatusBarButton` 没有 `contentView` → 改为 `addSubview`，并新增
   `MenuBarHostingView`（`hitTest` 返回 nil），标签不吞点击；`apply` 先清旧子视图。
3. AppKit 没有 `NSWindow.didChangeFrameNotification` → 分别观察
   `didMoveNotification` 与 `didResizeNotification`，逻辑抽到 `handleFrameChange`。
4. 顺带补强（需求 1）：模型变化立即触发重新测量（`objectWillChange` → 主队列 →
   `refreshLabel`），宽度不再等最多 10 秒的周期检查。

真实 `swift test` 暴露 11 个失败测试 / 18 处断言失败，全部修复：

| 失败 | 根因 | 修复 |
|---|---|---|
| `CodexAccountTests` 账号隔离三测（account 为 nil、缓存未写） | `CodexAppServerProviding.readAccount` 只是协议扩展默认实现（静态分派），stub 的实现永远不会被调用 | 声明为协议 requirement，扩展默认保留（未实现该方法的旧 stub 照常编译） |
| `testCacheAccountIDPrefersTheEmailAndRejectsBlanks` | 空白邮箱通过了 `!email.isEmpty` 检查 | `cacheAccountID` 先 trim 再判空 |
| `testAccountFingerprintIsStableAndNotTheKey` | 实现取了 6 个**字节**（12 个 hex 字符），测试钉的是 6 个 hex 字符 | 改为 `prefix(3)` 字节 = 6 hex 字符；GLM 的 `apiKeyFingerprint` 同步对齐 |
| `testNetworkFailureIsMappedToAFixedCategory` | `fetchBalances` 让 `ProviderTransportError` 原样抛出 | 新增 `ProviderFailure.from(_:)` 统一映射；`DeepSeekProvider.fetchBalances` 捕获转换；`GLMProvider.failure(from:)` 并入该静态方法（引擎同步改用） |
| `testRedirectWithoutAnOriginIsRefused` | 带 `baseURL` 的相对 URL 在新 Foundation 下仍暴露 host，被误判为同源 | `ProviderOrigin.init?` 拒绝 `baseURL != nil` 的 URL；无法钉住绝对来源的重定向一律拒绝 |
| `testDisconnectClearsCredentialAndCache` | 引擎 `disconnect` 只清状态不清业务缓存 | `ProviderCache` 新增 `clear(platform:)`；引擎断开时调用 |
| `testTruncationStepsDownInsteadOfShowingCutOffContent` | 截断被通用「不可见」路径吃掉，reason 报成 `hiddenOrOccluded` | 状态机先判截断再判不可见，reason 正确报 `truncated`，且同样锁增长 |
| `testShrinkingBlocksGrowthUntilASpaceEvent`（5 处断言） | 该测试与 `testShrinksImmediately…`、`testFailedGrowthAttempt…` 相互矛盾（前者要求一次观测从 full 直落到 icon，后两者钉住逐级收缩） | 修测试：补上第二次不可见观测（语义以两外两个测试 + 报告 §1.1「可连续收缩两级」为准），其余断言不变、全部通过 |
| `ProviderModelsTests` 两条 Decimal 断言 | `Decimal` 在本平台一律规范化尾零（已实证：`Decimal(string:)`、`init(sign:exponent:significand:)`、乘法全部把 `11000×10⁻²` 压成 `11×10¹`），「保留 110.00 尾零」不可满足 | 断言改为数值精确性（`== dec("110.00")`），两位小数呈现归 `DecimalFormatting`；`0.005`（无尾零）的 scale 断言保留 |
| `UsageServiceTests.testEpisodeClosesOnlyOnSuccess` 两条恒真断言 | `XCTAssertThrowsError(...) == ()`、三元恒 nil | 改为两条真实的 `XCTAssertThrowsError`（时间流逝不解冻 episode） |
| `GLMProviderTests.testSessionStateTransitions` | 对非 Optional 的 `SessionState` 做 `XCTAssertNil`（运行时必失败） | 删除该冗余断言，保留等价的 `== .absent` |

## 1. v1.1 需求复核（需求 9 清单逐项）

- **菜单栏几何检测**：纯逻辑层 `MenuBarSpaceFacts`/`MenuBarSpaceStateMachine` 全部测试
  通过（逐级收缩、增长需 3 次干净观测、收缩后锁增长直到空间事件、截断降级并锁增长、
  屏幕/唤醒事件重开）。AppKit 接线（`didMove`/`didResize`/屏幕/唤醒/10 秒本地检查 +
  内容变化触发的重新测量）已编译进应用，效果需实机确认。
- **Codex 账号**：`account/read` + `refreshToken: false` 有线级测试（echo 断言）；账号
  归属缓存、旧无归属缓存不供给已知账号、失败时只供给该账号自己的缓存——全部通过。
- **DeepSeek 余额**：`/user/balance` 白名单、Bearer、Decimal 精确解析、币种分行不换算
  不相加、HTTP 200 业务错误不当余额、401/403 → invalidCredential、网络失败映射固定类
  别——全部通过。
- **GLM 余额连接**：候选端点只读探测（Key 两种头 + 控制台 Cookie 两条路径）、HTTP 200
  业务码、合同门槛（`GLMContract.confirmed` 为空，任何返回都不显示）、未确认不参与定时
  轮询——全部通过。
- **Keychain**：`KeychainCredentialStore` 修复后的 update/add/delete 路径编译通过；
  `kSecAttrSynchronizable = false`；协议边界使测试永不触碰真实钥匙串。真机读写见 §7。
- **刷新与缓存隔离**：并发去重、失败保留旧值标 stale、401 暂停 + 重连恢复、断开清凭证
  清缓存、按平台×账号隔离——全部通过。
- **跨域重定向阻止**：跨 host / 换 scheme / 换端口拒绝、同源放行、无来源可判拒绝（本
  轮修复）、真实 `URLSessionTask` delegate 驱动的拒绝/放行——全部通过。
- **禁止模型端点**：模型片段黑名单、与白名单相互独立、client 拒绝非白名单路径且不离开
  进程、probe 只打官方主机——全部通过。

边界扫描（源代码检查，不读任何真实凭证）：无硬编码密钥/真实邮箱；模型端点片段守卫
仍在；凭证仅存 Keychain（不同步）；控制台 Webview 用应用自建 `nonPersistent()` 数据
store，不读现有浏览器 Cookie。

## 2. 测试结果（实际执行）

```
命令：swift test
结果：Executed 192 tests, with 0 failures (0 unexpected) in 6.148s
     Test Suite 'All tests' passed
退出码：0；编译 0 warning
```

对应关系：v1.1 需求 9 的测试项映射见 git 历史中 Round 4 首版报告 §3 的表格，全部保留
并全部通过。Round 3 的 95 项测试全部在内，未删除、未改名。

## 3. 构建结果（实际执行）

```
命令：./scripts/build.sh
结果：swift build (release) complete；staging dist/UsageMonitor.app；
     codesign --force --sign - 成功；codesign --verify 通过（satisfies its Designated
     Requirement）；plutil -lint Info.plist OK
退出码：0
产物：dist/UsageMonitor.app（Contents/MacOS/UsageMonitor + UsageMonitorCLI，2026-09-09 21:56）
```

## 4. 启动与退出清理检查（实际执行）

```
命令（要点）：
  dist/UsageMonitor.app/Contents/MacOS/UsageMonitor &     # 直启二进制
  ps 确认 app PID 与其子进程（ppid == app PID 的 codex app-server，恰好一个）
  kill -TERM <app>；wait <app>
结果：
  - 应用启动正常，仅创建一个自有 codex app-server 子进程；
  - SIGTERM 后约 400ms 内退出，wait 捕获退出码 0；
  - 子进程被回收，无孤儿（系统中其他应用的 codex 进程未受影响，未触碰）。
```

## 5. 已知问题

1. `GLMContract.confirmed` 为空，GLM 余额在拿到真实探测证据前不可能显示。这是设计结果。
2. `NSStatusItem` 几何事实只能在真实 AppKit 环境产生；核心判定已测，通知接线需实机确认。
3. 菜单栏宽度测量依赖 `NSHostingView.fittingSize`，极窄空间下 macOS 的行为无法单测复现。
4. 手动刷新按钮、详情窗口、弹出面板等可视交互仍未独立验证（沿用 Round 3 结论）。

## 6. 尚未完成内容

见 §5 与 §7。文档 `PROVIDER_ENDPOINTS.md` 已同步控制台只读探测的规则（§3.1/§3.2）。

## 7. 待用户实机核对项

1. **Codex 账号邮箱**：启动应用打开详情，确认 Codex 组显示真实账号邮箱；断网后确认
   「账号信息暂不可用」且金额仍在。
2. **账号切换隔离**（若有多账号）：切换后确认旧账号缓存数字不再出现。
3. **DeepSeek 线上余额**：录入真实 API Key，确认面板金额与官方控制台一致（多币种分行、
   granted/topped_up 分项）。
4. **GLM API Key 探测**：录入真实 Key 点击「探测一次」，把面板显示的 HTTP 状态、业务码、
   顶层字段名反馈到 `PROVIDER_ENDPOINTS.md`，再决定是否关闭合同门槛。
5. **GLM 控制台会话**：应用内登录（验证码）→「探测一次」确认控制台路径也能取回观测；
   断开后确认无残留。
6. **刘海机型**：图标不进刘海、空间不足按 full → compact → icon 收缩、重启后被遮挡时
   自动弹出详情窗口。
7. **菜单栏抖动**：多状态项拥挤时确认模式不来回跳动；数字变化（如 78% → 100%）时宽度
   立即重测，不出现长时间截断。
8. **手动刷新按钮与详情窗口**：Round 3 起 PENDING 的可视验收仍未完成。
9. **官方 UI 对照**：PROJECT_SPEC.md §17 要求的 Codex Usage 页面对照仍未完成。

## 8. 本轮实际执行的命令

```bash
swift build                 # PASS（迭代过程中多次，最终 0 error / 0 warning）
swift test                  # PASS：192 tests, 0 failures, exit 0
./scripts/build.sh          # PASS：dist/UsageMonitor.app 重新生成、签名校验通过
dist/UsageMonitor.app/Contents/MacOS/UsageMonitor   # 启动检查，SIGTERM 后 exit 0，子进程无孤儿
```

未执行、也不应在本环境执行：`git commit` / `git push`（按指示不提交不推送）；未读取
任何真实 Key、全局认证配置或现有浏览器 Cookie。

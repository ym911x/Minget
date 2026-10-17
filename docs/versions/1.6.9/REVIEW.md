# 1.6.9 审核

审核对象：分支 `codex/minget-1-6-9` 的工作区改动（`Sources/UsageMonitorApp/ViewModels/RefreshBatch.swift`、`UsageViewModel.swift`、`AntigravityModel.swift`、`ManagedAccounts.swift`、`MenuBarRefreshPolicy.swift`、`Views/UsagePanelView.swift`、`Views/MingetSettingsView.swift`、`Sources/UsageMonitorCore/Providers/ProviderRefreshEngine.swift`、`ProviderCache.swift`、`Services/UsageCache.swift`、三个测试文件、文档与版本号）。检查方式：源码差异逐项核对 + 规则与 `REQUIREMENTS.md` 逐条比对 + 完整 `swift test` + Release 严格签名构建与安装校验。审核时间 2026-10-17。

## 需求逐条核对

| 需求 | 实现 | 证据 |
| --- | --- | --- |
| 默认只刷菜单栏来源 | 三条旧定时器合并为一条 `menuBarRefreshTimer`，只维护 `menuBarRefreshTarget()` | `RefreshScopeTests.testLaunchReadsOnlyTheDisplayedProfile`、`testMenuBarLoopReadsOnlyTheDisplayedSource`、`testTheDisplayedDeepSeekBalanceIsExcludedFromEveryPageBatch` |
| 打开页面补刷一次 | `panelWillOpen(tab:)` / `panelDidSwitchTab(_:)` → `performPageBatch` | `testOpeningTheOverviewReadsEveryHiddenAccountOnce`、`testSwitchingToABrandPageReadsOnlyThatBrand` |
| 5 分钟整批门槛 | `RefreshBatchPolicy.needsRefresh`（全部成员新鲜才跳过）+ 取数台账 | 纯规则用例 6 项 + `testABatchPastTheAgeReadsAgain`、`testTheWholeBatchReadsTogetherWhenOneMemberIsStale` |
| 批次不含菜单栏账号 | `members` 先算候选再排除 `menuBarTarget` | 纯规则用例覆盖概览/品牌页 × Profile/Google/DS/API × 注册表/旧模式 |
| 失败仍计入门槛 | 取数任务在派发时记账 | `testFailedAttemptsStillCloseTheBatchGate` |
| 手动路径不受限 | `refreshNow` / `refreshBrand` / 点火确认路径未加任何门槛 | `testManualRefreshIgnoresTheBatchGate`、既有 `BrandRefreshTests` 全部通过 |
| 设置规则只作用于菜单栏 | `MenuBarRefreshPolicy` 逻辑未改，仅注释更新 | `RefreshCadenceTests.testMenuBarLoopFollowsSelectionAccelerationDisableAndStop`（30 → 300 → 30 → 120 → nil） |
| 状态页取消后台定时 | 移除 provider 定时器；概览/DeepSeek 页按 5 分钟自带门槛读取 | `UsageViewModel.performPageBatch` 与 `refreshDeepSeekStatus` 的既有门槛；无后台调用点 |

## 独立检查发现的问题

1. **主 actor 记账会拖慢取数（实现中已修复）**。第一版在取数任务里 `await` 主 actor 记录尝试时间；两个阻塞式等待的既有测试（`ProfileRefreshPublishingTests`、`BrandRefreshTests` 的 ChatGPT 用例）立刻暴露：主线程不空闲时取数迟迟不开始。改为锁保护的 `RefreshAttemptLedger`，取数任务同步记账，读取不再依赖主线程进度。修复后 5 项相关用例全部恢复，且新增用例继续覆盖「失败计入」。
2. **启动重复读取（实现中已修复）**。第一版启动时先读一次菜单栏来源、凭据准备完成后再读一次，API 来源会重复请求。按来源类型区分：Profile/Google 在 `start()` 立即读，凭据相关的 API 连接只读一次（旧模式由凭据准备收尾读，注册表模式由该账号自己的运行时读）。
3. **可见性契约**：`panelWillOpen(tab:)` 因参数类型为内部类型由 `public` 降为 `internal`；无模块外调用方。

## 边界检查

- 未改任何端点、请求语义、凭证读取路径与跨域拒绝规则；`git diff` 中 `Sources/UsageMonitorCore/Providers` 只剩删除项（面板年龄刷新机制与 `refreshScheduled`），无新增网络路径。
- 菜单栏来源为 Google 时，批次排除的是同一 `googleAccount`；Google 模型的 `attempts` 为其唯一取数时间来源。
- 注册表模式下，旧 DeepSeek 连接的固定 id `deepseek` 与菜单栏 `menuTarget` 映射一致，被正确排除。
- 删除项无遗留引用：`shouldRefreshOnPanelOpen`、`refreshScheduled`、`maxAgeForPanelOpenRefresh`、`panelOpenRefreshAge`、`UsageCache.isStale` 在源码与测试中均已无调用点。
- 生成物：`swift test` 706 项 0 失败；Release 严格签名构建、staging 与正式路径校验见 `ACCEPTANCE.md` 与 `evidence/records/local-install.txt`。

## 残留风险与待现场验证

- 真实请求节奏（菜单栏来源的频率、页面补刷的 5 分钟门槛）需在正式安装版上用真实账号复验，自动测试只能证明判定逻辑与派发范围。
- 切换菜单栏来源后，新来源第一次读取仍等它自己的节奏到点（与 1.6.8 相同）。
- 台账是进程内内存数据，重启后页面第一次打开必定补刷一次。

## 发布后独立复核补充（2026-10-17）

发现尚未修复的 P2：菜单栏某个 ChatGPT 账号刷新期间打开概览或 ChatGPT 页面，另一个账号的自动补刷会被全局 `isRefreshing` 直接丢弃，当前刷新结束后不会补上。隔离副本的 RefreshScopeTests 共 15 项，14 项既有测试通过，新增并发场景失败。详见 [复核记录](evidence/records/post-publication-review.md)、[确定性复现补丁](evidence/records/post-publication-overlap-regression.patch) 与 [测试日志](evidence/logs/post-publication-refresh-scope.log)。原 706 项回归和原用户验收记录保持原结论，本次不能记为无问题通过。

等待当前刷新结束后点品牌页「刷新」或页头「刷新全部」可绕过。v1.6.9 已在本次请求前公开发布，标签与 App 保持原样；修复应进入后续补丁。

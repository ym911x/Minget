# 1.3.1 实施报告

状态：四项需求已实现，自动测试、Release 构建、严格签名和只读边界检查通过；Codex 复核发现的 R1 无障碍阻断已按指定方式修复，等待独立复验。真实界面、真实 DeepSeek 菜单栏余额、A/B 真实点火和机器重启复验仍未执行，保持「待验收」，不以自动测试代替。

本文只记录实现 Agent 在本次任务中实际执行的内容。产品文案、状态语义和范围均取自 `REQUIREMENTS.md` 与 `IMPLEMENTATION_TASKS.md`，未自行重新设计。第二节记录首轮实现，第十节记录 R1 修复轮次的增量。

## 开工基线

- 日期：2026-09-17
- HEAD：`8adaa66`（`Record Minget 1.3.0 publication`）
- 分支：`main`
- 工具链：Apple Swift 6.4（swift-driver 1.168.6），目标 `arm64-apple-macosx27.0.0`
- 测试 scratch path：`/tmp/minget-131-tests`（仓库与 iCloud Drive 之外）

开工前工作区已有改动，全部保留，未清理、未回退、未纳入本次变更集：

- `docs/versions/1.0.2/evidence/01-menubar-states-light.png`
- `docs/versions/1.0.2/evidence/02-menubar-states-dark.png`
- `.commandcode/`、`.workbuddy/`
- `明明有数_Minget_双ChatGPT账号额度窗口自动点火_实施记录_2026-09-16.md`
- `README.md`、`ROADMAP.md` 中由方案阶段加入的 1.3.1 链接与条目

## 1. 修改文件清单

### 新增

| 文件 | 用途 |
| --- | --- |
| `Tests/UsageMonitorAppTests/ProfileRefreshPublishingTests.swift` | 用可控阻塞点确定性地验证双 Profile 按完成顺序发布、失败立即发布、整轮关闭和 `stop()` 后不发布 |
| `Tests/UsageMonitorAppTests/CommandCodeAccessibilityTests.swift` | R1 修复的验证：真实 AX 树中的按钮 press 动作（需 AX 授权，未授权时跳过并明确标注为未执行），以及始终运行的设置入口存在性检查 |

### 修改（源码）

| 文件 | 修改内容 |
| --- | --- |
| `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift` | `refresh` 的 Task Group 元素改为 `profileID`，按完成顺序消费并逐项发布；新增 `publishCompletedProfile` / `finishProfileRefreshCycle`；删除只在整轮结束后发布的 `applyProfileStates`；点火确认改为 2 秒后第一次只读刷新（已确认即结束）＋ 5 秒后第二次只读刷新，并用纯分类器产出最终结果；新增 `finishFireCycle`；`windowConfirmationThreshold` 改为引用 core 的共享阈值 |
| `Sources/UsageMonitorCore/Models/ChatGPTFireResult.swift` | 新增 `.requestSucceededConfirmationUnavailable`（文案「请求成功，暂无法确认」，次要色）；更新 `displayText`、`isFailure` 的穷尽分支；新增纯类型 `FireWindowConfirmation`（`Observation` 固定分类、`confirms`、`classify`、`threshold = 60`）；R1 附带清理把 `ChatGPTFireProcessOutcome` 注释中的 “two request succeeded card values” 改为 “three” |
| `Sources/UsageMonitorCore/Providers/CommandCodeProvider.swift` | `parseSummary` 改为 `try?` 可选解析，credits 仍为唯一必须来源；月度窗口只组合实际取得的字段（`used`/`limit` 缺失时不再推算） |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | `CommandCodeCardPresentation` 新增 `subtitle`、`cacheHelpText`、`helpText`、`accessibilitySubtitle` 并区分 `periodText(.none)` 与 `.unknown`；卡片 Header 改用集中副文案；R1 修复把 Logo／标题／副文案抽成独立的 `CommandCodeHeaderIdentity`，只在该非交互视图上使用 `.accessibilityElement(children: .combine)`，设置按钮留在 `header` 中作为独立兄弟元素；删除卡片内重复的连接文案分支；两处开发态版本 fallback 更新为 `1.3.1` |
| `Sources/UsageMonitorApp/Views/MingetSettingsView.swift` | 设置页开发态版本 fallback 更新为 `1.3.1` |

### 修改（测试）

| 文件 | 修改内容 |
| --- | --- |
| `Tests/UsageMonitorAppTests/FireLifecycleTests.swift` | `ScriptedClient` 增加调用计数；`snapshot` 支持缺重置时间；原「两次缓存得到未变化」改为「暂无法确认」；新增真值表四行、跳过/执行第二次刷新、缺前值、以及 2 秒和 5 秒等待期间停止的用例 |
| `Tests/UsageMonitorCoreTests/CommandCodeProviderTests.swift` | 新增 summary 503／畸形 JSON／401／403、月度字段不伪造、credits 401／结构不支持仍关闭等用例 |
| `Tests/UsageMonitorAppTests/DetailPanelLayoutTests.swift` | 固定 nil summary 三行文案；新增 `periodText` 区分、副文案四态矩阵、缓存帮助文本和辅助功能语义断言 |
| `Tests/UsageMonitorAppTests/DetailEvidenceRenderTests.swift` | 新增 `testRenderCommandCodeCacheAndStatisticsStates`，输出缓存、统计不可用、超长套餐名和周期未确认四种脱敏渲染（浅色/深色） |
| `Tests/UsageMonitorCoreTests/ChatGPTFireServiceTests.swift` | 修正既有计时竞态：`testTimeoutTerminatesTheChildAndReportsTimeout` 的超时由 0.5 秒改为 5 秒（见「已知问题」） |

### 修改（版本与文档）

| 文件 | 修改内容 |
| --- | --- |
| `VERSION` | `1.3.0` → `1.3.1` |
| `CHANGELOG.md` | 新增 1.3.1 中文条目与 English summary 条目 |
| `README.md` | 新增 v1.3.1 修订段；更新当前版本、测试数、点火三态与 Command Code 分层容错描述；补 1.3.1 实施报告链接 |
| `ROADMAP.md` | 1.3.1 条目由「待实施」改为「已实现，待真实界面验收」 |
| `PROVIDER_ENDPOINTS.md` | 适用版本改为 1.3.1；三条 Command Code 路径补记层级容错 |
| `scripts/build.sh` | 内嵌 README 的 “single app-server” 描述改为两个 Profile 各有独立子进程；构建流程未改动 |

## 2. 四项需求的实现落点

### 2.1 双 Profile 完成即发布

- `UsageViewModel.refresh(resetFailureBudget:)`：`withTaskGroup(of: String.self)`，每个 `addTask` 返回自己的 `profileID`。
- 父任务用 `for await completedProfileID in group` 按完成顺序消费，每项调用 `publishCompletedProfile(_:)`：`guard !isStopped, !Task.isCancelled`，然后 `publishProfileStates()` 与 `tick += 1`，不提前结束整轮。
- `publishProfileStates()` 始终从 `coordinator.runtimes` 读取全部运行态快照，因此数组顺序永远是 A、B。
- 整轮结束走单独的 `finishProfileRefreshCycle()`：再次检查停止／取消，设置 `isRefreshing = false`、清空 `refreshTask`、发布最终快照并递增 `tick`。
- 取消／停止路径同样清 `isRefreshing`，但 `guard` 保证停止后不发布任何 UI 状态；`stop()` 仍先 `fireService.stopAll()` 再 drain。
- 既有 `guard !isStopped, !isRefreshing` 保留，普通刷新不叠加。

### 2.2 点火确认三态与延迟重试

- `ChatGPTFireResult.requestSucceededConfirmationUnavailable`，文案「请求成功，暂无法确认」；`isSuccess` 仍只对 `.requestSucceededWindowConfirmed` 为真，`isFailure` 对三种「请求成功」都为假，卡片据此使用次要色。
- `FireWindowConfirmation` 是唯一的判断收敛点：`Observation` 只有 `.live(resetsAt:)` 与 `.noEvidence` 两种固定分类，不携带原始错误、响应或进程输出；`classify(previousReset:observations:)` 实现 `REQUIREMENTS.md §4.3` 的真值表。
- `UsageViewModel.finishFire`：CLI 成功后等 `fireConfirmDelay`（生产 2 秒）→ 第一次只读强制刷新；若已是实时且前移 ≥ 60 秒立即确认并跳过第二次；否则等 `fireRetryDelay`（生产 5 秒）→ 第二次只读刷新 → `classify`。
- `fetchFiveHourResetObservation` 保持 live-only：只有 `FetchResult.isLive == true` 且 5 小时窗口有 `resetsAt` 才算 `.live`。
- CLI 参数、120 秒超时、3 秒 terminate grace、同 Profile 去重和 A/B 并发均未改动；第二次刷新只读额度，不重复模型请求。

### 2.3 Command Code 辅助接口容错

- `fetchUsage`：`let credits = try await parseCredits(...)`（唯一必须），`let summary = try? await parseSummary(...)`，`let subscription = try? await parseSubscription(...)`。
- 月度窗口用 `summary?.monthlyUsed` 与 `credits.monthlyRemaining` 组合：只有 `monthlyUsed` 存在时才计算 `limit = used + remaining`，否则 `used`/`limit` 保持缺失。
- `ProviderUsage.summary` 直接取 `summary?.summary`，用既有 `summary == nil` 表示统计不可用，未新增持久化字段，未引入缓存迁移。
- 连接状态由 ProviderRefreshEngine 依据本次读取是否成功判定；credits 成功即视为连接成功，辅助接口单独 401/403 不再暂停凭证。网络路径、Bearer、Accept、超时和跨域重定向防护未改动。

### 2.4 Command Code 缓存与统计文案

- `CommandCodeCardPresentation.subtitle(connection:planName:)` 实现固定四态；`cacheHelpText` 生成「缓存数据 · 上次成功 MM-dd HH:mm」或「缓存数据 · 成功时间未知」；`helpText` 与 `accessibilitySubtitle` 复用同一套判断。
- 视图 Header 只调用这些函数，不再另写连接文案分支；副文案保持 `lineLimit(1)` + 尾部省略。
- `periodText` 区分 `.none`（统计暂不可用）与 `.unknown`（统计周期未确认）；`summaryLines(nil)` 第一行固定为「统计暂不可用 · Token — · 请求 —」。
- 卡片 416 × 162 pt、轨道宽度、字号、间距和三条额度行未改动；四种详情页高度断言未改动。

## 3. 测试

### 3.1 新增与修改的测试

新增：`ProfileRefreshPublishingTests`（5 项）
- `testAFastProfilePublishesBeforeTheBlockedProfileReturns`
- `testBFastProfileAlsoPublishesFirstAndKeepsTheArrayOrder`
- `testAFailedProfilePublishesItsFailureWhileTheOtherIsBlocked`
- `testTheRoundClosesAndTheNextOneIsAllowed`
- `testALateResultAfterStopIsNeverPublished`

`FireLifecycleTests` 新增（9 项）
- `testTheConfirmationTruthTableIsExhaustive`
- `testTheThreeRequestSucceededResultsCarryNoSuccessOrFailureColour`
- `testAConclusiveFirstReadSkipsTheSecondRefresh`
- `testAnUnchangedFirstLiveReadStillTriggersTheSecondRefresh`
- `testTwoLiveReadsBelowTheThresholdReportUnchanged`
- `testAPreFireStateWithoutAWindowCannotConfirm`
- `testStoppingInsideTheConfirmWaitPublishesNothing`
- `testStoppingInsideTheRetryWaitSkipsTheSecondRead`

`CommandCodeProviderTests` 新增（5 项）
- `testSummaryFailureKeepsCreditsLiveAndReportsNoStatistics`
- `testMalformedSummaryJSONKeepsTheCreditsWindows`
- `testSummaryUnauthorizedDoesNotDiscardCredits`
- `testSummaryFailureKeepsTheMonthlyRemainingWithoutFabricatingUsedOrLimit`
- `testCreditsUnauthorizedStillSuspendsTheCredential`
- `testUnsupportedCreditsStructureFailsClosedEvenWithAHealthySummary`

`DetailPanelLayoutTests` 新增（4 项）
- `testMissingSummaryAndUnknownPeriodAreWordedDifferently`
- `testTheHeaderSubtitleFollowsTheConnectionAndPlanMatrix`
- `testTheCacheHelpTextCarriesTheLastSuccessTimeOrSaysItIsUnknown`
- `testTheAccessibilityValueRepeatsTheCacheSemantics`

`DetailEvidenceRenderTests` 新增（1 项）
- `testRenderCommandCodeCacheAndStatisticsStates`

`CommandCodeAccessibilityTests` 新增（2 项，其中 1 项在本机跳过）
- `testTheSettingsEntryIsStillDrawnAsARealControl`（始终运行）
- `testTheSettingsButtonKeepsItsOwnAXPressAction`（真实 AX 树，需运行器获得辅助功能授权）

按新语义修改：`FireLifecycleTests.testTwoCachedRefreshesReportTheRequestWithoutConfirmingAWindow`（由「窗口未变化」改为「暂无法确认」）、`DetailPanelLayoutTests.testCommandCodeAlwaysHasThreeQuotaRowsAndThreeSummaryLines`（固定 nil summary 三行文案）。`ChatGPTFireServiceTests.testTimeoutTerminatesTheChildAndReportsTimeout` 修正超时预算。

### 3.2 总测试数与命令结果

| 测试层级 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: |
| Core | 331 | 0 | 0 |
| App | 119 | 0 | 1 |
| 合计 | 450 | 0 | 1 |

唯一跳过项是 `CommandCodeAccessibilityTests.testTheSettingsButtonKeepsItsOwnAXPressAction`；跳过原因与影响见第 6 节和第 10 节。

执行命令与结果：

| 命令 | 结果 |
| --- | --- |
| `swift build --build-tests --disable-sandbox --scratch-path /tmp/minget-131-tests` | 全部目标与测试目标编译通过 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter ProfileRefreshPublishingTests` | 5 项通过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter FireLifecycleTests` | 14 项通过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter CommandCodeProviderTests` | 17 项通过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter DetailPanelLayoutTests` | 30 项通过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter DetailEvidenceRenderTests` | 4 项通过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter CommandCodeAccessibilityTests` | 1 项通过、1 项跳过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests` | Core 331 + App 120（含 1 项跳过）= 451 项执行，0 项失败；连续两次结果一致 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter StartupWindowTests` | 2 项通过，0 项失败 |

（基线 1.3.0 为 Core 325 + App 100 = 425 项。首轮 1.3.1 为 449 项；R1 修复后新增 `CommandCodeAccessibilityTests` 2 项，App 由 118 增至 120。）

## 4. Release 构建与签名

| 命令 | 结果 |
| --- | --- |
| `./scripts/build.sh` | Release 构建成功；staging 严格签名、两个嵌套可执行文件严格签名、`Info.plist` 校验、固定运行路径严格签名全部通过；`dist/Minget.app` 归档副本通过普通校验（严格校验受 iCloud 文件提供方属性影响，脚本按既有约定记录） |
| `codesign --verify --strict --verbose=2 "$HOME/Applications/Minget.app"` | 通过：`valid on disk`、`satisfies its Designated Requirement`（退出码 0） |
| `defaults read "$HOME/Applications/Minget.app/Contents/Info.plist" CFBundleShortVersionString` | `1.3.1` |

## 5. 实际运行检查与未验证项

### 已执行的本机检查

- **冷启动与退出清理（真实签名包）**：`StartupWindowTests` 针对新构建的 1.3.1 运行包执行，`testColdStartShowsNoWindowOtherThanTheDetailPage` 与 `testQuitLeavesNoOwnedCodexChildBehind` 均通过——冷启动后该进程拥有的 layer-0 窗口数为 0，退出后没有属于本应用的子进程。
  - 边界：该测试启动的是生产 App，生产启动路径会按既有逻辑执行只读刷新（ChatGPT 额度、以及已配置凭证时的 DeepSeek／Command Code）。本轮命令记录无法证明当时是否实际读到了 Keychain 凭证，因此它只作为「窗口与进程清理」证据，**不计入**任何真实余额或用量验收。
- **无遗留子进程**：`pgrep -fl "codex app-server"` 与 `ps` 扫描 `~/.codex-minget-*` 均未发现本应用遗留的自有子进程（机器上存在的是 ChatGPT 桌面应用自己的 app-server，命令行指向 `/Applications/ChatGPT.app/...`，与本应用无关）。
- **脱敏渲染**：`$TMPDIR/Minget-1.3.0-Evidence/` 下生成 `06-commandcode-cache-light.png`、`07-commandcode-cache-dark.png`，另更新 `01-detail-440x552-light.png`、`02-detail-440x552-dark-a-cached.png`、`03-detail-440x330-light.png`、`04-chatgpt-card-states-light.png`、`05-commandcode-cards-light.png`。已目检 06 号图：连接态显示套餐名与「统计暂不可用 · Token — · 请求 —」，缓存态显示「individual-go · 缓存」，超长套餐名仍为单行，周期未确认态保留真实数字。
- **只读边界检查**（见第 7 节）。

### 仍未验证（保持「待验收」）

- 真实界面：正常、缓存、统计不可用三种 Command Code 状态在真实凭证下的表现，以及四种详情页尺寸无截断、无滚动条（`ACCEPTANCE.md` 中相关项目）。
- 真实 DeepSeek 菜单栏余额与详情余额一致性（沿用 1.3.0 待验收）。
- A/B 两次真实应用内点火：会产生真实模型请求，需用户在执行阶段另行明确授权，本次未执行。
- 机器完整重启后的 Profile 缓存隔离复验（沿用 1.3.0 待验收）。
- 一分钟刷新周期下两个 Profile 的真实完成顺序（自动测试以可控阻塞点覆盖该时序，真实环境不作为证据）。

## 6. 已知问题与范围外事项

- **既有计时竞态（已修正）**：`ChatGPTFireServiceTests.testTimeoutTerminatesTheChildAndReportsTimeout` 原先使用 0.5 秒超时，偶发早于 `python3` 写完 PID 文件而报 `pid.txt` 不存在。该用例不属于本次四项需求，但会使全量测试非确定性失败。已把超时预算改为 5 秒（仍远低于子进程的 120 秒 sleep），断言重新针对被测行为。这是在连续多次全量运行中实际观察到的间歇失败，不是猜测。
- **渲染证据的宿主限制（沿用 1.3.0）**：证据图运行在 XCTest 宿主中，`Bundle.main` 指向测试进程，品牌资源与版本号回退为占位。几何、轨道、文案与数据为真实渲染结果；签名包内品牌资源显示正常。
- **环境限制（沿用 1.3.0）**：裸 `swift test` 在本仓库 iCloud 路径下会因 File Provider 扩展属性导致测试包签名失败，所有测试均使用仓库外 `--scratch-path`。
- **范围外**：账号管理、自动点火、通知、公证、自动更新、功耗重构和第三方新端点均未涉及。Command Code 卡片内没有新增缓存持久化字段，`summary == nil` 仍由既有结构表达。
- **辅助功能树在 XCTest 运行器中不可观测（R1 复验相关）**：XCTest 运行器不是 GUI 应用，进程不会向辅助功能服务注册窗口，因此**即使它已获 AX 信任也拿不到树**。实测（2026-09-18）：`AXIsProcessTrusted()` 在两次运行中分别出现 `false` 与 `true`，但两种情况下 `kAXWindows` 都返回 0（期间 `NSApp.windows.count == 1`，窗口确实存在）；未信任时自身 AX 查询返回 `kAXErrorNotImplemented`；System Events 能看到 `xctest` 进程但看不到它的窗口。结论是「树里没有按钮」在本运行器中无法区分 R1 是否修复，对应的 AX 用例因此在缺少可观测树时明确跳过并标注为「未执行」，未被当作通过。真实的辅助功能树证据改由第 10 节的独立验证程序取得。
- **曾尝试并放弃的一条错误验证路径（记录以免重复）**：先写过一版「结构守卫」——用 SwiftUI 是否为按钮生成 AppKit 子视图来判断按钮是否落在 `.combine` 容器内。实测不成立：把按钮放进带 `.combine` 的视图后，SwiftUI 对默认样式按钮不生成 `SwiftUIAppKitButton`（只生成 `KeyViewProxy` 与 `_FocusRingView`），该守卫对错误结构同样通过。该实现已删除，只保留能真实观测的「设置入口仍被绘制为真实控件」检查。

## 7. 只读检查结果

| 检查项 | 结果 |
| --- | --- |
| 是否新增模型端点 | 否。`grep` 命中的 `chat/completions` 只出现在 `ProviderRequestGuard` 的永久阻断列表中 |
| 是否读取认证 JSON、浏览器会话或全局配置 | 否。`Sources/` 内 `auth.json`、`.codex/auth`、`.codex/config`、`HTTPCookie`、`WKWebsiteDataStore`、`NSHTTPCookieStorage` 均无匹配 |
| 详情页与设置页是否新增滚动容器 | 否。`Sources/UsageMonitorApp/` 内无 `ScrollView`、`NSScrollView`、`NSTableView`、`NSOutlineView` |
| 公开文件是否含真实邮箱、余额、API Key、token、session id 或原始响应 | 否。1.3.1 目录、根目录文档与本次修改的源码／测试中，未发现密钥、Bearer 值、JWT 或非 `example.com` 邮箱 |
| 开工前无关改动是否保留 | 是。`docs/versions/1.0.2/evidence/01`、`02`、`.commandcode/`、`.workbuddy/` 与根目录实施记录均保持开工时状态，未进入本次变更集 |

## 8. 声明

- 未执行任何真实点火，未主动执行任何真实服务验收，未消耗任何额度。
- 未主动发起真实带认证请求；但需明确边界：签名包冷启动测试会启动生产 App，其正常启动路径可能执行只读刷新并读取 Keychain 凭证。本轮记录无法证明是否实际取得凭证，因此该启动测试只作为窗口与进程清理证据，不作为任何真实余额或用量数据验收。
- 未提交（`git commit`）、未推送远端、未打标签、未创建或修改 GitHub Release。
- 本次唯一的生产状态改动是安装到固定运行路径的本地 Release 构建（`~/Applications/Minget.app`，版本 1.3.1），用于严格签名验证和签名包启动检查；该构件未发布。
- 未读取、列出或修改 `~/.codex-minget-a`、`~/.codex-minget-b`、`~/.local/bin/minget-fire` 和现有 LaunchAgent 的任何内容。
- 未修改 `docs/archive/v1.0/`。

## 9. 交接

首轮四项需求实现完成后，Codex 独立复核发现 R1 无障碍阻断。R1 已按指定方式修复，见第 10 节；请 Codex 复验后更新本目录的 `REVIEW.md` 与 `ACCEPTANCE.md`，并由用户完成真实界面验收。

## 10. R1 修复（2026-09-18）

依据：`REVIEW.md` R1 —— Command Code 卡片无数据时，`header` 整体使用 `.accessibilityElement(children: .combine)`，把标题、状态文字和条件式「前往设置／查看设置」按钮合并为一个元素，按钮失去独立的 `AXPress` 动作。等级 P1，发布前必须修复。

### 修改

| 文件 | 修改内容 |
| --- | --- |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 把 Logo、标题和副文案抽成新的 `CommandCodeHeaderIdentity` 视图，`.accessibilityElement(children: .combine)` 与缓存 label/value **只**施加在这个非交互视图上；`header` 改为 `HStack { CommandCodeHeaderIdentity; Spacer; 设置按钮 }`，`header` 自身不再有任何辅助功能合并修饰符，按钮保持为独立兄弟元素 |
| `Tests/UsageMonitorAppTests/CommandCodeAccessibilityTests.swift` | 新增。真实 AX 树检查（`AXUIElementCreateApplication(getpid())` → `AXWindows` → 递归查找 `AXButton`，断言 `AXActionNames` 含 `AXPress`），以及对「设置入口仍是真实控件、且仅在没有用量报告时出现」的始终运行的检查 |
| `Sources/UsageMonitorCore/Models/ChatGPTFireResult.swift` | 注释 “two request succeeded card values” 改为 “three” |

逐条对应固定修复要求：

1. 不再对包含按钮的整个 header 使用 `.combine` —— `header` 内已无 `.accessibilityElement`，全文件仅剩 `CommandCodeHeaderIdentity` 内一处 `.combine`（另有卡片级 `.accessibilityElement(children: .contain)`，`.contain` 保留子元素，不合并）。
2. 只组合 Logo、标题和状态文字 —— 这三项现在只存在于 `CommandCodeHeaderIdentity` 中。
3. 设置按钮保留为独立辅助功能按钮 —— 按钮是 `header` 的直接子元素，位于组合元素之外，标题与 `.link` 样式未改。
4. 真实辅助功能树测试 —— 已添加：`CommandCodeAccessibilityTests.testTheSettingsEntryKeepsItsOwnElementAndPressAction` 断言设置入口是独立元素、与身份元素不是同一节点、且 `AXPress` 能触发产品动作。该用例在 XCTest 运行器中**跳过**（运行器不是 GUI 应用，拿不到辅助功能树，详见第 6 节），因此**在测试体系内没有取得通过证据**。同一断言逻辑改由第 10 节的独立验证程序在受信任的 GUI 进程中实际执行并取得结果，见「真实辅助功能树实测」一节；该结果是本轮新增证据，但仍应由 Codex 或用户复验。
5. 注释清理 —— 已完成。

### 复验结果

| 命令 | 结果 |
| --- | --- |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter CommandCodeAccessibilityTests` | 1 项通过、1 项跳过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter DetailPanelLayoutTests` | 30 项通过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests --filter DetailEvidenceRenderTests` | 4 项通过，0 项失败 |
| `swift test --disable-sandbox --scratch-path /tmp/minget-131-tests` | Core 331 + App 120（含 1 项跳过）= 451 项执行，0 项失败；连续两次一致 |
| `./scripts/build.sh` + 固定路径 `codesign --verify --strict --verbose=2` | 通过，`CFBundleShortVersionString = 1.3.1` |

### 真实辅助功能树实测（2026-09-18）

XCTest 运行器不受 AX 信任，无法自行读取辅助功能树；但发现**由 shell 直接启动的自编译二进制会继承终端的辅助功能信任**（实测 `AXIsProcessTrusted() == true`）。据此写了一个一次性验证程序：把 `Sources/UsageMonitorCore` 与 `Sources/UsageMonitorApp`（排除 `@main` 入口）连同 harness 一起编译，在真实 `NSApplication` 事件循环里显示真实的 `CommandCodeOverviewCard`，再用 `AXUIElementCreateApplication(getpid())` 读取自己的辅助功能树并实际执行 `AXPress`。

命令（重建方式）：

```bash
# harness 位于仓库外临时目录；编译真实视图源码 + main.swift
swiftc -O <Sources/UsageMonitorCore/*.swift> \
       <Sources/UsageMonitorApp/*.swift 除去 UsageMonitorApp.swift> \
       main.swift -framework AppKit
```

实测结果，同一份源码、只改 `header` 的辅助功能组合方式：

| 组合方式 | 辅助功能树中的元素 | 设置入口元素 | `AXPress` |
| --- | --- | --- | --- |
| 修复后（1.3.1） | `AXStaticText desc=Command Code value=未连接` + `AXLink desc=前往设置` | 存在，独立元素，`AXLink` | 成功，且确实触发产品动作 |
| R1 原状（整个 header `.combine`） | 单个 `AXButton desc=Command Code value=未连接` | **不存在** | 成功，且按钮动作仍被触发 |

可见区别有两处，也据此修正对 R1 证据的表述：

1. **修复生效**：设置入口现在是自己的辅助功能元素，带自己的名称「前往设置／查看设置」，与合并后的身份元素分离；VoiceOver 能单独聚焦并激活它，且缓存副文案（`Command Code, <副文案>`）仍由身份元素读出，两者互不覆盖。
2. **与 R1 描述的差异**：R1 说按钮「失去独立的 `AXPress` 动作」。实测在无数据卡片这种「容器里只有一个 Button」的情形下，合并后的元素执行 `AXPress` 仍会触发按钮动作，所以真正的损失是**入口元素本身和它的名称消失了**（VoiceOver 只会念出「Command Code，未连接，按钮」，用户无从知道它通向设置），而不是动作完全失效。修复方式不变且更优，但这一点必须按实测记录，不沿用过强的表述。

另外记录一条方法上的限制：本测试用例在未授权的运行器上会因树为空而**失败**，不会静默通过；把守卫临时短路后实测确实失败（`the combined identity element must be reachable`），确认用例非空转。

### 对 R1 证据方法的一点说明

R1 描述的证据是「最小 `NSHostingView` 检查中辅助功能树没有按钮的 `AXPress` 动作」。在 XCTest 运行器里复现该做法时得到的是**空树**：不仅没有按钮，也没有任何 SwiftUI 元素；把同一查询用在修复后的代码上，结果同样是空树。也就是说，用未受信任的运行器做这个观察，无法区分正确与错误组合，既不能证明有缺陷，也不能证明已修复。

改用受信任的一次性验证程序后（见上一节），可以真正区分两种组合，并且测到的缺陷比 R1 的描述更具体：**入口元素和它的名称被合并掉了**，而 `AXPress` 在该形态下仍能把动作转发出去。

修复按 R1 指定的方式完成，且不依赖上述任何一种证据方法都成立：按 Apple 语义，`.accessibilityElement(children: .combine)` 会把容器内的交互控件并入容器，交互子元素不再单独可达，因此把设置按钮留在组合元素之外是正确的做法，与普通鼠标操作无关。

最终确认建议二选一：

1. 在受信任的环境里运行 `CommandCodeAccessibilityTests.testTheSettingsEntryKeepsItsOwnElementAndPressAction`（本机该用例因运行器未授权而跳过）；
2. 或用 VoiceOver 在 Command Code 无数据状态下确认「前往设置」被单独读出、可聚焦、可激活。

二者任一完成即可把 R1 标为已复验；本报告不代替该复验。

# 1.3.0 实施任务

本文是给实现 Agent 的主任务单。首轮实现未通过用户界面验收，当前重新进入实施状态。先执行 `REVISION_SPEC.md`，界面实现同时逐项遵守 `UI_SPEC.md`。不得用实现说明代替代码、测试和真实运行证据。

> 2026-09-17 第三轮微调：用户在第二轮真实界面检查后要求继续收窄详情页、调整周期分组、精简 Command Code 文案并重排 DeepSeek。最新尺寸和文案以 `UI_SPEC.md` 为准；本文件下方 520 pt 条目保留第二轮任务背景，不再作为最终尺寸。

## 0. 开工前检查

| 任务 | 状态 | 完成标准 |
| --- | --- | --- |
| 阅读项目规则与版本资料 | 待实施 | 完整阅读根目录 `AGENTS.md`、`README.md`、`ROADMAP.md`、`PROVIDER_ENDPOINTS.md` 和 `docs/versions/1.3.0/` |
| Xcode license | 已完成 | 2026-09-16 用户输入 `agree`；已复核 `swift --version` 和系统 `git status` 正常 |
| 建立可复现测试命令 | 已完成 | iCloud 内默认 `.build/out` 会触发扩展属性签名失败；使用仓库外 `--scratch-path` 后 310 项测试通过 |
| 保护现有工作区改动 | 待实施 | 不修改两张已变化的 1.0.2 evidence PNG，不纳入 `.workbuddy/` 和实施记录文件 |
| 填写实施记录 | 待实施 | 按现有 `IMPLEMENTATION_REPORT.md` 模板逐步记录改动文件、命令、测试、真实验证、已知问题 |
| 核实现前基线 | 已完成 | HEAD `938b7f3`；`swift test --scratch-path <仓库外临时目录>`：310 项通过，0 项失败 |

当前只读检查发现工作树已有用户改动：

- `docs/versions/1.0.2/evidence/01-menubar-states-light.png`
- `docs/versions/1.0.2/evidence/02-menubar-states-dark.png`
- `.workbuddy/`
- 根目录的本机点火实施记录 `明明有数_Minget_双ChatGPT账号额度窗口自动点火_实施记录_2026-09-16.md`（未纳入 Git）

这些内容不得清理、覆盖或误提交。

> 2026-09-18 目录整理：该本机实施记录已脱敏迁移为 [FIRE_DESIGN_BACKGROUND.md](FIRE_DESIGN_BACKGROUND.md)，根目录原文件已删除。

## 1. Profile 与多服务核心

### 1.1 新增模型

必须新增：

- `Sources/UsageMonitorCore/Models/ChatGPTAccountProfile.swift`
- `Sources/UsageMonitorCore/Services/CodexProfileRuntime.swift`
- `Sources/UsageMonitorCore/Services/CodexProfilesCoordinator.swift`

任务：

- 按需求文件中的固定值定义两个只读 Profile。1.3.0 不做 Profile 编辑 UI，也不把 Profile 写入 UserDefaults。
- Profile 只保存 ID、显示名称、菜单栏短标签和相对 `CODEX_HOME`，不保存任意命令或点火参数。
- 只在路径解析层展开用户主目录，不在默认值、日志和公开文档写个人绝对路径。
- 把可配置数据与运行态分离。运行态包含 service、display、account、connection、refresh/fire 状态。
- 为两个 Profile 建立独立 `UsageService`，支持并行刷新、独立失败预算和独立停止。

### 1.2 传递 `CODEX_HOME`

必须修改：

- `Sources/UsageMonitorCore/Services/UsageService.swift`
- `Sources/UsageMonitorCore/Services/JSONRPCClient.swift`

任务：

- 为生产 service factory 增加明确的 child environment 参数。
- 用当前环境的副本覆盖 `CODEX_HOME`，传入 `JSONRPCClient`。
- `CodexLocator` 保持不变；它继续只负责定位可执行文件，账号隔离完全由 `JSONRPCClient.environment` 完成。
- 保持可执行文件 URL 直启，禁止 shell。
- 保证环境值不进入 `Diagnostics`。

### 1.3 Profile 级缓存

必须修改：

- `Sources/UsageMonitorCore/Services/UsageCache.swift`
- `Sources/UsageMonitorCore/Services/UsageService.swift`

任务：

- 新增 v3 Profile 级缓存结构，绑定 `profileID`、`accountID` 和 snapshot。
- 将 last-known account 改为按 Profile 保存。
- 严格实现 v2 缓存迁移：升级后不展示；账号 A 首次成功读到 accountID 时，仅同 ID 迁移，否则删除；账号 B 永不接收。
- 不改变 DeepSeek / Command Code 的 `ProviderCache` 格式。

## 2. 应用组合与 ViewModel

必须修改：

- `Sources/UsageMonitorApp/UsageMonitorApp.swift`
- `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`

任务：

- `AppContainer` 从单一 `codexService` 改为 `CodexProfilesCoordinator`。
- ViewModel 发布有稳定顺序的 `[CodexProfileViewState]`，不再把单值状态当成全部账号。
- 启动时并行刷新两个 Profile，定时器每轮刷新两个 Profile但不重复叠加请求。
- 面板打开和手动刷新按 Profile 的 freshness/force 规则运行。
- 停止流程必须等待两个 service drain；任一超时需要固定分类诊断，不能遗留子进程。
- DeepSeek、Command Code 的刷新循环保持独立。

## 3. 菜单栏来源选择

### 3.1 偏好模型

必须新增：

- `Sources/UsageMonitorApp/ViewModels/MenuBarPreferences.swift`

任务：

- 定义可 Codable 的稳定选择：Profile ID 或 DeepSeek。
- 升级默认值为账号 A。
- DeepSeek 多币种选择严格按 `已保存 → CNY → USD → 币种代码升序 → 未确认币种` 回退。
- 偏好对象只保存显示选择，不触碰凭证、缓存或刷新控制。

### 3.2 菜单栏内容

必须修改：

- `Sources/UsageMonitorCore/Utilities/MenuBarContent.swift`
- `Sources/UsageMonitorApp/Views/MenuBarLabelView.swift`
- `Sources/UsageMonitorApp/StatusItem/StatusItemController.swift`
- `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`

任务：

- 将 `MenuBarContentBuilder` 从只接收单一 Codex display 改为接收已解析的菜单栏来源快照。
- ChatGPT 完整/紧凑文字严格使用需求文件的固定格式，并保留双额度和双时间条。
- DeepSeek 路径隐藏时间条，严格使用 `DS CNY 余额 123.45` / `DS CNY 123.45` 格式。
- 继续保证最多一个异常标记、缓存状态不冒充实时数据、内容签名变化时重新测量宽度。
- 为 ChatGPT A、ChatGPT B、DeepSeek 单币种、多币种、不可用、缓存、完整和紧凑模式补齐纯函数测试和渲染证据。

### 3.3 设置页

必须修改：

- `Sources/UsageMonitorApp/Views/MingetSettingsView.swift`

任务：

- 增加“菜单栏显示”单选 Picker。
- 列出两个 Profile 的显示名称；DeepSeek 多币种时显示币种 Picker。
- 设置页固定 `520 × 600 pt`、无滚动容器；菜单栏来源使用纵向 radio group；DeepSeek/Command Code 管理表单使用单开 accordion。
- 保留 DeepSeek 和 Command Code 详情显示开关，不能把“详情隐藏”和“菜单栏选择”混为同一偏好。
- 如果菜单栏选中 DeepSeek，即使详情卡隐藏，也应继续显示余额；界面需明确两者相互独立。

## 4. 详情页双账号

必须修改：

- `Sources/UsageMonitorApp/Views/UsagePanelView.swift`
- `Sources/UsageMonitorApp/StatusItem/StatusItemController.swift`

必须新增：

- `Sources/UsageMonitorApp/Views/CodexProfileCard.swift`
- `Sources/UsageMonitorApp/ViewModels/CodexProfileViewState.swift`

任务：

- 保留由 `CodexProfileViewState` 驱动的两个可复用 ChatGPT 卡片，状态继续互相隔离。
- 禁止使用任何滚动容器。把首轮 720 pt 双列实现改成 520 pt 单列，固定顺序 A → B → DeepSeek → Command Code。
- 严格实现 `520 × 560 / 486 / 398 / 324 pt` 四种页面尺寸，卡片宽均为 496 pt；ChatGPT 126 pt、DeepSeek 68 pt、Command Code 156 pt。
- ChatGPT 恢复 1.2.1 的两条额度剩余轨道和两条重置时间轨道；5 小时 5 段、周额度 7 段。
- DeepSeek 恢复紧凑横向样式，多币种最多横向 3 项，超过时显示固定溢出提示。
- Command Code 保留三条额度和三行摘要，并给三个窗口增加时间剩余轨道；额度 fraction 改为 `remaining / limit`。
- 偏好变化时普通详情窗口立即调整 content size；popover 在 show 前设置相同 preferredContentSize。
- 以状态按钮 `midX` 为 popover 锚点；当前屏幕不能完整容纳时改用普通详情窗口。
- 全局刷新触发两个 Profile；单个 Profile 的点火后只强制刷新该 Profile。
- 顶部全局更新时间必须汇总可见来源，不能只看账号 A。

### 4.1 启动空窗口

- 删除 SwiftUI `Settings { EmptyView() }` Scene，改成 `NSApplication` + `AppDelegate` 的显式 AppKit 入口。
- 冷启动不创建任何空窗口；设置窗口只由用户点击设置入口创建。
- 保留菜单栏不可见时打开真实详情窗口的既有降级。

## 5. 点火服务

### 5.1 核心实现

必须新增：

- `Sources/UsageMonitorCore/Services/ChatGPTFireService.swift`
- `Sources/UsageMonitorCore/Models/ChatGPTFireResult.swift`

任务：

- 使用 `CodexLocator` 定位官方 CLI，以 `Process` 直接执行需求文件给出的固定参数；禁止调用 `minget-fire` 和禁止 shell。
- 为子进程覆盖对应 Profile 的 `CODEX_HOME`，工作目录固定为系统临时目录下 `minget-fire`。
- stdout/stderr 均接到 `Pipe` 并持续 drain 后丢弃，避免子进程因管道写满阻塞；不写入项目日志，不把原始文本返回 UI。
- 超时严格为 120 秒；terminate 后等待 3 秒，再只 kill 本次 PID 并回收。
- 增加幂等 `stopAll()`；应用退出时终止并回收所有仍运行的点火子进程，不能只取消外层 Swift Task。
- 返回固定分类结果和退出码，不返回 shell/Codex 原始错误文本。
- 同 Profile 第二次请求立即返回 `.alreadyRunning`，不排队、不合并；不同 Profile 可并行。

### 5.2 UI 和刷新核验

必须修改：

- `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`
- `Sources/UsageMonitorApp/Views/CodexProfileCard.swift`

任务：

- 使用需求文件中给定的 `confirmationDialog` 标题、正文和按钮文字。
- 点火时禁用对应按钮并显示进度。
- 成功后等待 2 秒刷新；未取得实时结果时再等 5 秒重试一次；只有 `FetchResult.isLive == true` 且 `resetsAt` 至少推后 60 秒才确认新窗口。
- 明确区分“请求成功”和“新窗口已确认”。
- 不从 `fire-A.log`、`fire-B.log` 中解析状态；这些 raw log 当前含 Codex CLI session 信息，不适合作为产品数据接口。

## 6. 测试任务

### 6.1 Core 单元测试

必须新增：

- `Tests/UsageMonitorCoreTests/CodexProfilesCoordinatorTests.swift`
- `Tests/UsageMonitorCoreTests/UsageCacheTests.swift`
- `Tests/UsageMonitorCoreTests/ChatGPTFireServiceTests.swift`

必须修改：

- `Tests/UsageMonitorCoreTests/JSONRPCTransportTests.swift`
- `Tests/UsageMonitorCoreTests/MenuBarContentTests.swift`

必须覆盖：

- 两个子进程得到不同 `CODEX_HOME`。
- A/B 并行刷新、独立失败、独立 failure budget。
- Profile + account 双重缓存隔离和 v2 到 v3 迁移。
- 外部换号后不继续显示旧账号为当前账号。
- 两服务停止和并发停止不遗留子进程。
- Codex CLI 缺失、成功、非零退出、超时、重复点击和 A/B 并行。
- 点火测试只用临时 fake executable，禁止真实模型调用。
- 菜单栏三种来源、DeepSeek 金额语义、多币种、缓存和错误状态。

### 6.2 App 与布局测试

必须修改：

- `Tests/UsageMonitorAppTests/ProductionWiringTests.swift`
- `Tests/UsageMonitorAppTests/DetailPanelLayoutTests.swift`
- `Tests/UsageMonitorAppTests/MenuBarLabelWiringTests.swift`
- `Tests/UsageMonitorAppTests/MenuBarEvidenceRenderTests.swift`
- `Tests/UsageMonitorAppTests/StatusItemWiringTests.swift`

必须覆盖：

- 生产 composition 确实创建两个 Profile runtime。
- 设置选择持久化、升级默认账号 A、DeepSeek 币种选择。
- 两个 Codex 卡片与两个点火按钮存在，状态互不污染。
- 详情页视图树不包含 `ScrollView`/`List`/`NSScrollView`；四种固定页面尺寸、单列顺序和每张卡片尺寸完全一致。
- 冷启动没有可见空窗口；设置入口只创建一个真实设置窗口。
- ChatGPT 每卡同时有 2 条额度轨道和 2 条时间轨道，段数固定 5/7。
- Command Code 的 fraction 使用 remaining，5/7/月时间线的段数和缺失状态正确。
- popover 中心锚点、显示前 contentSize 和 visibleFrame 降级有纯几何测试。
- 正在运行的 fake 点火进程在 stop 后被终止回收；缓存刷新不能确认新窗口。
- 菜单栏切换后实时重测宽度，紧凑降级无截断。
- CI 无 WindowServer 时只跳过真实图形状态项安装，纯布局和内容测试仍运行。
- `MenuBarEvidenceRenderTests` 和新增详情渲染测试默认只写入 `$TMPDIR/Minget-1.3.0-Evidence/`。自动测试不得写 `docs/archive/`、`docs/versions/1.0.2/` 或任何历史 evidence 目录；需要入库的脱敏图片在人工审核后单独复制到 `docs/versions/1.3.0/evidence/`。

## 7. 真实验收顺序

自动测试和构建全部通过后，按以下顺序执行，禁止把 fixture 结果写成真实通过：

1. 启动签名后的固定路径 `~/Applications/Minget.app`。
2. 确认账号 A 卡片显示 A 的邮箱、套餐和额度；账号 B 同理。
3. 在两个账号额度明显不同的时刻切换菜单栏 A/B，核对文字和重置时间对应正确。
4. 切到 DeepSeek，核对币种和金额与详情卡一致；断网或 API 失败时不得显示零余额。
5. 分别点击 A、B 的点火按钮，各确认一次真实请求。记录固定结果，不保存原始输出。
6. 如果点火发生在新窗口边界，确认 `resetsAt` 变化后 UI 才显示“新窗口已确认”；若仍在旧窗口，确认 UI 只报告请求成功。
7. 连续三次完全退出和重启；检查没有遗留的自有 `codex app-server`，两个 Profile 缓存不串号。
8. 验证现有 LaunchAgent、脚本和两个 `CODEX_HOME` 的时间戳/内容未被应用修改。
9. 冷启动确认不出现空设置窗口；弹层在菜单栏图标附近完整位于屏幕内。
10. 用户完成浅色、深色、单列弹层、普通详情窗口、Command Code 时间线和设置页体验确认。

基线和最终测试统一使用以下模式，临时路径必须位于仓库和 iCloud Drive 之外：

```bash
MINGET_TEST_SCRATCH="$(mktemp -d /tmp/minget-swift-test.XXXXXX)"
swift test --scratch-path "$MINGET_TEST_SCRATCH"
```

不要直接运行裸 `swift test` 作为最终证据。Xcode 27 会在本项目 iCloud 路径的 `.build/out` 对测试包签名，并可能因 File Provider 扩展属性失败。

## 8. 文档和版本收尾

实现完成后同步更新：

- `VERSION`
- `README.md`
- `CHANGELOG.md`
- `ROADMAP.md`
- `PROVIDER_ENDPOINTS.md`
- `docs/ARCHITECTURE.md`
- `docs/versions/1.3.0/IMPLEMENTATION_REPORT.md`
- `docs/versions/1.3.0/REVIEW.md`
- `docs/versions/1.3.0/ACCEPTANCE.md`

最终测试数必须在所有文档中一致。公开截图只能使用脱敏副本。

## 9. 实现 Agent 的停止条件

出现以下任一情况时停止扩大范围并在报告中写明：

- 必须读取或复制 `auth.json` 才能继续。
- 必须修改或调用现有 `minget-fire`、修改 LaunchAgent 或修改两个 `CODEX_HOME` 才能完成本任务。
- 点火只能通过 shell 拼接任意字符串实现。
- 两个 app-server 无法在独立 `CODEX_HOME` 下稳定并存。
- 仓库外 scratch path 仍无法完成测试、编译或签名。

不得自行发布、推送远端、打标签或创建 GitHub Release。

# 1.3.0 实施报告

> 2026-09-17：首轮界面未通过用户验收，修订要求见 `REVISION_SPEC.md`。第三轮界面微调与最终验证记录在本文开头，其后第二轮和首轮内容作为历史记录保留。

当前状态：第三轮界面微调已完成；425 项自动化测试、Release 构建、严格签名与真实详情页验收通过。真实 DeepSeek 菜单栏余额与 A/B 两次真实点火仍待后续验证。

## 第三轮界面微调（2026-09-17）

触发依据：用户在第二轮真实界面检查后确认功能基本可用，同时指出详情页仍偏宽、周期块过密、Command Code 右侧信息重复，以及 DeepSeek 菜单栏和详情卡视觉层级不足。

### 修改内容

| 项 | 修订结果 |
| --- | --- |
| 详情页宽度 | 从 520 pt 收窄到 440 pt，内容宽度从 496 pt 收窄到 416 pt；进度条承担主要压缩 |
| ChatGPT 分组 | 卡片高度改为 129 pt，5 小时与周额度窗口块之间使用 4 pt 间距 |
| Command Code 分组 | 卡片高度改为 162 pt，5 小时、周额度、本月之间使用 4 pt 间距 |
| Command Code 额度文字 | 改为 `$余额 / $总计`；移除“剩余”和百分比；缺失字段使用 `—`，不显示 used 值冒充余额 |
| Command Code 时间文字 | 5 小时和周只显示绝对重置日期时间；月度保留“剩余 N 天 · 日期” |
| DeepSeek 菜单栏 | 移除汉字“余额”；完整模式 `DS CNY 123.45` 使用 13 pt medium / 7 pt 词间距，紧凑模式使用 12 pt medium / 4 pt 词间距 |
| DeepSeek 详情卡 | 改为 `416 × 48 pt` 单行，Logo、wordmark、连接状态、可点击服务状态和余额同行；余额采用 `110.00 CNY` 行内格式 |
| 页面高度 | 四卡全开 `440 × 552`；仅 Command Code `440 × 498`；仅 DeepSeek `440 × 384`；两服务隐藏 `440 × 330` |

### 修改文件

- `Sources/UsageMonitorApp/Views/UsagePanelView.swift`
- `Sources/UsageMonitorApp/Views/CodexProfileCard.swift`
- `Sources/UsageMonitorApp/Views/MenuBarLabelView.swift`
- `Sources/UsageMonitorCore/Utilities/UsageFormatting.swift`
- `Sources/UsageMonitorCore/Utilities/MenuBarContent.swift`
- `Tests/UsageMonitorAppTests/DetailPanelLayoutTests.swift`
- `Tests/UsageMonitorAppTests/DetailEvidenceRenderTests.swift`
- `Tests/UsageMonitorAppTests/MenuBarLabelWiringTests.swift`
- `Tests/UsageMonitorAppTests/MenuBarEvidenceRenderTests.swift`
- `Tests/UsageMonitorAppTests/StatusItemWiringTests.swift`
- `Tests/UsageMonitorAppTests/StartupWindowTests.swift`
- `Tests/UsageMonitorCoreTests/MenuBarContentTests.swift`
- 当前版本规格、审核、验收与根目录版本说明

### 阶段验证

- 定向布局、菜单栏、状态项和脱敏渲染测试：Core 33 + App 66 = 99 项通过，0 失败。
- 脱敏渲染已生成 `01-detail-440x552-light.png`、`02-detail-440x552-dark-a-cached.png`、`03-detail-440x330-light.png`、`05-commandcode-cards-light.png`、`09-three-sources-light.png` 和深色对应图。
- 全量测试：Core 325 + App 100 = 425 项通过，0 失败。
- `./scripts/build.sh` 完成 Release 构建、staging 签名和固定运行路径安装；`CFBundleShortVersionString = 1.3.0`。
- 在可访问本机钥匙串信任链的完整环境中，`codesign --verify --strict --verbose=2 ~/Applications/Minget.app` 通过。受限沙箱内执行同一命令会因无法读取信任链返回 `CSSMERR_TP_NOT_TRUSTED`，不作为签名失败结论。
- `StartupWindowTests` 启动签名包验证冷启动无 layer-0 空窗口，退出后无自有子进程残留。
- 已目检浅色 440 pt 全卡片、Command Code 卡片和三来源菜单栏脱敏渲染：单行 DeepSeek 卡片、精简额度文字、绝对重置时间及菜单栏字号均符合当前规格。
- 用户于 2026-09-17 提供最终真实运行截图并确认详情页修订完成；公开副本保存为 `assets/screenshots/v1.3.0/detail-redacted.png`，其中邮箱、余额、额度、时间和统计数据均已替换为示例值。

## 第二轮修订（2026-09-17）

依据 `docs/versions/1.3.0/REVISION_SPEC.md`（本轮最高优先级）。触发原因：用户真实界面验收否决了首轮的启动空窗口与 720 pt 双列布局，独立审核另发现两处点火生命周期缺陷。

### 修订内容

| 项 | 首轮问题 | 修订 |
| --- | --- | --- |
| 启动窗口 | `Settings { EmptyView() }` 仍是真实 Scene，系统可在启动时打开，用户看到空「设置」窗口 | 删除 SwiftUI `App`/`Scene`，改为 `@main enum MingetMain` + `NSApplication.shared` + 手工 `AppDelegate` 并由 `withExtendedLifetime` 持有；该文件不再 `import SwiftUI` |
| 详情页布局 | 720 pt 双列，第二列右侧被屏幕裁掉 | 改为 520 pt 单列，一排一张卡片，顺序 A → B → DeepSeek → Command Code；新增纯几何模型 `DetailPageLayout`，视图与测试共用同一套 frame 计算 |
| 页面高度 | 720 × 570 / 326 两种 | 520 × 560 / 486 / 398 / 324 四种，由可见服务卡片决定 |
| ChatGPT 卡片 | 只有额度轨道与绝对重置时刻，丢失 1.2.1 的分段时间轨道 | 恢复双轨：额度剩余轨道（6 pt）+ 其正下方分段时间轨道（3 pt，5 段 / 7 段，蓝色）；未知或非法时间用灰色轨道 + 中央 `?`；已到期显示「等待刷新」。卡片 `496 × 126 pt` |
| Command Code | 额度轨道用 `used / limit` 从左向右增长，且没有时间轨道 | 改为 `remaining / limit`，紫色 5 pt 左对齐、越用越短；每行新增时间轨道（5 段 / 7 段 / 本月连续单条，system indigo）；右侧固定 `剩余 $X.XX / $Y.YY · Z%` |
| 月度进度 | 没有开始时间来源 | `ProviderUsage` 增加可选 `billingPeriodStart`；解析 `currentPeriodStart` 并要求开始早于结束；只有两端齐全才画进度，否则中性空轨道 |
| DeepSeek 卡片 | 4 行纵向余额 | 恢复 1.2.1 横向紧凑形态 `496 × 68 pt`，最多 3 个金额，超出时第三项为「另有 N 个币种」 |
| 弹层 | 720 pt 弹层右侧越界且无法移回 | `show` 前设置 hosting controller 与 popover 的 contentSize；以按钮 `midX` 处 2 pt 锚点显示；屏幕容纳不下整页时改走普通详情窗口；普通详情窗口以图标为水平中心并 clamp 到 visibleFrame |
| 点火退出 | `stop()` 只取消 Swift 任务，无法终止阻塞中的 `Process` | 新增 `ChatGPTFireService.stopAll()`，在 coordinator drain 之前 terminate、SIGKILL 兜底并回收 |
| 点火确认 | `fetchFiveHourReset` 把缓存 `.success` 也当作实时证据 | 只有 `result.isLive == true` 才返回新 `resetsAt`；缓存成功进入 5 秒后的第二次刷新；两次都缓存只能是「请求成功，窗口未变化」 |

### 修改文件（第二轮）

| 文件 | 修改内容 |
| --- | --- |
| `Sources/UsageMonitorApp/UsageMonitorApp.swift` | AppKit 入口 `MingetMain` 取代 SwiftUI `App`；不再声明任何 Scene |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 新增 `DetailPageLayout`；单列 520 布局；DeepSeek 卡片 496 × 68；Command Code 卡片 496 × 156 含剩余轨道与时间轨道；新增 `ProviderTrackBar` / `ProviderTimeBar`；`DeepSeekBalanceRows.strip` 取代原 4 行规则 |
| `Sources/UsageMonitorApp/Views/CodexProfileCard.swift` | 重写为 496 × 126，恢复额度轨道 + 分段时间轨道双轨与单行 Footer |
| `Sources/UsageMonitorApp/StatusItem/StatusItemController.swift` | 新增 `panelSize(for:)`、`centerAnchor(in:)`、`panelFits(size:visibleFrame:)`；`show` 前设尺寸；放不下降级；`DetailWindowController.present(centeredOn:)`；`PanelHostingController` 接收同一 `DetailPreferences` |
| `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift` | `stop()` 先 `fireService.stopAll()` 再 drain；`fetchFiveHourReset` 要求 `isLive` |
| `Sources/UsageMonitorCore/Services/ChatGPTFireService.swift` | 新增幂等 `stopAll(terminateGrace:)` |
| `Sources/UsageMonitorCore/Providers/ProviderModels.swift` | `ProviderUsage.billingPeriodStart`；`ProviderUsageWindow.effectiveRemaining` / `remainingFraction` |
| `Sources/UsageMonitorCore/Providers/CommandCodeProvider.swift` | 解析 `currentPeriodStart`，要求开始早于结束，否则视为不可用 |
| `Sources/UsageMonitorCore/Utilities/ProviderTimeProgress.swift` | 新增：provider 窗口时间进度（分段 / 连续 / 已到期 / 不可用）与固定时长文案 |
| `Sources/UsageMonitorCore/Utilities/UsageFormatting.swift` | 新增 `shortDate` / `shortDateTime` |
| `Tests/UsageMonitorAppTests/DetailPanelLayoutTests.swift` | 重写：520 单列几何、四种高度、卡片 frame 不重叠、无滚动容器、双轨道、Command Code 剩余方向与三种时间轨道、DeepSeek 3 槽规则、点火状态互不污染 |
| `Tests/UsageMonitorAppTests/DetailEvidenceRenderTests.swift` | 重写：520 × 560 浅/深、520 × 324、ChatGPT 未知与已到期、Command Code 剩余收缩与三种时间轨道 |
| `Tests/UsageMonitorAppTests/StartupWindowTests.swift` | 新增：启动签名包检查冷启动窗口与退出后子进程 |
| `Tests/UsageMonitorAppTests/FireLifecycleTests.swift` | 新增：缓存→重试→实时确认、`stop()` 终止运行中的点火子进程 |
| `Tests/UsageMonitorAppTests/StatusItemWiringTests.swift` | 新增：panel 尺寸、hosting 与 popover 尺寸一致、锚点、屏幕容纳降级、设置窗口单实例、详情窗口固定尺寸 |
| `Tests/UsageMonitorAppTests/ProductionWiringTests.swift` | 新增：入口为 AppKit 且无 Scene |
| `Tests/UsageMonitorCoreTests/CommandCodeProviderTests.swift` | 新增：`currentPeriodStart` 合法 / 缺失 / 倒序 / 等于结束 |
| `Tests/UsageMonitorCoreTests/ChatGPTFireServiceTests.swift` | 新增：`stopAll` 终止并回收两个子进程、幂等、不误杀无关 PID |

### 执行命令（第二轮）

| 命令 | 结果 |
| --- | --- |
| `swift build --scratch-path /tmp/minget-dev-scratch` | 源码编译通过 |
| `MINGET_TEST_SCRATCH=$(mktemp -d …); swift test --scratch-path "$MINGET_TEST_SCRATCH"` | Core 325 + App 99 = 424 项通过，0 失败 |
| `./scripts/build.sh` | Release 构建、staging 严格签名、固定运行路径严格签名通过；`CFBundleShortVersionString = 1.3.0` |
| `open -g ~/Applications/Minget.app` + `CGWindowListCopyWindowInfo` | 冷启动 layer-0 窗口数 `0` |
| 退出后 `pgrep` / `ps eww` 扫描 | 子进程分别运行在 `.codex-minget-a` / `.codex-minget-b`，退出后全部回收，全机无残留 |

### 真实证据（第二轮）

- **冷启动无空窗口**：启动签名包 12 秒后，该进程拥有的 layer-0 窗口数为 `0`。同一断言由 `StartupWindowTests` 自动执行并通过。
  - 反向验证：在用修订前代码的旧签名包上运行同一断言，报告 `unexpected window unnamed 900×450 at cold start`，说明该测试确实能捕获原缺陷，而不是恒真。
- **双 Profile 隔离**：两个兄弟 `codex app-server` 子进程，实测 `CODEX_HOME` 分别为 `~/.codex-minget-a` 与 `~/.codex-minget-b`。只读取子进程自身环境，未读取、列出或修改两个目录内容。
- **退出清理**：`pkill -TERM` 后应用退出，两个子进程均被回收；全机扫描无进程仍引用 `~/.codex-minget-*`。本轮未执行任何真实点火请求。
- **脱敏渲染**：`$TMPDIR/Minget-1.3.0-Evidence/` 下生成 `01-detail-520x560-light.png`、`02-detail-520x560-dark-a-cached.png`、`03-detail-520x324-light.png`、`04-chatgpt-card-states-light.png`、`05-commandcode-cards-light.png`、`11-popover-frame-evidence.txt`。

### 第二轮已知限制

- 渲染证据运行在 XCTest 宿主中，`Bundle.main` 指向测试进程而非 `Minget.app`，因此 Blossom、鲸鱼、`deepseek` wordmark、Command Code symbol 与版本号在证据图里回退为占位（SF Symbol / 宿主版本号）。几何、轨道、文案与数据均为真实渲染结果；签名包内品牌资源显示正常，`scripts/build.sh` 的资源清单未改动。
- 弹层的最终摆放由 AppKit 在 `show` 时完成。本实现保证「尺寸在 show 前已确定」与「整页放不下时不显示弹层」，真实几何位置仍以用户界面验收为准。
- 周额度时间文案按 `REVISION_SPEC.md` §7.3 的固定格式使用「小时+分」，因此一周窗口会显示形如「剩余 71小时59分 · 09-20 09:15」。这是规格要求的形式，未自行改成「天」。

---

## 首轮实现（2026-09-16）

以下为首轮记录，数字与结论均为当时的快照，不能作为当前完成结论。

当前状态：代码、自动测试、Release 构建与严格签名已完成；两个真实账号额度、真实 DeepSeek 菜单栏余额、真实点火和三次重启验收待用户执行。

## 开工基线

- 日期：2026-09-16
- HEAD：`938b7f3`
- Xcode：27.0，license 已接受
- Swift：6.4
- 直接 `swift test`：因 iCloud `.build/out` 的 File Provider 扩展属性导致测试包签名失败
- 仓库外 scratch path：310 项通过，0 项失败，其中 Core 271 项、App 39 项
- 基线命令：

```bash
MINGET_TEST_SCRATCH="$(mktemp -d /tmp/minget-swift-test.XXXXXX)"
swift test --scratch-path "$MINGET_TEST_SCRATCH"
```

## 受保护的既有工作区内容

以下内容不属于 1.3.0，不得覆盖、清理或误提交：

- `docs/versions/1.0.2/evidence/01-menubar-states-light.png`
- `docs/versions/1.0.2/evidence/02-menubar-states-dark.png`
- `.workbuddy/`
- 根目录的本机点火实施记录 `明明有数_Minget_双ChatGPT账号额度窗口自动点火_实施记录_2026-09-16.md`

> 2026-09-18 目录整理：该本机实施记录已脱敏迁移为 [FIRE_DESIGN_BACKGROUND.md](FIRE_DESIGN_BACKGROUND.md)，根目录原文件已删除；`.workbuddy/` 也已清理。本文其余内容保持当时的记录不变。

渲染测试默认输出到 `$TMPDIR/Minget-1.3.0-Evidence/`，禁止把历史 evidence 目录作为测试输出位置。

### 基线运行造成的实际影响

首次基线 `swift test` 运行时，当时尚未修改的 `MenuBarEvidenceRenderTests` 仍把全部 8 张
`docs/versions/1.0.2/evidence/` 图写入该历史目录，因此把这 8 个文件重绘了一遍。

处置：

- `03`–`08` 六个在开工时是干净的文件已用 `git checkout HEAD --` 还原，工作区不再有它们的改动。
- `01`、`02` 在开工前本来就是用户未提交的改动，无法还原其原始字节。当前内容是同一套 1.0.2
  fixture 在当前机器上重绘的结果；它们仍然保持「已修改、未提交」状态，未被纳入本轮任何提交
  （本轮没有提交）。
- 新的渲染测试只写 `$TMPDIR/Minget-1.3.0-Evidence/`，同类覆盖不会再次发生。

## 修改文件

### 新增（Core）

| 文件 | 修改内容 | 对应任务 |
| --- | --- | --- |
| `Sources/UsageMonitorCore/Models/ChatGPTAccountProfile.swift` | 两个固定只读 Profile（ID、显示名、菜单栏短标签、相对 `CODEX_HOME`），路径按当前用户主目录解析 | 1.1 |
| `Sources/UsageMonitorCore/Services/CodexProfileRuntime.swift` | 单 Profile 运行态：service、display、connection、account、fetch/fire 状态，锁保护并输出值快照 | 1.1 |
| `Sources/UsageMonitorCore/Services/CodexProfilesCoordinator.swift` | 拥有全部 Profile 运行时，逐 Profile 刷新与并发停止 | 1.1、2 |
| `Sources/UsageMonitorCore/Models/ChatGPTFireResult.swift` | 卡片可见的 7 项固定结果与进程级 6 项结果 | 5.1 |
| `Sources/UsageMonitorCore/Services/ChatGPTFireService.swift` | 直启官方 Codex CLI，固定参数，drain 后丢弃输出，120 秒超时与 3 秒终止宽限 | 5.1 |

### 新增（App）

| 文件 | 修改内容 | 对应任务 |
| --- | --- | --- |
| `Sources/UsageMonitorApp/ViewModels/MenuBarPreferences.swift` | 可 Codable 的稳定菜单栏来源（Profile ID 或 DeepSeek）与 DeepSeek 币种偏好 | 3.1 |
| `Sources/UsageMonitorApp/ViewModels/CodexProfileViewState.swift` | 单张 ChatGPT 卡片的纯值状态 | 2、4 |
| `Sources/UsageMonitorApp/Views/CodexProfileCard.swift` | 338 × 246 可复用账号卡片，含固定点火确认文案与结果行 | 4 |

### 修改（Core）

| 文件 | 修改内容 | 对应任务 |
| --- | --- | --- |
| `Sources/UsageMonitorCore/Services/UsageService.swift` | 新增 `profileID`；`childEnvironment(base:codexHome:)` 复制环境并覆盖 `CODEX_HOME`；缓存读写与 last-known account 按 Profile 归属 | 1.2、1.3 |
| `Sources/UsageMonitorCore/Services/UsageCache.swift` | 新增 v3 `profileID + accountID` 命名空间与 Per-Profile last-known account；严格实现 v2→v3 迁移 | 1.3 |
| `Sources/UsageMonitorCore/Services/JSONRPCClient.swift` | 暴露 `childEnvironment` 只读访问器，供隔离测试核验两个子进程的 `CODEX_HOME` | 1.2 |
| `Sources/UsageMonitorCore/Utilities/MenuBarContent.swift` | 构建器改为接收已解析来源；新增 ChatGPT A/B、DeepSeek 与 DeepSeek 多币种选择器 | 3.2 |
| `Sources/UsageMonitorCore/Utilities/UsageFormatting.swift` | 新增带账号短标签的完整/紧凑格式、DeepSeek 金额与余额文案、固定两位小数 | 3.2 |
| `Sources/UsageMonitorCore/Utilities/UsageDisplay.swift` | 声明 `Sendable`，供运行态值快照跨越线程 | 1.1 |

### 修改（App）

| 文件 | 修改内容 | 对应任务 |
| --- | --- | --- |
| `Sources/UsageMonitorApp/UsageMonitorApp.swift` | `AppContainer` 由单一 `codexService` 改为 `CodexProfilesCoordinator`；退出清理改为停止全部 Profile | 2 |
| `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift` | 发布 `[CodexProfileViewState]`；一轮内并行刷新两个 Profile；菜单栏来源解析与偏好变化重发布；点火编排与结果判定 | 2、3.2、5.2 |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 720 × 570 / 720 × 326 双列固定布局；DeepSeek 最多 4 行余额规则；Command Code 固定三行额度与三行摘要 | 4 |
| `Sources/UsageMonitorApp/Views/MenuBarLabelView.swift` | 三种来源共用同一内容类型；无时间条时居中且不预留空行 | 3.2 |
| `Sources/UsageMonitorApp/Views/MingetSettingsView.swift` | 520 × 600 固定页；菜单栏显示纵向 radio group；DeepSeek 币种 Picker；服务组四行与单开 accordion | 3.3 |
| `Sources/UsageMonitorApp/StatusItem/StatusItemController.swift` | 详情窗口 720 宽并按偏好立即 `setContentSize`；设置窗口 520 × 600 | 3.3、4 |

### 测试与文档

| 文件 | 修改内容 | 对应任务 |
| --- | --- | --- |
| `Tests/UsageMonitorCoreTests/CodexProfilesCoordinatorTests.swift` | 新增：真实双子进程 `CODEX_HOME` 隔离、并行刷新、独立失败与失败预算、并发停止 | 6.1 |
| `Tests/UsageMonitorCoreTests/UsageCacheTests.swift` | 新增：Profile + account 双重隔离、v2→v3 迁移四分支、外部换号归属替换 | 6.1 |
| `Tests/UsageMonitorCoreTests/ChatGPTFireServiceTests.swift` | 新增：固定参数、CLI 缺失、成功、非零退出、超时终止、重复点击、A/B 并行（全部 fake executable） | 6.1 |
| `Tests/UsageMonitorCoreTests/JSONRPCTransportTests.swift` | 新增：子进程实际观测到的 `CODEX_HOME` 与两个传输的不同取值 | 6.1 |
| `Tests/UsageMonitorCoreTests/MenuBarContentTests.swift` | 改为来源驱动；覆盖三种来源、DeepSeek 金额语义、多币种优先级、缓存与错误状态 | 6.1 |
| `Tests/UsageMonitorAppTests/DetailPanelLayoutTests.swift` | 固定尺寸常量与合成尺寸校验；两种页面均无滚动容器；两卡片与两点火按钮状态互不污染；DeepSeek 行数与 Command Code 固定行 | 6.2 |
| `Tests/UsageMonitorAppTests/MenuBarPreferencesTests.swift` | 新增：选择持久化、升级默认账号 A、损坏回退、DeepSeek 币种、来源切换重测宽 | 6.2 |
| `Tests/UsageMonitorAppTests/ProductionWiringTests.swift` | 新增：生产 composition 创建两个 Profile runtime 与两个不同 `CODEX_HOME` | 6.2 |
| `Tests/UsageMonitorAppTests/MenuBarLabelWiringTests.swift` | 三种来源在两种模式下的实测宽度；DeepSeek 无时间条；金额变化改变签名 | 6.2 |
| `Tests/UsageMonitorAppTests/MenuBarEvidenceRenderTests.swift` | 输出改到 `$TMPDIR/Minget-1.3.0-Evidence/`；新增三来源完整/紧凑渲染 | 6.2 |
| `Tests/UsageMonitorAppTests/DetailEvidenceRenderTests.swift` | 新增：720 × 570 浅/深、720 × 326、服务卡片、点火状态渲染 | 6.2 |
| `VERSION`、`README.md`、`CHANGELOG.md`、`ROADMAP.md`、`PROVIDER_ENDPOINTS.md`、`docs/ARCHITECTURE.md` | 版本与资料同步 | 8 |

## 执行命令

| 时间 | 命令 | 结果 |
| --- | --- | --- |
| 2026-09-16 | `MINGET_TEST_SCRATCH="$(mktemp -d /tmp/minget-swift-test.XXXXXX)"; swift test --scratch-path "$MINGET_TEST_SCRATCH"` | 基线：Core 271 + App 39 = 310 项通过，0 项失败 |
| 2026-09-16 | `swift build --scratch-path /tmp/minget-dev-scratch --target UsageMonitorCore` | Core 编译通过（仅既有 SecKeychain 弃用警告） |
| 2026-09-16 | `swift build --scratch-path /tmp/minget-dev-scratch --build-tests` | 全部目标与测试目标编译通过 |
| 2026-09-16 | `swift test --scratch-path "$MINGET_TEST_SCRATCH"` | Core 317 项、App 67 项，合计 384 项通过，0 项失败 |
| 2026-09-16 | `./scripts/build.sh` | Release 构建、staging 严格签名、固定运行路径严格签名全部通过 |
| 2026-09-16 | `defaults read ~/Applications/Minget.app/Contents/Info.plist CFBundleShortVersionString` | `1.3.0` |
| 2026-09-16 | `open -g ~/Applications/Minget.app`；`ps -o args= -p <child>` 与 `ps eww -p <child> \| grep -o 'CODEX_HOME=[^ ]*'` | 两个兄弟 `codex app-server` 子进程，分别运行在 `~/.codex-minget-a` 与 `~/.codex-minget-b` |
| 2026-09-16 | 三次 `open -g` / `pkill -TERM -f Minget.app/Contents/MacOS/UsageMonitor` 循环 | 每次两个子进程、退出后全部回收；结束后无遗留自有 app-server |
| 2026-09-16 | `git checkout HEAD -- docs/versions/1.0.2/evidence/0{3,4,5,6,7,8}-*.png` | 还原基线运行误改的 6 个历史证据图 |

## 自动化测试

| 测试层级 | 通过 | 失败 | 跳过 | 证据 |
| --- | ---: | ---: | ---: | --- |
| Core | 317 | 0 | 0 | `swift test --scratch-path <仓库外临时目录>` |
| App | 67 | 0 | 0 | 同上；CI 环境会跳过需要 WindowServer 的渲染与状态项用例 |
| 合计 | 384 | 0 | 0 | |

新增覆盖要点：

- 两个真实子进程分别报告 `~/.codex-minget-a` 与 `~/.codex-minget-b`，互不相同。
- A 失败时 B 仍为 live；A 的失败预算不冻结 B。
- Profile + account 双重缓存隔离；v2 缓存「升级后不展示」「同 ID 迁移」「不同 ID 删除」「B 永不接收」。
- 外部换号后，同一 Profile 的当前账号归属被替换，旧账号缓存不再作为当前数据。
- 点火：参数逐项固定、CLI 缺失、成功、非零退出、超时后只杀本次 PID、同 Profile 重复点击立即 `.alreadyRunning`、A/B 并行。
- 菜单栏：三来源完整/紧凑固定文案、DeepSeek 币种优先级与「无余额不显示 0」。
- 详情页：视图树不含 `ScrollView`/`NSTableView`/`NSOutlineView`，720 × 570 与 720 × 326 两种尺寸均可渲染。

## 构建与签名

- Release 构建：`./scripts/build.sh` 成功
- staging 严格签名：通过（bundle 与两个嵌套可执行文件分别校验）
- 固定运行路径严格签名：`~/Applications/Minget.app` 通过
- App 版本：`CFBundleShortVersionString = 1.3.0`
- 归档副本：`dist/Minget.app`（位于 iCloud 路径，按脚本既有约定记录差异）

## 真实验证

以下均为本机只读检查与启动/退出检查。除用户点击卡片按钮外，应用不会发出模型请求；本轮未点击任何点火按钮，未消耗任何重置额度。

### 隔离与子进程清理（已用签名包实测）

对签名后的 `~/Applications/Minget.app` 做了 1 次观察启动和 3 次完整的启动/退出循环：

- 每次启动都恰好出现两个 `codex app-server` 子进程，且两者互为兄弟进程（同一父进程）。
- 两个子进程实测到的 `CODEX_HOME` 分别为 `~/.codex-minget-a` 与 `~/.codex-minget-b`，方向在三次循环中交替出现，说明两个 Profile 各自启动自己的子进程，而不是复用同一个。
- 每次退出后两个子进程都被回收；三次循环后没有属于本应用的遗留 `codex app-server`，也没有任何进程仍在引用 `~/.codex-minget-*`。
- 观察方式为 `ps` 读取子进程自身的环境与命令行；未读取、未列出、未修改两个 `CODEX_HOME` 目录中的任何文件。

其余本机只读检查：

- `~/.codex-minget-a` 与 `~/.codex-minget-b` 两个目录均存在。
- `~/Library/LaunchAgents/com.minget.chatgpt-fire.plist` 与 `~/.local/bin/minget-fire` 的修改时间仍为 2026-09-16 20:03 / 20:07，未被本轮触碰。

真实验收进展：

- 已完成：ChatGPT A/B 账号、套餐、额度与两张真实卡片的内容核对；最终截图未写入真实邮箱和数值。
- 已完成：浅色弹层、440 pt 单列详情页、DeepSeek 单行卡片与 Command Code 三周期卡片体验确认。
- 待执行：菜单栏 A/B/DeepSeek 真实切换与重置时间对应。
- 待执行：DeepSeek 真实菜单栏余额、多币种与失败不显示零。
- 待执行：A、B 两次真实点火与新窗口确认判定；该操作会消耗少量额度。
- 待执行：机器重启后的表现。

真实邮箱、余额、API Key、OAuth token、原始响应、Codex CLI session id 和点火 raw output 禁止写入本文。

## 已知问题

- 基线 `swift test` 运行触发了当时未修改的 1.0.2 渲染测试，重绘了 `docs/versions/1.0.2/evidence/` 全部 8 张图。其中 6 张已还原；`01`、`02` 在开工前即为用户未提交的改动，其原始字节无法恢复，当前为同 fixture 的当前机器重绘结果。详见上文「基线运行造成的实际影响」。
- 裸 `swift test` 在本仓库 iCloud 路径下仍会因 File Provider 扩展属性导致测试包签名失败；这是环境问题，不是代码缺陷，所有基线、迭代与最终测试均使用仓库外 `--scratch-path`。
- 详情页与设置页依赖 SwiftUI 的固定 `.frame`；`NSHostingView` 的 `fittingSize` 用于证据渲染，最终像素表现仍以用户真实界面确认为准。

## 未完成事项

- 菜单栏三来源真实切换、DeepSeek 真实菜单栏余额、A/B 两次真实点火和机器重启复验。

## 发布结果

- 发布提交：`827ca8b`（`Release Minget 1.3.0`），已推送到 GitHub `main`。
- 注释标签：`v1.3.0`，远端 peeled ref 指向 `827ca8b`。
- GitHub Release：[Minget v1.3.0](https://github.com/ym911x/Minget/releases/tag/v1.3.0)，正式发布，非草稿、非预发布。
- GitHub Actions：发布提交对应 CI #17 完成且结论为 `success`。
- 公开截图链接返回 HTTP 200；下载副本与仓库中脱敏 PNG 的 SHA-256 均为 `4bdf65c4b1f94f4ccb9c8bad350a6a71b83f8a1cc72540c18ab53c199af4f945`。

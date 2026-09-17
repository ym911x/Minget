# 1.3.0 回归修订规格

日期：2026-09-17
状态：已完成（第二轮历史规格；当前以 `UI_SPEC.md` 为准）
优先级：阻断 1.3.0 用户验收

本文记录第二轮回归修订。2026-09-17 用户实测后又确认第三轮界面微调，最终尺寸、间距和展示文案以 `UI_SPEC.md` 当前内容为准；本文件中保留的 520 pt 第二轮过程记录不再覆盖该最新规格。

第三轮固定结论：详情页宽 `440 pt`；ChatGPT 卡片 `416 × 129 pt`；DeepSeek 单行卡片 `416 × 48 pt`；Command Code 卡片 `416 × 162 pt`；四种页面高度为 `552 / 498 / 384 / 330 pt`。ChatGPT 和 Command Code 的相邻周期块间距为 `4 pt`。Command Code 额度文字只显示 `$余额 / $总计`，5 小时和周只显示绝对重置日期时间。DeepSeek 菜单栏不显示汉字“余额”，完整和紧凑均使用 `DS CNY 123.45`，通过字体与词间距形成宽度差。

## 1. 结论

当前 1.3.0 不通过用户界面验收，必须完成以下修订后再验收：

1. 删除启动时出现的空“设置”窗口，应用冷启动后只出现菜单栏图标；只有用户点“设置”时才创建设置窗口。
2. 详情页从 `720 pt` 双列恢复为 `520 pt` 单列，一排只放一张卡片，固定顺序为 ChatGPT A、ChatGPT B、DeepSeek、Command Code。
3. 详情页继续严格禁止滚动容器和滚动条。四张卡片全部显示时固定为 `520 × 560 pt`，在一页内看完。
4. 两张 ChatGPT 卡片恢复 1.2.1 的信息层级和视觉语法：额度剩余轨道下方必须紧跟重置时间轨道；5 小时为 5 段，周额度为 7 段。
5. Command Code 的额度轨道改为显示“剩余”，亮色区域随消耗从右端向左收缩；每个额度窗口增加独立的重置时间轨道和剩余时间文字。
6. 弹层以菜单栏图标水平中点为锚点。页面必须完整落在当前屏幕可见区域内，不能再出现右侧超出屏幕且无法移回的状态。
7. 同时修复独立审核发现的两个点火生命周期问题：退出时终止并回收仍在运行的点火子进程；缓存刷新不得被当作点火后的实时窗口确认。

本轮不改变双账号模型、菜单栏三来源选择、DeepSeek/Command Code 凭证边界、点火 CLI 固定参数和既有自动点火 LaunchAgent。

## 2. 验收基线和实际证据

### 2.1 当前 1.3.0 截图

用户提供的 1.3.0 截图确认了以下事实：

- 详情页采用 2 × 2 卡片网格，第二列右侧被屏幕裁掉。
- 两张 ChatGPT 卡片只有额度轨道和绝对重置时刻，没有 1.2.1 的蓝色分段重置时间轨道。
- ChatGPT 的套餐、账号和额度信息层级与 1.2.1 不一致。
- Command Code 当前紫色轨道按 `used / limit` 从左向右增长，和用户需要的“剩余量从右端向左收缩”相反。

该截图包含真实邮箱和真实余额，只能作为本地验收证据，不得复制进仓库、测试快照、公开文档或发布素材。

### 2.2 唯一视觉基线

OpenAI/ChatGPT 卡片以 `assets/screenshots/v1.2.1/detail-redacted.png` 为唯一视觉基线，必须保留以下视觉语法：

- Blossom、套餐和账号位于卡片顶部。
- 5 小时和周额度分别有一条主额度轨道。
- 每条主额度轨道正下方各有一条更细的重置时间轨道。
- 5 小时重置时间轨道为 5 段，周额度为 7 段。
- 主额度右侧显示“剩余”；时间轨道右侧显示重置时刻。
- reset credits 位于卡片底部。
- 背景、圆角、边框、字体层级、绿色额度/蓝色时间配色沿用 1.2.1。

允许为容纳双账号缩小字号、间距和图标尺寸，不允许删除上述任何信息或轨道。

## 3. 启动空窗口

### 3.1 原因

`Sources/UsageMonitorApp/UsageMonitorApp.swift` 当前使用：

```swift
@main
struct UsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
```

这仍然注册了一个真实的 SwiftUI Settings Scene。系统恢复窗口或以应用方式启动时可以把这个空 Scene 打开，因此用户看到一个没有内容的设置窗口。

### 3.2 固定实现

删除 SwiftUI `App` 和 `Settings { EmptyView() }` 入口，改成显式 AppKit 启动：

```swift
@main
enum MingetMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
```

约束：

- `AppDelegate.applicationDidFinishLaunching` 继续设置 `.accessory`、启动 model 和安装 `NSStatusItem`。
- 不再声明任何 SwiftUI `Scene`，也不创建占位窗口。
- 设置窗口仍只由 `StatusItemController.showSettingsWindow()` 创建。
- 不使用启动后立刻 `close()` 的闪烁式补丁。
- 如果菜单栏图标被刘海或空间隐藏，既有“打开普通详情窗口”降级仍保留；该窗口有真实内容，不属于本缺陷。

## 4. 详情页固定布局

### 4.1 页面尺寸

| 可见服务卡片 | 页面尺寸 |
| --- | --- |
| DeepSeek + Command Code | `520 × 560 pt` |
| 仅 Command Code | `520 × 486 pt` |
| 仅 DeepSeek | `520 × 398 pt` |
| 两者都隐藏 | `520 × 324 pt` |

公共尺寸：

- 外边距：`12 pt`
- 内容宽度：`496 pt`
- Header：`496 × 36 pt`
- 所有纵向间距：`6 pt`
- 卡片圆角：`14 pt`
- 卡片边框：`1 pt`、`Color.primary.opacity(0.05)`
- 卡片背景：沿用 1.2.1 `controlBackgroundColor.opacity(0.82)`
- ChatGPT A 卡片：`496 × 126 pt`
- ChatGPT B 卡片：`496 × 126 pt`
- DeepSeek 卡片：`496 × 68 pt`
- Command Code 卡片：`496 × 156 pt`

固定结构：

```text
┌──────────────────── 520 pt ────────────────────┐
│ Header                                         │ 36
│ ChatGPT A                                      │ 126
│ ChatGPT B                                      │ 126
│ DeepSeek                                       │ 68
│ Command Code                                   │ 156
└──────────────────── 560 pt ────────────────────┘
```

每一排只有一张卡片。禁止 `LazyVGrid`、双列 `HStack`、根据宽度自动变成两列以及横向滚动。

### 4.2 无滚动规则

详情页和普通详情窗口的视图树都不得出现：

- `ScrollView`
- `List`
- `NSScrollView`
- `NSTableView`
- `NSOutlineView`
- 隐藏滚动条但仍可滚动的自定义容器

动态文字统一 `lineLimit(1)`；邮箱使用中间省略，其他动态文字使用尾部省略。缺失值显示 `—`，不通过增加页面高度解决。

## 5. ChatGPT 卡片

### 5.1 固定结构

每张卡片内边距 `10 pt`，内容区 `476 × 106 pt`。从上到下固定为：

1. Header 行，`26 pt`。
2. 账号行，`13 pt`。
3. 5 小时窗口块，`25 pt`。
4. 周额度窗口块，`25 pt`。
5. Footer 行，`13 pt`。

组间只用 `1 pt`，不得插入说明段落。

### 5.2 Header 和账号行

- Blossom 画布：`26 × 26 pt`。
- Profile 名称：`13 pt semibold`，A 为“Codex 账号”，B 为“Hermes / OpenClaw 账号”。
- 套餐：Profile 名称下方 `9 pt secondary`，显示服务原值。
- 点火按钮：右侧 `76 × 22 pt`，标题“5 小时点火”；运行时为“点火中…”，禁用并显示小型进度图标。
- 账号行左侧：连接状态，`9 pt`；实时绿色、缓存橙色、其他 secondary。
- 账号行右侧：真实账号邮箱，`9 pt secondary`、中间省略、单行、可复制。不可用时显示“账号暂不可用”。

### 5.3 额度和重置时间

每个窗口块必须有两行：

```text
5 小时    [额度剩余轨道]          剩余 66%
重置时间  [5 段时间剩余轨道]      09-17 05:35
```

```text
周额度    [额度剩余轨道]          剩余 17%
重置时间  [7 段时间剩余轨道]      09-19 16:15
```

尺寸与行为：

- 左标签宽：`46 pt`。
- 右值宽：`92 pt`。
- 主额度轨道高：`6 pt`。
- 重置时间轨道高：`3 pt`，段间距 `2 pt`。
- 主额度轨道表示 `remainingPercent / 100`，亮色从左侧开始，额度消耗时右端向左收缩。
- 主额度颜色沿用 1.2.1：正常绿色、警告橙色、临界红色。
- 重置时间轨道固定蓝色；实时 opacity `0.85`，缓存 `0.45`。
- 时间轨道表示“距离重置还剩多少时间”，5 小时用 5 个等宽段，周额度用 7 个等宽段。
- 未知或非法重置时间使用灰色轨道和中央 `?`，不得绘制成 0 或已到期。
- 已到重置时间但还未取得服务端新窗口时，右侧显示“等待刷新”。

`CodexProfileCard` 应复用或抽取 1.2.1 的 `DetailQuotaBar` / `DetailResetBar` 算法，不得把菜单栏 `ResetTimeBarsView` 直接塞入卡片后靠缩放凑尺寸。

### 5.4 Footer

- 左侧显示 `UsageFormatting.rateLimitResetText`，`9 pt secondary`。
- 右侧显示点火结果，`9 pt`，固定文案沿用当前 1.3.0；成功绿色，未变化 secondary，失败/超时橙色。
- 两侧各单行，空间不足时左侧先尾部省略，点火结果完整优先。
- 初始无点火结果时右侧为空，但保留布局，不产生高度跳动。

## 6. DeepSeek 卡片

保持 1.2.1 的紧凑横向风格：

- 左侧鲸鱼 Logo + `deepseek` wordmark。
- 右侧显示主要币种和余额。
- 底部同一行显示连接状态、官方服务状态和“状态页”。
- 内边距 `10 pt`，动态文字全部单行。
- 多币种时按既有币种顺序横向显示，最多 3 个金额；超过 3 个时第三项改为“另有 N 个币种”。不得换算、合计或伪造 0。
- 详情隐藏偏好继续生效；DeepSeek 被选为菜单栏来源时仍可隐藏详情卡片，两者互不绑定。

## 7. Command Code 卡片

### 7.1 固定结构

卡片内边距 `10 pt`，内容区 `476 × 136 pt`：

1. Header，`24 pt`：Logo、名称、套餐/连接状态。
2. 5 小时窗口块，`25 pt`。
3. 周额度窗口块，`25 pt`。
4. 本月窗口块，`25 pt`。
5. 摘要区，3 行，每行 `11 pt`。

窗口块和摘要不得换行撑高。三行摘要保持当前固定顺序：周期/Token/请求、输入/输出/成功/失败、成功率/成本。

### 7.2 额度轨道含义和方向

当前 `used / limit` 必须改为 `remaining / limit`。额度轨道固定使用 Command Code 品牌紫色：

- 轨道高：`5 pt`。
- 亮色区域左对齐。
- 初始剩余额度越多，亮色越长。
- 使用量增加时，亮色的右端向左收缩。
- 禁止继续显示“已用比例从左向右增长”的效果。
- 右侧文字固定优先显示：`剩余 $X.XX / $Y.YY · Z%`。
- `remaining` 或 `limit` 缺失时显示服务端实际存在的金额；不能计算百分比时不显示百分比，不能用 0 代替。

### 7.3 重置时间轨道

每个额度行下方增加一条重置时间行：

| 窗口 | 轨道 | 数据来源 |
| --- | --- | --- |
| 5 小时 | `5` 段，`3 pt` 高 | `ProviderUsageWindow.resetsAt`，周期固定 5 小时 |
| 周额度 | `7` 段，`3 pt` 高 | `ProviderUsageWindow.resetsAt`，周期固定 7 天 |
| 本月 | 连续单条，无刻度，`3 pt` 高 | 计费周期开始和结束时间 |

颜色固定为 system indigo，与紫色额度轨道区分。时间亮色同样表示“剩余时间”，随时间流逝从右端向左收缩。

右侧时间文案：

- 5 小时和周：`剩余 2小时13分 · 09-17 05:35`；空间不足时先省略绝对时刻，保留相对剩余时间。
- 本月：`剩余 12天 · 09-30`。
- 已到期：`等待刷新`。
- 没有 `resetsAt`：`时间未知`。

月度时间进度不能猜测：

- `ProviderUsage` 增加可选 `billingPeriodStart`，`CommandCodeProvider` 只在响应真实包含 `currentPeriodStart` 时解析。
- 结束时间继续使用 `currentPeriodEnd`。
- 只有开始和结束都存在且顺序合法时才绘制月度进度。
- 只有结束时间时显示空的中性轨道和剩余/到期文字；不得假设 30 天或自然月起点。

### 7.4 缺失和缓存状态

- 缺少任一窗口时保留该窗口块并显示 `—` 和灰色空轨道。
- 缓存数据保留上次真实数字但整体降低轨道 opacity，并明确显示“缓存数据”。
- Command Code 字段语义仍按 `PROVIDER_ENDPOINTS.md` 的 C 级证据处理；本轮只改展示，不把尚未同刻对账的字段升级为已确认。

## 8. 弹层锚点和屏幕边界

### 8.1 弹层

保留当前 `2 pt` 宽的中心锚点算法：

```swift
NSRect(x: button.bounds.midX - 1,
       y: button.bounds.minY,
       width: 2,
       height: button.bounds.height)
```

在 `popover.show` 前完成以下步骤：

1. 创建 `UsagePanelView`。
2. 把 hosting controller 的 `preferredContentSize` 设置为当前页面的 `520 × preferredHeight`。
3. 把 `popover.contentSize` 设置成相同值。
4. 再以中心锚点显示。

页面变窄后，图标中心两侧各约 `260 pt`，不再使用 720 pt 宽页面挤出屏幕。

### 8.2 边界优先级

1. 当前屏幕能容纳时，弹层和图标使用同一水平中心线。
2. 图标靠近屏幕边缘、无法严格居中时，优先保证弹层完整位于 `screen.visibleFrame.insetBy(dx: 8, dy: 8)` 内，由 AppKit 调整箭头位置。
3. 如果当前屏幕连 `520 × preferredHeight` 都无法容纳，不显示被裁掉的 popover，改用普通详情窗口。
4. 普通详情窗口首次打开时，以菜单栏图标的屏幕坐标为水平中心并把最终 frame clamp 到 visibleFrame；没有可用图标窗口时才 `window.center()`。

不得直接移动已经显示的 `NSPopover` 私有窗口，也不得使用私有 API。

## 9. 点火生命周期修订

### 9.1 退出时停止点火子进程

当前 `UsageViewModel.stop()` 只取消 Swift `Task`，`ChatGPTFireService.fire()` 是同步阻塞调用，取消 Task 不会终止 `Process`。必须增加：

- `ChatGPTFireService.stopAll()`，在锁内复制所有 `activeProcesses` 后解锁，再逐个 terminate。
- 每个进程等待不超过 `3 秒`；仍运行时只对自己的 PID 发送 `SIGKILL`；随后 `waitUntilExit()` 回收。
- `stopAll()` 幂等，可与自然退出、超时和重复 stop 并发。
- `UsageViewModel.stop()` 必须先取消任务、调用 `fireService.stopAll()`，再等待 coordinator 的两个 app-server drain，最后才调用 completion。
- `applicationWillTerminate` 保留最后兜底，但正常退出的完成信号必须覆盖 app-server 和点火进程两类子进程。

### 9.2 点火后的实时刷新证据

`fetchFiveHourReset` 当前只检查 `.success`，但 `.success` 可能携带缓存 `FetchResult.isLive == false`。固定规则：

- 只有 `case .success(let result)` 且 `result.isLive == true` 才可返回新 `resetsAt`。
- 缓存成功等同于“没有取得实时确认”，必须进入 5 秒后的第二次刷新。
- 第二次仍非实时或没有前后两个 `resetsAt` 时，结果只能是“请求成功，窗口未变化”。
- 只有同一 Profile 的实时新值比点火前至少晚 `60 秒`，才显示“新窗口已确认”。

## 10. 必改文件

实现至少修改：

- `Sources/UsageMonitorApp/UsageMonitorApp.swift`
- `Sources/UsageMonitorApp/StatusItem/StatusItemController.swift`
- `Sources/UsageMonitorApp/Views/UsagePanelView.swift`
- `Sources/UsageMonitorApp/Views/CodexProfileCard.swift`
- `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`
- `Sources/UsageMonitorCore/Providers/ProviderModels.swift`
- `Sources/UsageMonitorCore/Providers/CommandCodeProvider.swift`
- `Sources/UsageMonitorCore/Services/ChatGPTFireService.swift`
- `Tests/UsageMonitorAppTests/DetailPanelLayoutTests.swift`
- `Tests/UsageMonitorAppTests/DetailEvidenceRenderTests.swift`
- `Tests/UsageMonitorAppTests/StatusItemWiringTests.swift`
- `Tests/UsageMonitorAppTests/ProductionWiringTests.swift`
- `Tests/UsageMonitorCoreTests/CommandCodeProviderTests.swift`
- `Tests/UsageMonitorCoreTests/ChatGPTFireServiceTests.swift`

实现完成后同步：

- `REQUIREMENTS.md`
- `UI_SPEC.md`
- `IMPLEMENTATION_TASKS.md`
- `IMPLEMENTATION_REPORT.md`
- `REVIEW.md`
- `ACCEPTANCE.md`
- 根目录 `README.md`、`ROADMAP.md`、`CHANGELOG.md` 中仍描述 720 pt 双列或旧测试数的部分

## 11. 自动测试

至少新增或改写以下断言：

### 11.1 启动和窗口

- 生产入口不再声明 `Settings` Scene。
- 冷启动 2 秒内 `NSApp.windows` 不存在可见空窗口。
- 用户点设置后只出现一个 `520 × 600 pt` 的真实设置窗口。
- 连续打开、关闭、重开不会增加窗口实例。

### 11.2 布局

- `UsagePanelView.pageWidth == 520`。
- 四卡全开高度为 `560`；仅 Command Code `486`；仅 DeepSeek `398`；两者隐藏 `324`。
- 两个 ChatGPT、DeepSeek、Command Code 的 `minX` 相同且宽度均为 `496`。
- 四张卡片的 `minY` 严格递增，任意两张卡片的垂直 frame 不相交。
- 视图树无任何滚动容器。
- 所有固定页面状态无裁切、无横向溢出。

### 11.3 ChatGPT

- 每张卡片同时存在两条额度轨道和两条重置时间轨道。
- 5 小时时间轨道为 5 段，周为 7 段。
- 两张卡片各自读取自己的 snapshot，不共享额度、邮箱、reset credits 或点火结果。
- 未知、已到期、缓存状态分别渲染成规定状态。

### 11.4 Command Code

- `remaining = 3`、`limit = 4` 时轨道 fraction 为 `0.75`，不得为 `0.25`。
- 剩余从 3 降到 1 时亮色右端向左移动。
- 5 小时为 5 段、周为 7 段、本月为连续单条。
- 本月只有结束时间而无开始时间时，不计算虚构 fraction。
- `currentPeriodStart` / `currentPeriodEnd` 合法、缺失、倒序各有 parser 和 presentation 测试。
- 金额缺失时显示 `—`，不能显示 `$0.00`。

### 11.5 Popover

- hosting controller 和 popover 在 `show` 前已得到相同 preferredContentSize。
- 中心锚点始终是状态按钮 `midX`。
- 常见屏幕 frame 下弹层完整包含于 visibleFrame；不能容纳时走普通详情窗口。

### 11.6 点火

- stop 期间正在运行的 A/B fake 点火子进程都被终止和回收。
- `stopAll()` 重复调用和自然退出并发不崩溃、不误杀无关 PID。
- 首次返回缓存、第二次实时的场景会重试。
- 两次都返回缓存时不能显示“新窗口已确认”。

## 12. 脱敏视觉证据

渲染测试只写 `$TMPDIR/Minget-1.3.0-Evidence/`，不得覆盖 1.0.2 或 1.2.1 历史素材。至少生成：

1. `520 × 560` 浅色全卡片，A/B 额度明显不同。
2. `520 × 560` 深色全卡片，A 缓存、B 实时。
3. `520 × 324` 只显示两个 ChatGPT 卡片。
4. ChatGPT 未知/已到期时间条。
5. Command Code 剩余额度收缩、5/7 段时间条、无刻度月时间线。
6. 弹层在屏幕中央、左边缘、右边缘三个菜单栏位置的 frame 证据。

所有证据使用 `demo@example.com`、合成余额和合成用量。用户本次截图不得入库。

## 13. 实施顺序

实现 Agent 严格按以下顺序工作：

1. 写失败测试，固定新尺寸、单列顺序、四种页面高度和无滚动规则。
2. 改 AppKit 启动入口，消除空 Settings Scene。
3. 改 `UsagePanelView` 为单列固定布局。
4. 按 1.2.1 恢复 ChatGPT 额度和重置时间双轨道。
5. 重做 Command Code 剩余额度和时间轨道。
6. 固定 popover preferredContentSize、中心锚点和屏幕容纳降级。
7. 修复点火停止和实时刷新判断。
8. 跑全部单元测试、布局测试、脱敏渲染和 Release 构建。
9. 启动签名包，人工检查无空窗、无越界、无滚动条。
10. 把修改文件、命令、测试结果、截图路径和未完成事项写入 `IMPLEMENTATION_REPORT.md`，停止并交给 Codex 独立复核。

## 14. 完成门槛

以下条件全部满足前，仍然判定 1.3.0 未完成：

- 冷启动无空窗口。
- 四卡片单列且在 `520 × 560 pt` 一页完整显示。
- OpenAI 两条额度轨道和两条分段时间轨道恢复。
- Command Code 显示额度剩余和时间剩余，方向、颜色、粗细和刻度符合本文。
- 弹层完整位于屏幕内并尽可能以菜单栏图标为中心。
- 退出后无 `codex app-server` 和点火 `codex exec` 遗留子进程。
- 缓存刷新不能确认新窗口。
- 全量测试、Release 构建、严格签名通过。
- 用户完成真实界面验收。

不得发布、推送、打标签、创建 GitHub Release 或执行真实点火请求，除非用户另行明确授权。

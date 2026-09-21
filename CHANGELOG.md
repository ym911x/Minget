# 变更记录

## 1.4.1（2026-09-21）

状态：发布验收通过并已发布。517 项自动测试执行，516 通过、1 项 AX 环境跳过、0 失败；Release arm64 构建、严格签名、签名包重启和真实界面验收通过。发布提交 `2d05344`、annotated tag `v1.4.1`、[GitHub Release](https://github.com/ym911x/Minget/releases/tag/v1.4.1) 与 CI `35549933542` 均已完成。

### 详情页外观

- 详情页保持 440 pt 单列，放大标题、额度和辅助信息，按 4/10/12 pt 留白分组并移除卡片内细分隔线。
- “明明有数”与版本号同行；ChatGPT 使用自定义名称、套餐和连接绿点两行头部；DeepSeek 使用两行余额和服务器状态布局。
- 5 小时重置时间固定 5 格，周额度固定 7 格，本月重置时间使用连续条并显示天数与日期。
- Command Code 统计拆为 Token／成本和请求／结果两行，长数值只在所属组内续行。
- 短屏只滚动卡片区，首选高度足够时不创建滚动容器。
- OpenAI 使用官方 SVG 的裁边矢量副本，避免后置放大导致发虚；DeepSeek 按鲸鱼实际图案裁去图片画布空白，放大可见图案并校准左缘；Command Code 使用默认名称时去掉副标题中重复的品牌名。

### 本地显示名称

- 设置页为 ChatGPT A、ChatGPT B、DeepSeek、Command Code 提供输入、保存和恢复默认。
- 名称按稳定 ID 保存，清理首尾空白，空值恢复默认，最多 40 个字符；详情页、来源选择、点火计划和辅助标签立即同步。
- 菜单栏保留 A/B/DS 短标签，账号绑定、缓存、刷新、点火计划执行和网络接口不变。


## 1.4.0（2026-09-20）

状态：发布验收通过并已发布。513 项自动测试执行（Core 360、App 153），512 通过、1 项既有 AX XCTest 明确跳过、0 失败；Release arm64 构建、staging/install/archive 严格签名、签名包退出/重启和设置页明暗布局检查通过。发布提交 `b9c2701`、annotated tag `v1.4.0`、[GitHub Release](https://github.com/ym911x/Minget/releases/tag/v1.4.0) 与 CI `35514875456` 均已完成。

### 点火模型统一

- 应用内 Command Code 手动点火与定时点火统一使用 `deepseek/deepseek-v4.1-flash`。
- 外部 `minget-fire` 的 Command Code 路径已核对为同一模型标识；本版本不修改 LaunchAgent 时间表或触发编排。

### 菜单栏低额度自适应刷新

- 当前菜单栏选中的 ChatGPT Profile 在 5 小时剩余严格低于阈值，或周额度剩余严格低于阈值时，增加只针对该 Profile 的补充刷新。
- 当前菜单栏显示 DeepSeek 且实际显示币种为 CNY、余额严格低于阈值时，增加 DeepSeek 补充刷新；显示 USD 等其他币种时不套用 CNY 阈值。
- 设置页新增低额度加速开关、15/30/60 秒周期、5 小时阈值、周阈值和 DeepSeek CNY 金额阈值；默认值为启用、30 秒、50%、15%、15.00 元，并可恢复默认。
- 当前来源切换、无效金额 fail-closed、既有请求合并和补充 timer 停止均有回归覆盖；详情页和其他账号的普通刷新规则保持不变。

### 验证边界

本版本自动测试使用 fake service/provider，不消耗真实额度。设置控件明暗布局、来源切换、timer 安装/取消与签名包启动已验收；真实低额度服务轮询没有通过人为制造额度条件触发，保留为发布后现场观察项，不提前写成通过。

## 1.3.2（2026-09-20）

状态：点火确认、刷新功耗优化、每日多时点点火计划与 Command Code 手动点火已实现。506 项自动测试执行（Core 360、App 146），505 通过、1 项明确跳过、0 失败；Release arm64 构建与 staging/install/archive 严格签名通过，Command Code 真实手动点火已由用户确认成功。用户于 2026-09-20 明确授权发布；发布提交 `c51791b`、annotated tag `v1.3.2` 和 [GitHub Release](https://github.com/ym911x/Minget/releases/tag/v1.3.2) 已完成。真实睡眠/唤醒、完整界面和 Command Code 定时点火保留为发布后验证项，不随发布改记为通过。

### 点火确认

- 确认读取只做 `handshake + rateLimits/read`，不调用 `account/read`，不更新归属，不触发缓存迁移；失败熔断语义与完整读取一致。
- 点火记录前值是否为实时；分类仍按 1.3.1 真值表，不新增分支。
- 卡片展示实测差值：确认态 `新窗口已确认 · +6小时12分`，未变化态如 `请求成功，窗口未变化 · +32秒`，暂无法确认态无后缀；辅助功能值同步。
- 每个 Profile 内存保留最近 3 次点火（结果、时间、差值），tooltip 多行展示；重启即清空，不持久化、不进日志。
- 实现中修复两个真实缺陷：轻量读取成功后未落盘导致卡片不展示新窗口；缓存回退覆盖显示导致重试 live 值被吞掉。

### 每日点火计划

- 设置页为 OpenAI 账号 A、账号 B 和 Command Code 分别提供多个每日本地时间；每条新建默认不启用，勾选后才生效。
- 计划支持 10 分钟启动/唤醒补跑、跨重启去重和系统时钟改变重算；相邻已启用时间小于 5 小时时给出橙色提示。
- 停止应用时取消计划触发任务并终止自有点火子进程，不使用 LaunchAgent 或外部 `minget-fire`。

### Command Code 点火

- Command Code 卡片新增「5 小时点火」按钮与固定确认文案；结果使用与 OpenAI 一致的三态、差值和最近 3 条历史。
- 用户授权 Minget 将 Keychain 中的 Command Code Key 仅传给官方 CLI。CLI 直启不经 shell，固定最小参数，禁用自动更新、session 和 skills，使用隔离 `HOME`，输出持续 drain 后丢弃。
- CLI 成功后仅通过既有 `credits` GET 端点确认 5 小时窗口；应用 HTTP 客户端的模型端点阻断保持不变。手动点火可请求 Keychain 交互，定时点火禁止弹窗。
- Command Code 卡片增至 416 × 176 pt，四卡详情页增至 440 × 566 pt；设置页为 520 × 700 pt 并使用一个有界滚动区承载可增长的计划。

### 刷新与功耗

- 详情页时钟从每 1 秒降为每 30 秒；菜单栏仍按 `Date()` 逐帧计算倒计时。
- ChatGPT 定时按重置时间退避：10 分钟 horizon 内 30 秒，无数据 60 秒，否则 120 秒；定时器幂等重排。
- Command Code 辅助接口 15 分钟复用窗口：自动刷新只重读 credits，手动刷新与重连强制全量；辅助失败不刷新复用时间戳。
- 菜单栏宽度按尺寸签名缓存，签名不变时跳过 `NSHostingView` 实测。
- 睡眠唤醒后一次节流刷新，30 秒内不与定时轮询叠加；不绕开失败熔断。

### 测试维护（R2）

- 辅助功能测试循环内重取当前窗口并关闭旧窗口；`UsagePanelView` 注释与实施报告措辞按 1.3.1 harness 实测对齐。

### English summary

Fire confirmation now reads rate limits only, shows measured drift, and keeps the last 3 finishes in memory. Settings adds opt-in daily multi-time fire schedules for ChatGPT A, ChatGPT B and Command Code. The Command Code card can fire through the official CLI using the app-owned Keychain key in an isolated HOME, then confirms through credits only. Its child PATH now resolves the CLI's Node shebang from Finder-launched builds. Refresh cadence, auxiliary caching, width caching and wake probes are also improved. 506 tests ran (360 Core, 146 App): 505 passed, 1 skipped, 0 failed. The user confirmed a real Command Code manual fire in the signed PATH-fix build and authorised release on 2026-09-20. Signed-app UI, real sleep/wake and real Command Code scheduled fire remain post-release checks and are not recorded as passed.

## 1.3.1（2026-09-18）

状态：稳定性修补已实现；Codex 复核发现的 R1 无障碍阻断已修复。451 项自动化测试执行（Core 331、App 120），450 项通过、1 项跳过、0 项失败；Release 构建和严格签名通过。跳过的 XCTest 进程没有可观测的辅助功能窗口；Codex 另用当前源码编译临时 GUI harness，真实读取系统 AX 树并确认设置入口为独立元素且可激活。用户于 2026-09-18 明确授权发布，`main`、标签 `v1.3.1`、[GitHub Release](https://github.com/ym911x/Minget/releases/tag/v1.3.1) 与发布提交 CI 均已完成。真实界面、真实 DeepSeek 菜单栏余额、A/B 真实点火和机器重启复验仍未执行，不随发布改记为通过。

本版本是稳定性修补版，窗口尺寸、卡片顺序、额度语义、菜单栏格式和凭证安全边界保持 1.3.0 不变。

### 双 Profile 完成即发布

- `UsageViewModel.refresh` 的 Task Group 元素从 `Void` 改为稳定 `profileID`，按完成顺序逐项消费：任一 Profile 一返回就立即在 MainActor 重新发布 `profileStates` 并递增 `tick`，不再等待另一个 Profile。
- 发布始终读取全部运行态的完整值快照，因此数组顺序永远是账号 A、账号 B，不按完成顺序重排。
- `isRefreshing` 仍是整轮状态：最后一个 Profile 完成或整轮取消后才恢复 `false`；`stop()`/取消后不再发布任何 UI 状态，迟到结果被丢弃。
- 保留既有 `guard !isRefreshing`，普通刷新仍不叠加。失败或缓存状态同样立即发布，不等待另一个账号。

### 点火确认三态与延迟重试

- `ChatGPTFireResult` 新增 `.requestSucceededConfirmationUnavailable`，固定文案“请求成功，暂无法确认”，次要色，既不标成功也不标失败；`isSuccess` 仍只对“新窗口已确认”为真。
- 新增纯分类类型 `FireWindowConfirmation`：输入点火前时间和最多两次实时观察，只输出三种请求成功结果，携带固定分类而不携带原始错误或响应。
- 时序固定为：CLI 成功后等 2 秒做第一次只读强制刷新；第一次已是实时前移 ≥ 60 秒时立即确认并跳过第二次；其他情况（缓存、失败、实时缺重置时间、实时未变化）一律再等 5 秒做第二次只读刷新，按真值表产生唯一最终结果。
- 第二次刷新只读取额度，不重复 Codex 模型请求。`fetchFiveHourReset` 的 live-only 规则保持不变。
- 缓存和失败不再被当作“窗口未变化”。原“两次缓存得到未变化”的断言已按新语义改为“暂无法确认”。

### Command Code 分层容错

- `credits` 仍是唯一必须成功的来源，其自身错误继续抛出，不会被折叠成缺失的统计。
- `summary` 改为可选解析：网络错误、5xx、401/403、畸形 JSON 或字段结构变化都只让 `summary == nil`，统计区明确显示不可用，已取得的 5 小时／周额度保持 live。
- 辅助接口单独 401/403 不再暂停凭证，凭证状态由主数据 credits 决定；credits 的 401/403 仍暂停。
- 月度行只组合实际取得的字段：有 credits 余额无 summary 时保留 `remaining`，`used` 和 `limit` 保持缺失，不推算总额或计费周期。
- 不新增网络路径，不改变 Bearer、Accept、超时和跨域重定向防护，不修改 `ProviderModels` 持久化结构。

### Command Code 缓存与统计文案

- `CommandCodeCardPresentation` 集中生成标题副文案与缓存帮助文本，视图不再有第二套判断：connected 显示套餐名或“已连接”；stale 显示 `<套餐名> · 缓存` 或“缓存数据”；其他状态沿用既有固定连接／错误文案。
- 缓存帮助文本固定为“缓存数据 · 上次成功 `<MM-dd HH:mm>`”，时间缺失时为“缓存数据 · 成功时间未知”；工具提示与辅助功能标签都表达同样的缓存语义，不显示底层错误原文。
- `summary == nil` 的第一行改为“统计暂不可用 · Token — · 请求 —”；`summary` 存在但周期未知时继续显示“统计周期未确认”，两者不再共用一句话。
- Command Code 卡片 416 × 162 pt、轨道宽度、字号、间距和三条额度行均未改动。

### 测试与构建

- 新增 `ProfileRefreshPublishingTests`：用可控阻塞点确定性地验证 A 先完成、B 先完成、A 失败、整轮关闭后可开始下一轮，以及 `stop()` 后迟到结果不发布。
- 新增 `CommandCodeAccessibilityTests`：保留始终执行的控件存在性检查，并准备真实辅助功能树检查；当前 XCTest 进程没有可观测的 AX 窗口时明确跳过，不计为通过。Codex 使用单独的临时 GUI harness 完成了真实 AX 树验收。
- `FireLifecycleTests` 扩充到覆盖真值表全部四行、第一次确认后跳过第二次、实时未变化仍执行第二次、两次实时都未达阈值、缺前值、以及在 2 秒和 5 秒等待期间停止。
- `CommandCodeProviderTests` 新增 summary 失败／畸形／401／403、月度字段不伪造、credits 401／结构不支持仍关闭等用例。
- 修正 `ChatGPTFireServiceTests.testTimeoutTerminatesTheChildAndReportsTimeout` 的既有计时竞态：0.5 秒超时可能早于 `python3` 写完 PID 文件，该用例改为 5 秒超时，使断言针对被测行为而不是解释器启动速度。
- `swift test --scratch-path /tmp/minget-131-tests`：Core 331 + App 120，共 451 项执行，450 项通过、1 项跳过、0 项失败。
- `./scripts/build.sh` 完成 Release 构建、staging 严格签名和固定运行路径严格签名安装；`CFBundleShortVersionString = 1.3.1`。

### 无障碍修复（R1）

- Command Code 卡片此前对整个 `header` 使用 `.accessibilityElement(children: .combine)`，把标题、状态文字和「前往设置／查看设置」按钮合并为一个元素。真实辅助功能树实测显示：合并后设置入口**不再作为独立元素存在，名称也一并消失**，VoiceOver 只会读出「Command Code，未连接，按钮」，用户无从知道它通向设置。
- 现在只对 Logo、标题和副文案组成的非交互视图 `CommandCodeHeaderIdentity` 使用 `.combine`；设置按钮留在 `header` 中作为独立兄弟元素。修复后树中是 `AXStaticText desc=Command Code` 加上独立的入口元素 `desc=前往设置／查看设置`，可单独聚焦、激活，缓存副文案仍由身份元素读出。
- 修复由代码结构、控件存在性测试和 Codex 的独立 GUI harness 共同复核。仓库内真实 AX 树用例在 XCTest 没有可观测窗口时跳过并明确标注为未执行，不计入通过项。

### 版本与文档

- `VERSION`、`README.md`、`ROADMAP.md` 与内嵌构建说明同步到 1.3.1。`scripts/build.sh` 内嵌 README 的“single app-server”旧描述改为两个 Profile 各有独立子进程，构建流程未改动。
- 详情页 Header 与设置页的开发态版本 fallback 更新为 `1.3.1`，运行包版本仍直接读取 bundle。

## 1.3.0（2026-09-17）

状态：双 ChatGPT 账号、菜单栏三来源与手动点火已实现；首轮 720 pt 双列布局和启动空窗口在真实界面验收中被否决，第三轮界面微调已完成。425 项自动化测试（Core 325、App 100）、Release 构建、严格签名和真实详情页验收通过，随 [Minget v1.3.0](https://github.com/ym911x/Minget/releases/tag/v1.3.0) 发布。真实 DeepSeek 菜单栏余额与 A/B 两次真实点火仍待后续验证。

### 界面微调（2026-09-17）

- 详情页从 520 pt 进一步收窄为 440 pt，卡片内容宽度为 416 pt；四种页面尺寸为 `440 × 552 / 498 / 384 / 330 pt`。设置页继续保持 `520 × 600 pt`。
- 两张 ChatGPT 卡片的 5 小时与周额度窗口之间增加到 4 pt 间距；Command Code 的 5 小时、周额度、本月三个窗口之间同样使用 4 pt 间距。
- Command Code 额度文字精简为 `$余额 / $总计`，移除“剩余”和重复百分比；5 小时与周只显示绝对重置日期时间，本月继续显示剩余天数与日期。
- DeepSeek 菜单栏完整和紧凑模式均使用 `DS CNY 123.45`，移除汉字“余额”；完整模式使用 13 pt medium 与 7 pt 词间距，紧凑模式使用 12 pt medium 与 4 pt 词间距。
- DeepSeek 详情卡改为 `416 × 48 pt` 单行：Logo、wordmark、连接状态、可点击服务状态和余额位于同一水平线；余额改用 `110.00 CNY` 行内格式，极端宽度不足时保留主币种完整金额并把其余币种合并为溢出提示。
- 脱敏渲染更新为 `440 × 552` 全卡片和 `440 × 330` 双 ChatGPT 页面，并增加新菜单栏字号与单行 DeepSeek 卡片检查。

### 回归修订（2026-09-17）

- 启动入口改为显式 AppKit（`@main enum MingetMain` + `NSApplication.run()`），不再声明任何 SwiftUI `Scene`。此前的 `Settings { EmptyView() }` 仍是真实场景，系统可在启动时把它打开，用户会看到一个空的「设置」窗口；现在该失败模式在结构上不再存在，而不是启动后补一次 `close()`。设置窗口仍只由用户点击设置时创建。
- 详情页由 720 pt 双列恢复为 520 pt 单列，一排一张卡片，顺序固定为 ChatGPT A、ChatGPT B、DeepSeek、Command Code；四张全开 `520 × 560 pt`，仅 Command Code `486 pt`，仅 DeepSeek `398 pt`，都隐藏 `324 pt`。新增纯几何模型 `DetailPageLayout`，视图与测试共用同一套 frame 计算。
- 详情页与普通详情窗口继续不包含任何滚动容器；新增断言覆盖四种页面状态、四张卡片的 `minX` 一致、宽度均为 496、`minY` 严格递增且两两不相交。
- ChatGPT 卡片恢复 1.2.1 的信息层级：每个窗口都是「剩余额度轨道 + 其正下方的分段时间轨道」成对出现，5 小时 5 段、周额度 7 段，时间轨道表示距离重置的剩余时间并从右向左收缩；未知或非法时间显示灰色轨道与中央 `?`，已到重置时间显示「等待刷新」。卡片 `496 × 126 pt`，内边距 10 pt。
- Command Code 卡片额度轨道方向修正为 `remaining / limit`（原为 `used / limit`），亮色左对齐、越用越短；右侧固定显示 `剩余 $X.XX / $Y.YY · Z%`。每条额度下方新增重置时间轨道：5 小时 5 段、周 7 段、本月连续单条、system indigo，同样表示剩余时间。
- 月度进度不再猜测：`ProviderUsage` 新增可选 `billingPeriodStart`，`CommandCodeProvider` 只解析响应真实包含的 `currentPeriodStart`，且开始必须早于结束；只有两端都存在才绘制月度进度，只有结束时间时画中性空轨道。新增字段为可选，既有 `ProviderCache` JSON 仍可解码。
- DeepSeek 卡片改为 1.2.1 的横向紧凑形态 `496 × 68 pt`，最多显示 3 个币种金额，超过 3 个时第三项显示「另有 N 个币种」。
- 弹层在 `show` 之前先把 hosting controller 与 `NSPopover` 的内容尺寸设成当前页面尺寸，再以状态按钮 `midX` 处的 2 pt 中心锚点显示；当前屏幕容纳不下整页时不再显示被裁掉的弹层，改用普通详情窗口。普通详情窗口首次打开时以菜单栏图标的屏幕坐标为水平中心，并把 frame clamp 到 `visibleFrame`。
- 点火生命周期修复：新增 `ChatGPTFireService.stopAll()`，退出时在 coordinator drain 之前终止并回收仍在运行的 `codex exec` 子进程（原实现只取消 Swift 任务，无法触及阻塞中的 `Process`）；`fetchFiveHourReset` 改为只在 `FetchResult.isLive == true` 时返回新 `resetsAt`，缓存成功不再被当作新窗口确认。
- 新增冷启动真实进程测试：启动签名包后 2 秒内该进程不得拥有任何非 520 pt 宽度的窗口，退出后不得遗留自有子进程；另新增 `FireLifecycleTests` 覆盖「缓存 → 重试 → 实时确认」与「stop 终止运行中的点火子进程」。
- 渲染测试证据改为 `520 × 560` 浅色/深色、`520 × 324`、ChatGPT 未知与已到期时间条、Command Code 剩余收缩与三种时间轨道，并输出弹层在屏幕中央与左右边缘的 frame 记录；全部只写 `$TMPDIR/Minget-1.3.0-Evidence/`。

### 首轮实现（2026-09-16）

- 新增 `ChatGPTAccountProfile`：两个固定只读 Profile（`chatgpt-a` / `chatgpt-b`，短标签 `A` / `B`，相对路径 `.codex-minget-a` / `.codex-minget-b`）。默认值不含个人绝对路径，运行时按当前用户主目录解析；1.3.0 不提供新增、删除或改名界面。
- 新增 `CodexProfileRuntime` 与 `CodexProfilesCoordinator`：每个 Profile 一个长生命周期 `UsageService` 与独立 `codex app-server` 子进程，独立失败预算，并行刷新，退出时并发 drain。
- `UsageService` 新增 Profile 归属与 `childEnvironment(base:codexHome:)`：复制当前环境并只覆盖该 Profile 的 `CODEX_HOME`；`CodexLocator` 保持只负责定位可执行文件，子进程仍由 `Process.executableURL` 直启，不经过 shell。
- `UsageCache` 的 last-known account 改为按 Profile 保存，并新增 v3 `profileID + accountID` 命名空间。旧 1.2.1 缓存在升级后不展示；账号 A 首次成功读到相同 accountID 才迁移，不同或缺失时删除，账号 B 永不接收。DeepSeek 与 Command Code 的 `ProviderCache` 格式未变。
- `UsageViewModel` 改为发布 `[CodexProfileViewState]`；`displayState`、`connectionState`、`codexAccount` 三个单值形态移除。一轮刷新并行覆盖两个 Profile，单个 Profile 点火后只强制刷新该 Profile。
- 新增 `MenuBarPreferences`：菜单栏来源以稳定标识持久化（Profile ID 或 DeepSeek），升级默认账号 A，损坏值回退账号 A，不扫描用户目录寻找其他账号。
- 菜单栏构建器改为接收已解析来源。ChatGPT 完整 `A 5H 78% | W 42%`、紧凑 `A 78% 42%`，保留双额度与两排重置时间条；DeepSeek 完整 `DS CNY 余额 123.45`、紧凑 `DS CNY 123.45`，不显示时间条，无可用余额时显示 `DS —` 并加一个前置警告标记。
- DeepSeek 多币种菜单栏选择顺序固定为「已保存且仍存在 → CNY → USD → 币种代码升序 → 币种未确认」，优先 `available`，否则 `total`；不换算、不合计、不显示零。
- 新增 `CodexProfileCard`：显示 Profile 名称、连接/缓存状态、套餐、实际账号邮箱、两个额度窗口、重置时间、可用重置次数、点火结果与“5 小时点火”按钮。邮箱中间省略并支持选择复制。
- 设置页固定 `520 × 600 pt`，新增纵向 radio group 的“菜单栏显示”（账号 A、账号 B、DeepSeek）与 DeepSeek 币种 Picker；服务组列出两个只读 ChatGPT 行（仅显示 `CODEX_HOME` 尾段），DeepSeek 与 Command Code 管理表单改为单开 accordion。详情显示开关与菜单栏来源保持相互独立。
- 新增 `ChatGPTFireService` 与 `ChatGPTFireResult`：使用 `CodexLocator` 定位官方 CLI，`Process` 直启固定参数 `exec --ephemeral --sandbox read-only --skip-git-repo-check -C <临时目录> -m gpt-5.6-luna -c model_reasoning_effort="none" "Reply exactly: OK"`，不调用 `minget-fire`，不使用 shell。
- 点火子进程的 stdout/stderr 持续 drain 后丢弃，不写入日志、UserDefaults、测试快照或文档；不记录 session id、prompt 或 token。超时固定 120 秒，terminate 后等待 3 秒，仍未退出时只对本次 PID 发送 `SIGKILL` 并回收。
- 同一 Profile 进行中再次请求立即返回 `.alreadyRunning`，不排队、不合并；不同 Profile 可并行。点火成功后等待 2 秒强制刷新该 Profile，失败再等 5 秒重试一次；只有同一 Profile 的实时新值比点火前晚至少 60 秒才显示“新窗口已确认”，否则显示“请求成功，窗口未变化”。
- 现有 `~/.local/bin/minget-fire`、`com.minget.chatgpt-fire` LaunchAgent 和两个 `CODEX_HOME` 未被读取、修改或调用；应用内手动点火不产生 raw log。本版本不实现 LaunchAgent 编辑、自动点火开关、定时表、睡眠唤醒、Fire All 或点火历史。
- 渲染测试输出统一改为 `$TMPDIR/Minget-1.3.0-Evidence/`，不再写入 `docs/archive/` 或任何历史 evidence 目录。

## 1.2.1（2026-09-15）

状态：金额显示与详情卡片空间修订已实现；310 项自动化测试、Release 构建和严格签名检查通过，真实界面已由用户确认，随 [Minget v1.2.1](https://github.com/ym911x/Minget/releases/tag/v1.2.1) 发布。

- Command Code 的窗口已用、剩余和统计成本统一显示到小数点后 2 位，显示层采用四舍五入，底层 `Decimal` 原值不变。
- 移除 Command Code 卡片底部的“刚刚更新”“更新于 X 分钟前”等相对时间，继续使用详情页顶部的全局刷新状态。
- Command Code 可见时详情页高度同步减少 20 点，避免删除底部文字后留下无效空间。

## 1.2.0（2026-09-15）

状态：实现、309 项自动化测试、Release 构建和严格签名检查已完成；用户截图确认真实 Command Code API Key 能返回额度与用量数据。修复后的持续显示仍需真实界面复验；源码已发布为 [Minget v1.2.0](https://github.com/ym911x/Minget/releases/tag/v1.2.0)。

- 新增 Command Code Keychain 凭证、账号隔离缓存、认证暂停、并发刷新合并和五分钟刷新链路；详情页默认显示可隐藏卡片，菜单栏不新增 Command Code 指标。
- 只读使用 `credits`、`usage/summary` 和可选 `subscriptions` 三条 `/alpha` 路径；Bearer 凭证、GET、超时、路径白名单、模型端点阻断和跨域重定向拒绝均有测试约束。
- 规范化展示 5 小时、周、月度信用额及 token、请求、成功率、成本；缺失字段、未知周期、字段漂移和接口未确认状态均不伪造数字。
- 详情页固定高度扩展为：仅 Codex 320 点，含 DeepSeek 420 点，含 Command Code 530 点，双卡 630 点。
- 修复 Command Code 数据只在刷新中短暂显示的问题：刷新后的报告重建会保留刚成功取得的用量，并以缓存支持完整重启恢复。

## 1.1.2（2026-09-15）

状态：实现、自动验证、真实界面检查和 GitHub Release 均已完成；发布页为 [Minget v1.1.2](https://github.com/ym911x/Minget/releases/tag/v1.1.2)，证据与边界见 [1.1.2 验收台账](docs/versions/1.1.2/ACCEPTANCE.md)。

- 菜单栏空间状态只保留完整与紧凑双额度模式，紧凑文本固定保留 `5H` 和 `W`，两排重置时间条继续显示；紧凑模式仍无法渲染时沿用隐藏状态项打开详情窗口，不输出残缺的 `5H`。
- OpenAI `account/rateLimits/read` 的 `rateLimitResetCredits` 只读解析 `availableCount` 和最近未来 `expiresAt`，在详情卡显示“可用重置 N 次”及可选最近到期时间；缓存、缺失或非法字段显示不可用，不提供消费操作。
- DeepSeek 详情卡将服务文字标识放到鲸鱼 Logo 右侧，真实余额与品牌同列右对齐并垂直居中，连接与官方服务状态位于下方并继续支持多币种。未增加账号接口或浏览器会话读取。
- 详情页改为固定整页布局，移除纵向滚动容器；窗口高度按是否显示 DeepSeek 收紧为 420/320 点，避免详情内容被滚动条或底部留白遮挡视觉重点。
- `UsageSnapshot` 的可选重置摘要持久化保持旧缓存可解码，新增解析、格式化、缓存边界和菜单栏状态机回归测试。
- `swift test`：301 项通过，0 项失败；Release 构建和严格签名检查结果记录在版本验收台账。

## 1.1.1（2026-09-13）

状态：实现、自动测试、本地构建和真实界面检查完成，随 GitHub `v1.1.1` 发布；真实服务账号未重新请求。

- 移除智谱 GLM 的取数、网络请求、WebKit 登录、解析、设置、详情和诊断路径。
- 启动时按本应用旧标识清理 GLM Keychain 项、缓存、连接模式和显示偏好；删除失败不影响启动，并在下次启动重试。
- 设置页合并为“服务”模块，显示 OpenAI Codex 的固定详情状态，以及 DeepSeek 的显示开关和管理入口。
- 退出按钮改为“退出明明有数”。关于弹层增加 GitHub 项目主页链接。

## 1.1.0（2026-09-13）

状态：详情页与精简设置已完成，自动测试和构建通过，用户已确认当前详情页体验；未覆盖的边界交互和真实服务回归见 [验收台账](docs/versions/1.1.0/ACCEPTANCE.md)。

### 详情页

- 重构为顶部标题、刷新状态、设置入口、Codex 卡片和余额卡片的紧凑布局。
- Codex 卡片使用 OpenAI Blossom 图标，图标后的套餐文字来自 `account/read` 返回的真实 `planType`；账号邮箱放在右侧，四条轨道共用同一宽度，保持左右端对齐。
- 5 小时和周额度分别显示连续额度条，以及蓝色 5 段和 7 段重置时间条。
- 重置时间显示真实本地时间点 `MM-dd HH:mm`；到期、未知和非法状态不显示虚构日期。
- 余额概览优先使用真实 `available` 字段，否则使用 `total`；CNY 使用 `¥`，Decimal 统一两位概览精度。
- DeepSeek 与智谱 GLM 改为各自占据一整行；DeepSeek 使用用户提供的黑色鲸鱼图标和只保留 `deepseek` 的透明文字标识，连接与官方服务状态压缩到金额下方的小号元数据区。
- 追加收紧详情页底部高度、使用原始 Blossom SVG、标题名称跟随系统语言并显示版本；DeepSeek 金额行改为“余额 + 金额”、状态完整显示在金额下方；设置页移除滚动容器，弹层锚点固定到状态项按钮中心并跟随系统外观。

### 设置

- 新增单页精简设置窗口。
- 新增 DeepSeek 和智谱 GLM 是否显示在详情页的两个开关，默认开启并持久化到应用自有 UserDefaults。
- 既有连接管理、钥匙串诊断、关于、打开详情和退出入口迁入设置页；未增加刷新周期、通知、主题等新设置。

### 验证

- `swift test`：371 项通过，0 项失败，0 项跳过。
- `./scripts/build.sh`：Release 构建成功，运行包严格签名校验通过，版本为 `1.1.0`。
- 用户已确认当前详情页体验。本版本按源码发布，不附带未经 Apple 公证的安装包。

## 1.0.2（2026-09-12）

状态：实现、独立审核与用户真实界面验收完成。资料见 [docs/versions/1.0.2](docs/versions/1.0.2/)。

### 菜单栏

- 移除菜单栏内的品牌图标 `M²`。三种空间模式都以纯文字显示额度，正常态从 `5H` 起头，不再保留图标占位空隙。
- 在额度文字下方新增两排重置时间分段条：上排 5 段对应 5 小时窗口，下排 7 段对应周窗口。两排左右端严格对齐额度文字的实测宽度。
- 亮区随时间从右向左缩退，到重置时间时整排变空并等待下一次真实刷新，不自行恢复满格。
- 7 段按「每段 1 天、合计 7 天」实现，而不是每段一周。这是对用户原话的明确设计解释，详见 [需求与实施任务书](docs/versions/1.0.2/REVISION_SPEC.md) 第 1.3 节。
- 重置时间未知或非法时，该排轨道变淡并以一个 `?` 区分「未知」与「已到期」，不新增第二处警告。
- 菜单栏异常提示统一为文字前方的一个标记（SF Symbol 警告三角），删除字符串尾部追加的 `⚠`。同一时刻最多一个标记。

### 交互

- 菜单栏详情弹层支持点击外部收起，覆盖桌面、其他应用、其他状态项与本应用的独立窗口，收起后原点击仍作用到原目标。
- 普通详情窗口与 GLM 登录窗口保持普通窗口行为，不因其他位置点击而自动关闭。

### 修复

- 修正状态项首次布局使用 fallback 宽度参与截断判定，导致空间充足的菜单栏被误判为截断、并降级到最小兜底且自动弹出详情窗口的问题。
- 修正唤醒通知注册在默认通知中心因而从不触发的问题，改用 `NSWorkspace.shared.notificationCenter`。

### 构建

- `scripts/build.sh` 默认改用本地代码签名身份 `Minget Local Signing`，解决 ad-hoc 签名导致的钥匙串反复授权弹框。签名身份不存在时构建以非零退出，不产出未签名包；`MINGET_SIGN_IDENTITY=- ./scripts/build.sh` 可回退到 ad-hoc。
- 新增 `scripts/make-signing-identity.sh`，用于生成并导入该自签名证书。本机已创建 `Minget Local Signing` 身份，当前候选包已使用该身份签名并通过严格校验。

### 钥匙串与凭证（KEYCHAIN_REVISION_PLAN.md）

- 凭证读取返回类型化结果（可用/不存在/需要交互/已拒绝/其他），失败不再全部折叠为"未配置"；只有 `errSecItemNotFound` 报告为不存在，其余保留原始状态码。
- 新增凭证访问协调器：本进程全部钥匙串调用走一条串行队列，同一凭证的并发读取合并为一次访问，成功值仅存进程内存。
- 启动、状态查询与后台刷新不再直接访问钥匙串：先做一次后台无交互读取，被拒后显示「需要授权」并暂停该平台自动尝试；只有用户点「授权读取」才会进行一次可能弹窗的读取。
- DeepSeek 一次读取的凭证同时用于余额请求与账号指纹；GLM 只加载已选连接模式需要的凭证，控制台模式不再探测旧 API Key。
- 钥匙串写入与删除失败会传播到界面：删除失败显示「断开失败」，授权拒绝不再引导重新输入 Key。
- 面板新增「记录钥匙串访问诊断」开关，把每次凭证访问的类别、状态码与耗时写入应用自身目录，正常启动即可采集。
- 构建脚本将候选包安装到 `~/Applications/Minget.app` 并做严格校验；`dist/Minget.app` 为归档副本（位于 iCloud 路径，严格校验受文件提供方属性影响，差异由脚本显式记录）。

### 验证

- 自动化测试：359 项通过，0 项失败，0 项跳过。
- 候选包完成构建、Info.plist 校验与代码签名校验，`CFBundleShortVersionString` 为 `1.0.2`。
- 真实进程运行验证了模式保持、测宽替换、退出清理与钥匙串读取。用户已确认钥匙串只弹一次，选择“始终允许”后不再重复弹出；点击菜单栏详情后再点击桌面或其他应用，详情会立即收起且原点击有效。

## 1.0.1（2026-09-10）

### 品牌

- 对外产品品牌由工程代号 UsageMonitor 更新为「明明有数 · Minget」。
- 确立品牌视觉符号 `M²`，以及固定的中英文 Slogan。
- 更新 README、应用显示名称、关于页面、菜单栏识别和应用图标。
- Swift Package、Target、Bundle Identifier、缓存键以及 v1.0 历史归档继续保留原工程标识。

## 1.0.0（2026-09-10）

首个完成实际运行验证的正式版本。

### 功能

- 在 macOS 菜单栏显示 Codex 额度，并展示 5 小时额度、周额度、重置时间和更新时间。
- 显示当前 Codex 账号名称。
- 检测菜单栏状态项与屏幕刘海安全区域的关系，在屏幕切换、唤醒、位置变化及每 10 秒本地检查时更新状态。
- 通过 DeepSeek 官方余额接口读取总余额、充值余额和赠送余额。
- 通过智谱控制台独立登录会话读取余额、累计充值、累计赠送、累计消费和冻结金额。
- 使用 macOS Keychain 保存服务凭据，并在本机保存非敏感缓存和偏好设置。
- 支持手动刷新、自动刷新、开机启动及菜单栏显示方式设置。

### 验证

- 自动化测试：274 项通过，0 项失败。
- Release 应用完成构建、Info.plist 校验和代码签名校验。
- 用户完成 Codex、DeepSeek 和智谱 GLM 的实际连接与余额显示验证。

### 已知限制

- 智谱取数依赖控制台当前的网页接口和登录会话，控制台改版后可能需要适配。
- 长时间运行下的智谱登录会话寿命仍需在后续版本持续观察。
- 当前为 Apple Silicon 构建，尚未制作通用二进制或公证安装包。

---

## English summary

### 1.3.1 (2026-09-18)

A stability patch; window sizes, card order, quota semantics, menu-bar formats, and credential boundaries are unchanged from 1.3.0. 451 automated tests ran (331 Core, 120 App): 450 passed, 1 was skipped, and 0 failed, plus a release build and strict signing. The skipped XCTest process exposed no observable accessibility windows; a separate GUI harness built from the current sources verified the real AX tree and activation. Released as [Minget v1.3.1](https://github.com/ym911x/Minget/releases/tag/v1.3.1), with the release-commit CI passing. Real-interface, real DeepSeek menu-bar, real A/B fire, and post-reboot checks remain unverified.

- One refresh round publishes each ChatGPT profile as soon as that profile returns, instead of waiting for the whole task group. The published array still reads account A then account B, `isRefreshing` still covers the round, and nothing is published after `stop()`.
- Fires now distinguish three outcomes: a live before/after comparison that moved by at least 60 s confirms a new window, live reads that did not move report the window unchanged, and missing or cached evidence reports "request succeeded, confirmation unavailable" rather than claiming the window did not change. A conclusive first read skips the second; every other case retries once after 5 s.
- Command Code `credits` stays the only required source. A failed summary leaves the quota windows live with `summary == nil`, an auxiliary 401/403 no longer suspends the credential, and the monthly row keeps only the fields that really arrived.
- A cached Command Code card says `<plan> · 缓存` (or `缓存数据`) with a "缓存数据 · 上次成功 …" tooltip, and a missing summary reads `统计暂不可用 · Token — · 请求 —` instead of the unknown-period wording.
- Accessibility fix: the card header no longer combines the whole row. Only the non-interactive logomark, title and subtitle are merged, so the settings button keeps its own `AXPress` action.
- The pre-existing timing race in `ChatGPTFireServiceTests.testTimeoutTerminatesTheChildAndReportsTimeout` (a 0.5 s budget racing `python3` startup) is stabilised with a 5 s budget.

### 1.3.0 (2026-09-17)

Released as [Minget v1.3.0](https://github.com/ym911x/Minget/releases/tag/v1.3.0). Two isolated ChatGPT (Codex) accounts, a selectable menu bar source, and a per-account manual fire button are included. The third UI revision uses a fixed 440 pt single column, adds modest spacing between quota-window groups, simplifies Command Code values and reset copy, enlarges the DeepSeek menu-bar label, and places the DeepSeek detail card on one line. 425 automated tests (325 Core, 100 App), a release build, strict signing, and real detail-page acceptance pass. Real DeepSeek menu-bar balances and both real fire requests remain unverified.

- The entry point is explicit AppKit with no SwiftUI scene, so a cold start shows only the menu-bar icon; the `Settings { EmptyView() }` scene that macOS could open is gone structurally rather than closed after the fact.
- The detail page is a 440 pt single column, one card per row in the fixed order ChatGPT A, ChatGPT B, DeepSeek, Command Code, with page heights 552 / 498 / 384 / 330. A pure `DetailPageLayout` model is shared by the view and the layout tests.
- Each ChatGPT window is again a pair of tracks: remaining-credit above, its own segmented reset-time rail below (five and seven segments), with a grey `?` rail for unknown times and 等待刷新 once the reset time has passed.
- Command Code's credit tracks show `balance / total` without a duplicate percentage. Five-hour and weekly rows show only an absolute reset date and time; the monthly row retains relative days. Each row keeps its own time rail.
- The DeepSeek menu-bar label is `DS CNY 123.45` with larger full-mode typography, and its 48 pt detail card places the logo, wordmark, statuses, and balances on one horizontal line.
- The panel fixes its content size before `show` and falls back to the regular detail window when the page cannot fit the screen, so a clipped panel can no longer be left off-screen. The regular detail window centres on the menu-bar icon and is clamped into the visible frame.
- Fire lifecycle: `ChatGPTFireService.stopAll()` terminates and reaps a running `codex exec` at exit, and only a live refresh (`isLive == true`) may confirm a new window; a cached refresh never does.
- A real-process cold-start test asserts the signed app owns no layer-0 window at cold start and leaves no child behind; `FireLifecycleTests` cover the cached-then-live retry and stopping a running fire.

### 1.0.2 (2026-09-12)

Implementation, independent review, and user validation are complete. See [docs/versions/1.0.2](docs/versions/1.0.2/).

- Removed the `M²` brand mark from the menu bar in all space modes; the quota text now starts with `5H`.
- Added two rows of reset-time segments under the quota text: 5 segments for the five-hour window and 7 for the weekly window, both spanning the measured text width. The bright region recedes from right to left and empties at the reset time without refilling locally.
- The 7 weekly segments are one day each (7 days total), not one week each. This is a documented interpretation of the original wording.
- Unified the abnormal marker into a single leading marker and removed the trailing `⚠` appended by the formatting layer.
- The transient menu bar popover now collapses on an outside click while the click still reaches its original target; independent windows are unaffected.
- Fixed a first-layout defect where the per-mode fallback width was used as the truncation baseline, which downgraded a roomy menu bar to the minimal fallback and auto-opened the detail window.
- Fixed the wake notification being registered on the wrong notification centre.
- 345 automated tests pass; the candidate bundle is built and signature-verified. Real menu bar screenshots and real click interactions remain unverified on this machine.

### 1.0.1 (2026-09-10)

- Updated the public product identity from the `UsageMonitor` engineering name to **明明有数 · Minget**.
- Added the M² app icon, bilingual slogans, About view, branded app bundle name, and public documentation.
- Retained internal package, target, bundle identifier, persistence keys, and frozen v1.0 archive names for compatibility.

### 1.0.0 (2026-09-10)

The first user-validated release. It displays Codex usage windows and account identity, DeepSeek balances, and Zhipu GLM console balances. The release passed 274 automated tests and a local Apple Silicon release build. The app is ad-hoc signed and is not yet notarized for public binary distribution.

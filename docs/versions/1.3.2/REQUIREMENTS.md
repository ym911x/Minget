# 1.3.2 点火计划、点火确认与刷新功耗优化需求

状态：新增的定时点火与 Command Code 点火已实现并完成自动验证，Command Code 真实手动点火已由用户确认成功。用户于 2026-09-20 接受发布；真实睡眠/唤醒、完整界面和 Command Code 定时点火保留为发布后验证项，不改记为通过。

本文把 1.3.2 的产品判断、状态语义和边界一次性固定。实现 Agent 不得自行扩大范围；遇到本文没有覆盖且会改变用户可见行为的情况，停止实现并记录问题，交由 Codex 与用户确认。

1.3.2 是小版本优化版：点火确认更省、刷新更省电，并根据用户的后续明确要求加入每日多时点自动点火和 Command Code 点火。菜单栏格式、额度语义和点火三态真值表保持不变；Command Code 卡片与设置页因新控件增高。

## 1. 版本目标

1. 点火确认只读取确认真正需要的额度数据，不再附带账号身份请求；点火前记录前值是否为实时；卡片展示前后时间差，方便判断时钟抖动与真实新窗口；每个账号保留最近几次点火记录。
2. 详情页每秒 tick 降频，菜单栏倒计时不受影响；ChatGPT 定时刷新按重置时间动态退避；Command Code 辅助接口单独降频；菜单栏宽度测量结果缓存；睡眠唤醒后先探活再按需刷新。
3. 修复 R2 测试维护问题：`CommandCodeAccessibilityTests` 循环内复用旧窗口列表；对齐两处说明文字。
4. 在设置页为 OpenAI 账号 A、OpenAI 账号 B 和 Command Code 提供每日多个固定点火时间，每条单独勾选生效。
5. Command Code 详情卡增加与 OpenAI 一致的 5 小时点火按钮和确认结果；仅在用户明确确认或已勾选定时项时，将 Minget Keychain 中的 Key 传给官方 CLI 执行最小模型请求。

## 2. 已核实的 1.3.1 基线

- 点火确认的两次只读刷新走完整 `coordinator.fetch`，内含 `handshake + account/read + rateLimits/read`。确认逻辑只使用 5 小时 `resetsAt`，身份请求对确认无贡献。
- 点火前只保存 `previousFiveHourReset: Date?`，丢失了该值来自实时还是缓存的信息；stale 前值会让下一次点火的比较基础不可靠。
- 点火结果只有最终分类文案，没有前后时间差；59 秒与 61 秒的边界肉眼无法区分。
- 每个 Profile 只有一个 `fireResult`，连点两次即覆盖上一次，无时间信息。
- `UsageViewModel.clockTimer` 每 1 秒 `tick += 1`，详情页整页每秒重算；菜单栏签名已排除倒计时，但详情页仍在每秒刷新。
- ChatGPT 定时刷新固定 60 秒一轮，与已知的重置时间无关；离重置很远时也在高频轮询。
- Command Code 三路 `async let` 每次同频并发，辅助两路失败时仍占 5 分钟轮询。
- `MenuBarLabelMetrics.widths` 每次内容变化对 full 与 compact 各建一次 `NSHostingView` 实测，无缓存。
- 睡眠唤醒后无显式探活，靠下一轮 fetch 自然恢复，唤醒后第一轮容易超时一次。
- R2：`CommandCodeAccessibilityTests.swift` 第 148 至 152 行缓存 `windows`，第 162 至 168 行新建窗口后第 170 行仍读旧 `windows`；`UsagePanelView.swift` 第 720 至 721 行注释仍写合并后没有 `AXPress`；`IMPLEMENTATION_REPORT.md` 对 AX 用例的实现摘要写成查找 `AXButton`，实际按名称查找并直接执行 `AXPress`。

## 3. 点火规则改进

### 3.1 轻量确认读取

- 新增确认专用的轻量读取路径：只做 `handshake + rateLimits/read`，不做 `account/read`，不更新账号身份与缓存归属。
- 轻量读取仍走 `UsageService` 的失败预算与熔断语义：episode 开启时不自动重开；只读确认不得用 `resetFailureBudget: true` 绕开熔断。
- 轻量读取的 live-only 规则不变：只有 `FetchResult.isLive == true` 且 5 小时窗口有 `resetsAt` 才算 `.live`，其他一律 `.noEvidence`。
- 第一次确认已前移 ≥ 60 秒仍立即结束并跳过第二次；其他情况仍等 5 秒做第二次轻量读取。
- 不改变 CLI 参数、120 秒超时、terminate grace、同 Profile 去重、A/B 并发、2 秒／5 秒等待时长和退出清理。

### 3.2 前值 live 标记

- 点火开始时同时记录前值时间和前值是否为实时：`previousFiveHourReset: Date?` 与 `previousWasLive: Bool`。
- 前值是否实时取自点火瞬间该 Profile 的 `display`：`.live` 为真，其他为假。
- 前值为 nil 或非实时时，轻量读取仍用于更新卡片，但最终分类固定为「请求成功，暂无法确认」，不计算差值；只有存在实时前值时才允许判定「新窗口已确认」或「请求成功，窗口未变化」。
- 卡片在点火结果旁不新增状态色：前值非实时不改变三态颜色语义。

### 3.3 时间差展示

- 新增纯函数：输入点火前时间和确认使用的实时后值，输出前移秒数 `TimeInterval?`；任一端缺失或后值早于前值时返回 nil，不展示负数。
- 卡片 footer 的点火结果后追加差值：确认态显示如 `新窗口已确认 · +6小时12分`；未变化态显示如 `请求成功，窗口未变化 · +0秒` 或实际小幅前移如 `+32秒`；暂无法确认态不追加差值。
- 差值文字使用固定中文单位：≥ 1 小时显示 `+X小时Y分`，≥ 1 分钟显示 `+X分Y秒`，否则显示 `+X秒`；不展示毫秒。
- 差值展示不得改变卡片 416 × 129 pt 尺寸、footer 单行与尾部省略规则；超长时点火结果优先完整，差值部分先被省略。
- 辅助功能值同步包含差值，措辞与可见文字一致。

### 3.4 点火历史

- 每个 Profile 保留最近 3 次点火记录：结果分类、完成时间、前移秒数（可空）。
- 历史只存内存运行态，不进 UserDefaults、不进缓存文件、不进日志；应用重启即清空。
- 卡片 footer 仍只显示最近一次结果与差值；历史通过点火结果的帮助文本（tooltip）展示，格式为每行 `MM-dd HH:mm 结果 · 差值`，无差值时只写结果。
- 不新增点火历史面板、LaunchAgent 管理或 Fire All；最近 3 条历史仍只存内存和 tooltip。

### 3.5 每日多时点点火计划

- 设置页为 OpenAI A、OpenAI B、Command Code 分别列出计划；每个目标可添加多个本地墙上时间，每条有勾选、时间和删除操作。
- 新增条目默认不启用；只有用户勾选后才会触发真实请求。
- 应用启动、每 30 秒 tick、睡眠唤醒和系统时钟改变时评估到期条目；错过时间最多补跑 10 分钟，更旧的不补跑。
- 每条以当天的计划时刻做持久化去重，重画、重复 tick、唤醒或应用重启均不得重复执行同一次。
- 同一目标的已启用时间间隔小于 5 小时时显示橙色警告，但不禁止保存。
- 同一目标正在点火时不叠加请求；暂时忙的条目在 10 分钟窗口内可由后续 tick 再次尝试。

### 3.6 Command Code 点火

- 详情卡提供「5 小时点火」；手动点火必须先显示固定确认对话框，说明会调用官方 CLI 并消耗少量额度。
- 定位官方 `command-code` 可执行文件并用 `Process.executableURL` 直接启动，不经 shell；固定使用 `--no-auto-update --no-session --no-skills --skip-onboarding --permission-mode plan --max-turns 1 --model deepseek/deepseek-v4-flash --print "Reply exactly: OK"`。
- 子进程使用隔离临时 `HOME`，不读取用户级 Command Code 配置或认证；Key 只放入子进程环境，stdout/stderr 持续读取后丢弃。
- 应用自有 HTTP 客户端仍禁止所有模型端点；模型请求仅由这个经授权的官方 CLI 路径发起，不用于验证 Key。
- CLI 成功后使用 Command Code `credits` 端点进行 2 秒／5 秒的两次最多确认，套用与 OpenAI 一致的 live 前值、60 秒阈值、三态、差值和最近 3 条历史。
- 手动点火允许 Keychain 交互；定时点火禁止弹出 Keychain 授权界面。缺 Key、CLI 不存在、启动失败、非零退出和超时都使用固定脱敏结果。

## 4. 刷新与功耗优化

### 4.1 详情页 tick 降频

- `clockTimer` 从每 1 秒改为每 30 秒 `tick += 1`；唤醒与系统时钟变化仍立即 `tick += 1`。
- 菜单栏倒计时绘制不受影响：`MenuBarLabelView` 仍以 `Date()` 为当前帧时钟按需计算，不依赖 tick 频率。
- 详情页 Header 的全局更新行、相对时间文案的刷新粒度变为 30 秒；这是明确接受的显示延迟，不做逐秒补偿。
- `StatusItemController.noteContentMayHaveChanged` 的签名比较逻辑不变；tick 降频后其调用频率同步下降。

### 4.2 ChatGPT 动态退避

- 定时轮询间隔按最近重置时间动态选择：任一 Profile 的 5 小时或周重置时间在 10 分钟内到达时用 30 秒间隔，否则用 120 秒间隔。
- 首次启动与无数据时用 60 秒间隔，与 1.3.1 一致，不因退避延迟首屏。
- 退避只改变定时器触发频率，不改变手动刷新、开面板补刷（30 秒阈值）、失败熔断与逐个发布语义。
- 定时器重排必须幂等：间隔变化时重建 timer，间隔不变时不重建，避免重复订阅。

### 4.3 Command Code 辅助接口降频

- `summary` 与 `subscriptions` 分别保存值和最后成功时间，自动刷新周期从 5 分钟降为 15 分钟；`credits` 每次必读，仍是连接状态的唯一依据。
- 辅助缓存以 API Key 的完整 SHA-256 摘要隔离，公开账号标签继续使用短指纹；缓存中不保存原始 Key。两个辅助接口分别判断复用或请求，不共享时间戳。
- 单路失败时保留该路旧值并标记缓存，不推进成功时间，下一轮继续重试；手动刷新与重连强制刷新两路辅助接口。
- `ProviderUsage` 持久化 summary/subscription 的可选组件新鲜度；旧缓存无需迁移即可解码。UI 对套餐、统计和使用到缓存辅助字段的月度行分别显示缓存语义，5 小时与周额度仍保持本次 credits 的实时状态。
- 强制策略随具体读取任务传递。自动读取进行中收到同代手动 force 时，先等待自动读取完成，再补一次强制全量读取；不同凭证代次不合并，旧代结果不得提交。
- 凭证状态仍只由 `credits` 决定；辅助 401/403 不暂停凭证。

### 4.4 菜单栏宽度缓存

- `StatusItemController` 缓存 `widths` 的测量来源签名：签名不变时不重建 `NSHostingView` 实测，直接复用上次宽度。
- 签名沿用 `menuBarSizeSignature`（模式、文案、警告标记），倒计时不参与签名。
- fallback 宽度仅在首次测量前使用，逻辑不变。

### 4.5 唤醒后探活刷新

- 监听到 `NSWorkspace.didWakeNotification` 时，除立即 `tick += 1` 外，并行检查两个 Profile。探活只使用现有运行中的 app-server，执行 `handshake + rateLimits/read`，不读身份、不启动或重启子进程。
- 成功则更新该 Profile 的实时额度与已知归属缓存；失败则关闭失效 client，并只让该 Profile 进入普通刷新，继续使用原有一次重启预算。
- failure episode 已开启、已有读取进行中或服务已停止时返回 suppressed，不绕开熔断、不叠加请求。
- 唤醒检查与定时轮询互斥：唤醒后 30 秒内的定时轮询跳过一次，避免重复请求。

## 5. R2 测试维护修复

- `CommandCodeAccessibilityTests.testTheSettingsEntryKeepsItsOwnElementAndPressAction`：每次 `host` 后重新从 `AXUIElementCreateApplication(getpid())` 获取窗口，只遍历本次新窗口；切换状态前关闭上一扇窗口。
- `UsagePanelView.swift` 第 720 至 721 行注释按实测修正：合并后入口元素与名称消失，`AXPress` 在单按钮容器形态下仍可能转发动作。
- `IMPLEMENTATION_REPORT.md` 对 AX 用例的摘要按实际实现修正：按名称查找元素并直接执行 `AXPress`，非查找 `AXButton`。
- 以上三项不改变生产行为，只修正测试与文档。

## 6. 保持不变

- 详情页保持 440 pt 单列、卡片顺序、间距、颜色和进度条含义；Command Code 卡片由 162 pt 增至 176 pt，四卡页由 552 pt 增至 566 pt，只显示 Command Code 时由 498 pt 增至 512 pt。
- 菜单栏 A/B/DeepSeek 文案、字号、时间轨道、空间降级不变。
- OpenAI 点火的三态文案、颜色、60 秒阈值、真值表、2 秒／5 秒等待、CLI 参数、120 秒超时和终止策略不变。
- 设置页改为固定 520 × 700 pt，内部使用一个有界滚动区承载可增长的点火计划列表。
- DeepSeek 余额解析、Keychain、显示开关、状态页读取不变。
- 应用 HTTP 客户端不新增网络端点，不调用模型端点验证 Key；Command Code 点火的官方 CLI 模型请求是用户明确授权的窄例外。
- 不读取全局 Codex／Claude 配置或认证文件，不读取浏览器会话。
- 不把 API Key、OAuth token、Cookie、邮箱、真实余额、原始响应、子进程输出、点火历史写入源码、日志、文档、fixture 或截图。

## 7. 明确非目标

- 第三个 Profile、Profile 重命名、隐藏或路径编辑。
- Fire All、点火历史面板和 LaunchAgent 管理。
- 修改详情页宽高、卡片布局或继续压缩字号。
- Apple Developer ID、公证、自动更新或安装器。
- 新服务、新端点、新通知和诊断导出。
- 修改 `docs/archive/v1.0/` 或覆盖历史版本结论。

## 8. 完成定义

1. 轻量确认读取有确定性自动测试：确认路径不调用 `account/read`，live-only 规则与 1.3.1 一致。
2. 前值 live 标记与差值展示有单测与渲染断言：边界 59 秒／60 秒差值正确，暂无法确认态无差值，卡片尺寸不断言变化。
3. 点火历史有单测：保留最近 3 次，重启清空（进程内新实例即空），tooltip 格式固定。
4. 点火计划有确定性测试：三个目标、多时间、勾选、持久化去重、10 分钟补跑、跨午夜小于 5 小时警告。
5. Command Code 点火有 fake CLI 和 fake transport 测试：固定参数、隔离环境、输出丢弃、超时回收、手动／定时 Keychain 策略、credits-only 确认、差值和历史。
6. tick 降频、动态退避、辅助降频、宽度缓存、唤醒检查均有确定性自动测试，不依赖真实睡眠与长时间等待。
7. R2 三项修正完成，注释与报告措辞与实测一致。
8. 全量测试、Release 构建、严格签名和退出后子进程清理通过。
9. 独立 GUI harness 的真实 AX 树确认入口独立、名称正确且一次 `AXPress` 只触发一次；真实签名包界面确认详情页、设置计划和 Command Code 点火 footer 无截断、无状态歧义。
10. 用户触发一次真实睡眠/唤醒，确认 30 秒内恢复、无重复刷新风暴、无账号串用和无孤儿 app-server；未完成不得标记为可发布。
11. 真实 Command Code 手动点火已在签名包内由用户确认成功；仍需执行一次短时定时点火，确认窗口被开启、没有重复请求，且无凭证弹窗风暴。
12. Git 提交、推送、标签或 GitHub Release 都必须另有用户明确授权。

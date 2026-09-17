# 1.3.0 需求

## 1. 版本目标

将 Minget 从单一 Codex 账号监控扩展为两个隔离 ChatGPT 账号的额度监控，并增加可控的菜单栏数据来源和每账号手动点火。

本版本只交付以下四项：

1. 同时读取并展示两个 ChatGPT 订阅账号的 5 小时额度、周额度、重置时间、套餐和账号标识。
2. 在详情页分别展示两个 ChatGPT 账号，两个账号互不覆盖、互不串缓存。
3. 在设置中选择系统菜单栏显示账号 A、账号 B 或 DeepSeek；一次只显示一个来源。
4. 为两个 ChatGPT 账号分别提供“5 小时点火”按钮，以与既有脚本相同的固定 Codex 参数直接运行官方 CLI，但不产生 raw log。

## 2. 已核实基线

- 当前应用版本为 `1.2.1`，应用层只有一个 `UsageService`、一个 `UsageDisplay` 和一套 Codex 菜单栏内容。
- `JSONRPCClient` 已支持为子进程传入独立环境，但生产 `UsageService` 尚未把不同 `CODEX_HOME` 传给不同的 `codex app-server`。
- `UsageCache` 已能按 Codex 账号标识保存快照，但“最后一次账号”仍是全局单值，不能直接支撑两个长期并存的 Profile。
- `ProviderCache` 已按 `platform + accountID` 隔离 DeepSeek 和 Command Code 数据。
- 1.2.1 详情页为窄幅单列；首轮 1.3.0 实现误改成 720 点双列并在真实屏幕上越界。最终 1.3.0 收窄为 440 点单列固定布局，继续禁止滚动，并在一页内容纳两个 ChatGPT 卡片和两个服务卡片。
- 本机已有两个独立目录：`~/.codex-minget-a` 和 `~/.codex-minget-b`。本版本只把目录作为 `CODEX_HOME` 传给 Codex 子进程，不读取其中的 `auth.json`。
- `~/.local/bin/minget-fire a|b|all` 已经完成真实请求验证，也确认 Luna、`reasoning=none`、read-only sandbox 和两个隔离 `CODEX_HOME` 可行。该脚本会记录完整 CLI 输出和 session id，因此 1.3.0 的应用内手动点火不调用脚本，只复用同一组固定 CLI 参数；现有脚本继续供 LaunchAgent 使用并保持不动。
- `com.minget.chatgpt-fire` LaunchAgent 已存在。本版本不修改它的时间表和加载状态。

## 3. Account Profile 模型

新增可扩展的 `ChatGPTAccountProfile`。1.3.0 固定提供两个只读 Profile，不提供新增、删除、改名或路径编辑界面；业务逻辑使用稳定 ID，不依赖数组位置。

每个 Profile 恰好包含：

- `id`：稳定、非敏感标识，固定为 `chatgpt-a`、`chatgpt-b`。
- `displayName`：详情页和设置页名称。
- `shortLabel`：菜单栏短标签，固定为 `A`、`B`，最长 1 个可见字符。
- `codexHomeRelativePath`：相对当前用户主目录的路径，固定为 `.codex-minget-a`、`.codex-minget-b`。

首个 1.3.0 迁移默认建立两个 Profile：

| Profile | 默认名称 | 菜单栏短标签 | `CODEX_HOME` |
| --- | --- | --- | --- |
| `chatgpt-a` | Codex 账号 | A | `~/.codex-minget-a` |
| `chatgpt-b` | Hermes / OpenClaw 账号 | B | `~/.codex-minget-b` |

默认值不得包含 `/Users/example` 等硬编码绝对路径。运行时使用 `FileManager.homeDirectoryForCurrentUser` 解析。两个 Profile 始终启用并参与刷新。

## 4. 双账号额度读取

### 4.1 进程隔离

- 每个启用的 Profile 拥有独立的长生命周期 `UsageService` 和独立的 `codex app-server` 子进程。
- 启动子进程时复制当前安全环境并仅覆盖该 Profile 的 `CODEX_HOME`。
- 直接使用 `Process` / `JSONRPCClient` 启动已定位的 `codex`，不得经过 `/bin/sh`、`zsh -c` 或字符串拼接命令。
- 一个账号失败、超时、未登录或正在重启时，不得阻塞另一个账号的刷新。
- 应用退出时必须对两个服务都执行有界 drain，确认两个子进程均已停止和回收。

### 4.2 Profile 级状态

每个 Profile 独立维护：

- `UsageDisplay`
- `UsageService.ConnectionState`
- `CodexAccount`
- `isRefreshing`
- 最近成功时间、错误分类和缓存状态
- 点火运行状态

不得继续用单一 `displayState`、`connectionState`、`codexAccount` 代表全部 ChatGPT 账号。

### 4.3 缓存归属

- 将 Codex 缓存升级为 Profile 级命名空间，绑定 `profileID + accountID + snapshot`。
- 每个 Profile 有独立的 last-known account，不再共享 `UsageMonitor.lastAccountID.v2`。
- A 的缓存不得在 B 的卡片或菜单栏出现，B 同理。
- 外部重新登录导致同一 `CODEX_HOME` 换号后，首次成功的 `account/read` 必须替换该 Profile 的归属；旧账号缓存不能继续作为新账号的当前数据。
- 旧 1.2.1 缓存在升级后暂不展示。账号 A 第一次成功完成 `account/read` 后，只有 v2 缓存的 accountID 与账号 A 实际 accountID 完全相同才复制到 `chatgpt-a` 的 v3 项；不相同或缺失时立即删除 v2 项。账号 B 永远不接收 v2 缓存。

## 5. 详情页

### 5.1 固定尺寸和结构

- 详情页禁止使用 `ScrollView`、`List`、`NSScrollView` 或任何会出现滚动条的容器。
- 页面固定宽度为 `440 pt`，外边距 `12 pt`，纵向间距为 `6 pt`，可用内容宽度为 `416 pt`。
- 顶部 Header 固定高度 `36 pt`，保留产品名、版本、全局刷新和设置入口。
- 卡片固定为单列，从上到下依次为账号 A、账号 B、DeepSeek、Command Code；一排只允许一张卡片。
- 两张 ChatGPT 卡片均为 `416 × 129 pt`，DeepSeek 为 `416 × 48 pt`，Command Code 为 `416 × 162 pt`。
- 两张服务卡片都显示时页面为 `440 × 552 pt`；仅 Command Code 为 `440 × 498 pt`；仅 DeepSeek 为 `440 × 384 pt`；两者都隐藏为 `440 × 330 pt`。
- 菜单栏弹层和普通详情窗口使用同一尺寸和同一 `UsagePanelView`。显示偏好变化时，已经打开的普通详情窗口立即调用 `setContentSize` 更新到上述尺寸，不留空白、不截断。
- 弹层以菜单栏状态按钮的水平中点为锚点；无法严格居中时优先保证页面完整位于当前屏幕可见区域，当前屏幕无法容纳时改用普通详情窗口。

### 5.2 ChatGPT 卡片

- 每张卡片固定展示：Profile 名称、连接/缓存状态、套餐、实际账号邮箱、5 小时额度、周额度、两个重置时间、可用 reset credits、点火结果和“5 小时点火”按钮。
- 卡片 Header 左侧显示 `28 pt` OpenAI Blossom、Profile 名称和套餐，右侧显示点火按钮；连接状态和邮箱占 Header 下方一行。
- 5 小时和周额度各使用两行：第一行是额度剩余轨道和“剩余 N%”，第二行是重置时间轨道和重置时刻。5 小时必须为 5 段，周额度必须为 7 段，恢复 1.2.1 的视觉和信息层级。
- 5 小时与周额度两个窗口块之间使用 `4 pt` 间距，其他相邻区域保持 `1 pt`，让两个周期清晰分组而不过度增加高度。
- reset credits 和点火结果并列在 Footer，同为单行；长文本尾部省略。邮箱中间省略并支持选择复制。
- 点火按钮固定标题为“5 小时点火”；运行时改为“点火中…”并禁用。

### 5.3 服务卡片

- DeepSeek 和 Command Code 继续遵守各自详情显示开关。
- DeepSeek 使用单行横向卡片；Logo、wordmark、连接状态、可点击服务状态与余额位于同一行。多币种最多横向显示 3 项，极端宽度不足时完整保留主币种金额并把其余合并为“另有 N 个币种”，不得合计或截断金额。
- Command Code 固定显示三条额度窗口和三行统计摘要。每个额度窗口必须同时显示额度剩余轨道和重置时间轨道；5 小时 5 段、周额度 7 段、本月为无刻度连续轨道。缺失项用 `—`，禁止通过换行扩张卡片。
- Command Code 主轨道使用 `remaining / limit`，亮色右端随消耗向左收缩；禁止继续使用 `used / limit` 的向右增长效果。
- Command Code 三个窗口块之间使用 `4 pt` 间距；额度右侧只显示 `$余额 / $总计`，不重复“剩余”和百分比；5 小时与周只显示绝对重置日期时间，本月保留相对剩余天数和日期。
- 所有动态状态和错误文字最多两行，超出后尾部省略；完整固定错误分类在辅助功能文本和设置页保留。

## 6. 菜单栏来源选择

### 6.1 选择规则

设置页新增“菜单栏显示”单选项，一次只允许选择：

- ChatGPT 账号 A
- ChatGPT 账号 B
- DeepSeek

选择结果持久化为稳定 Profile ID 或明确的 provider 标识，不保存数组下标。首次升级默认选择账号 A，以保持 1.2.1 行为。

设置页固定为 `520 × 600 pt` 且不使用滚动容器。“菜单栏显示”使用纵向 radio-group Picker，顺序固定为账号 A、账号 B、DeepSeek。DeepSeek 被选中且存在多个币种时，在其下方显示第二个币种 Picker。服务管理采用单开 accordion，DeepSeek 和 Command Code 的连接表单同一时间最多展开一个。

### 6.2 ChatGPT 菜单栏内容

- 保留现有完整、紧凑两档布局和 5 小时/周重置时间条。
- 完整模式固定格式：`A 5H 78% | W 42%` 或 `B 5H 78% | W 42%`。
- 紧凑模式固定格式：`A 78% 42%` 或 `B 78% 42%`。
- 两种模式都保留 5 小时和周重置时间条，短标签使用户知道当前显示的是哪个账号。
- 警告、缓存和未知重置时间规则继续生效。
- 选中 Profile 无实时或缓存数据时，完整模式固定显示 `A 5H — | W —` / `B 5H — | W —`，紧凑模式显示 `A — —` / `B — —`，并使用一个前置警告标记；不得静默切换账号。

### 6.3 DeepSeek 菜单栏内容

- 显示 `DeepSeek` 短标识和官方余额接口返回的余额，不显示 5 小时/周重置条。
- 单币种直接显示该币种余额。
- 多币种不得换算或合计。选择优先级固定为：已保存且仍存在的币种 → `CNY` → `USD` → 币种代码升序第一项 → 币种未确认项。设置页允许用户改选当前响应中存在的币种。
- 菜单栏优先显示 `available`，没有 `available` 时显示 `total`，与详情页金额语义保持一致。
- 完整和紧凑模式的语义文字均为 `DS CNY 123.45`，不显示汉字“余额”。完整模式使用 13 pt medium 与更宽词间距，紧凑模式使用 12 pt medium 与较窄词间距。币种缺失时使用 `DS — 123.45`，金额固定两位小数但不修改底层 `Decimal`。
- 有缓存时保留同一金额文字并增加一个前置警告标记；无任何可归属余额时固定显示 `DS —` 并增加一个前置警告标记。不得显示 `0` 冒充余额。
- 刘海空间判断仍采用完整、紧凑和打开详情窗口的既有降级机制，DeepSeek 需要自己的宽度测试样例。

## 7. 手动点火

### 7.1 调用边界

- 每个 ChatGPT 卡片提供一个独立按钮，按钮把对应 Profile 交给 `ChatGPTFireService`。
- `ChatGPTFireService` 使用 `CodexLocator` 定位官方 `codex` 可执行文件，以 `Process.executableURL` 直接启动，不经过 shell。
- 参数固定为：`exec --ephemeral --sandbox read-only --skip-git-repo-check -C <临时工作目录> -m gpt-5.6-luna -c model_reasoning_effort="none" "Reply exactly: OK"`。临时工作目录固定为系统临时目录下的 `minget-fire`，不存在时由应用创建。
- 子进程环境使用当前环境副本并覆盖当前 Profile 的 `CODEX_HOME`。不读取该目录内容。
- Codex CLI 无法定位时按钮保持可见并显示固定分类错误。
- 同一 Profile 点火进行中时禁用其按钮，第二次调用直接返回 `.alreadyRunning`；A 和 B 可以互不阻塞地同时执行。
- 单次点火超时固定为 `120 秒`。超时先向本次脚本子进程发送 terminate，等待 `3 秒`，仍未退出时只对该 PID 发送 `SIGKILL` 并回收。
- 不读取或解析 `auth.json`，不读取现有浏览器 Cookie、密码或会话。

### 7.2 交互与结果

- 点击后使用 `confirmationDialog`，标题固定为“启动 5 小时额度窗口？”，正文固定为“将通过该账号执行一次真实 Codex 请求，会消耗少量额度。Minget 不会读取账号认证文件。”，主按钮为“确认点火”，取消按钮为“取消”。
- 运行中显示“点火中…”，结束后显示固定分类结果：成功、Codex CLI 不可用、进程启动失败、退出码失败、超时。
- 不把 Codex CLI 原始 stdout/stderr、session id、prompt、token 或认证材料写入 Minget 日志、UserDefaults、测试快照或文档。
- `exit 0` 只表示点火请求执行成功。成功后等待 `2 秒`，强制刷新对应 Profile；第一次没有取得实时结果（包括只得到缓存）时，再等待 `5 秒` 重试一次。只有 `FetchResult.isLive == true` 且新的 5 小时 `resetsAt` 比点火前晚至少 `60 秒`，才显示“新窗口已确认”。否则显示“请求成功，窗口未变化”。
- 应用退出时必须显式终止和回收仍在运行的点火子进程；取消 Swift `Task` 不能代替终止 `Process`。
- 点火不能删除、覆盖、重新登录或修复任何 Codex 认证目录。

固定结果文案如下，不允许显示原始进程文本：

| 结果 | 卡片文案 |
| --- | --- |
| `.requestSucceededWindowConfirmed` | 新窗口已确认 |
| `.requestSucceededWindowUnchanged` | 请求成功，窗口未变化 |
| `.codexCLINotFound` | Codex CLI 不可用 |
| `.launchFailed` | 点火进程启动失败 |
| `.nonZeroExit` | 点火请求失败 |
| `.timedOut` | 点火请求超时 |
| `.alreadyRunning` | 该账号正在点火 |

### 7.3 与现有自动点火的关系

- 保留现有 LaunchAgent 和外部脚本，不在 1.3.0 中生成、编辑、bootstrap、bootout、删除或调用该 plist/脚本。自动点火继续走外部脚本，应用内手动点火走 `ChatGPTFireService`。
- 1.3.0 不展示“自动点火已开启”之类结论，除非以后实现对实际 launchd 状态的完整查询。
- 本版本不新增 `Fire All`，不读取旧 raw log 作为产品状态，也不实现点火历史。

## 8. 安全与隐私边界

- 项目现有凭证规则在 1.3.0 中增加一个窄例外：允许把用户配置的隔离目录作为 `CODEX_HOME` 传给官方 Codex CLI 子进程；Minget 自身仍禁止打开、解析、复制、显示或上传任何 Codex 配置或认证文件。
- 源码、文档、日志、测试 fixture、截图和 UserDefaults 不得出现 OAuth token、API Key、Cookie、原始认证 JSON、真实邮箱、真实余额或真实 session id。
- 公开截图必须使用脱敏示例数据，并明确标注为展示副本。
- 诊断只记录 Profile ID、固定错误分类、时间和自有子进程生命周期，不记录子进程原始输出。
- 点火功能是明确的模型请求例外，只能由用户点击已知按钮触发；定时点火继续由现有外部 LaunchAgent 负责，不纳入 Minget 网络层。

## 9. 迁移和兼容

- 1.2.1 升级后默认菜单栏仍展示账号 A 的 Codex 额度。
- DeepSeek、Command Code 的 Keychain 项、显示开关、缓存和接口行为不变。
- 不修改 `docs/archive/v1.0/`。
- 不修改或清理 `~/.codex-minget-a`、`~/.codex-minget-b`、`~/.local/bin/minget-fire` 和现有 LaunchAgent。
- Profile 配置在 1.3.0 中是代码内固定值，不写入 UserDefaults。菜单栏来源或 DeepSeek 币种偏好损坏时回退到账号 A，不扫描用户目录寻找其他账号。

## 10. 明确非目标

- 自动点火开关和定时表编辑。
- `Fire All` 按钮。
- 睡眠唤醒或 `pmset` 配置。
- Codex 登录、退出、换号或认证修复。
- 读取点火 raw log、点火历史、token 统计。
- 新增第三个 ChatGPT 账号的 UI；底层模型应允许以后扩展。
- 新增 Command Code 或 DeepSeek 网络端点，或改动既有 Keychain 存储。允许在现有 subscriptions 响应中按真实字段补充解析可选 `currentPeriodStart`，不得猜测计费周期起点。
- 发布、推送、打标签或创建 GitHub Release。

## 11. 完成定义

只有在以下证据全部具备后，1.3.0 才能进入用户验收：

1. 新增测试全部通过，旧测试无回归。
2. Release 构建和严格签名通过。
3. 两个真实 `CODEX_HOME` 同时读取到各自账号和额度，互换菜单栏来源时无串号。
4. DeepSeek 真实余额能被选中显示，失败和多币种场景不伪造数字。
5. A、B 两个点火按钮分别完成一次真实执行，原始子进程输出没有进入应用日志。
6. 点火后窗口变化与未变化两种结果都按证据准确显示。
7. 三次完整退出/重启后无遗留 `codex app-server` 子进程，缓存仍按 Profile 隔离。
8. 用户确认详情布局、菜单栏切换和两个点火按钮的真实界面行为。
9. 详情页视图树和 AppKit 宿主中不存在任何滚动容器，440 × 552 / 498 / 384 / 330 四种状态均无截断、无横向越界。
10. 冷启动不出现空设置窗口；弹层在菜单栏图标可用时以其水平中点为锚点，并完整位于屏幕可见区域。
11. 退出时无点火 `codex exec` 遗留子进程；缓存刷新不能被当作“新窗口已确认”的实时证据。

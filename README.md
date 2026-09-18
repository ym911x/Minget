# 明明有数 · Minget

[![CI](https://github.com/ym911x/Minget/actions/workflows/ci.yml/badge.svg)](https://github.com/ym911x/Minget/actions/workflows/ci.yml)

<img src="assets/brand/minget-app-icon-1024.png" alt="Minget M² Logo" width="128">

**你的 AI 使用，心里有数。**<br>
*Your AI usage, at a glance.*

Minget 是一个 macOS 菜单栏应用，用于集中查看两个隔离的 ChatGPT (Codex) 账号、DeepSeek 与 Command Code 的额度、余额和使用状态。

## v1.3.1 修订

- 两个 ChatGPT 账号的刷新仍同时启动，但任一账号一返回就立即发布自己的新状态，不再等待另一个账号。卡片顺序仍固定为账号 A、账号 B；整轮刷新状态仍在最后一个账号完成后才结束。
- 点火结果由两种细分为三种：`新窗口已确认`、`请求成功，窗口未变化`，以及证据不足时的`请求成功，暂无法确认`。只有点火前后都取得实时重置时间且前移 ≥ 60 秒才确认新窗口；缓存结果不再被当作“窗口未变化”。
- 第一次确认刷新已是实时前移时立即结束；其他情况（含第一次实时时间尚未变化）会再等 5 秒做一次只读刷新。第二次刷新只读取额度，不重复模型请求。
- Command Code 以 `credits` 为必须的主数据，`summary` 与 `subscriptions` 为可选辅助数据：辅助接口失败时，已取得的额度仍为实时，统计区显示`统计暂不可用 · Token — · 请求 —`，不推算总额或周期。
- Command Code 显示缓存数据时给出明确文字：套餐名后追加`· 缓存`，帮助文本给出最后成功时间；无套餐名时显示`缓存数据`。
- 修复 Command Code 卡片的辅助功能回归：卡片标题行不再整体合并，只合并 Logo、标题和状态文字，无数据时的「前往设置／查看设置」按钮保留为独立辅助功能按钮和 press 动作。

本版本是稳定性修补版。窗口尺寸、卡片顺序、额度语义、菜单栏格式和凭证安全边界与 1.3.0 相同。

## v1.3.0 修订

- 详情页同时显示两个 ChatGPT 账号卡片，各自绑定一个独立的 `CODEX_HOME` 与独立的 `codex app-server` 子进程，额度、套餐、账号和缓存互不串号。
- 设置页新增“菜单栏显示”单选项，可在账号 A、账号 B 与 DeepSeek 之间切换；菜单栏一次只显示一个来源，ChatGPT 文案带账号短标签（`A 5H 78% | W 42%`），DeepSeek 显示官方余额接口返回的余额（`DS CNY 123.45`）且不显示重置时间条。
- 每张 ChatGPT 卡片提供独立的“5 小时点火”按钮：确认后应用直接执行官方 Codex CLI 的固定参数，用该账号的隔离目录作为 `CODEX_HOME`，只保留请求结果，不写 raw log、不调用 `minget-fire`。
- 详情页为 `440 pt` 宽的单列固定布局，一排一张卡片，顺序为 ChatGPT A、ChatGPT B、DeepSeek、Command Code；四张卡片全部显示时固定 `440 × 552 pt`，一页看完。设置页固定 `520 × 600 pt`。两者都不使用任何滚动容器。
- 应用改为显式 AppKit 启动，不再声明任何 SwiftUI `Scene`，冷启动只出现菜单栏图标，不再出现空的「设置」窗口。
- Minget 自身仍不打开、解析、复制或上传任何 Codex 配置或认证文件；它只把用户配置的隔离目录作为环境变量传给官方 CLI 子进程。

<img src="assets/screenshots/v1.3.0/detail-redacted.png" alt="Minget 1.3.0 双 ChatGPT 账号、DeepSeek 与 Command Code 详情页脱敏示例" width="520">

*1.3.0 详情页脱敏展示副本。邮箱、余额、额度、重置时间和用量均已替换为示例数据；界面布局来自用户确认的真实运行截图。*

自动测试 425 项通过（Core 325、App 100），Release 构建、严格签名与真实详情页验收通过。源码随 [Minget v1.3.0](https://github.com/ym911x/Minget/releases/tag/v1.3.0) 发布；真实 DeepSeek 菜单栏余额与 A/B 两次真实点火仍未执行，结果记录在 [1.3.0 验收台账](docs/versions/1.3.0/ACCEPTANCE.md)。

## v1.2.1 修订

- Command Code 卡片内的已用、剩余和成本金额统一显示到小数点后 2 位，底层 `Decimal` 数据不变。
- 移除 Command Code 卡片底部的单独更新时间；详情页顶部继续提供全局刷新状态。

<img src="assets/screenshots/v1.2.1/detail-redacted.png" alt="Minget 1.2.1 详情页脱敏示例" width="680">

*1.2.1 详情页脱敏展示副本。邮箱、余额和用量均已替换为示例数据，菜单栏已移除其他第三方程序图标。*

## v1.2.0 修订

- 详情页新增可隐藏的 Command Code 用量卡片。用户在应用内填写的 API Key 仅保存于 macOS Keychain，菜单栏仍只显示 Codex 的双额度。
- 卡片可展示 5 小时、周和月度信用额，以及 token、请求、成功率与成本摘要。字段缺失、接口变更或统计周期未知时明确显示不可用或未确认，不推算数字。
- 请求只允许 `https://api.commandcode.ai` 的三条只读 `/alpha` 用量路径，使用 `Authorization: Bearer` 与 `Accept: application/json`；模型端点、未列路径和跨域重定向均会在本地拒绝。

用户截图已确认真实 Command Code API Key 能返回额度与统计数据。字段与 Studio 的同刻对账仍记为待确认，真实账号、余额、成本和原始响应均未写入仓库。

## v1.1.2 修订

- 菜单栏只在完整和紧凑双额度模式之间切换；空间不足时也保留 `5H`、`W` 和两排重置时间条，无法容纳完整紧凑内容时打开详情窗口。
- OpenAI 详情卡在额度轨道下显示可用 earned rate-limit reset 数量；接口提供有效明细时追加最近到期时间。该信息只读，缓存数据不会冒充当前可用权益。
- DeepSeek 详情卡使用鲸鱼 Logo 与现有 `deepseek` 文字标识，真实余额与品牌同列右侧并垂直居中，连接和官方服务状态位于 Logo 下方。官方余额接口没有账号名称或邮箱字段，因此不生成账号占位信息。
- 详情页为固定整页布局，不显示滚动条；窗口会为启用的 DeepSeek 多币种余额预留完整高度。

1.1.2 真实界面已经验收。本页下方截图暂保留明确标注的 1.1.1 脱敏历史基线，避免把含个人账号和余额的实时画面直接写入仓库；后续如补充 1.1.2 公开截图，继续使用明确标注的脱敏副本。

## v1.1.1 界面（历史基线）

<img src="assets/screenshots/v1.1.1/menu-bar.png" alt="Minget 1.1.1 菜单栏额度与重置时间进度" width="236">

*菜单栏显示 5 小时额度和周额度；下方两排短线表示距离两个窗口重置的时间进度，不代表剩余额度。*

<img src="assets/screenshots/v1.1.1/detail-redacted.png" alt="Minget 1.1.1 详情页" width="680">

*详情页脱敏展示副本。账号已替换为示例地址，其余内容来自用户提供的 1.1.1 实测界面。*

<img src="assets/screenshots/v1.1.1/settings.png" alt="Minget 1.1.1 设置页" width="560">

*设置页实测截图。服务模块集中提供 OpenAI Codex 固定详情状态和 DeepSeek 显示、连接管理入口。*

长期定位：统一查看和管理个人 AI 服务使用状态、可用资源与成本信息的 macOS 菜单栏工具。

## 当前版本

- 当前版本：`1.3.1`
- 状态：双 Profile 完成即发布、点火确认三态、Command Code 辅助接口容错、缓存标识与辅助功能修复已实现；451 项自动化测试执行（Core 331、App 120），450 项通过、1 项跳过、0 项失败，Release 构建、严格签名和发布提交 CI 通过。源码发布页：[Minget v1.3.1](https://github.com/ym911x/Minget/releases/tag/v1.3.1)。真实界面、真实 DeepSeek 菜单栏余额、A/B 两次真实点火与机器重启复验仍待用户验收，详见 [1.3.1 验收台账](docs/versions/1.3.1/ACCEPTANCE.md)。
- 平台：macOS 13 及以上，Apple Silicon
- 发布记录：[CHANGELOG.md](CHANGELOG.md)
- 后续规划：[ROADMAP.md](ROADMAP.md)

## 已实现功能

- 同时监控两个隔离的 ChatGPT (Codex) 账号：各自独立的 `CODEX_HOME`、独立的长生命周期 `codex app-server` 子进程、独立的失败预算与独立的额度缓存。
- 菜单栏一次显示一个来源：ChatGPT 账号 A、ChatGPT 账号 B 或 DeepSeek，可在设置页切换并持久化；升级默认保持账号 A。
- ChatGPT 菜单栏文案带账号短标签与两排重置时间进度：完整 `A 5H 78% | W 42%`，紧凑 `A 78% 42%`，下方上排 5 段代表 5 小时、下排 7 段代表 7 天。
- DeepSeek 菜单栏条目显示官方余额接口返回的余额，不换算、不合计、不显示重置时间条：完整和紧凑模式均为 `DS CNY 123.45`，通过字号与词间距区分宽度；无可用余额时显示 `DS —` 并加一个前置警告标记，不显示 `0`。
- 检测状态项是否进入刘海遮挡区域，并在空间不足时从完整模式压缩为保留双额度与双时间条的紧凑模式；紧凑内容仍无法显示时打开详情窗口，不显示残缺文字。
- 点击菜单栏打开详情后，点击桌面或其他应用可立即收起弹层，同时保留原点击效果。
- 应用以显式 AppKit 入口启动，不声明任何 SwiftUI Scene；冷启动只出现菜单栏图标，不会出现空的设置窗口。弹层在显示前先确定内容尺寸，屏幕容纳不下整页时改用普通详情窗口，不会留下越界且无法移回的弹层。
- 详情页为 440 pt 宽的固定单列无滚动布局，一排一张卡片：ChatGPT A、ChatGPT B、DeepSeek、Command Code；四张全开时 `440 × 552 pt`，两张服务卡都隐藏时收缩为 `440 × 330 pt`，普通详情窗口立即同步调整尺寸。
- 每张 ChatGPT 卡片显示 Profile 名称、连接/缓存状态、套餐、实际账号邮箱、5 小时与周额度的**剩余额度轨道和各自的重置时间分段轨道**（5 小时 5 段、周 7 段）、可用重置次数、点火结果和“5 小时点火”按钮。
- 手动点火经固定确认对话框触发，应用直接执行官方 Codex CLI 的固定参数并丢弃子进程输出；结果区分“新窗口已确认”“请求成功，窗口未变化”和证据不足时的“请求成功，暂无法确认”。
- DeepSeek 卡片把 Logo、wordmark、连接状态、服务状态和余额放在同一行，横向最多显示 3 个币种金额，超过 3 个时第三项显示“另有 N 个币种”；不换算、不合计、不伪造 0。
- Command Code 卡片的三条额度轨道显示**剩余**（越用越短），右侧只显示“余额 / 总计”；每条下方各有一条重置时间轨道，5 小时与周只显示绝对重置时间，本月保留剩余天数。`credits` 失败按缓存或错误处理，`summary`/`subscriptions` 失败只影响统计区，并在缓存时显示套餐名后的`· 缓存`。
- 设置页固定 `520 × 600 pt`：菜单栏显示使用纵向 radio group，服务组列出两个只读 ChatGPT 行的 `CODEX_HOME` 尾段，DeepSeek 与 Command Code 管理表单单开 accordion。
- OpenAI 详情卡显示账号可用重置次数，并在服务提供有效到期明细时显示最近到期时间；缓存或字段不可用时明确显示不可用。
- 详情面板使用放大的 OpenAI Blossom 图标和 API 返回的 Codex 套餐类型；DeepSeek 可在设置中选择显示或隐藏，隐藏不会断开连接，也不会改变菜单栏来源。
- DeepSeek 卡片在同一水平线显示用户提供的鲸鱼图标、只保留 `deepseek` 的透明文字标识、状态和余额；状态页不可达时明确显示不可用。官方余额接口不提供账号名称或邮箱，因此不显示虚构账号信息。
- 详情页与设置页直接显示整页内容，不使用滚动容器或滚动条。
- 通过 DeepSeek 官方余额接口读取余额，API Key 保存在 macOS Keychain。
- Command Code API Key 仅由用户在应用设置页输入并存入 macOS Keychain；详情卡可隐藏但隐藏不会删除 Key 或停止既有刷新机制。
- 启动时清理旧版智谱 GLM 的应用内凭据、缓存与显示偏好；失败会在下次启动重试。
- 连接状态和数据缓存保存在本机，不上传到第三方服务。
- 支持手动刷新和既有自动刷新机制。

## 运行

```bash
./scripts/build.sh
open dist/Minget.app
```

开发调试：

```bash
swift run UsageMonitorApp
```

运行测试：

```bash
swift test
```

## 资料导航

- [架构与数据流](docs/ARCHITECTURE.md)
- [品牌规范](BRAND.md)
- [服务端点与取数依据](PROVIDER_ENDPOINTS.md)
- [参与贡献](CONTRIBUTING.md)
- [安全说明](SECURITY.md)
- [品牌权利说明](TRADEMARKS.md)
- [v1.0 归档索引](docs/archive/v1.0/README.md)
- [v1.0 最终验收](docs/archive/v1.0/acceptance/ACCEPTANCE.md)
- [v1.0.2 修订与验收](docs/versions/1.0.2/ACCEPTANCE.md)
- [v1.1.0 开发方案](docs/versions/1.1.0/DEVELOPMENT_PLAN.md)
- [v1.1.0 实施报告](docs/versions/1.1.0/IMPLEMENTATION_REPORT.md)
- [v1.1.1 需求与实施任务](docs/versions/1.1.1/REQUIREMENTS.md)
- [v1.1.1 实施报告](docs/versions/1.1.1/IMPLEMENTATION_REPORT.md)
- [v1.1.1 验收台账](docs/versions/1.1.1/ACCEPTANCE.md)
- [v1.1.2 需求](docs/versions/1.1.2/REQUIREMENTS.md)
- [v1.1.2 实施任务](docs/versions/1.1.2/IMPLEMENTATION_TASKS.md)
- [v1.1.2 实施报告](docs/versions/1.1.2/IMPLEMENTATION_REPORT.md)
- [v1.1.2 审核状态](docs/versions/1.1.2/REVIEW.md)
- [v1.1.2 验收台账](docs/versions/1.1.2/ACCEPTANCE.md)
- [v1.2.0 需求](docs/versions/1.2.0/REQUIREMENTS.md)
- [v1.2.0 实施任务](docs/versions/1.2.0/IMPLEMENTATION_TASKS.md)
- [v1.2.0 审核状态](docs/versions/1.2.0/REVIEW.md)
- [v1.2.0 验收台账](docs/versions/1.2.0/ACCEPTANCE.md)
- [v1.2.1 需求与验收](docs/versions/1.2.1/REQUIREMENTS.md)
- [v1.3.0 需求](docs/versions/1.3.0/REQUIREMENTS.md)
- [v1.3.0 实施任务](docs/versions/1.3.0/IMPLEMENTATION_TASKS.md)
- [v1.3.0 界面规格](docs/versions/1.3.0/UI_SPEC.md)
- [v1.3.0 实施报告](docs/versions/1.3.0/IMPLEMENTATION_REPORT.md)
- [v1.3.0 审核状态](docs/versions/1.3.0/REVIEW.md)
- [v1.3.0 验收台账](docs/versions/1.3.0/ACCEPTANCE.md)
- [v1.3.1 稳定性修补需求](docs/versions/1.3.1/REQUIREMENTS.md)
- [v1.3.1 实施任务](docs/versions/1.3.1/IMPLEMENTATION_TASKS.md)
- [v1.3.1 实施报告](docs/versions/1.3.1/IMPLEMENTATION_REPORT.md)
- [v1.3.1 审核状态](docs/versions/1.3.1/REVIEW.md)
- [v1.3.1 验收台账](docs/versions/1.3.1/ACCEPTANCE.md)
- [v1.3.1 发布说明](docs/versions/1.3.1/RELEASE_NOTES.md)
- [项目协作规则](AGENTS.md)

历史方案、任务单和审核报告均已冻结在 `docs/archive/v1.0`。后续版本的需求和审核记录使用新的文件，避免改写 v1.0 的基线资料。

## 开源与品牌

源代码采用 [MIT License](LICENSE)。`Minget`、`明明有数`、`M²` 及 Logo 是本项目的品牌标识，详见 [品牌权利说明](TRADEMARKS.md)。

当前本地构建使用项目自建的稳定代码签名身份，尚未经过 Apple Developer ID 公证。开发者可以从源码构建；面向普通用户的正式安装包将在签名和公证完成后提供。

---

## English

**Minget** is a macOS menu bar app for viewing two isolated ChatGPT (Codex) accounts, DeepSeek balances, and optional Command Code usage. Version 1.3.0 adds a second Codex account, a selectable menu bar source, and a per-account manual fire button; 1.3.1 publishes each account the moment it finishes, splits fire confirmation into three outcomes, and makes Command Code statistics optional so a failed summary cannot hide the credits.

### Features

- Monitors two isolated ChatGPT (Codex) accounts, each with its own `CODEX_HOME`, its own long-lived `codex app-server` child, its own failure budget, and its own usage cache.
- Shows exactly one menu bar source at a time — account A, account B, or DeepSeek — selectable in settings and persisted by stable identifier. Upgrading keeps account A.
- Labels the ChatGPT quota text with the account short label and keeps both reset-time rows: `A 5H 78% | W 42%` full, `A 78% 42%` compact. The compact fallback still includes both values; if even that cannot be rendered, the detail window opens.
- Shows the DeepSeek menu bar entry as an amount from the official balance endpoint, with no conversion, no summing, and no reset-time rows: `DS CNY 123.45` in both semantic modes, using larger typography and spacing in full mode. With nothing attributable it shows `DS —` and one warning marker, never a zero.
- Closes the detail popover when the user clicks the desktop or another app while preserving the original click.
- Uses a fixed, non-scrolling 440 pt single-column detail layout — one card per row: ChatGPT A, ChatGPT B, DeepSeek, Command Code. All four cards fit a 440 × 552 pt page; with both service cards hidden the page shrinks to 440 × 330 pt.
- Each ChatGPT card pairs every window's remaining-credit track with its own segmented reset-time rail (five segments for the five-hour window, seven for the weekly one).
- Command Code's credit tracks show *remaining* (shrinking from the right as credit is used) and only `balance / total` at the right. Five-hour and weekly rows use absolute reset times; the monthly row retains relative days.
- Starts as an explicit AppKit app with no SwiftUI scene, so a cold start shows only the menu-bar icon and never an empty settings window; the panel fixes its content size before it is shown and falls back to the detail window when the page cannot fit the screen.
- Each ChatGPT card shows the profile name, connection or cache state, the plan returned by `account/read`, the real account email, both quota windows, reset times, available reset credits, the last fire result, and its own fire button.
- Manual fire runs the official Codex CLI with a fixed argument list under that account's isolated `CODEX_HOME` and discards the child's output. It reports three separate outcomes: a confirmed new window, a request that succeeded while the window stayed put, and a request that succeeded with no live evidence to compare.
- Publishes each ChatGPT account's state as soon as that account returns, rather than holding a fast account behind a slow one.
- Places the DeepSeek logo, wordmark, connection state, service state, and balances on one line. It shows up to three currency amounts (currency code ascending, unnamed bucket last); beyond three the third slot becomes a fixed overflow line.
- Uses a fixed 520 × 600 pt settings page with a vertical radio group for the menu bar source, two read-only ChatGPT rows showing only the `CODEX_HOME` suffix, and single-open accordions for the DeepSeek and Command Code forms.
- Displays the read-only `rateLimitResetCredits.availableCount` value and, when supplied by the service, the nearest future expiry in the OpenAI detail card. Cached or missing fields remain explicitly unavailable.
- Lets users show or hide the DeepSeek and Command Code cards without disconnecting either, and independently of the menu bar source.
- Shows the complete detail page and the settings page in fixed-size surfaces without any scroll container or scrollbar.
- Reads DeepSeek balances through its official balance endpoint.
- Retires legacy GLM credentials, cache entries, and display preferences during startup.
- Keeps provider credentials in macOS Keychain. Minget never opens, parses, copies or uploads a Codex configuration or auth file; it only passes a user-configured isolated directory to the official CLI as `CODEX_HOME`.
- Checks menu bar visibility locally without model calls or token usage.

### Build and run

Requirements: macOS 13 or later, Apple Silicon, and Swift 5.9 or later.

```bash
./scripts/build.sh
open dist/Minget.app
```

Run the test suite with `swift test`. Real-interface and live-service evidence is recorded separately in the current acceptance ledger; a missing or unconfirmed provider field remains unavailable rather than replaced by a fixture.

The source code is available under the [MIT License](LICENSE). The Minget name, Chinese name, M² mark, and logo remain project brand identifiers; see [Trademark and Brand Notice](TRADEMARKS.md). The current local build uses a project-created stable signing identity and has not been notarized by Apple.

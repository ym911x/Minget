# 明明有数 · Minget

[![CI](https://github.com/ym911x/Minget/actions/workflows/ci.yml/badge.svg)](https://github.com/ym911x/Minget/actions/workflows/ci.yml)

<img src="assets/brand/minget-app-icon-1024.png" alt="Minget M² Logo" width="128">

**你的 AI 使用，心里有数。**<br>
*Your AI usage, at a glance.*

Minget 是一个 macOS 菜单栏应用，用于集中查看 OpenAI Codex 与 DeepSeek 的额度、余额和使用状态。

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

- 当前版本：`1.1.2`
- 状态：已完成菜单栏双额度兜底、OpenAI 可用重置只读展示和 DeepSeek 详情卡重排。301 项自动测试通过；Release 构建、严格签名和真实界面验收记录见 [1.1.2 验收台账](docs/versions/1.1.2/ACCEPTANCE.md)。GitHub 发布页：[Minget v1.1.2](https://github.com/ym911x/Minget/releases/tag/v1.1.2)
- 平台：macOS 13 及以上，Apple Silicon
- 发布记录：[CHANGELOG.md](CHANGELOG.md)
- 后续规划：[ROADMAP.md](ROADMAP.md)

## 已实现功能

- 菜单栏持续显示 Codex 的 5 小时额度和周额度，不再放置品牌图标。
- 额度文字下方显示两排重置时间进度：上排 5 段代表 5 小时，下排 7 段代表 7 天；亮区随重置时间临近从右向左缩退。
- 检测状态项是否进入刘海遮挡区域，并在空间不足时从完整模式压缩为保留双额度的紧凑模式；紧凑内容仍无法显示时打开详情窗口，不显示残缺的 `5H`。
- 点击菜单栏打开详情后，点击桌面或其他应用可立即收起弹层，同时保留原点击效果。
- 详情面板显示当前 Codex 账号、5 小时额度、周额度和 5/7 段重置时间进度。
- OpenAI 详情卡显示账号可用重置次数，并在服务提供有效到期明细时显示最近到期时间；缓存或字段不可用时明确显示不可用。
- 详情面板使用放大的 OpenAI Blossom 图标和 API 返回的 Codex 套餐类型；DeepSeek 可在设置中选择显示或隐藏，隐藏不会断开连接。
- DeepSeek 卡片同时显示用户提供的鲸鱼图标和只保留 `deepseek` 的透明文字标识；多币种余额与品牌同列靠右并垂直居中，连接与官方服务状态位于 Logo 下方；状态页不可达时明确显示不可用。官方余额接口不提供账号名称或邮箱，因此不显示虚构账号信息。
- 详情页直接显示整页内容，不使用滚动容器或滚动条。
- 设置页以单一“服务”模块集中展示 OpenAI Codex 固定详情显示与 DeepSeek 的显示、连接管理和诊断入口。
- 通过 DeepSeek 官方余额接口读取余额，API Key 保存在 macOS Keychain。
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
- [项目协作规则](AGENTS.md)

历史方案、任务单和审核报告均已冻结在 `docs/archive/v1.0`。后续版本的需求和审核记录使用新的文件，避免改写 v1.0 的基线资料。

## 开源与品牌

源代码采用 [MIT License](LICENSE)。`Minget`、`明明有数`、`M²` 及 Logo 是本项目的品牌标识，详见 [品牌权利说明](TRADEMARKS.md)。

当前本地构建使用项目自建的稳定代码签名身份，尚未经过 Apple Developer ID 公证。开发者可以从源码构建；面向普通用户的正式安装包将在签名和公证完成后提供。

---

## English

**Minget** is a macOS menu bar app for viewing OpenAI Codex usage and DeepSeek balances. Version 1.1.2 keeps both quota windows visible in every menu-bar mode, adds read-only earned reset information to the OpenAI detail card, and rebalances the DeepSeek card.

### Features

- Shows Codex five-hour and weekly limits in the menu bar without a leading brand mark. The compact fallback still includes both values and both reset-time rows; if even that content cannot be rendered, the detail window opens.
- Shows two segmented reset-time rows below the quota text: five hourly segments and seven daily segments. These rows represent time until reset, not quota remaining.
- Closes the detail popover when the user clicks the desktop or another app while preserving the original click.
- Displays the OpenAI Blossom mark, the plan returned by `account/read`, the active Codex account, quota tracks, and five-hour/seven-day reset-time segments in the detail panel.
- Displays the read-only `rateLimitResetCredits.availableCount` value and, when supplied by the service, the nearest future expiry in the OpenAI detail card. Cached or missing fields remain explicitly unavailable.
- Lets users show or hide the DeepSeek balance card without disconnecting it.
- Gives DeepSeek a full-width balance card with the wordmark beside its whale logo, vertically centered multi-currency balances on that same brand row, and connection plus official status below the logo. The official balance response has no account-name field, so no account identity is invented.
- Shows the complete detail page in a fixed-height surface without a vertical scroll container or scrollbar.
- Keeps connection management and diagnostics in a compact settings window.
- Reads DeepSeek balances through its official balance endpoint.
- Retires legacy GLM credentials, cache entries, and display preferences during startup.
- Keeps provider credentials in macOS Keychain.
- Checks menu bar visibility locally without model calls or token usage.

### Build and run

Requirements: macOS 13 or later, Apple Silicon, and Swift 5.9 or later.

```bash
./scripts/build.sh
open dist/Minget.app
```

Run the test suite with `swift test`. Version 1.1.2 passes 301 tests. Real-interface and live-service evidence is recorded separately in its acceptance ledger; a live account that omits reset fields is recorded as an unavailable sample rather than replaced by a fixture.

The source code is available under the [MIT License](LICENSE). The Minget name, Chinese name, M² mark, and logo remain project brand identifiers; see [Trademark and Brand Notice](TRADEMARKS.md). The current local build uses a project-created stable signing identity and has not been notarized by Apple.

# 明明有数 · Minget

[![CI](https://github.com/ym911x/Minget/actions/workflows/ci.yml/badge.svg)](https://github.com/ym911x/Minget/actions/workflows/ci.yml)

<img src="assets/brand/minget-app-icon-1024.png" alt="Minget M² Logo" width="128">

**你的 AI 使用，心里有数。**<br>
*Your AI usage, at a glance.*

Minget 是一个 macOS 菜单栏应用，用于集中查看 Codex、DeepSeek、智谱 GLM 等 AI 服务的额度、余额和使用状态。

![Minget v1.0.2 菜单栏显示](assets/minget-menubar-v1.0.2.png)

*v1.0.2 菜单栏实测截图。文字显示 5 小时额度和周额度；下方两排短线分别显示距离 5 小时窗口和周窗口重置的剩余时间。短线表达时间进度，不代表剩余额度。*

长期定位：统一查看和管理个人 AI 服务使用状态、可用资源与成本信息的 macOS 菜单栏工具。

## 当前版本

- 正式版本：`1.0.2`
- 状态：已完成实现、独立审核和用户真实界面验收
- 平台：macOS 13 及以上，Apple Silicon
- 发布记录：[CHANGELOG.md](CHANGELOG.md)
- 后续规划：[ROADMAP.md](ROADMAP.md)

## 已实现功能

- 菜单栏持续显示 Codex 的 5 小时额度和周额度，不再放置品牌图标。
- 额度文字下方显示两排重置时间进度：上排 5 段代表 5 小时，下排 7 段代表 7 天；亮区随重置时间临近从右向左缩退。
- 检测状态项是否进入刘海遮挡区域，并在空间不足时逐级缩短显示内容。
- 点击菜单栏打开详情后，点击桌面或其他应用可立即收起弹层，同时保留原点击效果。
- 详情面板显示当前 Codex 账号、5 小时额度和周额度。
- 通过 DeepSeek 官方余额接口读取余额，API Key 保存在 macOS Keychain。
- 通过应用内独立登录窗口连接智谱控制台，读取控制台实际返回的余额字段。
- 连接状态和数据缓存保存在本机，不上传到第三方服务。
- 支持手动刷新、自动刷新、开机启动和菜单栏样式设置。

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
- [项目协作规则](AGENTS.md)

历史方案、任务单和审核报告均已冻结在 `docs/archive/v1.0`。后续版本的需求和审核记录使用新的文件，避免改写 v1.0 的基线资料。

## 开源与品牌

源代码采用 [MIT License](LICENSE)。`Minget`、`明明有数`、`M²` 及 Logo 是本项目的品牌标识，详见 [品牌权利说明](TRADEMARKS.md)。

当前本地构建使用项目自建的稳定代码签名身份，尚未经过 Apple Developer ID 公证。开发者可以从源码构建；面向普通用户的正式安装包将在签名和公证完成后提供。

---

## English

**Minget** is a macOS menu bar app for viewing AI service usage, balances, and availability in one place. Version 1.0.2 adds reset-time indicators, simplifies the menu bar label, fixes popover dismissal, and prevents repeated Keychain authorization prompts.

### Features

- Shows Codex five-hour and weekly limits in the menu bar without a leading brand mark.
- Shows two segmented reset-time rows below the quota text: five hourly segments and seven daily segments. These rows represent time until reset, not quota remaining.
- Closes the detail popover when the user clicks the desktop or another app while preserving the original click.
- Displays the active Codex account in the detail panel.
- Reads DeepSeek balances through its official balance endpoint.
- Reads Zhipu GLM balances through an isolated in-app console session.
- Keeps provider credentials in macOS Keychain.
- Checks menu bar visibility locally without model calls or token usage.

### Build and run

Requirements: macOS 13 or later, Apple Silicon, and Swift 5.9 or later.

```bash
./scripts/build.sh
open dist/Minget.app
```

Run the test suite with `swift test`. Version 1.0.2 passes 359 tests.

The source code is available under the [MIT License](LICENSE). The Minget name, Chinese name, M² mark, and logo remain project brand identifiers; see [Trademark and Brand Notice](TRADEMARKS.md). The current local build uses a project-created stable signing identity and has not been notarized by Apple.

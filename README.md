# 明明有数 · Minget

[![CI](https://github.com/ym911x/Minget/actions/workflows/ci.yml/badge.svg)](https://github.com/ym911x/Minget/actions/workflows/ci.yml)

<img src="assets/brand/minget-app-icon-1024.png" alt="Minget M² Logo" width="128">

**你的 AI 使用，心里有数。**<br>
*Your AI usage, at a glance.*

Minget 是一个 macOS 菜单栏应用，用于集中查看 Codex、DeepSeek、智谱 GLM 等 AI 服务的额度、余额和使用状态。

![Minget v1.0 初始可用版菜单栏显示](assets/usagemonitor-menubar-v1.0.png)

*v1.0 初始可用版菜单栏实测截图。品牌升级后的菜单栏视觉符号为 M²。*

长期定位：统一查看和管理个人 AI 服务使用状态、可用资源与成本信息的 macOS 菜单栏工具。

## 当前版本

- 正式版本：`1.0.1`
- 状态：已完成首次可用版本验收
- 平台：macOS 13 及以上，Apple Silicon
- 发布记录：[CHANGELOG.md](CHANGELOG.md)
- 后续规划：[ROADMAP.md](ROADMAP.md)

## 已实现功能

- 菜单栏持续显示 Codex 额度，并检测状态项是否进入刘海遮挡区域。
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
- [项目协作规则](AGENTS.md)

历史方案、任务单和审核报告均已冻结在 `docs/archive/v1.0`。后续版本的需求和审核记录使用新的文件，避免改写 v1.0 的基线资料。

## 开源与品牌

源代码采用 [MIT License](LICENSE)。`Minget`、`明明有数`、`M²` 及 Logo 是本项目的品牌标识，详见 [品牌权利说明](TRADEMARKS.md)。

当前构建使用本机临时签名，尚未经过 Apple Developer ID 公证。开发者可以从源码构建；面向普通用户的正式安装包将在签名和公证完成后提供。

---

## English

**Minget** is a macOS menu bar app for viewing AI service usage, balances, and availability in one place. Version 1.0 supports Codex usage windows, DeepSeek balances, and Zhipu GLM console balances. Version 1.0.1 introduces the public Minget brand.

### Features

- Shows Codex five-hour and weekly limits in the menu bar.
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

Run the test suite with `swift test`. The current release passes 274 tests.

The source code is available under the [MIT License](LICENSE). The Minget name, Chinese name, M² mark, and logo remain project brand identifiers; see [Trademark and Brand Notice](TRADEMARKS.md). The current local build is ad-hoc signed and has not been notarized by Apple.

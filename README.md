# UsageMonitor

UsageMonitor 是一个 macOS 菜单栏应用，用于集中查看 Codex、DeepSeek 和智谱 GLM 的账户额度或余额。

## 当前版本

- 正式版本：`1.0.0`
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
open dist/UsageMonitor.app
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
- [服务端点与取数依据](PROVIDER_ENDPOINTS.md)
- [v1.0 归档索引](docs/archive/v1.0/README.md)
- [v1.0 最终验收](docs/archive/v1.0/acceptance/ACCEPTANCE.md)
- [项目协作规则](AGENTS.md)

历史方案、任务单和审核报告均已冻结在 `docs/archive/v1.0`。后续版本的需求和审核记录使用新的文件，避免改写 v1.0 的基线资料。

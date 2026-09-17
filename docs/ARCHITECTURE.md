# 架构与数据流

## 应用结构

明明有数 · Minget 是基于 Swift Package Manager 构建的 macOS 菜单栏应用。工程内部继续使用 `UsageMonitor` 标识，主要代码位于 `Sources`，测试位于 `Tests`。

| 模块 | 职责 |
| --- | --- |
| `UsageMonitorApp` | 应用生命周期、状态栏项目、菜单和设置入口 |
| `UsageMonitorCore` | 额度模型、刷新调度、状态管理和错误分类 |
| `Providers` | Codex、DeepSeek 与 Command Code 的取数实现及历史服务迁移 |
| `Security` | Keychain、敏感字段清理和日志保护 |
| `Views` | 详情面板、连接窗口和设置界面 |

## 多 ChatGPT Profile

1.3.0 起 Codex 不再是单一连接，而是两个隔离的账号 Profile。

| 类型 | 职责 |
| --- | --- |
| `ChatGPTAccountProfile` | 只读配置：稳定 ID、显示名、菜单栏短标签、相对 `CODEX_HOME` |
| `CodexProfileRuntime` | 单 Profile 运行态：service、display、connection、account、fetch/fire 状态 |
| `CodexProfilesCoordinator` | 拥有全部运行时，逐 Profile 刷新、并行停止 |
| `UsageService` | 单 Profile 的长生命周期 `codex app-server`、缓存策略与失败预算 |
| `UsageCache` | v3 `profileID + accountID` 命名空间，以及 v2→v3 一次性迁移 |
| `MenuBarPreferences` | 菜单栏来源（Profile ID 或 DeepSeek）与 DeepSeek 币种显示选择 |
| `ChatGPTFireService` | 手动点火：直启官方 Codex CLI，固定参数，丢弃子进程输出 |

配置与运行态分离：Profile 是常量值，运行态全部在 `CodexProfileRuntime` 内由锁保护。业务逻辑以稳定 ID 为键，不依赖数组位置，因此后续版本可以直接扩展第三个 Profile。

## 数据流

```mermaid
flowchart LR
    UI[菜单栏与详情面板] --> Store[UsageViewModel]
    Store --> Coord[CodexProfilesCoordinator]
    Coord --> A[Profile A / CODEX_HOME A]
    Coord --> B[Profile B / CODEX_HOME B]
    A --> AServer[codex app-server A]
    B --> BServer[codex app-server B]
    Store --> DeepSeek[DeepSeek 官方余额接口]
    DeepSeek --> Keychain[macOS Keychain]
    Store --> Fire[ChatGPTFireService]
    Fire --> CLI[官方 codex exec]
    Store --> Cache[本机缓存与偏好设置]
```

## 服务边界

### Codex

每个 Profile 连接一个本机 Codex app-server，读取该账号的标识和额度窗口。子进程环境是当前环境的副本，只覆盖该 Profile 的 `CODEX_HOME`；应用不打开、列出或解析该目录中的任何文件。任何一个 Profile 失败、超时或未登录都不会阻塞另一个。

菜单栏一次只显示一个来源，来源与显示偏好都只保存非敏感选择值。遮挡检查只读取本机屏幕和状态项位置，每 10 秒执行一次，不产生网络请求，也不消耗模型 token。

手动点火是本应用唯一的模型请求路径：由用户点击卡片按钮并经固定确认对话框触发，直接执行官方 Codex CLI 的固定参数，子进程输出持续 drain 后丢弃，不进入日志、缓存或界面。定时点火继续由外部 LaunchAgent 与 `minget-fire` 承担，应用既不调用也不修改它们。

### DeepSeek

应用调用 DeepSeek 官方余额端点。API Key 仅保存在 macOS Keychain，请求不会调用生成模型，因此不会产生模型 token 消耗。菜单栏选中 DeepSeek 时只显示该接口返回的单一币种金额，不换算、不合计。

### 历史 GLM 清理

1.1.1 启动服务前清理本应用旧版 GLM 的两个精确 Keychain account 名称、缓存项和非敏感偏好。此路径不读取凭据值、不访问浏览器数据，也不发送网络请求；Keychain 删除失败时保留未完成标记，以便下次启动重试。

## 安全边界

- 不在日志、诊断信息或测试产物中输出 API Key、访问令牌、OAuth token、Codex CLI session id、点火 raw output 和完整 Cookie。
- DeepSeek 与 Command Code 的 API Key 使用 Keychain 保存。
- 唯一的窄例外是把用户配置的隔离目录作为 `CODEX_HOME` 传给官方 Codex CLI 子进程；应用自身不读取其中的认证文件。
- 调试与归档产物默认位于被 Git 忽略的 `artifacts/`；渲染测试证据写入 `$TMPDIR/Minget-1.3.0-Evidence/`。
- 任何新增服务都应先验证官方取数路径、费用和凭据边界，再进入实现。

---

## English summary

Minget is a Swift Package Manager based macOS menu bar application. The internal package and module names remain `UsageMonitor` for compatibility.

- `UsageMonitorApp` owns the application lifecycle, status item, panel, connection UI, and settings.
- `UsageMonitorCore` owns models, parsing, refresh scheduling, provider clients, caching, and security rules.
- Since 1.3.0 Codex consists of two isolated profiles: one `CodexProfileRuntime` and one long-lived `codex app-server` child each, coordinated by `CodexProfilesCoordinator`, with a `profileID + accountID`-scoped cache.
- Each child is launched with a copy of the current environment whose `CODEX_HOME` is the profile's isolated directory. Minget never opens, lists or parses that directory.
- The menu bar shows exactly one source at a time — profile A, profile B, or DeepSeek — chosen by a persisted non-secret preference.
- DeepSeek data comes from its official balance endpoint; the API key is stored in macOS Keychain.
- Manual fire runs the official Codex CLI with a fixed argument list and discards its output; it is the only model-request path and is only reachable through the user's confirmation dialog.
- The retired Zhipu GLM integration has no runtime, WebKit, network, or browser-session path; only its local app-owned retirement cleanup remains.
- Geometry checks for notch and menu bar visibility are fully local and do not consume model tokens.
- Logs and diagnostics exclude API keys, access tokens, session ids, full cookies, and raw account responses.

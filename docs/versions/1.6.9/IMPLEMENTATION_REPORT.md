# 1.6.9 实施记录

分支 `codex/minget-1-6-9`，起点 `main@5bfb848`（1.6.8 发布后的文档提交）。2026-10-17，Asia/Singapore。本轮只改刷新范围与频率，端点、凭证边界、失败重试策略与点火路径均未改动。

## 1. 刷新模型

改动文件：`Sources/UsageMonitorApp/ViewModels/RefreshBatch.swift`（新增）、`Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`

一条自动循环取代原来的三条：它只维护菜单栏当前显示的那一个来源。

| 规则 | 实现 |
| --- | --- |
| 菜单栏来源 | `menuBarRefreshTarget()` 把 `MenuBarPreferences.Selection` 映射为账号键（`O1…`、`G1…`、`DS1…`）；`currentMenuBarRefreshInterval` 取该来源自己的节奏，低于阈值时用设置里的加速周期，绝不慢于原节奏 |
| 账号键 | `RefreshTarget`：ChatGPT Profile、Google 连接、注册表 API 账号、旧模式平台连接 |
| 节奏 | ChatGPT Profile 按自己的重置距离 30/60/120 秒；DeepSeek、Command Code、Google 约 5 分钟；加速仍为设置里的 15/30/60 秒 |
| 启动 | 只读菜单栏来源。Profile/Google 在 `start()` 立即读；API 连接等凭据准备完成后由该来源自己的路径读一次，避免读到未就绪的钥匙串状态 |
| 唤醒 | 只探测/补刷菜单栏来源（Profile 用既有唤醒探测，其余走各自刷新） |
| 删除 | 原「全部 Profile 的 ChatGPT 定时器」「全部 Provider + 全部 Google 的 5 分钟定时器」「加速专用定时器」合并为上表这一条循环 |

## 2. 页面批次与 5 分钟门槛

改动文件：`Sources/UsageMonitorApp/ViewModels/RefreshBatch.swift`、`UsageViewModel.swift`、`Sources/UsageMonitorApp/Views/UsagePanelView.swift`

- `RefreshBatchScope`：概览、ChatGPT、Gemini、DeepSeek、Command Code 五个页面，各自一批。
- `RefreshBatchPolicy.members`：批次 = 页面显示的账号减去菜单栏来源；概览跨品牌，品牌页只含该品牌。
- `RefreshBatchPolicy.needsRefresh`：批次内账号**全部**在 5 分钟内有取数才跳过；只要有一个过期就整批刷一次（整批判断，双方确认口径）。触发后成员取数时间即更新，因此 5 分钟内不会再次自动触发；刷新失败同样记账，不会反复重试。
- `RefreshAttemptLedger`：带锁的取数时间台账，取数任务在派发那一刻同步写入。第一版把记账放在主 actor 上，阻塞式等待的既有测试暴露了后果：主线程繁忙会推迟甚至卡住取数。改成锁保护后，取数不再依赖主线程进度。
- 触发点：面板 `onAppear`（按当前标签）与面板内标签切换（跟随显示）；独立详情窗口共用同一入口。
- DeepSeek 官方状态页：取消后台 5 分钟定时，改为概览页或 DeepSeek 页显示补刷时、距上次读取超过 5 分钟才读一次。

## 3. 支持改动

改动文件：`Sources/UsageMonitorApp/ViewModels/AntigravityModel.swift`、`ManagedAccounts.swift`、`Views/MingetSettingsView.swift`

- Google 模型：`refresh`/`start` 增加 `accountIDs` 范围参数（nil 保持原行为，供测试与内部路径使用）；新增 `lastAttemptAt(accountID:)`，让 Google 账号复用模型自己的尝试时间，不建第二份台账。
- 托管 API 账号：凭据准备完成后只读菜单栏显示的那一个；启动不再逐个读全部连接。
- 设置页「菜单栏低额度刷新」页脚补一句范围说明：菜单栏没显示的账号不再后台刷新，只在打开概览或品牌页时按 5 分钟门槛补刷一次。

## 4. 清理

改动文件：`Sources/UsageMonitorCore/Providers/ProviderRefreshEngine.swift`、`ProviderCache.swift`、`Services/UsageCache.swift`

面板打开时按年龄补刷的机制被批次规则取代，随之删除无调用方的 `ProviderRefreshEngine.shouldRefreshOnPanelOpen`、`defaultPanelOpenRefreshAge`、`panelOpenRefreshAge`、`refreshScheduled`，`ProviderCache.maxAgeForPanelOpenRefresh` 与 `UsageCache.maxAgeForPanelOpenRefresh`／`isStale`。菜单栏低额度策略 `MenuBarRefreshPolicy` 的规则未变，仅更新了注释。

## 5. 执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `swift build --build-tests --scratch-path /tmp/minget-1.6.9-build` | 退出码 0 |
| `swift test --scratch-path /tmp/minget-1.6.9-build` | 706 项（Core 457 + App 249），701 通过、5 项既有跳过、0 失败，退出码 0；日志 `evidence/logs/swift-tests.log` |

## 6. 新增与更新的自动测试

- 新增 `Tests/UsageMonitorAppTests/RefreshScopeTests.swift`（14 项）：菜单栏来源映射、批次成员（概览/品牌页 × 注册表/旧模式 × 显示与否）、5 分钟门槛（全新鲜跳过、一个过期整批刷、边界值、时钟回拨）、启动只读菜单栏来源、菜单栏循环跟随来源切换、概览补刷一次且 5 分钟内不重复、超过门槛再次补刷、品牌页只刷本品牌、整批一起刷、失败仍计入、手动刷新不受门槛限制。全部以「真实发生的读取次数」为断言，不用调用路径推断。
- 更新 `RefreshCadenceTests`：菜单栏循环改为「选择切换 + 加速 + 关闭加速 + 停止」契约（30 → 300 → 30 → 120 → nil）；唤醒测试改为只探测显示中的 Profile，隐藏 Profile 完全不被触碰。
- 更新 `UsageSnapshotTests`（删除随旧机制移除的缓存新鲜度用例）、`ProviderRefreshEngineTests`（`refreshScheduled` 改为直接自动读一次）。

## 7. 已知问题与未完成事项

- 菜单栏来源切换后，新来源的第一次读取要等它自己的节奏到点（ChatGPT 最长 120 秒，API/Google 最长 5 分钟），与 1.6.8 相同，本轮未改。
- 取数台账为进程内内存数据：重启后页面第一次打开一定判定为「需要刷新」。
- 页面上未显示的账号若正被重试阶梯挡住，批次会跳过它而不是强读；下一次打开页面时再尝试。
- 真实界面与真实请求节奏的复验由用户执行，见 `ACCEPTANCE.md`。

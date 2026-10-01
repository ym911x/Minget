# 1.6.1 实施报告

日期：2026-10-01。代码完成，Release arm64 签名包已安装并运行；本机真实界面检查通过。用户最终审美体验确认尚未取得。本轮未推送、未创建发布标签、未公开发布。

代码提交：`cfcb164`，分支 `codex/minget-1-6-1`，基线 `da97890`（1.6.0 发布台账）。

## 完成内容

1. 六个账号以统一摘要行呈现；选择服务后显示完整额度，导航与底部操作固定，640 pt 高度上限和短屏滚动保留。
2. GPT/Gemini 共用卡片头部、额度条、重置轨道、两位小数、字体和语义颜色。Gemini 首选官方主组，其他共享组展开查看；刷新后展开状态仍保留。缺失额度和已知时间分别处理，零值不会与未知混淆。
3. 服务切换采用原生菜单，点火移到卡片右下；原确认、授权、统计与缓存口径保留。连接类按钮进入账号页；更多菜单提供独立详情、关于及退出。
4. 设置与账号管理共用一个可调整大小的原生侧栏窗口；五个页面分工明确，账号行与编辑弹窗共用。登录组件准备收进展开项，账号显示名称及已有连接仍保留。
5. 主目录对齐已公开的 1.6.0，登记旧 worktree、隔离过期图谱；修正 README 当前版本矛盾，更新当前状态、审核及历史索引。

## 修改文件

- `Views/SharedQuotaViews.swift`：公共额度、卡片头部、标识及摘要行。
- `Views/UsagePanelView.swift` / `CodexProfileCard.swift` / `AntigravityViews.swift`：概览、服务详情、底部操作及统一额度布局。
- `Views/MingetSettingsView.swift` / `AccountManagementView.swift`：原生设置、统一账号行及管理 sheet。
- `ViewModels/DetailPreferences.swift` / `SettingsNavigation.swift`：既有显示选择迁移、当前页与展开状态。
- `StatusItem/StatusItemController.swift` / `UsageMonitorApp.swift`：窗口复用、关于入口及 Finder 重开详情。
- `UsageMonitorCore/Utilities/ResetTimeProgress.swift`：时间元数据独立计算，保留既有周期和异常时间校验。
- `Tests/UsageMonitorAppTests/`：迁移、缺失/零值、主组选择、布局、同窗复用、真实启动及生产视图示例图。
- `VERSION` 和当前项目文档：版本、任务入口、实施与验收状态。

没有改动 HTTP 白名单、官方 CLI 取数/登录协议、凭证存储、模型请求权限或外部点火计划。

## 执行与验证

- 完整测试：`MINGET_TEST_APP_PATH=/tmp/minget-161-final/Minget.app MINGET_RELEASE_SCREENSHOTS=/tmp/minget-161-samples MINGET_EVIDENCE_DIR=/tmp/minget-161-component-evidence swift test --scratch-path /tmp/minget-161-build`。Core 449 项、App 176 项，共 625 项，620 通过、5 跳过、0 失败。
- 五项跳过为四个需显式开启的官方 CLI 探针及 XCTest 原生 AX 环境测试；未以模拟结果填补。真实应用 AX 树已通过 CUA 另行检查。
- 最后限定详情窗口不可任意拉宽后，重跑 `StatusItemWiringTests|StartupWindowTests`：15 项、0 失败。最终签名候选也通过真实启动和退出子进程检查。
- `scripts/build.sh` 使用独立 `/tmp` 构建/签名路径及 `Minget Local Signing`；stage、候选、归档及正式安装路径严格签名检查通过。
- CUA 通过 Finder 精确打开候选及正式 App；检查真实六账号概览、GPT/Gemini 卡片、额度展开、只读刷新、账号页、菜单栏设置、计划页、凭证 sheet 打开/关闭及关于入口。安装版显示 1.6.1，现保留概览供使用。
- 本轮未重新提交 Key、登录授权、断开账号、触发点火、重置额度或更改点火计划。

日志、包指纹及脱敏生产视图例图见 [evidence](evidence/verification.json)。真实账号 UI 观察保留在当前任务工具记录；入库 PNG 全为带明确标记的合成数据。原生侧栏离屏渲染存在材质限制，未把该类离屏截图作为真实设置验收依据。

## 仍需确认

用户对最终视觉体验的确认，以及第二台 Mac、真实短屏和系统深色模式的现场体验。深色和短屏本轮已有渲染/布局检查，不能替代这些现场确认。1.6.0 遗留的续期、撤销重登与真实睡眠唤醒验证仍按原台账保留。

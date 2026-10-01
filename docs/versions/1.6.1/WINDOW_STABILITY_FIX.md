# 1.6.1 详情窗口稳定性补修

日期：2026-10-01。代码提交 `52f3b89`。本机正式安装包已更新，未推送或发布。

## 用户反馈与原因

用户反馈 Gemini 其他额度组折叠时弹层飞到菜单栏上方、详情滚动条明显、服务切换有抖动。此前检查没有覆盖已显示菜单栏弹层的连续尺寸变化，不能据此宣布该行为验收完成。

`DetailPreferences.objectWillChange` 使服务选择和额度组展开都触发窗口尺寸更新。弹层尺寸更新还替换整个 hosting controller；服务页高度不同造成 AppKit 重新定位。独立详情窗口同样随偏好和账号数改变尺寸。

## 修复

- `StatusItemController.swift`：外层宽 440 pt、高 640 pt，受屏幕可见区限制。取消偏好变更驱动的窗口尺寸变化，不再替换已显示弹层的 hosting controller；关闭 hosting controller 自动尺寸协商。独立详情窗使用同一稳定尺寸。
- `UsagePanelView.swift`：所有服务共用固定内容视口，禁用该页面隐式动画；隐藏滚动指示器，保留滚轮和触控板滚动。切换服务重置内容滚动位置，头部与底部固定。
- 测试增加两个 Gemini 账号与完整共享额度组的真实 AppKit 弹层回归，切换服务并展开额度后，逐次断言窗口 frame 和 hosting controller identity 完全一致。渲染检查统一使用稳定外层尺寸。

## 验证与边界

- App 测试 177 项，176 通过、1 项既有 AX 测试跳过、0 失败；新增真实弹层回归实际通过，没有跳过。见 [日志](evidence/stability-app-tests.log)。Core 实现未修改，沿用本轮先前完整测试结果。
- 最新签名候选启动测试 2 项通过：冷启动窗口、退出后无残留自有子进程。见 [日志](evidence/stability-startup.log)。
- Release arm64 构建和 stage/candidate/archive/install 严格签名通过。见 [构建日志](evidence/stability-build.log) 与 [安装指纹](evidence/stability-verification.json)。
- 从 Finder 固定路径打开正式 App，通过 CUA 操作真实 Gemini 账号展开其他额度组，窗口保持原位；截图无可见滚动条。滚轮向下后第二账号与完整主额度仍可查看；切换 ChatGPT 和概览，窗口尺寸保持一致。真实邮箱和额度截图没有复制入仓库。
- 用户实际菜单栏弹层体验仍待复验；本轮直接自动验证的是真实 AppKit 菜单栏弹层，人工界面操作的是正式 App 独立详情窗。第二台 Mac、实际短屏、系统深色模式没有新增现场验收。

## 回退

修复前 1.6.1 已备份到 `~/Applications/Minget Backups/1.6.1-before-window-fix-20261001-140552/Minget.app`。此前 1.6.0 备份继续保留。安装文件 SHA-256 为 `c19a601ba2084d56be50c95f3b72c1bae79bf6498a084fc518840fbbabfff51d`。回退时退出正式 App、恢复固定安装路径并核对签名，不直接启动备份副本，不覆盖账号及凭证。

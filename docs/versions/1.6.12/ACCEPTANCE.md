# 1.6.12 验收

- 截图账号的官方 CLI 实测返回一个 Argon 周额度桶，剩余比例、重置时间皆存在。详见[脱敏记录](evidence/usage.md)。
- 完整回归执行 713 项，708 项通过、5 项既有环境跳过，0 失败。新增用例覆盖开关默认值、持久化、两项额度组开关各自独立，以及周额度、5 小时或两者均存在时的卡片布局。
- 本机 Release 包经 Minget Local Signing 签名并通过严格校验。程序 SHA-256 为 `8cf15532ea6534142872fcff63460c7c4b86c5f641e29e6dd47cfbb60c71fad6`。
- 本机签名包位于主目录 `artifacts/1.6.12/Minget-1.6.12.zip`，SHA-256 为 `9ec5d382c7f08d0488f37bcde74e6d817f312a38fd05f74f5a3c91c740881684`。
- 1.6.11 已备份到 `~/Library/Application Support/Minget Backups/Minget-1.6.11-20261118.zip`。重新解包后的严格签名校验通过，程序指纹与 1.6.11 验收记录一致。

实际界面验证使用生产 `UsagePanelView` 和 `MingetSettingsView`，以示例账号和隔离偏好创建两个 macOS 窗口。通过 AXPress 操作真实开关，分别对仅周额度及同时含 5 小时与周额度的报告执行「开 → 关 → 开」，共六个状态通过。核对可访问性树、截图和偏好持久化。第二种报告为合成测试。

2026-11-18 已安装并从 `/Applications/Minget.app` 重启 1.6.12，正式路径的版本号、主程序摘要及严格签名校验通过。2026-11-18 用户确认本机 1.6.12 审核通过，授权正式发布并同步 GitHub。

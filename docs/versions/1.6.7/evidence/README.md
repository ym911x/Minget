# 1.6.7 证据说明

本轮为本机编码交付阶段的证据，采集时间 2026-10-13（Asia/Shanghai），采集环境 macOS 27.0.1 / Apple Silicon，分支 `codex/minget-1-6-7`（起点 `main@1592f46`）。未打标签、未推送、未建 Release；已完成 Release 严格签名并装入正式路径，真实界面验收状态见 [验收台账](../ACCEPTANCE.md)。

- `logs/swift-tests.log`：完整回归，Core 462 项（4 项显式官方 CLI 探针跳过）+ App 232 项（1 项 AX 信任限制跳过），689 通过、5 跳过、0 失败，退出码 0。
- `logs/release-build-staging.log`：`scripts/build.sh` Release 构建、`Minget Local Signing` 签名、staging / 安装路径 / archive 三处严格校验，退出码 0。
- `records/local-install.txt`：正式路径版本、可执行文件指纹、替换前 1.6.6 备份路径与指纹，以及本轮改动的源码指纹。
- `screenshots/settings-{menuBar,detail,schedules,about,accounts}-{light,dark}.png`：真实 `MingetSettingsView` 五个分组的离屏渲染（780×640），用于核对唯一标题层级、分组脚注、标签与控件两列对齐、深浅色。
- `screenshots/settings-sidebar-marks-{light,dark}.png`：五个分组的侧栏彩色方块图标（与窗口侧栏使用同一行视图）。离屏宿主不会实例化 `NavigationSplitView` 的侧栏，因此单独渲染；真实窗口中的侧栏见用户复验。
- `screenshots/accounts-{light,dark}.png`：托管账号模式下「账号」页，含页头主操作「添加账号」与各平台分组内的账户行。
- `screenshots/add-api-{light,dark}.png`：添加 API 账号的弹窗。

本目录不保存真实账号截图、邮箱、Key、Cookie、额度原文或认证文件；示例渲染使用合成账号与 `InMemoryCredentialStore`，UserDefaults 与点火计划均使用隔离套件。

## 已知的渲染宿主限制

离屏 host 中的 `NavigationSplitView` 不绘制侧栏列表，因此窗口级截图里左栏为空；这与 1.6.3 起的既有证据一致（当时同样只显示详情栏）。侧栏本身以 `settings-sidebar-marks-*.png` 单独留证，真实窗口表现由用户复验。

`settings-about-*.png` 中版本显示 `—`：渲染宿主没有应用 Info.plist，本轮起不再回退成过时的假版本号；正式 App 的版本在安装记录中单独确认为 1.6.7。

## 文件归类

- `logs/`：测试与 Release 构建日志。
- `screenshots/`：示例渲染图片。
- `records/`：脱敏验证与安装记录。
- `manifests/`：校验清单。`SHA256SUMS` 内路径相对于版本目录，执行方式：`cd docs/versions/1.6.7 && shasum -a 256 -c evidence/manifests/SHA256SUMS`。

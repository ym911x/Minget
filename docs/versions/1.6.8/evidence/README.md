# 1.6.8 证据说明

本轮为本机编码交付阶段的证据，采集时间 2026-10-16（Asia/Singapore），采集环境 macOS 27.0.1 / Apple Silicon，分支 `codex/minget-1-6-8`（起点 `codex/minget-1-6-7@1a0a172`）。未打标签、未推送、未建 Release；已完成 Release 严格签名并装入正式路径，真实界面验收状态见 [验收台账](../ACCEPTANCE.md)。

- `logs/swift-tests.log`：完整回归，Core 458 项（4 项显式官方 CLI 探针跳过）+ App 235 项（1 项 AX 信任限制跳过），688 通过、5 跳过、0 失败，退出码 0。
- `logs/release-build-staging.log`：`scripts/build.sh` Release 构建、`Minget Local Signing` 签名、staging / 安装路径 / archive 三处严格校验，退出码 0。
- `records/local-install.txt`：正式路径版本、可执行文件指纹、替换前 1.6.7 备份路径与指纹、固定宽度常量，以及本轮改动的源码指纹。
- `screenshots/01-menubar-states-light.png`、`02-menubar-states-dark.png`：真实的 `MenuBarLabelContent` 状态矩阵（正常、满格、临近重置、到重置、未知窗口、缓存、读取失败、加载中、100% 与 9%），每行都绘制在同一个固定宽度里，可直接比对长度。
- `screenshots/09-three-sources-light.png`、`10-three-sources-dark.png`：三种来源与代号（`O1`、`O2`、`DS1`、`DS2`）以及不可用文案，同样全部等宽；⚠ 标记与文字同行，不改变长度。
- `screenshots/11-host-frame-{light,dark}.png`：同样的状态放进**真实宿主尺寸**（`itemWidth - padding` × 菜单栏厚度）渲染。第一版实现正是在这个尺寸下把两条时间条挤出了可视区，这张图是那类回归的常驻证据。
- `screenshots/03-direction-light.png`、`04-weekly-direction-light.png`：时间条细节（5 段方向、7 段方向），表达与 1.6.7 一致。
- `screenshots/settings-menuBar-{light,dark}.png`：旧模式（无账号注册表）下的设置「菜单栏显示」列表，行为 `O1 Codex 账号`、`O2 Hermes / OpenClaw 账号`、`DS1 DeepSeek`。
- `screenshots/menubar-sources-{light,dark}.png`：托管模式、含 4 个 Google 账号的同一列表，显示 `O1`–`O4`、`DS1`–`DS2`、`G1`–`G4`，用于核对代号与账号名称的对应关系。

本目录不保存真实账号截图、邮箱、Key、Cookie、额度原文或认证文件；示例渲染使用合成账号与 `InMemoryCredentialStore`，UserDefaults 使用隔离套件。

## 已知的渲染宿主限制

渲染宿主没有应用 Info.plist 与真实菜单栏，因此菜单栏项目本身以固定夹具离屏渲染（`MenuBarLabelContent`，与生产视图同一份绘制代码），真实菜单栏中的长度与代号由用户复验。

## 文件归类

- `logs/`：测试与 Release 构建日志。
- `screenshots/`：示例渲染图片。
- `records/`：脱敏验证与安装记录。
- `manifests/`：校验清单。`SHA256SUMS` 内路径相对于版本目录，执行方式：`cd docs/versions/1.6.8 && shasum -a 256 -c evidence/manifests/SHA256SUMS`。

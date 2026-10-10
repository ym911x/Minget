# 1.6.6 证据说明

本轮为本机编码交付阶段的证据，采集时间 2026-10-10（Asia/Singapore），采集环境 macOS 27.0.1 / Apple Silicon，分支 `codex/minget-1-6-6`（起点 `main@14004e5`）。开发交付时未发布；用户随后明确授权审核并发布，核验见 [PUBLICATION.md](../PUBLICATION.md)。已完成 Release 严格签名并装入正式路径，真实界面验收状态见 [验收台账](../ACCEPTANCE.md)。

- `logs/swift-tests.log`：完整回归，Core 462 项（4 项显式官方 CLI 探针跳过）+ App 227 项（1 项 AX 信任限制跳过），684 通过、5 跳过、0 失败，退出码 0。
- `logs/release-build-staging.log`：`scripts/build.sh` Release 构建、`Minget Local Signing` 签名、staging / 安装路径 / archive 三处严格校验，退出码 0。
- `records/local-install.txt`：正式路径版本、可执行文件指纹、替换前 1.6.5 备份路径与指纹，以及本轮改动的源码指纹。
- `screenshots/panel-google-{light,dark}.png`：真实 `UsagePanelView` 在 Gemini 品牌页的离屏示例渲染；两组额度直接相连，`Claude and GPT models` 用量为 Claude 橙，重置时间条仍为蓝，无「最近成功」行与「其他额度组」折叠控件。
- `screenshots/google-dual-{light,dark}.png`：两张 Google 示例卡片的独立渲染，用于逐行核对组名、百分比与时间条配色。
- `screenshots/panel-all-{light,dark}.png`：真实「概览」标签页渲染；ChatGPT 与 Gemini 行图示与 Command Code 双列等长，名称列压缩后的截断表现。
- `screenshots/overview-{light,dark}.png`：概览行组件的独立渲染（含 ChatGPT 两行、Gemini 两行、DeepSeek 余额行、Command Code 双列行）用于对比四类行的条长。
- `screenshots/overview-edge-{light,dark}.png`：边界行，含长名称截断、长状态先缩字号再截断、真实零、额度缺失但时间已知、未连接、Command Code 单列兜底（缓存）与周额度兜底。

本目录不保存真实账号截图、邮箱、Key、Cookie、额度原文或认证文件；示例渲染使用合成账号与 `InMemoryCredentialStore`，额度数字为合成值。

## 配色核对（像素级）

`google-dual-light.png` 采样 `Claude and GPT models` 一组的「剩余 73.50%」文字像素，转换为 sRGB 后为 `(217, 119, 87)`，即 Claude 品牌橙 `#D97757`；同一图的用量条为该颜色在 0.86 不透明度下的绘制结果（缓存态为 0.45），时间条保持系统蓝。

## 文件归类

- `logs/`：测试与 Release 构建日志。
- `screenshots/`：示例渲染图片。
- `records/`：脱敏验证与安装记录。
- `manifests/`：校验清单。`SHA256SUMS` 内路径相对于版本目录，执行方式：`cd docs/versions/1.6.6 && shasum -a 256 -c evidence/manifests/SHA256SUMS`。

渲染截图来自测试进程，没有应用 Info.plist 时页头版本回退为 v1.6.1，属于既有的测试宿主现象（1.6.4/1.6.5 证据同）。正式 App 的 Info.plist 已在安装记录中单独确认为 1.6.6。

## 发布审核追加证据

- `records/publication-local-review.txt`：正式安装版指纹、签名、原证据校验和脱敏真实界面观察。
- 发布独立回归日志保留首次失败、针对性复测与完整复测，结果与边界见发布记录。
- 示例渲染的硬编码标题还可能显示 1.6.5；图片内容来自本轮源码，标题不作为安装版版本证明。

- `records/github-ci-summary.json`、`github-release-summary.json` 与 `logs/github-ci-verification.log`：公开 Release 及发布提交 CI 的实际核验结果。v1.6.6 为 Latest，CI 689 项、55 项环境跳过、0 失败，Release 构建与严格签名通过。

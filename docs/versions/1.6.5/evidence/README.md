# 1.6.5 证据说明

本轮为本机编码交付阶段的证据，采集时间 2026-10-09/10（Asia/Shanghai），采集环境 macOS 27.0.1 / Apple Silicon，分支 `codex/minget-1-6-5`（起点 `main@97e6bc3`）。未打标签、未推送、未建 Release；已完成 Release 严格签名并装入正式路径，真实界面验收见 [验收台账](../ACCEPTANCE.md)。

- `logs/swift-tests.log`：完整回归，Core 462 项（4 项显式官方 CLI 探针跳过）+ App 224 项（1 项 AX 信任限制跳过），0 失败，退出码 0。
- `logs/release-build-staging.log`：`scripts/build.sh` Release 构建、`Minget Local Signing` 签名、staging / 安装路径 / archive 三处严格校验，退出码 0。
- `records/local-install.txt`：正式路径版本、可执行文件指纹、替换前 1.6.4 备份路径与指纹，以及本轮改动的源码指纹。
- `screenshots/overview-{light,dark}.png`：真实 `UsagePanelView` 概览组件的离屏示例渲染，含 Command Code 双列（5H + 月）。
- `screenshots/overview-edge-{light,dark}.png`：边界行，含长名称截断、真实零、额度缺失但时间已知、未连接、余额不可用、Command Code 单列兜底（缓存）与周额度兜底。
- `screenshots/brand-refresh-{chatGPT,deepSeek,commandCode}-{light,dark}.png`：三个品牌页各自的标签行右侧刷新按钮。
- `screenshots/brand-refresh-commandcode-refreshing-{light,dark}.png`：同一个 Command Code 页在其自身刷新进行中的状态（按钮禁用并显示进度，版式不移动）。

本目录不保存真实账号截图、邮箱、Key、Cookie、额度原文或认证文件；示例渲染使用合成账号与 `InMemoryCredentialStore`，额度数字为合成值。

## 文件归类

- `logs/`：测试与 Release 构建日志。
- `screenshots/`：示例渲染图片。
- `records/`：脱敏验证与安装记录。
- `manifests/`：校验清单。`SHA256SUMS` 内路径相对于版本目录，执行方式：`cd docs/versions/1.6.5 && shasum -a 256 -c evidence/manifests/SHA256SUMS`。

示例截图标题显示 v1.6.5；截图来自测试进程，没有应用 Info.plist 时页头版本回退为 v1.6.1，属于既有的测试宿主现象（1.6.4 证据同）。正式 App 的 Info.plist 已单独确认 1.6.5。

## 发布前核对（2026-10-10，Asia/Singapore）

原清单 16 项全部通过后，日志去除 ANSI、本机用户名与工作区路径，安装/回滚记录将主目录写为 `$HOME`。个人余额与用量明细从公开需求及验收移除，仅保留结构与结论；截图保持原合成图。品牌页截图的 v1.6.1 为无 bundle 元数据时的既有回退文字，正式版本从安装 App 的 Info.plist 核验。`logs/publication-swift-tests.log` 为发布前独立回归：686 项、681 通过、5 跳过、0 失败；既有编译警告保留。远端进度见 [PUBLICATION.md](../PUBLICATION.md)。

远端发布核验：CI 摘要和 Release 元数据位于 `records/github-*-summary.json`；`logs/github-ci-verification.log` 留存 686 项测试总数及 Release 严格签名节选。v1.6.5 已公开为 Latest，详细发布提交与标签见 [PUBLICATION.md](../PUBLICATION.md)。

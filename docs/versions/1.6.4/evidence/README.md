# 1.6.4 证据说明

本轮为本机编码交付阶段的证据，采集时间 2026-10-09（Asia/Shanghai），采集环境 macOS 27.0.1 / Swift 6.4 / Apple Silicon，分支 `codex/minget-1-6-4`（起点 `main@73c3f9a`）。未打标签、未推送、未建 Release；用户要求测试后已 Release 严格签名并装入正式路径，用户复测确认可固化。

- `logs/swift-tests.log`：固化源码上的完整回归，Core 462 项（4 项显式官方 CLI 探针跳过）+ App 217 项（1 项 AX 信任限制跳过），0 失败，退出码 0。
- `logs/build.log`：`swift build` 全量构建，退出码 0。
- `logs/release-build.log`：`scripts/build.sh` Release 构建、`Minget Local Signing` 签名、staging 与正式路径严格校验、archive 副本，退出码 0。
- `records/local-verification.txt`：环境、执行的命令、结果，以及两项进程时序测试在并行满载下各失败一次、隔离复跑通过的说明。该波动位于本轮未改动的 `UsageMonitorCore`。
- `records/local-install.txt`：装入 `/Applications/Minget.app` 的版本、修复版与首次安装版指纹、替换前 1.6.3 指纹与备份路径。
- `records/frozen-build.txt`：固化核对，证明用户测试的安装版与固化源码是同一份构建。
- `screenshots/overview-order-{before,after}-{light,dark}.png`：真实 `UsagePanelView` 组件的离屏示例渲染，5 个示例账号，排序前为来源顺序、排序后为把两个 API 行移到 ChatGPT 行之前的结果。只证明行序、手柄外观与滑让几何，不能证明真实指针拖动、跟手手感、弹簧观感或 VoiceOver 现场表现；用户复测的手感结论见 [验收台账](../ACCEPTANCE.md)。

本目录不保存真实账号截图、邮箱、Key、Cookie、额度原文或认证文件；示例渲染使用合成账号与 `InMemoryCredentialStore`。拖动过程中与拖动落位的现场交互结论见 [验收台账](../ACCEPTANCE.md)。

## 文件归类

- `logs/`：编译、测试与 Release 构建日志。
- `screenshots/`：示例渲染图片。
- `records/`：脱敏验证与安装记录。
- `manifests/`：校验清单。`SHA256SUMS` 内路径相对于版本目录，执行方式：`cd docs/versions/1.6.4 && shasum -a 256 -c evidence/manifests/SHA256SUMS`。

## 发布核验证据（2026-10-09）

`logs/publication-swift-tests.log` 是 Codex 在固化分支上的独立完整复跑：Core 462 + App 217，674 通过、5 跳过、0 失败。新增日志去除本机用户/工作区路径和 ANSI 控制码，原始固化日志与 SHA256SUMS 不改写。`manifests/PUBLICATION_SHA256SUMS` 只覆盖本次新增发布证据，路径同样相对于版本目录。

示例截图标题显示 v1.6.1，来自测试进程没有应用 Info.plist 时既有的版本回退文字；图片仅证明组件和顺序效果。正式 App Info.plist 已单独确认 1.6.4。`records/local-verification.txt` 的 676 项为首次安装前阶段，最终修正及发布复跑为 679 项；以同目录修正记录和本次发布日志为准。

`records/github-ci-summary.json`、`github-release-summary.json` 为发布后的远端核验摘要。GitHub CI 679 项，624 通过、55 环境跳过、0 失败，并通过应用构建及 ad-hoc 严格签名；本机跳过数不同，不能合并为全部通过。

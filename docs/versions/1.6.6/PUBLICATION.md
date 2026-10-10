# Minget 1.6.6 发布记录

日期：2026-10-10，Asia/Singapore。用户授权：审核并发布 1.6.6。

## 发布前检查

- 开始时主目录为 `codex/minget-1-6-6`，起点 `14004e5`，改动尚未提交；本地 main 与远端 main 均为 `14004e5`，Latest 为 v1.6.5，远端无 v1.6.6 标签。
- 独立逐项检查四个应用源码及五个测试文件。Core、网络、认证、缓存和点火路径无改动；未发现阻断发布的问题。
- 原 14 项证据清单全部通过；正式 App 1.6.6 deep/strict 签名、两个内嵌程序 strict 签名及源码与主程序指纹核对通过。保留现有正式安装包，无需重建或替换。
- 发布独立完整回归首次 689 项，5 跳过、1 失败：既有 `CodexLaunchTests.testProbeTimeoutAlsoKillsWrapperDescendant` 未生成临时 child-pid 文件。随后 11 项 CodexLaunchTests 复测及完整回归复测均通过，未改测试或应用代码。复测 689 项，684 通过、5 项既有跳过、0 失败，退出码 0。首次失败根因未确定，按未复现的测试时序问题保留，不覆盖原失败记录。
- 正式 App 真实概览与 Gemini 三账号布局检查、滚动及品牌只读刷新通过。用户体验复验、真实低额度红档、VoiceOver、第二台 Mac 及其它现场边界按验收台账保留。
- 修正根 README 当前版本遗留 1.6.3、实施记录卡片高度公式和当前版本文档时区。新增日志已脱敏本机与临时目录路径，真实账号观察只保存无账号和无数值的结果摘要。
- 没有模型点火、消耗重置额度、读取认证文件或既有浏览器会话。

## 远端结果

发布准备完成，下一步将准备提交推送至 main，待同一提交的 GitHub CI 测试与 Release 构建通过后建立 v1.6.6 标签并公开 Release。结果在完成后回写；目前不记已发布或 CI 通过。继续源码分发，无自定义二进制附件。

证据：`evidence/logs/publication-swift-tests-first-attempt.log`、`publication-codex-launch-retry.log`、`publication-swift-tests.log` 与 `evidence/records/publication-local-review.txt`。

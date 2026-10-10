# Minget 1.6.6 发布记录

日期：2026-10-10，Asia/Singapore。用户授权：审核并发布 1.6.6。

## 发布前检查

- 开始时主目录为 `codex/minget-1-6-6`，起点 `14004e5`，改动尚未提交；本地 main 与远端 main 均为 `14004e5`，Latest 为 v1.6.5，远端无 v1.6.6 标签。
- 独立逐项检查四个应用源码及五个测试文件。Core、网络、认证、缓存和点火路径无改动；未发现阻断发布的问题。
- 原 14 项证据清单全部通过；正式 App 1.6.6 deep/strict 签名、两个内嵌程序 strict 签名及源码与主程序指纹核对通过。保留现有正式安装包，无需重建或替换。
- 发布独立完整回归首次 689 项，5 跳过、1 失败：既有 `CodexLaunchTests.testProbeTimeoutAlsoKillsWrapperDescendant` 未生成临时 child-pid 文件。随后 11 项 CodexLaunchTests 复测及完整回归复测均通过，未改测试或应用代码。复测 689 项，684 通过、5 项既有跳过、0 失败，退出码 0。首次失败根因未确定，按未复现的测试失败保留，不覆盖原失败记录。
- 正式 App 真实概览与 Gemini 三账号布局检查、滚动及品牌只读刷新通过。用户体验复验、真实低额度红档、VoiceOver、第二台 Mac 及其它现场边界按验收台账保留。
- 修正根 README 当前版本遗留 1.6.3、实施记录卡片高度公式和当前版本文档时区。新增日志已脱敏本机与临时目录路径，真实账号观察只保存无账号和无数值的结果摘要。
- 没有模型点火、消耗重置额度、读取认证文件或既有浏览器会话。

## 远端结果

- 发布时间：2026-10-10 21:44:35（Asia/Singapore）。
- Release：[v1.6.6](https://github.com/ym911x/Minget/releases/tag/v1.6.6)，已由 GitHub latest 端点核验为 Latest、非草稿、非预发布；无自定义附件，继续源码分发。
- 发布提交：`78c57ba7323da6ade365050819de1f2bbe409aa8`。Annotated tag 对象 `2af6812d83c456448792a70bced706666529ee1c`，远端解引用到上述发布提交。
- [GitHub CI](https://github.com/ym911x/Minget/actions/runs/38056670941) 首次执行成功：689 项，634 通过、55 项 CI 环境跳过、0 失败；Release 应用构建与 ad-hoc 包 staging / 安装 / archive 严格签名校验通过。本机复测为 684 通过、5 跳过，环境差异分别保留。
- 主目录 main 从 `14004e5` 快进到发布提交，随后仅回写文档与脱敏证据，使用 `[skip ci]`；源码、测试、构建脚本与 VERSION 相对标签不变。CI 结论针对发布提交。
- 正式 App 仍为已现场检查的 1.6.6，deep/strict 签名与主程序指纹复核通过；发布期间未重建或替换正式 App。
- 本机首次测试失败的根因未确定；针对性复测、完整复测与独立远端 CI 均通过。日志均保留，不修改或跳过失败断言。
- 用户体验复验、VoiceOver、第二台 Mac、Command Code Studio 同刻对账等现场边界继续保留，不因发布改记通过。
- 核验摘要见 `evidence/records/github-ci-summary.json`、`github-release-summary.json`，测试总数与严格签名节选见 `evidence/logs/github-ci-verification.log`。

证据：`evidence/logs/publication-swift-tests-first-attempt.log`、`publication-codex-launch-retry.log`、`publication-swift-tests.log` 与 `evidence/records/publication-local-review.txt`。

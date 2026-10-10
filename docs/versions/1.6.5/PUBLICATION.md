# Minget 1.6.5 发布记录

日期：2026-10-10，Asia/Singapore。用户授权：检查 1.6.5 文件，完整即可发布 GitHub。

## 发布前检查

- 开发提交 `ba7045b`，初次检查主目录工作区干净，远端 main 为 `97e6bc3`，Latest 为 v1.6.4，远端无 v1.6.5 标签。
- 独立检查三处应用源码与两处测试改动；Core、网络、认证、点火路径无新增或修改。
- 原证据清单 16 项全部通过；正式 App 1.6.5 deep/strict 签名通过，主程序 SHA-256 与固化安装记录相同；未重建或替换正式 App。
- 独立完整回归 Core 462 + App 224 = 686 项，681 通过、5 项既有跳过、0 失败；日志见 `evidence/logs/publication-swift-tests.log`。
- 用户已完成正式界面及品牌刷新范围复验，VoiceOver、Studio 同刻对账、第二台 Mac 保留待验收。
- 补齐发布说明，清理个人用量明细与日志中的本机路径。原开发提交仅本地保留，公开 main 使用整理后内容的 squash 提交，避免推送未脱敏开发历史。
- 核对期间主目录出现外部 Git 分支切换，因此发布准备在独立临时 worktree `codex/publish-1-6-5` 完成；主目录同步前重新检查状态。

## 远端结果

- 发布时间：2026-10-10 13:58:27（Asia/Singapore）。
- Release：[v1.6.5](https://github.com/ym911x/Minget/releases/tag/v1.6.5)，Latest、非草稿、非预发布，无自定义附件，继续源码分发。
- 发布提交：`61bf600956eb86bc2ecf09eb6bfdb6c2bc812892`。Annotated tag 对象 `9b669d80e612c2bb62655fe552ffb472801e1a27`，远端解引用到上述提交。
- [GitHub CI](https://github.com/ym911x/Minget/actions/runs/38029112741) 成功：686 项，631 通过、55 项 CI 环境跳过、0 失败；Release 应用构建与 ad-hoc 包严格签名校验通过。本机为 681 通过、5 跳过，环境差异分别保留。
- 主目录 main 已快进到发布提交，后续只回写文档与脱敏证据并使用 `[skip ci]`；源码、测试、构建脚本与 VERSION 相对标签不变。CI 结论针对发布提交。
- 正式 App 保持用户复验通过的 1.6.5，deep/strict 签名及主程序指纹复核通过。发布期间没有重建或替换 App、改账号和点火计划、消耗重置额度。
- 核验摘要见 `evidence/records/github-ci-summary.json`、`github-release-summary.json`，测试总数及签名日志节选见 `evidence/logs/github-ci-verification.log`。
- VoiceOver、Studio 同刻对账、第二台 Mac 继续保留待验收，不因发布改记通过。

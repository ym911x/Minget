# 1.6.4 发布记录

2026-10-09（Asia/Shanghai）：用户授权检查 1.6.4 文件，完整即可发布 GitHub。本次授权接续已固化的本机交付，允许推送 main、创建 annotated tag v1.6.4 和公开 Latest Release。发布范围为源码与版本资料，不附本机签名 App；目录整理分支的未提交变更独立保留，不进入本次发布。

## 发布前核验

- 开发分支 `codex/minget-1-6-4`，实现提交 `dfe6936`，状态补充提交 `bd0bfb2`，相对远端 `main@73c3f9a` 可快进。
- Codex 检查全部生产差异：只涉及概要视图、手势与本地账号 ID 顺序偏好；网络、凭证、刷新、点火和账号注册表没有修改。
- 独立完整回归：Core 462 项、App 217 项，合计 679 项，674 通过、5 跳过、0 失败。日志见 `evidence/logs/publication-swift-tests.log`，新增日志已去除本机用户名、工作区绝对路径和 ANSI 控制码。
- 原证据清单 10 项全部通过；本机 `/Applications/Minget.app` 版本 1.6.4，deep/strict 签名校验通过，主程序及 CLI 指纹与固化记录一致。未重建或替换正式 App。
- 示例渲染已人工查看，前后行序及明暗外观符合内容说明。测试进程没有应用 bundle 元数据，截图标题的 v1.6.1 来自既有回退文字，不能用作安装版版本证据；真实版本以正式 Info.plist 为准。
- 需求、任务、实施、审核、验收、回滚和证据齐全，补齐发布说明与发布记录；全部现场待验收项保留。
- 主目录原目录整理变更保存在独立 worktree，218 个已变更或未跟踪文件逐项比对，无 SHA-256 差异；保留原 stash 作第二份恢复入口。本次不发布该维护分支。

## 远端结果

- 发布时间：2026-10-09 13:20:55（Asia/Shanghai）。
- Release：[v1.6.4](https://github.com/ym911x/Minget/releases/tag/v1.6.4)，Latest、非草稿、非预发布，无自定义附件，继续源码分发。
- 发布提交：`1f12d0bf160d89f0c21268c9bba1449cec33e791`。Annotated tag 对象 `a04805a411441bdbf72c5cf231027f9225cfd7bf`，解引用到上述提交，远端标签同步核验。
- [GitHub CI](https://github.com/ym911x/Minget/actions/runs/37887900744) 成功：679 项，624 通过、55 项 CI 环境跳过、0 失败；Release 应用构建及 ad-hoc 包严格校验通过。本机结果为 674 通过、5 跳过，环境差异分别保留。
- 主目录 `main` 已快进到发布提交，后续仅回写文档与脱敏证据并使用 `[skip ci]`；源码、测试、脚本与 VERSION 相对标签不变。CI 结论只针对发布提交，不宣称后续文档提交另跑 CI。
- 本机正式 App 保持用户测试通过的 1.6.4，发布期间没有替换 App、修改账号、点火计划或消耗重置额度。
- 远端核验摘要见 `evidence/records/github-ci-summary.json`、`github-release-summary.json`。现场待验收项继续保留。

## 本地目录整理工作的保留

原分支 `codex/project-folder-organization` 与全部未提交变更保存在 `$HOME/.codex-minget-b/worktrees/minget-folder-organization-preserved/额度显示小组件`，218 个条目逐项 SHA-256 比对一致。恢复备份 stash 为 `0a523bab5d414a595e293a329d09e9d74081b492`，未删除。原主目录里的忽略历史资料仍留原处，未公开或删除；该维护分支尚未合入 `main`，后续维护需重新以本次发布基线核对。

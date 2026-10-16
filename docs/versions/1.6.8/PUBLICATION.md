# Minget 1.6.8 发布记录

日期：2026-10-16，Asia/Singapore。用户明确授权将尚未发布的版本发布到 GitHub。

## 发布范围与准备

- 远端 main 为 `1592f46`，Latest 为 v1.6.6；尚未公开的版本为 1.6.7 与 1.6.8。本次统一发布 v1.6.8，包含 1.6.7 设置窗口视觉统一，不单独补发 v1.6.7。
- 当前分支 `codex/minget-1-6-8`，起点 `1a0a172`；逐项检查七个应用/Core 源文件差异与相关测试，变更限于菜单栏展示和设置列表，不改网络、认证、缓存及点火路径。
- 16 份既有证据的 SHA-256 清单与安装记录中的源码指纹全部复核通过。正式 App 版本 1.6.8，主程序 SHA-256 为 `97c2635dd0d2e5672474ce347a776cd6659a9fac5999643731f92d6bdf84be49`；bundle deep/strict 与两个内嵌程序 strict 签名均通过。本次不重建或替换正式安装包。
- 开始时工作区另有 `releases/README.md`、`releases/v1.0.0/README.md`、`releases/v1.0.1/README.md` 三份本地删除。这些与版本无关，保持用户工作区原状并排除提交，远端保留历史文件。
- 修正当前版本文档中的分支起点名称和时区；证据中的原测试、构建结果保持不变。
- 发布前完整回归通过：Core 458 项 + App 235 项，共 693 项，688 通过、5 项既有跳过、0 失败，退出码 0。命令 `swift test --scratch-path /tmp/minget-swiftpm-build --disable-sandbox`，日志 `evidence/logs/publication-swift-tests.log`。远端 CI 与公开 Release 已核验，见下文。
- 沿用源码分发，不上传本机签名包。刘海机型、VoiceOver、第二台 Mac 与其它历史待验收项继续保留，发布不改变验收结论。

## 推送中的临时网络中断（已恢复）

- 发布准备提交：`1d9d6bc`。主目录已切回 `main`，从 `1592f46` 快进到该提交，保留两轮完整提交历史。
- `git push origin main` 两次返回 `LibreSSL SSL_connect: SSL_ERROR_SYSCALL`；`gh api` 返回 `EOF`。读取系统现有代理后，以命令级 `http.proxy=http://127.0.0.1:7892` / `HTTPS_PROXY` 复核仍失败；没有修改系统代理、Git 全局设置或凭证。
- 初始 `git ls-remote` / `gh release list` 成功时，远端 main 为 `1592f46`，Latest 为 v1.6.6；失败推送未报告成功。远端最终状态待连接恢复后重查。
- 上述连接失败期间尚未推送，也未触发远端 CI、未创建标签或 Release。当时状态不记完成。用户随后说明已切换台湾代理节点，GitHub 连接恢复，后续推送成功。
- 恢复连接后，发布准备与网络经过记录共同推送为 `983bb8e`，该提交远端 CI 通过，再创建标签与 Release。
- 三份既有 releases 文档删除保持在工作区，不纳入任何本轮提交。

## 正式发布结果

- 发布时间：2026-10-16 21:59:50（Asia/Singapore）。[v1.6.8](https://github.com/ym911x/Minget/releases/tag/v1.6.8) 已由 GitHub latest 端点核验为 Latest、非草稿、非预发布，无自定义附件，继续源码分发。
- 发布提交：`983bb8ecaa65095b54bd9efdcf73249aa556be22`。Annotated tag 对象 `0d1c0c6328b211764fe776c5a126bbae367834a1`，远端解引用到上述提交。
- [GitHub CI](https://github.com/ym911x/Minget/actions/runs/38911824149) 通过：Swift 5.10，693 项，639 通过、54 项 CI 环境跳过、0 失败；Release 构建及 ad-hoc 包 staging / 安装 / archive 严格校验通过。本机为 688 通过、5 跳过，分别保留环境差异。
- 发布后主目录 main 回写台账，文档提交使用 `[skip ci]`；源码、测试、构建脚本、VERSION 相对标签不变，CI 结论针对发布提交。
- 正式 App 仍为已由用户验收的 1.6.8，本次没有替换安装包；既有三份 releases 文档删除仍只在本地工作区，公开源码保留原文件。
- 核验摘要与日志见 `evidence/records/github-release-summary.json`、`github-ci-summary.json` 及 `evidence/logs/github-ci-verification.log`。源码归档核验见 `evidence/records/public-source-verification.json`。
- 刘海机型、VoiceOver、第二台 Mac 及其它历史待验收项继续保留，不因发布改记通过。

公开源码归档完成下载及 ZIP CRC 校验，605 个已跟踪文件逐个比对标签内容一致，VERSION 为 1.6.8；首次 45 秒下载超时，随后独立完整下载成功。公开渲染 PNG 返回 HTTP 200 / image/png。最终证据清单含 21 份文件并已重新校验。

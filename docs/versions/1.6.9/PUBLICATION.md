# Minget 1.6.9 发布记录

日期：2026-10-17，Asia/Singapore。用户在本机正式安装版上复验通过（结论「可以了」），明确同意固化并准备发布，随后授权发布到 GitHub。

## 发布范围与准备

- 远端 main 为 `5bfb848`，Latest 为 v1.6.8；本次发布 v1.6.9，不涉及其他未发布版本。
- 当前分支 `codex/minget-1-6-9`，起点 `5bfb848`；改动为刷新范围与频率（App 视图模型与批次规则、Google 与托管账号的刷新入口、面板与设置文案、Core 旧机制清理、测试与版本资料），不改端点、认证、凭证边界、失败重试策略与点火口径。
- 正式 App 已为严格签名的 1.6.9（主程序 SHA-256 `68c09e577943bd22e9f8c390b57c21304b1ab0fe738effb0969e2cd6f6fde7ae`），staging、正式路径与归档三处一致；本次发布不再重建或替换安装包。
- `releases/README.md`、`releases/v1.0.0/README.md`、`releases/v1.0.1/README.md` 三份本地删除与版本无关，保持用户工作区原状并排除所有提交，远端保留历史文件。
- 发布前完整回归：Core 457 项 + App 249 项，共 706 项，701 通过、5 项既有跳过、0 失败，退出码 0（`swift test --scratch-path /tmp/minget-1.6.9-clean`），日志 `evidence/logs/publication-swift-tests.log`。
- 签名与安装记录复核：staging、正式路径与归档三处可执行文件哈希一致，`codesign --verify --deep --strict` 通过；见 `evidence/records/local-install.txt`。
- 发布前确认源码与安装包一致：构建后没有比安装包更新的源码文件；`VERSION` 为 1.6.9。
- 沿用源码分发，不上传本机签名包；刘海机型现场、VoiceOver 现场、第二台 Mac 与其他历史待验收项继续保留，发布不改变其结论。

## 推送与发布结果

- 发布提交 `04c3ffa`（`release: prepare Minget 1.6.9 refresh scope and frequency optimization`），`main` 从 `5bfb848` 快进到该提交并推送成功。监控期间遇到一次 `unexpected EOF`，重查后 CI 结论为成功；未修改系统或 Git 代理配置，也未重试任何已成功的操作。
- 远端 CI（run `39017709849`，push 事件，提交 `04c3ffa`）通过：`swift test` 与 Release 打包两个阶段全部成功，摘要见 `evidence/records/github-ci-summary.json`。
- Annotated tag `v1.6.9` 对象 `f48a905600eea935379eb52bc48de5a4f52b7acd`，远端解引用到发布提交 `04c3ffadf709ba4a002dcf3d472cc314aca2f592`。
- GitHub Release：[v1.6.9](https://github.com/ym911x/Minget/releases/tag/v1.6.9)，标题「Minget 1.6.9：刷新范围与频率优化」，发布时间 2026-10-17 16:39:02（Asia/Singapore）；latest 端点核验为 Latest、非草稿、非预发布、无自定义附件，继续源码分发，摘要见 `evidence/records/github-release-summary.json`。
- 公开源码归档核验：下载 v1.6.9 源码 tar.gz（27455402 字节，SHA-256 `3de0dc3ea3633ef63a7db4cc355cd294bf631a8170d65572b3a6a92af90073bd`），与 `git archive v1.6.9` 逐文件比对一致（各 624 个文件，`diff -r` 无差异），`VERSION` 为 1.6.9，见 `evidence/records/public-source-verification.txt`。
- 本机正式 App 仍为已由用户验收的 1.6.9，本次发布没有重建或替换安装包；三份既有 releases 文档删除仍只在本地工作区，公开源码保留原文件。
- 刘海机型现场、VoiceOver 现场、第二台 Mac 与其他历史待验收项继续保留，不因发布改记通过。

## 发布后独立复核补充（2026-10-17）

发现尚未修复的 P2：菜单栏某个 ChatGPT 账号刷新期间打开概览或 ChatGPT 页面，另一个账号的自动补刷会被全局 `isRefreshing` 直接丢弃，当前刷新结束后不会补上。隔离副本的 RefreshScopeTests 共 15 项，14 项既有测试通过，新增并发场景失败。详见 [复核记录](evidence/records/post-publication-review.md)、[确定性复现补丁](evidence/records/post-publication-overlap-regression.patch) 与 [测试日志](evidence/logs/post-publication-refresh-scope.log)。原 706 项回归和原用户验收记录保持原结论，本次不能记为无问题通过。

等待当前刷新结束后点品牌页「刷新」或页头「刷新全部」可绕过。v1.6.9 已在本次请求前公开发布，标签与 App 保持原样；修复应进入后续补丁。

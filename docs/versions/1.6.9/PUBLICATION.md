# Minget 1.6.9 发布记录

日期：2026-10-17，Asia/Singapore。用户在本机正式安装版上复验通过（结论「可以了」），并明确同意固化与准备发布。

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

待推送。用户确认后执行 `git push origin main`、创建 annotated tag `v1.6.9` 与 GitHub Release，并核验远端 CI；结果随后补记到本节。

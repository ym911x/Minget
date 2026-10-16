# Minget 1.6.8 发布记录

日期：2026-10-16，Asia/Singapore。用户明确授权将尚未发布的版本发布到 GitHub。

## 发布范围与准备

- 远端 main 为 `1592f46`，Latest 为 v1.6.6；尚未公开的版本为 1.6.7 与 1.6.8。本次统一发布 v1.6.8，包含 1.6.7 设置窗口视觉统一，不单独补发 v1.6.7。
- 当前分支 `codex/minget-1-6-8`，起点 `1a0a172`；逐项检查七个应用/Core 源文件差异与相关测试，变更限于菜单栏展示和设置列表，不改网络、认证、缓存及点火路径。
- 16 份既有证据的 SHA-256 清单与安装记录中的源码指纹全部复核通过。正式 App 版本 1.6.8，主程序 SHA-256 为 `97c2635dd0d2e5672474ce347a776cd6659a9fac5999643731f92d6bdf84be49`；bundle deep/strict 与两个内嵌程序 strict 签名均通过。本次不重建或替换正式安装包。
- 开始时工作区另有 `releases/README.md`、`releases/v1.0.0/README.md`、`releases/v1.0.1/README.md` 三份本地删除。这些与版本无关，保持用户工作区原状并排除提交，远端保留历史文件。
- 修正当前版本文档中的分支起点名称和时区；证据中的原测试、构建结果保持不变。
- 发布前完整回归通过：Core 458 项 + App 235 项，共 693 项，688 通过、5 项既有跳过、0 失败，退出码 0。命令 `swift test --scratch-path /tmp/minget-swiftpm-build --disable-sandbox`，日志 `evidence/logs/publication-swift-tests.log`。远端 CI 与公开 Release 结果待核验。
- 沿用源码分发，不上传本机签名包。刘海机型、VoiceOver、第二台 Mac 与其它历史待验收项继续保留，发布不改变验收结论。

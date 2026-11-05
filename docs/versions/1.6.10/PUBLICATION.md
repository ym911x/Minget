# 1.6.10 发布记录

2026-11-05（Asia/Singapore）。用户确认功能及间距复验通过，明确授权正式安装、推送与发布。

- 发布提交：436e1f0b0df5f98d6ee317cd9cdfd5eb3149b5a0；main 快进同步，annotated tag v1.6.10 已推送。
- CI 42057710864：测试和应用构建均 success。
- Release：https://github.com/ym911x/Minget/releases/tag/v1.6.10 ，Latest、非草稿、非预发布，沿用源码分发。
- 本机完整回归 706 项，701 通过、5 跳过、0 失败；见 evidence/publication-tests.log。
- /Applications/Minget.app 为严格签名 1.6.10，已从正式路径启动。主程序 SHA-256：04f5ac10471b18511cc1e293f31c6ef1f63483bf5200ed982e45d6b2a7e1aa3a，与用户验收包一致。
- 1.6.9 回滚备份：/tmp/minget-rollback-1.6.9-20261105/Minget.app。
- 三份 releases 文档删除保留本地，未提交；既有 ChatGPT 并发补刷问题及历史待验收项目保持原状态。

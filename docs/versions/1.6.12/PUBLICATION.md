# 1.6.12 发布记录

2026-11-18（Asia/Singapore），用户确认本机 1.6.12 审核通过，并授权同步 GitHub。

- GitHub 最新正式版为 [v1.6.12](https://github.com/ym911x/Minget/releases/tag/v1.6.12)，沿用源码分发。发布标签指向 `a2869fce99efcc50c7feafb7568b9b791d9841d6`。
- GitHub 原运行环境 `macos-14` 在执行测试前被拒绝。改用 `macos-15` 后，发布提交的[测试与应用构建](https://github.com/ym911x/Minget/actions/runs/44288216010)全部通过。
- 本机正式安装为 1.6.12，严格签名校验通过，主程序 SHA-256 与[验收记录](ACCEPTANCE.md)一致。完整本机回归 713 项，708 通过、5 项既有跳过、0 失败。
- 主目录 main 快进到发布线。API Key 提示、刷新和相关测试改动及三份发布文档删除保留为本地修改。

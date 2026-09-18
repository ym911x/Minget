# 参与贡献 / Contributing

## 中文

感谢关注明明有数 · Minget。提交修改前请先创建 Issue，说明问题、预期行为和拟议范围。

开发要求：

1. 使用 macOS 13 或以上版本和 Swift 5.9 或以上版本。
2. 不读取现有浏览器 Cookie 或 Codex、Claude 全局认证文件。
3. 不在代码、测试、日志和文档中加入真实凭据。
4. Provider 余额只能来自已验证的只读接口，不得使用估算或模拟值冒充真实数据。
5. 提交前运行 `swift test --scratch-path "${TMPDIR:-/tmp}/minget-tests"` 和 `./scripts/build.sh`，避免在 iCloud 项目目录生成构建缓存。

## English

Thank you for your interest in Minget. Before submitting a change, open an issue describing the problem, expected behavior, and proposed scope.

Development requirements:

1. Use macOS 13 or later and Swift 5.9 or later.
2. Do not read existing browser cookies or global Codex and Claude authentication files.
3. Never place real credentials in code, tests, logs, or documentation.
4. Provider balances must come from verified read-only sources. Estimated or mock values must never be presented as real data.
5. Run `swift test --scratch-path "${TMPDIR:-/tmp}/minget-tests"` and `./scripts/build.sh` before submitting a change so build caches stay outside the iCloud-hosted repository.

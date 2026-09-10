# v1.0 验证产物

正式归档时的测试、构建和签名检查日志保存在项目根目录的 `artifacts/release-v1.0/`。

`artifacts/` 被 Git 忽略，原因是日志可能包含用户名、设备路径、进程信息或其他本机环境信息。源码和资料的一致性由上级目录的 `MANIFEST.sha256` 记录。

归档日志包括：

- `tests.log`：完整自动化测试输出。
- `build.log`：Release 构建输出。
- `verification.txt`：版本、Info.plist、签名和发布包校验结果。

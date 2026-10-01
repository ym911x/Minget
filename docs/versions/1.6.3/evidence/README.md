# 1.6.3 证据说明

- `swift-tests.log`：最终完整测试，环境为本机 macOS；启动测试指向最终签名候选；此前正式安装版同样通过，临时禁用定时点火。
- `signed-process-tests.log`：最终候选签名包的冷启动和退出子进程检查。
- `late-response-tests.log`：两项新增迟到响应场景及其他账号管理定向回归，全部使用假网络/Keychain。
- `release-build.log`：最终 Release 编译、稳定本机签名及严格验证。
- `local-install.txt`：版本、应用备份与 candidate/archive/installed 指纹核对。
- `synthetic-accounts-{light,dark}.png`、`synthetic-add-api-{light,dark}.png`：真实 SwiftUI 组件的示例渲染，无真实 Key 或额度。离屏渲染未绘制侧栏，不能用于证明原生窗口现场交互；现场交互另见 ACCEPTANCE.md。

本目录不保存真实用户账号截图、AX 明细或认证文件。记录仅用于本机交付，没有公开发布。

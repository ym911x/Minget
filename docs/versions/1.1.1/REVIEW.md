# 1.1.1 审核状态

独立审核已完成。自动测试、Release 构建和签名均通过；已在正常启动的
`/Users/yuyimeng/Applications/Minget.app` 完成以下真实界面检查：

- 设置页将 OpenAI Codex 与 DeepSeek 显示在同一服务模块。
- 退出文案为“退出明明有数”。
- 关于弹层可显示，点击弹层外或按 Escape 都可关闭，GitHub 链接会触发默认浏览器。

验证依据：`swift test` 292 项通过；`scripts/build.sh`、Info.plist 版本 1.1.1 和严格签名检查通过。

限制：为避免中断当前菜单栏进程，本轮没有点击退出按钮；受控停机路径由自动测试覆盖。DeepSeek 真实账号与真实 Codex 本机服务请求本轮未重新验证。真实 Keychain 迁移仍需由已存在旧 GLM 数据的升级环境确认。

# Claude Code Round 5 修订任务

继续修订当前额度显示小组件，直到满足 v1.1 方案与 Codex 第四轮审核。先阅读 `AGENTS.md`、`ROUND_4_REPORT.md`、`PROVIDER_ENDPOINTS.md` 和现有源码，保留已经通过的 192 项测试。

必须修复以下问题：

1. `StatusItemController` 不能直接用 `NSStatusItem()` 创建状态项。改为通过 `NSStatusBar.system.statusItem(withLength:)` 注册到系统菜单栏，并在应用退出时正确停止监视器、关闭 popover/详情窗口、调用 `removeStatusItem`。确保稳定 `autosaveName`、几何检测和 full/compact/icon 状态机继续工作。
2. 保存 GLM API Key 后必须立即执行 API Key 只读探测并发布脱敏 observation。合同未确认时不能把它交给普通余额 `read()` 后直接失败。字段和金额口径未确认前仍禁止显示余额。
3. 保存 GLM 控制台会话后必须立即执行 Cookie 会话的只读探测并发布 observation。不得要求用户再手动点一次“探测”。401/403、过期会话和 HTTP 200 业务错误需要准确分类；认证失败应暂停自动重试，重新连接后恢复。
4. 修复 `RedirectGuardDelegate.refusedRedirect` 的跨请求污染和并发串扰。拒绝状态必须按具体 task/request 隔离；一次跨域重定向不能让之后无关的网络错误被误报。
5. 增加针对应用接线的测试或可验证检查，覆盖系统状态项注册/清理、保存两种 GLM 凭证后立即探测、重定向状态不污染后续请求。不要只测试孤立工具函数。
6. 完整复核菜单栏、Codex 账号、DeepSeek、GLM、Keychain、刷新、缓存隔离及禁止模型端点要求。不要读取或打印真实 API Key、全局认证配置或现有浏览器 Cookie，不提交、不推送。
7. 真实运行 `swift test`，修复全部失败直到通过；运行 `./scripts/build.sh`；确认 `dist/UsageMonitor.app` 重新生成；完成安全的启动、退出和子进程清理检查。
8. 更新 `ROUND_4_REPORT.md` 或新增 `ROUND_5_REPORT.md`，写入真实执行命令、测试数量、构建结果、修复内容和仍需用户实机验证的事项。

请连续执行常规代码修改、测试和构建，不要中途等待确认。完成后停在最终报告界面。

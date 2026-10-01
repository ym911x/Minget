# v1.6.0 实施记录

工作分支：codex/minget-google-quota，基于 1.5.0 分支提交 97148f0，独立管理工作树，不修改原 1.5.0 工作树。

新增 AntigravityProvider、AntigravityModel 和 AntigravityViews，扩展 Keychain credential key、严格拒绝重定向的可选 transport 模式、Google 显示偏好、菜单栏稳定账号与额度组选择、详情与窗口尺寸接线。所有已有 Provider 请求模式保持原有默认值。

执行命令：swift build --scratch-path /tmp/minget-google-build --disable-sandbox；swift test --scratch-path /tmp/minget-google-build --disable-sandbox；swift test --scratch-path /tmp/minget-google-build --disable-sandbox --filter Antigravity。首轮完整测试零失败，Google 专项测试通过。最终复验 Core 409 项、App 172 项，零失败；1 项 AX 环境测试跳过。完整输出保存在 evidence/swift-test.log。

不自动读取本机 management-key.txt。真实服务验收依赖用户在签名应用管理账号表单输入密钥。Google 登录与启停继续使用 CPA 管理面板。


最终构建使用 scripts/build.sh，环境变量 MINGET_BUILD_SCRATCH_DIR=/tmp/minget-google-release、MINGET_STAGING_DIR=/tmp/minget-google-staging/Minget.app、MINGET_RUN_PATH=/tmp/minget-google-verified/Minget.app、MINGET_ARCHIVE_PATH=/tmp/minget-google-archive/Minget.app。Minget Local Signing 签名，脚本所有严格校验通过，日志见 evidence/release-build.log。

最终安装路径：/Users/<user>/Applications/Minget.app，CFBundleShortVersionString=1.6.0。原 1.5.0 备份：/Users/<user>/Applications/Minget Backups/1.5.0-20260929-220903/Minget.app。安装后已重启正确的 UsageMonitor 可执行文件，通过 --show-accounts 打开 Google 连接表单并做原生 AX 和截图检查。管理密钥仍为空，未读取任何磁盘密钥或 Google 授权文件。

明暗卡片图片为合成数据的布局证据，实际账号卡片与菜单栏归属仍待真实连接验收。当前菜单栏来源未改动，Google 初次连接后默认启用详情显示；菜单栏账号和额度组需要用户选择。

收尾修正：多个 CredentialAccessCoordinator 默认共用进程级串行队列，避免 Keychain 交互策略重叠；已选额度组丢失时显示“额度组不可用”，不转选其他组；Google 时间条只对应当前显示周期。新增两项回归测试覆盖组丢失和跨协调器串行访问。

修改文件清单：

- Core：新增 Providers/AntigravityProvider.swift；修改 Providers/ProviderModels.swift、Providers/ProviderRequestGuard.swift、Providers/CredentialAccessCoordinator.swift、Utilities/MenuBarContent.swift。
- App：新增 ViewModels/AntigravityModel.swift、Views/AntigravityViews.swift；修改 UsageMonitorApp.swift、StatusItem/StatusItemController.swift、ViewModels/DetailPreferences.swift、ViewModels/MenuBarPreferences.swift、ViewModels/MenuBarRefreshPolicy.swift、ViewModels/UsageViewModel.swift、Views/AccountManagementView.swift、Views/MingetAboutView.swift、Views/MingetSettingsView.swift、Views/ResetTimeBarsView.swift、Views/UsagePanelView.swift。
- Tests：新增 UsageMonitorCoreTests/AntigravityProviderTests.swift、UsageMonitorAppTests/AntigravityModelTests.swift。
- 构建与资料：scripts/build.sh、VERSION、AGENTS.md、README.md、ROADMAP.md、CHANGELOG.md、PROVIDER_ENDPOINTS.md、REVIEW.md 和 docs/versions/1.6.0/。旧版本目录未修改。

已知未完成项与外部限制见 ACCEPTANCE.md。未发布、未推送、未发起模型生成或额度重置请求。

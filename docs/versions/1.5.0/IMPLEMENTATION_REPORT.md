# v1.5.0 实施记录

已在独立工作树实现 v1.5.0，版本号更新为 1.5.0。没有修改冻结的 `docs/archive/v1.0/`，没有推送或发布。

修改范围：

- `DetailPreferences`、`UsagePanelView`、`MingetSettingsView`：持久化两种显示模式和当前标签，按稳定供应商标识筛选，固定底部操作区，短屏仅滚动卡片；切换不调用刷新。
- `StatusItemController`：菜单栏重复点击关闭浮窗，切换标签时调整浮窗高度，复用设置和账号窗口。独立详情窗口沿用现有备用入口。
- `FirstRunGate`、`AccountManagementView`、`UsageMonitorApp`：新安装显示一次可跳过连接界面，已有本应用偏好或缓存的升级用户不强制引导。
- `CodexAppServerClient`、`UsageService`、`UsageViewModel`：官方 ChatGPT 浏览器登录 RPC、取消与完成通知；单个交互登录，匹配登录 ID 和连接代次，登录时暂停相应账号的额度读取，完成后使用现有刷新引擎读取身份和额度。
- `README.md`、`ROADMAP.md`、`PROVIDER_ENDPOINTS.md` 和本目录：版本说明及接口依据。

验证：`swift test --disable-sandbox` 完整通过（Core 395 项，App 162 项，其中 1 项原有辅助功能测试跳过）；新增的早到登录通知、筛选高度测试通过。最终 Release 构建由 `scripts/build.sh` 完成，`codesign --verify --deep --strict` 对暂存包和已安装包均通过。已备份原 1.4.3 安装包，最终 1.5.0 安装于 `/Users/yuyimeng/Applications/Minget.app`。签名包启动后观察到两个隔离 app-server 子进程；发送 SIGTERM 后主进程及两个子进程均退出，随后重新启动。

验收边界：Mac 已解锁，本应用偏好中的两个隔离账号额度缓存时间戳在签名版运行期间更新，证明既有连接的真实只读取数成功。当前桌面自动化无法直接定位无窗口的菜单栏图标，菜单栏点击、Esc、窗口切换等真实界面操作仍待验收。真实 ChatGPT 首次浏览器授权、DeepSeek/Command Code Keychain 提示和第二台 Mac 首次使用也尚无本版实测证据。模拟 RPC、静态渲染和进程检查不能替代这些验收。不记录真实凭证或授权 URL。

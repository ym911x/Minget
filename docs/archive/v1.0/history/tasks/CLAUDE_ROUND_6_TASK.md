# Claude Code Round 6 修订任务：DeepSeek Key 保存无反馈

用户实测：在正式构建的应用中输入 DeepSeek API Key，反复点击“保存”没有任何反馈，也无法确认是否保存。

已定位的根因：`AppContainer` 使用 `UsageViewModel(service:providerEngine:)`，没有传入 `credentials`；`UsageViewModel.saveDeepSeekKey` 在 `guard let credentials else { return }` 静默返回。现有应用接线测试使用了显式内存 credentials，因此没有覆盖生产组合根。

请完成以下修订：

1. 修复生产接线。优先让 `DeepSeekReading` 像 `GLMReading` 一样负责保存/替换自己的 API Key，并由 ViewModel 通过 engine reader 调用，避免 ViewModel 另外持有一份可能漏传的 credential store。删除会导致静默失败的可选依赖路径。若采用其他设计，也必须让生产 `AppContainer` 与测试使用同一条保存路径。
2. 增加明确的用户反馈状态，至少覆盖：正在保存、已保存并正在验证余额、保存失败、Key 无效或认证失败、验证成功、网络失败但 Key 已保存在本机。不要显示或记录 Key 内容。
3. 保存按钮点击后立刻显示反馈。只有本地钥匙串保存成功后才能清空输入框；保存失败时保留输入，允许重试。成功连接后可以显示“已连接”或同等明确状态。
4. Keychain 错误不能只写日志。界面需要显示固定、安全且可理解的错误，不得带系统返回的敏感文本。
5. DeepSeek 保存成功后立即调用官方只读余额接口验证，不调用任何模型接口。401/403 明确显示 Key 无效；断网显示“Key 已保存，暂时无法验证”；成功显示余额和最近更新时间。
6. 删除 Key 后显示“已删除/未连接”，清除对应余额缓存和认证暂停状态。
7. 增加生产组合根或等价应用接线测试，必须能捕获本次 `credentials == nil` 静默返回问题。增加 UI/ViewModel 状态测试：保存成功、Keychain 保存失败、401、网络失败、成功连接、删除。
8. 保留已有 212 项测试，真实运行 `swift test` 直到全部通过，再运行 `./scripts/build.sh`，确认 `dist/UsageMonitor.app` 重建。做启动和退出清理检查。
9. 新增 `ROUND_6_REPORT.md`，记录根因、具体修复、真实测试数量、构建结果和用户实机复测步骤。不要提交或推送，不要读取或打印任何真实 Key、认证配置或浏览器 Cookie。

请持续执行直到测试、构建和报告全部完成，不要中途等待常规修改授权。

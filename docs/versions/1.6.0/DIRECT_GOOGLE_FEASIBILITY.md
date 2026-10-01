# Google 官方直连与双账号登录可行性（2026-09-30）

后续更新：用户已改为允许官方 CLI。真实 `/usage` JSON 读取已成功，见 [OFFICIAL_CLI_PROBE.md](OFFICIAL_CLI_PROBE.md)。下文为此前直连调查历史；其中把宽泛条款推定为只读额度访问必然被禁止的结论过度，不能作为官方 CLI 技术验证的终止依据。

## 当前需求

Minget 自行完成两个 Google 账号的桌面 OAuth 登录、续期、Keychain 隔离和官方额度查询。首次使用显示登录入口，日常启动显示已确认的额度；不依赖 CLIProxyAPI、Antigravity、Google CLI 或其他本机程序。需读取 Google 官方返回的额度组、5 小时与周额度及重置时间，在两个账号和第二台 Mac 上真实验收。

## 前置结论

**暂停 Google 官方直连实施。** Google Antigravity [附加服务条款第 6 条](https://antigravity.google/terms)明确把第三方软件访问 Antigravity 服务列为违约，且提到可能暂停或终止 Antigravity 和 Gemini CLI 账号。[官方 FAQ](https://www.antigravity.google/docs/faq/)也直接确认该限制。Minget 即使使用自己注册的桌面 OAuth 客户端，直接请求 Antigravity 内部额度端点，仍属于第三方软件访问该服务。OAuth 授权成功和 HTTP 接口返回成功都不能解除此限制。

已检查的官方额度显示入口为 Antigravity 应用设置页和 [Antigravity CLI `/usage`](https://antigravity.google/docs/cli/commands/usage/) 交互面板；后者需要安装 CLI，不满足本项目的独立运行要求。[Cloud Quotas API](https://docs.cloud.google.com/docs/quotas/api-overview)面向 Google Cloud 项目额度，不能据此推断个人 Antigravity 账号的 5 小时和周剩余额度。未找到 Google 公开授权 Minget 读取这些个人额度的 API 文档；这表示目前缺少合规依据，并非证明将来不会发布。

官方桌面 [OAuth 授权码、PKCE 与 loopback 流程](https://developers.google.com/identity/protocols/oauth2/native-app)只说明身份授权方式，不授予第三方使用 Antigravity 内部服务的权利。[Google OAuth 测试状态](https://support.google.com/cloud/answer/15549945?hl=en)的非基本身份范围授权还会在七天后到期，不能作为长期交付方案。

## 本轮实际检查与边界

- 阅读现有 1.6.0 代码、版本资料和 `PROVIDER_ENDPOINTS.md`。现有实现仍通过本机 CLIProxyAPI 管理端点获取额度，账号窗口要求代理地址和管理密钥，不符合新的直连与跨 Mac 登录需求。
- 阅读 Google 官方 Antigravity 条款、FAQ、额度文档、Cloud Quotas 文档和桌面 OAuth 文档。此前对官方安装包的只读检查确认 `retrieveUserQuotaSummary` 的方法名与响应结构，但它是内部协议，不能据此认定第三方客户端可用或被允许使用。
- Google Cloud 首次启用页面要求接受服务条款。未勾选条款、未创建项目或 OAuth 客户端、未请求两个账号授权，也未调用内部额度端点；没有读取任何真实令牌或额度。
- 因前置限制已明确，未替换代理实现、未新增 Google 登录页、未做合成数据演示，也未构建或安装新的版本。昨日原型实现及说明保留，不能按新需求视为已交付。

执行的本地检查包括 `git status --short`、`rg -n 'Antigravity|Google' Sources/UsageMonitorCore`、读取 `README.md`、`ROADMAP.md`、`PROVIDER_ENDPOINTS.md` 和 `docs/versions/1.6.0/`。本轮仅修改文档，没有代码或自动测试运行；昨日自动测试结果不能验证新方案。

## 重新启动条件

需 Google 发布或明确授权第三方使用的个人 Antigravity 额度只读 API，并允许独立桌面 OAuth 客户端访问。届时先以 Minget 自有客户端完成真实只读查询与口径核对，再继续双账号登录、界面、缓存和第二台 Mac 验收。若仅有 Cloud 项目额度 API，其数据与个人 Antigravity 额度不同，需另立需求。

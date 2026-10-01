# 安全说明 / Security

## 中文

请不要在公开 Issue、Discussion、日志或截图中提交 API Key、Cookie、访问令牌、邮箱、账号响应或其他敏感信息。

如果发现可能泄露凭据、绕过请求白名单、跨域发送认证信息或调用模型推理端点的问题，请先通过 GitHub 私密漏洞报告功能联系维护者。仓库启用该功能后，可以在 Security 页面选择“Report a vulnerability”。

提交报告时请提供受影响版本、复现步骤和影响范围，并删除所有真实凭据和账号数据。

### Google 官方 CLI

Minget 的 Google 功能由官方 CLI 在本机专用账号目录保管授权，不读取或复制认证文件。请勿上传 `~/Library/Application Support/Minget/AntigravityCLI/profiles/`、账号连接元数据、一次性授权码或包含真实身份的登录画面。公开截图使用标明示例的展示副本；额度查询只使用官方 `/usage`，不通过模型请求验证登录。

## English

Do not include API keys, cookies, access tokens, email addresses, raw account responses, or other sensitive information in public issues, discussions, logs, or screenshots.

For vulnerabilities involving credential exposure, request allow-list bypasses, cross-origin authentication data, or model inference endpoints, use GitHub private vulnerability reporting after it is enabled for this repository. Open the Security page and select “Report a vulnerability”.

Include the affected version, reproduction steps, and impact. Remove all real credentials and account data before submitting a report.

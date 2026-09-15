# 1.2.0 需求

## 目标

在 1.1.2 基线上接入一个个人 Command Code API Key 的只读用量展示。详情页默认显示，设置可隐藏，菜单栏继续只显示 Codex 的 5 小时和周额度。

## 数据与安全边界

- Key 只能由用户在应用内输入并存于 macOS Keychain。不得读取浏览器 Cookie、现有浏览器会话、Command Code CLI 或本地认证文件。
- 认证请求仅允许 `https://api.commandcode.ai` 的 `GET /alpha/billing/credits`、`GET /alpha/usage/summary` 和可选 `GET /alpha/billing/subscriptions`。
- 只发送 Bearer 认证和 JSON Accept。若真实服务还要求未公开的 CLI 伪装头，停止正式接入并报告接口口径未确认。
- 拒绝跨域重定向、所有未列路径与模型端点。不得调用 `/alpha/generate`、chat completions、messages 或任何模型端点。
- 数据缺失、字段漂移、网络或 5xx 保留最后成功缓存并标记过期；没有缓存时显示不可用。401/403 暂停自动重试直至手动重新连接。

## 展示

显示 5 小时、周和月度信用额，当前统计周期的 token、输入输出 token、请求数、成功失败、成功率和成本。未知统计周期必须标记。月度总额只在真实响应证明已用与剩余属于同一周期时派生。

## 非目标

不包含逐请求历史、组织或多账号切换、Command Code 菜单栏指标、通知、模型调用、远端推送、标签或 GitHub Release。

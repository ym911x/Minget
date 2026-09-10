# 服务端点与取数依据

更新日期：2026-09-10  
适用版本：1.0.0

本文件记录正式版本实际使用的数据来源、验证级别和安全边界。开发期间的完整调查记录已归档至 `docs/archive/v1.0/evidence/PROVIDER_ENDPOINTS_DEVELOPMENT.md`。

## 验证级别

| 级别 | 含义 |
| --- | --- |
| A | 在本机真实服务或真实账号上完成验证 |
| B | 有服务商公开文档或官方部署代码支持，且由自动化测试固定请求和响应结构 |
| C | 仅由自动化测试或第三方资料支持，尚未完成真实账号验证 |

## Codex

### `account/rateLimits/read`

- 传输：本机 `codex app-server` 的 stdio JSON-RPC。
- 用途：读取额度窗口、已用百分比和重置时间。
- 验证：A。真实本机服务已验证，解析和进程生命周期由自动化测试覆盖。

### `account/read`

- 参数：`{"refreshToken": false}`。
- 用途：读取账号类型和可用的邮箱标识。
- 验证：请求为 A，响应结构为 B。响应结构依据本机 Codex 协议 schema，线上账号显示已由用户实际运行确认。
- 边界：不读取 `~/.codex/auth.json`，不触发 token 刷新。

菜单栏安全区域检查只读取本机屏幕和状态项几何位置，不调用网络或模型。

## DeepSeek

### `GET https://api.deepseek.com/user/balance`

- 认证：`Authorization: Bearer <API Key>`。
- 字段：`is_available`、`balance_infos[].currency`、`total_balance`、`granted_balance`、`topped_up_balance`。
- 验证：A。接口结构来自 DeepSeek 官方文档，用户已用真实账号确认余额显示。
- 金额规则：使用 `Decimal`；不同币种分别显示；不换算、不合计、不把缺失字段显示为零。
- 凭据：API Key 只保存在 macOS Keychain。

该请求是余额查询，不调用生成模型，不产生模型 token 消耗。

## 智谱 GLM

### `GET https://bigmodel.cn/api/biz/account/query-customer-account-report`

- 认证来源：应用内独立 `WKWebView` 登录会话。
- 请求头：应用自建会话中的 `bigmodel_token_production` 对应 `Authorization`，以及该页面 localStorage 中可用的 `Bigmodel-Organization`、`Bigmodel-Project`。
- 金额字段：响应 `data` 下的 `balance`、`availableBalance`、`rechargeAmount`、`giveAmount`、`totalSpendAmount`、`frozenBalance`。
- 币种：官方控制台前端以人民币元显示该国内账户数据，应用显示为 CNY。
- 验证：A。端点、请求头和字段结构依据 2026-09-10 检查的智谱官方部署前端代码；用户随后在应用独立登录会话中确认真实余额及明细显示。
- 稳定性：该端点是控制台内部接口，未被视为公开稳定 API。官网改版后可能需要适配。

应用不读取已有浏览器 Cookie。会话只保存在应用自己的 WebKit 数据存储和 Keychain，且只用于智谱官方域名的只读余额请求。该请求不调用推理接口，不产生模型 token 消耗。

### API Key 兼容路径

代码保留 `https://open.bigmodel.cn/api/paas/v4/balance` 的兼容实现和严格解析测试，但缺少智谱公开稳定文档，也未在用户账号上证实可用。正式使用路径为应用内控制台登录，界面不应引导用户依赖该兼容路径。

## 通用安全规则

- 所有带认证请求拒绝跨域重定向。
- 请求路径使用白名单，模型推理端点被显式拒绝。
- 日志和诊断仅记录固定错误类别及脱敏结构，不记录凭据、Cookie 值、账号原始响应或上游错误正文。
- 余额缺失、字段不合法或接口口径不明时显示不可用，不伪造为零。
- 测试使用合成凭据，不包含真实 API Key。

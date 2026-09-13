# 服务端点与取数依据

更新日期：2026-09-13
适用版本：1.1.1

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

### `GET https://status.deepseek.com/`

- 认证：无。只读取公开状态页，不发送 DeepSeek API Key。
- 用途：详情页 DeepSeek 卡片顶部的小型“服务状态”标识。
- 解析：读取官方页面当前状态标题，例如 `Everything is running smoothly` 和
  `All systems are operating as expected` 映射为“服务正常”；无法识别或页面不可达时显示“状态暂不可用”。
- 验证：B。2026-09-13 从 DeepSeek 官方状态页确认页面当前公开展示整体状态和系统状态；页面使用 FlashDuty 渲染，旧的 Atlassian `/api/v2` JSON 路径已不再作为本实现的接口依据。HTML 标题解析由本地 fixture 测试覆盖。
- 边界：仅显示整体状态与官方状态页入口，不抓取事件正文，不把历史事件文本当作当前状态，不调用模型接口。

## 已退役的智谱 GLM

1.1.1 不再发送智谱请求，也不再创建 WebKit 登录窗口或解析控制台响应。首次启动仅针对本应用先前创建的两个精确 Keychain account 名称及本地缓存、连接模式和显示偏好做清理。Keychain 清理失败不会阻止启动，且不会记录任何凭据值；下一次启动会重试。

## 通用安全规则

- 所有带认证请求拒绝跨域重定向。
- 请求路径使用白名单，模型推理端点被显式拒绝。
- 日志和诊断仅记录固定错误类别及脱敏结构，不记录凭据、Cookie 值、账号原始响应或上游错误正文。
- 余额缺失、字段不合法或接口口径不明时显示不可用，不伪造为零。
- 测试使用合成凭据，不包含真实 API Key。

---

## English summary

This document records the data sources, evidence level, and security boundaries used by Minget 1.0.0.

### Codex

- `account/rateLimits/read` and `account/read` are called through the local `codex app-server` stdio JSON-RPC connection.
- `account/read` uses `{"refreshToken": false}` and does not read `~/.codex/auth.json`.
- Menu bar geometry checks are local and do not use network requests or model tokens.

### DeepSeek

- Minget calls the documented `GET https://api.deepseek.com/user/balance` endpoint.
- Amounts use decimal arithmetic and currencies remain separate.
- The API key is stored only in macOS Keychain and is never used for model inference.
- The detail panel reads the unauthenticated headline from `GET https://status.deepseek.com/` for a compact “today's service status” line. A parser failure is shown as unavailable, never as operational.

### Retired Zhipu GLM integration

- Minget 1.1.1 does not call any Zhipu endpoint or access an existing browser session.
- Legacy app-owned credentials and cached entries are retired locally at launch only.

### Shared safeguards

- Authenticated requests reject cross-origin redirects.
- Provider clients use endpoint allow-lists and explicitly block model inference paths.
- Logs and diagnostics exclude keys, cookie values, tokens, raw account responses, and upstream error bodies.
- Missing or invalid balance fields are reported as unavailable and are never converted into fabricated zero values.

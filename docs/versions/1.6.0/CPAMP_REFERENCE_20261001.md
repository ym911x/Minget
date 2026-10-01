# CPA Manager Plus 取数与授权方案核对

日期：2026-10-01，Asia/Shanghai。目标：核对用户本机面板为何能显示真实额度，提取 Minget 可以借鉴的做法。本次没有切换应用后端、修改反代或读取 Google OAuth 文件。

## 已确认的调用链

```text
CPA Manager Plus 网页面板
  → 本机 CLIProxyAPI 管理 API（8317）
    → 根据 authIndex 选择账号并填入其授权 token
      → Google 官方 retrieveUserQuotaSummary
        → groups / buckets → 5 小时、周剩余与重置时间
```

面板依赖 CLIProxyAPI；此路径不运行官方 `agy /usage`。剩余比例来自 Google，认证及代发请求由本机代理完成。

本机静态面板约 6.4 MB，内嵌代码包含相同端点、token 占位符和解析逻辑。上游源码按当前安装版 v1.14.1 核对，commit `aa8c5e9886b42ec82d78a419a1e1f59700ca90c5`。CLIProxyAPI 后端按 v8.0.4 核对，commit `d33f63f8e3d98428440ebca5a5b6a981a61ff71e`。

## 额度查询如何实现

[providerRequests.ts](https://github.com/seakee/CPA-Manager-Plus/blob/v1.14.1/apps/web/src/utils/quota/providerRequests.ts) 的 `fetchAntigravityQuota`：从账号元数据取 `authIndex` 与 project，调用管理 `/api-call`，先查询官方 Summary，不支持时尝试 Models。限流停止；订阅套餐另行查询。

请求的关键结构如下，变量由当前连接提供，不在文档保存真实认证值：

```json
{
  "authIndex": "<selected-account-index>",
  "method": "POST",
  "url": "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
  "header": {
    "Authorization": "Bearer $TOKEN$",
    "Content-Type": "application/json",
    "User-Agent": "antigravity/cli/1.0.13 (aidev_client; os_type=darwin; arch=arm64)"
  },
  "data": "{\"project\":\"<account-project>\"}"
}
```

`$TOKEN$` 由 CPA 替换，面板不需要自己对这次查询提取 token。[管理 API 文档](https://github.com/router-for-me/CLIProxyAPIDocs/blob/main/docs/en/management/api.md)说明了代发与占位符协议。请求 body 中有 POST 不代表模型调用，目标是固定的只读额度方法。

[builders.ts](https://github.com/seakee/CPA-Manager-Plus/blob/v1.14.1/apps/web/src/utils/quota/builders.ts) 的 `buildAntigravityQuotaGroups` 优先使用 Summary 的组与桶，读取 `remainingFraction`、`window`、`resetTime`；显示层把比例转成百分比。

如果只有 Models 响应，它还会按模型类别构造共享组、取最低比例，并在特定缺失情形采用 0。这些回退推断不能照搬到 Minget 的真实数值口径；Minget 继续保留未知与真实零的区别，以官方明确组与周期为准。

## 本次真实验证

2026-10-01 01:02:07 左右，使用现有本机管理连接，分别对两个账号代发一次固定 Summary 请求，两者 Google 上游 HTTP 200。project 从公开账号元数据的顶层字段取得，未下载授权文件。只输出规范化额度字段，未发起模型请求。

| 本次枚举编号 | Gemini 5h | Gemini 周 | Claude/GPT 5h | Claude/GPT 周 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 99.82% | 99.88% | 100.00% | 97.99% |
| 2 | 98.56% | 98.72% | 100.00% | 93.76% |

枚举编号仅用于本次证据，不作为应用的 A/B 身份或缓存键。

两个账号均返回 `Gemini Models`、`Claude and GPT models`；桶 ID 为 `gemini-5h`、`gemini-weekly`、`3p-5h`、`3p-weekly`，周期明确为 `5h` 与 `weekly`，各有 UTC ISO 重置时间。采样时间与截图不同，不声称本次数字与截图同刻逐项一致。

截图上方的历史请求数、Token、费用、成功率是代理调用历史/统计，与下方官方剩余额度是两类数据。不能用本机请求数推算 Google 全账号额度，也不能把截图的“Claude”标签理解为逐模型独立额度；真实返回是 Claude/GPT 共享组。

## 登录为何更容易做成网页入口

[oauth.ts](https://github.com/seakee/CPA-Manager-Plus/blob/v1.14.1/apps/web/src/services/api/oauth.ts) 的流程：启动 `antigravity-auth-url`，取得 URL/state；用户浏览器授权；查询 `get-auth-status`，必要时提交 `oauth-callback`，取消使用对应 session。授权与查询生命周期明确分离。

本次源码检查确认：CLIProxyAPI 的 `RequestAntigravityToken` 和 `AntigravityAuth` 自行构造 Google 授权请求、交换授权码、取得账号身份和项目并保存授权。它不依赖官方 CLI 的主题、条款或信任目录交互。没有在本次启动新 OAuth 会话或改变现有账号。

这说明它能直接复用代理已有登录，不能证明 Minget 自有 OAuth 客户端权限已经验证，也不能证明复制另一应用的 OAuth 客户端配置即可成为 Minget 正式授权。

## Minget 可借鉴的内容及当前差距

| 内容 | 可以采用的做法 |
| --- | --- |
| 数据口径 | Summary 为首选；按真实组、5h/weekly、精确比例和 UTC 重置时间展示 |
| 身份隔离 | 身份来自认证结果/账号元数据，缓存绑定身份，不能按列表下标绑定 |
| 登录状态 | 启动、待用户操作、完成、失败、取消分阶段管理，独立于额度读取状态 |
| 异常与缓存 | 读取失败保留有明确时间的旧数据，单账号失败不阻塞另一账号 |
| 显示 | 同一共享组分别显示五小时和周额度；不把共有额度拆成每模型额度 |

Minget 旧 `AntigravityProvider.swift` 已有相同的 `/auth-files`、`/api-call`、Summary/Models 调用及结构字段。当前真实响应与其预期主字段一致，这是源码对照结果；本次未将完整真实响应送入 Swift 解析器做额外运行验收，也未把该旧路径恢复为生产交付。

因此，之前的未交付不能解释成没有找到可读取额度的方法。主要缺口是正式认证闭环、UI/服务接线、缓存及刷新，以及安装版未替换。

保持原定独立运行目标时，借鉴上述结构和状态管理，继续由官方 CLI 管理授权并读取 `/usage`。若改为复用当前 CPA 后端，则可免去 Minget 再次独立登录，直接使用已有两账号；但新电脑也需要 CPA 和对应登录环境，这属于依赖方案变更，不能不说明就切换。

## 处理记录

本次只进行了公共源码对照、两次官方额度只读代查及文档记录。Google OAuth token/授权文件未读取或复制，模型请求未发送；Minget 运行代码、安装包和反代配置未改。该记录是后续实现依据，不能替代正式 UI、独立登录与跨 Mac 验收。

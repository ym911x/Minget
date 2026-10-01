# 服务端点与取数依据

更新日期：2026-10-01
适用版本：1.6.3

本文件记录正式版本实际使用的数据来源、验证级别和安全边界。开发期间的完整调查记录已归档至 `docs/archive/v1.0/evidence/PROVIDER_ENDPOINTS_DEVELOPMENT.md`。

## 验证级别

| 级别 | 含义 |
| --- | --- |
| A | 在本机真实服务或真实账号上完成验证 |
| B | 有服务商公开文档或官方部署代码支持，且由自动化测试固定请求和响应结构 |
| C | 仅由自动化测试或第三方资料支持，尚未完成真实账号验证 |

## 1.6.3 多账号边界

- 每个连接使用稳定账号 ID。ChatGPT 沿用官方 app-server，每个 Profile 独立 `CODEX_HOME`；Google 继续使用固定官方 CLI 与 UUID 隔离目录。
- DeepSeek、Command Code 新增连接拥有自己的 Keychain account、reader、刷新引擎和缓存命名空间。原有单连接条目原位沿用，元数据迁移不读取 Key。
- 请求端点和模型请求授权规则不变。重复检测只使用实际观察到的身份或既有不可逆 Key 指纹，不推断不同 Key 是否属于同一服务商账户。
- 移除 ChatGPT 连接新增官方 `account/logout`，作用于该 Profile 的 app-server。接口依据：[官方文档](https://learn.chatgpt.com/docs/app-server)。Minget 不直接编辑认证文件。
- 第三、第四个账号和 API 多连接的自动测试只证明接线与隔离。真实新账号登录、额度核对和真实移除的验收状态见 `docs/versions/1.6.3/ACCEPTANCE.md`。

## Google / Antigravity（1.6.0）

2026-10-01 最新 A 级证据：Minget 正式 A/B 独立 profile 的官方 CLI `/usage`、重启与真实卡片均已对照通过；两个报告 SUCCESS、num_turns 和全部模型 token 为 0。第二 Mac 由用户延期；续期及授权失效未实测。下文较早阶段状态保留供追溯，最新结论见验收台账。

2026-10-01 实测补充：按本机 CPA Manager Plus v1.14.1 的固定查询结构，通过 CLIProxyAPI v8.0.4 分别代发两个账号的 `retrieveUserQuotaSummary`，Google 上游均 HTTP 200，返回 Gemini 与 Claude/GPT 共享组及明确的 `5h`/`weekly`、比例、重置时间。project 从公开账号元数据取得，未读取授权文件、未发起模型请求。该证据确认本机代理查询路线能读取官方数据；不表示 Minget 自有 OAuth 或正式 CLI 应用接线已完成。详细源码依据、与截图的采样时间差及可借鉴内容见 [CPAMP 核对记录](docs/versions/1.6.0/CPAMP_REFERENCE_20261001.md)。

### 官方 CLI 试验（2026-09-30 后续）

用户已允许官方 CLI 依赖。Google 签名的 Antigravity CLI 1.2.13 实测支持 `--print /usage --output-format json`：两个真实隔离账号各自返回共享额度组、`weekly`／`5h`、`remaining_fraction` 和 `reset_time`；轮次和模型 token 为 0。该真实试验是 A 级证据，详见 `docs/versions/1.6.0/OFFICIAL_CLI_PROBE.md`。正式运行现已接入 CLI 的双账号模型、登录及刷新；旧代理网络客户端只在历史记录和测试目标编译。真实空 profile 的认证快速终止、首屏到完整 OAuth URL 识别、正式双账号授权后的沙箱额度查询与本机卡片对账通过；自然续期未实测，第二台 Mac 由用户延期。见 `docs/versions/1.6.0/ACCEPTANCE.md`。仅以邮箱确认本版身份，JSON 绑定 UUID；不读取认证文件、不输出授权码/URL/原始报告。

查询固定 30 秒总超时、每路输出 1 MiB 上限；沙箱拒绝 fork、Apple Events 和 LaunchServices，HOME/appdata/workspace/tmp 均为账号专用绝对路径。仅从 macOS 系统 HTTP/HTTPS 配置取得网络代理，未修改代理配置、不读取任意 shell 凭证。CLI 错误字符串中的明确 HTTP 429 可分类，但没有已确认的 Retry-After 字段，不推算等待时长。

应用内下载只访问固定 Google Storage 官方包，拒绝重定向；校验 archive/executable SHA-512 和 Google TeamIdentifier EQHXZ8M8AV。仅支持已验证的 arm64 1.2.13，不静默升级。官方 [Headless 文档](https://antigravity.google/docs/cli/headless/)说明 JSON error 是字符串；[Model Quotas 文档](https://antigravity.google/docs/cli/commands/usage/)说明只读额度命令。实际生命周期仍以本轮验证为准。

### 此前直连调查与昨日代理原型

**2026-09-30 自有 OAuth 直连调查。** Google [Antigravity 附加条款第 6 条](https://antigravity.google/terms)及[官方 FAQ](https://www.antigravity.google/docs/faq/)没有明确给 Minget 自行访问内部接口的许可；原调查将只读软件一概判为禁止的结论过度。下述内部端点和代理路径仅记录昨日开发原型，不构成当前官方 CLI 路线的生产依据。详情见 `docs/versions/1.6.0/DIRECT_GOOGLE_FEASIBILITY.md`。未注册 Minget OAuth 客户端，未用真实账号调用内部端点。

兼容代码依据：CLIProxyAPI v7.3.18 的 internal/api/handlers/management/api_tools.go、auth_files.go，CPA Manager Plus v1.14.1 的 apps/web/src/utils/quota/builders.ts 和 types/quota.ts。当前验证为 C，真实双账号尚待应用内连接核对。控制台内部协议，非 Google 公开稳定 API。

- 本机默认 origin：http://127.0.0.1:8317，只允许 literal 127.0.0.1、HTTP、可选合法端口，禁止 userinfo/query/fragment/额外 path。管理密钥由用户主动输入，只进 Keychain antigravity.management-key。
- GET /v0/management/auth-files：只保留 provider=antigravity 的稳定 ID、auth_index、label/email/project_id 和启停状态。不使用授权文件下载接口。
- POST /v0/management/api-call：固定 auth_index、POST、Content-Type、User-Agent、Bearer $TOKEN$ 和 project 请求体。占位符由 CPA 替换，Minget 不取得 Google OAuth token。
- 上游仅允许 daily-cloudcode-pa.googleapis.com、daily-cloudcode-pa.sandbox.googleapis.com、cloudcode-pa.googleapis.com 下的 /v1internal:retrieveUserQuotaSummary 和 /v1internal:fetchAvailableModels，按该顺序查询。401/429/重定向状态不继续回退；其他不支持响应可按固定列表回退。禁止用户任意转发目标及代理覆盖。
- 外层及上游 status_code 都检查。只有明确认识的 groups/buckets 或 models/quotaInfo 响应生成归属快照；remainingFraction 只接受有限 0...1 数字，缺失/布尔/越界为未知，0 保留。重置时间仅解析服务端 ISO 日期，未知周期不补造；逐模型不合并共享池。
- Minget 的 URLSession 拒绝全部重定向，使用 ephemeral session，无 Cookie/cache。外部 CPA 的 Google token 刷新和上游 HTTP 行为由 CPA 负责；当前 api-call 默认 Go 客户端会处理上游重定向，Minget 无法独立验证其未跳转。没有因此修改既有代理或读取 token。
- 五分钟节流、手动强制、唤醒补刷；账号以完成顺序发布。连接代次和账号 ID/email/project identity 隔离缓存，不记录原始响应、Key 或 token。成功发现账号列表后清除已删除/身份更换缓存；新连接/断开清空本应用 Google 缓存。后台 Keychain 禁止 UI，拒绝被记住。

## Codex

1.3.0 起应用同时维护两个隔离的 ChatGPT 账号 Profile。每个 Profile 拥有一个独立的长生命周期 `codex app-server` 子进程，子进程环境保留当前环境并覆盖该 Profile 的 `CODEX_HOME`；1.4.3 对 Node CLI 额外补齐其运行 PATH，以绝对 Node 程序及解析后的 CLI 入口启动（`~/.codex-minget-a`、`~/.codex-minget-b`，按当前用户主目录解析）。Minget 不打开、不列出、不解析、不复制这两个目录的内容，也不读取其中任何文件。

1.4.3 读取与授权点火共用 `CodexLaunch`：先查找系统与用户 Applications 的官方原生 Codex（包含嵌套 `codex-cli/CodexCLI.app/Contents/MacOS/codex`），再查找旧布局和已有 CLI。候选执行 `--version`，每项最多 2 秒，自有进程组超时终止并回收；输出丢弃，仅读取退出状态。Node shebang 只读取程序入口前 256 字节，不涉及配置或认证。显式路径覆盖不回退，连接重建重新解析。2026-09-27 本机原生与 Node CLI 均已真实只读验证；缺少依赖和换机组合由隔离测试覆盖，第二台 Mac 未实测。

### `account/rateLimits/read`

- 传输：本机 `codex app-server` 的 stdio JSON-RPC，每个 Profile 一条连接。
- 用途：读取额度窗口、已用百分比和重置时间。
- 验证：A。真实本机服务已验证，解析、进程生命周期和双 Profile 环境隔离均由自动化测试覆盖；两个真实 `CODEX_HOME` 同时读取和额度核对待用户验收。
- 可选字段：[`rateLimitResetCredits`](https://learn.chatgpt.com/docs/app-server) 的 `availableCount` 是账号当前可用的 earned rate-limit reset 数量；`credits` 明细可能提供 `expiresAt`。应用只保留数量和最近一个未来到期时间，明细缺失时仍以 `availableCount` 为准。
- 展示边界：只在 ChatGPT 卡片显示该只读摘要，不消费重置权益；缓存快照不被标记为当前可用，字段缺失或非法时显示不可用。
- 缓存归属：快照按 `profileID + accountID` 隔离。1.2.1 的账号级缓存升级后不展示；账号 A 首次成功读到相同 accountID 时迁移，不同或缺失时删除，账号 B 永不接收。

### `account/rateLimitResetCredit/consume`

- 应用不调用此写入方法。重置消费、幂等键和二次确认留待后续版本单独评估。

### `account/read`

- 参数：`{"refreshToken": false}`。
- 用途：读取账号类型和可用的邮箱标识，并确定该 Profile 当次读数的归属。
- 验证：请求为 A，响应结构为 B。响应结构依据本机 Codex 协议 schema；真实账号显示待用户验收。
- 边界：不读取 `~/.codex/auth.json`，不触发 token 刷新。

### `account/login/start`、`account/login/completed`、`account/login/cancel`（1.5.0）

- 依据：[Codex App Server 官方文档](https://learn.chatgpt.com/docs/app-server) 中的 ChatGPT 浏览器登录流程。调用方传 `type: chatgpt`；官方子进程返回 `loginId` 与 HTTPS `authUrl`，浏览器完成授权后发出带同一 `loginId` 的完成通知。取消时把该 ID 交给 `account/login/cancel`。
- 每个账号沿用已有隔离 `CODEX_HOME` 和长生命周期 app-server 子进程；同一时间仅允许一个交互登录。完成通知只接受当前连接代次及当前登录 ID，成功后按既有身份与额度只读路径刷新；旧通知和取消后的通知忽略。
- Minget 只把限定为官方域名的登录 URL 交给系统默认浏览器，不读取浏览器会话或认证文件，不记录 URL、响应正文或令牌。登录本身由用户在官方页面完成。登录请求不调用模型端点，也不点火。

### 手动点火（`codex exec`，模型请求例外）

- 传输：`CodexLocator` 定位官方 `codex` 可执行文件后由 `Process.executableURL` 直启，不经过 shell，也不调用 `~/.local/bin/minget-fire`。
- 参数固定为：`exec --ephemeral --sandbox read-only --skip-git-repo-check -C <临时工作目录> -m gpt-5.6-luna -c model_reasoning_effort="none" "Reply exactly: OK"`；临时工作目录固定为系统临时目录下的 `minget-fire`。
- 子进程环境为当前环境的副本并只覆盖当前 Profile 的 `CODEX_HOME`；不读取该目录内容。
- 验证：命令形态和进程生命周期由自动化测试以 fake executable 固定（C）。真实点火请求待用户按验收台账执行。
- 这是 OpenAI 的模型请求路径：由用户在卡片确认，或由用户在 Minget 设置中明确勾选的每日计划触发。Minget 不调用、不修改旧的外部 LaunchAgent 或 `minget-fire`。
- 子进程 stdout/stderr 持续 drain 后丢弃，不写入日志、UserDefaults、测试快照或文档；不记录 session id、prompt、token 或退出输出。单次超时 120 秒，terminate 后等待 3 秒，仍未退出时只对本次 PID 发送 `SIGKILL` 并回收。
- 确认读取（1.3.2）：点火成功后的两次只读确认只做 `handshake + account/rateLimits/read`，不调用 `account/read`，不更新账号归属，不触发缓存迁移；失败熔断语义与完整读取一致。
- 诊断只记录 Profile ID、固定结果分类和自有子进程生命周期。

菜单栏安全区域检查只读取本机屏幕和状态项几何位置，不调用网络或模型。

## 外部点火计划脚本（1.4.2 模板）

- 位置：`scripts/minget-fire/` 与 `scripts/install-minget-fire.sh`。这是可复现的模板与显式安装器，不是应用运行路径；Minget 应用本身仍不调用、不修改 `~/.local/bin/minget-fire`、`~/.local/libexec/minget-fire` 或任何 LaunchAgent。
- 行为：严格串行 OpenAI A → 15 秒 → OpenAI B → 15 秒 → Command Code；单请求 120 秒超时；命令、模型与每日时间表沿用现网既有值。
- 传输：官方 `codex exec` 与官方 `command-code` CLI；全部路径、工作目录、日志位置与时限由 `MINGET_FIRE_*` 环境变量覆盖，生产默认值对应既有 `~/.local` 布局。
- 读取器：Python 字节缓冲 `os.read` 加单一单调总期限，兼容分包与粘包 JSON；子进程以自有进程组回收（SIGTERM 后 SIGKILL）。
- 日志：固定词表（target/start/end/exit/duration/window/used/reset/drift），不记录子进程原始输出、身份或凭据。
- 退出码：请求成功时，重置时间观测"未变化 / 不可用"均退出 0（"前移"另以观测行标注，不证明新窗口）；只有进程失败或超时（124）退出非零。
- 安装器：SHA-256 预期哈希校验、按目标时间戳备份并校验、临时文件哈希复核后原子替换、打印回滚指令；不写 plist、不重载 launchd、不从构建产物安装。
- 验证：fake CLI 沙盒测试 37 项断言（C）；串行顺序、超时续跑、分包/粘包、总期限与进程组回收均由假 CLI 固定。真实定时运行待用户验收。

## DeepSeek

### `GET https://api.deepseek.com/user/balance`

- 认证：`Authorization: Bearer <API Key>`。
- 字段：[`is_available`、`balance_infos[].currency`、`total_balance`、`granted_balance`、`topped_up_balance`](https://api-docs.deepseek.com/zh-cn/api/get-user-balance/)。
- 验证：A。接口结构来自 DeepSeek 官方文档，用户已用真实账号确认余额显示。
- 金额规则：使用 `Decimal`；不同币种分别显示；不换算、不合计、不把缺失字段显示为零。
- 凭据：API Key 只保存在 macOS Keychain。

该请求是余额查询，不调用生成模型，不产生模型 token 消耗。

## Command Code

### `GET https://api.commandcode.ai/alpha/billing/credits`

- 认证：用户在 Minget 设置页主动输入的 `Authorization: Bearer <API Key>`；另附 `Accept: application/json`。
- 用途：读取服务端报告的 5 小时、周窗口和月度剩余信用额。
- 验证：请求有效性为 A，字段语义为 C。2026-09-15 用户在正式构建中使用真实 API Key 成功显示窗口额度；字段与 Studio 尚未同刻对账。
- 层级：1.3.1 起为唯一必须成功的来源。本轮失败时有旧值显示 stale，无旧值按既有错误分类显示不可用；`summary` 或 `subscriptions` 的失败不会被算作 credits 失败。

### `GET https://api.commandcode.ai/alpha/usage/summary`

- 用途：读取当前服务端统计周期的 token、请求结果、成功率、成本，以及可能存在的月度已用信用额。
- 验证：请求有效性为 A，字段语义为 C。用户截图确认真实 token、请求和成本摘要能够返回；统计周期和字段口径尚未与 Studio 同刻确认。
- 层级：1.3.1 起为可选辅助数据。网络错误、5xx、401/403、JSON 错误或字段结构变化都只让统计区显示「统计暂不可用」，已由 credits 取得的额度保持实时，凭证状态不因该接口单独暂停。
- 节流（1.3.2）：summary 与 subscriptions 按 API Key 的完整 SHA-256 摘要隔离，分别记录成功时间并独立判断 15 分钟复用窗口；复用或单路失败时明确标记组件缓存，失败不推进时间戳并在下一轮重试。credits 每轮必读，手动刷新与重连强制全量三路。

### `GET https://api.commandcode.ai/alpha/billing/subscriptions`

- 用途：可选读取套餐名称和计费周期。该请求失败不会让额度与统计失效。
- 验证：C。仅无凭证 401 与合成 fixture 测试。
- 层级：可选辅助数据。缺少有效起止时间时月度时间轨道继续显示不可用，不假定 30 天。

Command Code Studio 公开说明确认其展示成本、token 和运行分析，Provider API 说明确认 API Key 为正式认证方式；官方资料未公开上述账户用量读取接口。本版本不会读取 Command Code 本地认证或设置文件、既有浏览器 Cookie 或会话。没有真实响应时不显示数字；未知统计周期会保留服务端数值并标记“统计周期未确认”。

### 5 小时点火（官方 `command-code` CLI，模型请求例外）

- 依据：Command Code 官方 [Usage Limits](https://commandcode.ai/docs/resources/usage-limits) 说明滚动 5 小时窗口由第一个请求开启；只读 `credits` 查询不能代替点火。
- 触发：用户在详情卡确认手动点火，或在设置中明确勾选某条每日计划。未勾选条目永不执行。
- 凭证：只使用 Minget Keychain 中的 Command Code API Key，以 `COMMAND_CODE_API_KEY` 传给官方 CLI。官方 [Settings](https://commandcode.ai/docs/settings) 说明该环境变量优先于本地 `auth.json`；Minget 另使用隔离临时 `HOME`，不读取用户级认证或设置。
- 启动：定位官方 `command-code` 后由 `Process.executableURL` 直启，不经 shell。参数固定为 `--no-auto-update --no-session --no-skills --skip-onboarding --permission-mode plan --max-turns 1 --model deepseek/deepseek-v4-flash --print "Reply exactly: OK"`，命令形态来自官方 [CLI Reference](https://commandcode.ai/docs/reference/cli)。
- 隔离：子进程仅保留执行所需的最小环境变量，显式禁用自动更新、session 和 skills；stdout/stderr 持续 drain 后丢弃，不进日志、缓存、UserDefaults 或界面。
- 确认：CLI 零退出后最多两次读取既有 `credits` 端点的 5 小时 `resetsAt`，不读 summary/subscriptions，不直接调用模型 HTTP 端点。
- 限制：同时只有一个 Command Code 点火子进程。手动路径可允许 Keychain 交互，定时路径必须禁止弹窗。退出应用或超时只终止并回收自有 PID。
- 验证：官方行为依据为 B；fake CLI、fake Keychain 和 fake transport 的参数、隔离、超时、credits-only 确认为 C。真实手动和定时点火待用户在签名包内验收。

1.2.1 只调整显示：Command Code 美元金额固定显示两位小数，底层 `Decimal` 和接口原值不变；卡片内不再重复显示相对更新时间，全局刷新状态仍保留。

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
- 应用 HTTP 请求路径使用白名单，模型推理端点被显式拒绝；经用户授权的 Command Code 点火只能经官方 CLI 进行。
- 日志和诊断仅记录固定错误类别及脱敏结构，不记录凭据、Cookie 值、账号原始响应或上游错误正文。
- 余额缺失、字段不合法或接口口径不明时显示不可用，不伪造为零。
- 测试使用合成凭据，不包含真实 API Key。
- Command Code 只允许上述三个精确 GET 路径；`/alpha/generate`、`/provider/v1/chat/completions`、`/provider/v1/messages` 和其他模型路径均拒绝。
- 窄例外只有两类：将用户配置的隔离目录作为 `CODEX_HOME` 传给官方 Codex CLI；将 Minget Keychain 中的 Command Code Key 传给隔离 `HOME` 的官方 Command Code CLI 用于已确认点火。Minget 自身仍禁止打开、解析、复制、显示或上传任何全局配置或认证文件。

---

## English summary

This document records the data sources, evidence level, and security boundaries used by Minget 1.4.2.

### External fire scheduler template (1.4.2)

- `scripts/minget-fire/` plus `scripts/install-minget-fire.sh` provide a reproducible scheduler template and an explicit installer; the Minget app itself still never calls or modifies `~/.local/bin/minget-fire` or any LaunchAgent.
- The template runs strictly serial OpenAI A → 15 s → OpenAI B → 15 s → Command Code with a 120 s per-request timeout, mirroring the existing production commands, models, and schedules; every path and limit is overridable via `MINGET_FIRE_*` environment variables.
- The Python reader uses byte-buffered `os.read` with a single monotonic deadline, tolerates fragmented and coalesced JSON, and reaps children as an owned process group. Logs carry only fixed sanitized fields; unchanged/unavailable reset observations exit 0 when the request itself succeeded, while process failure or timeout exits nonzero.
- The installer verifies SHA-256 hashes, takes a timestamped backup, replaces atomically, and prints rollback instructions; it never writes or reloads a launchd plist and never installs from build artifacts.

### Codex

- Minget maintains two isolated ChatGPT profiles, each with its own long-lived `codex app-server` child launched under its own `CODEX_HOME` (`.codex-minget-a`, `.codex-minget-b`).
- `account/rateLimits/read` and `account/read` are called through that local stdio JSON-RPC connection.
- `account/rateLimits/read` may return `rateLimitResetCredits.availableCount` and optional credit expiry details; Minget displays only the normalized count and nearest future expiry and never calls the consume method.
- `account/read` uses `{"refreshToken": false}` and does not read `~/.codex/auth.json`. The profile's cache namespace is keyed by `profileID + accountID`, and the 1.2.1 account-scoped cache is retired by a one-time migration.
- OpenAI fire runs the official Codex CLI directly with a fixed argument list and discards output. It is reachable through a confirmation dialog or a daily schedule row the user explicitly enabled; Minget does not call or modify the legacy external LaunchAgent or `minget-fire`.
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

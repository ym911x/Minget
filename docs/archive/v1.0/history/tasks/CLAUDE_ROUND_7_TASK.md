# Claude Code Round 7 修订任务：GLM 余额接入与连接表单体验

## 用户实测证据

用户已经用真实账户完成测试：

- DeepSeek 已能显示真实余额 `122.28 CNY`。
- 智谱 GLM 保存 API Key 后未显示余额；在应用内登录智谱控制台后也未显示余额。
- GLM 面板的实际探测结果为：`HTTP 200 · 字段 code, data, msg, success`。
- DeepSeek/GLM 连接表单偶尔点不进输入框；保存成功后输入区域仍展开，容易让用户误以为没有保存。

禁止读取、打印或记录用户的真实 API Key、Cookie、Authorization 头和原始响应值。本轮只允许使用脱敏的结构信息和本地测试夹具。

## 已确认根因

1. `GLMContract.confirmed` 当前为空，`GLMAccountReportObservation.isDisplayable` 永远为 `false`。因此，即使接口返回可解析金额，正式应用也必然拒绝显示。
2. 现有诊断只显示顶层字段。用户已证明真实响应的余额在 `data` 内部，但当前界面看不到 `data` 的子字段和类型。
3. 现有解析器主要查找 `data.total_balance`、`data.balance` 等标量；若 `data.balance` 是对象，解析会失败。
4. 现有 GLM 只调用候选控制台接口 `/api/biz/account/query-customer-account-report`。多个独立开源实现目前使用普通智谱 API Key 调用 `GET https://open.bigmodel.cn/api/paas/v4/balance`，并解析 `data.total_balance`、`data.available_balance`、`data.currency`。这仍缺少智谱官方公开文档，应在 `PROVIDER_ENDPOINTS.md` 中按“第三方实现 + 用户实测待确认”标注，不能写成官方公开合同。
5. `DeepSeekSettingsView` 和 `GLMSettingsView` 保存成功时只清空文本，没有折叠连接表单。反馈又位于表单内部，因此用户会继续看到一个空输入区。

参考资料：

- https://github.com/Ychris12138/dsh-usage-stats/blob/main/lib/balance.js
- https://github.com/zh667/TokenLedger
- 用户提供的本机截图，顶层响应结构为 `code/data/msg/success`。

## 必须完成的修订

### 1. 为普通 API Key 增加余额端点

- 将 `/api/paas/v4/balance` 加入 GLM 的同源 GET 白名单，并将它作为普通 API Key 的首选余额读取路径。
- 请求只能发往 `https://open.bigmodel.cn`，必须继续阻止跨源重定向、模型接口和非 GET 请求。
- 使用普通 API Key 现有的安全认证头路径。不要调用任何模型推理接口，不产生模型 token 消耗。
- 严格解析 `data.total_balance`、`data.available_balance`、`data.currency`；金额允许 JSON number 或 decimal string，但必须直接转换为 `Decimal`，不得经 `Double`，不得猜单位。
- 只在 2xx、业务成功且至少一个已知金额字段能严格解析时显示余额。HTTP 200 的业务错误、字段缺失、空值或非法数字仍为明确失败，不能显示 0。
- 主金额优先表达“可用余额”。若同时存在总余额与可用余额，详情分别标注“总额”和“可用”，不要把 `available_balance` 错标为“充值”。若通用 `ProviderBalance` 现有字段不能表达该语义，应以向后兼容方式扩展模型和缓存格式。
- 币种只有在响应明确给出时使用；如果该端点的真实合同不返回币种，可在用户实测确认前显示金额但标注“币种未确认”，或继续拒绝显示，禁止无依据默认 CNY。测试夹具提供币种时必须正确显示。

### 2. 兼容用户已经探测成功的控制台报告结构

- 保留 `/api/biz/account/query-customer-account-report`，用于控制台会话和兼容回退。
- 增加安全的嵌套结构摘要：最多 3 层、限定数量，只记录 JSON 路径和类型，例如 `data.balance: object`、`data.balance.availableBalance: number`。不得记录任何值、数组内容、上游消息、Key 或 Cookie。
- 对已知报告形态做严格的、端点专属的解析，至少兼容 `data.balance` 为对象时的 `balance`、`availableBalance`、`rechargeAmount`、`giveAmount`、`totalSpendAmount`、`frozenBalance`。所有字段都必须保留原语义，累计充值、赠送、累计消费和冻结金额不能塞进 DeepSeek 的“充值余额/赠费余额”语义。
- 如果真实结构仍不匹配，界面应显示“已连接，但当前响应结构暂不支持”，并给出脱敏路径摘要，供下一次修订使用。
- 不要用一个全局布尔门槛粗暴放开所有形态。改成端点和 schema 版本对应的严格合同：只有命中已知成功包络、字段路径、类型及金额约束的响应才可显示。

### 3. 正确判断连接成功

- HTTP 200 只表示传输成功。必须结合 `success` 和 `code` 判断业务结果；兼容数字或字符串形式的成功码，已知成功值需由测试固定。
- 401/403 和明确的认证业务码继续映射为 Key 无效；网络错误应显示“Key 已保存，暂时无法验证”。
- API Key 路径成功后直接进入 `.connected` 并参加正常刷新。控制台会话路径只有在严格解析出余额后进入 `.connected`。
- API Key 成功时无需强迫用户再次登录控制台。保留控制台登录作为兼容入口。

### 4. 修复连接表单交互

- 处理菜单栏 `NSPopover` 内 SecureField 偶尔无法获得键盘焦点的问题。检查并修正窗口激活、key window、SwiftUI 视图 identity 和刷新时重建/抢焦点行为。
- 用户点“连接”后，输入框应能稳定点击和输入；连续刷新余额不应打断正在输入的内容。
- Keychain 保存成功后立即清空输入并折叠连接表单。验证反馈移到折叠后仍可见的供应商区域，按现有状态机继续显示“正在验证”“已连接”或固定错误。
- Keychain 保存失败时保留输入和展开状态；认证失败也应允许用户重新展开并替换 Key。
- GLM 控制台“完成连接”后关闭登录 sheet，并在主面板显示验证反馈。

### 5. 测试与文档

- 新增 GLM API Key 余额端点测试：URL、GET、认证、同源限制、成功包络、`Decimal`、总额/可用额语义、币种、HTTP 200 业务错误、401/403、缺字段、非法数字、跨域重定向。
- 新增控制台报告嵌套对象测试和脱敏结构摘要测试，证明摘要没有任何数值、消息、Key、Cookie 或 Authorization 内容。
- 新增 ViewModel/应用接线测试：保存 API Key后余额可达 `.connected`，控制台会话成功路径，失败路径，缓存隔离，删除凭证清缓存。
- 对输入表单增加可自动测试的状态逻辑。保存成功折叠，保存失败保留，验证反馈在折叠后可见。
- 保留全部既有测试。运行 `swift test`，再运行 `./scripts/build.sh`，重建 `dist/UsageMonitor.app`，并做启动和退出清理检查。
- 更新 `PROVIDER_ENDPOINTS.md`，清楚区分智谱官方文档、第三方实现、用户实测和本地夹具验证。
- 新建 `ROUND_7_REPORT.md`，写明实际修改、实际测试数量、构建结果、尚待用户实测的内容。不要提交或推送。

## 验收结果

1. 用户重新保存同一把 GLM API Key 后，应用使用只读余额端点；合同匹配时显示真实可用余额和更新时间。
2. 如果该账户响应不同，面板显示脱敏的嵌套路径与类型，能够直接定位差异，同时不泄露金额或凭据。
3. 保存成功后连接输入区自动收起，供应商区域持续显示验证反馈。
4. DeepSeek 已有真实余额显示不能回归。
5. 所有测试和正式构建通过，报告内容与真实命令输出一致。

请持续执行直到实现、测试、正式构建和报告全部完成，不要在常规修改中途等待授权。

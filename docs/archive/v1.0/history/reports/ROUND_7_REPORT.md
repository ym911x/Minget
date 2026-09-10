# Round 7 report — GLM 余额接入与连接表单体验（已执行）

Status: implementation complete. All numbers below come from real commands run in this
round's environment. Nothing was committed or pushed. DeepSeek's real-balance display path
is unchanged by construction (its parser and endpoint were not modified) and its 38
existing tests still pass.

## 1. 本轮修改

### 1.1 普通 API Key 的余额端点（任务 1）

- `GLMProvider` 新增 `balancePath = "/api/paas/v4/balance"`，白名单为
  `{balancePath, accountReportPath}`（`ProviderRequestGuardTests` 钉死）。请求只发往
  `https://open.bigmodel.cn`，GET only，跨源重定向拒绝与模型端点黑名单不变（既有传输层
  测试全部保留并通过）。
- 认证沿用现有头路径：读用 `Bearer <key>`，探测兼容 `Bearer`/`ApiKey` 两种拼写。
- 严格解析 `data.total_balance` / `data.available_balance` / `data.currency`，作为普通
  API Key 的首选余额读取路径；控制台报告端点保留为兼容回退（一次，且仅在主端点返回
  未知形状/业务错误时；401/403 与网络类失败不回退）。

### 1.2 金额精度修复（实现中发现的真实缺陷）

- 实测发现：`JSONSerialization` 解析 JSON number `66.6` 后再序列化会写出
  `66.599999999999994`（探针程序实证），任何经 `[String: Any]` 往返的金额都会失真。
- 修复：新增 `StrictAmount`（Decodable），两个 GLM 严格解析器直接用 `JSONDecoder` 解码
  **原始响应 body**。本机 Foundation 的 JSONDecoder 对 number 字面量的 Decimal 路径按
  源文本精确解析（探针实证 `66.6` → 精确相等）；decimal string 走既有
  `SafeConversion.decimal` 严格字面量。全程无 `Double`。
- 金额字段"存在但非法"（非数字、千分位、null）→ 明确失败，绝不显示 0；字段全缺 →
  明确失败。

### 1.3 总额/可用语义与币种（任务 1）

- `ProviderBalance` 向后兼容扩展：`currency: String?`（响应未标注 → nil，绝不默认 CNY）、
  新增 `available: Decimal?`、`additionalAmounts: [ProviderLabeledAmount]?`（field + 固定
  中文标签 + 金额）。`PersistedBalance` 同步扩展，旧缓存条目可继续解码（测试钉死）。
- 显示规则（`DecimalFormatting`）：主金额优先显示可用余额；详情分别标注"总额"与"可用"；
  `available_balance` 永不标成"充值"。无币种时金额旁不发明代码，面板显示
  "币种未确认：响应未标注币种，金额按原始值显示。"。测试夹具提供币种时正确显示。

### 1.4 控制台报告结构兼容（任务 2）

- 保留 `/api/biz/account/query-customer-account-report`（控制台会话 + 回退）。
- 严格解析已知形态：`data.balance` 对象的 `balance`（总额）、`availableBalance`（可用），
  以及 `rechargeAmount`（累计充值）、`giveAmount`（累计赠送）、`totalSpendAmount`
  （累计消费）、`frozenBalance`（冻结金额）——后四者以 `additionalAmounts` 保留原语义，
  **不塞进** DeepSeek 的充值/赠费字段（测试钉死）。
- 全局布尔门槛废除：`GLMContract.confirmedSchemas: Set<GLMSchema>` 按端点确认；
  `apiBalanceV1` 与 `consoleReportV1` 均以"第三方实现 + 用户实测待确认"证据级别打开
  （`PROVIDER_ENDPOINTS.md` §3 明确标注，未写成官方公开合同）。
- 脱敏结构摘要：响应匹配未知形状时记录 `path: type`（最多 3 层、24 条、数组只记首元素
  形态），例如 `data.balance: object`、`data.balance.availableBalance: number`。
  测试断言摘要不含任何值、消息文本、Key 或 Cookie。
- 结构不匹配 → `ProviderFailure.structureUnsupported` → 反馈"已连接，但当前响应结构暂
  不支持"，面板显示摘要供下一轮定位。

### 1.5 连接成功判定（任务 3）

- `GLMEnvelope`：HTTP 200 + `code ∈ {200, "200", "success", 0}`（数字与字符串兼容，
  由测试固定）且 `success != false` 才算业务成功；无 code 的未知形状是
  `unexpectedResponse`，有码/有 error 对象才是 `businessError`。
- 401/403 与认证业务码 → `invalidCredential`（Key 无效）；网络失败 → "Key 已保存，
  暂时无法验证"。
- API Key 成功 → 直接 `.connected` 并加入正常 5 分钟轮询（`isAutomaticRefreshEnabled`
  按存储凭证对应的已确认 schema 判定）；控制台会话仅在严格解析出余额后 `.connected`。
  API Key 成功无需再登录控制台，控制台登录保留为兼容入口。

### 1.6 连接表单交互（任务 4）

- 新增 `ConnectionFormState`（每平台一个，`StateObject` 持有）：保存成功 → 清空输入 +
  折叠表单；保存失败 → 保留输入与展开状态；删除凭证 → 清 draft、报告"已删除"；
  认证失败后可重新展开替换 Key。后台刷新触发的重渲染不会打断输入（测试钉死）。
- 反馈行移到供应商 section（表单外、折叠后仍可见）。
- `StatusItemController.togglePanel` 在 `popover.show` 前调用
  `NSApp.activate(ignoringOtherApps: true)`：accessory 应用刚弹出的 popover 不是 key
  window，文本框拿不到焦点——这正是"点不进输入框"的根因。
- GLM"完成连接"后 sheet 关闭（既有行为），验证反馈显示在主面板 section。

## 2. 测试（243 条，实际执行）

既有 219 条全部保留（名称不变的测试中，部分断言随合同行为更新，逐条见下）；新增 24 条。

| 套件 | 新增/更新 |
|---|---|
| `GLMProviderTests`（重写 GLM 解析部分） | 新增：成功码四种拼写、`success:false` 否决、未知形状+摘要、状态分类保留真实码、余额端点（总额/可用语义、number/string 精确 Decimal、币种缺省、缺字段、非法数字、无 data）、控制台报告（六字段原语义、未知 data 形态）、结构摘要（仅路径+类型、深度/条数上限）、自动刷新跟随已确认 schema。更新：`observe` 带 schema 参数；`probeAccountReport*` 更名 `probeBalance*` 并指向余额端点 |
| `ProviderModelsTests` | 新增：available/labelled amounts 缓存往返、旧格式缓存条目解码、可用余额主金额显示、无币种显示、附加语义标签显示 |
| `ProviderRequestGuardTests` | GLM 白名单更新为两个端点 |
| `ProviderRefreshEngineTests` | 周期轮询测试改为按已确认 schema 判定（原 `accountReportConfirmed` API 已移除） |
| `GLMConnectWiringTests`（应用接线） | 更新：保存 Key → 余额端点 → `.connected` 且金额上屏；未知形状 → `.structureUnsupported` + 摘要；保存会话 → 报告端点 Cookie 读取 → `.connected`。新增：结构不支持反馈测试 |
| `ProductionWiringTests` | GLM 保存改为断言 `.connected`（经余额端点、无模型路径） |
| `ConnectionFormStateTests`（新文件） | 保存成功折叠+清空+反馈折叠后可见；保存失败保留；认证失败可重展开替换；删除清 draft；后台刷新不打断输入 |

```
命令：swift test
结果：Executed 243 tests, with 0 failures (0 unexpected) in 6.762s
     Test Suite 'All tests' passed
退出码：0；编译 0 error / 0 warning（含测试目标）
```

## 3. 构建结果（实际执行）

```
命令：./scripts/build.sh
结果：swift build (release) complete，0 warning；codesign --force --sign - 成功；
     codesign --verify 通过（satisfies its Designated Requirement）；plutil -lint OK
退出码：0
产物：dist/UsageMonitor.app（Contents/MacOS/UsageMonitor + UsageMonitorCLI 重建）
```

## 4. 启动与退出清理检查（实际执行）

```
dist/UsageMonitor.app/Contents/MacOS/UsageMonitor &
  → 仅一个自有 codex app-server 子进程（ppid == app PID）
kill -TERM <app>
  → 约 500ms 内退出，子进程被回收，无孤儿
```

## 5. 尚待用户实机验证

1. **验收 1（核心）**：重新保存同一把 GLM API Key → 应用应请求 `/api/paas/v4/balance`；
   若响应匹配 `apiBalanceV1` 合同，面板显示真实可用余额（主金额为可用额）+ 更新时间，
   状态"已连接"。若真实响应字段不同（如 `totalBalance` 驼峰、`data` 下另有嵌套），将
   显示"已连接，但当前响应结构暂不支持"并附脱敏结构摘要——请把摘要内容（路径与类型，
   无数值）反馈到下一轮。
2. **验收 2**：控制台登录路径同理；`data.balance` 形态匹配时应显示余额并标注
   累计充值/累计赠送/累计消费/冻结金额（原语义）。
3. **验收 3**：保存成功后连接输入区自动收起，供应商区域持续显示"正在验证/已连接/固定
   错误"；保存失败时输入与展开状态保留。
4. **验收 4**：DeepSeek 真实余额（122.28 CNY）显示不应有任何变化（其解析与端点未动）。
5. **输入框焦点**：菜单栏 popover 内 SecureField 应可稳定点击输入（app 激活修复）；
   若仍有复现路径，请记录当时的操作顺序。

## 6. 本轮实际执行的命令

```bash
swift build               # PASS（多次迭代，最终 0 error / 0 warning）
swift build --build-tests # PASS（0 error / 0 warning）
swift test                # PASS：243 tests, 0 failures, exit 0（4 次运行确认）
./scripts/build.sh        # PASS：dist/UsageMonitor.app 重建、签名校验通过、0 warning
dist/UsageMonitor.app/Contents/MacOS/UsageMonitor   # 启动检查：SIGTERM 后退出，子进程无孤儿
```

边界检查：本轮未读取、打印或记录任何真实 Key、Cookie、Authorization 头或原始响应值；
所有 GLM 响应均为本地合成夹具；探测/读取仅声明 `open.bigmodel.cn` 的两个只读端点；
模型端点黑名单测试全部保留并通过。未执行 `git commit` / `git push`。

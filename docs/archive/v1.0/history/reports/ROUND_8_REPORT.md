# Round 8 report — 优先打通智谱控制台余额读取（已执行，含审核修订）

Status: code revisions complete; **console-balance objective is PARTIAL**（机制与证据
仪表已交付，真实端点/字段/单位适配待用户一次应用内登录后完成，见 §9.5）。All numbers
below come from real commands run in this round's environment. Nothing was committed or
pushed. 本轮以控制台路径为主任务；API Key 路线按任务要求只做了有边界的证据核查（结论：
**未证实**，双向都不下结论），未删除。

## 0. REVIEW.md 第七轮审核四项必修的落实

| 发现 | 落实 |
|---|---|
| [P1] 持久化凭证选择 + 按实际使用的凭证派生缓存身份 | `GLMReading` 连接模式（apikey/console-session）以非秘密值持久化在应用自有 UserDefaults（`UsageMonitor.glm.connectionMode`），注入式便于测试；重启后继续使用所选控制台连接，不自动切回旧 Key。缓存身份按**实际使用**的凭证派生：Key 读 → `apikey-<指纹前缀>`，会话读 → `console-<捕获毫秒>`；`accountIdentifier()`（偏向 Key 的旧实现）删除。会话派生的金额永远不进 Key 的缓存条目 |
| [P2] 认证业务码分类 | HTTP 200 body 的业务码等于 401/403（数字或数字字符串）→ `invalidCredential`，与其他认证失败一致地暂停自动轮询；重新保存凭证恢复。证据边界刻意保守：只映射与 HTTP 状态字面相同的码，未知码保持中性 `businessError` |
| [P2] available-only 语义 | `ProviderBalance.total` 改为 `Decimal?`。只报 `available_balance`/`availableBalance` 时 total 保持 nil，绝不再把可用额复制进总额槽位；显示层主金额为可用额，详情行只出"可用 X"，不发明"总额"行。缓存格式向后兼容（旧条目 total 仍可解码） |
| [P2] present-null 声明字段严格拒绝 | 两个 schema 的解析器在严格解码前先做 JSONSerialization 级 null 检查：schema 声明的金额字段存在但为 null → `unexpectedResponse`（明确失败），不允许其他字段掩盖未知值。既有"全缺字段"测试与新"部分 null"测试都钉住该行为 |

## 1. 控制台路径（本轮主任务）

### 1.1 已实现（不依赖实机登录的部分）

- **连接模式持久化**：见上表 P1 项。重启、双凭证共存、切换选择均有夹具测试。
- **缓存归属**：凭证变更（`reconnect` / `connectAfterCredentialChange`）现在先
  `invalidateAttribution`（清 authSuspended/lastError/**accountID**），旧账户的缓存数字
  在新凭证生效前不再展示；新会话成功后以新身份写入缓存。重新登录/更换会话不会显示旧
  账户缓存。
- **状态区分**：未登录（`notConfigured`）、登录过期（硬过期会话不重放 →
  `invalidCredential` → `authSuspended`）、读取失败（网络/超时/服务器错误 →
  `savedUnverified` 文案）、结构不支持（`structureUnsupported` → "已连接，但当前响应
  结构暂不支持"+ 脱敏摘要）、成功获取（仅当严格解析出金额 → `.connected`）。认证失败
  暂停自动重试，应用内重新保存凭证/会话后恢复。
- **数据来源观察器（核实仪表）**：应用自建 WKWebView 注入
  `GLMConsoleResponseObserver` 脚本，包装页面自身的 `fetch`/`XMLHttpRequest`，对页面
  加载的每个 JSON 响应上报：URL 路径（去 query/fragment）、HTTP 方法、**请求头名**
  （不含值）、脱敏 path/type 摘要（≤3 层、≤24 条、无任何值）。脱敏在页面内完成，Swift
  侧二次校验，非红acted 形状的消息整条丢弃。面板 GLM 区显示这些摘要——用户登录后
  浏览控制台余额页，真实余额资源的路径、请求头机制与响应结构即被记录，下一轮按证据
  钉合同，不再猜端点。注入脚本本身用 JavaScriptCore 在测试中执行并断言红action。
- **金额语义与 null**：见 §0 P2 两项。DeepSeek 路径未动（回归测试全过）。
- **保留 Round 6/7 修复**：保存反馈状态机、保存成功清空并折叠表单、反馈在折叠后可见、
  popover 激活修复全部保留并有测试。

### 1.2 需要实机登录才能完成的部分（阻点说明）

本环境无法也不允许代替用户登录智谱控制台（不得读取浏览器数据、不得要求向聊天发送
Key/Cookie）。因此以下事项在用户于应用内完成一次登录后才能定案：

1. 控制台余额页的真实数据来源（哪个请求返回余额），及其认证是否超出 Cookie
   （如 CSRF/Token 头）。观察器会把这些以脱敏形式记录在面板上。
2. `consoleReportV1` 的嵌套形态是否与真实响应一致；不一致时以面板摘要为准修合同。
3. 若最终确认 Cookie-only 不足以读取余额，需按观察结果补充请求头或改用窗口内
   DOM 的确定性读取（前提同样是先观察到真实页面结构，不做猜测）。

## 2. API Key 路线的证据核查结论（未证实，不删除）

按任务边界核查后：HTTP 200、顶层 `code/data/msg/success`、合成测试、第三方项目声明
均不能证明该路线对用户账户可用；也不存在"单把 Key 被拒绝"的可用证据。**双向均未证实
（未证实）**，因此不满足"确证走不通"的删除条件，智谱 API Key 输入/保存/探测/回退路径
原样保留，且不得宣称该路线不可用。`PROVIDER_ENDPOINTS.md` §3.1 已按此标注。若用户
后续提供该路线不可用的实测证据，删除范围将是：GLM API Key 输入与保存路径、探测按钮的
Key 分支、Key→report 回退、`glm.api-key` 本应用条目的清除（只删本应用条目、不读值、
不触碰 DeepSeek 凭证）及相关专属测试。

## 3. 测试（259 条，实际执行）

既有 243 条全部保留；新增 16 条：

| 测试 | 覆盖 |
|---|---|
| `GLMProviderTests`（+7） | available-only 两个 schema 均 total=nil 且显示"可用"不发明"总额"；present-null（含部分 null）→ 明确失败；认证业务码 401/403（数字与字符串）→ `invalidCredential`，未知码仍中性；**会话重启**后仍走控制台（Cookie、无 Authorization）；保存 Key 在会话之后 → Key 成为所选；会话缓存身份与 Key 身份不同；断开清除持久化模式 |
| `GLMConsoleResponseObserverTests`（+5，新文件） | Swift 侧校验：query 剥离、头名清洗/去重、非路径类型条目丢弃、畸形消息整条拒绝、条数/长度上限；**注入脚本本体在 JavaScriptCore 中执行**：fetch 观察产生与页面内一致的红acted 结果（路径无 query、头名无值、纯 path/type、无任何数值或消息文本）；非 JSON 响应静默 |
| `GLMConnectWiringTests`（+3） | HTTP 200 业务认证码 → `.invalidCredential` + 引擎暂停 + 重连恢复；重登（新会话）→ 缓存归属切换到新会话身份且显示新数字；控制台观察记录按路径去重、总量封顶、无敏感内容 |

```
命令：swift test
结果：Executed 259 tests, with 0 failures (0 unexpected) in 7.108s
     Test Suite 'All tests' passed
退出码：0；编译 0 error / 0 warning（含测试目标）
```

## 4. 构建与启动检查（实际执行）

```
命令：./scripts/build.sh
结果：swift build (release) complete，0 warning；codesign --force --sign - 成功；
     codesign --verify 通过；plutil -lint Info.plist OK
退出码：0；产物 dist/UsageMonitor.app 重建

启动检查：dist/UsageMonitor.app/Contents/MacOS/UsageMonitor &
  → 仅一个自有 codex app-server 子进程（ppid == app PID）
kill -TERM <app>
  → 约 500ms 内退出，子进程被回收，无孤儿
```

## 5. 实机验证清单（最终验收需要）

1. **控制台余额一致（核心验收）**：应用内登录智谱控制台 → 在该窗口进入余额页 →
   面板 GLM 区应显示"控制台窗口响应结构（脱敏）"列表；把其中的路径、请求头名、
   path/type 摘要（无数值）反馈到下一轮。若响应恰与 `consoleReportV1` 匹配，则直接
   显示余额并与控制台页面数字/单位对照一致。
2. **会话重启**：连接控制台后退出并重启应用 → 仍走控制台路径（不回退旧 Key）；
   面板数字与重启前同账户。
3. **过期与重登**：会话过期后显示"凭证被拒绝或已过期，请重新连接"且不自动重试；
   重新登录后恢复，且不出现旧会话数字。
4. **输入框稳定性**：菜单栏 popover 内 SecureField 实际点击输入验证（状态测试不等同
   于 UI 验证）。
5. **DeepSeek 回归**：真实余额 122.28 CNY 显示不变。

## 6. 本轮实际执行的命令

```bash
swift build               # PASS（多次迭代，最终 0 error / 0 warning）
swift build --build-tests # PASS（0 error / 0 warning）
swift test                # PASS：259 tests, 0 failures, exit 0（4 次运行确认）
./scripts/build.sh        # PASS：dist/UsageMonitor.app 重建、签名校验通过、0 warning
dist/UsageMonitor.app/Contents/MacOS/UsageMonitor   # 启动检查：SIGTERM 后退出，子进程无孤儿
```

边界检查：未读取、打印或记录任何真实 Key、Cookie、Authorization 值或原始响应；观察器
脚本在页面内完成脱敏，Swift 侧二次校验；未删除任何路线（API 路线未证实，不下否定
结论）；未读取浏览器数据；未改全局配置；未执行 `git commit` / `git push`。

---

## 9. Round 8 审核修订（REVIEW.md Round 8，已执行）

Codex 独立审核结论为 REVISION REQUIRED（259 项测试通过、构建通过，但列出三项必修）。
本轮修订全部落实后真实复测：**Executed 268 tests, with 0 failures (0 unexpected) in
8.863s（exit 0）**；`./scripts/build.sh` 重建 dist/UsageMonitor.app（0 warning，签名与
plist 校验通过）；启动/退出检查再次通过（单 codex 子进程，SIGTERM 约 500ms 退出，无孤儿）。

### 9.1 [P1] Cookie 捕获缺口与完成连接（审核发现 1）

- 新增 `ConsoleCookieCapture`：挂接到应用自建 `WKHTTPCookieStore`，窗口打开期间以 1 秒
  轮询持续观察存储——SPA/fetch/XHR 登录不再依赖文档导航也能被捕获；完成连接按钮的可用
  状态随存储实时更新。
- **完成连接改为 awaited 全新捕获**：按钮先 `await freshSession()` 直接读取存储当前
  内容，绝不保存早先的旧快照；然后保存并验证。
- **存储失败传播**：未捕获到会话或钥匙串写入失败时，窗口保持打开并显示固定状态文本
  （"未捕获到会话 Cookie，请先完成登录"/"会话保存失败，本机钥匙串写入未成功，请重试"），
  不再静默关闭。
- 新测试 4 条（`ConsoleCookieCaptureTests`）：轮询跟随初始加载后变化的 Cookie；完成时
  的 awaited 捕获返回存储最新内容；跨域 Cookie 不进入会话；"最新捕获 → 保存 → 立即
  验证"全链路。

### 9.2 [P1] 过期任务的写回竞态（审核发现 2）

- `ProviderRefreshEngine` 引入 per-provider **凭证 generation**：
  `reconnect`/`connectAfterCredentialChange`/`disconnect` 递增；读取任务在启动时携带
  所属 generation，完成时（成功**与**失败两条路径）先比对，代次不符则整条丢弃——不写
  状态、不写缓存、不改连接显示。
- 同代请求才允许合并：凭证变更后 `refresh` 不再复用旧代在飞任务，新凭证开启自己的
  读取（不依赖取消，传输层可忽略取消）。
- 新测试 2 条（`ProviderRefreshEngineTests`，门控 reader 精确建模乱序完成）：A 的成功
  结果在 B 完成之后返回 → A 不覆盖 B 的状态与缓存；A 的认证失败在 B 成功之后返回 →
  不挂起 B 的自动刷新。

### 9.3 [P2] 观察器净化加固（审核发现 3）

- Swift 侧 `sanitizePath` 改用 `URLComponents` 归一化：query、fragment、user、password
  全部剥离，仅接受官方控制台 host（`GLMConsoleSessionPolicy.isHostAllowed`）的 https
  URL；相对路径仅接受以 `/` 开头的形式并同样剥离 query/fragment；长度上限 512。
- **发送前净化下沉到注入脚本**：`isOfficialHost`（URL API 与字符串双实现）先行过滤，
  非 bigmodel.cn/open.bigmodel.cn 资源什么都不上报；`pathOnly` 从 origin+pathname 重建
  （query/fragment/userinfo 无法在该形式中存活），无 URL API 的环境走字符串降级（显式
  剥离 userinfo）；请求头名按 RFC 字符集、长度 ≤64、数量 ≤16 清洗；字段路径长度上限
  180。Swift 侧二次校验保持不变（纵深防御）。
- 新测试 4 条（`GLMConsoleResponseObserverTests`）：Swift 侧 userinfo+fragment 哨兵
  剥离与外 host 拒绝；注入脚本（URL 分支）对 `user:pass@…?token=leak#frag-sentinel`
  的净化（无任何哨兵值外泄）与外 host 零上报；无 URL 降级分支同样剥离；非官方
  scheme/host 在 Swift 侧整条拒绝。测试仅使用合成哨兵值，未记录任何真实数据。

### 9.4 测试数变化说明

268 = 259（审核时基线）+ 9（本轮修订新增：4 + 2 + 3；其中观察器 2 条旧测试并入重写的
harness，计数净变化见上）。无既有测试被删除或改名。

### 9.5 交付边界（诚实陈述）

本轮交付的是**控制台路径的机制与证据仪表**：凭证选择持久化、代次隔离、Cookie 观察、
全新完成捕获、失败传播、脱敏观察器。审核指出的核心验收缺口保持成立——真实端点/字段/
单位证据、超出 Cookie 的认证适配（如需要）与 DOM 读取，仍需用户在应用自建窗口内登录
一次并查看面板脱敏摘要后才能完成；在那之前，**控制台余额目标为部分交付，不得视为
已完成**。API Key 路线维持"未证实、不删除"（见 §2）。

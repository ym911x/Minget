# ChatGPT / Codex Usage Monitor
## macOS 菜单栏 + iPhone Widget 项目完整方案
### 兼作 Codex × ClaudeCode 多 Agent 协同开发验证项目

> 文档版本：v1.0  
> 日期：2026-09-09  
> 项目代号：UsageMonitor  
> 目标平台：macOS 第一阶段，iPhone Widget 第二阶段  
> 开发协同：Codex 负责组织、方案、审查与最终验收；ClaudeCode（GLM-5.3-Flash）负责编码、测试、修订  
> 最大迭代轮数：5 轮；满足验收条件后立即结束，不要求跑满 5 轮

---

# 1. 项目结论

本项目先实现一个极简的 macOS 菜单栏小工具，用于持续显示 ChatGPT/Codex 当前账号的：

- 5 小时额度剩余百分比
- 周额度剩余百分比
- 5 小时窗口重置时间
- 周窗口重置时间
- 最后更新时间
- 数据读取异常状态

第一阶段不做完整桌面主窗口，不做复杂历史统计，不做账号管理，不做云服务器。

数据读取首选路径：

```text
Codex 已登录状态
      ↓
codex app-server
      ↓
JSON-RPC
account/rateLimits/read
      ↓
UsageMonitor 数据层
      ↓
macOS MenuBarExtra
```

核心原则：

1. 不自行计算“官方额度总量”。
2. 不读取、复制或上传用户密码。
3. 尽量不直接管理 ChatGPT Cookie。
4. 优先复用 Codex 已登录会话和官方 Codex app-server。
5. 根据 `windowDurationMins` 识别额度窗口，不硬编码 `primary = 5h`、`secondary = weekly`。
6. 当前已知典型窗口：
   - 300 分钟 = 5 小时
   - 10080 分钟 = 7 天
7. 如果 OpenAI 后续调整接口，应用必须明确显示“数据不可用”，不能伪造剩余量。

---

# 2. 项目目标

## 2.1 用户问题

目前查看 ChatGPT/Codex 剩余额度需要：

```text
打开 ChatGPT / Codex
→ 点击账号区域
→ 打开 Usage / 用量
→ 查看 5 小时和周额度
```

这是高频但操作层级较深的信息。

本项目希望把它变成：

```text
Mac 菜单栏常驻
5H 78% | W 42%
```

无需进入 ChatGPT。

---

# 3. MVP 范围

## 3.1 第一阶段必须实现

macOS 菜单栏显示：

```text
5H 78%  |  W 42%
```

点击菜单栏后显示：

```text
ChatGPT Usage

5 小时额度
剩余：78%
重置：14:35

周额度
剩余：42%
重置：09-13 11:20

最后更新：10 秒前

[立即刷新]
```

## 3.2 MVP 必须具备

- 菜单栏常驻
- 自动读取额度
- 5 小时窗口识别
- 周窗口识别
- 剩余比例计算
- Reset 时间本地化
- 自动刷新
- 手动刷新
- 数据错误提示
- Codex 未登录提示
- app-server 不存在提示
- 最近一次成功数据缓存
- 应用退出后不留下孤立 `codex app-server` 进程

## 3.3 MVP 暂不实现

- iPhone Widget
- Apple Watch
- 历史使用趋势
- 消耗速度预测
- 多账号切换
- OpenAI API 费用统计
- Token 统计
- 云同步
- 通知中心复杂规则
- 登录 ChatGPT
- 内置浏览器
- 自动读取 Safari/Chrome Cookie
- 自建后台服务

---

# 4. 数据来源方案

## 4.1 首选：Codex app-server

使用本机已经安装并登录的 Codex。

目标调用：

```text
codex app-server
```

通过 stdio 与 app-server 建立 JSON-RPC 通信。

初始化后调用：

```text
account/rateLimits/read
```

预期响应中寻找 RateLimitSnapshot / RateLimitWindow。

典型结构示意：

```json
{
  "rateLimits": {
    "limitId": "codex",
    "primary": {
      "usedPercent": 25,
      "windowDurationMins": 300,
      "resetsAt": 1779459394
    },
    "secondary": {
      "usedPercent": 18,
      "windowDurationMins": 10080,
      "resetsAt": 1779826837
    }
  }
}
```

注意：

**不要根据 primary / secondary 名称判断窗口类型。**

必须根据：

```text
windowDurationMins
```

进行分类。

推荐：

```swift
300      -> fiveHour
10080    -> weekly
其他值    -> unknownWindow
```

如果未来出现新的窗口类型，程序不崩溃，只忽略或记录 unknown。

---

# 5. 剩余额度计算

服务器返回通常是：

```text
usedPercent
```

UI 需要显示：

```text
remainingPercent
```

计算：

```text
remainingPercent = max(0, min(100, 100 - usedPercent))
```

UI 的文字必须明确：

```text
剩余 78%
```

避免出现“78%”但用户不知道是已使用还是剩余。

---

# 6. 技术架构

推荐使用：

```text
Swift
SwiftUI
MenuBarExtra
Foundation
Process
Pipe
Codable / JSONSerialization
```

第一版避免第三方依赖。

目录建议：

```text
UsageMonitor/
├── UsageMonitorApp.swift
├── Models/
│   ├── UsageSnapshot.swift
│   ├── RateLimitWindow.swift
│   └── UsageError.swift
│
├── Services/
│   ├── CodexAppServerClient.swift
│   ├── JSONRPCClient.swift
│   ├── UsageService.swift
│   └── UsageCache.swift
│
├── ViewModels/
│   └── UsageViewModel.swift
│
├── Views/
│   ├── MenuBarLabel.swift
│   ├── UsagePopoverView.swift
│   ├── UsageRowView.swift
│   └── ErrorStateView.swift
│
├── Utilities/
│   ├── DateFormatting.swift
│   └── ProcessUtilities.swift
│
└── Tests/
    ├── WindowClassificationTests.swift
    ├── JSONParsingTests.swift
    ├── RemainingPercentTests.swift
    └── MockJSONRPCTests.swift
```

---

# 7. 核心数据模型

建议内部统一模型：

```swift
struct UsageWindow {
    enum Kind {
        case fiveHour
        case weekly
        case unknown
    }

    let kind: Kind
    let usedPercent: Double
    let remainingPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date?
}

struct UsageSnapshot {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    let fetchedAt: Date
    let source: UsageSource
}
```

UsageSource 第一版：

```swift
enum UsageSource {
    case codexAppServer
    case cached
}
```

---

# 8. Codex app-server 通信设计

## 8.1 启动策略

UsageMonitor 启动时：

```text
检测 codex 是否存在
        ↓
启动 codex app-server
        ↓
建立 stdin/stdout Pipe
        ↓
JSON-RPC initialize
        ↓
initialized
        ↓
account/rateLimits/read
```

## 8.2 生命周期

推荐 MVP：

应用启动时创建一个 app-server 子进程。

应用运行期间复用该进程。

应用退出时：

```text
关闭 pipe
→ terminate process
→ 清理资源
```

如果 app-server 异常退出：

```text
标记 disconnected
→ 最多自动重启一次
→ 若仍失败，显示错误
```

禁止无限重启循环。

---

# 9. JSON-RPC 客户端要求

JSONRPCClient 至少支持：

```text
request ID
method
params
result
error
notification
```

必须处理：

- stdout 分段返回
- 一次读取包含多条消息
- JSON-RPC error
- app-server 输出非 JSON 内容
- 超时
- process termination

建议单次额度查询超时：

```text
5 秒
```

超时后：

```text
不清空最近一次成功数据
显示 stale 状态
```

---

# 10. 刷新策略

MVP 推荐：

```text
App 启动：立即刷新
正常运行：每 60 秒
用户点击菜单：如果距离上次成功更新 > 30 秒，则刷新
点击“立即刷新”：强制刷新
```

不要 1 秒或 5 秒轮询。

理由：

- 额度不需要秒级精度
- 减少额外请求
- 降低内部接口变化或限流风险
- MenuBar 工具应尽量轻量

---

# 11. 缓存策略

保存最近一次成功快照。

推荐：

```text
UserDefaults
```

存储：

```text
fiveHourRemaining
fiveHourResetAt
weeklyRemaining
weeklyResetAt
fetchedAt
```

如果当前获取失败但缓存存在：

菜单栏：

```text
5H 78% | W 42% ⚠
```

展开后：

```text
当前无法获取最新数据
显示 8 分钟前的数据
```

如果从未成功：

```text
Usage unavailable
```

绝对禁止把缓存数据显示成“实时数据”。

---

# 12. UI 设计

## 12.1 菜单栏默认

首选：

```text
5H 78% | W 42%
```

空间不足时：

```text
78% / 42%
```

但 MVP 优先第一种，因为语义最清楚。

## 12.2 展开面板

建议宽度约：

```text
280–320 pt
```

结构：

```text
ChatGPT Usage

5-hour
████████░░
78% remaining
Reset 14:35

Weekly
████░░░░░░
42% remaining
Reset Sep 13 11:20

Updated 10 sec ago

Refresh
Quit
```

## 12.3 状态颜色

MVP 可使用系统语义颜色。

建议逻辑：

```text
> 50%    正常
20–50%   提醒
< 20%    警示
```

不要为了颜色而依赖颜色传递全部信息，百分比文字始终保留。

---

# 13. 错误状态

需要明确区分：

## A. 找不到 Codex

```text
Codex CLI not found
```

## B. Codex 未登录

```text
Codex is not signed in
```

## C. app-server 启动失败

```text
Unable to start Codex app-server
```

## D. RPC 失败

```text
Unable to read usage
```

## E. 返回数据没有 300 分钟窗口

```text
5-hour usage unavailable
```

## F. 返回数据没有 10080 分钟窗口

```text
Weekly usage unavailable
```

窗口缺失不能导致整个 UI 崩溃。

---

# 14. 安全要求

MVP 必须满足：

1. 不要求用户输入 OpenAI 密码。
2. 不读取浏览器密码。
3. 不主动导出 Codex Token。
4. 不上传 Codex Token。
5. 不向第三方服务器发送 usage 数据。
6. 不保存完整认证响应。
7. 日志不得打印 access token / authorization header。
8. 不将 `~/.codex/auth.json` 内容写入日志。
9. 所有数据只保存在本机。
10. 如果未来加入 iCloud，只同步 UsageSnapshot，不同步认证凭证。

---

# 15. 对 OpenAI 内部接口变化的防御

这是项目最主要的技术风险。

因此数据层需要实现：

```text
Transport
    ↓
Raw RPC Response
    ↓
Parser
    ↓
Normalizer
    ↓
UsageSnapshot
    ↓
UI
```

UI 不直接依赖 OpenAI 原始 JSON。

以后即使字段变化，只修改：

```text
CodexAppServerClient / Parser
```

不要修改整个 UI。

---

# 16. 单元测试最低要求

至少包含以下测试。

## Test 1

输入：

```text
usedPercent = 25
```

结果：

```text
remaining = 75
```

## Test 2

输入：

```text
windowDurationMins = 300
```

结果：

```text
fiveHour
```

## Test 3

输入：

```text
windowDurationMins = 10080
```

结果：

```text
weekly
```

## Test 4

primary 和 secondary 顺序互换。

程序仍正确识别：

```text
300 -> 5H
10080 -> Weekly
```

这是强制测试。

## Test 5

只有 300，无 10080。

App 正常运行。

## Test 6

只有 10080，无 300。

App 正常运行。

## Test 7

未知：

```text
windowDurationMins = 43800
```

不得崩溃。

## Test 8

usedPercent 超界：

```text
-5
110
```

remaining 必须 clamp 到：

```text
0...100
```

## Test 9

RPC timeout。

保留缓存。

## Test 10

Malformed JSON。

程序不崩溃。

---

# 17. 第一阶段验收标准 Definition of Done

只有同时满足以下项目，Codex 才能宣布第一阶段完成。

## 功能

- [ ] App 可编译
- [ ] App 可启动
- [ ] 菜单栏出现
- [ ] 可读取真实 Codex 账号额度
- [ ] 正确识别 5h
- [ ] 正确识别 weekly
- [ ] 正确计算 remaining
- [ ] 正确显示 reset 时间
- [ ] 自动刷新
- [ ] 手动刷新
- [ ] 缓存可工作
- [ ] 数据失败不会崩溃
- [ ] app-server 生命周期正常

## 正确性

必须实际对照：

```text
ChatGPT / Codex Settings → Usage
```

至少验证一次：

```text
5H UI ≈ UsageMonitor
Weekly UI ≈ UsageMonitor
Reset ≈ UsageMonitor
```

允许页面刷新时间造成少量显示差异。

禁止只用 Mock 数据宣布完成。

## 工程质量

- [ ] 无硬编码 Token
- [ ] 无认证数据打印
- [ ] 无明显进程泄漏
- [ ] 核心逻辑有单元测试
- [ ] Build 无 error
- [ ] 关键 warning 已解释或清除
- [ ] README 可说明如何运行

---

# 18. 第二阶段：iPhone Widget

只有 Mac MVP 验证稳定后再开发。

推荐架构：

```text
Codex
 ↓
Mac UsageMonitor
 ↓
UsageSnapshot
 ↓
iCloud / CloudKit
 ↓
iPhone App
 ↓
WidgetKit
```

iPhone 只读取：

```json
{
  "fiveHourRemaining": 78,
  "fiveHourReset": "...",
  "weeklyRemaining": 42,
  "weeklyReset": "...",
  "updatedAt": "..."
}
```

不向 iPhone 同步：

```text
Token
Cookie
auth.json
Codex credential
```

iPhone Widget 示例：

```text
ChatGPT
5H   78%
W    42%
Updated 1m
```

这一阶段不属于当前 MVP 的 Definition of Done。

---

# 19. 后续可选功能

MVP 完成后才考虑：

- 低额度通知
- Apple Watch complication
- 24h / 7d 历史图
- 每小时平均消耗速度
- 周额度预计耗尽时间
- Reset 倒计时
- Credits balance
- 多额度窗口动态展示
- Launch at Login
- iCloud 同步
- 多 Mac 状态同步

---

# 20. Codex × ClaudeCode 协同开发实验

本项目同时用于测试一套明确的双 Agent 工作流。

角色固定：

```text
Codex
= 项目负责人 / Architect / Reviewer / QA / Final Approver

ClaudeCode + GLM-5.3-Flash
= Implementer / Developer / Test Fixer
```

不得混淆角色。

---

# 21. Codex 职责

Codex 负责：

1. 阅读本文件。
2. 检查本机开发环境。
3. 核实 Codex CLI / app-server 当前实际协议。
4. 制定具体实现步骤。
5. 将明确任务交给 ClaudeCode。
6. 不替 ClaudeCode 大规模完成实现。
7. 每轮 ClaudeCode 完成后进行：
   - diff review
   - build
   - test
   - runtime review
   - security review
8. 输出具体问题。
9. 给 ClaudeCode 下一轮修订要求。
10. 满足全部 Definition of Done 后宣布完成。

Codex 是唯一最终验收者。

---

# 22. ClaudeCode 职责

ClaudeCode 使用：

```text
GLM-5.3-Flash
```

负责：

- 创建项目
- 写 Swift 代码
- 编写测试
- 执行 Build
- 修复 Build Error
- 修复 Test Failure
- 根据 Codex Review 修订代码
- 更新 README
- 不自行降低验收标准

ClaudeCode 每轮必须报告：

```text
本轮完成内容
修改文件
Build 结果
Test 结果
已知问题
尚未完成内容
```

禁止只说：

```text
Done
```

---

# 23. 最大 5 轮循环协议

流程：

```text
Codex Plan
   ↓
ClaudeCode Round 1
   ↓
Codex Review 1
   ↓
PASS ?
 ├─ YES → Final Verification → Finish
 └─ NO
      ↓
ClaudeCode Round 2
      ↓
Codex Review 2
      ↓
PASS ?
 ├─ YES → Finish
 └─ NO
      ↓
...
最多 Round 5
```

重要：

```text
5 是上限，不是目标。
```

如果 Round 1 已满足要求：

```text
Round 1
→ Codex Review
→ PASS
→ Final Verification
→ 完成
```

立即结束。

不为了形式继续 Round 2。

---

# 24. 每轮 Review 的固定检查顺序

Codex 每轮必须按下面顺序检查。

## 1. Scope

是否符合本 MD。

## 2. Build

```text
是否成功编译
```

## 3. Tests

```text
单元测试是否通过
```

## 4. Runtime

实际启动。

## 5. Real Data

实际调用：

```text
account/rateLimits/read
```

## 6. Correctness

窗口是否按：

```text
windowDurationMins
```

识别。

## 7. Security

是否泄漏凭证。

## 8. Process

app-server 是否正确结束。

## 9. UI

菜单栏是否清晰。

## 10. Definition of Done

逐项检查。

---

# 25. Review 结果格式

Codex 每轮必须输出：

```text
REVIEW ROUND X

Build:
PASS / FAIL

Tests:
PASS / FAIL

Runtime:
PASS / FAIL

Real Usage:
PASS / FAIL

Security:
PASS / FAIL

Acceptance:
PASS / FAIL

Blocking Issues:
1.
2.
3.

Non-blocking Issues:
1.
2.

Decision:
PASS
或
REVISION REQUIRED
```

只有 Blocking Issues = 0 才允许 PASS。

---

# 26. Codex 给 ClaudeCode 的修订要求格式

必须具体。

错误示例：

```text
请优化代码。
```

正确示例：

```text
Round 2 修订要求：

1. WindowClassifier 当前根据 primary/secondary 判断 5h 和 weekly。
   修改为根据 windowDurationMins。
   300 -> fiveHour
   10080 -> weekly。

2. 增加 primary/secondary 互换的测试。

3. RPC timeout 后不要清空 UsageSnapshot。
   返回 stale cached snapshot。

4. Process termination 必须在 App 生命周期结束时执行。

完成后：
- 运行 xcodebuild
- 运行 unit tests
- 报告结果
```

---

# 27. 第 5 轮仍未通过时

禁止无限循环。

如果 Round 5 后仍有 Blocking Issue：

Codex 输出：

```text
MAX ITERATION REACHED

Completed:
...

Remaining blockers:
...

Root cause:
...

Recommended next action:
...
```

项目状态：

```text
NOT COMPLETE
```

不能为了结束流程而虚假宣布完成。

---

# 28. Codex 最终验收

最终必须再次执行：

```text
Build
Tests
Launch
Real usage fetch
Compare with official Usage UI
Security sanity check
Process cleanup check
```

然后输出：

```text
FINAL VERIFICATION

Build: PASS
Tests: PASS
Runtime: PASS
Real Usage: PASS
5H Accuracy: PASS
Weekly Accuracy: PASS
Reset Time: PASS
Security: PASS
Process Cleanup: PASS

FINAL DECISION:
COMPLETE
```

如果任何核心项失败：

```text
FINAL DECISION:
NOT COMPLETE
```

---

# 29. 推荐的 Agent 交接文件

项目根目录建议维护：

```text
PROJECT_SPEC.md
AGENTS.md
REVIEW.md
README.md
```

其中：

## PROJECT_SPEC.md

就是本文件。

## AGENTS.md

描述双方角色和开发纪律。

## REVIEW.md

Codex 每轮 Review 持续追加：

```text
Round 1
Round 2
...
Final
```

这样 ClaudeCode 可以直接读取上轮审查结果。

---

# 30. 推荐 AGENTS.md 内容

```markdown
# Agents

## Codex

Role:
- Project owner
- Architect
- Reviewer
- QA
- Final approver

Codex must not mark the project complete until PROJECT_SPEC.md Definition of Done passes.

## ClaudeCode

Model:
GLM-5.3-Flash

Role:
- Implementation
- Tests
- Fixes

ClaudeCode must implement Codex tasks and respond to REVIEW.md findings.

## Workflow

Codex -> ClaudeCode -> Codex Review -> ClaudeCode Fix

Maximum implementation/review rounds: 5.

Stop immediately once Codex verifies all acceptance criteria.

PROJECT_SPEC.md is the source of truth.
```

---

# 31. 建议给 Codex 的第一条主 Prompt

将本 MD 放在项目目录后，对 Codex 输入：

```text
你是这个项目的技术负责人、架构师、Reviewer 和最终验收者。

首先完整阅读 PROJECT_SPEC.md。

这个项目有两个目标：

1. 完成 macOS ChatGPT/Codex Usage Monitor MVP。
2. 验证 Codex 与 ClaudeCode 的双 Agent 协同开发流程。

协同规则：
- 你负责组织、架构、任务拆解、代码审查、测试和最终验收。
- ClaudeCode 使用 GLM-5.3-Flash，负责实际编码与修订。
- 每一轮 ClaudeCode 完成后，你必须实际检查代码、diff、build、tests 和运行结果。
- 如果存在问题，给 ClaudeCode 明确的下一轮修订要求。
- 最多 5 轮。
- 如果第 1 或第 2 轮已经全部满足 PROJECT_SPEC.md，不要继续迭代。
- 只有你有权宣布 COMPLETE。
- 不允许仅凭 ClaudeCode 自述通过验收。
- 必须至少一次使用真实账号数据对照 Codex/ChatGPT Usage 页面。
- 不允许为了完成流程而降低 PROJECT_SPEC.md 的验收标准。

现在先不要写大量业务代码。

第一步：
1. 检查项目环境。
2. 检查本机 codex CLI 和 codex app-server 能力。
3. 验证 account/rateLimits/read 的真实调用方式和返回结构。
4. 根据 PROJECT_SPEC.md 制定实施计划。
5. 创建或完善 AGENTS.md。
6. 给 ClaudeCode 下发 Round 1 的明确开发任务。

之后进入最多 5 轮的实现 → Review → 修订流程。
```

---

# 32. 建议 Codex 给 ClaudeCode 的 Round 1 Prompt

Codex 应根据实际环境修订后再使用，参考：

```text
你是本项目的实现工程师。

模型：GLM-5.3-Flash。

请完整阅读：
- PROJECT_SPEC.md
- AGENTS.md

Codex 是项目负责人和最终 Reviewer。

你负责 Round 1 实现。

目标：
实现 PROJECT_SPEC.md 定义的 macOS UsageMonitor MVP。

优先完成：
1. SwiftUI MenuBarExtra 项目。
2. Codex app-server JSON-RPC client。
3. account/rateLimits/read。
4. 根据 windowDurationMins 分类：
   - 300 -> fiveHour
   - 10080 -> weekly
5. remainingPercent。
6. reset 时间。
7. 60 秒刷新。
8. 手动刷新。
9. cache。
10. error state。
11. process cleanup。
12. 单元测试。

禁止：
- 读取浏览器 Cookie。
- 将认证信息写入日志。
- 硬编码 Token。
- 假设 primary 永远是 5 小时。
- 假设 secondary 永远是 weekly。
- 用 mock 数据代替最终真实数据验证。

完成后必须：
1. build。
2. tests。
3. 报告修改文件。
4. 报告 Build 结果。
5. 报告 Test 结果。
6. 报告仍存在的问题。

不要自行宣布整个项目完成。
等待 Codex Review。
```

---

# 33. 真实数据验证

这一项是本项目最重要的实验。

在编码前或 Round 1 早期，Codex 应优先验证：

```text
codex app-server
```

能否成功执行：

```text
account/rateLimits/read
```

并获得：

```text
usedPercent
windowDurationMins
resetsAt
```

如果验证失败：

不要立即改成抓网页。

先判断：

1. Codex 版本是否变化。
2. app-server handshake 是否变化。
3. method 是否变化。
4. experimental capability 是否需要。
5. account 是否已登录。
6. 当前返回 schema 是否变化。

只有确认 app-server 路线不可用以后，才评估替代路线。

---

# 34. Fallback 方案

优先级：

```text
A. codex app-server
↓
B. Codex 公开可访问的本地状态/命令能力
↓
C. 官方后续提供的 Usage API
↓
D. 最后才考虑 Web DOM
```

Web DOM 抓取不进入 MVP 默认方案。

原因：

- 易受 UI 改版影响
- 登录状态复杂
- Cookie 风险高
- App Sandbox 更麻烦

---

# 35. 开发风险

## 风险 1：Codex 内部协议变化

应对：

Adapter 层隔离。

## 风险 2：额度窗口新增

应对：

按 duration 分类，未知窗口忽略。

## 风险 3：窗口 duration 后续变化

应对：

Parser 允许配置映射，未知窗口保留原始值供诊断。

## 风险 4：Codex app-server 不稳定

应对：

缓存 + stale state + 一次重启。

## 风险 5：OpenAI UI 与后台数据短暂不同步

应对：

显示 fetchedAt，不虚假宣称强实时。

---

# 36. 项目成功标准

这个实验成功，不仅代表 App 可用。

还要验证双 Agent 流程：

```text
Codex
提出方案
↓
ClaudeCode
实现
↓
Codex
真正 Review
↓
ClaudeCode
根据问题修订
↓
Codex
重新验证
↓
最终验收
```

重点观察：

- Codex 是否能发现真实代码问题
- GLM-5.3-Flash 是否能准确按 Review 修订
- 是否出现两个 Agent 相互“口头确认”但没有真正测试
- 每一轮是否比上一轮收敛
- 需要几轮达到 Definition of Done
- Review 是否具有技术价值
- 多 Agent 是否比单 Agent 更可靠

建议最终在 REVIEW.md 增加：

```text
Collaboration Evaluation

Total rounds:
1 / 2 / 3 / 4 / 5

Major defects found by Codex:
...

Fix success rate:
...

Repeated defects:
...

Human intervention:
...

Conclusion:
...
```

这将让本项目同时成为一次可复用的 Agent 协同开发案例。

---

# 37. 参考依据

本方案的数据读取设计基于当前 OpenAI Codex app-server 已公开的 rate-limit 能力。

当前公开信息显示：

- `account/rateLimits/read` 可返回当前 ChatGPT/Codex rate-limit snapshot。
- RateLimitWindow 包含 `usedPercent`、`windowDurationMins`、`resetsAt` 等字段。
- 300 分钟窗口对应典型 5 小时窗口。
- 10080 分钟对应典型 7 天窗口。
- 客户端应优先依据窗口持续时间识别窗口，而不是依赖 primary / secondary 的位置含义。
- OpenAI 官方帮助文档确认 Codex 存在 5 小时和 weekly usage window，并会显示其 reset 时间。
- 这些属于 Codex 产品能力，不应被当成长期稳定的公开 OpenAI Developer API。

开发时应以本机当前 Codex 版本实际 schema 和 app-server 行为为最终依据。

---

# 38. 最终开发原则

```text
先验证真实数据链路
再做 UI

先完成 Mac MVP
再考虑 iPhone

先保证正确
再增加功能

Codex 负责证明“真的完成”
ClaudeCode 负责把问题“真的修好”

最多 5 轮
通过即停
不凑轮数
不虚假验收
```

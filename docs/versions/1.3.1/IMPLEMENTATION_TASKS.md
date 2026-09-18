# 1.3.1 实施任务

状态：待实现。

本文供实现 Agent 直接执行。需求和状态语义以 `REQUIREMENTS.md` 为唯一依据；实现过程中不得重新设计文案、真值表或版本范围。

## 0. 开工规则

1. 完整阅读根目录 `AGENTS.md`、`README.md`、`ROADMAP.md`、`PROVIDER_ENDPOINTS.md`，以及 `docs/versions/1.3.0/` 和 `docs/versions/1.3.1/`。
2. 运行 `git status --short`，保留所有开工前已有改动。已知的 1.0.2 evidence PNG、`.commandcode/`、`.workbuddy/` 和中文实施记录不属于 1.3.1。
3. 不读取任何 `~/.codex*/auth.json`、Claude/Codex 全局配置、浏览器 Cookie 或真实 API Key。
4. 新建并持续填写 `docs/versions/1.3.1/IMPLEMENTATION_REPORT.md`，记录修改文件、执行命令、测试结果、真实验证、已知问题和未完成项。
5. 不运行真实点火，不推送、不打标签、不创建 Release，除非用户另行明确授权。

## 1. 双 Profile 完成即发布

主要文件：

- `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`
- `Tests/UsageMonitorAppTests/MenuBarLabelWiringTests.swift`，或新增职责清晰的 `ProfileRefreshPublishingTests.swift`

实施要求：

1. 把 `refresh(resetFailureBudget:)` 的 Task Group 元素从 `Void` 改为稳定 `profileID`。
2. 使用 `for await` 按完成顺序消费 Task Group。每个完成项都调用一个 MainActor 私有方法，该方法：
   - 检查 `!isStopped && !Task.isCancelled`；
   - 调用 `publishProfileStates()`；
   - 递增 `tick`；
   - 不提前把整轮 `isRefreshing` 设为 false。
3. 全部完成后调用单独的整轮结束方法：再次检查停止／取消，设置 `isRefreshing = false`，清空 `refreshTask`，发布最终快照并递增 `tick`。
4. 取消或停止路径也必须清理 `isRefreshing`，但停止后不能再发布 UI 状态。
5. 保留现有 `guard !isRefreshing`，不增加普通刷新请求叠加。

测试必须使用可控阻塞点，不依赖随机调度或长时间 `sleep`。至少覆盖：

- A 先完成、B 保持阻塞时，A 已显示新数据，B 仍为刷新中，整轮仍为刷新中。
- B 先完成时同样成立，最终数组顺序仍是 A、B。
- A 失败、B 阻塞时，A 的失败／缓存状态立即发布。
- 最后一个完成后整轮刷新状态关闭，随后允许下一轮刷新。
- `stop()` 或取消发生后，迟到结果不更新 `profileStates`。

## 2. 点火确认三态与延迟重试

主要文件：

- `Sources/UsageMonitorCore/Models/ChatGPTFireResult.swift`
- `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`
- `Tests/UsageMonitorAppTests/FireLifecycleTests.swift`
- 受枚举穷尽 switch 影响的渲染测试

实施要求：

1. 增加 `.requestSucceededConfirmationUnavailable`，文案固定为“请求成功，暂无法确认”。
2. 更新 `displayText`、`isSuccess`、`isFailure` 与任何穷尽 switch。新增结果使用次要色。
3. 把确认判断收敛成一个可单测的纯函数或私有类型，输入为点火前时间和最多两次实时观察，输出只允许三种请求成功结果。
4. 第一次观察已确认前移 ≥ 60 秒时立即结束；其他情况全部执行 5 秒后的第二次只读刷新。
5. 保持 `fetchFiveHourReset` 的 live-only 规则。若为清楚地区分缓存、实时缺字段和请求失败而引入内部 observation enum，只能包含固定分类，不能携带原始错误或响应。
6. 不改变 CLI 参数、120 秒超时、Process 终止、同 Profile 去重和 A/B 并发规则。

测试矩阵必须完整覆盖：

- 前值存在，第一次实时值前移 ≥ 60 秒：确认，第二次不执行。
- 前值存在，第一次实时值相同，第二次前移：确认。
- 前值存在，两次实时值都未达到阈值：未变化。
- 前值存在，两次都只有缓存／失败／缺时间：暂无法确认。
- 前值不存在，即使后值存在：暂无法确认。
- 第一次缓存、第二次实时前移：确认。
- 第一次实时未变化、第二次刷新确实被执行。
- 应用在 2 秒或 5 秒等待期间停止：无迟到发布、无遗留点火子进程。

已有“两个缓存结果得到未变化”的测试必须改成期望“暂无法确认”；不得为了保留旧断言而违背新语义。

## 3. Command Code 辅助接口容错

主要文件：

- `Sources/UsageMonitorCore/Providers/CommandCodeProvider.swift`
- `Tests/UsageMonitorCoreTests/CommandCodeProviderTests.swift`

实施要求：

1. credits 继续使用抛错解析，是唯一必须成功的数据源。
2. summary 改为可选解析。任何失败返回 `nil`，但不得吞掉 credits 自身的错误。
3. subscriptions 保持可选解析。
4. 不增加网络路径，不改变 Bearer、Accept、超时和重定向防护。
5. 不修改 `ProviderModels` 的持久化结构；使用现有 `summary == nil` 表示统计不可用，避免 1.3.1 引入缓存迁移。
6. monthly window 只组合实际取得的字段：有 credits 余额无 summary 时保留 remaining，limit 和 used 缺失。

测试至少覆盖：

- credits 成功 + summary 503 + subscription 成功：5 小时／周额度 live，summary nil，套餐仍存在。
- credits 成功 + summary 畸形 JSON：额度保留，summary nil。
- credits 成功 + summary 401/403：额度保留，连接不因辅助接口单独进入 authSuspended。
- credits 成功 + summary 失败 + monthlyCredits 存在：月度 remaining 存在，used/limit 不伪造。
- credits 401/403：仍抛 `.invalidCredential`。
- credits 结构不支持：仍失败关闭，不从 summary 或 subscription 拼凑额度。
- 三条允许路径与模型路径阻断测试继续通过。

## 4. Command Code 缓存与统计文案

主要文件：

- `Sources/UsageMonitorApp/Views/UsagePanelView.swift`
- `Tests/UsageMonitorAppTests/DetailPanelLayoutTests.swift`
- `Tests/UsageMonitorAppTests/DetailEvidenceRenderTests.swift`

实施要求：

1. 在 `CommandCodeCardPresentation` 增加纯展示函数，集中生成标题副文案和缓存帮助文本，视图不得另写第二套判断。
2. 严格按需求表处理 connected/stale、套餐存在／缺失。
3. `summaryLines(nil)` 第一行改成“统计暂不可用 · Token — · 请求 —”；后两行保持固定占位结构。
4. `summary != nil && periodBasis == .unknown` 继续显示“统计周期未确认”。
5. stale 帮助文本和 accessibility 必须表达缓存与最后成功时间，不显示底层错误原文。
6. 不改 Command Code 卡片的 416 × 162 pt、轨道宽度、字号、间距和三条额度行。

测试至少覆盖：

- connected + plan、connected + no plan、stale + plan、stale + no plan 四种副文案。
- stale 有／无 `lastSuccessAt` 的帮助文本。
- nil summary 与 unknown period 的文案区别。
- 明暗模式渲染均无截断；stale + 长套餐名仍为单行尾部省略。
- 四种详情页总高度和所有既有布局断言不变化。

## 5. 版本与文档收尾

实现和审核通过后再执行：

1. `VERSION` 从 `1.3.0` 更新为 `1.3.1`。
2. 更新 `CHANGELOG.md`、`README.md` 和 `ROADMAP.md` 的当前状态、测试数与真实验收状态。
3. 修正 `scripts/build.sh` 内嵌 README 的“single app-server”旧描述，使其准确说明两个 Profile 各有独立子进程；不借机改构建流程。
4. 检查 About、Header 和设置页的版本显示来自 bundle；开发态 fallback 不得继续落后于当前版本。
5. 完成 `IMPLEMENTATION_REPORT.md`，Codex 再更新本目录的 `REVIEW.md` 和 `ACCEPTANCE.md`。
6. 未取得真实证据的项目必须保持“待验收”，不得用自动测试代替。

## 6. 固定验证命令

优先使用仓库外 scratch path，避免 iCloud 扩展属性污染构建产物：

```bash
swift test --scratch-path /tmp/minget-131-tests
./scripts/build.sh
codesign --verify --strict --verbose=2 "$HOME/Applications/Minget.app"
```

如果测试提供筛选入口，先运行以下定向组，再运行全量：

```bash
swift test --scratch-path /tmp/minget-131-tests --filter CommandCodeProviderTests
swift test --scratch-path /tmp/minget-131-tests --filter FireLifecycleTests
swift test --scratch-path /tmp/minget-131-tests --filter DetailPanelLayoutTests
swift test --scratch-path /tmp/minget-131-tests
```

实现 Agent 还必须执行只读检查：

- 确认没有新增 chat/completions 或其他模型端点。
- 确认没有读取认证 JSON、浏览器会话或全局配置。
- 确认详情页和设置页没有新增滚动容器。
- 确认公开文件中没有真实邮箱、余额、API Key、token、session id 或原始响应。
- 确认开工前的无关工作区改动仍被保留且没有进入 1.3.1 变更集。

## 7. 实施完成后的交接格式

实现 Agent 最终只报告以下内容，并在 `IMPLEMENTATION_REPORT.md` 留下同样记录：

1. 修改文件清单及每个文件的用途。
2. 四项需求各自的实现落点。
3. 新增／修改测试名称、总测试数和完整命令结果。
4. Release 构建和签名结果。
5. 实际运行检查结果，以及哪些仍未验证。
6. 已知问题和范围外事项。
7. 明确声明是否执行了真实点火、真实带认证请求、提交、推送或发布。

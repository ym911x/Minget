# 1.3.1 稳定性修补需求

状态：方案已确认，已实现并完成 Codex 独立复核；真实界面和明确列出的真实服务项目仍待用户验收。

本文把 1.3.1 的产品判断、状态语义和边界一次性固定。实现 Agent 不得自行扩大范围；遇到本文没有覆盖且会改变用户可见行为的情况，停止实现并记录问题，交由 Codex 与用户确认。

## 1. 版本目标

1. 两个 ChatGPT Profile 仍并行刷新，但任一 Profile 完成后立即发布自己的新状态，不再等待另一 Profile。
2. 点火请求成功后，明确区分“窗口确实未变化”和“缺少证据，暂时无法确认”。
3. Command Code 的额度、统计和订阅按重要性分层容错，辅助接口失败不能遮住已经取得的真实额度。
4. Command Code 显示缓存数据时给出明确且紧凑的文字提示。

1.3.1 是稳定性修补版。窗口尺寸、卡片顺序、额度语义、菜单栏格式和凭证安全边界保持 1.3.0 不变。

## 2. 已核实的 1.3.0 基线

- 两个 ChatGPT Profile 的请求已经并行执行，但 `UsageViewModel.refresh` 等待整个 Task Group 完成后才调用一次 `applyProfileStates()`。因此快速 Profile 的结果会被慢速 Profile 延迟显示。
- Profile 运行时已经按 Profile 加锁，`CodexProfileRuntime.state()` 可提供一致的值快照，适合逐个完成后发布。
- 点火确认目前只有“新窗口已确认”和“请求成功，窗口未变化”。如果点火前缺少重置时间，或点火后只取得缓存／请求失败，也会落入“窗口未变化”。
- 点火后的第一次确认只有在没有取得实时重置时间时才重试。第一次取得实时但尚未变化的旧时间时不会重试，无法覆盖服务端延迟更新。
- Command Code 的 credits 与 summary 都是成功条件；summary 失败会使本次整体失败。subscriptions 已经是辅助数据，失败不会遮住其他数据。
- Command Code 卡片使用套餐名优先于连接文字。存在套餐名且报告为 stale 时，卡片只通过轨道变淡暗示缓存，没有明确的“缓存”文字。
- 1.3.0 自动测试、Release 构建和真实详情页已经通过。真实 DeepSeek 菜单栏余额、A/B 应用内真实点火、机器重启后的缓存隔离仍在 1.3.0 验收台账中标为待验收。

## 3. 双 Profile 独立发布

### 3.1 固定行为

- 一轮刷新仍同时启动所有 Profile，继续禁止为同一轮叠加第二组请求。
- Task Group 的每个子任务返回稳定 `profileID`。父任务使用 completion-order 迭代；每收到一个完成项，立即在 MainActor 上重新发布 `profileStates` 并递增 `tick`。
- 发布仍从 `coordinator.runtimes` 读取完整值快照，因此数组顺序永远保持 A、B，不按照完成顺序重排。
- `isRefreshing` 是整轮状态：开始时为 `true`，最后一个 Profile 完成或整轮取消后才恢复 `false`。
- 快速 Profile 完成后，其额度、账号、缓存／错误状态和卡片刷新状态必须立即更新；慢速 Profile 继续保留自己的 `isRefreshing == true`。
- 某个 Profile 失败后也立即发布失败或缓存状态，不等待另一个 Profile。
- 完成整轮后把 `refreshTask` 清空。`stop()` 后或任务取消后不得再发布状态。
- 不改变 `UsageService`、Profile 缓存命名空间、失败预算、app-server 数量和子进程停止策略。

### 3.2 明确不做

- 不增加单账号手动刷新按钮。
- 不允许同一 Profile 同时存在两个普通额度请求。
- 不因为某一 Profile 失败而取消另一 Profile。
- 不把 A 的数据临时复制给 B，也不让菜单栏自动切换到另一个账号。

## 4. 点火确认三态

### 4.1 新增结果

在 `ChatGPTFireResult` 增加：

| 枚举值 | 固定显示文案 | 颜色语义 |
| --- | --- | --- |
| `.requestSucceededConfirmationUnavailable` | `请求成功，暂无法确认` | 次要色，既不标成功也不标失败 |

现有文案保持：

| 枚举值 | 固定显示文案 |
| --- | --- |
| `.requestSucceededWindowConfirmed` | `新窗口已确认` |
| `.requestSucceededWindowUnchanged` | `请求成功，窗口未变化` |

`isSuccess` 仅对 `.requestSucceededWindowConfirmed` 为真。新增结果与 `.requestSucceededWindowUnchanged` 的 `isFailure` 都为假。CLI 定位、启动、退出码和超时错误规则不变。

### 4.2 固定时序

1. 点火前保存该 Profile 当前的 5 小时 `resetsAt`，可能为空。
2. CLI 返回成功后等待 2 秒，执行第一次只读强制刷新。
3. 如果第一次已经拿到实时 `resetsAt`，并且比点火前晚至少 60 秒，立即报告“新窗口已确认”，不做第二次刷新。
4. 其他情况全部等待 5 秒，再执行一次只读强制刷新。这里包括：缓存结果、请求失败、实时结果缺少重置时间，以及实时重置时间尚未变化。
5. 第二次刷新后按照 4.3 的真值表只产生一个最终结果。

第二次刷新只是读取额度，不得再次执行 Codex 模型请求。

### 4.3 最终分类真值表

| 点火前有效时间 | 两次确认中的实时有效时间 | 是否至少有一个时间前移 ≥ 60 秒 | 最终结果 |
| --- | --- | --- | --- |
| 有 | 有 | 是 | `requestSucceededWindowConfirmed` |
| 有 | 有 | 否 | `requestSucceededWindowUnchanged` |
| 有 | 无 | 不适用 | `requestSucceededConfirmationUnavailable` |
| 无 | 任意 | 无法比较 | `requestSucceededConfirmationUnavailable` |

缓存快照不属于“实时有效时间”。实时快照中 5 小时窗口或 `resetsAt` 缺失，也不属于“实时有效时间”。不得用缓存时间确认新窗口。

### 4.4 退出与并发

- A、B 的点火继续互不阻塞；同一 Profile 重复点击继续返回 `.alreadyRunning`。
- 应用停止期间取消等待并终止自有点火子进程，停止后不发布任何点火结果。
- 不增加点火历史，不记录 stdout、stderr、session id、prompt 或 token。

## 5. Command Code 分层容错

### 5.1 数据层级

固定优先级如下：

| 接口 | 层级 | 失败后的行为 |
| --- | --- | --- |
| `/alpha/billing/credits` | 主数据、必须 | 本轮失败；有旧值则显示 stale，无旧值则按既有错误分类显示不可用 |
| `/alpha/usage/summary` | 辅助数据、可选 | 本轮额度仍为 live；`summary == nil`，统计区明确显示暂不可用 |
| `/alpha/billing/subscriptions` | 辅助数据、可选 | 保持现状；套餐与计费周期字段缺失，不影响额度和统计 |

只要 credits 成功且至少包含一个可解析的 5 小时或周额度窗口，本次读取就可以生成 live `ProviderUsage`。summary 的网络错误、5xx、401/403、JSON 错误或字段结构变化都只影响统计区；凭证状态由主数据 credits 的结果决定。这样可以兼容不同端点权限或短暂故障，同时不把任何缺失字段伪造成数字。

### 5.2 月度额度规则

- credits 返回 `monthlyCredits` 而 summary 不可用时，月度行显示真实剩余值，格式为 `$余额 / —`。
- 只有 summary 同时提供真实 `totalMonthlyCredits` 时，才按既有规则组合出月度已用和总计。
- 不推算月度总额、计费周期起点或重置时间。
- subscriptions 缺少有效起止时间时，月度时间轨道继续显示不可用，不假定 30 天。

### 5.3 统计区固定文案

summary 不可用时仍保持三行和现有卡片高度：

1. `统计暂不可用 · Token — · 请求 —`
2. `输入 — · 输出 — · 成功 — · 失败 —`
3. `成功率 — · 成本 —`

summary 存在但 `periodBasis == .unknown` 时，第一行继续使用 `统计周期未确认`，不得误写成“统计暂不可用”。

### 5.4 缓存标识

Command Code 标题副文案遵循以下唯一规则：

| 连接状态 | 套餐名 | 副文案 |
| --- | --- | --- |
| connected | 有 | 原套餐名 |
| connected | 无 | `已连接` |
| stale | 有 | `<套餐名> · 缓存` |
| stale | 无 | `缓存数据` |
| 其他 | 任意 | 既有固定连接／错误文案 |

- stale 时额度轨道和时间轨道继续变淡。
- stale 副文案的帮助文本固定为 `缓存数据 · 上次成功 <MM-dd HH:mm>`；时间不存在时为 `缓存数据 · 成功时间未知`。
- 帮助文本使用本机时区，不新增相对时间，不展示底层错误原文。
- 辅助功能标签必须包含相同的缓存语义。
- 卡片尺寸、字号和三条额度行不变；长套餐名继续单行尾部省略。

## 6. 保持不变的用户界面

- 详情页仍为 440 pt 单列，四种高度仍为 552 / 498 / 384 / 330 pt。
- ChatGPT、DeepSeek 和 Command Code 卡片尺寸、顺序、间距、颜色和进度条含义不变。
- 菜单栏 A/B/DeepSeek 的文字、字号、时间轨道和空间降级不变。
- 设置页仍为 520 × 600 pt，不增加开关或账号编辑入口。
- 不修改 DeepSeek 余额解析、Keychain、显示开关和状态页读取。

## 7. 安全与数据边界

- 不新增网络端点，不调用任何模型端点验证 API Key。
- Command Code 仍只允许现有三条只读路径，仍拒绝跨域重定向。
- 不读取全局 Codex／Claude 配置或认证文件，不读取现有浏览器会话。
- 不把 API Key、OAuth token、Cookie、邮箱、真实余额、原始响应和子进程输出写入源码、日志、文档、fixture 或截图。
- 所有自动测试使用 fake transport、fake executable 或合成数据，不消耗真实额度。

## 8. 明确非目标

- 第三个 ChatGPT Profile、Profile 重命名、隐藏或路径编辑。
- 自动点火设置、Fire All、点火历史和 LaunchAgent 管理。
- 修改详情页宽高、卡片布局或继续压缩字号。
- 修改一秒时钟、刷新周期或新增功耗优化。1.3.1 只做发布前后观察，未经测量不改频率。
- Apple Developer ID、公证、自动更新或安装器。
- 新服务、新端点、新通知和诊断导出。
- 修改 `docs/archive/v1.0/` 或覆盖历史版本结论。

## 9. 完成定义

1. 四项行为均有确定性的自动测试，旧测试全部通过。
2. 快速 Profile 的状态可在慢速 Profile 解除阻塞前被观察到，数组顺序仍为 A、B。
3. 点火确认三种结果全部由真值表覆盖；实时旧时间会触发第二次刷新，缓存永远不能确认窗口。
4. Command Code summary 和 subscriptions 任一失败时，真实额度仍可显示；credits 失败仍按既有缓存和错误规则处理。
5. stale + 套餐名时界面明确出现“缓存”，详情页尺寸与三行摘要不变化。
6. 全量测试、Release 构建、严格签名和退出后子进程清理通过。
7. 真实界面检查确认无截断、无尺寸变化、无状态歧义。
8. 任何真实点火、Git 提交、推送、标签或 GitHub Release 都必须另有用户明确授权。

# 1.4.2 实施报告

状态：实现、独立审核、538 项 Swift 测试（1 项环境跳过、0 失败）、53 项外部脚本断言、严格签名安装及自然定时运行核验完成。真实界面三次手动刷新已观察到数据返回；用户于 2026-09-24 确认详情页关闭重开三次均正常。第三轮聚合结束标志未单独留证，保留此证据边界。 GitHub 发布核验见 ACCEPTANCE.md；不承诺服务端窗口必然推进。

## 1. 修改文件

### 服务层（UsageMonitorCore）

| 文件 | 变更 |
| --- | --- |
| `Sources/UsageMonitorCore/Services/UsageService.swift` | 重写：`performShared` 单飞 + `WaiterBox` 等待者 + 手动补刷；`OperationKind`（full / rateLimitsOnly / wakeProbe）；`gateOutcome` 门槛策略；`runEpisode` 立即重试 + 梯子记账；`runWakeProbeRead` 占槽探测；`stop()` 先兑现等待者再有界排空；`FetchResult.readStartedAt` 与 `connectionEpoch`；新子进程发布时推进连接代次。 |
| `Sources/UsageMonitorCore/Services/CodexRetryPolicy.swift` | 新增：纯策略（立即重试次数、退避阶梯、下次自动重试、到期判定、可自动重试判定）。 |
| `Sources/UsageMonitorCore/Services/CodexAppServerClient.swift` | 拆分超时常量：quota 15 s / handshake 5 s / identity 3 s。 |
| `Sources/UsageMonitorCore/Services/CodexProfilesCoordinator.swift` | fetch / fetchRateLimitsOnly / probeAfterWake 传递拆分超时；`fetchRateLimitsOnly` 增加 `resetFailureBudget`；提供各 Profile 的自动重试时间。 |
| `Sources/UsageMonitorCore/Services/CodexProfileRuntime.swift` | `ProfileIdentityState` 状态机与记录规则；缓存回退的结果按失败路径处理身份；额度成功但身份失败仅在同一 app-server 连接代次降级 previous，连接替换后清除旧身份。 |
| `Sources/UsageMonitorCore/Models/ChatGPTFireResult.swift` | 三态重命名 + `observesAdvancedReset` 阈值 60 秒 + 文档注释。 |

### 应用层（UsageMonitorApp）

| 文件 | 变更 |
| --- | --- |
| `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift` | `pendingManualRefresh` 恰好一次补刷；自动轮跳过门槛未到期 Profile，timer 在 retry deadline 早于常规周期时缩短等待；点火确认新鲜度屏障（`fireCompletedAt`）；点火确认读取旁路门槛；停止时清理。 |
| `Sources/UsageMonitorApp/ViewModels/CodexProfileViewState.swift` | 以 `identity` 替代裸账号；`identityLabel`；非实时卡片 `lastSuccessText`；点火差值词表。 |
| `Sources/UsageMonitorApp/Views/CodexProfileCard.swift` | 账号行渲染"上次身份"标签。 |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 头部"部分数据未更新"聚合状态；手动刷新按钮不再在进行中禁用；版本回退值 1.4.2。 |
| `Sources/UsageMonitorApp/Views/MingetAboutView.swift` / `MingetSettingsView.swift` | 版本回退值 1.4.2。 |
| `VERSION` | `1.4.2`。 |

### 外部脚本

| 文件 | 变更 |
| --- | --- |
| `scripts/minget-fire/bin/minget-fire` | 新增：调度器模板（严格串行、120 s 超时、观测三态、干净日志、`MINGET_FIRE_*` 覆盖）。 |
| `scripts/minget-fire/libexec/minget-fire/read-codex-reset.py` | 新增：字节缓冲读取器（单一单调总期限、分包/粘包、进程组回收覆盖主进程先退出与 TERM 忽略）。 |
| `scripts/minget-fire/libexec/minget-fire/run-with-timeout.py` | 新增：有界执行器模板，结束后清理本次命令的专属进程组。 |
| `scripts/minget-fire/tests/run_tests.sh` | 新增：假 CLI 与隔离 HOME 安装器测试，覆盖进程组回收、未知哈希拒绝、安装与回滚命令。 |
| `scripts/minget-fire/README.md` / `SHA256SUMS` | 新增：模板说明与预期哈希。 |
| `scripts/install-minget-fire.sh` | 新增：显式安装器（模板与旧文件校验、已知旧版 hash allowlist、先全量预检/备份、原子替换、精确回滚命令、无 launchd 操作）。 |

### 测试

| 文件 | 变更 |
| --- | --- |
| `Tests/UsageMonitorCoreTests/UsageServiceTests.swift` | 重写 + 新增：单飞、补刷、停止释放、退避梯子、唤醒探测占槽/升级、`readStartedAt`、连接代次、定位器。 |
| `Tests/UsageMonitorCoreTests/CodexProfileIdentityTests.swift` | 新增：身份状态机 9 项场景，覆盖连接代次替换。 |
| `Tests/UsageMonitorCoreTests/CodexProfilesCoordinatorTests.swift` | 增加 Profile 级独立梯子断言。 |
| `Tests/UsageMonitorAppTests/DetailEvidenceRenderTests.swift` / `DetailPanelLayoutTests.swift` | 视图状态初始化改用 `identity:`；文案断言更新。 |

## 2. 关键设计决定

### 2.1 身份与连接代次

独立审核将“同一连接”明确按实际 app-server 子进程连接处理。`UsageService` 发布新子进程时递增 `connectionEpoch`，实时结果携带其读取代次。`CodexProfileRuntime` 仅在当前代次保留上次身份；重试导致子进程替换、后续额度查询缺少身份或点火确认换到新连接时均清除旧身份，直到新连接成功读取身份。测试覆盖同代次身份查询缺失、连接替换后的额度查询和只读确认、重试重启与重新确认。

### 2.2 缓存回退结果的身份路径

`UsageService` 在轮次失败但有缓存时返回 `.success(FetchResult(isLive: false, error: ...))`（回退策略），退避门槛同样如此。协调器把这类结果交给 `recordFetchSuccess`，后者识别 `!isLive && error != nil` 并转投 `recordFetchFailure` 的身份处理，否则一次瞬时失败就会因为"快照到达"而被误判为成功并清掉上次身份。

### 2.3 探测占槽与升级

唤醒探测经 `performShared(.wakeProbe)` 运行，修复独立审核指出的两个缺陷：

- 探测不再与随后的完整读取并发使用同一子进程（探测持槽，读取者加入等待）。
- 探测失败关闭死连接不再可能拆掉另一轮正在使用的连接（持槽期间没有并发使用者）。

加入了一个无法产出实时读数的探测的完整读取，由同一执行者立即补跑一轮 `.full(false)`；探测调用者最终拿到补跑轮的结果（实时则 `.refreshed`）。这避免把探测的死胡同直接交给等待者，也避免唤醒路径重复触发一轮完整刷新。

### 2.4 点火确认的新鲜度屏障

`FetchResult` 新增 `readStartedAt`（仅实时读数携带）。`finishFire` 在请求返回后记录 `fireCompletedAt` 作为屏障；确认读数若来自一次屏障之前开始的共享读取（合并/加入所致），一律按 `noEvidence` 处理，不能当作点火后证据。

### 2.5 门槛策略的返回值

退避门槛激活且无缓存时，服务重新抛出已记录的失败而不是静默成功；有缓存时回缓存并保留 `isLive=false` 与错误字段。手动调用与点火确认以 `resetFailureBudget: true` 旁路门槛（确认属于手动点火的一部分）。

### 2.6 外部脚本观测流程

与 1.3.x 的差异：首读未观测到前进（包括读数失败、无基线）也会再等 5 秒做第二次只读读取，与"批准方案"一致；观测行补充 `duration`（观测读取耗时）、`used_before` / `used_after` / `drift`（实测差值）。`drift` 是在任务词表基础上按独立审核要求新增的数值字段，仍为纯数字，无身份信息。

## 3. 测试命令与结果

```sh
# 全套 Swift 测试（Core + App）
swift test --scratch-path "${TMPDIR:-/tmp}/minget-build"
# 结果：Core 380 项、App 158 项；1 项既有 AX 环境跳过，0 失败，538 项执行

# 外部脚本模板测试（假 CLI，/tmp 沙盒，无网络无模型请求）
scripts/minget-fire/tests/run_tests.sh
# 结果：53 项断言全部通过

# 安装器演练（隔离 HOME，未触碰真实 ~/.local）
HOME="$(mktemp -d)" scripts/install-minget-fire.sh --check   # 哈希校验 + 计划输出，无写入
HOME="$(mktemp -d)" scripts/install-minget-fire.sh           # 备份 + 原子替换 + 回滚指令
# 篡改模板后安装被 SHA256SUMS 拒绝（exit 1），恢复后校验通过
```

本机签名安装与自然定时运行已实际核验；真实界面三次手动刷新已观察到数据返回；用户于 2026-09-24 确认详情页关闭重开三次均正常。第三轮聚合结束标志未单独留证，保留此证据边界。 详见 ACCEPTANCE.md。不承诺每次请求都会令服务端窗口即时推进。

## 4. 风险与验收边界

1. **手动补刷连点**：每轮进行中最多合并一个手动补刷；补刷运行期间再次点击可再排一轮。属于“每轮恰好一次”语义，极端连续点击可能产生连续刷新。
2. **服务端窗口推进**：请求零退出只证明请求执行成功；窗口观测可能未变化或不可用，应用不会额外发模型请求强制推进。
3. **墙钟屏障**：点火证据比较基于 `Date()`；系统时间大幅回拨理论上可能影响重叠读取的新鲜度判断，自动化覆盖常规边界，未模拟真实系统时钟修改。
4. **自然运行样本边界**：已核对安装后首个自然 LaunchAgent 运行；单次运行能验证执行顺序、退出码与观测日志，但不能证明 OpenAI 服务端每次都推进窗口。

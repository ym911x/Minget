# 1.4.2 实施任务单

状态：实现、独立审核、538 项 Swift 测试（1 项环境跳过、0 失败）、53 项外部脚本断言、严格签名安装及自然定时运行核验完成。真实界面三次手动刷新已观察到数据返回；用户于 2026-09-24 确认详情页关闭重开三次均正常。第三轮聚合结束标志未单独留证，保留此证据边界。 GitHub 发布核验见 ACCEPTANCE.md；不承诺服务端窗口必然推进。

## 1. 服务层单飞与等待者语义（UsageService）

- [x] 1.1 共享操作槽：`performShared` 成为唯一入口；运行中调用者加入并等待实际结果（`WaiterBox`），不返回忙碌错误。
- [x] 1.2 手动补刷：手动调用在运行中排队恰好一次补刷，由同一执行者在结果分发后立即运行；等待者收到补刷轮实际结果。
- [x] 1.3 分发与释放同锁区间：结果交付、补刷认领、操作槽释放合并在同一个 `NSLock` 临界区，消除"解锁后到达、无人唤醒"的窗口。
- [x] 1.4 唤醒探测占槽：`probeRateLimitsAfterWake` 经由共享槽运行（`.wakeProbe`）；探测运行中开始的完整读取加入探测；探测无法产出实时读数时为加入的读取者补跑一轮真实读取。
- [x] 1.5 停止语义：`stop()` 先以 shutdown 兑现全部等待者（含补刷等待者），再进行有界排空；卡死的操作不阻塞停止返回。
- [x] 1.6 退避门槛策略：门槛激活时有缓存回缓存（`isLive=false` 携带错误），无缓存重新抛出已记录错误；手动与点火确认旁路。

## 2. 超时与重试梯子

- [x] 2.1 拆分超时常量：quota 15 s / handshake 5 s / identity 3 s（`CodexAppServerClient`），各调用路径按方法传递。
- [x] 2.2 `CodexRetryPolicy`：立即重试 1 次；退避 30/60/120/300 封顶 300；`nextAutomaticRetry(now:failedEpisodes:)`、`isAutomaticAttemptDue`、`isAutoRetryable`。
- [x] 2.3 服务接入梯子：`failedEpisodes` / `nextAutomaticRetryAt` / `manualRetryRequired`；成功清零；手动重试重置；不可自动重试错误进入手动状态。
- [x] 2.4 调度器接线：协调器暴露 `isAutomaticRetryGated` 与各 Profile 的自动重试时间；自动 timer 按最近 deadline 缩短等待，自动刷新轮跳过门槛未到期 Profile；点火确认读取以 `resetFailureBudget: true` 旁路门槛。
- [x] 2.5 可查询状态：`isRetryBackoffActive`、`isManualRetryRequired`、`automaticRetryGate`、`lastFailureSummary`。

## 3. 身份状态机（CodexProfileRuntime）

- [x] 3.1 `ProfileIdentityState`：confirmed / previous / unavailable，`previous` 显示"上次身份"标签。
- [x] 3.2 记录规则：成功确认或替换；额度成功但身份失败降级为 previous；额度瞬时失败保留 previous；退出登录等不可恢复失败清除已存身份；shutdown 不做声明。
- [x] 3.3 连接语义：身份绑定实际 app-server `connectionEpoch`；同一代次内临时失败可显示上次身份，新 child 发布后必须重新确认。
- [x] 3.4 确认读取不触碰身份状态。

## 4. 界面与视图模型

- [x] 4.1 `CodexProfileViewState` 以 `identity` 替代裸账号；`lastSuccessText` 供非实时卡片显示最近成功时间。
- [x] 4.2 `CodexProfileCard` 账号行：橙色"上次身份"标签 + 邮箱。
- [x] 4.3 头部聚合状态：存在非实时 ChatGPT 卡片时显示"部分数据未更新"，不暗示全部新鲜。
- [x] 4.4 手动刷新按钮在进行中不再禁用；点击排队恰好一次补刷。
- [x] 4.5 点火结果文案与差值、最近 3 次历史沿用 1.3.x 词表（重命名后的三态）。
- [x] 4.6 点火确认新鲜度屏障：请求完成时间作为屏障，屏障前开始的共享读数不计为点火后证据（`FetchResult.readStartedAt`）。

## 5. 类型与文档内模型

- [x] 5.1 `ChatGPTFireResult` 三态重命名：`requestSucceededResetAdvanced` / `requestSucceededResetUnchanged` / `requestSucceededResetUnavailable`；`observesAdvancedReset(live:previous:)` 阈值 60 秒。
- [x] 5.2 `CodexProfileRuntimeState` 增加 `identity`；旧 `account` 字段保持渲染兼容。
- [x] 5.3 UI 版本号回退值更新为 1.4.2；`VERSION` 更新为 1.4.2。

## 6. 外部点火计划脚本模板

- [x] 6.1 `scripts/minget-fire/bin/minget-fire`：严格串行 A → 15 s → B → 15 s → Command Code；120 s 请求超时；`MINGET_FIRE_*` 环境覆盖全部路径与时限，生产值为默认。
- [x] 6.2 请求结果与观测分离：请求成功一律退出 0；观测三态（ADVANCED / UNCHANGED / UNAVAILABLE）独立记录；超时 124、进程失败非零。
- [x] 6.3 观测流程：请求后 2 秒首读；未见前进（含失败、无基线）再等 5 秒读一次；记录 duration / used_before / used_after / drift；绝不发第二次模型请求。
- [x] 6.4 `read-codex-reset.py`：字节缓冲 `os.read`、单一单调总期限、分包/粘包 JSON 兼容、自有进程组 + TERM→KILL 整组回收（含 leader 先退出、grandchild 忽略 TERM），`MINGET_FIRE_CODEX` 可覆盖。
- [x] 6.5 `run-with-timeout.py`：有界执行器（进程组、124、TERM→KILL）；正常或超时退出均清理专属进程组。
- [x] 6.6 干净日志：固定字段词表；子进程输出丢弃；无身份信息。
- [x] 6.7 `scripts/install-minget-fire.sh`：SHA256SUMS 模板校验 + 已知旧版 hash allowlist → 全目标预检 → 全量备份校验 → 原子替换（bin 755 / libexec 700）→ 打印精确回滚指令；不认识的文件在任何写入前拒绝，无 plist/launchctl 操作。
- [x] 6.8 `scripts/minget-fire/tests/run_tests.sh`：假 CLI 覆盖串行顺序、超时后续跑、聚合退出码、分包/粘包、总期限、进程组回收、观测退出语义、默认值、日志词表与身份标记泄漏检查。

## 7. 测试

- [x] 7.1 核心测试重写与新增：拆分超时、唤醒探测（占槽/合并/升级）、单飞等待者、补刷恰好一次、退避梯子数值与门槛、不可重试错误、停止释放等待者、身份连接代次状态机（9 项）。
- [x] 7.2 修订旧断言：原"失败后永久冻结"类测试改为"立即重试一次 + 退避门槛 + 手动旁路"语义。
- [x] 7.3 全套 `swift test` 通过（Core 380、App 158、1 项 AX 环境跳过）；`run_tests.sh` 53 项假 CLI/安装器断言通过。

# 1.4.2 实施自审（供独立复核）

状态：实施完成，自审通过。本文逐条回应 INDEPENDENT_REVIEW.md 的预审发现，供 Codex 独立复核最终差异。

## 1. 对独立审核预审发现的逐条回应

| 审核发现 | 回应 |
| --- | --- |
| `probeRateLabelsAfterWake` 空闲分支直接读取现有 client，不占用 `operationRunning`，可与完整查询并发；失败可能关闭另一轮正在使用的连接 | 已修复：探测改为经 `performShared(.wakeProbe)` 占槽运行（`UsageService.runWakeProbeRead`）。探测持槽期间开始的完整读取加入探测并等待实际结果；探测失败关闭死连接时不存在并发使用者。测试：`testFetchJoiningARunningWakeProbeReceivesItsActualResult`。 |
| 加入探测但探测无法产出实时读数的完整读取，被交回探测失败 | 已修复：`performShared` 释放循环中，探测轮若未产出实时结果且有等待者，等待者的盒子保持排队，同一执行者立即补跑一轮 `.full(false)` 并把补跑轮实际结果交付给他们。测试：`testFetchJoiningAFailingWakeProbeRunsARealEpisodeForIt`。 |
| `performShared` 仅在 `.full` 时执行手动补刷；确认读取期间排队的手动等待者会被返回 shutdown | 已修复：补刷认领不再限定当前操作类型；任何操作（含 `.rateLimitsOnly`、`.wakeProbe`）结束后都会认领排队的补刷并以 `resetFailureBudget: true` 运行。测试：`testManualFollowUpRunsEvenWhenTheRunningOperationIsAConfirmationRead`。 |
| 结果分发后先解锁、再由 defer 清除 `operationRunning`，间隙加入者可能永远收不到结果 | 已修复：交付、补刷认领、槽释放合并在同一个锁临界区（repeat 循环 + `runFollowUp` 标志），不存在"已解锁、未清理"的窗口。测试：全套单飞/停止用例反复覆盖该窗口。 |
| 点火确认可加入点火前已开始的查询，旧证据可能被当作点火后读数 | 已修复：`FetchResult` 新增 `readStartedAt`（仅实时读数携带）；`finishFire` 以请求完成时间为屏障，屏障前开始的读数按 `noEvidence` 处理。测试：`testLiveResultsCarryReadStartedAtAndCacheServedResultsDoNot` + 全部点火生命周期测试（真实服务路径下屏障自然成立）。 |
| 自动退避期限需实际接入调度器与按钮补刷 | 已修订：协调器提供自动重试到期时间；ChatGPT timer 在最近 deadline 早于常规刷新周期时缩短等待；到期前逐 Profile 跳过，不影响另一账号；确认读取和手动补刷旁路。测试：`testRetryDeadlineShortensNormalTimerAndExpiredGateUsesNormalCadence`、`testAutomaticRetryDatesExcludeProfilesRequiringManualAction`，并覆盖服务层退避阶梯。 |
| UI 按钮的 `.disabled(isAnyRefreshInFlight)` | 已修复：手动刷新按钮不再禁用；进行中点击排队恰好一次补刷（`UsagePanelView` 移除 `.disabled`）。 |
| `recordFetchSuccess` 在额度成功但身份查询失败时直接置 unavailable | 已修复：额度成功 + 身份未解析 + 已存身份存在，且仍属同一 app-server 连接代次时降级 `previous`；连接替换后清除旧身份。测试覆盖同代次保留与 full/confirmation 换代清除。 |
| 外部脚本只有首次确认失败才做第二次读取；首读未推进也应等 5 秒再读 | 已修复：`fire_account` 观测改为"首读未见前进（含失败、无基线）→ 等 5 秒再读一次"；与查询端 `FireWindowConfirmation` 的两段式一致。 |
| 需补充读取耗时、前后 used 与差值记录 | 已实现：观测行含 `duration`（观测读取耗时）、`used_before` / `used_after`、`drift`（数值差值）；词表仍为纯数字字段，无身份信息。测试：`run_tests.sh` 词表正则 + `drift` 断言。 |
| 身份连接代次失效机制是否完整 | 已修订：身份绑定 `FetchResult.connectionEpoch`。新 child 上线后旧邮箱不会沿用；额度实时读取和只读确认都覆盖换代失效，除非新连接重新确认身份。 |
| 安装器是否保护意外本地改动 | 已修订：真实安装 `--check` 只读确认三个目标匹配记录的 pre-1.4.2 基线；沙盒测试验证任意未知 hash 在全体写入前失败，空 HOME 安装及精确回滚命令通过。 |
| Python 进程组退出清理 | 已修订：直接 child 先退出、grandchild 忽略 TERM 的测试通过；期限后对专属进程组升级 SIGKILL。 |

## 2. 自审检查单

- [x] 等待者收到对应轮次实际结果；忙碌不再作为失败或缓存返回。
- [x] 停止以 shutdown 兑现全部等待者（含补刷等待者）后有界排空；`stop(shutdownTimeout: 0.5)` 不被卡死操作阻塞。
- [x] 超时拆分 15/5/3 秒在真实客户端与全部调用路径生效（含超时记录断言）。
- [x] 退避 30/60/120/300 封顶 300；成功清零；手动旁路；不可重试错误不循环。
- [x] 身份三态与"上次身份"标签；确认替换、退出登录、不可恢复失败使身份失效。
- [x] 卡片 fetching/live/cache/failure 与最近成功时间；头部聚合不暗示全部新鲜。
- [x] 点火三态文案 + 差值 + 最近 3 次历史；确认只读、2 s/5 s、无第二次模型请求。
- [x] 脚本模板退出码语义：请求成功观测未变化/不可用 exit 0；超时 124；进程失败非零。
- [x] 读取器字节缓冲 + 单一总期限 + 分包/粘包 + 进程组回收（含孤儿子进程回收断言）。
- [x] 安装器哈希校验、备份校验、原子替换、回滚指令；无 plist 写入、无 launchctl 重载、不从构建产物安装。
- [x] 全部日志仅含固定词表字段；测试断言无身份标记泄漏。

## 3. 最终发布门槛状态

1. [x] 全套自动测试、严格签名构建、签名安装及外部脚本备份安装。
2. [x] 新脚本安装后的首个自然定时运行核验；A 窗口观测不可用、B 窗口未变化，均如实记录。
3. [x] 真实详情页手动刷新及用户三次重开验收；证据边界见 ACCEPTANCE.md。
4. [x] GitHub 提交 `e094a67`、注释标签 `v1.4.2`、正式 Release、公开页面 HTTP 200 与 CI `35890064042` 成功均已核验。

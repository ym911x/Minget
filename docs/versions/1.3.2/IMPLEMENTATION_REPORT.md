# 1.3.2 实施报告

状态：原定优化与后续新增的每日多时点点火、Command Code 卡片点火均已实现，Command Code 真实手动点火已由用户确认成功。用户于 2026-09-20 接受并授权发布；真实睡眠/唤醒、完整界面和 Command Code 定时点火转为发布后验证项，不改记为通过。

## 基线与边界

- 日期：2026-09-20
- 基线 HEAD：`5ec2b45`，发布分支 `main`
- 版本：`1.3.2`
- 全量测试使用 `mktemp` 创建的系统临时 scratch，避免 iCloud Finder 扩展属性导致 XCTest 签名失败。
- 最终 PATH 修复后的 Release、运行副本与归档副本位于 `/tmp/minget-132-release-*`。早先一次验证误用了构建脚本默认路径，已将旧的 1.3.2 测试包写入 `/Users/yuyimeng/Applications/Minget.app`；后续最终验证未再修改该安装路径。
- 自动测试只使用 fake CLI；用户随后在 `/tmp/minget-132-pathfix-run/Minget.app` 完成一次真实 Command Code 手动点火并确认成功。
- 未读取全局 Codex/Claude/Command Code 认证文件、浏览器会话或现有隔离目录内容。

## 1. 实现结果

### 点火确认

- `FireWindowConfirmation.classify` 增加 `previousWasLive`。只有实时前值才能判定「确认」或「未变化」；nil/stale/unavailable 前值均完成轻量读取更新卡片，但最终固定为「暂无法确认」，无差值。
- 确认路径只做 `handshake + rateLimits/read`，不读身份、不更新账号归属、不触发迁移，也不绕开 failure episode。
- footer 将结果和差值拆成兄弟文本：结果优先级 2、左侧重置摘要 1、差值 0；辅助功能值使用完整组合，tooltip 使用同语义的最近历史。
- 每 Profile 在内存保留最近 3 次完成时间、结果和可选差值；不持久化、不进日志。

### 点火计划与 Command Code 点火

- `FireSchedulePreferences` 按 OpenAI A、OpenAI B、Command Code 保存多个每日本地时间；每条独立勾选，新增默认不启用。每 30 秒、启动凭证 prime 完成后、唤醒和时钟改变时评估。
- 每条持久化上次计划时刻，防止重复 tick、唤醒和重启重复点火；错过时间只补跑 10 分钟。相邻已启用时间小于 5 小时时显示橙色提示。
- `CommandCodeFireService` 直启官方 CLI，不经 shell；固定最小参数、禁用自动更新/session/skills，每次使用唯一的隔离 `HOME` 并在进程结束后删除，Key 只存在子进程环境，stdout/stderr 丢弃。超时和退出只终止自有 PID。
- 真机反馈发现官方 CLI 使用 `--max-turns 1` 时，已完成单轮请求仍按契约返回退出码 8。原实现将所有非零码当成请求失败；现在仅将官方 `MAX_TURNS_REACHED = 8` 当作请求已执行并继续 credits 确认，其他非零码仍失败。
- 第二次真机反馈确认修复包仍在 CLI 阶段失败。对照验证发现 Finder 启动的稀疏 `PATH` 无法为官方 CLI 的 `#!/usr/bin/env node` 解析 Homebrew Node，退出码为 127；同一参数补入 `/opt/homebrew/bin` 后能正常启动 CLI，并按合成假 Key 返回认证退出码 3。子进程现在将已定位的 CLI 目录、常见 Homebrew 目录和继承目录合并为去重 `PATH`，不经 shell，也不增加凭证暴露面。
- CLI 成功后最多两次读取 `credits` 的 5 小时 `resetsAt`，复用 live 前值、60 秒阈值、三态、差值与 3 条内存历史。手动点火允许 Keychain 交互，定时点火禁止弹窗。
- Command Code 卡片高度为 176 pt，四卡详情页为 440 × 566 pt；设置页为 520 × 700 pt，只有一个滚动区。

### Command Code 辅助缓存

- summary 与 subscription 的缓存按 API Key 完整 SHA-256 摘要隔离，分别保存值、成功时间与重试状态；公开账号标签仍是短指纹，缓存不保存原始 Key。
- credits 每轮必读并独立决定连接状态；两个辅助组件分别在 15 分钟内复用、分别过期、分别失败重试。
- 单路失败保留旧值并标记缓存，不推进成功时间。手动刷新与重连 force 两路；同代 force 到达自动读取时等待后补全量，不同凭证代次不合并，旧代结果由 generation gate 拒绝。
- 新增可选 Codable `ProviderUsageComponentFreshness`；旧缓存无需迁移即可解码。
- UI 仅对真实使用到缓存辅助字段的套餐、统计、月度额度/周期行显示橙色缓存语义；5 小时与周额度保持本次 credits 的实时状态。

### 唤醒与节奏

- `probeRateLimitsAfterWake` 只使用现有运行 client 做 handshake + rate limits，不读身份、不调用 factory、不启动或重启子进程。
- 探活成功更新该 Profile；失败关闭失效 client 并只让该 Profile 进入普通刷新；failure episode、读取中和停止态返回 suppressed。
- A/B 并行探活、逐个发布；唤醒与定时轮询保持 30 秒互斥，停止路径取消任务和 timer，并等待两个服务 drain。
- 详情页 tick 为 30 秒；ChatGPT 轮询为临近重置 30 秒、无数据/注入基础间隔默认 60 秒、远离 120 秒；菜单栏宽度只在尺寸签名变化时重测。

### R2 与版本收尾

- AX XCTest 每轮只遍历新窗口并在结束后关闭；XCTest 无 AX 窗口时明确跳过。
- About、Header、设置页开发态版本 fallback 均为 1.3.2。
- `REQUIREMENTS`、任务、审核、验收、发布说明、README、CHANGELOG、ROADMAP、端点和架构说明已按实测同步。

## 2. 关键回归

- 点火：live/stale/unavailable 前值、首次提前结束、两次无证据、59/60 秒、差值格式、A/B 隔离、最近 3 条历史。
- 计划与 Command Code 点火：三目标、多时点、勾选、持久化去重、10 分钟补跑、跨午夜间隔；CLI 参数、环境隔离、输出丢弃、超时/stop 回收、缺 Key、手动/定时 Keychain 策略、credits-only 确认与差值。
- Command Code：同凭证复用、跨凭证隔离、组件分别过期、部分失败与旧值回退、force/in-flight、凭证代次、组件新鲜度、旧缓存解码、系统时钟回拨。
- 唤醒：健康 Profile 只读额度、失败 Profile 才完整刷新、failure episode 与 stop 抑制、30 秒节流、停止后不发布。
- UI：固定尺寸、结果/差值组合、缓存套餐/统计/月度行、浅色/深色 fixture。

## 3. 验证证据

| 验证 | 结果 |
| --- | --- |
| Core 全量 | 360 项通过，0 失败 |
| App 全量 | 146 项执行，145 通过、1 项 AX XCTest 跳过、0 失败 |
| 合计 | 506 项执行，505 通过、1 跳过、0 失败 |
| 独立 AX harness | `AXLink:前往设置`、`AXLink:查看设置`、`AXStaticText:Command Code`；两次 `AXPress` 各触发 1 次 |
| 脱敏渲染 | Command Code 组件缓存、点火 footer、OpenAI 点火三态和多时点设置均输出浅色/深色 fixture；新尺寸目检无截断 |
| 隔离 Release | `/tmp/minget-132-release-run/Minget.app`，版本 1.3.2，两个可执行文件均为 arm64 |
| 严格签名 | staging、run、archive 和额外 `codesign --verify --strict --verbose=2` 均通过 |
| 启停清理 | stop/exit 自动回归通过；当前已运行 Minget 进程持有两个 app-server 子进程，父子归属完整、无孤儿。本轮未擅自终止用户正在运行的应用；签名 1.3.2 真实退出仍随用户验收执行 |
| 差异检查 | `git diff --check` 通过，`docs/archive/v1.0/` 无改动，无旧全局 force flag |
| 安全边界 | 应用 HTTP 网络层仍仅允许既有只读端点并阻断模型路径；Command Code 模型请求仅存在于用户授权的官方 CLI 点火路径，且自动测试只用 fake |

构建仍有既有 Security.framework Keychain API 弃用 warning，以及既有 `ProductionWiringTests` 恒真类型检查 warning；均非 1.3.2 新增失败。

## 4. 发布后跟进验证

1. 在真实签名包内目检 440 × 566 详情页、520 × 700 设置页、多条计划、Command Code 点火 footer 与历史 tooltip，无截断、无状态歧义。
2. 触发一次真实睡眠/唤醒，确认 30 秒内恢复、无重复刷新风暴、A/B 无串用、退出后无孤儿 app-server。
3. 执行一次临时设定的 Command Code 定时点火，确认开启 5 小时窗口、无重复请求和无 Keychain 弹窗风暴；手动点火已由用户确认成功。

以上项目由用户明确接受移至发布后验证，不阻断 1.3.2，也不因发布改记为通过。真实 DeepSeek 菜单栏与详情余额核对、A/B 真实点火和完整重启缓存隔离继续保留为待验收项。用户已授权 Command Code 点火功能使用 Keychain Key，并已确认真实手动点火成功；Codex 自动验证未执行任何真实模型请求。

# v1.6.0 当前实施记录：官方 Antigravity CLI

日期：2026-09-30。分支：`codex/minget-google-quota`。保留进入本轮前的所有未提交修改；昨日代理原型的原实施报告保存在 `history/PROXY_IMPLEMENTATION_REPORT_20260929.md`。冻结的 `docs/archive/v1.0/` 未改。

## 结论

P0 未通过，官方 CLI 不接入 Minget 的常驻自动刷新。空账号无终端 `/usage` 仍等待授权码，且 `AGY_CLI_DISABLE_AUTO_UPDATE=1` 下产生脱离原进程组的后台更新进程；详细脱敏证据见 `P0_GATE_RESULT.md`。已有真实双账号额度试验仍有效，但不能代替后台安全和正式应用验收。未恢复 CLIProxyAPI 方案，也未创建自有 OAuth 客户端或发起模型请求。

## 本轮修改

- `Sources/UsageMonitorCore/Providers/AntigravityCLIReport.swift`：保留原解析器，新增非空会话 ID 的拒绝条件。真实零、未知字段、精确比例和周期仍按官方结构化字段处理。
- `Sources/UsageMonitorCore/Services/AntigravityCLIProcess.swift`：新增**未接入生产实例**的固定 `/usage` 进程封装。绝对可执行文件、独立 `HOME` 和 appdata、空工作目录、独立 stdout/stderr、各 1 MiB 上限、全程超时、取消、自有进程组回收、退出码和报告检查。不输出认证诊断或原始结果。由于官方 updater 可脱离进程组，此封装本身不满足 P0。
- `Tests/UsageMonitorCoreTests/AntigravityCLIReportTests.swift`、`AntigravityCLIProcessTests.swift`：覆盖固定参数、隔离环境、合法结构、非零退出、输出上限、超时、取消、缺失目录、非零会话 ID、重复组及超大报告。合成数据仅检验程序行为。
- `docs/versions/1.6.0/` 及根目录资料：区分今日官方 CLI 路线、P0 阻断和昨日代理原型；当前审核、验收与来源状态以本轮证据更新。

## 执行与验证

| 项 | 结果 |
| --- | --- |
| `swift test --scratch-path /tmp/minget-google-build --disable-sandbox --filter AntigravityCLIReportTests` | 5 项通过，0 失败 |
| `swift test --scratch-path /tmp/minget-google-build --disable-sandbox --filter AntigravityCLIProcessTests` | 5 项通过，0 失败 |
| `swift test --scratch-path /tmp/minget-google-build --disable-sandbox` | Core 419 项通过；App 172 项执行，1 项既有 AX 环境测试跳过、0 失败。日志：`/tmp/minget-google-full-test.log`。 |
| 隔离候选构建 | `scripts/build.sh` Release arm64，`Minget Local Signing`；staging、run、archive 严格签名检查通过。日志：`/tmp/minget-google-candidate-build.log`。候选：`/tmp/minget-google-candidate/archive/Minget.app`。 |
| 当前安装版备份 | `/Users/<user>/Applications/Minget-backups/Minget-before-official-cli-20260930-210454.app`；`ditto` 后严格签名验证通过，主可执行文件 SHA-256 与原安装版一致。未替换 `/Users/<user>/Applications/Minget.app`。 |

候选仍使用昨日代理 UI 和运行路径，因为 P0 禁止生产切换；签名通过不代表官方 CLI 登录、后台或真实界面验收通过。正式安装、双账号持久 profile、第二台 Mac 和跨机独立性均未完成。

## 后续必需工作

先解决 `P0_GATE_RESULT.md` 的后台等待、更新进程和稳定身份绑定；然后按 `OFFICIAL_CLI_IMPLEMENTATION_PLAN.md` 的 P1–P5 接正式 profile、登录、双账号状态/缓存、界面与迁移，再做真实账号和第二台 Mac 验收。只有正式切换满足门槛后，才使用现有备份进行可恢复的本地替换。未推送远端、未公开发布。

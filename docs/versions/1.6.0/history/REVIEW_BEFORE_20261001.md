# v1.6.0 当前审核：官方 CLI 路线

2026-10-01 复查：[当前状态与阻断点](AUDIT_20261001.md)。后续代码已增加登录试验窗口、profile 与沙箱/认证提示处理；本次相关 39 项测试通过，但正常应用仍走代理。正式账号尚未提交，并发现授权码提交后官方引导无法继续操作的代码缺口。下文 09-30 审核尚未覆盖这些后续修改，不能用其早期失败推定最新方案必然失败。

日期：2026-09-30。状态：**P0 未通过，应用集成和正式替换暂停**。昨日代理原型的审核记录保存在 `history/PROXY_REVIEW_20260929.md`，不作为当前路线验收。

## 独立检查

- 实测官方 Antigravity CLI 1.2.13 的 `--version`、arm64 文件格式和 Google LLC / `EQHXZ8M8AV` 签名主体；既有下载清单核验见 `OFFICIAL_CLI_PROBE.md`。
- 已登录试验环境 A/B 的官方 TUI 各显示不同邮箱；先前 `/usage` 的真实双账号、零轮次/token、重启和并发结果见 `OFFICIAL_CLI_PROBE.md`。本轮没有读取认证文件或原始 token。
- 空 profile、无终端、stdin `/dev/null` 下的固定 `/usage` 仍等待授权码；`--print-timeout 3s` 没有覆盖授权阶段。`AGY_CLI_DISABLE_AUTO_UPDATE=1` 下仍有脱离原进程组的 `--bg-updater`。见 `P0_GATE_RESULT.md`。不能宣布后台无交互或可控进程生命周期。
- 代码差异检查：新增解析器及只读进程封装无任意模型 prompt、Google HTTP 端点或认证文件读取；进程封装没有生产接线。原 `AntigravityModel`、视图和打包文案仍是昨日代理实现，故候选 `.app` **不满足**官方 CLI 产品目标。
- 专项测试 10 项通过；完整 Core 419 项、App 172 项执行，App 1 项既有 AX 环境跳过，0 失败。Release arm64 隔离构建及 `Minget Local Signing` 严格签名通过。当前安装版已备份但未替换，细节见 `IMPLEMENTATION_REPORT.md`。

## 未通过门槛

身份解析在首次引导、提示改版和窄终端尚未验证；正式 profile 登录、条款选择、取消与拒绝未验收；后台无交互和更新控制实测失败；两个正式持久账号、缓存隔离、真实界面、第二台 Mac、授权失效与续期均未验收。合成测试、已登录试验 profile 和签名候选不能替代这些结果。

决定：维持 P0 停止线，不接入自动刷新、不安装候选、不推送、不公开发布。后续从 `OFFICIAL_CLI_IMPLEMENTATION_PLAN.md` 的 P0 未通过项继续。

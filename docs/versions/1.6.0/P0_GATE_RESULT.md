# 1.6.0 官方 CLI P0 门槛实测

日期：2026-09-30，Asia/Shanghai。工作树：`codex/minget-google-quota`。本页只记录官方 CLI 1.2.13 的探测与当前可实施边界；账号邮箱、授权网址、授权码和原始认证输出未保存。

## 环境与命令

- 可执行文件：`/tmp/minget-agy-probe/antigravity`，arm64。`--version` 返回 1.2.13；`codesign` 显示 Developer ID Application: Google LLC、TeamIdentifier `EQHXZ8M8AV`。下载清单 SHA-512 和严格签名的既有核验见 `OFFICIAL_CLI_PROBE.md`。
- 已登录身份：用官方 TUI 的受控 PTY 分别打开既有试验 profile A/B，`HOME` 与 `ANTIGRAVITY_APP_DATA_DIR` 各自隔离，未读取认证文件。A 在 80、120 列下各捕获一个邮箱；B 在 80 列下捕获另一个邮箱，大小写规范化后两者不同。只在内存提取、比较，不输出邮箱。该观察仅证明这些终端宽度下可读，不证明提示改版、首次引导和任意宽度下可靠。
- 空 profile 后台：新建当前用户独占的空 `HOME`、`ANTIGRAVITY_APP_DATA_DIR`、工作目录，stdin 接 `/dev/null`，stdout/stderr 分管道，调用固定 `--log-file /dev/null --print /usage --output-format json --print-timeout 3s`。外层分别等待 12 秒和 7 秒，超时只向自有进程组发信号并回收。第二次加 `CI=1`、`BROWSER=/usr/bin/false`，结果仍相同。

## 结果

| P0 项 | 结果 | 实际证据与边界 |
| --- | --- | --- |
| 官方身份读取 | 部分通过 | 既有已登录 TUI 的 PTY 输出可提取两个不同邮箱；官方没有在已查文档和 `--help` 中提供机器可读身份命令。尚无经首次登录及 UI 改版验证的稳定解析器。 |
| 登录协议与首次引导 | 未通过 | `OFFICIAL_CLI_PROBE.md` 已记录用户在试验环境手动完成浏览器授权及授权码回填；本轮未对正式持久 profile 实测应用驱动的登录、取消、拒绝、条款和可选数据选择。 |
| 后台无交互 | **未通过** | 空账号 JSON 返回 `status=ERROR`、零轮次及零 token，诊断进入 `Authentication required`、显示授权网址并等待授权码，标示 60 秒；`--print-timeout 3s` 未覆盖授权阶段。无终端也没有按[官方 Headless 文档](https://antigravity.google/docs/cli/headless/)所述即时退出。外层总超时有效，但不能作为官方无交互能力的证明。浏览器是否实际弹出未单独验证，`BROWSER` 是否被 CLI 尊重也未证明。 |
| 更新控制与子进程回收 | **未通过** | 设置 `AGY_CLI_DISABLE_AUTO_UPDATE=1` 后，探测仍观察到官方二进制自启并脱离原进程组的 `--bg-updater`。只终止本轮确认产生的 PID，未使用全局 `killall`。该变量不能作为已验证的禁更机制。 |
| 固定查询 | 已通过试验 | 两个既有登录 profile 的内置 `/usage`、零轮次及零 token、真实额度与 TUI 对照见 `OFFICIAL_CLI_PROBE.md`。正式 profile、失效续期与应用运行路径未通过。 |

## 决策与下一门槛

按 `OFFICIAL_CLI_IMPLEMENTATION_PLAN.md` 的 P0 退出条件，身份绑定和后台无交互尚未同时通过。**当前禁止把 Antigravity CLI 接入常驻自动刷新，也不把昨日 CLIProxyAPI 原型作为替代交付。** 已加入未接线的固定只读进程封装及合成测试，供后续在后台行为与更新控制明确后复用。候选 `.app` 仍运行昨日代理实现，只作为编译与签名检查，不用于正式替换。

下一步需要在官方支持或可重复实测的条件下确认：无需授权时能快速报错且不弹浏览器；更新进程可禁用或可靠限制在自有生命周期；正式 profile 的用户可见登录和稳定身份解析。第二台 Mac、授权失效与续期也仍待真实验收。

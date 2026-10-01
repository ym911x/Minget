# 官方 Antigravity CLI 只读额度验证

日期：2026-09-30。用户已允许采用官方 CLI 路径，替代最初的无本机依赖方案。

## 已确认

- 从 Google [官方安装页](https://antigravity.google/docs/cli/install/)所指向的安装脚本和发布清单下载 CLI 1.2.13。下载包 SHA-512 与官方清单一致；`codesign --verify --strict` 通过，签名主体 Google LLC，TeamIdentifier `EQHXZ8M8AV`。
- 可执行文件只放在 `/tmp/minget-agy-probe/antigravity`，未运行安装器或修改 shell 配置。两个试验环境分别使用该目录下 `profile-a`、`profile-b` 作为子进程 HOME，并使用各自的 `appdata`。认证数据全部由官方 CLI 管理，未打开或复制认证文件。
- 账号 A 经官方浏览器 OAuth 登录，真实 TUI 显示 Google AI Pro。用户明确同意首次启用条款；关闭了可选的交互数据收集。
- TUI `/usage` 真实显示 Gemini 共享额度组和 5 小时、周额度。随后退出 CLI，新进程执行以下命令成功，退出码 0，无需再次登录：

  ```sh
  agy --log-file /dev/null --print /usage --output-format json --print-timeout 20s
  ```

- 真实 JSON 的 `status` 为 `SUCCESS`，`command.name` 为 `usage`；`num_turns` 为 0，五个模型 token 计数字段均为 0，`conversation_id` 为空。这是 CLI 内置命令返回，未产生模型对话。
- 数据路径为 `command.data.groups[].buckets[]`。组字段 `name`，桶字段 `id`、`name`、`window`、`remaining_fraction`、`reset_time`。真实返回 `weekly` 和 `5h`，重置为 UTC ISO 8601 时间。
- 账号 A 本次观测：Gemini 周剩余 98.92%、5 小时剩余 98.82%；Claude/GPT 共用组周剩余 97.99%、5 小时剩余 100%。这些是本次观测值，不能当作持续实时额度。
- JSON 的 `response` 文本将比例取整；Minget 解析器只读取 `command.data` 的精确数值。官方按组返回共享额度，不能把组拆成逐模型独立额度。
- A 登录后，B 独立环境仍显示未登录，没有继承 A 的会话。用户随后完成 B 的官方登录，CLI 显示第二个账号的 Google AI Pro 身份；可选交互数据收集同样已关闭。
- 退出 B 的交互进程后，同时启动 A、B 两个新的 JSON 查询进程：两者均退出 0、返回 `SUCCESS`、轮次及五个模型 token 计数全为 0。两账号的周重置时间不同，分别返回自己的额度。
- B 登录后重启 A 的交互进程，官方界面仍显示 A 的邮箱与 Google AI Pro，`/usage` 的 Gemini 99.91% 周剩余、99.75% 五小时剩余与本轮 A 的 JSON 值按两位小数一致。B 的 TUI 与 JSON 对比同样一致（98.96% 周剩余、99.83% 五小时剩余）。证明这两个试验环境在本轮登录、退出重开与并发读取中没有串号。

最新并发查询观测（2026-09-30 11:14 左右，Asia/Shanghai；区别于上文较早一次观测）：

| 账号 | 额度组 | 周剩余 | 五小时剩余 | 周重置 UTC | 五小时重置 UTC |
| --- | --- | --- | --- | --- | --- |
| A | Gemini | 99.91% | 99.75% | 2026-10-06T11:50:18Z | 2026-09-30T06:20:39Z |
| A | Claude/GPT | 97.99% | 100% | 2026-10-06T12:00:59Z | 2026-09-30T08:14:22Z |
| B | Gemini | 98.96% | 99.83% | 2026-10-04T03:51:55Z | 2026-09-30T06:20:57Z |
| B | Claude/GPT | 93.76% | 100% | 2026-10-06T12:24:06Z | 2026-09-30T08:14:25Z |

以上是官方返回的观测值。期间部分比例和重置时间有变化，应用必须以当次返回为准，不从倒计时推算或补满。试验结束后所有自有交互与查询进程正常退出；临时试验目录仅当前用户可访问。未迁移认证文件，也未将临时路径作为正式应用配置。

## 尚未完成

2026-09-30 后续 P0 实测的后台授权等待、更新进程和身份观察见 [P0_GATE_RESULT.md](P0_GATE_RESULT.md)；本页保留先前成功的真实双账号试验记录，不将其提升为应用验收。

- 应用级重复账号检查、断开后旧请求回写和凭证失效处理。两个试验账号并发查询及重启归属已完成；额度 JSON 本身没有账号身份，账号归属必须在登录阶段确认并绑定独立环境，不能从额度数字推断。
- 后台未登录或授权失效时的无界面退出：未登录 `--print /usage` 实测可能打开浏览器并等待授权；`--print-timeout` 不足以覆盖整个登录阶段。集成必须处理固定超时、认证中断与自有进程组回收，不能每五分钟触发交互登录。
- 应用内登录入口、CLI 子进程服务和原代理界面的替换。当前只加入解析器，现有 app 运行路径尚未切换。
- 第二台 Mac、自动续期、断开后隔离和完整签名安装验收。

## 代码与验证

新增 `Sources/UsageMonitorCore/Providers/AntigravityCLIReport.swift`，将官方 CLI 内置命令的 JSON 转为既有额度组模型。拒绝错误状态、非 usage 命令、非零模型轮次/token 与重复桶身份；保留未知与真实零的区别，重置到期不补满。

新增 `Tests/UsageMonitorCoreTests/AntigravityCLIReportTests.swift`，只用合成数据验证解析。执行：

```sh
swift test --scratch-path /tmp/minget-google-build --disable-sandbox --filter AntigravityCLIReportTests
```

结果：4 项通过，0 失败。已有 Keychain 弃用警告未由本轮引入。未运行完整回归、未打包、未安装或公开发布。合成测试不代替上述真实 CLI 证据。

## 与此前直连调查的关系

此前 `DIRECT_GOOGLE_FEASIBILITY.md` 记录的是 Minget 自有 OAuth 客户端直接调用内部 HTTP 端点的调查。将 Google 对第三方访问的条款直接推定为只读额度工具必然被禁止，结论过度；官方没有单独明确这类只读工具的边界。当前技术路线由用户改为调用官方 CLI，自有 OAuth 客户端不再是此验证的前置条件。CLI 验证成功只证明技术可行，不代表 Google 对 Minget 作出了专项许可。

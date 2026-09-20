# 1.3.2 审核状态

状态：Codex 已完成新增点火计划与 Command Code 点火的代码审核和自动发布证据收口，Command Code 真实手动点火已由用户确认成功。用户于 2026-09-20 接受并授权发布；发布提交 `c51791b`、annotated tag `v1.3.2` 和公开 GitHub Release 已完成。真实睡眠/唤醒、完整界面和 Command Code 定时点火明确保留为发布后验证项。

## 审核结论

未发现新增生产代码阻断。应用 HTTP 客户端仍不新增端点且拒绝模型路径；唯一新增模型请求是用户明确授权的官方 Command Code CLI 点火。该路径使用隔离 `HOME`、固定最小参数、丢弃输出，不读全局认证文件或浏览器会话。定时点火只在用户勾选条目后生效。

## 清单

- [x] 差异主体只覆盖 1.3.2 任务、回归与必要文档。
- [x] 非 live 点火前值固定「暂无法确认」；只有 live 前值可判确认/未变化。
- [x] 点火确认只读 rate limits，不读身份、不改归属、不绕开熔断。
- [x] footer 结果、差值和左侧摘要优先级符合方案；三态、60 秒、2 秒/5 秒、历史最多 3 条未变。
- [x] Command Code 辅助缓存以完整摘要隔离，两个组件独立复用/过期/失败重试，旧缓存兼容。
- [x] force 随任务传递；同代补强制读取，凭证代次隔离，旧代结果不提交。
- [x] 缓存套餐、统计和月度字段显示缓存语义，5 小时/周额度保持 credits 实时语义。
- [x] 三个目标均支持每日多时间、每条独立勾选、10 分钟补跑、跨重启去重和小于 5 小时警告。
- [x] Command Code 卡片手动点火、定时点火、credits-only 确认、三态、差值与最近 3 条历史完整连通。
- [x] Command Code CLI 不经 shell，隔离 `HOME`，禁用自动更新/session/skills，只传入必要环境与 Key，输出丢弃，超时/stop 回收自有 PID；每次唯一临时 `HOME` 在结束后删除。
- [x] 官方 CLI 在 `--max-turns 1` 命中上限后返回固定退出码 8；该码表示单轮请求已执行，继续进入 credits 确认，其他非零码仍是失败。
- [x] Finder 启动时即使继承的 `PATH` 只有系统目录，CLI 子进程也会将已定位的 CLI 目录及 Homebrew 目录置于前方，保证 `#!/usr/bin/env node` 能解析 Node；稀疏 PATH 对照回归通过。
- [x] 唤醒只探活现有 client，失败 Profile 才完整刷新；熔断/读取中/停止态不叠加请求。
- [x] 30/60/120 秒节奏、基础间隔注入、30 秒 tick、宽度签名和 stop 清理由测试固定。
- [x] AX XCTest 不再复用旧窗口；独立 GUI harness 真实 AX 树与按压通过。
- [x] 浅色/深色 fixture 覆盖点火三态、长文案/差值和 Command Code 组件缓存，目检通过。
- [x] 菜单栏格式不变；Command Code 卡片、详情页和设置页尺寸已按新功能更新并有布局断言。
- [x] 506 项自动测试执行，505 通过、1 项 AX XCTest 明确跳过、0 失败；脱敏浅色/深色渲染目检通过。
- [x] Release 版本 1.3.2、arm64、staging/install/archive 严格签名通过。
- [x] `git diff --check`、冻结目录、端点/敏感信息、Command Code 临时目录和进程归属检查通过。
- [ ] 发布后：用户真实签名包完整界面验收。
- [ ] 发布后：用户真实睡眠/唤醒验收。
- [x] 用户真实 Command Code 手动点火验收。
- [ ] 发布后：用户真实 Command Code 定时点火验收。

## 唯一自动跳过项

`CommandCodeAccessibilityTests.testTheSettingsEntryKeepsItsOwnElementAndPressAction` 在 XCTest 进程无 AX 窗口时明确跳过，不计为通过。仓库外独立 GUI harness 直接编译当前源码，取得以下真实结果：

```text
PASS entry=AXLink:前往设置
PASS entry=AXLink:查看设置
PASS identity=AXStaticText:Command Code count=2
PASS AXPress counts=1,1
```

## 审核边界

Codex 自动验证没有执行真实点火或模型请求；用户已在 PATH 修复签名包内确认 Command Code 手动点火成功，并于 2026-09-20 明确授权发布。真实睡眠/唤醒、完整界面和 Command Code 定时点火作为发布后验证保留，不改记为通过；真实 DeepSeek 菜单栏、A/B 点火和机器完整重启继续按验收台账保持待验收。

# 明明有数 · Minget 1.3.0

1.3.0 将 ChatGPT（Codex）额度监控扩展为两个相互隔离的账号，并增加可选择的菜单栏来源和每账号手动点火入口。本版本同时完成三轮真实界面修订。

## 本次更新

- 同时监控两个 ChatGPT 账号。每个 Profile 使用独立的 `CODEX_HOME`、`codex app-server`、失败预算和额度缓存。
- 设置页可选择菜单栏显示账号 A、账号 B 或 DeepSeek；ChatGPT 保留双额度与双重置时间条，DeepSeek 使用更醒目的 `DS CNY 123.45` 单行格式。
- 每张 ChatGPT 卡片提供独立的“5 小时点火”入口。应用直接执行官方 Codex CLI 固定参数，丢弃子进程输出，并区分“请求成功”与“新窗口已确认”。
- 详情页改为固定 `440 pt` 单列。两张 ChatGPT 卡片、DeepSeek 单行卡片和 Command Code 三周期卡片可在一页完整显示，无滚动条。
- Command Code 右侧只显示“余额 / 总计”，5 小时与周额度只显示绝对重置时间，月度继续显示剩余天数。
- 修复冷启动空设置窗口、弹层越界、点火子进程退出清理和缓存结果误判为实时确认的问题。

## 验证

- `swift test --scratch-path /tmp/minget-revision-scratch`：Core 325 项、App 100 项，共 425 项通过，0 项失败。
- Release 构建、版本检查、staging 与固定运行路径严格签名验证通过。
- 签名包冷启动无空窗口，退出后无自有子进程残留。
- 用户真实截图确认 440 pt 详情页、两个 ChatGPT 账号、DeepSeek 单行卡片和 Command Code 三周期信息完整显示。

![Minget 1.3.0 详情页脱敏示例](https://raw.githubusercontent.com/ym911x/Minget/v1.3.0/assets/screenshots/v1.3.0/detail-redacted.png)

截图中的邮箱、余额、额度、重置时间和用量均为示例数据。真实 DeepSeek 菜单栏余额与 A/B 两次真实点火未在本轮执行。

当前发布继续提供源码构建说明，不附带未经 Apple Developer ID 公证的安装包。

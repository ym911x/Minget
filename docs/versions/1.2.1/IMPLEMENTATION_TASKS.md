# 1.2.1 实施任务

| 项目 | 状态 | 依据 |
| --- | --- | --- |
| Command Code 美元金额两位小数格式化 | 已实现 | `UsageFormatting.usdAmount` 与单元测试 |
| 移除卡片内相对更新时间 | 已实现 | `CommandCodeOverviewCard` 不再渲染 `ProviderUpdatedFooter` |
| 收紧 Command Code 可见时的详情高度 | 已实现 | 510/610 点布局断言 |
| 自动化测试 | 已通过 | 2026-09-15 `swift test`：310 项通过，0 项失败 |
| Release 构建与签名 | 已通过 | 2026-09-15 `./scripts/build.sh`：1.2.1 构建和严格签名验证通过 |
| 真实界面 | 已通过 | 用户截图确认金额两位小数、底部更新时间已移除且内容完整 |

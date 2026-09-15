# 1.1.2 实施任务

## Core 数据链路

- 新增规范化 `RateLimitResetCredits`，只保留 `availableCount` 和最近未来到期时间。
- 扩展 `UsageSnapshot` 与可选持久化字段，保持 1.1.1 旧缓存可解码。
- 在 `UsageParser` 解析 `rateLimitResetCredits`，拒绝负数、分数、布尔值和非法结构；`availableCount` 对明细数组具有权威性。
- 增加只读格式化函数，区分 live、cached、缺失和过期状态。

## 菜单栏

- 移除 `MenuBarSpaceMode.icon` 的生产和测试路径。
- `full` 压缩后只降为 `compact`；紧凑模式保持两种额度和两排时间条。
- 调整紧凑初始 fallback 宽度，确保首次测量前也不会裁切双额度标题。

## 详情页

- OpenAI 额度轨道下增加可用重置摘要。
- DeepSeek 将真实余额与顶部品牌同列右对齐并垂直居中，状态继续位于 Logo 下方，不预留虚构账号位置。
- 移除详情页纵向滚动容器，按内容状态提高固定窗口高度，使整页直接可见。
- 保持现有多币种金额、设置入口、状态页入口、缓存状态和深浅色行为。

## 文档与验证

- 更新 `VERSION`、`CHANGELOG.md`、`README.md`、`ROADMAP.md` 和 `PROVIDER_ENDPOINTS.md`。
- 更新版本需求、实施报告、审核和验收台账。
- 执行全量 Swift 测试、Release 构建、签名检查和正常启动后的真实界面检查。

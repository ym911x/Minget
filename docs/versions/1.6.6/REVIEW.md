# 1.6.6 审核

审核对象：分支 `codex/minget-1-6-6` 的工作区改动（`AntigravityViews.swift`、`SharedQuotaViews.swift`、`UsagePanelView.swift`、`DetailPreferences.swift`、五个测试文件、文档与版本号）。检查方式：源码差异逐项核对 + 完整 `swift test` + 示例渲染目视与像素核对 + Release 严格签名构建与安装校验。审核时间 2026-10-10。

## 检查结果

- [x] 其他额度组直接显示：`QuotaPresentation.otherGroups(_:)` 排除主组、保持服务端顺序；`AntigravityOverviewCard` 按该顺序渲染组名标题与两行额度，主组仍只显示两行且不带组名。
- [x] 删除项与用户确认一致：额度行下方「最近成功 hh:mm」整行（含「缓存数据」小字）与「其他额度组」折叠标题都不再渲染；失败提示块保留，未连带删除。
- [x] 折叠状态一并清理：`AntigravityOverviewCard` 不再持有 `expanded` / `localExpanded`，`DetailPreferences.expandedGoogleAccounts` 已删除，`Sources/` 与 `Tests/` 中不再有引用（grep 为空）。
- [x] 配色范围正确：只有覆盖 Claude 与 GPT 模型的那一组使用 `claudeModels`；`QuotaPresentation.color` 委托给 `levels`，ChatGPT 卡、Gemini 主组、概览列与菜单栏行为不变。
- [x] 分级符合确认口径：`claudeModels` 在 ≥20% 为 Claude 橙 `#D97757`，<20% 为红，无效值次要灰；`levels` 三档阈值与颜色未变（测试固定）。
- [x] 时间条未受影响：`ProviderTimeBar` 在这两组里继续使用系统蓝，颜色只随缓存态变淡（0.45），不随用量颜色变化。
- [x] 概览条等长：`.quotas` 图示宽度与双列 `.credits` 同为 224 pt，两列各 106 pt + 12 pt 间距；单列金额行与余额行保持 164 pt。
- [x] 小字让位策略按确认执行：名称保持 15 pt 截断，状态小字 `minimumScaleFactor(0.8)` 先缩字号再截断，全文保留在悬停与无障碍标签；行高 64 pt、行间距与拖动排序几何未变。
- [x] 卡片高度常量随内容更新为 318 pt（两组都显示的实测高度），详情页首选高度、`presentationHeight` 与空状态占位共用同一常量；只有一组时按内容收窄且不低于既有 228 pt 最小值。
- [x] 未新增网络请求类型，未改端点、认证、节流、缓存命名空间与点火路径；`UsageMonitorCore` 无改动，`PROVIDER_ENDPOINTS.md` 无需更新。
- [x] 完整回归 689 项（Core 462 + App 227），5 项既有跳过，0 失败；新增 3 项测试覆盖配色口径、图示宽度与组筛选。
- [x] 渲染证据：Gemini 卡片、Gemini 品牌页、概览页与概览边界行明暗各一张，全部使用合成账号与内存凭证；像素采样确认橙色为 `#D97757`（sRGB 下 217/119/87）。
- [x] Release 严格签名构建通过，安装到 `/Applications/Minget.app` 后版本为 1.6.6，安装前后可执行文件哈希一致，替换前 1.6.5 已备份并校验。

## 结论

代码、自动测试、渲染证据与构建证据齐全，改动范围与用户确认的口径一致；真实界面复验由用户在正式安装的 1.6.6 上进行，结果记入 [ACCEPTANCE.md](ACCEPTANCE.md)。本轮未发布，发布边界见 [ROLLBACK.md](ROLLBACK.md)。

## 发布前独立复核（2026-10-10）

Codex 再次逐项检查工作区差异与关键视图路径，未发现阻断发布的代码问题。正式安装版、四个改动源码与 VERSION 的指纹均与安装记录相同，严格签名复核通过；原 14 项证据清单全通过。通过正式完整路径检查真实界面并执行 Gemini 品牌只读刷新，观察范围与未执行项见 `evidence/records/publication-local-review.txt`。用户已明确授权发布，远端及独立回归结果见 [PUBLICATION.md](PUBLICATION.md)。

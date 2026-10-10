# 1.6.6 实施任务

开发入口：主目录分支 `codex/minget-1-6-6`，起点为干净 `main` 的 `14004e5`（1.6.5 发布台账回写提交）。

1. `QuotaUsageTint`：新增用量着色口径枚举，`levels` 保留现有红绿灯分级（ChatGPT 卡、Gemini 主组、概览继续使用），`claudeModels` 只用 Claude 品牌橙 `#D97757` 与危险红两档。
2. `QuotaPresentation.color(_:)` 委托给 `levels`，保持现有语义与调用点不变；新增 `otherGroups(_:)`（排除主组、保持服务端顺序）与 `tint(for:)`（主组 `levels`，其他组 `claudeModels`）两个纯函数，供视图与测试共用。
3. `QuotaWindowBlock` 增加 `tint` 参数，用量条与「剩余 %」文字都按该口径着色；时间条继续固定蓝色。
4. Gemini 详情卡：删除「最近成功 … / 缓存数据」行与「其他额度组」折叠控件，改为按顺序直接渲染其他额度组（组名标题 + 该组额度行），主组传 `levels`、其他组传 `claudeModels`；失败提示块保留。
5. 移除折叠状态：卡片去掉 `expanded` / 本地兜底状态，`DetailPreferences.expandedGoogleAccounts` 与详情页调用点的 binding 一并删除。
6. 卡片高度常量按两组都显示的实测高度（318 pt）更新，并补注释说明算法。
7. 概览：`OverviewUsageSummary.graphicWidth` 的 `.quotas` 分支改为 224 pt（两列各 106 pt，与 Command Code 双列等长），单列金额行与余额行保持 164 pt。
8. 概览行小字让位：状态小字加 `minimumScaleFactor`，先缩字号再截断；名称保持 15 pt 截断规则，行高、拖动排序、列间距不变。
9. 更新与新增自动测试：额度条宽度（`.quotas` 224）、`claudeModels` 着色与无效值兜底、`otherGroups` / `tint(for:)`、移除 `expandedGoogleAccounts` 相关断言；渲染测试帧高按新卡片高度调整。
10. 导出脱敏渲染证据（概览与 Gemini 详情，浅/深色），据此确认两组相邻显示、橙色与红色、条长一致、名称与状态小字的压缩表现。
11. 版本号升到 1.6.6，更新变更记录、版本索引、项目状态与版本目录资料（需求、任务、实施记录、审核、验收、回滚、发布说明、证据）。
12. 运行完整 `swift test` 与 Release 严格签名构建，备份并安装到正式路径，记录回滚指令。

# 1.6.6 实施记录

分支 `codex/minget-1-6-6`，起点 `main@14004e5`。2026-10-10，Asia/Singapore。

## 1. Gemini 详情卡：其他额度组直显，删掉两行占位

改动文件：

| 文件 | 内容 |
| --- | --- |
| `Sources/UsageMonitorApp/Views/AntigravityViews.swift` | `AntigravityOverviewCard` 删除「最近成功 … / 缓存数据」整行与 `DisclosureGroup("其他额度组")`，改为 `ForEach(QuotaPresentation.otherGroups(groups))` 直接渲染：组名标题（13 pt 半粗）+ 该组 `5 小时` / `周额度` 两行；去掉 `expanded` / `localExpanded` / `expansion` 折叠状态；`quotaRows(_:tint:)` 增加配色参数；卡片高度常量 264 → 318 |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | `AntigravityOverviewCard` 调用点去掉折叠 binding，改为 `AntigravityOverviewCard(state:displayName:)` |
| `Sources/UsageMonitorApp/ViewModels/DetailPreferences.swift` | 删除仅内存态的 `expandedGoogleAccounts`（无持久化键，删除不影响本机数据） |
| `Sources/UsageMonitorApp/Views/SharedQuotaViews.swift` | `QuotaPresentation` 新增 `otherGroups(_:)`（排除主组、保持服务端顺序）与 `tint(for:)`（主组 `levels`，其他组 `claudeModels`） |

- 主额度组 `Gemini Models` 继续只显示两行、不带组名；其他组按服务端顺序跟在后面，组与组之间、组内行之间沿用卡片既有的 12 pt 间距，不再需要「展开」动作。
- 失败提示块保留（只在失败时出现，区域不可用仍带官方说明链接）。
- 「最近成功 hh:mm」不再显示：快照的缓存与新鲜度继续由标题栏右侧状态文字表达（`statusText` 在缓存时为橙色「缓存 · 上次额度」），此取舍记入验收台账。
- 高度常量按两张组都显示时的实测高度：16 pt 上下内边距 ×2 + 50 pt 页头 + 主组两行 40 + 40 + 其他组 [16 组名 + 40 + 40] + 外层 12 pt ×3 + 其他组内 12 pt ×2 = 318 pt。常量同时用于详情页首选高度、`presentationHeight` 与空状态占位；只有一组时卡片按内容收窄，最小高度仍是既有的 228 pt。

## 2. Claude 橙：只作用于覆盖 Claude 与 GPT 模型的额度池

改动文件：`Sources/UsageMonitorApp/Views/SharedQuotaViews.swift`。

- 新增 `QuotaUsageTint`：`levels` 保留 1.0 以来的红绿灯分级（>50% 绿、20–50% 橙、<20% 红），`claudeModels` 为 Claude 橙 `#D97757`（`Color(red: 217/255, green: 119/255, blue: 87/255)`）与危险红两档：剩余 ≥20% 为 Claude 橙，<20% 为红，无效值仍为次要灰。
- `QuotaPresentation.color(_:)` 改为委托 `QuotaUsageTint.levels.color(_:)`，语义与所有既有调用点（ChatGPT 卡、Gemini 主组、概览列）不变；`QuotaWindowBlock` 增加 `tint` 参数，用量条与「剩余 %」文字使用同一颜色，重置时间条继续固定系统蓝。
- 概览、菜单栏、Command Code 紫色与 DeepSeek 余额文字均未改动。

## 3. 概览：额度图示与 Command Code 等长，小字先让位

改动文件：`Sources/UsageMonitorApp/Views/SharedQuotaViews.swift`、`Sources/UsageMonitorApp/Views/UsagePanelView.swift`。

- `OverviewUsageSummary.graphicWidth`：`.quotas`（ChatGPT 与 Gemini 的两列 5H/周）由 164 pt 改为 224 pt，两列各 106 pt + 12 pt 间距，与 Command Code 的 5H + 月额度双列完全等长；`.credits` 单列与 `.balances` 保持 164 pt。
- 示意宽度变化：行宽 408 pt 减去固定区（左右内边距 24 + 标志 28 + 3 处 10 pt 间距 + 箭头 10）= 292 pt，名称列由约 152 pt 变为约 92 pt。
- 名称保持 15 pt 并在过长时截断（悬停与无障碍标签仍含全文）；标题下方 11 pt 状态小字加 `minimumScaleFactor(0.8)`，先缩小字号，仍放不下时截断。行高 64 pt、拖动排序、两列间距与轨道高度（4 pt / 3 pt）不变。

## 4. 执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `swift build --build-tests --scratch-path <本机临时目录>` | 退出码 0（仅有既有警告：测试中的 `var now` 未再赋值、`is` 恒真断言） |
| `swift test --scratch-path <本机临时目录>` | 689 项（Core 462 + App 227），684 通过、5 项既有跳过、0 失败，退出码 0；日志 `evidence/logs/swift-tests.log` |
| `MINGET_RELEASE_SCREENSHOTS=… MINGET_OVERVIEW_EVIDENCE=… swift test --filter "ReleaseScreenshotTests\|OverviewPresentationTests"` | 导出 Gemini 双账号卡片、Gemini 品牌页、概览页与概览边界行（明暗各一张） |
| `scripts/build.sh`（Release，暂存与归档在本机临时目录） | 退出码 0，`Minget Local Signing` 签名，staging / 安装 / 归档三处严格校验通过；日志 `evidence/logs/release-build-staging.log` |
| 备份并替换 `/Applications/Minget.app` | 旧 1.6.5 已备份并校验（哈希与替换前一致）；新版 1.6.6 严格校验通过，安装前后可执行文件哈希一致；`evidence/records/local-install.txt` |

## 5. 新增与更新的自动测试

- `Tests/UsageMonitorAppTests/OverviewPresentationTests.swift`（新增 3 项）：`testClaudeModelPoolUsesClaudeOrangeAndOnlyTheCriticalBand`（100/50.01/50/20 → Claude 橙，19.99/0 → 红，NaN/∞/−1/101 → 次要灰，并复核 `levels` 三档未变）、`testTwoColumnQuotaGraphicMatchesTheTwoCreditWidth`（`.codex` 与 `.gemini` 两列图示为 224）、`testOtherGroupsExcludeThePrimaryPoolAndKeepTheReportedOrder`（主组不重复、顺序保持、配色选择）。
- `Tests/UsageMonitorAppTests/Interface161Tests.swift`、`Tests/UsageMonitorAppTests/StatusItemWiringTests.swift`：移除 `expandedGoogleAccounts` 相关断言与状态恢复；弹层宿主与框架稳定性测试改名为 `testVisiblePopoverKeepsHostAndFrameAcrossNavigation`，仍覆盖品牌切换不移动浮窗。
- `Tests/UsageMonitorAppTests/AntigravityModelTests.swift`：Google 卡片渲染帧高 310 → 380（卡片变高，避免裁切）。
- `Tests/UsageMonitorAppTests/ReleaseScreenshotTests.swift`：Google 双账号导出帧高 646 → 780（两张 318 pt 卡片）。

## 6. 已知问题与未完成事项

- 名称列压到约 92 pt 后，长账号名会截断（悬停与无障碍文本保留全文），状态小字先缩字号再截断；这与 1.6.5 概览 Command Code 双列行的既有行为一致（当时已记录为 1.6.2 既定行为）。示例渲染确认「cn189」「911x」这类短名称完整显示。
- 删除「最近成功 hh:mm」后，快照时间不再有独立行；缓存状态仍由标题栏状态文字表达。若后续需要精确到分钟的取数时间，需要在标题栏或悬停中另行恢复。
- 真实界面复验由用户在安装版 1.6.6 上进行，状态见 [ACCEPTANCE.md](ACCEPTANCE.md)；本轮未做发布。
- 发布审核已修正根 `README.md` 的「当前版本」遗留 1.6.3 及本记录的高度公式；应用源码未因审核改变。开发阶段记录以上述命令与原证据为准，发布审核追加见 `PUBLICATION.md`。

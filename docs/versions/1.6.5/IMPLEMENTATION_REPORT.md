# 1.6.5 实施记录

分支 `codex/minget-1-6-5`，起点 `main@97e6bc3`。2026-10-09/10，Asia/Shanghai。

## 1. 概览 Command Code 行改为 5H + 月额度

改动文件：

| 文件 | 内容 |
| --- | --- |
| `Sources/UsageMonitorApp/Views/SharedQuotaViews.swift` | 新增 `OverviewCreditWindow`（金额口径的概览列：短标签 5H/周/月、`$余额 / $总计`、紫色额度轨、靛蓝时间轨、月度用计费周期起止）；`OverviewUsageSummary.credits` 由单窗口改为 `fiveHour + second`；新增 `commandCode(_ usage:)` 构造器与 `graphicWidth`；新增 `OverviewCreditGraphic` |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 概览行两处构造点（托管账号与旧单连接路径）改用 `.commandCode(report.usage)`；`CommandCodeCardPresentation.timeText` 拆出 `billingPeriodEnd` 重载，概览与详情共用同一时间文案规则 |

选择规则（纯函数，随测试固定）：

1. 第一列恒为 5 小时窗口。
2. 第二列优先月度窗口，条件是服务端确实返回了月度剩余（`billingPeriod.effectiveRemaining != nil`）。
3. 月度剩余不可用时退回周窗口；两者都没有时保持单列，不画空框、不补零。
4. 月度列沿用详情卡的缓存口径：`summaryFreshness` 或 `subscriptionFreshness` 为缓存时该列标橙，5 小时列仍按行级缓存显示。

宽度：单列仍是 164 pt（1.6.2 规格不变），双列 224 pt（两列各 106 pt + 12 pt 间距），名称列随之压缩到约 92 pt，长名称与长状态继续截断并保留悬停全文。示例渲染中的 13~15 字符金额文本在 11 pt 下不截断（见 evidence/screenshots）。

## 2. 各品牌详情页单独刷新

改动文件：

| 文件 | 内容 |
| --- | --- |
| `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift` | 新增 `refreshBrand(_:)`、`isRefreshing(brand:)`、`isAnyRefreshInFlight`、`hasRefreshableAccounts(brand:)`，以及按平台分派的 `refreshBrandPlatform` / `isPlatformRefreshing` |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 服务标签行右侧新增品牌刷新按钮；页头全局刷新沿用 `model.isAnyRefreshInFlight` |

分派规则（全部走手动/强制路径，与 `refreshNow()` 同级）：

- ChatGPT → 既有的 Profile 刷新周期（`resetFailureBudget: true`），只读两个 ChatGPT Profile；已在刷新时按既有语义排队一次。
- Gemini → `google.refresh(force: true)`，只读本机 Google/Antigravity 连接。
- DeepSeek → 该平台每个连接 `refreshManagedAPI(force: true)`（旧单连接模式为 `refreshProvider(.deepseek, force: true)`），并强制刷新该页的公开服务状态。
- Command Code → 该平台每个连接 `refreshManagedAPI(force: true)`；`force` 会把 `credits`、`summary`、`subscriptions` 三路一起强读。

按钮：`bordered` + `small`，24 pt 高，图标 + 「刷新」，刷新中换成小进度指示并禁用；只在品牌标签且该品牌有可读账号时出现，「概览」标签不出现（页头全局刷新不变）。品牌是否有账号由 `hasRefreshableAccounts` 判断：托管模式看该平台未移除的账号，旧模式看引擎 reader 的内存凭证状态（确认缺失时不显示）。

## 3. 执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `swift build --scratch-path <本机临时目录>` | 退出码 0 |
| `swift test --scratch-path <本机临时目录>` | 686 项（Core 462 + App 224），5 项既有跳过，0 失败，退出码 0；日志 `evidence/logs/swift-tests.log` |
| `MINGET_OVERVIEW_EVIDENCE=… swift test --filter OverviewPresentationTests/testExportOverviewExamples` | 导出概览明暗各 2 张（含双列与单列兜底边界） |
| `MINGET_BRAND_REFRESH_EVIDENCE=… swift test --filter BrandRefreshTests/testExportBrandRefreshEvidence` | 导出三个品牌页明暗各 2 张，以及 Command Code 刷新中的 2 张 |
| `scripts/build.sh`（Release，暂存与归档在本机临时目录） | 退出码 0，`Minget Local Signing` 签名，staging/安装/归档三处严格校验通过；日志 `evidence/logs/release-build-staging.log` |
| 备份并替换 `/Applications/Minget.app` | 旧 1.6.4 已备份并严格校验；新版 1.6.5 严格校验通过，安装前后可执行文件哈希一致；`evidence/records/local-install.txt` |

## 4. 新增与更新的自动测试

- `Tests/UsageMonitorAppTests/OverviewPresentationTests.swift`：更新 `.credits` 相关断言；新增 `testCommandCodeOverviewPrefersMonthlyThenWeeklyAndNeverInventsOne`（月度优先、周兜底、月度剩余缺失退回周、只用 5H 时单列、缓存只标月度列、宽度切换、文案包含两列）；示例渲染增加双列行与两个边界行，并把边界图高度放宽以容纳 7 行。
- `Tests/UsageMonitorAppTests/BrandRefreshTests.swift`（新增，6 项）：旧单连接模式下 DeepSeek 刷新不读 Command Code、Command Code 刷新不读 DeepSeek；ChatGPT 品牌刷新同时读两个 Profile 且不读任何 Provider；托管模式下 Command Code 刷新不触发 DeepSeek 请求、反向同理；无账号的品牌不提供按钮；品牌刷新证据导出。

## 5. 已知问题与未完成事项

- 概览 Command Code 行双列后名称列约 92 pt：长名称与长状态会截断（悬停可见全文），这是 1.6.2 既定行为，不是新缺陷；四个新增/边界渲染图已逐一目视核对。
- 月度上限由「本月已用（summary）+ 月度剩余（credits）」相加得到，字段语义仍为 C 级；本轮未与 Command Code Studio 同刻对账，界面继续显示服务端原值，缺失显示 `—`。
- 真实界面对用户复验完成（2026-10-10）：概览 Command Code 双列与四个品牌页的单独刷新均无问题；VoiceOver 现场朗读与 Command Code Studio 同刻对账仍未执行，见 [ACCEPTANCE.md](ACCEPTANCE.md)。
- 实施阶段未做发布；2026-10-10 用户授权发布核对，后续记录见 [PUBLICATION.md](PUBLICATION.md)。

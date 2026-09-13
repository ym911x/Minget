# 明明有数 · Minget v1.1.0 验收台账

更新时间：2026-09-13。自动测试和构建已完成，用户已确认当前详情页体验；边界窗口交互、异常视觉矩阵和本轮真实服务取数仍待执行。生成参考图仅作为设计基准，不作为运行验收证据。

| 编号 | 验收项 | 状态 | 证据 |
| --- | --- | --- | --- |
| A01 | 详情卡片布局、邮箱归属、顶部刷新与齿轮 | 代码完成，用户已确认当前界面 | `UsagePanelView.swift`、`StatusItemController.swift`、用户 2026-09-13 确认 |
| A01a | 放大的 Blossom 图标和 API 套餐类型 | 资源随构建包验证；用户已确认当前图标视觉 | `CodexAccount.displayPlanType`、构建包 `Contents/Resources` |
| A02 | 四轨道等长且两端对齐、额度“剩余”文案 | 代码完成，真实测量待验证 | `CodexQuotaGrid` 统一三列布局 |
| A03 | 蓝色 5/7 段、部分填充、绝对重置点、到期/未知 | 自动测试与代码完成，真实截图待验证 | `ResetTimeModel`、`UsageFormattingTests` |
| A04 | Decimal 金额、两位概览、字段标签、多币种/小额 | 已验证（自动测试） | `ProviderModelsTests.testOverviewBalanceUsesFieldSemanticsAndCNYSymbol` |
| A05 | 两项显示开关、重启持久化、DeepSeek/GLM 各自整行、零卡片布局 | 持久化已验证，真实布局待验证 | `DetailPreferencesTests`、`UsagePanelView.providerCards` |
| A06 | 精简设置仅包含范围内项目且默认无滚动条 | 代码复核通过，用户已确认当前设置页 | `MingetSettingsView.swift`、`SettingsWindowController` |
| A07 | 连接管理、授权、删除、登录及失败反馈 | 既有路径复用，真实回归待验证 | `DeepSeekSettingsView`、`GLMSettingsView`、现有测试 |
| A08 | 显示开关无凭证副作用、窗口共用服务 | 代码复核通过 | `DetailPreferences`、`StatusItemController` |
| A09 | 缓存、局部失败与顶部新鲜度真实 | 逻辑已接入，真实状态待验证 | `UsagePanelView.updateStatusText` |
| A10 | 外部点击、Esc、20 次开关、设置和登录窗口焦点 | 待真实交互 | CUA 只短暂返回 accessibility snapshot，后续截图/滚动调用无窗口 |
| A11 | 菜单栏回归、唤醒、签名和稳定授权 | 构建/签名已验证，菜单栏和授权待验证 | `build.sh` 输出；真实 UI 未完成 |
| A12 | 浅深色、长文本、缩放、屏幕边界真实截图 | 待真实视觉 | CUA 截图调用超时，不能用生成图替代 |
| A13 | 自动测试、构建、版本与安全边界检查 | 已验证 | 371 项测试、1.1.0 构建、`git diff --check` |
| A14 | Codex 独立审核与用户最终体验确认 | 已完成 | `REVIEW.md`、用户 2026-09-13 发布确认 |
| A15 | DeepSeek 官方状态页整体状态摘要、状态页入口、失败不伪造 | 自动测试完成；CUA 文本确认“服务正常”和入口，真实网络持续性/视觉待验证 | `DeepSeekStatusProviderTests`、`DeepSeekStatusProvider.swift` |
| A16 | OpenAI/DeepSeek 双标识资源已进入 app bundle | 已验证六份 Provider PNG 和两份 SVG；用户已确认当前视觉 | `/Users/yuyimeng/Applications/Minget.app/Contents/Resources/*`、`scripts/build.sh` |
| A17 | DeepSeek 透明 `deepseek` 文字标识、金额/状态层级、去除底部留白 | 已完成，用户已确认当前界面 | `UsagePanelView.swift`、构建包资源 |
| A18 | 系统语言产品名、版本号、弹层中心锚点与外观 | 代码与语言选择测试完成，用户已确认当前界面 | `UsagePanelView.swift`、`StatusItemController.swift`、`DetailPanelLayoutTests.swift` |

## 自动化与候选包记录

| 项目 | 实际结果 |
| --- | --- |
| `swift test` | 371 项通过，0 项失败，0 项跳过 |
| `./scripts/build.sh` | Release 构建成功；staging 与 `/Users/yuyimeng/Applications/Minget.app` 严格校验通过 |
| `plutil -lint` | 通过，Info.plist 有效 |
| `CFBundleShortVersionString` | `1.1.0` |
| 签名身份 | `Minget Local Signing` |
| `dist/Minget.app` | 普通签名校验通过；iCloud 文件提供方属性使严格校验仍由构建脚本标注为归档副本限制 |

每项验收分别记录自动化、夹具、真实服务或用户实测证据，不能互相替代。当前详情页体验已经用户确认；A10 至 A12 中尚未覆盖的边界场景继续保留，不把发布动作视为这些场景已通过。

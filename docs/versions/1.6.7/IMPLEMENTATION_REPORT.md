# 1.6.7 实施记录

分支 `codex/minget-1-6-7`，起点 `main@1592f46`。2026-10-13，Asia/Shanghai。本轮只改设置窗口的视觉与信息层级，功能、开关语义、持久化键、取数、节流、缓存、凭证与点火路径均未改动。

## 1. 设置窗口的样式常量与分组说明

改动文件：`Sources/UsageMonitorApp/Views/MingetSettingsView.swift`

- 新增 `SettingsStyle`：页面标题 20 pt、页面留白 22 pt、页头上下留白 22/14 pt、说明字号 11 pt、侧栏方块 22 pt（圆角 6、字形 12）。此前散落在文件里的 11/12/13 pt 与 18 pt 标题统一收敛到这里。
- `SettingsSection` 增加 `subtitle`（每个分组一句说明，互不重复）与 `tint`（系统语义色：蓝=账号、靛蓝=菜单栏、青=详情显示、橙=刷新与点火、灰=关于与诊断）。`SettingsNavigation.swift` 未改，仍只保存标题与符号，保持 UI 无关。
- 新增 `SettingsSectionRow`（侧栏行）：彩色圆角方块 + 白色 SF Symbol + 分组名；选中态沿用 `List(selection:)` 原生高亮，方块保持彩色；图标对辅助功能隐藏，行保留标题标签。
- 统一页头 `paneHeader`：唯一标题 + 一行说明 + 可选尾部主操作（账号页的「添加账号」）；账号页的瞬时反馈（`model.accountMessage`）显示在页头说明下方，不再挤进分组卡片。

## 2. 各分组的排印与层级

| 分组 | 改动 |
| --- | --- |
| 菜单栏 | 删除分组内重复的「菜单栏显示」小标题；独立性说明移入分组 footer；币种行改用 `LabeledContent`（两列对齐），Google 额度说明保持一行 11 pt 次要文字 |
| 详情显示 | 原「说明独占一张卡片」的第二个 Section 取消，说明并入 `Section("可见服务")` 的 footer |
| 刷新与点火 | 低额度阈值行改用 `LabeledContent`，读数在前、步进器在后（`thresholdRow`）；错误提示保持红色并归位到同一列；点火计划以 `Section("5 小时点火计划")` 作分组标题，删除 `FireScheduleSettingsView` 内部重复标题与说明（说明并入 footer）；计划行的开关与日期选择补 `accessibilityLabel`；删除计划行之间多余的手工分隔线 |
| 关于与诊断 | 版本行改为 `LabeledContent` + `monospacedDigit`；「入口」独立成组；诊断分组补 footer 说明（只记录访问类别与结果，不含 Key 内容、请求或用户文本）；品牌语作为该页 footer |

## 3. 账号页与弹窗

改动文件：`Sources/UsageMonitorApp/Views/ManagedAccountManagementView.swift`、`Sources/UsageMonitorApp/Views/AccountManagementView.swift`

- 托管账号页删除自绘的标题/说明/「添加账号」块，页体只保留分组表单；标题与主操作上移到页头，`firstRun` 文案留在表单内。
- 账户行沿用 `AccountManagementRow`（服务图标 28 pt、名称 15 pt 半粗、身份与状态 11 pt 次要、尾部动作右对齐、最小高度 64 pt），行之间由分组表单给出分隔线；**不在分组卡片内再嵌卡片**。
- 每个平台分组保留「添加 <平台> 账号」行；旧路径（无账号注册表）的首个分组标题由 `.headline` 统一为 13 pt 半粗 + 11 pt 说明。

## 4. 版本号回退修正（连带）

`MingetSettingsView` 与 `UsagePanelView` 原来在缺少应用 Info.plist 时回退成硬编码的 `1.6.1`。本轮改为：设置页显示 `—`，概览页头在同样情况下不再显示版本标签（`appVersion(bundle:)` 返回 nil）。正式 App 的版本仍来自自己的 Info.plist，界面表现不变；渲染证据里不再出现错误的版本号。

## 5. 执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `swift build --build-tests --scratch-path <本机临时目录>` | 退出码 0，无新增警告 |
| `swift test --scratch-path <本机临时目录>` | 694 项（Core 462 + App 232），689 通过、5 项既有跳过、0 失败，退出码 0；日志 `evidence/logs/swift-tests.log` |
| `MINGET_EVIDENCE_DIR=… swift test --filter "…/testRenderSettingsPanesLightAndDark"` | 导出五个分组明暗各一张与侧栏图标两张 |
| `MINGET_EVIDENCE_DIR=… swift test --filter ManagedAccountEvidenceTests` | 导出托管账号页与添加账号弹窗明暗各一张 |
| `scripts/build.sh`（Release，暂存与归档在本机临时目录） | 退出码 0，`Minget Local Signing` 签名，staging / 安装 / 归档三处严格校验通过；日志 `evidence/logs/release-build-staging.log` |
| 备份并替换 `/Applications/Minget.app` | 旧 1.6.6 已备份并校验（哈希与替换前一致）；新版 1.6.7 严格校验通过，安装前后可执行文件哈希一致；`evidence/records/local-install.txt` |

## 6. 新增与更新的自动测试

- `Tests/UsageMonitorAppTests/SettingsAppearanceTests.swift`（新增 4 项）：每个分组都有非空且互不重复的 `subtitle`；每个分组的 SF Symbol 在本机可解析且五个分组的 `tint` 互不相同；侧栏方块圆角小于半径、字形小于方块、标题字号大于说明字号；缺少应用元数据时设置页版本为 `—`、概览页头版本为 nil。
- `Tests/UsageMonitorAppTests/DetailEvidenceRenderTests.swift`：新增 `testRenderSettingsPanesLightAndDark`（五个分组明暗导出 + 侧栏图标导出）；`makeModel` 为 `FireSchedulePreferences` 注入隔离 UserDefaults，修掉此前证据测试把点火计划写进测试进程标准偏好的问题（旧测试因此会在多次运行后累积计划行）。

## 7. 已知问题与未完成事项

- 离屏 host 不绘制 `NavigationSplitView` 侧栏，窗口级截图左栏为空；这是 1.6.3 起既有的证据限制，本轮以 `settings-sidebar-marks-*.png` 单独留证，真实窗口由用户复验。
- 本轮未做 VoiceOver 现场朗读；新增/调整的控件已补辅助功能名称，但现场朗读未执行，不记通过。
- 真实界面观感由用户在正式安装的 1.6.7 上复验，状态见 [ACCEPTANCE.md](ACCEPTANCE.md)；本轮未发布。
- 工作区中 `releases/README.md`、`releases/v1.0.0/README.md`、`releases/v1.0.1/README.md` 处于已删除未提交状态，是 1.6.7 开始前既有状态，本轮未触碰。

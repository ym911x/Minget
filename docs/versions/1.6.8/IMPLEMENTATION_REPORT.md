# 1.6.8 实施记录

分支 `codex/minget-1-6-8`，起点 `codex/minget-1-6-7@1a0a172`（1.6.7 提交）。2026-10-16，Asia/Singapore。本轮只改菜单栏的展示口径与固定长度，取数、刷新、缓存、凭证与点火路径均未改动。

## 1. 固定长度

改动文件：`Sources/UsageMonitorApp/Views/MenuBarLabelView.swift`、`Sources/UsageMonitorApp/StatusItem/StatusItemController.swift`

宽度就是「菜单栏能显示的最宽配额文案」——两个 100% 的百分比加两位代号——再留 2 pt 取整余量：

| 组成 | 值 | 说明 |
| --- | --- | --- |
| `textBudget` | 81 pt | `ceil(O1 100% 100% 的实测宽度 79) + 2`；**没有**为异常标记、Gemini 中文回退、不可用文案或 DeepSeek 币种另外加宽 |
| `labelWidth` | 81 pt | 绘制区宽度 |
| `horizontalPadding` | 12 pt | 沿用 |
| `itemWidth` | 93 pt | 实际申请的菜单栏长度（1.6.7 为 123 pt） |

- 长度恒定：文字行与两条时间条都固定在 `textBudget` 内；异常标记与文字共用一行（不再预留前置位），其余超预算文案（Gemini 中文回退、不可用提示）按 `textShrinkFactor = 0.85` 收缩，绝不截断。
- 测量方式改变：不再按内容重新测量。`StatusItemController` 删除了 per-mode 的 `widths` 字典、`labelSignature` 与 `shouldRemeasure` 重测规则，`apply()` 只在安装时执行一次并设置 `statusItem.length = itemWidth`；内容重绘由 `MenuBarLabelView` 自身观察模型完成。

### 1.1 修复过程记录（进度条消失与宽度收窄）

第一版实现把异常标记的 15 pt 前置位**常驻**预留（无标记时用 `Color.clear` 占位）。两个后果都暴露了出来：

1. **两条时间条在真实菜单栏里消失**。`Color.clear` 没有文字基线，而它所在的是 `.firstTextBaseline` 对齐的 HStack：基线偏移被算成该弹性视图的高度，于是文字被下推、时间条被挤出 22 pt 的菜单栏带（离屏渲染用的是宽松尺寸，所以证据图看不出来）。诊断方式：临时测试把真实 `NSStatusItem` 的按钮与「真实宿主尺寸（`itemWidth - padding` × `NSStatusBar.system.thickness`）」下的标签渲染成 PNG 直接目视，确认了文字在、时间条不在。
2. **肉眼可见的空白**：15 pt 常驻预留位（左侧）+ 96 pt 预算相对 79 pt 文字产生的右侧空档，正是用户指出的「数字两边留了很多空位」。

修复：取消常驻预留位，标记与文字同行；宽度改为「最宽配额文案」实测值；并补上 `testRenderInsideTheRealHostFrame` 证据（把状态矩阵放进真实宿主尺寸渲染），这类「被挤掉」的回归以后能被看见。

## 2. 代号

改动文件：`Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`、`Sources/UsageMonitorApp/Views/MingetSettingsView.swift`

- 新增 `menuBarCode(for:) -> String`：`.profile` → `O{ordinal}`、`.google` → `G{ordinal}`、`.deepSeek`/`.apiAccount` → `DS{ordinal}`。
- 序号取账号注册表行的持久化 `ordinal`（稳定，重命名与移除其他账号都不重排）；无注册表的旧模式退化为当前列表位置（这是旧模式唯一的顺序）。
- 菜单栏与设置「菜单栏显示」列表都通过这一个方法解析代号，因此两处不可能不一致；设置列表的每一行是「代号 + 空格 + 原名称」（`O1 Codex 账号`、`G1 cn189 · Google`、`DS1 DeepSeek`），已移除账号的回退行同样带代号。

## 3. 菜单栏内容

改动文件：`Sources/UsageMonitorCore/Utilities/MenuBarContent.swift`、`Sources/UsageMonitorCore/Utilities/UsageFormatting.swift`

- `MenuBarSource` 携带 `code`（`.chatGPT(code:display:connectionState:)`、`.antigravity(code:group:isCached:missingGroup:)`），`MenuBarDeepSeekContent` 增加 `code`。
- 单一文本格式（不再分 full/compact）：
  - ChatGPT：`O1 78% 42%`；无数据 `O1 — —`。
  - Gemini：`G1 80% 90%`（所选额度组的 5 小时与周百分比）；只有一个桶时 `G1 80%`；未选组/组不可用 `G1 请选择额度组` / `G2 额度组不可用`。
  - DeepSeek：`DS1 CNY 89.67`。
  - 不可用：`请添加账号` / `请重新选择` / `请选择账号`（原 `账号已移除，请重新选择` 与 `请选择菜单栏账号` 超出预算，已按固定宽度缩短）。
- `UsageFormatting` 新增 `menuBarQuotaTitle(code:fiveHour:weekly:)` 与带 `code` 的 DeepSeek 标题；删除 `labeledMenuBarTitle`、`labeledCompactMenuBarTitle`、`compactDeepSeekMenuBarTitle`（无 compact 形态）。1.0.2 的 `menuBarTitle`/`compactMenuBarTitle` 保留（面板仍在用）。
- `MenuBarContent` 去掉 `mode`；`sizeSignature` 只含 text + attention。

## 4. DeepSeek 余额行的阶梯

固定宽度下 13 pt 的 `DS1 CNY 123.45`（110 pt）超出 81 pt 预算，按用户确认的「币种可以简写或省略」处理，降级顺序为纯函数（`MenuBarLabelContent.fittedBalanceText`）：

1. 完整形态（含币种）——能放下就不动；
2. 去掉币种：`DS1 123.45`（75 pt，放得下）；
3. 去币种后仍超预算时按实测比例连续缩小字号（`DS1 — 123.45` 这类形态，或六位数以上余额），最低到 `balanceMinimumFactor = 0.75`；**金额数字从不截断**。

缩放比例按「字形宽度随字号缩放、词间 7 pt 间距固定」解算（`estimatedBalanceWidth(_:scale:)`）：只按整行等比缩放会低估实际宽度，第一版因此把 `DS1 — 123.45` 渲染成了 `DS1 — 123....`（截断），已修正并复核。

实际效果：DeepSeek 在菜单栏显示为 `DS1 123.45`；无名币种形态 `DS1 — 123.45` 略缩小但完整。币种仍在详情卡与设置里可见。

## 5. 刘海路径

改动文件：`Sources/UsageMonitorCore/Utilities/MenuBarSpaceState.swift`、`Sources/UsageMonitorApp/StatusItem/StatusItemController.swift`

- `MenuBarSpaceMode` 收敛为单值 `case fixed`；`MenuBarSpaceStateMachine` 简化为两出口：`apply(facts) -> .keep | .openDetailWindow`（`isRendered` 为假即后者）。删除了 full/compact 迁移、grow 确认窗口、成长阻塞与 `noteSpaceEvent`。
- `checkGeometry()` 在未渲染时，沿用既有「等自身 resize 稳定后打开详情窗口」的路径（`selfResizeSettleInterval` + `hasAutoOpenedDetailWindow` 只开一次 + `openDetailWindowIfItemIsHidden` 再核对一次），不显示残缺内容。
- `MenuBarSpaceFacts` 保留（几何事实仍需要），`MenuBarSpaceMonitor` 保留观察项与节奏，只去掉不再有意义的 `spaceEvent` 透传。

## 6. 执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `swift build --build-tests --scratch-path <本机临时目录>` | 退出码 0 |
| `swift test --scratch-path <本机临时目录>` | 693 项（Core 458 + App 235），688 通过、5 项既有跳过、0 失败，退出码 0；日志 `evidence/logs/swift-tests.log` |
| `MINGET_EVIDENCE_DIR=… swift test --filter "MenuBarEvidenceRenderTests\|DetailEvidenceRenderTests/testRenderSettingsPanesLightAndDark"` | 导出菜单栏状态矩阵、三个来源、时间条细节、真实宿主尺寸与设置页明暗各一张 |
| （诊断）临时测试渲染真实 `NSStatusItem` 按钮与真实宿主尺寸下的标签 | 复现并定位「时间条被挤出菜单栏带」，修复后目视确认，临时测试已删除 |
| `MINGET_EVIDENCE_DIR=… swift test --filter ManagedAccountEvidenceTests` | 导出含 4 个 Google 账号的「菜单栏显示」列表（`menubar-sources-*.png`） |
| `scripts/build.sh`（Release，暂存与归档在本机临时目录） | 退出码 0，`Minget Local Signing` 签名，staging / 安装 / 归档三处严格校验通过；日志 `evidence/logs/release-build-staging.log` |
| 备份并替换 `/Applications/Minget.app` | 旧 1.6.7 已备份并校验（哈希与替换前一致）；新版 1.6.8 严格校验通过，安装前后可执行文件哈希一致；`evidence/records/local-install.txt` |

## 7. 新增与更新的自动测试

- `Tests/UsageMonitorAppTests/MenuBarCodeTests.swift`（新增 6 项）：`O1`/`O2`、`G1`/`G2`/`G3`、`DS1` 与第二个 DeepSeek 账号得 `DS2`；移除账号后存活账号不重排；旧模式位置回退；菜单栏文本与设置列表使用同一代号。
- `Tests/UsageMonitorAppTests/MenuBarLabelWiringTests.swift`（重写）：固定宽度不变量（`textBudget` 等于最宽配额文案 + 2、每个来源与状态测量值相同、标记不改变宽度）、配额与余额形态落在预算内、时间条铺满预算、DeepSeek 阶梯（含币种优先、按比例缩放、字号下限、无名币种形态）、`install` 后 `appliedWidth == itemWidth`、内容变化不改变长度（替代旧的重测规则测试）。
- `Tests/UsageMonitorCoreTests/MenuBarContentTests.swift`（重写）：新文本格式、`O1 — —`、DeepSeek 各形态、`sizeSignature` 新语义。
- `Tests/UsageMonitorCoreTests/MenuBarSpaceStateTests.swift`（重写）：facts 判定保留，状态机改为两出口契约。
- `Tests/UsageMonitorCoreTests/AntigravityProviderTests.swift`：Gemini 文本断言更新为 `G1 80%` / `G2 额度组不可用`。
- `Tests/UsageMonitorAppTests/MenuBarPreferencesTests.swift`、`ManagedAccountTests.swift`、`RefreshCadenceTests.swift`：断言更新；`testShouldRemeasureOnlyOnSignatureChange` 随重测规则一并删除（新不变量由 `MenuBarLabelWiringTests.testContentChangesNeverResizeTheItem` 覆盖）。
- `Tests/UsageMonitorAppTests/MenuBarEvidenceRenderTests.swift`、`ManagedAccountEvidenceTests.swift`：行标签更新，去掉 compact 行，新增真实宿主尺寸渲染（`11-host-frame-*.png`）与 `menubar-sources` 明暗证据。
- 合计：Core 458 + App 235 = 693 项（1.6.7 为 694 项：single-mode 重写合并/删除了模式迁移与成长确认用例，新增代号、固定宽度与宿主尺寸证据用例）。

## 8. 已知问题与未完成事项

- 菜单栏项目宽度为 93 pt（1.6.7 为 123 pt，更早的配额条目约 82 pt）。宽度严格等于「`O1 100% 100%` 的实测宽度 + 2 pt」，符合用户确认的口径；超出预算的中文回退文案与长余额靠收缩字号容纳（最小 0.85 / 0.75），不截断。
- DeepSeek 币种代码在菜单栏按约定省略（固定宽度下的冲突处置），菜单栏只显示金额；币种仍在详情卡与设置中可见。
- 真实界面观感与代号对应由用户在正式安装的 1.6.8 上复验，状态见 [ACCEPTANCE.md](ACCEPTANCE.md)；本轮未发布。
- 工作区中 `releases/README.md`、`releases/v1.0.0/README.md`、`releases/v1.0.1/README.md` 仍处于已删除未提交状态，是本轮开始前既有状态，本轮未触碰。

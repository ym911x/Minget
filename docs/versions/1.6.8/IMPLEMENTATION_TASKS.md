# 1.6.8 实施任务

## 代码

1. **代号解析**（`UsageViewModel`）：新增 `menuBarCode(for:)`，`.profile` → `O{ordinal}`、`.google` → `G{ordinal}`、`.deepSeek`/`.apiAccount` → `DS{ordinal}`；注册表序号优先，旧模式（无注册表）退化为位置序号。`menuBarSource()` 把代号传入 Core 的 `MenuBarSource`。
2. **菜单栏文本**（`MenuBarContent.swift`、`UsageFormatting.swift`）：
   - `MenuBarSource` 携带 `code`（`MenuBarDeepSeekContent` 增加 `code`）。
   - 单一格式：ChatGPT/Gemini → `"\(code) \(p5) \(pw)"`；无数据显示 `"\(code) — —"`；Gemini 未选组/组不可用 → `"\(code) 请选择额度组"` / `"\(code) 额度组不可用"`。
   - DeepSeek → `"\(code) \(currency) \(amount)"`；超出预留宽度时先去币种、再缩放 0.85（不截断数字）。
   - `MenuBarContent` 去掉 `mode`；`sizeSignature` 只含 text + attention。
   - `UsageFormatting`：新增 `menuBarQuotaTitle(code:fiveHour:weekly:)` 与带 code 的 DeepSeek 标题；删除 `labeledMenuBarTitle` / `labeledCompactMenuBarTitle` / `deepSeekCompactMenuBarTitle`。
3. **固定宽度**（`StatusItemController.swift`、`MenuBarLabelView.swift`）：
   - `MenuBarLabelMetrics`：`textBudget = ceil(实测宽度(O1 100% 100%)) + 2 = 81 pt`；`labelWidth = textBudget`、`itemWidth = labelWidth + horizontalPadding = 93 pt`。宽度不因异常标记、Gemini 中文回退、不可用文案或 DeepSeek 币种而变宽；超预算文案按 `textShrinkFactor = 0.85` 收缩。
   - 异常标记与文字同行，不设常驻前置位（用户要求去掉数字两侧的空白）。
   - `MenuBarLabelContent` 固定为 `labelWidth` 宽、左对齐；两条时间条铺满 `textBudget`；DeepSeek 走同一预算与阶梯（去币种 → 按「字形缩放、间距固定」解算的比例缩小字号，下限 0.75）。
   - `StatusItemController`：单一 `labelWidth`，删除 `widths` 字典、`labelSignature` 与按内容重测机制；`apply()` 恒定宽度。
4. **刘海状态机**（`MenuBarSpaceState.swift`）：`MenuBarSpaceMode` 收敛为 `case fixed`；`MenuBarSpaceStateMachine` 简化为 `.keep` / `.openDetailWindow` 两出口；`checkGeometry` 在未渲染时沿用既有延时与只开一次的详情窗口路径。
5. **设置列表**（`MingetSettingsView.menuBarSections`）：候选行改为「代号 + 空格 + 现有名称」；移除账号回退行文案不变。

## 测试

6. `MenuBarContentTests`：新文本格式、无数据与中文回退、DeepSeek 阶梯、`sizeSignature`。
7. `MenuBarSpaceStateTests`：按新契约重写。
8. `AntigravityProviderTests`：更新 Gemini 菜单栏文本断言。
9. 新增 `MenuBarCodeTests`：O/G/DS 映射、ordinal 优先、旧模式位置回退、删除后不重排。
10. `MenuBarLabelWiringTests`：固定宽度不变量（所有来源/数值/标记下同一宽度；每个可渲染文本 ≤ 预算；时间条铺满预算；`statusItem.length` 恒定）。
11. `MenuBarEvidenceRenderTests`：标签更新，去掉 compact 行，加代号与阶梯样例；设置列表标题断言。

## 文档与版本

12. `VERSION` → `1.6.8`；`CHANGELOG.md`、`README.md`（含刘海压缩那句改为固定宽度）、`ROADMAP.md`、`docs/versions/README.md`、`PROJECT_STATUS.md`、根 `REVIEW.md`。
13. 导出菜单栏与设置渲染证据（明/暗）到 `docs/versions/1.6.8/evidence/`。
14. `./scripts/build.sh` 签名构建并装入 `/Applications/Minget.app`（先备份 1.6.7）；记录指纹、回滚指令与验收状态。

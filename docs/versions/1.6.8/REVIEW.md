# 1.6.8 审核

审核对象：分支 `codex/minget-1-6-8` 的工作区改动（`MenuBarContent.swift`、`MenuBarSpaceState.swift`、`UsageFormatting.swift`、`MenuBarLabelView.swift`、`StatusItemController.swift`、`UsageViewModel.swift`、`MingetSettingsView.swift` 与七个测试文件、文档与版本号）。检查方式：源码差异逐项核对 + 完整 `swift test` + 菜单栏与设置渲染证据目视 + 真实字体宽度实测 + Release 严格签名构建与安装校验。审核时间 2026-10-16。

## 检查结果

- [x] 长度固定是常量而不是测量结果：`MenuBarLabelMetrics.itemWidth = 93 pt`（`textBudget 81 + padding 12`），`StatusItemController.apply()` 只安装时设置一次 `statusItem.length`；per-mode 宽度字典、`labelSignature`、`shouldRemeasure` 与按内容重测路径已删除。
- [x] 宽度口径与用户要求一致：`textBudget = ceil(实测宽度(O1 100% 100%) = 79) + 2`，测试用等式钉住；没有为异常标记、Gemini 中文回退、不可用文案或 DeepSeek 币种预留额外宽度。
- [x] 异常标记不改变长度：标记与文字共用一行，不预留前置位；测试断言同一账号在 live 与 cached 两种状态下测量宽度相同。第一版曾用常驻 `Color.clear` 占位，导致无基线的弹性视图把整个 HStack 的基线算歪、**两条时间条被挤出 22 pt 菜单栏带**；临时诊断测试渲染真实宿主尺寸定位后已改为同行方案，并新增 `testRenderInsideTheRealHostFrame` 证据防回归。
- [x] 配额与余额形态都落在预算内：测试断言 `O1/O2/G1/G3 100% 100%`、`O1 — —`、`O1 9% 9%`、`G1 —`、`DS1 9.00`、`DS1 123.45`、`DS1 —` 的实测宽度 ≤ `textBudget`；超预算的中文回退文案按 `textShrinkFactor = 0.85` 收缩，不截断。
- [x] 时间条铺满预算：测试断言 5 段与 7 段各自铺满 `textBudget`，最小段宽退化行为不变；真实宿主尺寸证据中两条时间条可见。
- [x] 代号规范且稳定：`menuBarCode(for:)` 对 `.profile`/`.google`/`.deepSeek`/`.apiAccount` 给出 `O*/G*/DS*`，序号取注册表 `ordinal`；测试覆盖 O1/O2、G1/G2/G3、DS1/DS2、移除账号后不重排，以及无注册表时的位置回退。
- [x] 菜单栏与设置一致：设置列表与菜单栏来源都通过 `menuBarCode(for:)` 解析代号，列表行为「代号 + 原名称」；测试断言菜单栏文本以同一代号开头。
- [x] 内容格式符合确认口径：上排 `代号 + 百分比`（`O1 78% 42%`、`G1 80% 90%`），`5H`/`W` 与 Gemini 组名不再出现在菜单栏；下排 5 段/7 段时间条表达不变，并铺满固定预算。
- [x] DeepSeek 阶梯可测且不丢数据：先省略币种、再按「字形随字号缩放、词间距固定」解算的比例缩放字号（下限 0.75），金额数字从不截断；`DS1 — 123.45`（无名币种）与 `DS1 —`（无余额）各有一项测试，第一版等比缩放导致的截断已修正并目视复核。
- [x] 刘海路径不退化：`MenuBarSpaceStateMachine` 只返回 `.keep` / `.openDetailWindow`，控制器沿用既有延时与只开一次的保护；`MenuBarSpaceFacts` 的几何判定（含刘海、越界、截断、无帧）测试全部保留。
- [x] 未新增网络请求类型，未改端点、认证、节流、缓存命名空间与点火路径；`UsageMonitorCore` 的改动只在菜单栏展示层（`MenuBarContent`、`MenuBarSpaceState`、`UsageFormatting` 的菜单栏函数）。
- [x] 完整回归 693 项（Core 458 + App 235），5 项既有跳过，0 失败；与 1.6.7 的 694 项基本持平（single-mode 重写合并/删除了模式迁移与成长确认用例，新增代号、固定宽度与宿主体积证据用例；差异已在实施记录中列明）。
- [x] 渲染证据：菜单栏状态矩阵与三来源明暗各两张、时间条细节两张、**真实宿主尺寸**两张、设置「菜单栏显示」（旧模式与含 4 个 Google 账号两种）明暗各两张，全部为合成数据；图像显示所有行等宽、代号可见、两条时间条在真实宿主尺寸下仍然可见。
- [x] Release 严格签名构建通过，安装到 `/Applications/Minget.app` 后版本为 1.6.8，安装前后可执行文件哈希一致（修正版 `97c2635d…`），替换前 1.6.7 已备份并校验。

## 结论

改动范围与用户确认的口径一致，固定长度是可测常量而不是渲染巧合，代号在菜单栏与设置之间由单一方法保证一致；用户在正式安装的 1.6.8 上复验通过（2026-10-16），验收细节与未执行项见 [ACCEPTANCE.md](ACCEPTANCE.md)。本轮未发布，回滚边界见 [ROLLBACK.md](ROLLBACK.md)。

## 发布前独立复核（2026-10-16）

用户已授权发布。源码与已验收正式 App 记录指纹一致，原 16 份证据校验、正式包及两个程序严格签名通过；独立完整回归 693 项，688 通过、5 项既有跳过、0 失败。1.6.7 改动随 1.6.8 合并公开，发布结果见 [PUBLICATION.md](PUBLICATION.md)。

发布完成：v1.6.8 为 Latest，发布提交 `983bb8e` 的 GitHub CI 测试、Release 构建与严格签名通过，公开核验见 [PUBLICATION.md](PUBLICATION.md)。

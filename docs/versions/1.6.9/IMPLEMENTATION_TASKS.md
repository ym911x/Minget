# 1.6.9 实施任务

## 代码

1. **批次模型（App 层新增纯类型）**：`RefreshBatchScope`（`.overview`、`.chatGPT`、`.google`、`.deepSeek`、`.commandCode`）与成员解析函数。输入当前页面（`DetailPreferences.effectiveTab`）、菜单栏来源（`MenuBarPreferences.Selection`）、账号清单（Profile、Google、注册表账号），输出批次账号标识集合；纯函数，覆盖注册表与旧模式。
2. **刷新时间台账（`UsageViewModel`）**：按账号记录最近一次刷新发起时间（含失败），作为批次门槛唯一依据；从未刷新的账号视为已过期。周期、批次、手动、点火确认四条入口统一写入。
3. **周期循环收窄（`UsageViewModel`）**：
   - ChatGPT 自适应循环只在菜单栏来源为 Profile 时刷该 Profile，间隔按它的快照计算。
   - Provider 循环只在菜单栏来源为 DS / API 账号或 Google 账号时刷对应来源；删除对全部平台与全部 Google 账号的定时刷新。
   - `start()` 首次刷新与 `refreshAfterWake` 同样只作用于菜单栏来源。
4. **页面批次补刷（`UsageViewModel.panelWillOpen` 重写）**：按当前 `effectiveTab` 解析批次，做整批 5 分钟判定，命中则整批刷一次；概览页批次跨品牌，品牌页只含该品牌；DeepSeek 相关页面按需带官方状态页（超过 5 分钟才读）；独立详情窗口与 popover 共用该入口。
5. **标签切换（`UsagePanelView`）**：`selectedTab` 变化时调用同一批次入口，与打开时的触发去重。
6. **手动路径保持**：`refreshNow()`、`refreshBrand(_:)` 与点火确认刷新保持强制语义，并更新台账。
7. **设置说明（`MingetSettingsView`）**：「菜单栏低额度刷新」页脚补充新范围说明（其余账号仅在打开概览或品牌页时按 5 分钟门槛补刷），与实现措辞一致。

## 测试

8. 批次解析纯测试：概览 / 各品牌页 × 菜单栏来源（Profile / Google / DS / API / 未选择）× 注册表 / 旧模式。
9. 门槛判定测试：全新鲜跳过、一个过期整批刷、失败尝试计入、手动刷新推后门槛、批次之间不互相污染。
10. 定时器行为测试：三个循环只作用于菜单栏来源；来源切换后重新指向；启动与唤醒不再全量。
11. 面板 / 窗口测试：打开与标签切换的触发与去重；概览与品牌页范围正确；独立详情窗口一致。
12. 回归更新：`panelWillOpen`、`refreshProviders`、`MenuBarRefreshPolicy` 及相关既有用例按新契约修正；完整回归 0 失败。

## 文档与版本

13. `VERSION` → `1.6.9`；`CHANGELOG.md`、`README.md`、`ROADMAP.md`、`docs/versions/README.md`、`PROJECT_STATUS.md`。
14. `docs/versions/1.6.9/` 补齐 IMPLEMENTATION_REPORT.md、REVIEW.md、ACCEPTANCE.md，含本机请求节奏的真实证据。
15. `./scripts/build.sh` 签名构建并装入 `/Applications/Minget.app`（先备份 1.6.8），记录指纹、回滚指令与验收状态。

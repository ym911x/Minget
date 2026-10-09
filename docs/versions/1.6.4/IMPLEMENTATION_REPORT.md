# 1.6.4 实施记录

日期：2026-10-09，Asia/Shanghai。执行者：Command Code（Claude）。开发分支 `codex/minget-1-6-4`，来自干净 `main` 的 `73c3f9a`。本机交付，不推送、不打标签、不发布。用户要求测试后，已按本机流程做 Release 严格签名并安装到正式路径 `/Applications/Minget.app`。

## 完成结果

- 概要页（有效 Tab 为「概览」）的全部账号行支持拖动左侧 Logo 上下排序，跨平台全局混排，不分组限制。
- 落位目标按行高加行间距吸附到最近整数行：`OverviewAccountRow.pitch = 64 + 12 = 76`。拖动中被拖行只跟随指针位移，其余受影响的行按一格滑让，松手提交顺序并播放弹簧过渡（`response 0.28 / dampingFraction 0.9`）。
- 拖动状态由 `UsagePanelView` 持有（`dragActiveID`、`dragOriginIndex`、`dragDropIndex`、`dragFrozenOrder`、`dragTranslation`），不放在行内部，因此行内容每 30 秒的 `TimelineView` 重绘不会重置进行中的拖动。
- 拖动开始时冻结当次可见顺序，拖动期间模型发布新快照不改变行序；松手时把冻结顺序经移动规则写回偏好。
- 短按 Logo 与行内其他位置仍走原有详情入口；按下后位移超过 3 pt 即接管该次拖动（首次测试后由按住 0.3 秒改为立即，见下方修正记录）。
- 手势在窗口全局坐标系测量，并在行内使用高优先级，先于行按钮生效。
- 新增 `OverviewAccountOrderPreferences`：只存账号 ID 列表（`overview.accountOrder.v1`），解析规则为偏好优先、未知 ID 追加末尾、失效 ID 清理、去重；读取不落盘，只有真实提交才写入。
- 拖动排序之外提供键盘与 VoiceOver 的「上移/下移」（`accessibilityAdjustableAction`），复用同一条提交路径。
- 空状态的 Gemini 占位行 `isReorderable = false`，不参与拖动，也不写入顺序。

## 修改文件

- 新增 `Sources/UsageMonitorApp/ViewModels/OverviewAccountOrderPreferences.swift`：`OverviewReorder` 纯规则（`resolve` / `move` / `displacement` / `dropIndex`）与顺序偏好对象（读取、提交、去重、落盘）。
- 修改 `Sources/UsageMonitorApp/Views/SharedQuotaViews.swift`：`OverviewAccountRow` 增加 `pitch`、`isReorderable` 与 `onReorderDragArmed/Changed/Ended/Step` 回调，Logo 改为按住拖动的手柄（命中区外扩 4 pt、抓手提示、无障碍标签与可调操作）。
- 修改 `Sources/UsageMonitorApp/Views/UsagePanelView.swift`：概览行由三段独立 `ForEach` 改为统一有序列表 `displayedOverviewRows`（ChatGPT、Google、DeepSeek、Command Code 同一数组，占位行单列）；新增拖动状态、`reorderTransform` 位移与滑让、提交与步进；静态常量 `reorderAnimation` 统一动画曲线。
- 新增 `Tests/UsageMonitorAppTests/OverviewReorderTests.swift`：15 项纯规则与持久化测试。
- 新增 `Tests/UsageMonitorAppTests/OverviewReorderEvidenceTests.swift`：按 `MINGET_REORDER_EVIDENCE` 显式导出的示例渲染，无真实账号数据。
- `VERSION` 由 1.6.3 升为 1.6.4；`CHANGELOG.md` 增加 1.6.4 条目；本版本目录新增需求、任务、实施记录、审核、验收、回滚与证据。

## 命令与结果

```sh
swift build --scratch-path /tmp/minget-1.6.4-build --disable-sandbox
swift test  --scratch-path /tmp/minget-1.6.4-build --disable-sandbox

MINGET_REORDER_EVIDENCE=<dir> \
swift test --scratch-path /tmp/minget-1.6.4-build --disable-sandbox --filter OverviewReorderEvidenceTests

MINGET_BUILD_SCRATCH_DIR=/tmp/minget-1.6.4-release \
MINGET_STAGING_DIR=/tmp/minget-1.6.4-stage/Minget.app \
MINGET_RUN_PATH=/Applications/Minget.app \
MINGET_ARCHIVE_PATH=/tmp/minget-1.6.4-archive/Minget.app \
./scripts/build.sh
```

构建退出码 0；完整回归 Core 462 项（4 项既有跳过）+ App 214 项（1 项既有跳过），合计 676 项、0 失败、退出码 0。Release 流程使用已有 `Minget Local Signing`，staging、正式路径和 archive 三处严格校验通过且指纹一致，旧版 1.6.3 先备份再替换正式路径。原始日志与校验清单见 `evidence/logs/`、`evidence/records/local-install.txt`、`evidence/manifests/`。

## 拖动反馈修正（2026-10-09，用户首次测试后）

用户现场反馈两点：拖动过程中行会抖动且不连贯；希望按下即可拖动，不要等待。

原因与修正：

1. **抖动来自坐标系反馈**。拖动手势原先使用默认的局部坐标系，而行的位置又由同一次拖动驱动：行一边移动，手势一边以移动后的行作为参照测量距离，两者互相抵消，跟手距离被反复打折，表现为抖动与滞后。改为在窗口全局坐标系测量（`DragGesture(minimumDistance: dragThreshold, coordinateSpace: .global)`），手势只报告指针自身的位移，不再受行移动影响。
2. **滑动动画被页面级事务吞掉**。`UsagePanelView` 自 1.6.1 起带有 `.transaction { $0.animation = nil }`，用于抑制页面级隐式动画（当时页面内没有任何显式动画）。该修饰符覆盖整个子树，会把排序用的 `withAnimation` 一并清空，滑让只能瞬间跳格，观感不连贯。本轮移除该修饰符：页面内没有其他动画来源，服务切换与尺寸变化的实际表现不变；排序动画改为每行按自身位移判定（被拖行显式不参与动画，保证精确跟手）。
3. **去掉按住门槛**。原实现要求按住 0.3 秒后才接管，用户体感接近半秒到一秒。现在改为按下后位移超过 3 pt 即进入拖动，短按（不产生位移）仍由行按钮进入详情。
4. 落位与拖动结束合并为一次事务，被拖行从指针位置弹回目标槽位；位移换算抽成纯函数 `OverviewReorder.dragOffset`，并补充 3 项回归测试（被拖行只承担指针位移、其余行只整格滑动、槽位未变时其余行不动）。

修正后：`swift build` 通过；完整回归 Core 462 项（4 项既有跳过）+ App 217 项（1 项既有跳过），合计 679 项、0 失败；Release 严格签名重新安装到正式路径，候选与 archive 指纹一致。日志与安装记录见 `evidence/logs/swift-tests.log`、`evidence/logs/release-build.log`、`evidence/records/local-install.txt`。

## 已注意的实现细节

- 提交顺序时用 `visibleIDs` 过滤，拖动途中被移除的账号不会写进偏好；`displayedOverviewRows` 的字典构造使用 `uniquingKeysWith`，重复 ID 也不会让界面崩溃。
- 概览行高度函数（`overviewHeight` / `presentationHeight`）只与账号数量有关，本轮未改，七账号无滚动容器与短屏兜底的既有行为保持不变。
- 拖动过程中不改 `AccountRegistry.ordinal`，管理账号列表、菜单栏来源列表和详情页顺序不受影响。

## 未完成事项

- 用户于 2026-10-09 复测确认拖动体验可以接受，本轮固化。用户确认的范围是拖动交互本身（跟手、无抖动、无需按住等待）；拖动期间刷新不打乱行序、重启后顺序恢复、键盘与 VoiceOver 上移下移仍为自动逻辑通过、现场待核对。
- 拖动到视口边缘不会自动滚动卡片栈。概要设计为完整显示、屏幕放不下时才出现滚动容器，该增强留给后续版本，本轮不做也不在此记为通过。
- 未发布：未打标签、未推送、未建 Release、未写发布说明。远端核验由后续发布任务完成。

## 固化状态（2026-10-09）

- 分支 `codex/minget-1-6-4` 基于 `main@73c3f9a`，包含本轮全部实现与文档；`codex/project-folder-organization` 的目录整理变更不在本分支内，合并顺序由后续任务决定。
- 冻结源码与已安装构建一致：`Sources/`、`Tests/` 内没有晚于 Release 构建（12:25:26）的文件，正式路径与 archive 的 UsageMonitor 指纹同为 `57824c9262bb3b51b3c144fbe43692e83e1885bb57de5bd5f2d8f09bd0245d6d`。核对记录见 `evidence/records/frozen-build.txt`。
- 进度、证据与回滚路径见本目录 [验收](ACCEPTANCE.md)、[回滚](ROLLBACK.md) 与 [证据说明](evidence/README.md)。

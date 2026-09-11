# 明明有数 · Minget v1.0.2 实施报告

| 项目 | 值 |
| --- | --- |
| 目标版本 | 1.0.2 |
| 需求文件 | `docs/versions/1.0.2/REVISION_SPEC.md` |
| 检查基线提交 | `d16a5bc72b2cd99a8cf7ffa83c6da561f8a8c1d0` |
| 提交状态 | 执行全过程未提交、未推送、未创建标签，工作区保持未提交状态 |
| `VERSION` 变更 | `1.0.1` 改 `1.0.2` |
| 候选包 | `dist/Minget.app` |
| 候选包版本 | `CFBundleShortVersionString` = `1.0.2` |
| Bundle Identifier | `local.usagemonitor.UsageMonitor`，未变更 |
| 实施范围 | 需求文件 §1.1 的四项修订（R1 品牌图标、R2 两排时间条、R3 外部点击收起、R4 异常标记统一） |
| 审核状态 | 2026-09-11 Codex 独立代码审核与构建复核通过；2026-09-12 用户真实点击验收通过 |

## 1. 执行环境与权限边界

| 项目 | 实测值 |
| --- | --- |
| 机器 | Apple Silicon（arm64），macOS 13+ 目标 |
| 工具链 | Swift 6.x，SwiftPM，`swift build` / `swift test` 正常 |
| 显示 | 内建屏 1512 × 982，带传感器刘海，`safeAreaInsets.top` = 37 pt |
| 菜单栏带宽 | `NSStatusBar.system.thickness` 实测 **22.0 pt**。需求文件 §3.2 写作 24 pt，本轮以本机实测值设计高度 |
| 屏幕录制权限 | 无。`screencapture -x` 无法执行，真实菜单栏截图在本环境不可得 |
| 辅助功能权限 | 无。System Events 合成点击返回「权限违例」，真实鼠标点击链路在本环境不可得 |

两条权限限制决定了第 6 节的未验证项。其余自动测试、构建、包校验与真实进程运行均已实际执行。

## 2. 改了什么

### R1 移除菜单栏品牌图标

| 文件 | 修改 |
| --- | --- |
| `Sources/UsageMonitorApp/Views/MenuBarLabelView.swift` | 删除 `icon(size:)` 与全部模式下的 `M²` 绘制；三种模式统一为纯文字，`full` 与 `compact` 从 `5H` 起头 |
| `Sources/UsageMonitorCore/Utilities/UsageFormatting.swift` | 新增 `minimalMenuBarTitle()`，返回 `5H` |
| `Sources/UsageMonitorApp/StatusItem/StatusItemController.swift` | 最小模式 fallback 宽度由 28 pt 收窄到 26 pt，对应不再绘制图标 |

正常态文字形态：`5H 78% | W 42%`（full）、`5H 78% W 42%`（compact）、`5H`（最小兜底）。11 pt 字号保持不变。

### R2 新增两排重置时间分段条

| 文件 | 修改 |
| --- | --- |
| `Sources/UsageMonitorCore/Utilities/ResetTimeProgress.swift` | 新增纯时间模型，不依赖 SwiftUI、定时器与网络 |
| `Sources/UsageMonitorApp/Views/ResetTimeBarsView.swift` | 新增两排分段视图 |
| `Sources/UsageMonitorCore/Utilities/MenuBarContent.swift` | 新增单一决策点，输出文字、标记、两排进度 |
| `Sources/UsageMonitorApp/Views/MenuBarLabelView.swift` | 文字在上、两排在下；文字宽度用 `PreferenceKey` 实测，两排消费同一宽度 |

时间算法按 §4.2 实现：`fills[i] = min(max(units - i, 0), 1)`，`units = clamp(remaining, 0, total) / secondsPerSegment`。5 段每段 3600 秒，7 段每段 86400 秒。段宽 `(L - (段数 - 1) × 2) / 段数`，两排总宽相同。60 秒时钟容差为常量 `ResetTimeModel.clockTolerance`。

绘制参数：细线高 1.5 pt，同排段间距 2 pt，两排间距 2 pt，文字与第一排间距 1 pt，亮区不透明度 0.85（实时）与 0.45（缓存），轨道 0.20（实时）与 0.15（缓存），未知或非法排的轨道再降一档（0.12 / 0.10）。

### R3 点击外部收起详情弹层

| 文件 | 修改 |
| --- | --- |
| `Sources/UsageMonitorCore/Utilities/PopoverDismissDecision.swift` | 新增纯几何判定，输入点击点、弹层 frame、状态项按钮 frame，输出三种目标 |
| `Sources/UsageMonitorApp/StatusItem/StatusItemController.swift` | `StatusItemController` 实现 `NSPopoverDelegate`；新增 `PopoverDismissMonitor`，仅在弹层打开期间安装 local 与 global 鼠标监听 |

local 监听返回原事件，点击不被吞掉。弹层内控件、状态项按钮、弹层所属 sheet 判为内部，不关闭；其余判为外部并关闭。`popoverDidClose` 委托回调与 `uninstall()` 都会移除监听，`install` 幂等。普通详情窗口与 GLM 独立窗口不参与该逻辑。

### R4 异常标记统一前置

| 文件 | 修改 |
| --- | --- |
| `Sources/UsageMonitorCore/Utilities/UsageFormatting.swift` | `menuBarTitle` 与 `compactMenuBarTitle` 删除 `isStale` 形参与尾部 `⚠` |
| `Sources/UsageMonitorCore/Utilities/UsageDisplay.swift` | `menuBarTitle` 改为直接委托，不再内置警告 |
| `Sources/UsageMonitorCore/Utilities/MenuBarContent.swift` | 警告决定集中在 `MenuBarContentBuilder.attention`，取值 `none` / `warning`；前方标记使用 SF Symbol `exclamationmark.triangle.fill` |

`attention` 规则：`live` 无标记；`stale` 有标记；`unavailable` 且连接状态为 `disconnected` 有标记；`unavailable` 且为 `idle` 或 `connecting`（首次加载未定论）无标记。同一时刻最多一个标记，只出现在文字前方，尾部不再出现任何警告字符。

### 支撑性修改

| 文件 | 修改 |
| --- | --- |
| `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift` | 新增 `menuBarContent(for:now:)` 与 `menuBarSizeSignature`；新增时钟观察，唤醒通知注册在 `NSWorkspace.shared.notificationCenter`，系统时钟变化注册在默认中心；`stop()` 释放全部 observer |
| `Sources/UsageMonitorCore/Utilities/MenuBarSpaceState.swift` | `.icon` 的显示标签由 `icon` 改 `minimalText`；`rawValue` 保持 `icon`，位置与偏好持久化不受影响 |
| `VERSION` | `1.0.1` 改 `1.0.2` |

## 3. 关键设计决定

1. **两排条的单位按需求文件 §1.3 执行：7 段，每段 1 天，合计 7 天。** 用户原文为「每个短线代表一周」，与「周重置」的上下文相乘会变成 7 周，无法表达当前周窗口。本项在最终回复中单独向用户点明，若用户更正则改回。
2. **时间模型、布局决策、点击判定全部做成纯函数。** `ResetTimeProgress`、`MenuBarContentBuilder`、`PopoverDismissDecision` 都不触碰 SwiftUI、定时器与网络，因此第 8.1 节的异常矩阵可以在无窗口服务器的环境下完整验证。
3. **文字宽度是唯一尺寸来源。** `MenuBarLabelContent` 让 `Text` 决定宽度，两排条只消费已确定的宽度，因此条不会反过来撑宽状态项。首次布局用同字号的同步估算（`estimatedTextWidth`）兜底，实测到达后替换。
4. **警告只有一个来源。** 字符串层不再拼警告，绘制层只画一个前方标记。这样任何调用方都无法追加第二个标记，也不会丢失缓存提示。
5. **弹层关闭采用显式监听加 `.transient` 双保险。** 仅依赖 `.transient` 在配件型应用与菜单栏场景下覆盖不足，因此在其上叠加显式判定；监听只在弹层打开期间存在，所有关闭路径（含系统自动关闭）经 `popoverDidClose` 统一清理。
6. **测量先于首次几何检查。** 这一项由真实运行证据倒逼得出，详见第 5 节。

## 4. 执行命令与实际结果

全部命令在仓库根目录执行，原始输出保存于 `evidence/logs/`。

| 命令 | 实际结果 | 证据 |
| --- | --- | --- |
| `git rev-parse HEAD` | `d16a5bc72b2cd99a8cf7ffa83c6da561f8a8c1d0` | `logs/01-test-and-repo.txt` |
| `git status --short` | 10 个已修改文件、9 个新增文件、`docs/versions/` 未跟踪 | 同上 |
| `swift test`（四项菜单栏修订阶段） | **345 项通过，0 项失败，0 项跳过**，用时 10.4 s | 同上；钥匙串修订加入后全量为 359 项，见第 11.3 节 |
| `./scripts/build.sh` | `built: dist/Minget.app`，release 配置，ad-hoc 签名 | `logs/02-build-and-bundle.txt` |
| `plutil -lint dist/Minget.app/Contents/Info.plist` | `OK` | 同上 |
| `codesign --verify --verbose=1 dist/Minget.app` | `valid on disk`，`satisfies its Designated Requirement`，退出码 0 | 同上 |
| `plutil -extract CFBundleShortVersionString` | `1.0.2` | 同上 |
| 二进制 | `Mach-O 64-bit executable arm64`，`flags=0x2(adhoc)`，`TeamIdentifier=not set` | 同上 |

测试基线说明：1.0.0 的 274 项记录未改动。本轮 345 项中，各新增与调整类别的实际用例数如下。

| 测试类 | 用例数 | 覆盖的第 8.1 节条目 |
| --- | --- | --- |
| `ResetTimeProgressTests` | 21 | 1、2、3、4、5、6、7 |
| `MenuBarContentTests` | 19 | 8，以及三种模式的文字与尺寸签名 |
| `PopoverDismissDecisionTests` | 10 | 11 的纯判定部分 |
| `MenuBarLabelWiringTests` | 17 | 9、10、11 的生命周期部分 |
| `MenuBarEvidenceRenderTests` | 1 | 生成 §8.2 的布局证据图 |
| `MenuBarSpaceStateTests` | 20 | 空间模式与截断判定 |
| `UsageFormattingTests` | 8 | 尾部警告已删除的同步更新 |
| `UsageDisplayTests` | 6 | 缓存与实时语义保留 |

## 5. 真实运行中发现并修复的缺陷

这是本轮执行中最重要的发现。启动真实候选包后，日志显示状态项在几秒内从 full 一路降级到最小兜底，并且因为被判为「不可见」而自动弹出了普通详情窗口。

**修复前（单实例，`evidence/logs/04-real-run-truncation-defect-before-fix.log`）**

```
fetch ok windows=5h:true/weekly:true account:chatgpt(plus)
display live
menu bar ... truncated:y frame:x1316 w116 requested:132 mode:full
menu bar ... truncated:y frame:x1316 w110 requested:132 mode:compact
menu bar ... truncated:y frame:x1316 w44  requested:132 mode:minimalText
menu bar ... truncated:y frame:x1420 w44  requested:100 mode:minimalText
status item not visible at launch, opening detail window
（此后 3 分钟以上一直停在 mode:minimalText）
```

**修复后（单实例，同样从 `/tmp` 运行，`evidence/logs/03-real-run-after-fix.log`）**

```
fetch ok windows=5h:true/weekly:true account:chatgpt(plus)
display live
menu bar ... truncated:n frame:x1293 w116 requested:67  baseline:67  mode:full
menu bar ... truncated:n frame:x1260 w116 requested:100 baseline:100 mode:full
（此后每 10 秒一次的检查连续 20 余次均为 mode:full、truncated:n）
termination requested
service stopped (generation 1, drained=no)
viewmodel stopped
service stopped (generation 2, drained=no)
```

两次运行的授予宽度都是 116 pt，起手模式都是 full，构成一次干净的真实 A/B：基线取 132 pt fallback 时判 `truncated:y` 并连续降级，基线取实测 100 pt 时判 `truncated:n` 并稳定保持 full。

顺带解释了一个此前存疑的数值：授予宽度 116 pt 与文字实测宽度 100 pt 相差约 16 pt。应用请求的 100 pt 已经包含自己的 12 pt 内边距，因此这 16 pt 只能来自系统侧对状态项窗口的外扩。该结论由日志中的两个数值推出，不是对 AppKit 内部实现的直接观测。判定截断时比较的是 macOS 授予的窗口宽度与应用请求的宽度，因此这一差额本身不会造成误判，前提是基线为实测值。

**根因**：`install` 里第一次 `apply` 发生在任何测量之前，用的是每个模式的 fallback 宽度（full 为 132 pt）。`isTruncated` 拿 macOS 实际授予的 116 pt 与 132 pt 比较，判为「被截断」，于是状态机每观察一次降一级，从 full 降到 compact 再降到最小兜底，并被 `growthBlocked` 挡住不能自行恢复。后果有两层：一是需求文件 §3.3 明确禁止的「最小兜底成为实际默认」被触发；二是 `isStatusItemRendered` 为假，触发了启动自动打开详情窗口。修复前日志中还能看到 sizing 与 mode 已经脱节：`mode:minimalText` 时的 `requested` 是 100，即 full 模式的实测宽度。

`evidence/logs/05-real-run-first-candidate.log` 是同一候选包更早一次的真实运行，同为 116 pt 授予宽度却保持了 `mode:full` 超过两分钟，说明这是竞态而非固定行为。该次日志早于 `requested:` 字段的加入，因此没有记录基线值；但 `isTruncated` 为假要求 `授予宽度 ≥ 基线 - 1`，由 `116 ≥ 基线 - 1` 可推出该次运行的基线不高于 117 pt，也就是实测宽度而非 132 pt fallback。

需要如实说明的一点：修复前日志（`logs/04`）中降级的三条观察里 `requested` 都显示 132，第四条才显示 100，即降级决策确实发生在任何实测宽度生效之前，但同一秒内的调用先后顺序本轮没有插桩到可以逐条归因的程度。修复后 `requested` 与 `baseline` 在每一行都等于该模式的实测值，该顺序问题不再存在，因此未继续追查原始时序。`evidence/logs/06-real-run-truncation-defect-with-measure-diagnostics.log` 保留了当时用于定位的临时测宽诊断行，可直接读出三种模式的实测宽度：无额度数据时 full=67、compact=61、minimalText=28；真实数据时 full=100、compact=94、minimalText=28。

**修复**（`StatusItemController.swift`）

1. `install` 在 `apply` 之前调用新增的 `measureWidths(for:)`，状态项首次上屏就用实测宽度。
2. `checkGeometry` 在「当前模式尚无实测宽度」时把传给几何判定的 `requestedWidth` 取 0。`MenuBarSpaceFacts.isTruncated` 本身要求 `requestedWidth > 0`，因此未测量的 fallback 永远不会被当成截断基线。
3. 日志增加 `baseline:` 字段，使 `requested` 与判定基线可分别核对。

修复后退出路径干净，子进程按既有机制回收。该缺陷同时被两项测试固定：(a) `MenuBarSpaceStateTests.testNoMeasuredBaselineIsNotTruncation` 断言无基线时不判截断；(b) `MenuBarLabelWiringTests.testInstallSizesTheItemFromAMeasurementNotTheFallback` 断言 `install` 后 `appliedWidth` 等于实测宽度且不等于 fallback。

## 6. 已知问题与未完成事项

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| UI-01、UI-02、UI-06、UI-07、UI-08 真实菜单栏截图 | **未验证** | 本环境无屏幕录制权限，`screencapture` 不可执行。已用真实视图代码的离屏渲染图替代（`evidence/01` 到 `08`），图内明确标注为夹具 |
| UI-10、UI-11、UI-12 真实外部点击 | **未验证** | 本环境无辅助功能权限，无法合成点击，也无法录制。仅完成纯判定测试与实际运行时的监听安装/清理观察 |
| UI-13 睡眠唤醒真实复现 | **未验证** | 需要真实睡眠周期，本轮未执行；唤醒通知已改到 `NSWorkspace.shared.notificationCenter`，并有单元测试覆盖唤醒后的重算逻辑 |
| UI-14 独立窗口不被误关 | **未验证（真实交互）** | 代码路径上独立窗口不参与弹层判定，已由纯判定测试覆盖 |
| `?` 状态徽标位置 | **偏离，已记录** | 两排合计 5 pt 高，可读的 `?` 约 9.5 pt，按排水绘制必然溢出。改为整块居中绘制一个，具体哪一排未知由该排更淡的轨道与无障碍文字承载 |
| 启动到 `viewmodel start` 的 11 到 87 秒延迟 | **超出本轮范围，候选原因未证实** | 四次真实运行中 `applicationDidFinishLaunching` 到 `viewmodel start` 间隔为 14 s、13 s、11 s、13 s，另一次超过 87 s；换自签名证书后三次启动仍为 12 s、15 s、11 s。该段代码属于既有初始化路径，四项修订未触碰，本轮不做改动。候选原因与判别方式见第 10 节 |
| 钥匙串反复授权弹框 | **核心场景已由用户实测通过** | 用户确认只弹一次，选择“始终允许”后不再重复弹出，真实余额随后更新；后台轮询、换 Key 与锁屏唤醒列为扩展观察项，见第 11.6 节 |
| `dist/UsageMonitor.app` 旧包残留 | **需人工确认** | 仓库 `dist/` 下仍存在 1.0.0 时期的 `UsageMonitor.app`，与本轮 `dist/Minget.app` 同名可执行文件。已确认本轮全部真实运行使用的是 `dist/Minget.app`（后复制到 `/tmp` 运行以排除干扰）。建议后续清理旧包，避免误启动旧实例 |
| 发布、推送、标签 | **未执行** | 需求文件 §1.2 明确不做 |

## 7. 偏离本方案的地方

1. **两排间距由 1 pt 改为 2 pt。** §3.2 起始值为 1 pt，实测在 Retina 菜单栏上两条 1.5 pt 细线会黏成一条粗带，两个窗口读起来像一个条。2 pt 属于 §3.2 允许的「小范围调整间距」。
2. **`?` 徽标整块绘制一个，而非按排各绘一个。** §4.3 要求「在该排中部覆盖小型 `?`」。两排合计高度 5 pt，按排绘制会得到两个重叠字形。改为整块居中一个，状态区分由轨道浓度与无障碍文字承担。
3. **几何判定新增 `baseline` 概念，未测量时不判截断。** §3.2 要求 fallback 合理并被实测替代，§3.3 要求最小兜底只在空间确实不足时出现。原实现两者都不满足，导致真实运行中最小兜底成为实际默认。本项属于为满足 §3.3 必需的最小改动，未改动状态机的防抖与恢复策略。
4. **`MenuBarSpaceMode.icon` 的 `description` 显示名改为 `minimalText`。** §3.3 允许保留枚举名作为内部兼容名。`rawValue` 未变，位置保存键与偏好持久化不受影响。
5. **修正唤醒通知的注册中心。** §4.4 要求核实并修正。原代码注册在 `NotificationCenter.default`，实际不会触发；改为 `NSWorkspace.shared.notificationCenter`。
6. **详情页重置时间文案改为「已到重置时间，等待刷新确认」。** §4.3 要求针对该状态最小修改，避免与菜单栏矛盾。未改版详情页其他内容。
7. **诊断日志增加 `baseline:` 与 `requested:` 字段。** 仅几何数值与模式名，无任何额度内容与凭证，用于本次定位与后续验收核对。

## 8. 报告与候选包路径

| 内容 | 路径 |
| --- | --- |
| 本报告 | `docs/versions/1.0.2/IMPLEMENTATION_REPORT.md` |
| 独立审核状态 | `docs/versions/1.0.2/REVIEW.md` |
| 分阶段验收台账 | `docs/versions/1.0.2/ACCEPTANCE.md` |
| 证据说明 | `docs/versions/1.0.2/evidence/README.md` |
| 布局证据图 | `docs/versions/1.0.2/evidence/01` 到 `08` 共 8 张 PNG |
| 命令与运行日志 | `docs/versions/1.0.2/evidence/logs/01` 到 `12` |
| 签名交接文件 | `docs/versions/1.0.2/SIGNING_HANDOFF.md` |
| 钥匙串修订方案 | `docs/versions/1.0.2/KEYCHAIN_REVISION_PLAN.md` |
| 签名脚本（新增） | `scripts/make-signing-identity.sh` |
| 构建脚本（签名段与产物路径已改） | `scripts/build.sh` |
| 运行候选包 | `~/Applications/Minget.app` |
| 归档候选包 | `dist/Minget.app` |

## 9. 执行 `SIGNING_HANDOFF.md` 的记录

`docs/versions/1.0.2/SIGNING_HANDOFF.md` 描述的是钥匙串反复授权弹框，与四项修订无关，属于第二份交接。用户确认后本轮执行了其中执行方可以完成的部分。

### 9.1 已完成

| 动作 | 文件 | 内容 |
| --- | --- | --- |
| 改签名段 | `scripts/build.sh` | 默认身份改为 `Minget Local Signing`，可用 `MINGET_SIGN_IDENTITY` 覆盖；身份存在性检查；`codesign --force --sign "$SIGN_IDENTITY" --timestamp=none` |
| 保留回退 | `scripts/build.sh` | `MINGET_SIGN_IDENTITY=- ./scripts/build.sh` 仍走 ad-hoc 签名 |
| staging 失败保护 | `scripts/build.sh` | `rm -rf` 后增加存在性检查，删除失败即非零退出，避免产出混合包（见 9.6） |
| 新增证书脚本 | `scripts/make-signing-identity.sh` | 用 OpenSSL 3 生成自签名代码签名证书、导入登录钥匙串、可选授权私钥（`--authorize`） |
| 行为验证 | `evidence/logs/08-signing-build-path.txt` | 默认路径在无证书时 `exit=1` 并打印指引；ad-hoc 回退路径构建通过、签名校验通过、版本仍为 `1.0.2` |

实测结果：默认路径失败时，`dist/Minget.app` 的 DR、mtime 与二进制大小逐字段不变，证明失败路径不会留下一个「已暂存但未签名」的包。

### 9.2 与交接文件的偏离

1. **身份检查放在 `swift build` 与 staging 之前**，而交接文件 §3.4 把它放在签名处。理由：交接文件的位置在 `rm -rf dist/Minget.app` 之后，身份缺失会在包已被删除重建后才失败，留下未签名产物，并浪费一次完整编译。前移后失败路径零副作用，实测见上。
2. **未加 `--options runtime`、未加时间戳**，与交接文件一致；`find-identity` 同样不带 `-v`，理由是该文件已说明的「未受信任的自签名证书会从 valid only 列表中被省略」。
3. **staging 增加删除失败检查**，交接文件未要求。这是本轮真实踩到的问题，理由见 9.6。

### 9.3 一处事实修正

交接文件 §2.3 第 2 条写作「Swift 编译产物字节变化，cdhash 随之变化」，把变化归因于「重建」这一动作。实测表明该表述不够准确：源码未变时连续重建，cdhash 保持 `aedb372d…` 不变，二进制大小也一致，release 构建在本机是可复现的。

准确表述应为：cdhash 随二进制内容变化。因此 ad-hoc 签名下的症状会在代码改动后出现（这解释了「每次重建后照旧弹框」的实际观感，因为重建通常伴随改代码），而仅在源码未变时重复构建不会改变 DR。交接文件的结论不受影响：ad-hoc 的 DR 退化到 cdhash，一旦内容变化或与创建钥匙串条目时的版本不同，ACL 即失配；三个同 bundle id 副本的 cdhash 各不相同，会互相覆盖授权记录。

已在交接文件末尾追加一节「执行者补注」记录此项，未改动原文。

### 9.4 交接文件 §4 验收（证书创建后实测）

原始输出见 `evidence/logs/09-signed-verification.txt`。

| # | 检查 | 结果 | 实测 |
| --- | --- | --- | --- |
| 1 | 签名不再 ad-hoc | 通过 | `Authority=Minget Local Signing`、`Signature size=1822`、`flags=0x0(none)`，不再出现 `Signature=adhoc` |
| 2 | DR 含证书 | 通过，措辞需修正 | 实际为 `designated => identifier "local.usagemonitor.UsageMonitor" and certificate root = H"5a48bb2b5305dd0ad0484581f1ce5173061ba395"`。交接文件预期写作 `certificate leaf`，自签名证书自身即为根，因此导出的是 `certificate root`。证书哈希存在这一点不变 |
| 3 | DR 跨构建恒定 | **通过** | release 与 debug 交替构建三次：CDHash 为 `e4842fa1…` 到 `0173a4fc…` 再到 `e4842fa1…`（二进制内容确实变了），DR 的证书哈希始终为 `5a48bb2b…`。这正是 ad-hoc 时代会失配的场景，现已守住 |
| 4 | 结构校验通过 | 通过 | `codesign --verify --verbose=1` 返回 `valid on disk`，退出码 0 |
| 5 | 真实弹框消失 | **未达成** | 证书创建后仍会弹出，一次启动最多记录到 12 次，见 9.5 |

证书状态：`security find-identity -p codesigning` 列为 `1) 5A48BB2B5305DD0AD0484581F1CE5173061BA395 "Minget Local Signing" (CSSMERR_TP_NOT_TRUSTED)`。未设信任属 §3.3 的可选项，不影响签名与本地运行；`-v` 仍返回 `0 valid identities found`，印证了 `build.sh` 不带 `-v` 的必要性。

候选包现状：`dist/Minget.app` 为 release 构建，`CDHash=e4842fa1…`，`Authority=Minget Local Signing`，DR 指向证书根 `5a48bb2b…`，`CFBundleShortVersionString=1.0.2`，包内 7 个文件，校验通过。

### 9.5 仍需用户完成的动作

| 步骤 | 命令或操作 | 说明 |
| --- | --- | --- |
| 1 | `./scripts/make-signing-identity.sh` | **已完成**。证书已存在 |
| 2 | `./scripts/build.sh` | **已完成**，见 9.4 |
| 3 | 打开 `dist/Minget.app`，遇到弹框时点一次「始终允许」 | 结构性验收已通过，但真实弹框是否已被授权尚未确认 |
| 4 | 重建后再次打开，确认不再弹框 | 交接文件 §4 第 5 条，必须在真实界面完成 |

步骤 3 的实际结果：**未达成。** 证书创建后一次启动中，钥匙串对话框弹出 12 次（用户实测报告，原始记录见 `evidence/logs/11-dialog-investigation.txt`）。

代码侧的关键事实：钥匙串条目只有 3 个（`deepseek.api-key`、`glm.api-key`、`glm.console-session`），而 `credentials.load` 有 10 处调用点。因此 12 次弹框不可能是 12 个条目，只能是 12 次「访问」。这说明**授权没有被记住，每次读取都会重新弹框**，而不是「三个条目各授权一次即可」。

一个必须说明的方法差异：执行方此前全部用 `exec` 直接运行包内可执行文件来获取应用内日志，例如
`./dist/Minget.app/Contents/MacOS/UsageMonitor`。这不是用户打开应用的方式（正常方式是双击或 `open dist/Minget.app`，已用 `lsappinfo` 确认正常方式启动会注册为 App）。系统判定钥匙串访问归属的依据在两种方式下可能不同，所以上述 12 次还不能直接等同于用户双击时的表现，需要正常启动再数一次。

正常启动路径无法采集应用内日志：`open --env USAGE_MONITOR_LOG_FILE=...` 未生效，`launchctl setenv` 被拒绝（`Not privileged to set domain environment`）。用「`open` 到缓存文件 mtime 变化」的间接计时结果为 4 秒、12 秒、7 秒，该区间包含真实的网络取数，噪声大于要测的初始化阻塞，不足以定论。

下一步只有一个观察能定性：正常打开应用数一次弹框次数；同时在「钥匙串访问」里查看 `local.usagemonitor.credentials` 条目的「访问控制」列表长度。若该列表已被填满，就能解释为什么「始终允许」不再被记录。此项尚未实测，不作为结论。

### 9.6 一次真实的构建事故与修复

本回合内多次执行构建后，`rm -rf dist/Minget.app` 被执行环境的安全限制拒绝（单回合累计删除文件数超阈值），原脚本对此没有检查，继续执行 `mkdir` 与 `cp`，于是把上一次 debug 构建的二进制留在了 `dist/Minget.app`，并以退出码 0 打印 `built: dist/Minget.app`。实测该包 `CDHash=0173a4fc…`，属 debug 构建，不是 release。

处置：受损包移动到 `/tmp/minget-broken/Minget.broken.app`（未删除），重新构建得到干净产物，并在 `scripts/build.sh` 的 `rm -rf` 之后加入存在性检查，删除失败即非零退出且不触碰已有产物。修复后的行为已实测，见 `evidence/logs/10-staging-fail-closed.txt`。

该事故属执行环境的限制，不是产品缺陷；但它暴露的脚本脆弱点是真实的：删除被拒时会产出既不是上一版也不是新版的混合包，并误报成功。现已 fail closed。

不应由执行方代做的动作：`security set-key-partition-list` 需要登录密码，触碰既有钥匙串条目需要用户判断，真实界面的「始终允许」点击只有用户能做。

`scripts/make-signing-identity.sh` 的验证状态取决于用户实际采用哪条路径创建证书。当前事实是证书已存在，且 `codesign` 能在 1.4 秒内完成签名且不索要私钥密码，说明私钥授权已就绪。若证书是用该脚本创建，则脚本已完成端到端验证；若用钥匙串访问图形界面创建，则脚本本身仍只经过 `bash -n`，尚未端到端验证。

## 10. 启动延迟：候选原因与当前证据

第 6 节记录的启动阻塞最可能的解释，是第 9 节这份交接描述的钥匙串访问。原先的依据有四点：

1. 阻塞区间正好落在唯一一次钥匙串读取上。`AppContainer()` 在 `applicationDidFinishLaunching` 内首次被访问，其构造过程中 `UsageViewModel.init` 调用 `publishProviderReports()`，进入 `ProviderRefreshEngine.allReports()`，再进入 `report(for:)`。
2. `ProviderRefreshEngine.swift:117` 的 `reader.isConfigured` 会读钥匙串：`ProviderReadings.swift:18` 读 DeepSeek Key，`:123` 读 GLM Key，`:128` 的 `session()` 读 GLM 会话。`model.start()` 的日志在这之后才写出，与观测到的顺序一致。
3. 交接文件 §1 记录同一处访问在 ad-hoc 签名下每次启动都会弹框。
4. 延迟时长变化很大（11、13、13、14 秒，以及一次超过 87 秒），符合等待人工应答的特征，不符合固定计算耗时。

该结论为代码路径与既有记录推出的推断，不是对对话框的直接观测：本机无屏幕录制权限，无法截图；`log show` 在沙箱内不可执行。

**后续证据把机制说得更具体了，推断由「一次对话框等待应答」修正为「每次钥匙串访问各弹一次」。** 证书创建后一次启动中弹框 12 次（用户实测），而钥匙串条目只有 3 个，说明每次 `SecItemCopyMatching` 都触发一次对话框。启动路径中 `AppContainer()` 构造与 `model.start()` 会多次读取这些条目，因此 11 到 15 秒的阻塞与「用户逐个点掉十来个对话框」在数量级上吻合。原先记为「对话框等待应答」的方向没有错，具体形式需要修正。

仍有两点未定：

| 未定项 | 说明 |
| --- | --- |
| 执行方式的影响 | 上述 12 次是在执行方用 `exec` 直接运行包内可执行文件时发生的，不是用户双击的路径。两种路径下系统判定访问归属的依据可能不同，需正常启动再测一次 |
| 授权为何不被记住 | 条目只有 3 个，正常应只需 3 次授权。可能是点击的是「允许」而不是「始终允许」，也可能是条目的 ACL 列表已被 ad-hoc 时期反复重建的记录填满。后者与前者的判别方式是查看「访问控制」列表长度 |

判别只需要两个观察：正常打开应用时的弹框次数，以及该条目「访问控制」列表的长度。两者都在真实界面可见。

## 11. 执行 `KEYCHAIN_REVISION_PLAN.md` 的记录

该方案是签名问题暴露出的应用侧缺陷的修订：初始化与状态查询同步读钥匙串、同一流程重复取密钥、失败全部折叠为 nil、后台读取没有交互边界。P0 与 P1 已实施，P2 需用户在真实界面完成。

### 11.1 P0：诊断与干净构建基线

| 动作 | 位置 | 说明 |
| --- | --- | --- |
| 应用内可开启的凭证访问日志 | `Sources/UsageMonitorCore/Providers/CredentialAccessLog.swift` | 写入应用自身的 Application Support 目录，面板底部开关控制，正常启动即可生效。记录构建身份（版本、bundle id、可执行路径、指定要求字符串）、进程、单调与墙钟时间、固定凭证代号、调用目的、交互模式、结果类别、OSStatus、耗时。不记录密钥、会话、指纹、请求头或响应正文 |
| 构建与运行路径分离 | `scripts/build.sh` | bundle 在本地 staging 目录（iCloud 之外）构建并签名，先严格校验，再安装到固定运行路径 `~/Applications/Minget.app` 后再次严格校验；两个嵌套可执行文件单独校验 |
| 归档副本 | `dist/Minget.app` | 普通校验通过；严格校验因 iCloud file provider 重新写入的属性而失败，脚本把该差异显式打印并记录，不再隐藏 |
| 证据更正 | `evidence/logs/09-signed-verification.txt` | 补注该文件「切回 release」一行的内部不一致及其原因（staging 事故），未改动历史记录 |

计划 §2.1 的复核结论全部属实：`dist/Minget.app` 普通校验通过而严格校验失败，原因是包根目录的 `com.apple.FinderInfo`。该属性由 iCloud file provider 在构建后重新写入，构建脚本本已 `xattr -cr` 清理过。因此运行候选包移出 iCloud 路径，这是唯一的根治方式，脚本注释与 `logs/12-keychain-revision-build.txt` 均有记录。

### 11.2 P1：凭证访问改造

| 计划条目 | 实现 |
| --- | --- |
| P1.1 类型化结果 | `CredentialAccessOutcome`：available、missing、interactionRequired、deniedOrCancelled、unavailable(OSStatus)。只有 `errSecItemNotFound` 映射为 missing；`errSecSuccess` 但载荷为空或不可解码映射为 unavailable(errSecDecode)，绝不冒充可用凭证。无法准确区分的状态保留原始 OSStatus |
| P1.2 串行协调器 | `CredentialAccessCoordinator`：一条串行队列执行本进程全部钥匙串调用；同一凭证的并发读取合并到一个任务；不使用「Task 包装同步调用后仍在 MainActor 阻塞」的方式，读取用 continuation 挂起，钥匙串调用在专用队列执行 |
| P1.3 状态只读内存 | `ProviderReading` 增加 `credentialState`，`init`、`report`、`isConfigured`、自动刷新资格判断都只读内存；菜单栏与 Codex 启动不再等待 DeepSeek/GLM 授权 |
| P1.4 交互边界 | 后台读取一律 `.disallowed`；被拒后状态记为 needsAuthorization，该平台自动尝试暂停；面板出现「授权读取」按钮，用户点击后才进行一次受控交互，拒绝或取消后当前周期不再尝试其他入口 |
| P1.5 交互策略实现 | 采用 `SecKeychainSetUserInteractionAllowed`（macOS 10.10 起弃用，但仍是 file-based keychain 的进程级开关；Data Protection keychain 与 `kSecUseAuthenticationUI` 属另一后端，未采用）。先读旧值再关闭，调用后恢复；协调器的串行化保证该窗口不会与交互读取重叠。是否真的一律不再弹窗，需 P2 真实验收，本报告不断言 |
| P1.6 状态缓存 | 成功/缺失/受阻分别记忆；成功值仅存进程内存，退出即释放；拒绝状态等用户明确动作，不被每秒 UI 更新反复探测 |
| P1.7 单次读取 | `DeepSeekProvider.fetchBalances(apiKey:)` 与 `GLMProvider.probeBalanceObservation(apiKey:)` 改为接收调用方传入的密钥，取数与账号指纹共用一次读取；GLM 只加载已选连接模式需要的凭证，控制台模式不再探测旧 API Key |
| P1.8 写失败传播 | `delete` 改为抛出；钥匙串拒绝删除时，引擎返回失败、面板显示「断开失败」，不清缓存、不显示「已删除」；授权拒绝不提示「尚未添加密钥」 |

新文件：`CredentialAccess.swift`、`CredentialAccessLog.swift`、`CredentialAccessCoordinator.swift`。改写：`ProviderCredentialStore.swift`、`ProviderReadings.swift`、`ProviderRefreshEngine.swift`、`ProviderModels.swift`、`ProviderFailure.swift`、`DeepSeekProvider.swift`、`GLMProvider.swift`、`UsageViewModel.swift`、`UsagePanelView.swift`、`UsageMonitorApp.swift`、`build.sh`。

### 11.3 测试

`Tests/UsageMonitorCoreTests/CredentialAccessTests.swift` 新增 14 项：OSStatus 分类（含空载荷与不可解码载荷不得报告为可用）、受阻状态的记忆与不重复探测、用户授权后的重试、并发读取合并为一次访问、内存值复用、删除失败传播、删除不存在的条目不抛错、写入后立即可知、DeepSeek 单次读取、受阻凭证不是"未配置"、控制台模式不探测旧 Key、偏好凭证缺失时回退。全部使用合成凭证与可注入结果，不触碰真实钥匙串。

全量：**359 项通过，0 失败**（四项修订交付时为 345 项）。

### 11.4 验收状态（对照方案 §四）

| 场景 | 状态 |
| --- | --- |
| 初始化与反复读取报告不直接调用凭证存储 | 已由自动测试覆盖（状态查询零钥匙串访问） |
| 多处同时刷新合并为一次读取 | 已由自动测试覆盖 |
| 拒绝/取消停止自动重试、可恢复、不伪报 | 已由自动测试覆盖 |
| 后台轮询、开关面板 20 次无新授权框 | **待真实界面** |
| 完全退出再 open 3 次无重复授权框，真实余额可读取 | **待真实界面** |
| 代码变更后构建：同证书、CDHash 变化、DR 稳定、严格校验 | 已实测：新代码构建后 CDHash 为 `817cc257…`，DR 仍为 `5a48bb2b…`，staging 与运行路径严格校验通过 |
| 换 Key、断开、重新登录的一致性 | 部分由自动测试覆盖（写失败传播、状态一致），真实流程待用户 |
| 锁屏/唤醒不连弹 | **待真实界面** |
| 日志：正常 open 可采集、脱敏通过 | 开关与写入路径已实现，真实 open 采集待用户配合 |

### 11.5 偏离与风险

1. **使用了弃用 API `SecKeychainSetUserInteractionAllowed`**（macOS 10.10 起弃用）。方案 P1.5 允许并有条件地指明了这条路，条件（串行、保存恢复旧值、不与交互读取并发）均已满足。构建会输出弃用警告，属预期。
2. **后台读取是否真的不再弹窗，本环境无法证实**：无真实钥匙串拒绝场景，无屏幕录制。方案 §四 的四行真实项均待用户。若 P2 发现仍有弹窗，下一步是检查条目的访问控制元数据，而不是继续改代码。
3. **运行路径移到 `~/Applications/Minget.app`**，`dist/Minget.app` 降级为归档副本。原因是仓库位于 iCloud 路径，严格校验无法在其产物上长期成立。两个副本共享同一 DR，不会互相覆盖钥匙串授权记录。
4. **`ProviderCredentialStoring.load` 与 `delete` 的签名变更**波及测试：测试中的本地替身与构造调用已同步更新，2 个「删除断言」改用 `.missing`，1 个「重启后仍选中控制台连接」的断言改为验证「未读取未被使用的旧 Key」。

### 11.6 真实验收结果（2026-09-11 23:06-23:27，用户实测 + 应用内日志）

用户按 §11.5 的指引在真实界面执行了验收，结果：

1. **弹框问题解决。** 用户原话：「只弹出一次，授权始终允许后就不弹了」。此前一次启动 12 次弹框的症状消失。
2. **授权后真实读取成功。** 用户偏好 plist 的 `lastSuccessAt` 在授权后更新（23:11:34 与 23:26:45 两次），证明余额读取真实发生，不是伪状态。
3. **诊断日志经真实启动验证。** 用户在面板开启「记录钥匙串访问诊断」后，日志成功记录了构建身份（含指定要求字符串）、进程、交互模式与结果类别。

真实验收同时暴露了一个实现问题，已按证据修正：

**P1.4 的「非交互后台读取」不成立。** 日志对照（`evidence/logs/13-keychain-background-denial.txt`）显示，在 `SecKeychainSetUserInteractionAllowed(false)` 之下，即使 ACL 已含本应用的授权记录，读取仍被拒（`deniedOrCancelled`）；同一台机器、同一证书、同一 DR，交互允许时同样的读取直接成功。若维持原设计，面板会在每次启动时显示「需要授权」，用户每轮都得按一次按钮。

**修正**：默认读取路径改回交互允许，防弹框循环改由两条机制保证——稳定证书身份（授权按 DR 记住，跨构建有效）与协调器的结果记忆（自动用途不重试被拒的凭证）。该偏离符合方案 P1.5 自身的验证要求（「经真实验证有效」未通过则不采用），并已记录于 `logs/13` 与代码注释。`.disallowed` 交互模式保留在接口与测试中，供未来需要严格禁 UI 的场景使用。

修正后的端到端验证：15:26:41 启动新构建（CDHash 变化、DR 不变），15:26:44 两项凭证均 `available`，15:26:45 真实取数成功写入缓存，全程无「需要授权」状态。用户陈述无新弹框；日志无法区分静默成功与用户应答，此项以用户陈述为准（证据边界已记录于 `logs/13`）。

另修复一处小缺陷：诊断开关的关闭动作被自身 guard 吞掉，日志里只出现「enabled」不出现「disabled」，导致开关状态无法从日志还原。现两种状态都记录。

2026-09-12 追加验收：用户确认点击菜单栏详情后，再点击桌面或其他应用，详情立即收起且原点击有效。外部点击收起的核心场景通过。后台轮询、换 Key 与锁屏唤醒继续作为后续观察项，不构成 1.0.2 发布阻断。

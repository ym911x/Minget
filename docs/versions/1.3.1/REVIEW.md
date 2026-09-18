# 1.3.1 审核状态

## 当前结论

状态：Codex 已完成 R1 复核。生产代码修复、真实辅助功能树实测、451 项全量测试、Release 构建、固定运行路径严格签名和脱敏渲染检查均通过。用户于 2026-09-18 明确授权发布；提交 `0aff792`、标签 `v1.3.1`、GitHub Release 和发布提交 CI 均已完成。当前没有已知的生产代码发布阻断，真实界面及明确列出的真实服务项目继续保持待验收。

四项稳定性修补符合 `REQUIREMENTS.md`：双 Profile 按完成顺序发布，点火确认使用三态并在证据不足时重试一次，Command Code 以 credits 为必须主数据，缓存副文案明确显示“缓存”。R1 已把设置入口移出合并的辅助功能元素，系统辅助功能树中可以单独聚焦和激活。

## 独立复核证据（2026-09-18）

| 检查 | Codex 实际结果 |
| --- | --- |
| R1 代码结构 | `CommandCodeHeaderIdentity` 只包含 Logo、标题和副文案；`.combine` 只作用于该非交互视图。设置 `Button` 是 header 的独立兄弟元素，卡片根使用 `.contain` |
| R1 真实 AX 树 | 临时 GUI harness 直接编译当前 Core 与 App 源码并使用合成报告；读到 `AXStaticText desc=Command Code value=未连接` 和独立 `AXLink desc=前往设置`；对链接执行 `AXPress` 返回成功，产品闭包恰好触发 1 次 |
| R1 定向测试 | `CommandCodeAccessibilityTests`、`DetailPanelLayoutTests`、`DetailEvidenceRenderTests` 共 36 项执行，35 项通过、1 项明确跳过、0 失败 |
| 全量 Core | 331 项通过，0 失败 |
| 全量 App | 120 项执行，119 项通过、1 项 AX 树测试跳过、0 失败 |
| 总计 | 451 项执行，450 项通过、1 项跳过、0 失败 |
| Release 构建 | `./scripts/build.sh` 通过，`CFBundleShortVersionString = 1.3.1` |
| 严格签名 | 固定运行路径单独执行 `codesign --verify --strict --verbose=2`，退出码 0，`valid on disk`，满足 Designated Requirement |
| 自动渲染 | 目检 06／07 浅色与深色证据；正常、缓存、统计不可用、周期未知及无用量状态无可见截断，“前往设置”独立显示 |
| 网络与凭证边界 | 未执行真实点火或模型请求；未主动执行真实服务验收；未读取全局认证文件、浏览器会话或原始响应 |
| 历史资料 | `docs/archive/v1.0/` 未修改；开工前两张 1.0.2 evidence PNG 和未跟踪目录仍保留为范围外改动 |

## R1 复验结论：已解决

生产修复符合固定方案：包含设置按钮的 header 不再使用 `.combine`，Logo、标题与副文案集中在非交互的 `CommandCodeHeaderIdentity` 中，按钮保留自己的标题、角色和动作。独立 GUI harness 使用本轮源码、合成数据和真实系统 AX API 验证了以下结果：

```text
PASS identity=AXStaticText:Command Code:未连接
PASS entry=AXLink:前往设置:
PASS AXPress activated=1
```

该 harness 没有构造 `UsageViewModel`，没有访问网络、Keychain 或真实服务。它位于临时目录，没有作为仓库内回归测试保存，因此仓库内 XCTest 的跳过仍须准确记作“未执行”。

### 对上一轮证据的更正

上一轮最小 `NSHostingView` 检查在不可观测环境中返回空树。修复前后使用相同方法都会得到空树，因此该结果不能证明按钮动作丢失，现撤回这条证据。

实施者后续记录显示，旧结构会把入口和名称合并进 `Command Code` 元素，但合并元素仍可能转发 `AXPress`。因此 R1 的准确问题是“设置入口失去独立元素和名称”，不应继续表述为“动作必然完全失效”。修复方式与结论不受影响。

## 非阻断问题

### R2：仓库内 AX XCTest 会复用旧窗口列表

等级：P2，测试维护问题，不阻断当前生产候选。

`CommandCodeAccessibilityTests.swift` 在第 148 至 152 行先创建一扇无闭包状态的窗口并缓存 `windows`，随后在第 162 至 168 行为两个状态创建新窗口，但第 170 行仍从旧 `windows` 读取节点。若 XCTest 将来获得可观测的 AX 窗口，它会向旧窗口中的入口发送 `AXPress`，无法触发循环内的 `activated` 闭包，测试会在第 189 行失败。

建议后续修正：每个状态 `host` 完成后重新从 `AXUIElementCreateApplication(getpid())` 获取窗口，只遍历本次新窗口；切换状态前关闭上一扇窗口。当前独立 GUI harness 已直接验证生产行为，所以该测试缺陷不推翻 R1 的实测结论。

另有两处说明文字应随下次维护对齐：`UsagePanelView.swift` 第 720 至 721 行仍写成合并后没有 `AXPress`；`IMPLEMENTATION_REPORT.md` 对 AX XCTest 的实现摘要写成查找 `AXButton` 和 `AXActionNames`，实际用例按名称查找元素并直接执行 `AXPress`。两项都不影响运行。

编译继续出现既有 Security.framework 废弃 API 警告和一个既有“is test is always true”测试警告；本轮未新增，不阻断 1.3.1。

## 已通过的实现审核

- [x] 差异主体只覆盖 1.3.1 任务、测试与必要文档
- [x] Profile 完成顺序测试使用可控阻塞点，不依赖随机调度
- [x] stop/cancel 后无迟到状态发布
- [x] 点火三态真值表、第二次刷新次数和等待中停止均有测试
- [x] fake 点火进程退出与回收无回归
- [x] credits 必须、summary/subscription 可选的边界准确
- [x] summary 失败不产生伪造月度总额或统计数字
- [x] stale + plan 的自动渲染明确可见且未截断
- [x] 四种详情页尺寸、菜单栏三来源和设置页自动检查无布局回归
- [x] Command Code 设置入口在真实 AX 树中独立可达并可激活
- [x] 全量测试、Release 构建和严格签名通过
- [x] 签名包冷启动和退出清理通过
- [x] 无敏感原始响应或子进程输出进入 1.3.1 变更
- [x] 未执行真实点火或模型请求
- [x] 用户明确授权后完成 `main` 推送、`v1.3.1` 标签、GitHub Release 和发布提交 CI
- [ ] 用户真实界面验收

## 审核边界

本轮没有执行真实点火或模型请求。自动渲染和 AX harness 使用合成数据；真实 Command Code 缓存状态、真实 DeepSeek 菜单栏余额、A/B 真实点火和机器完整重启仍不能标记为通过。发布操作只在用户明确授权后执行。

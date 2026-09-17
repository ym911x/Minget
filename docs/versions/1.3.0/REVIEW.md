# 1.3.0 审核状态

## 当前结论

状态：第三轮界面微调已实现并通过独立复核。440 pt 详情页、周期分组、Command Code 文案精简、DeepSeek 菜单栏和单行详情卡已通过定向渲染、425 项全量测试、Release 构建、严格签名及签名包冷启动检查；用户于 2026-09-17 提供最终真实运行截图并确认详情页修订完成。真实 DeepSeek 菜单栏余额与 A/B 两次真实点火仍待后续验证。

第三轮检查结果：`440 × 552 / 498 / 384 / 330 pt` 四种页面尺寸、ChatGPT/Command Code 4 pt 周期间距、Command Code `$余额 / $总计` 与绝对重置时间、DeepSeek `DS CNY 123.45` 大字号菜单栏、`416 × 48 pt` 单行卡片均已由自动断言与脱敏渲染覆盖。

首轮 384 项自动测试、Release 构建与严格签名虽然通过，但不能覆盖已确认的启动、视觉、屏幕边界和点火生命周期缺陷。实现记录见 `IMPLEMENTATION_REPORT.md`。本轮未执行任何真实点火请求；用户已明确授权提交、推送、标签和 GitHub Release。

发布复核：提交 `827ca8b`、`v1.3.0` 标签与正式 GitHub Release 已同步；发布提交的 GitHub Actions CI #17 通过，公开脱敏截图与本地文件校验和一致。

## 2026-09-17 阻断项

| 编号 | 等级 | 实际证据 | 修订要求 |
| --- | --- | --- | --- |
| R1 | P0 | 冷启动出现内容为空的设置窗口；源码仍注册 `Settings { EmptyView() }` | 改用显式 AppKit lifecycle，冷启动不创建空 Scene |
| R2 | P0 | 用户截图中 720 pt 双列弹层右侧超出屏幕 | 改为 520 pt 单列；show 前设置尺寸；以状态按钮中点锚定并做屏幕容纳降级 |
| R3 | P0 | ChatGPT 卡片缺失 1.2.1 的 5/7 段重置时间轨道 | 恢复额度轨道 + 时间轨道双层结构 |
| R4 | P1 | ChatGPT 信息层级和风格偏离用户已确认的 1.2.1 | 以脱敏 1.2.1 截图为唯一视觉基线，压缩尺寸但不删信息 |
| R5 | P1 | Command Code 使用 `used / limit`，轨道向右增长，且没有重置时间线 | 改用 `remaining / limit`；增加 5/7 段和无刻度月度时间线 |
| R6 | P1 | `UsageViewModel.stop()` 取消 fire Task，但同步 `Process` 不响应 Task cancellation | `ChatGPTFireService.stopAll()` 终止并回收所有 active process |
| R7 | P1 | 点火后 `.success` 未检查 `FetchResult.isLive`，缓存可能跳过第二次刷新 | 只有 live 结果可确认；缓存必须重试且不能确认新窗口 |

详细设计、尺寸、文案、测试和实施顺序见 `REVISION_SPEC.md`。

## 实现落点（已由 Codex 复核）

- `AppContainer` 由单一 `codexService` 改为 `CodexProfilesCoordinator`，两个 Profile 各自拥有一个长生命周期 `UsageService`。
- `UsageViewModel` 发布 `[CodexProfileViewState]`，一轮内并行刷新两个 Profile；`displayState` / `connectionState` / `codexAccount` 单值形态已移除。
- `UsageCache` 的 last-known account 改为按 Profile 保存，并新增 v3 `profileID + accountID` 命名空间；v2 缓存按「同 ID 才迁移、否则删除、B 永不接收」处理。
- `UsageService` 通过 `childEnvironment(base:codexHome:)` 为子进程复制环境并覆盖 `CODEX_HOME`；`CodexLocator` 未改动。
- 菜单栏构建器改为接收已解析来源，支持 ChatGPT A、ChatGPT B 与 DeepSeek 三来源。
- 首轮详情页的 720 pt 双列方案已被真实界面验收否决；当前实现按第三轮规格固定为 440 pt 单列。
- 应用内点火直接执行固定 Codex CLI 参数并丢弃输出，不调用 `minget-fire`，不产生 raw log。

## 已确认的架构事实

- `AppContainer` 当前只创建一个 `UsageService`。
- `UsageViewModel` 当前发布单一 `displayState`、`connectionState` 和 `codexAccount`。
- `UsageService` 已支持账号归属缓存，但 `UsageCache` 的 last-known account 是全局单值。
- `JSONRPCClient` 构造器已支持子进程环境，生产 wiring 尚未为两个账号分别设置 `CODEX_HOME`。
- 菜单栏构建器当前只接受 Codex `UsageDisplay`，并固定生成双重置时间条。
- `DetailPreferences` 当前只管理 DeepSeek 和 Command Code 详情显示，不管理菜单栏来源。
- 方案评审时的 1.2.1 基线是 420 pt 单列；首轮 1.3.0 采用 720 pt 双列。真实界面验收否决该双列方案，第二轮先恢复为 520 pt 单列，第三轮最终收窄为 440 pt 单列。
- 现有 `minget-fire` 已验证固定 Codex CLI、隔离 `CODEX_HOME`、Luna、`reasoning=none` 和 read-only sandbox；A/B 已真实执行成功。由于脚本会写完整 CLI 输出和 session id，应用内按钮改为直接执行同参数并丢弃输出，脚本只保留给既有 LaunchAgent。
- 现有 raw 点火日志包含 Codex CLI session 信息，不适合作为 Minget 的产品数据源。

以上为方案评审时的事实记录，其中前两条已在本轮实现中改变，保留原文以保持历史可核对。

## 本轮设计判断

### 采用

- 可扩展 Profile 数据模型，1.3.0 UI 先落地两个账号。
- 每 Profile 一个长生命周期 app-server。
- 菜单栏一次选择一个来源。
- DeepSeek 多币种显式选择，不换算、不合计。
- 详情页固定为单列无滚动布局：A、B、DeepSeek、Command Code 各占一排，四卡全开为 440 × 552 pt。
- 点火由应用直接运行官方 Codex CLI 固定参数并丢弃输出，不调用外部脚本。
- 点火后刷新额度，并把“请求成功”与“新窗口已确认”分开。

### 不采用

- 让两个账号共用一个 app-server 并在请求前切换环境。
- 继续使用单一 `displayState` 后在 UI 临时替换数据。
- 用账号邮箱作为 Profile 主键。
- 从 raw log 解析 session、token 或成功状态。
- 在 1.3.0 中同时实现 launchd 编辑、自动唤醒、Fire All 和历史页。
- DeepSeek 多币种自动求和或固定猜测 CNY/USD 为主币种。

## 主要风险与审核点

| 风险 | 等级 | 审核要求 |
| --- | --- | --- |
| 两个 Profile 共用全局 last-known account 导致串号 | 高 | 必须有 Profile + account 双重隔离测试和真实 A/B 差异核对 |
| 两个子进程停止不完整 | 高 | 并发刷新退出、启动中退出、三次真实重启检查 |
| Minget 间接处理 Codex 认证目录 | 高 | 只允许传 `CODEX_HOME` 环境；源码搜索不得存在认证 JSON 读取 |
| 点火按钮造成真实额度消耗 | 高 | 用户确认后执行；自动测试全部使用 fake executable |
| `exit 0` 被误报为新窗口已启动 | 高 | 只有服务端窗口证据变化才显示确认 |
| DeepSeek 多币种显示错误 | 中 | 明确币种选择，不换算、不合计，缺失不显示零 |
| 详情页四卡片在固定窗口截断 | 高 | 锁定 440 × 552 / 498 / 384 / 330 四种页面尺寸和卡片高度，自动检查无滚动容器、无截断、无横向越界 |
| 菜单栏标签变长进入刘海 | 中 | 三来源完整/紧凑宽度测试和真实几何验收 |
| 个人路径或账号进入公开仓库 | 高 | 默认相对路径、脱敏截图、发布前敏感信息扫描 |

## 当前环境状态

- Xcode 27 license 已于 2026-09-16 由用户输入 `agree` 完成，`swift --version` 和系统 `git status` 已恢复正常。
- 裸 `swift test` 在 iCloud 内 `.build/out` 因 File Provider 扩展属性导致测试包签名失败；改用 `/tmp` 下仓库外 `--scratch-path` 后测试可完整运行。基线为 271 项 Core + 39 项 App，共 310 项、0 失败。
- 1.3.0 首轮实现后为 317 项 Core + 67 项 App，共 384 项、0 失败；`./scripts/build.sh` 的 Release 构建、staging 严格签名和固定运行路径严格签名均通过。
- 回归修订后为 325 项 Core + 99 项 App，共 424 项、0 失败；Release 构建与三级严格签名再次通过，运行包版本 `1.3.0`。
- 第三轮微调后为 325 项 Core + 100 项 App，共 425 项、0 失败；Release 构建与严格签名再次通过，运行包版本 `1.3.0`。定向布局、菜单栏、状态项和渲染测试另计 99 项，0 失败。
- 签名包实测（首轮）：启动后出现两个兄弟 `codex app-server` 子进程，分别运行在 `~/.codex-minget-a` 与 `~/.codex-minget-b`；三次完整启动/退出后无遗留自有子进程。该证据只读取子进程自身环境，未读取两个 `CODEX_HOME` 目录内容。
- 签名包实测（修订后）：冷启动后该进程拥有的 layer-0 窗口数为 `0`，即不再出现空的「设置」窗口；两个子进程仍分别运行在 `~/.codex-minget-a` 与 `~/.codex-minget-b`；退出后两者都被回收，全机范围内没有进程仍引用 `~/.codex-minget-*`。该检查由 `StartupWindowTests` 自动执行，本机已实际通过。
- 工作树已有与本版本无关的用户改动和未跟踪文件，实施时必须保留并避免纳入 1.3.0 提交。其中 `docs/versions/1.0.2/evidence/01`、`02` 两张图在开工前即为用户未提交改动，基线测试运行重绘了历史 evidence 目录，处置过程记录在 `IMPLEMENTATION_REPORT.md` 的「基线运行造成的实际影响」。

## Codex 独立审核

- [x] 代码差异与范围控制
- [x] 双 Profile 数据流和缓存迁移
- [x] 子进程环境与停止路径
- [x] 点火服务命令边界和日志边界
- [x] 菜单栏三来源及 DeepSeek 多币种语义
- [x] 自动测试、Release 构建和严格签名
- [x] 两个真实 ChatGPT 账号额度
- [ ] 两个真实点火按钮
- [ ] 真实 DeepSeek 菜单栏余额
- [x] 真实详情页界面
- [ ] 菜单栏真实切换
- [x] 版本文档、测试数和公开素材一致性

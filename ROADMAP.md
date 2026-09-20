# 后续版本路线图

产品名称：明明有数 · Minget

产品定位：统一查看和管理个人 AI 服务使用状态、可用资源与成本信息的 macOS 菜单栏工具。

## 当前基线

`v1.0.0` 已冻结。新功能和行为调整从下一版本开始记录，不回写 v1.0 的历史方案、任务单和审核报告。

`v1.1.0` 已完成：详情页重构、OpenAI 原始 Blossom 资源与套餐显示、DeepSeek 双标识与紧凑官方状态、系统语言名称、智谱整行卡片、无滚动精简设置和显示开关已经落地，371 项自动测试与构建通过，用户已确认当前详情页体验。实施资料见 `docs/versions/1.1.0/`。

`v1.1.1` 已完成并发布：GLM 运行时、WebKit 登录和界面入口已移除；旧版 GLM 本应用数据在启动时迁移清理；设置页合并为 OpenAI Codex 与 DeepSeek 的单一服务模块。真实界面检查已完成，真实服务账号未在本轮重新请求，资料见 `docs/versions/1.1.1/`。

`v1.1.2` 已完成并发布：菜单栏只保留完整和紧凑双额度模式；OpenAI 详情卡增加只读可用重置摘要；DeepSeek 详情卡把余额移到品牌同列并保留 Logo 下状态；详情页改为固定整页无滚动布局。301 项自动测试通过，Release 构建、真实界面验收和发布记录见 `docs/versions/1.1.2/`，发布页为 [GitHub Release v1.1.2](https://github.com/ym911x/Minget/releases/tag/v1.1.2)。

`v1.2.0` 已发布：详情页加入可隐藏的 Command Code 用量卡片，菜单栏仍只显示 Codex。API Key 由用户在应用内提供并仅存于 Keychain；请求边界限定为三个只读 `/alpha` 路径，模型端点和跨域重定向在本地拒绝。309 项自动测试、Release 构建和严格签名通过，真实 API Key 已返回用量；修复后的持续显示和完整重启仍待用户复验。资料位于 `docs/versions/1.2.0/`，发布页为 [GitHub Release v1.2.0](https://github.com/ym911x/Minget/releases/tag/v1.2.0)。

`v1.2.1` 已完成：Command Code 卡片金额统一为两位小数，并移除卡片内重复的相对更新时间，保留详情页顶部的全局刷新状态。310 项自动化测试、Release 构建和严格签名检查通过，真实界面已由用户确认。资料位于 `docs/versions/1.2.1/`，发布页为 [GitHub Release v1.2.1](https://github.com/ym911x/Minget/releases/tag/v1.2.1)。

`v1.3.0` 已完成并发布。首轮的 720 pt 双列和启动空窗口已经修复；用户后续实测推动详情页收窄为 440 pt 单列，ChatGPT 与 Command Code 周期块增加克制间距，Command Code 额度文字精简为余额/总计且非月度只显示绝对重置时间，DeepSeek 菜单栏移除“余额”二字并放大，详情卡改成 48 pt 单行。双轨语义、屏幕容纳降级、点火退出清理与实时确认规则继续保持。425 项自动测试、Release 构建、严格签名和真实详情页验收通过。真实 DeepSeek 菜单栏余额与 A/B 两次真实点火仍待后续验证。资料位于 `docs/versions/1.3.0/`，发布页为 [GitHub Release v1.3.0](https://github.com/ym911x/Minget/releases/tag/v1.3.0)。

`v1.3.1` 已完成并发布：两个 ChatGPT Profile 现在按完成顺序独立发布状态，快速账号不再被慢速账号延迟；点火结果细分为“新窗口已确认”“请求成功，窗口未变化”和“请求成功，暂无法确认”，第一次确认未成立时统一在 5 秒后再做一次只读刷新；Command Code 改为 credits 必须、summary/subscriptions 可选，辅助接口失败不再遮住已取得的额度，套餐名存在时明确标识缓存。Codex 复核发现的 Command Code 设置入口辅助功能阻断已修复，并以真实 AX 树独立验证。451 项自动化测试执行（Core 331、App 120），450 项通过、1 项跳过、0 项失败，Release 构建、严格签名和发布提交 CI 通过。窗口尺寸、菜单栏格式和凭证边界保持 1.3.0 不变；真实界面、真实 DeepSeek 菜单栏余额、A/B 真实点火和机器重启复验仍待用户执行。资料位于 `docs/versions/1.3.1/`，发布页为 [GitHub Release v1.3.1](https://github.com/ym911x/Minget/releases/tag/v1.3.1)。

`v1.3.2` 已完成并发布：点火确认只读额度不读身份，结果追加实测差值与最近 3 次内存历史；详情页时钟降为 30 秒，ChatGPT 按 30/60/120 秒退避，Command Code 辅助组件独立复用 15 分钟，唤醒先探活再按失败 Profile 完整刷新。版本加入 OpenAI A、OpenAI B、Command Code 每日多时点点火计划，以及 Command Code 卡片的手动点火；Command Code 仅在用户确认或勾选计划后，使用 Keychain Key 和隔离 `HOME` 调用官方 CLI 最小请求。506 项自动测试执行，505 通过、1 跳过、0 失败；Release arm64 构建与严格签名通过，Command Code 真实手动点火已由用户确认成功。用户于 2026-09-20 授权发布；真实睡眠/唤醒、完整界面与 Command Code 定时点火转为发布后验证项。资料位于 `docs/versions/1.3.2/`，发布页为 [GitHub Release v1.3.2](https://github.com/ym911x/Minget/releases/tag/v1.3.2)。

`v1.4.0` 已完成并发布：应用内与外部 Command Code 点火路径统一使用 `deepseek/deepseek-v4.1-flash`；菜单栏当前选中的 ChatGPT/DeepSeek 来源支持可配置阈值与 15/30/60 秒低额度补充刷新。513 项自动测试执行，512 通过、1 跳过、0 失败；Release 构建、严格签名、签名包退出/重启、设置页明暗布局和发布提交 CI 通过。真实低额度服务轮询保留为发布后现场观察项。资料位于 `docs/versions/1.4.0/`，发布页为 [GitHub Release v1.4.0](https://github.com/ym911x/Minget/releases/tag/v1.4.0)。

## 候选方向

以下内容作为迭代候选，尚未确定版本号和优先级：

- 改善 DeepSeek 密钥输入框的焦点、保存反馈和保存后的自动关闭行为。
- 增加第三个及更多 ChatGPT Account Profile 的配置界面；1.3.0 的底层模型已按可扩展设计，但只落地两个只读 Profile。
- 增加 Fire All、可见的长期点火历史和 LaunchAgent 管理；1.3.2 只保留最近 3 条运行时历史。
- 增加余额过低、额度临近耗尽和连接失效的本地通知。
- 制作可分发的签名、公证和更新流程。
- 增加版本内诊断导出，默认排除 Cookie、令牌和 API Key。

## 新版本启动流程

1. 确定本轮范围、版本号和明确不做的事项。
2. 在 `docs/versions/<版本号>/` 新建需求、实施计划和验收标准。
3. Claude Code 按任务单实现，Codex 独立检查差异、测试结果和实际运行表现。
4. 用户完成真实账号和真实界面的最终体验验收。
5. 更新 `CHANGELOG.md`、`VERSION` 和归档清单，并建立对应 Git 标签。

---

## English summary

The `v1.0.0` baseline is frozen. `v1.3.0` is released with an explicit AppKit entry, a fixed 440 pt single column, restored ChatGPT dual tracks, simplified Command Code balance/reset copy, a single-line DeepSeek card, enlarged DeepSeek menu-bar typography, screen-aware panel fallback, and complete fire-child shutdown. `v1.3.1` is released with per-account publishing as each refresh finishes, a three-outcome fire confirmation with a single 5 s retry, and layered Command Code tolerance where only `credits` is required. Real-interface and explicitly listed real-service checks remain pending. Candidate directions include improved DeepSeek credential UX, more account profiles, scheduled firing, local notifications, notarized distribution, and privacy-safe diagnostics export.

Each future version receives its own requirements, implementation plan, review, and acceptance records under `docs/versions/<version>/`. Historical v1.0 documents remain unchanged.

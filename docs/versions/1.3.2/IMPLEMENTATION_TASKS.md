# 1.3.2 实施任务

状态：原定优化和新增的点火计划／Command Code 点火已实现，全量自动验证已完成，用户已接受发布。未完成的真机项目保留为发布后验证，不阻断 1.3.2。

本文记录本版本实际执行的任务边界。需求与状态语义以 `REQUIREMENTS.md` 为准。

## 1. 点火确认与 footer

- [x] 分类接口改为 `classify(previousReset:previousWasLive:observations:)`；nil 或非 live 前值固定返回「暂无法确认」。
- [x] 点火后确认改走 `handshake + rateLimits/read`，不读身份、不改变归属、不绕开 failure episode。
- [x] 结果与差值拆为独立文本，结果布局优先级最高、差值最低、左侧重置摘要居中；辅助功能值与可见组合一致。
- [x] 每 Profile 内存保留最近 3 次结果、完成时间和可选差值；不持久化、不记录日志。
- [x] 保持 OpenAI 三态、60 秒阈值、2 秒/5 秒等待、CLI 参数和 120 秒超时不变。

## 2. 定时点火与 Command Code 点火

- [x] 设置页增加 OpenAI A、OpenAI B、Command Code 三组每日点火计划，支持添加多个时间、勾选启用、修改和删除。
- [x] 计划与每条已执行日期本地持久化；10 分钟补跑、跨重启去重、同目标忙时不叠加。
- [x] 相邻已启用时间小于 5 小时时显示橙色警告，包含跨午夜检查。
- [x] Command Code 卡片增加独立点火按钮、固定确认对话框、三态结果、差值和最近 3 条内存历史。
- [x] 新增 `CommandCodeFireService`：官方 CLI 直启、固定最小参数、每次唯一且事后删除的隔离 `HOME`、Key 只进子进程环境、输出丢弃、单实例和超时回收。
- [x] CLI 成功后仅读 `credits` 确认 5 小时 `resetsAt`；手动 Keychain 访问允许交互，定时访问禁止交互。
- [x] Command Code 卡片增高至 416 × 176 pt，详情页对应高度为 566/512/384/330 pt；设置页为 520 × 700 pt 且仅使用一个滚动区。

## 3. Command Code 辅助缓存

- [x] 缓存按 API Key 完整 SHA-256 摘要隔离；公开标签继续使用短指纹，原始 Key 不进缓存。
- [x] summary/subscription 分别存值与最后成功时间，独立判断 15 分钟复用；credits 每轮必读。
- [x] 单路失败保留旧值并标记缓存，不推进时间戳，下一轮只重试失败或已过期组件。
- [x] 手动刷新与重连强制刷新两路辅助接口。
- [x] `ProviderUsageComponentFreshness` 可选持久化，旧缓存直接兼容解码。
- [x] 套餐、统计和使用到缓存辅助字段的月度行分别显示缓存语义；5 小时/周额度保持 credits 的实时状态。
- [x] 强制策略随任务传递；同代 force 在自动读取后补强制全量读取，不同凭证代次不合并，旧代结果不提交。

## 4. 唤醒探活与刷新节奏

- [x] `probeRateLimitsAfterWake` 只用现有运行 client 做 handshake + rate limits，不启动、不重启、不读身份。
- [x] 健康 Profile 只更新额度；失败 Profile 关闭失效 client 后才进入普通刷新；熔断、读取中、停止态均 suppressed。
- [x] A/B 并行探活并逐个发布，只对失败项完整刷新。
- [x] 唤醒与定时轮询保持 30 秒互斥；停止时取消任务、timer 并等待服务 drain。
- [x] `refreshInterval` 成为真实基础间隔注入值；生产节奏保持临近 30 秒、无数据 60 秒、远离 120 秒。
- [x] 详情页时钟改为 30 秒，菜单栏倒计时仍按当前时间绘制；宽度只在尺寸签名变化时重测。

## 5. R2、测试与文档

- [x] AX XCTest 每轮记录旧窗口集合，只遍历本轮新增窗口并关闭；无可观测 AX 窗口时明确跳过。
- [x] 仓库外独立 GUI harness 直接编译当前源码，验证 `前往设置`/`查看设置` 为独立 AXLink，身份为 AXStaticText，两次按压各触发一次。
- [x] 回归覆盖非 live 前值、跨凭证缓存、组件分别过期、部分失败重试、force/in-flight、凭证代次、旧缓存解码、唤醒探活和 stop。
- [x] 回归覆盖三个计划目标、多时间、持久化去重、10 分钟补跑、小于 5 小时警告、fake Command Code CLI 和 credits-only 确认。
- [x] fixture 覆盖点火三态、长左侧文案、长/短/无差值，以及 Command Code 组件缓存，浅色/深色均输出到 `/tmp` 并目检。
- [x] 更新版本资料、根目录说明和端点边界；未修改 `docs/archive/v1.0/`。

## 6. 验证结果

- [x] Core 360 项通过；App 146 项执行、145 通过、1 项 AX XCTest 明确跳过；合计 506 项执行、505 通过、1 跳过、0 失败。
- [x] Release：arm64、版本 1.3.2、staging/install/archive 严格签名通过。
- [x] `git diff --check`、端点/敏感信息/冻结目录检查、CLI 临时目录清理和进程归属重新验证。
- [ ] 发布后：用户在真实签名包内完成完整界面目检。
- [ ] 发布后：用户触发一次真实睡眠/唤醒并确认 30 秒内恢复、无刷新风暴、无串号、无孤儿进程。
- [x] 用户在 PATH 修复签名包内执行一次 Command Code 手动点火并确认成功。
- [ ] 发布后：用户在签名包内执行一次短时 Command Code 定时点火。

## 7. 边界

自动验证不执行真实点火或模型请求；真实 Command Code 手动点火由用户执行并确认成功。发布动作已由用户于 2026-09-20 明确授权。不读取全局 Codex/Claude/Command Code 认证文件、浏览器会话或现有隔离目录内容。

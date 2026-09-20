# 1.4.0 验收台账

当前状态：发布验收、标签、GitHub Release 和发布提交 CI 均已完成。真实低额度服务轮询保留为发布后现场观察项。

| 项目 | 当前状态 | 验收依据 |
| --- | --- | --- |
| 应用内 Command Code 模型 | 自动通过 | 固定参数断言为 `deepseek/deepseek-v4.1-flash` |
| 外部 `minget-fire` 模型一致性 | 只读核对通过 | `/Users/yuyimeng/.local/bin/minget-fire` 的 `--model` 为同一标识；未改外部文件 |
| 设置默认值与持久化 | 自动通过 | UserDefaults 读写、恢复默认、无凭证键测试 |
| ChatGPT 严格阈值 | 自动通过 | 50%/15% 恰好边界不触发，低于阈值且任一窗口触发 |
| DeepSeek CNY 规则 | 自动通过 | 15.00 恰好不触发、14.99 触发、USD 不套用 CNY 阈值 |
| 当前菜单栏来源隔离 | 自动通过 | 选择 Profile/DeepSeek 分支只生成对应补充决策 |
| 无效输入 fail-closed | 自动通过 | 无效金额不触发；周期和百分比归一化 |
| timer 取消与停止清理 | 自动通过 | 安装、来源切换取消、重新启用、关闭开关和 stop 清理均有确定性回归 |
| 全量自动测试 | 通过 | Core 360；App 153（152 通过、1 项既有 AX XCTest 明确跳过）；0 失败 |
| Release 构建与严格签名 | 通过 | `scripts/build.sh`；版本 1.4.0；staging/install/archive 严格签名通过 |
| 已安装签名包生命周期 | 通过 | 真实退出、重新启动和进程存活检查通过；固定模型字符串核对通过 |
| 设置页布局 | 通过 | 明暗两套确定性渲染检查，新控件无截断或重叠 |
| GitHub 发布 | 通过 | 发布提交 `b9c2701`；annotated tag `v1.4.0`；正式 Release；CI `35514875456` 成功 |
| 真实菜单栏低额度服务轮询 | 发布后观察 | 不通过人为制造额度条件触发；策略、来源切换和 timer 生命周期由 fake service 回归覆盖 |
| LaunchAgent 时间与真实点火 | 本轮不改 | 不修改外部 plist；另行按用户授权验收 |

## 仍未标记通过的项目

- 确定性渲染和 fake service 回归不能替代真实低额度服务轮询的现场观察。
- 本轮没有调用真实模型请求，也没有消耗 Command Code、ChatGPT 或 DeepSeek 额度。

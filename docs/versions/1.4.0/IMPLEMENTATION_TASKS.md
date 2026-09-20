# 1.4.0 实施任务

状态：代码、自动验证、Release 构建、发布验收、标签和 GitHub Release 已完成。需求与边界以 `REQUIREMENTS.md` 为准。

## 1. 模型统一

- [x] 将 `CommandCodeFireService.modelName` 与应用内固定参数更新为 `deepseek/deepseek-v4.1-flash`。
- [x] 更新固定参数回归测试，确保旧 `deepseek/deepseek-v4-flash` 不再进入应用内点火路径。
- [x] 只读核对 `/Users/yuyimeng/.local/bin/minget-fire` 的 Command Code 路径使用相同模型；不改其外部调度文件。

## 2. 设置与策略

- [x] 在 `MenuBarPreferences` 中增加低额度加速开关、周期、5 小时阈值、周阈值和 DeepSeek CNY 阈值的版本化 UserDefaults 键。
- [x] 提供默认值、合法范围、数值归一化、无效金额 fail-closed 和恢复默认值。
- [x] 新增纯 `MenuBarRefreshPolicy`，覆盖严格小于边界、ChatGPT OR、DeepSeek CNY 与当前来源选择。
- [x] 设置页在菜单栏显示区域增加周期、阈值、金额输入、当前状态和恢复默认控件。

## 3. 调度接入

- [x] 为菜单栏当前来源增加独立补充 timer，不改变详情页与提供方的既有 timer。
- [x] ChatGPT 补充刷新只调用选中的 Profile；DeepSeek 补充刷新只调用 DeepSeek Provider。
- [x] 复用已有进行中状态与停止清理，切换来源时重算并取消不再适用的 timer。
- [x] 数据恢复正常后停止补充 timer，避免长期高频轮询。

## 4. 测试、构建与资料

- [x] 增加偏好持久化、归一化、恢复默认和凭证/缓存范围测试。
- [x] 增加 ChatGPT/DeepSeek 阈值边界、当前来源隔离、禁用和无效输入测试。
- [x] 更新 `VERSION`、README、CHANGELOG、ROADMAP 和本版本资料。
- [x] Release 构建、严格签名、安装包启动/退出检查，以及设置页明暗确定性布局检查。
- [x] 补充 timer 的安装、来源切换取消、重新启用、关闭开关和 stop 清理使用 fake service 确定性验收。
- [ ] 真实低额度服务轮询现场观察；不通过人为制造额度条件触发，不阻断本次源码发布。

## 5. 验证记录

最终 `swift test --disable-sandbox --scratch-path /tmp/minget-140-release-tests` 已完成：Core 360 项通过；App 153 项执行，152 项通过、1 项既有 AX XCTest 明确跳过、0 项失败。合计 513 项执行，512 项通过、1 项跳过、0 项失败。

最终 `scripts/build.sh` 使用独立 `/tmp` scratch/staging/archive 目录完成 Release arm64 构建；staging、`~/Applications/Minget.app` 与 archive 均通过严格签名。已安装包完成真实退出与重新启动，版本为 1.4.0，运行二进制包含固定模型 `deepseek/deepseek-v4.1-flash`。

发布提交 `b9c2701`、annotated tag `v1.4.0` 和 [GitHub Release](https://github.com/ym911x/Minget/releases/tag/v1.4.0) 已完成；发布提交 CI `35514875456` 通过。

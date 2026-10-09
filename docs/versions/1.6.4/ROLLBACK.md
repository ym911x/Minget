# 1.6.4 回滚

## 测试安装后的回滚（2026-10-09）

用户要求在正式路径测试 1.6.4，`/Applications/Minget.app` 已由 1.6.3 替换为严格签名的 1.6.4。替换前的 1.6.3 完整备份：

`/Users/yuyimeng/Applications/Minget Backups/1.6.3-before-1.6.4-20261009-113738/Minget.app`

回滚步骤：先退出 `/Applications/Minget.app` 并确认其子进程已回收，再把该备份包恢复到正式路径，然后执行 `codesign --verify --deep --strict /Applications/Minget.app`。个人目录兼容链接继续指向正式路径；不要直接运行备份。

备份只含应用包，不含 Key、浏览器会话或 CLI 认证文件。回滚不改动账号注册表：1.6.4 新增的只有顺序偏好键，1.6.3 读到它会忽略。

## 偏好键

- 本轮唯一新增的本机状态是顺序偏好键 `overview.accountOrder.v1`，写入应用自己的 `UserDefaults`（bundle ID `local.usagemonitor.UsageMonitor`，见 `scripts/build.sh`）。若需恢复平台分组默认顺序，退出应用后删除该键即可：

  ```sh
  defaults delete local.usagemonitor.UsageMonitor "overview.accountOrder.v1"
  ```

  键不存在时概要按 ChatGPT → Google → DeepSeek → Command Code 的来源顺序显示，功能不受影响。

- 除测试安装外本轮未做发布：未打标签、未推送、未建 Release；顺序偏好对旧版本是不可见的多余键，不影响旧版本运行。

约束沿用既有边界：不通过复制认证文件恢复登录，不读取或改写官方 CLI 的认证数据。

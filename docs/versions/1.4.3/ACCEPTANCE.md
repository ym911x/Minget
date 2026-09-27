# 1.4.3 验收台账

状态：代码、自动测试、严格签名、本机备份安装及真实只读运行核验完成。真实交互界面验收待补，第二台 Mac 未实测。用户已授权发布；远端核验状态见本版本发布记录。

| 检查 | 结果与证据 |
| --- | --- |
| 自动测试 | 551 项执行：Core 391、App 160，550 通过、1 项既有 AX 环境跳过、0 失败；evidence/test-summary.txt |
| 安装组合 | 新旧官方布局、用户级路径、精简 PATH、Node CLI/缺失 Node/无 CLI、损坏候选回退、显式覆盖、依赖恢复、探测超时及 wrapper 后代清理、A/B 点火假 CLI 隔离均通过 |
| Release 构建 | arm64，Minget Local Signing；staging/review/archive/install 及嵌套执行文件严格签名验证通过；evidence/signed-build.txt |
| 本机真实服务 | 安装包原生 A/B 与 Node 备用 A 的握手、用量读取、缓存往返和子进程回收均 PASS；evidence/native-A.txt、native-B.txt、node-A.txt |
| Finder 启动 | CUA 在 Finder 打开固定安装路径，Minget 的 PATH 为系统四目录；两条原生 Codex 子进程上线 |
| 双账号自动刷新 | 应用缓存 07:55:06 → 07:57:08，两账号均更新；仅读取应用自己的标准化缓存元数据，未输出身份 |
| 退出重启 | 正常退出并回收两条自有 Codex；Finder 再次打开后两账号 07:58:41 更新 |
| 详情页交互和视觉 | 未验收。工具连接收起的菜单栏浮窗超时；已请求用户打开详情页，尚未取得可操作的窗口 |
| 第二台 Mac | 未实测；只完成隔离安装组合测试 |
| 计划及凭证 | 外部脚本/LaunchAgent 未改；应用内启用计划为零；无真实点火、重置权益消费、认证文件读取，发布另按用户后续授权进行 |

## 安装与恢复

本机：`~/Applications/Minget.app`。旧版完整备份：`$HOME/Applications/Minget-1.4.2-backup-20260927-075450/Minget.app`。两个安装执行文件 SHA-256 与审核包一致，见 evidence/installation.json。

如需恢复，先正常退出 Minget，将当前 1.4.3 移到新的备份目录，把上述 1.4.2 的完整 Minget.app 放回固定安装位置，验证签名后从 Finder 打开；保留两个版本以便回滚。不需要修改账号隔离目录、Keychain 或定时计划。

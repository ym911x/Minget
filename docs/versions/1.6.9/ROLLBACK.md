# 1.6.9 回滚

## 本机测试安装后的回滚（2026-10-17）

`/Applications/Minget.app` 已由严格签名的 1.6.8 替换为 1.6.9（安装记录与指纹见 [evidence/records/local-install.txt](evidence/records/local-install.txt)）。替换前的 1.6.8 完整备份：

`$HOME/Applications/Minget Backups/1.6.8-before-1.6.9-20261017-101124/Minget.app`

（备份内可执行文件 SHA-256 `97c2635dd0d2e5672474ce347a776cd6659a9fac5999643731f92d6bdf84be49`，与替换前的正式路径一致。）

回滚步骤：先正常退出 `/Applications/Minget.app` 并确认其自有子进程已回收，再把该备份恢复到正式路径，然后执行 `codesign --verify --deep --strict /Applications/Minget.app`。个人目录兼容链接继续指向正式路径；不要直接运行备份。

备份只含应用包，不含 Key、浏览器会话或 CLI 认证文件。

## 本机状态

- 新增偏好键：无。菜单栏来源选择、低额度刷新设置、详情与顺序偏好语义均未变；本轮只改刷新范围与频率。
- 回滚到 1.6.8 后取数恢复为「全量周期刷新 + 面板打开按年龄补刷」；账号、缓存与点火计划无需转换。
- 每账号取数时间台账为进程内内存数据，回滚不涉及任何持久化清理。

## 公开发布

本轮未打标签、未推送、未建 Release。若后续发布，源码回滚可参考已公开标签 `v1.6.8`；本机 App 恢复使用上文已校验备份。

约束沿用既有边界：不通过复制认证文件恢复登录，不读取或改写官方 CLI 的认证数据。

# 1.6.2 应用程序启动入口修复

2026-10-01，Asia/Shanghai。用户反馈从应用程序运行看到1.5，明确要求将日常应用更新到1.6.2。

## 检查与处理

- 主项目 `codex/minget-1-6-2`，代码提交7626168，VERSION与个人应用目录正式包均为1.6.2；此前系统 `/Applications/Minget.app` 不存在。
- Spotlight同时索引了10份同bundle ID的历史备份，其中包含1.5.0。它们可能导致应用搜索/启动误选；本轮没有读取用户此前点选链接，不能唯一反推当时实际启动路径。
- 操作前核对无Minget进程。将已经验证过的完整1.6.2包从个人目录移动到 `/Applications/Minget.app`；可执行文件SHA-256保持不变，严格深度签名复验通过。
- 原 `~/Applications/Minget.app` 改为指向 `/Applications/Minget.app` 的软链接，兼容已有路径与启动脚本。没有改动任何账号、Keychain、认证或偏好。
- 对10份精确确认bundle ID的旧备份执行 `lsregister -u <备份路径>`，保留全部备份文件；对正式路径执行 `lsregister -f /Applications/Minget.app`，未重置全局LaunchServices/Launchpad数据库。
- 构建脚本识别上述明确软链接时默认安装到系统正式路径，防止未来构建删除软链接并再次产生双份正式包；其他机器默认个人目录行为及显式MINGET_RUN_PATH覆盖保持原样。

## 验证

- `bash -n scripts/build.sh`通过；安装路径决策的实际本机默认返回系统正式路径，显式环境覆盖返回指定候选路径。
- 通过Finder系统“应用程序”里的Minget条目打开，正式App界面显示v1.6.2；进程路径为 `/Applications/Minget.app/Contents/MacOS/UsageMonitor`。
- 真实概览仍为新布局，最终停在概览。签名与可执行文件指纹匹配本轮已测试包，没有重新编译或改变应用二进制，无需重复631项应用测试。
- 本轮未逐项测试Launchpad及Spotlight搜索结果；这里只确认系统应用程序正式入口可用。

证据与备份清单见 evidence/launch-entry-repair.json。回退应先退出正式应用，再把所需签名备份复制回 `/Applications/Minget.app`，不覆盖旧路径软链接；账号/凭证保持不动。

# 当前项目状态

更新：2026-10-17（Asia/Singapore）。本文件为当前入口，历史结论从版本索引查阅。

| 项目 | 当前状态 |
| --- | --- |
| 当前本机版本 | 1.6.9：刷新范围与频率优化。默认只刷菜单栏显示的来源（ChatGPT 30/60/120 秒自适应，DeepSeek、Command Code、Google 约 5 分钟），其余账号仅在打开概览或品牌页（含面板内切换标签）时按 5 分钟整批门槛补刷一次；启动与唤醒同样只作用于菜单栏来源，设置里的低额度加速规则与手动刷新路径不变。706 项完整回归（701 通过、5 项既有跳过、0 失败）通过，Release 严格签名并装入正式路径；真实界面与请求节奏已由用户复验通过（2026-10-17，结论「可以了」），见 [1.6.9 验收](docs/versions/1.6.9/ACCEPTANCE.md) |
| 上一本机版本 | 1.6.8：菜单栏固定长度与账号代号；用户复验通过（2026-10-16）并已公开发布，作为 1.6.9 的回滚备份保留 |
| 公开版本 | 1.6.8 已公开发布为 Latest，包含此前未单独发布的 1.6.7；标签 v1.6.8 对应 `983bb8e`，GitHub CI 测试、Release 构建及严格签名通过，见 [发布记录](docs/versions/1.6.8/PUBLICATION.md) |
| 主目录 main | 发布准备提交即 `codex/minget-1-6-9` 的头部，本次一并快进 main；源码、VERSION 与正式 App 均为 1.6.9，推送接管见 [1.6.9 发布记录](docs/versions/1.6.9/PUBLICATION.md) |
| 当前分支 | 发布准备已就绪（`codex/minget-1-6-9`，未合并差异为零）；`main` 保留 1.6.8 发布基线历史，无其他活动开发任务 |
| 正式安装应用 | `/Applications/Minget.app` 为严格签名 1.6.9（staging、正式路径与归档三处可执行文件哈希一致，`68c09e57…`），已由用户复验通过；1.6.8 备份、指纹与回滚步骤见 [1.6.9 ROLLBACK.md](docs/versions/1.6.9/ROLLBACK.md) |
| 旧工作区 | 1.5.0 / Google 1.6.0 已合入发布基线，仅保留历史，不继续开发 |
| 当前代码图谱 | 无；旧图谱已隔离，不用于解释本轮实现 |

## 当前工作资料

[1.6.9 需求](docs/versions/1.6.9/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.9/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.9/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.9/REVIEW.md) · [验收](docs/versions/1.6.9/ACCEPTANCE.md) · [回滚](docs/versions/1.6.9/ROLLBACK.md) · [证据](docs/versions/1.6.9/evidence/records/local-install.txt)。

[1.6.8 需求](docs/versions/1.6.8/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.8/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.8/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.8/REVIEW.md) · [验收](docs/versions/1.6.8/ACCEPTANCE.md) · [回滚](docs/versions/1.6.8/ROLLBACK.md) · [证据](docs/versions/1.6.8/evidence/README.md)。

[1.6.7 实施记录](docs/versions/1.6.7/IMPLEMENTATION_REPORT.md) · [1.6.8 发布记录](docs/versions/1.6.8/PUBLICATION.md) · [发布说明](docs/versions/1.6.8/RELEASE_NOTES.md) · [历史版本索引](docs/versions/README.md)。

代码、自动测试、签名、真实界面、真实取数、用户体验和公开发布分别记录，任何一项不得代替另一项。

## 1.6.9 本机验收通过、发布准备完成（2026-10-17）

刷新范围与频率优化已实现并通过自动验证（706 项回归，701 通过、5 项既有跳过、0 失败），Release 严格签名并装入正式路径，用户在本机正式安装版上复验通过并同意固化与准备发布（结论「可以了」）。需求、实施、审核、验收、发布说明与证据见 [1.6.9 资料](docs/versions/1.6.9/ACCEPTANCE.md)，发布准备状态见 [1.6.9 发布记录](docs/versions/1.6.9/PUBLICATION.md)；推送、标签与 GitHub Release 待用户确认后执行。1.6.8 仍是远端 Latest 与回滚基线。

## 1.6.8 发布完成（2026-10-16）

已发布 [v1.6.8](https://github.com/ym911x/Minget/releases/tag/v1.6.8) 为 Latest，包含 1.6.7 设置窗口统一与 1.6.8 固定菜单栏。本机 693 项回归和远端 CI 均通过。推送期间曾发生 GitHub TLS/EOF 连接中断，用户切换台湾节点后恢复；未修改系统代理或 Git 全局配置。三份既有 releases 文档删除仍只在本地工作区，未提交。详情见 [发布记录](docs/versions/1.6.8/PUBLICATION.md)。

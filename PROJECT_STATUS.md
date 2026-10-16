# 当前项目状态

更新：2026-10-16（Asia/Singapore）。本文件为当前入口，历史结论从版本索引查阅。

| 项目 | 当前状态 |
| --- | --- |
| 当前本机版本 | 1.6.8：菜单栏项目长度固定（所有来源、数值与警告状态同一宽度），上排改为「代号 + 百分比」（`O1 78% 42%`、`G1 80% 90%`），代号规范为 OpenAI `O1`/`O2`、Gemini `G1`/`G2`/`G3`、DeepSeek `DS1` 并与设置「菜单栏显示」列表一一对应；刘海或空间不足时不再压缩而打开详情窗口。693 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名并装入正式路径；真实界面复验通过（2026-10-16，用户结论「这次不错」） |
| 上一本机版本 | 1.6.7：设置窗口视觉统一（系统设置观感、彩色侧栏图标、账户行统一）；用户复验通过，提交 `1a0a172`，未单独发布，本次随 1.6.8 公开 |
| 公开版本 | 1.6.8 已公开发布为 Latest，包含此前未单独发布的 1.6.7；标签 v1.6.8 对应 `983bb8e`，GitHub CI 测试、Release 构建及严格签名通过，见 [发布记录](docs/versions/1.6.8/PUBLICATION.md) |
| 主目录 main | 已快进至发布提交 `983bb8e` 并回写本轮发布台账；源码、VERSION 与正式 App 均为 1.6.8，远端 main 同步发布台账 |
| 当前分支 | 主目录 `main` 保存最新完成基线；`codex/minget-1-6-8` 的发布准备已合入，无活动开发任务 |
| 正式安装应用 | `/Applications/Minget.app` 为严格签名 1.6.8（安装前后可执行文件哈希一致，`97c2635d…`），已重新启动供复验；1.6.7 备份见 [1.6.8 ROLLBACK.md](docs/versions/1.6.8/ROLLBACK.md) |
| 旧工作区 | 1.5.0 / Google 1.6.0 已合入发布基线，仅保留历史，不继续开发 |
| 当前代码图谱 | 无；旧图谱已隔离，不用于解释本轮实现 |

## 当前工作资料

[1.6.8 需求](docs/versions/1.6.8/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.8/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.8/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.8/REVIEW.md) · [验收](docs/versions/1.6.8/ACCEPTANCE.md) · [回滚](docs/versions/1.6.8/ROLLBACK.md) · [证据](docs/versions/1.6.8/evidence/README.md)。

[1.6.7 实施记录](docs/versions/1.6.7/IMPLEMENTATION_REPORT.md) · [1.6.8 发布记录](docs/versions/1.6.8/PUBLICATION.md) · [发布说明](docs/versions/1.6.8/RELEASE_NOTES.md) · [历史版本索引](docs/versions/README.md)。

代码、自动测试、签名、真实界面、真实取数、用户体验和公开发布分别记录，任何一项不得代替另一项。

## 1.6.8 发布完成（2026-10-16）

已发布 [v1.6.8](https://github.com/ym911x/Minget/releases/tag/v1.6.8) 为 Latest，包含 1.6.7 设置窗口统一与 1.6.8 固定菜单栏。本机 693 项回归和远端 CI 均通过。推送期间曾发生 GitHub TLS/EOF 连接中断，用户切换台湾节点后恢复；未修改系统代理或 Git 全局配置。三份既有 releases 文档删除仍只在本地工作区，未提交。详情见 [发布记录](docs/versions/1.6.8/PUBLICATION.md)。

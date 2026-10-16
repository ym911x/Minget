# 当前项目状态

更新：2026-10-16（Asia/Singapore）。本文件为当前入口，历史结论从版本索引查阅。

| 项目 | 当前状态 |
| --- | --- |
| 当前本机版本 | 1.6.8：菜单栏项目长度固定（所有来源、数值与警告状态同一宽度），上排改为「代号 + 百分比」（`O1 78% 42%`、`G1 80% 90%`），代号规范为 OpenAI `O1`/`O2`、Gemini `G1`/`G2`/`G3`、DeepSeek `DS1` 并与设置「菜单栏显示」列表一一对应；刘海或空间不足时不再压缩而打开详情窗口。693 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名并装入正式路径；真实界面复验通过（2026-10-16，用户结论「这次不错」） |
| 上一本机版本 | 1.6.7：设置窗口视觉统一（系统设置观感、彩色侧栏图标、账户行统一）；用户复验通过，提交 `1a0a172`，未公开发布 |
| 公开版本 | 1.6.6 已公开发布为 Latest；标签 v1.6.6 对应 `78c57ba`，GitHub CI 测试、Release 构建与严格签名通过；发布台账回写提交为 `1592f46`；见 [1.6.6 PUBLICATION.md](docs/versions/1.6.6/PUBLICATION.md) |
| 主目录 main | 已快进到 1.6.6 发布台账提交 `1592f46`；1.6.7 与 1.6.8 依次提交/实施在各自分支上 |
| 当前开发分支 | `codex/minget-1-6-8`（起点 `codex/minget-1-6-7@1a0a172`）；1.6.8 发布准备中，用户已授权合并公开 1.6.7 / 1.6.8；本机发布回归 693 项通过，远端 CI 与 Release 待核验 |
| 正式安装应用 | `/Applications/Minget.app` 为严格签名 1.6.8（安装前后可执行文件哈希一致，`97c2635d…`），已重新启动供复验；1.6.7 备份见 [1.6.8 ROLLBACK.md](docs/versions/1.6.8/ROLLBACK.md) |
| 旧工作区 | 1.5.0 / Google 1.6.0 已合入发布基线，仅保留历史，不继续开发 |
| 当前代码图谱 | 无；旧图谱已隔离，不用于解释本轮实现 |

## 当前工作资料

[1.6.8 需求](docs/versions/1.6.8/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.8/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.8/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.8/REVIEW.md) · [验收](docs/versions/1.6.8/ACCEPTANCE.md) · [回滚](docs/versions/1.6.8/ROLLBACK.md) · [证据](docs/versions/1.6.8/evidence/README.md)。

[1.6.7 实施记录](docs/versions/1.6.7/IMPLEMENTATION_REPORT.md) · [1.6.6 发布记录](docs/versions/1.6.6/PUBLICATION.md) · [发布说明](docs/versions/1.6.6/RELEASE_NOTES.md) · [历史版本索引](docs/versions/README.md)。

代码、自动测试、签名、真实界面、真实取数、用户体验和公开发布分别记录，任何一项不得代替另一项。

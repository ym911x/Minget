# 当前项目状态

更新：2026-10-10（Asia/Singapore）。本文件为当前入口，历史结论从版本索引查阅。

| 项目 | 当前状态 |
| --- | --- |
| 当前本机版本 | 1.6.6：Gemini 详情卡直接显示其他额度组（`Claude and GPT models`，Claude 橙 #D97757，低于 20% 红）并删除「最近成功 hh:mm / 缓存数据」与折叠标题；概览页 ChatGPT 与 Gemini 的额度图示加宽到与 Command Code 双列等长。689 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名并装入正式路径；Codex 已检查正式界面并通过 Gemini 三账号只读刷新；用户体验与现场边界见验收台账（2026-10-10） |
| 上一本机版本 | 1.6.5：概览 Command Code 行改为 5H + 月额度两列，四个品牌页新增只刷新本品牌的按钮；已公开发布 |
| 公开版本 | 1.6.5 已公开发布为 Latest；标签 v1.6.5 对应 `61bf600`，GitHub CI 测试、Release 构建与严格签名通过；见 [1.6.5 PUBLICATION.md](docs/versions/1.6.5/PUBLICATION.md) |
| 主目录 main | 已快进到 1.6.5 发布提交 `61bf600`，随后回写发布台账至 `14004e5`；源码、测试、构建脚本与发布标签一致 |
| 当前开发分支 | `codex/minget-1-6-6`（起点 `main@14004e5`）；1.6.6 的代码与文档已完成独立发布审核，准备提交并发布 |
| 正式安装应用 | `/Applications/Minget.app` 为严格签名 1.6.6（安装前后可执行文件哈希一致，`0cb0e841…`），发布审核的正式界面检查通过；1.6.5 备份见 [1.6.6 ROLLBACK.md](docs/versions/1.6.6/ROLLBACK.md) |
| 旧工作区 | 1.5.0 / Google 1.6.0 已合入发布基线，仅保留历史，不继续开发 |
| 当前代码图谱 | 无；旧图谱已隔离，不用于解释本轮实现 |

## 当前工作资料

[1.6.6 发布记录](docs/versions/1.6.6/PUBLICATION.md) · [1.6.6 需求](docs/versions/1.6.6/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.6/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.6/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.6/REVIEW.md) · [验收](docs/versions/1.6.6/ACCEPTANCE.md) · [回滚](docs/versions/1.6.6/ROLLBACK.md) · [证据](docs/versions/1.6.6/evidence/README.md)。

[1.6.5 发布记录](docs/versions/1.6.5/PUBLICATION.md) · [发布说明](docs/versions/1.6.5/RELEASE_NOTES.md) · [1.6.4 发布记录](docs/versions/1.6.4/PUBLICATION.md) · [历史版本索引](docs/versions/README.md)。

代码、自动测试、签名、真实界面、真实取数、用户体验和公开发布分别记录，任何一项不得代替另一项。

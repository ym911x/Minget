# 当前项目状态

更新：2026-10-10（Asia/Singapore）。本文件为当前入口，历史结论从版本索引查阅。

| 项目 | 当前状态 |
| --- | --- |
| 当前本机版本 | 1.6.5：概览页 Command Code 行改为 5H + 月额度两列，四个品牌页新增只刷新本品牌的按钮。686 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名并装入正式路径，用户复验界面与刷新范围无问题（2026-10-10） |
| 上一本机版本 | 1.6.4：概要页拖动排序已实现并固化，用户复测确认拖动体验可以接受；已公开发布 |
| 公开版本 | 1.6.4 已公开发布为 Latest；标签 v1.6.4 对应 `1f12d0b`，GitHub CI 测试、Release 构建和严格签名校验通过；见 [1.6.4 PUBLICATION.md](docs/versions/1.6.4/PUBLICATION.md) |
| 主目录 main | 已快进同步 1.6.4 发布提交 `1f12d0b`，并回写发布台账；源码、测试、构建脚本、VERSION 与发布标签一致 |
| 当前开发分支 | 1.6.5 实现与用户复验完成，公开发布准备中；整理入口为临时 `codex/publish-1-6-5`，原 `codex/minget-1-6-5` 仅本地保留 |
| 正式安装应用 | `/Applications/Minget.app` 为严格签名 1.6.5（安装前后可执行文件哈希一致），用户复验通过；1.6.4 备份见 [1.6.5 ROLLBACK.md](docs/versions/1.6.5/ROLLBACK.md) |
| 旧工作区 | 1.5.0 / Google 1.6.0 已合入发布基线，仅保留历史，不继续开发 |
| 当前代码图谱 | 无；旧图谱已隔离，不用于解释本轮实现 |

## 当前工作资料

[1.6.5 发布记录](docs/versions/1.6.5/PUBLICATION.md) · [发布说明](docs/versions/1.6.5/RELEASE_NOTES.md) · [1.6.5 需求](docs/versions/1.6.5/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.5/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.5/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.5/REVIEW.md) · [验收](docs/versions/1.6.5/ACCEPTANCE.md) · [回滚](docs/versions/1.6.5/ROLLBACK.md)。

[1.6.4 发布记录](docs/versions/1.6.4/PUBLICATION.md) · [发布说明](docs/versions/1.6.4/RELEASE_NOTES.md) · [1.6.4 需求](docs/versions/1.6.4/REQUIREMENTS.md) · [1.6.3 需求](docs/versions/1.6.3/REQUIREMENTS.md) · [历史版本索引](docs/versions/README.md)。

代码、自动测试、签名、真实界面、真实取数、用户体验和公开发布分别记录，任何一项不得代替另一项。

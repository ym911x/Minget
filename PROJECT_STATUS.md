# 当前项目状态

更新：2026-10-09（Asia/Shanghai）。本文件为当前入口，历史结论从版本索引查阅。

| 项目 | 当前状态 |
| --- | --- |
| 当前本机版本 | 1.6.4：概要页拖动排序已实现并固化。拖动位移在窗口坐标系测量、被拖行精确跟手、其余行整格滑让；679 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名并装入正式路径，用户复测确认拖动体验可以接受。拖动期间刷新、重启恢复顺序、键盘与 VoiceOver 现场项待核对 |
| 上一本机版本 | 1.6.3，多账号添加与管理已实现，完整回归、Release 签名、备份安装及入口检查通过；七账号概要完整显示，660 项回归及真实窗口复验通过，用户已验收概要；其取数及其他真实新账号、移除、点火待验收 |
| 公开版本 | 1.6.3 已公开发布为 Latest，标签与发布提交核验一致，GitHub 测试及构建 CI 通过；见 1.6.3 PUBLICATION.md。1.6.4 尚未发布，等待发布任务 |
| 主目录 main | v1.6.3 发布代码 `a5c5043` 及后续发布台账，保持与 origin/main 一致；1.6.4 尚未合入 main |
| 当前开发分支 | `codex/minget-1-6-4`（worktree，起点 `main@73c3f9a`），1.6.4 实现、文档与验收记录已完成并固化；该分支不包含 `codex/project-folder-organization` 的目录整理变更，两者相互独立，合并顺序由后续任务决定 |
| 正式安装应用 | `/Applications/Minget.app` 为严格签名 1.6.4（用户测试并确认），与固化源码同一构建；1.6.3 备份见 1.6.4 ROLLBACK.md，更早备份见 1.6.3 ROLLBACK.md |
| 旧工作区 | 1.5.0 / Google 1.6.0 已合入发布基线，仅保留历史，不继续开发 |
| 当前代码图谱 | 无；旧图谱已隔离，不用于解释本轮实现 |

## 当前工作资料

[1.6.4 需求](docs/versions/1.6.4/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.4/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.4/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.4/REVIEW.md) · [验收](docs/versions/1.6.4/ACCEPTANCE.md) · [回滚](docs/versions/1.6.4/ROLLBACK.md)。

[1.6.3 发布记录](docs/versions/1.6.3/PUBLICATION.md) · [1.6.3 需求](docs/versions/1.6.3/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.3/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.3/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.3/REVIEW.md) · [验收](docs/versions/1.6.3/ACCEPTANCE.md) · [回滚](docs/versions/1.6.3/ROLLBACK.md)。

[1.6.2 发布记录](docs/versions/1.6.2/PUBLICATION.md) · [历史版本索引](docs/versions/README.md)。

代码、自动测试、签名、真实界面、真实取数、用户体验和公开发布分别记录，任何一项不得代替另一项。

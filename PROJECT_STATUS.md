# 当前项目状态

更新：2026-10-13（Asia/Singapore）。本文件为当前入口，历史结论从版本索引查阅。

| 项目 | 当前状态 |
| --- | --- |
| 当前本机版本 | 1.6.7：设置窗口视觉统一（系统设置观感：唯一标题层级、分组脚注说明、对齐的标签与控件两列、彩色圆角方块侧栏图标；账号页标题与主操作上移、账户行统一为分组内的整行）。功能与数据口径零改动。694 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名并装入正式路径；真实界面复验待用户进行（2026-10-13） |
| 上一本机版本 | 1.6.6：Gemini 详情卡其他额度组直显（Claude 橙）、概览额度条与 Command Code 等长；已公开发布 |
| 公开版本 | 1.6.6 已公开发布为 Latest；标签 v1.6.6 对应 `78c57ba`，GitHub CI 测试、Release 构建与严格签名通过；发布台账回写提交为 `1592f46`；见 [1.6.6 PUBLICATION.md](docs/versions/1.6.6/PUBLICATION.md) |
| 主目录 main | 已快进到 1.6.6 发布台账提交 `1592f46`；源码、测试、构建脚本与发布标签一致 |
| 当前开发分支 | `codex/minget-1-6-7`（起点 `main@1592f46`）；1.6.7 的代码与文档改动在本分支工作区，尚未提交 |
| 正式安装应用 | `/Applications/Minget.app` 为严格签名 1.6.7（安装前后可执行文件哈希一致，`a17b5610…`），已重新启动供复验；1.6.6 备份见 [1.6.7 ROLLBACK.md](docs/versions/1.6.7/ROLLBACK.md) |
| 旧工作区 | 1.5.0 / Google 1.6.0 已合入发布基线，仅保留历史，不继续开发 |
| 当前代码图谱 | 无；旧图谱已隔离，不用于解释本轮实现 |

## 当前工作资料

[1.6.7 需求](docs/versions/1.6.7/REQUIREMENTS.md) · [实施任务](docs/versions/1.6.7/IMPLEMENTATION_TASKS.md) · [实施记录](docs/versions/1.6.7/IMPLEMENTATION_REPORT.md) · [审核](docs/versions/1.6.7/REVIEW.md) · [验收](docs/versions/1.6.7/ACCEPTANCE.md) · [回滚](docs/versions/1.6.7/ROLLBACK.md) · [证据](docs/versions/1.6.7/evidence/README.md)。

[1.6.6 发布记录](docs/versions/1.6.6/PUBLICATION.md) · [发布说明](docs/versions/1.6.6/RELEASE_NOTES.md) · [1.6.5 发布记录](docs/versions/1.6.5/PUBLICATION.md) · [历史版本索引](docs/versions/README.md)。

代码、自动测试、签名、真实界面、真实取数、用户体验和公开发布分别记录，任何一项不得代替另一项。

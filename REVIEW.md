# 当前审核状态

当前对象为 **1.6.8 菜单栏固定长度与账号代号**。菜单栏项目长度固定为常量（`textBudget 81 + padding 12 = 93 pt`），所有来源、所有数值与有无缓存/失败标记都不再改变长度；上排改为「代号 + 百分比」（`O1 78% 42%`、`G1 80% 90%`），`5H`/`W` 与 Gemini 额度组名不再出现在菜单栏，下排 5 小时与周时间条不变。代号规范为 OpenAI `O1`/`O2`、Gemini `G1`/`G2`/`G3`、DeepSeek `DS1`/`DS2`，取自账号注册表的持久化序号，并与设置「菜单栏显示」列表逐行对应。刘海或空间不足时不再压缩，直接走既有详情窗口路径。构建与 693 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名后装入正式路径；用户复验通过（2026-10-16），见 [验收台账](docs/versions/1.6.8/ACCEPTANCE.md)。

- [当前项目状态](PROJECT_STATUS.md)
- [实施记录](docs/versions/1.6.8/IMPLEMENTATION_REPORT.md)
- [代码与验证审核](docs/versions/1.6.8/REVIEW.md)
- [验收台账](docs/versions/1.6.8/ACCEPTANCE.md)

上一本机版本 1.6.7（设置窗口视觉统一）已由用户复验通过，提交 `1a0a172`，未公开发布。公开发布版本仍为 1.6.6（Latest），核验见 [1.6.6 发布记录](docs/versions/1.6.6/PUBLICATION.md)。历史版本记录保持原样。

本轮未打标签、未推送、未建 Release；回滚路径与备份见 [1.6.8 回滚](docs/versions/1.6.8/ROLLBACK.md)。

2026-10-16 发布进度：本机完整回归复核通过，1.6.7 与 1.6.8 已合入本地 main；推送遇 GitHub TLS/EOF 连接失败，尚未发布。恢复后继续远端 CI、标签和 Release，见 [发布记录](docs/versions/1.6.8/PUBLICATION.md)。

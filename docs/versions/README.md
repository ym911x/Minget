# 版本资料索引

本目录保存每个版本的需求、实施、审核与验收记录。各版本的资料命名并不完全一致，这是设计而非缺漏：`v1.0.2` 用 `REVISION_SPEC.md` 把需求与任务写在一起，`v1.1.0` 用 `DEVELOPMENT_PLAN.md`，`v1.2.0` 未单独撰写实施报告。缺失的文件以「—」标注，不补写历史报告，避免把后来的结论写进旧版本。

`v1.0.0` 的基线已冻结在 [../archive/v1.0/](../archive/v1.0/README.md)，不在本目录。

## 状态表

| 版本 | 发布 | 需求 | 实施任务 | 实施报告 | 审核 | 验收 | 发布说明 | 截图 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1.0.2 | 是 | REVISION_SPEC.md | REVISION_SPEC.md | IMPLEMENTATION_REPORT.md | REVIEW.md | ACCEPTANCE.md | — | 本目录 evidence/ |
| 1.1.0 | 是 | DEVELOPMENT_PLAN.md | DEVELOPMENT_PLAN.md | IMPLEMENTATION_REPORT.md | REVIEW.md | ACCEPTANCE.md | — | assets/screenshots/v1.1.0/ |
| 1.1.1 | 是 | REQUIREMENTS.md | IMPLEMENTATION_TASKS.md | IMPLEMENTATION_REPORT.md | REVIEW.md | ACCEPTANCE.md | — | assets/screenshots/v1.1.1/ |
| 1.1.2 | 是 | REQUIREMENTS.md | IMPLEMENTATION_TASKS.md | IMPLEMENTATION_REPORT.md | REVIEW.md | ACCEPTANCE.md | — | — |
| 1.2.0 | 是 | REQUIREMENTS.md | IMPLEMENTATION_TASKS.md | — | REVIEW.md | ACCEPTANCE.md | — | — |
| 1.2.1 | 是 | REQUIREMENTS.md | IMPLEMENTATION_TASKS.md | IMPLEMENTATION_REPORT.md | REVIEW.md | ACCEPTANCE.md | RELEASE_NOTES.md | assets/screenshots/v1.2.1/ |
| 1.3.0 | 是 | REQUIREMENTS.md | IMPLEMENTATION_TASKS.md | IMPLEMENTATION_REPORT.md | REVIEW.md | ACCEPTANCE.md | RELEASE_NOTES.md | assets/screenshots/v1.3.0/ |
| 1.3.1 | 是 | REQUIREMENTS.md | IMPLEMENTATION_TASKS.md | IMPLEMENTATION_REPORT.md | REVIEW.md | ACCEPTANCE.md | RELEASE_NOTES.md | — |
| 1.3.2 | 是（用户接受发布；保留发布后验证项） | REQUIREMENTS.md | IMPLEMENTATION_TASKS.md | IMPLEMENTATION_REPORT.md | REVIEW.md | ACCEPTANCE.md | RELEASE_NOTES.md | `/tmp` 脱敏渲染，不入库 |
| 1.4.0 | 是（保留真实低额度现场观察项） | REQUIREMENTS.md | IMPLEMENTATION_TASKS.md | — | REVIEW.md | ACCEPTANCE.md | RELEASE_NOTES.md | `/tmp` 明暗设置页渲染，不入库 |

## 各版本的额外资料

| 版本 | 额外文件 | 说明 |
| --- | --- | --- |
| 1.0.2 | `SIGNING_HANDOFF.md`、`KEYCHAIN_REVISION_PLAN.md`、`evidence/` | 签名交接、钥匙串访问改造计划与实测证据图 |
| 1.1.0 | `assets/` | 该版本自带的界面素材 |
| 1.3.0 | `REVISION_SPEC.md`、`UI_SPEC.md`、`AGENT_HANDOFF.md`、`FIRE_DESIGN_BACKGROUND.md` | 真实界面验收否决后的回归修订规格、最终界面规格、交接说明，以及脱敏后的双账号点火设计背景 |
| 1.3.1 | — | 记录 R1 无障碍阻断的发现与修复，无发布说明以外的额外文件 |

## 发布

- `v1.0.0`、`v1.0.1` 的本地发布元数据保存在 [releases/](../../releases/README.md)。
- `v1.1.0` 起以 GitHub Releases 与 [CHANGELOG.md](../../CHANGELOG.md) 为发布源，仓库内不再保存 App 包与 ZIP。
- 每个版本对应一个 Git 标签 `v<版本号>`。

## 阅读顺序

新版本开工时按 `REQUIREMENTS.md` → `IMPLEMENTATION_TASKS.md` → `IMPLEMENTATION_REPORT.md` → `REVIEW.md` → `ACCEPTANCE.md` 阅读；`ACCEPTANCE.md` 中的「待验收」项目只有取得真实证据后才能改为通过，自动测试不能替代。

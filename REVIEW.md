# 当前审核状态

## v1.1.0

状态：已完成。371 项自动测试与 1.1.0 构建通过，用户已确认当前详情页体验并授权上传 GitHub。尚未逐项重跑的边界交互、异常视觉矩阵和真实服务回归保留在 [验收台账](docs/versions/1.1.0/ACCEPTANCE.md)，不因发布而改记为通过。

| 资料 | 路径 |
| --- | --- |
| 开发方案 | [docs/versions/1.1.0/DEVELOPMENT_PLAN.md](docs/versions/1.1.0/DEVELOPMENT_PLAN.md) |
| 实施报告 | [docs/versions/1.1.0/IMPLEMENTATION_REPORT.md](docs/versions/1.1.0/IMPLEMENTATION_REPORT.md) |
| 独立审核状态 | [docs/versions/1.1.0/REVIEW.md](docs/versions/1.1.0/REVIEW.md) |
| 验收台账 | [docs/versions/1.1.0/ACCEPTANCE.md](docs/versions/1.1.0/ACCEPTANCE.md) |

## v1.0.2

状态：已完成。Codex 独立代码审核与构建复核通过，用户真实界面验收通过。

| 资料 | 路径 |
| --- | --- |
| 需求与实施任务书 | [docs/versions/1.0.2/REVISION_SPEC.md](docs/versions/1.0.2/REVISION_SPEC.md) |
| 实施报告 | [docs/versions/1.0.2/IMPLEMENTATION_REPORT.md](docs/versions/1.0.2/IMPLEMENTATION_REPORT.md) |
| 独立审核状态 | [docs/versions/1.0.2/REVIEW.md](docs/versions/1.0.2/REVIEW.md) |
| 验收台账 | [docs/versions/1.0.2/ACCEPTANCE.md](docs/versions/1.0.2/ACCEPTANCE.md) |
| 证据目录 | [docs/versions/1.0.2/evidence/](docs/versions/1.0.2/evidence/README.md) |

要点：`VERSION` 已改为 `1.0.2`，2026-09-11 独立复跑 359 项测试全部通过。运行候选包为 `~/Applications/Minget.app`（本地路径，严格校验通过），`dist/Minget.app` 为归档副本。钥匙串重复弹框与菜单栏外部点击收起均由用户实测确认通过。

另有独立交接 [SIGNING_HANDOFF.md](docs/versions/1.0.2/SIGNING_HANDOFF.md) 与 [KEYCHAIN_REVISION_PLAN.md](docs/versions/1.0.2/KEYCHAIN_REVISION_PLAN.md) 涉及的钥匙串反复授权问题：自签名证书已创建，构建已改用稳定身份；凭证读取由统一协调器串行执行、合并重复请求并在进程内记忆结果。用户已实测确认仅首次弹出一次，选择“始终允许”后不再重复弹出，真实余额随后更新。

## v1.0.1

状态：已作为品牌更新版本交付。变更内容见 [变更记录](CHANGELOG.md)。

## v1.0.0

状态：已完成。

最终依据见 [v1.0 最终验收](docs/archive/v1.0/acceptance/ACCEPTANCE.md)。历史审核过程见 [v1.0 归档索引](docs/archive/v1.0/README.md)。

## 下一版本

尚未确定下一版本范围。确定后在 `docs/versions/<版本号>/` 创建独立资料。

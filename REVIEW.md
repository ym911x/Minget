# 当前审核状态

本文件只作为入口，指向当前版本的审核与验收记录。历史版本的审核状态保留在各自版本目录，不再汇总到本文件；逐版本索引见 [docs/versions/README.md](docs/versions/README.md)。

## 当前版本：v1.4.2（本机验收通过；发布核验见验收台账）

状态：实现、独立审核、538 项 Swift 测试（1 项环境跳过、0 失败）、53 项外部脚本断言、严格签名安装及自然定时运行核验完成。真实界面三次手动刷新已观察到数据返回；用户于 2026-09-24 确认详情页关闭重开三次均正常。第三轮聚合结束标志未单独留证，保留此证据边界。 GitHub 发布核验见 ACCEPTANCE.md；不承诺服务端窗口必然推进。

| 资料 | 路径 |
| --- | --- |
| 独立审核（输入） | [docs/versions/1.4.2/INDEPENDENT_REVIEW.md](docs/versions/1.4.2/INDEPENDENT_REVIEW.md) |
| 需求 | [docs/versions/1.4.2/REQUIREMENTS.md](docs/versions/1.4.2/REQUIREMENTS.md) |
| 实施任务 | [docs/versions/1.4.2/IMPLEMENTATION_TASKS.md](docs/versions/1.4.2/IMPLEMENTATION_TASKS.md) |
| 实施报告 | [docs/versions/1.4.2/IMPLEMENTATION_REPORT.md](docs/versions/1.4.2/IMPLEMENTATION_REPORT.md) |
| 实施自审 | [docs/versions/1.4.2/REVIEW.md](docs/versions/1.4.2/REVIEW.md) |
| 验收台账 | [docs/versions/1.4.2/ACCEPTANCE.md](docs/versions/1.4.2/ACCEPTANCE.md) |
| 发布说明 | [docs/versions/1.4.2/RELEASE_NOTES.md](docs/versions/1.4.2/RELEASE_NOTES.md) |

上一发布版本 v1.4.1 的资料见 [docs/versions/1.4.1/ACCEPTANCE.md](docs/versions/1.4.1/ACCEPTANCE.md)。

## 冻结基线

`v1.0.0` 的最终验收与历史审核过程见 [docs/archive/v1.0/](docs/archive/v1.0/README.md)，不得改写。

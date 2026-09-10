# UsageMonitor v1.0 归档

归档日期：2026-09-10  
版本：1.0.0  
Git 标签：`v1.0.0`

本目录保存首个可用正式版本的需求、实施过程、审核记录和最终验收依据。归档内容应保持冻结；后续修订进入 `docs/versions/<版本号>/`。

## 目录

| 路径 | 内容 |
| --- | --- |
| `requirements/` | 原始完整方案、产品规格和实施计划 |
| `history/tasks/` | 各轮交给 Claude Code 的任务单 |
| `history/reports/` | 各轮实现报告和 Codex 审核记录 |
| `acceptance/` | 最终验收结论 |
| `evidence/` | 本机验证产物的保存规则 |
| `MANIFEST.sha256` | 归档时关键源码和资料的 SHA-256 清单 |

## 冻结基线

- Codex、DeepSeek、智谱 GLM 均已在真实应用界面中显示数据。
- 智谱 GLM 采用应用内独立控制台会话取数，不依赖付费推理 API。
- 274 项自动化测试通过，0 项失败。
- Release 应用通过构建、Info.plist 和代码签名检查。
- 用户确认该版本已跑通，并将其定为首个可用正式版本。

## 可复现命令

```bash
swift test
./scripts/build.sh
plutil -lint dist/UsageMonitor.app/Contents/Info.plist
codesign --verify --deep --strict dist/UsageMonitor.app
```

测试和构建日志保存在本机 `artifacts/release-v1.0/`。该目录默认不进入 Git，以避免把可能含设备环境信息的日志写入版本库。

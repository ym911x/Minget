# 项目目录职责与历史边界

检查日期：2026-10-01。根目录、版本记录、Git worktree、正式 App 与旧 App 实例已核对。凭证和私有账号目录不纳入清理。

| 位置 | 职责与本轮处理 |
| --- | --- |
| 根目录 README / ROADMAP / REVIEW | 产品介绍、规划、当前审核；删除“1.6.0 尚未发布 / 公开基线 1.4.3”的过期当前状态，以 PROJECT_STATUS 为入口 |
| PROJECT_STATUS.md | 当前任务、公开基线、开发分支、安装状态与验收入口 |
| Sources / Tests / Package.swift | 当前源码与测试，只在主项目的 1.6.1 分支继续开发 |
| scripts / .github | 构建、辅助脚本和 CI；本轮不更改点火安装计划 |
| assets | 产品素材与历史公开截图；本轮不覆盖 1.6.0 截图 |
| docs/versions/1.6.1 | 当前需求、实施、审核、验收与脱敏证据 |
| docs/versions/其他版本 | 历史版本记录，保留当时状态 |
| docs/archive/v1.0 | 冻结基线，未改写 |
| releases | 早期本地发布元数据；完整发布源为 GitHub Release 和 CHANGELOG |
| artifacts | 本地历史过程资料，保持旧链接；当前界面例图另入 1.6.1 evidence |
| artifacts/history/20261001-pre-1.6.1 | 隔离过期图谱，manifest.json 保留逐文件路径映射与 SHA-256 |
| .build / .swiftpm | 构建缓存与包管理状态，不能作为当前交付依据；本轮构建放 /tmp |
| .DS_Store | Finder 元数据，未当作项目资料 |
| 两个旧 worktree | 已合入 1.6.0 的历史工作区，保留原位置；路径及提交见 PROJECT_ALIGNMENT |
| ~/Applications/Minget.app | 唯一日常运行入口，版本由验收台账核对 |
| ~/Applications/Minget Backups | 本地签名回退副本，不能用应用显示名定位启动 |

今后每轮开工核对项目路径、分支、HEAD、VERSION、远端状态与正式 App；结束更新当前入口及版本台账。代码、测试、签名包、真实界面、真实取数、用户确认、公开发布分别记录。

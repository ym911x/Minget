# 1.6.3 实施记录

日期：2026-10-01，Asia/Shanghai。执行者：Codex。开发分支 `codex/minget-1-6-3`，来自干净 `main` 的 `ee7bc0ab59bbc750ae3685c70a38e582250d4103`。本机交付，不推送、不建标签、不发布。

## 完成结果

- 管理账号固定顶部的“添加账号”、四平台分组入口、服务详情入口均已接线；统一平台选择、名称和安全 Key 输入。名称最多 40 字符，默认平台名与递增编号。
- 新 `AccountRegistry` 只存稳定 ID、平台、名称、顺序及连接引用。首次迁移保留 ChatGPT A/B ID 和目录、Google UUID 和目录、API 服务原 Keychain account、名称、选择、缓存和计划。重复启动读取注册表，不重新导入旧 Google 元数据；损坏记录停止启动取数，不覆盖元数据。
- Google slot 改为可扩展标识；ChatGPT 协调器运行时添加和分离 Profile。取消及失败登录不产生持久空记录；仅对已确认身份和 Key 指纹去重。
- API 实例拥有 reader、刷新引擎、CredentialAccessCoordinator、凭证键、缓存命名空间和反馈。缓存同时绑定实例及实际身份，替换 Key 或移除后的旧响应不会回写。重启缓存显示待更新状态。
- 概览和详情继续复用 1.6.2 卡片。外层高度由实际账号数计算，在服务切换时保持稳定，最大 640 pt 并按屏幕裁剪；列表滚动，导航和底部操作可见。
- 菜单栏可选择各个 ChatGPT、Google、DeepSeek 账号。新增不改选择；删除来源保留显式待选择状态及选择入口。
- 点火计划和结果绑定账号 ID，新计划关闭，连接不触发点火。Command Code 跨实例串行，仍使用原固定最小请求及隔离环境。
- 移除先记录停用状态、停用计划并停止目标任务，再执行官方 ChatGPT `account/logout`、精确 Google UUID 清理或目标 API Keychain 删除。成功后删缓存与计划；失败保留停止行可重试。未修改外部 LaunchAgent。

## 修改文件

- 新增 `Sources/UsageMonitorCore/Models/AccountRegistry.swift`、`Sources/UsageMonitorApp/ViewModels/ManagedAccounts.swift`、`Sources/UsageMonitorApp/Views/ManagedAccountManagementView.swift`。
- Core：`ProviderModels/Readings/Cache/RefreshEngine`；`AntigravityProfileStore`、`CodexProfilesCoordinator`、`CodexAppServerClient`、`UsageService`、`UsageCache`、`ChatGPTFireService`、`MenuBarContent`。
- App：组合根 `UsageMonitorApp`；`UsageViewModel`、`AntigravityModel`、显示名称/菜单栏/计划偏好及刷新策略；账号、设置、登录、额度页和 `StatusItemController`。
- 测试：新 `AccountRegistryTests`、`ManagedAccountTests`、`ManagedAccountEvidenceTests`；补充 `UsageServiceTests` 的官方登出失败和缓存隔离；签名进程测试禁用本轮定时点火。
- `VERSION`、`scripts/build.sh` 内应用说明及根项目说明、本版本文档同步。

## 命令与结果

```sh
MINGET_EVIDENCE_DIR=/tmp/minget-1.6.3-evidence \
MINGET_TEST_APP_PATH=/tmp/minget-1.6.3-final/Minget.app \
swift test --scratch-path /tmp/minget-1.6.3-build --disable-sandbox

MINGET_BUILD_SCRATCH_DIR=/tmp/minget-1.6.3-release \
MINGET_STAGING_DIR=/tmp/minget-1.6.3-stage/Minget.app \
MINGET_RUN_PATH=/tmp/minget-1.6.3-final/Minget.app \
MINGET_ARCHIVE_PATH=/tmp/minget-1.6.3-archive/Minget.app \
./scripts/build.sh
```

完整回归及安装结果见 [验收](ACCEPTANCE.md)，原始日志保存在 `evidence/`。Release 使用已有 `Minget Local Signing`；候选、archive 和安装版两可执行文件 SHA-256 相同。旧版包先备份，再替换正式完整路径，个人目录兼容软链接保留。

实施期间修复了未知菜单栏来源误接受、删除一个 ChatGPT 缓存导致其他身份丢失、旧窗口高度回归、名称无效时提前写 Key、迁移后仍依赖旧 Google 元数据、Google 新 ID 被字典排序而非添加顺序排序、旧 API 引擎等待刷新时未恢复身份绑定缓存的问题。一轮弹窗位置测试受实际桌面布局变化影响失败；隔离复跑和最终完整回归通过，保留环境性风险，未改断言规避。

## 未完成的现场验收

第三/第四个真实 ChatGPT 和 Google 登录、第二个真实 API Key、真实移除和重新登录返回、新账号真实点火与计划触发需用户提供身份/Key 或操作后核对。自动测试不发真实模型请求，不以假额度证明取数。第二 Mac、真实睡眠唤醒与自然授权续期仍无本轮证据。

## 现场反馈后的修正

用户提供第三个 Google 账号无法取数的现场截图。通过该账号自建隔离目录的官方 `/usage`，定位到地区资格检查拒绝。修正错误分类及无快照缓存标签，见 [诊断与修正](GOOGLE_ELIGIBILITY_FIX.md)；原连接、名称与计划保留。

本轮定向 15 项及完整 658 项（653 通过、5 跳过、0 失败）通过；签名构建并备份安装完成，正式安装版真实界面确认提示、官方链接、无虚假缓存和原两个 Google 账号成功刷新。构建使用 `/tmp/minget-1.6.3-eligibility-{stage,candidate,archive}/Minget.app`，完整测试的 `MINGET_TEST_APP_PATH` 指向本轮 candidate，其余 scratch 和禁用定时点火参数沿用上文。没有推送、发布或改 Google 设置。

## 概要高度修正交付

用户七账号截图暴露了固定 640 pt 上限导致最后一行被截住的问题。修改 UsagePanelView、SharedQuotaViews、StatusItemController 与 DetailPanelLayoutTests，概要 684 pt 时完整显示且没有滚动容器，详情继续滚动。定向 61 项及完整 660 项（655 通过、5 既有跳过、0 失败）通过；Release 严格签名、签名候选真实窗口、备份安装及正式窗口复验完成。详见 OVERVIEW_HEIGHT_FIX.md。此前实施记录中的 640 pt 上限为初版行为，已被本次修正替代。

命令沿用此前 scratch，构建 MINGET_STAGING_DIR / MINGET_RUN_PATH / MINGET_ARCHIVE_PATH 分别指向 `/tmp/minget-1.6.3-overview-{stage,candidate,archive}/Minget.app`；完整测试 MINGET_TEST_APP_PATH 指向本轮 candidate，MINGET_EVIDENCE_DIR 为 `/tmp/minget-1.6.3-overview-evidence`。日志为 evidence/overview-*，版本仍为 1.6.3，无远端操作。

## 公开发布收尾

用户验收并明确授权后，v1.6.3 已公开发布；发布源码提交 a5c5043，GitHub CI 测试及应用构建通过，main 同步发布代码与后续台账。未上传本机 App 或真实账号截图，未重新安装应用。核验见 PUBLICATION.md。

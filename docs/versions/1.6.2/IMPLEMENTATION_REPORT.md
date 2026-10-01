# 1.6.2 实施报告

2026-10-01，Asia/Shanghai。已完成本地实现、验证与正式安装；尚未公开发布。

## 实现

- `SharedQuotaViews.swift`：新增结构化概览摘要（双周期窗口、余额、单信用额窗口）。概览状态移到名称下方，164 pt 图示区独立固定，5H/周两组间隔 12 pt，箭头居中；64 pt 行高保留。名称及状态全文可悬停查看。
- GPT/Gemini 复用现有百分比、语义颜色、连续额度轨和分段时间轨；提取共用时间转换，让概览/详情调用同一规则。Gemini 主组缺失不替换成共享池，额度未知时仍保留已知重置时间。
- 概览以 30 秒 TimelineView 本地重绘，没有新的读取或刷新回调。具体重置日期与完整状态进入悬停和 AX 标签。缓存橙色状态与减淡轨道，零值/缺失/到期明确区分。
- `UsagePanelView.swift`：只改概览接线与共享未知时间轨的固定高度。后者约束 Capsule 为 3 pt，避免“?”文字的固有高度把轨道撑成粗胶囊；详情的时间语义保持原样。
- DeepSeek 使用既有 Decimal 金额格式，保留币种；Command Code 保留5H金额、紫色额度轨及靛蓝时间轨。
- `OverviewPresentationTests.swift`：4 项语义回归和1项显式示例导出，验证主组、缺失/零值、已知时间、到期、阈值和币种/部分金额。没有修改认证、网络、点火或刷新调度代码。
- `VERSION` 更新至1.6.2；README、ROADMAP、REVIEW、PROJECT_STATUS、CHANGELOG和版本索引对齐本地迭代，公开基线仍为1.6.1。旧版本记录保持原样。

## 执行与结果

- 目标回归及示例导出：`MINGET_OVERVIEW_EVIDENCE="$PROJECT_ROOT/docs/versions/1.6.2/evidence" swift test --disable-sandbox --scratch-path /tmp/minget-swiftpm-build --filter 'OverviewPresentationTests|Interface161Tests|DetailPanelLayoutTests|StatusItemWiringTests'`，56项零失败。
- Release：`MINGET_RUN_PATH=/tmp/minget-162-candidate/Minget.app MINGET_STAGING_DIR=/tmp/minget-162-stage/Minget.app MINGET_ARCHIVE_PATH=/tmp/minget-162-archive/Minget.app MINGET_BUILD_SCRATCH_DIR=/tmp/minget-162-release ./scripts/build.sh`，arm64、稳定本地签名，stage/candidate/archive均通过严格核验。
- 完整测试：`MINGET_TEST_APP_PATH=/tmp/minget-162-candidate/Minget.app swift test --disable-sandbox --scratch-path /tmp/minget-swiftpm-build`，Core449＋App182，共631项，626通过、5项既有跳过、零失败；包含2项签名包真实进程启动/退出检查。
- 浅色、深色、缓存、长名称、长故障、阈值20%及真实零、缺失额度/已知时间、无连接与部分金额共四张示例图逐张观察通过。所有样例仅用于布局与状态展示。
- 正常退出旧正式 App 后，将原签名包移动至备份，再复制严格核验的候选至正式路径；失败可原路恢复。installed与candidate可执行文件SHA-256一致。
- Finder完整路径启动，六行、服务点击、GPT/Gemini读数对齐、Gemini展开、连续8次切换检查见 [真实界面记录](evidence/runtime-check.md)。

## 回退与边界

旧包：`~/Applications/Minget Backups/1.6.1-before-1.6.2-20261001-164733/Minget.app`。当前可执行文件SHA-256：`9d2b438968666cb535392faeb42774b8d8b2691cf03dc08969661a1db4c5bfb0`。源文件指纹及路径见 [verification.json](evidence/verification.json)。

回退时正常退出正式 App，用备份恢复固定的 `~/Applications/Minget.app`，严格核验并从完整路径打开；不要启动备份副本，不还原账号目录、凭证或偏好。

用户最终体验、真实菜单栏连续关开、系统实际深色/短屏、第二台Mac及睡眠唤醒仍保留现场边界；本轮不推送、不公开发布。既有4项Google官方CLI显式探针和1项XCTest AX环境检查跳过，不宣称其通过。详情见 [验收台账](ACCEPTANCE.md)。

## 应用程序入口修复

用户反馈后，正式入口迁移为 `/Applications/Minget.app`，原个人目录路径为兼容软链接，10份旧备份取消启动注册且文件保留。系统应用程序入口真实启动并显示1.6.2，签名与原已测试包指纹一致。以 [启动入口记录](INSTALLATION_ENTRY.md) 为当前路径与回退说明；前文路径保留此前验收时状态。

## 发布授权更新

用户已确认应用程序入口修复，并于2026-10-01明确授权直接发布 GitHub、无需重新测试。此前未发布描述保留当时状态，当前结果见 [发布记录](PUBLICATION.md)。

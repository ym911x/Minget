# 1.6.9 发布后独立复核（2026-10-17，Asia/Singapore）

本次用户要求「审核并发布 1.6.9」时，仓库和 GitHub 已完成该版本发布。本次不重复发布、不改标签、不替换正式 App。

## 发布与证据

- 主目录 main 与远端 main 均为 `a854ee14b257f6bc4c0ed77751393944199afc45`；源码、测试、构建脚本和 VERSION 相对 v1.6.9 无差异。
- GitHub latest 返回 v1.6.9，非草稿、非预发布；标签对象 `f48a905600eea935379eb52bc48de5a4f52b7acd` 指向 `04c3ffadf709ba4a002dcf3d472cc314aca2f592`。
- 在线复查 run 39017709849，发布提交的测试及应用构建步骤均为 success；原本机发布回归 706 项（701 通过、5 跳过）不重新执行。
- 原 15 项 evidence-manifest 全部校验通过。
- 正式 App 为 1.6.9，deep/strict 签名通过，UsageMonitor SHA-256 为 `68c09e577943bd22e9f8c390b57c21304b1ab0fe738effb0969e2cd6f6fde7ae`，与安装记录相同。
- 三份 releases 历史文档的既有删除保持原状，未纳入提交；不读取认证文件、不操作真实账号或点火。

## P2：不同 ChatGPT 账号的并发刷新会丢掉页面补刷

位置：`Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift:1023–1025`。

当菜单栏显示账号 A 且 A 的刷新尚未结束时，用户打开概览或 ChatGPT 页面。页面正确选出待补刷的 B，但 `refreshProfiles(ids: [B], resetFailureBudget: false)` 遇到全局 `isRefreshing` 立即返回。仅手动请求会设置待处理标记，自动页面请求没有保存其账号集合。A 完成后只恢复菜单栏定时器，B 不会读取，页面可能继续显示旧值或无数据。

这属于 1.6.9 将全量轮次拆为不同账号集合后引入的遗漏：已有轮次 A 的结果不能满足 B 的请求。建议按 Profile 跟踪进行中的工作，或保存未被当前轮次覆盖的账号集合并在完成后继续派发；同一个账号继续合并，手动刷新语义保持。

复现使用 `git archive v1.6.9` 的隔离副本和既有合成 `makeHarness`，给 RefreshScopeTests 添加 `testOpeningPageWhileLaunchReadIsInFlightMustStillReadHiddenProfile`。在同一主 actor 回合依次调用 start 与 panelWillOpen，不引入任何计时碰运气的阻塞或真实服务调用。A 成功读取并完成后，B 在等待窗口内仍为 0。

- 新增用例单独运行：1 项、1 失败，失败点为 B 未被读取，其他前置断言通过。
- 整个 RefreshScopeTests 再运行：15 项，14 项既有测试通过，仅新增用例失败。日志见 `../logs/post-publication-refresh-scope.log`。
- 测试补丁见 `post-publication-overlap-regression.patch`，只供隔离副本复现，未写入正式 Tests，不改变原 706 项回归或发布提交。
- 临时工作副本与测试命令：`swift test --package-path <isolated-review> --scratch-path <isolated-build> --filter RefreshScopeTests`，退出码 1。

绕过方式：等待当前刷新结束后，点击品牌页「刷新」或页头「刷新全部」；重新打开页面也会再次判定未读取的 B。

## 结论

已发布状态、CI 与安装产物核对一致，但本次追加审核发现未修复的 P2，不能记为无问题通过。保留已发布的 v1.6.9，公开说明同步补充已知问题；修复应进入后续补丁，不能覆盖现有发布标签。用户此前的现场验收与本次确定性复现分别保留。

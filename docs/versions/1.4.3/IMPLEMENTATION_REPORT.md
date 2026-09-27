# 1.4.3 实施报告

状态：Codex 直接实现，未委托 Claude Code。代码、自动测试、Release arm64 严格签名、本机备份安装及真实只读服务核验完成；交互界面验收待补。

## 实现

- `CodexLaunch` 保存程序、参数前缀与环境，统一读取、应用内授权点火及 QA CLI 的生产启动路径。
- 官方系统与用户级 App 新旧布局优先，npm CLI 根据前 256 字节 shebang 识别 Node；绝对 Node 启动解析后的程序入口，并保留隔离 CODEX_HOME。
- 每个候选 `--version` 最多 2 秒；独立进程组、输出丢弃、超时杀死自有组并回收直接子进程。自动发现回退，显式覆盖失败不回退；正式 RPC 失败不触发跨候选或模型重试。
- 缺少 Node 为固定分类、须手动重试；安装恢复后同一 service 手动刷新重新发现并恢复读取。缓存和设置页提供故障原因与处理提示。
- 版本为 1.4.3；AGENTS.md 与 ROADMAP.md 的协作规则统一为 Codex 默认直接实现，用户明确要求时才委托 Claude Code。

## 执行及结果

- `swift test --scratch-path /tmp/minget-143-tests`：Core 391、App 160，共 551 项执行，550 通过，1 项既有 AX 环境跳过，0 失败。早期新增测试的枚举拼写及过短探测期限已修正；最终通过结果见 evidence/test-summary.txt。
- `scripts/build.sh`，指定 `/tmp/minget-143-release` scratch、临时 staging/review/archive：Release arm64、本地签名、严格验证通过。使用已有本地证书，没有新建证书或修改权限。
- 两账号分别以精简 PATH 和各自 CODEX_HOME 执行安装包 MingetCLI：握手、只读用量、缓存往返及子进程回收均 PASS。额外强制 npm CLI，确认绝对 Node 备用路径同样 PASS；没有模型请求。
- Finder 正常打开安装包后，Minget 进程 PATH 仍是系统四目录，且拥有两条原生 Codex 子进程。应用自己的标准化缓存于 07:55:06 和 07:57:08 更新，证明双账号启动与连续自动刷新成功。
- 应用 SIGTERM 正常退出，自有两条 Codex 子进程均回收；再次从 Finder 打开后，两个账号缓存于 07:58:41 更新，证明退出重启后真实读取恢复。
- 签名安装产物与临时审核包两个执行文件 SHA-256 完全一致，见 evidence/installation.json。

## 边界

未读取全局配置、认证文件、隔离 Profile 文件或现有浏览器会话。没有真实点火、消费重置权益或修改外部计划。GitHub 发布按用户后续明确授权进行。应用内已启用点火计划为零；安装不修改任何用户偏好。

界面工具尝试连接菜单栏应用，但浮窗收起时持续超时，无法独立操作详情页；真实点击刷新、浮窗关闭重开及视觉检查尚未验收。第二台 Mac 未实测，安装组合仅由隔离测试覆盖。

## 修改文件

- AGENTS.md
- CHANGELOG.md
- PROVIDER_ENDPOINTS.md
- README.md
- REVIEW.md
- ROADMAP.md
- Sources/UsageMonitorApp/ViewModels/CodexProfileViewState.swift
- Sources/UsageMonitorApp/Views/CodexProfileCard.swift
- Sources/UsageMonitorApp/Views/ErrorStateView.swift
- Sources/UsageMonitorApp/Views/MingetAboutView.swift
- Sources/UsageMonitorApp/Views/MingetSettingsView.swift
- Sources/UsageMonitorCLI/UsageMonitorCLI.swift
- Sources/UsageMonitorCore/Models/UsageError.swift
- Sources/UsageMonitorCore/Services/ChatGPTFireService.swift
- Sources/UsageMonitorCore/Services/CodexLaunch.swift
- Sources/UsageMonitorCore/Services/CodexLocator.swift
- Sources/UsageMonitorCore/Services/UsageService.swift
- Sources/UsageMonitorCore/Utilities/UsageFormatting.swift
- Tests/UsageMonitorAppTests/CodexStartupStateTests.swift
- Tests/UsageMonitorCoreTests/CodexLaunchTests.swift
- VERSION
- docs/versions/1.4.2/ROOT_REVIEW_SNAPSHOT.md
- docs/versions/1.4.3/ACCEPTANCE.md
- docs/versions/1.4.3/IMPLEMENTATION_REPORT.md
- docs/versions/1.4.3/IMPLEMENTATION_TASKS.md
- docs/versions/1.4.3/RELEASE_NOTES.md
- docs/versions/1.4.3/REQUIREMENTS.md
- docs/versions/1.4.3/REVIEW.md
- docs/versions/1.4.3/evidence/installation.json
- docs/versions/1.4.3/evidence/native-A.txt
- docs/versions/1.4.3/evidence/native-B.txt
- docs/versions/1.4.3/evidence/node-A.txt
- docs/versions/1.4.3/evidence/signed-build.txt
- docs/versions/1.4.3/evidence/test-summary.txt

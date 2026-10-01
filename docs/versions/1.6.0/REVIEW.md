# v1.6.0 当前审核

公开副本说明：本轮发布准备已将个人邮箱、用户目录及正式 profile UUID 替换为示例标识。真实通过/未通过结论保留；示例邮箱不能用作真实账号身份验收。


当前状态（2026-10-01）：本机 1.6.0 官方 CLI 双账号迭代已完成并安装。正式 A/B 登录、官方 `/usage`、真实卡片对账、退出重启、手动刷新及应用内官方下载校验均已通过。发布准备测试 621 项，620 通过、1 跳过、0 失败，Release 严格签名通过。第二台 Mac 验收按用户要求延期；自然令牌续期、撤销后的重新登录和真实睡眠唤醒仍待现场验证。未推送或公开发布。

## 较早阶段记录（保留当时状态）
日期：2026-10-01。状态：正式 CLI 接线已实现，真实账号和跨 Mac 验收未完成，候选未正式安装。

## 本轮检查

- 阅读最新实现、差异和关键路径，确认正常 AppContainer 使用官方 CLI 模型，旧代理网络客户端只在历史及测试目标出现。
- 修复授权后导航被禁止、初始登录方式未识别、折行 OAuth URL 未被提取、查询忽略 appdata 等具体问题。
- 身份由固定版本官方 TUI 取得；JSON 绑定 UUID，不从额度或用户自填邮箱推断账号。不读取认证文件或浏览器会话。
- 核对每账号任务、缓存、认证失败隔离；断开/替换等待自有读任务回收后清理目录，避免旧请求回写及目录复活。
- 完整测试和签名结果见 ACCEPTANCE。真实 CLI 空账号快速退出与登录 URL 路径通过；尚无正式授权后的真实额度证明。

## 尚不能通过最终验收

正式两个账号登录和官方同刻对账、真实引导复选框关闭、已登录沙箱查询、续期/授权失效、完整 updater 生命周期、第二台 Mac 与正式替换尚待验证。Mac 已锁定，已请求用户解锁。未将未完成事项记为通过。

2026-09-30 原审核保存在 history/REVIEW_BEFORE_20261001.md；10-01 早期调查见 AUDIT_20261001.md。早期暂停结论和临时账号成功均不能覆盖本轮验收。

## 2026-10-01 09:30 登录反馈修复

- 用户报告 A、B 都点击了提交授权码，数分钟无明确成功后点击完成。检查 Minget 自有 `connections.json` 不存在，官方 CLI 子进程已退出。两次正式登录未完成；不归因于用户未操作。未读取、复制官方认证文件。
- 已确认旧实现将授权码限制在 2048 字节；提交失败也会清空 SecureField；失败结束仍显示“完成”。没有保存原始授权码或 CLI 输出，无法确认本次失败是否由长度、传输、引导或官方超时导致。
- 修复：最大 16 KiB 的受限 ASCII 一次性码；PTY 关闭 canonical 缓冲限制，分块处理非阻塞短写，保证完整传输或明确报错；只有提交接受才清空输入；立即展示等待阶段；提交后无身份确认 45 秒独立失败；成功按钮“完成（已登录）”、失败按钮“关闭（未登录）”。仍仅发送授权码与已识别引导输入。
- 合成回归：AntigravityLoginSessionTests 7 项通过，包含 7000 字节完整投递、敏感回显遮蔽、提交后无输出单独超时、后续条款以及取消。日志 `/tmp/minget-login-fix-tests.log`。这些测试不证明真实账号已接入。
- Mac 界面检查连续返回 timeoutReached；App 主线程采样处于正常事件循环，无忙循环或死锁证据。真实重新授权与额度验收待继续。

- 修正版候选包已重建，严格签名通过（`/tmp/minget-google-login-fix-build.log`），正式管理窗口重新显示 A/B 未登录；UI 检查已恢复，A 的新 Google OAuth 页面已打开。等待用户重新授权，真实结果仍未通过。

## 2026-10-01 09:43 令牌交换阻断定位

- 用户填入账号 A 的码后由 Codex 点击提交，真实 UI 先显示等待，45 秒后明确显示未连接。未读取剪贴板、授权码内容或认证文件。
- 使用官方 CLI、全新空 profile 和合成无效码 `4/…` 复现。CLI 进入 Signing in，返回 `token exchange failed` / `SecPolicyCreateSSL error: 0`。旧状态机忽略该错误，造成表面无响应。
- 对照探测：去掉写入限制仍报 SSL 策略错误；将用户 HOME 的拒读从 `file-read*` 改为 `file-read-data` 后，Google 返回 `invalid_grant` / Bad Request。保留用户文件内容限制、写入范围限制、禁 fork 和禁 AppleEvents；允许系统 SSL 初始化所需文件元数据，不绕过证书校验。
- 登录 PTY 使用独立 session 和控制终端；按官方启用的 bracketed paste 协议交付授权码，再发送确认键。缺少该模式时使用换行终止。合成 probe 只访问官方认证端点，没有真实凭证、模型调用或额度消耗。
- 新增网络/证书令牌交换失败分类，避免误报为码无效或一直等待。所有临时原始屏幕诊断代码已删除，候选包无诊断输出。
- 登录及官方 CLI targeted 回归 17 项全部通过，含真实官方端点拒绝合成码，日志 `/tmp/minget-login-final-fix-tests.log`。真实 A/B 登录和额度仍待新候选包验收。

## 2026-10-01 09:48 授权后交互仍未通过

- 用户粘贴新的 A 授权码，Codex 提交后，2 秒内真实 UI 报未识别的交互提示并停止。没有账号提交。没有保存原始输出，不能确定具体官方提示，也不能将此结果记为登录成功。
- 新增固定词条安全失败摘要，不展示原始码、网址或任意 CLI 文本；识别官方套餐读取/选择失败、证书错误、权限/限流状态以及 Enter 返回/继续提示。没有把未知提示自动当作可确认的条款或模型输入。
- 待确认 profile 在失败后仅保留至窗口关闭，新增重新启动同一官方 CLI 的重试入口，便于已有官方授权继续身份确认；关闭或取消仅清理此本机 pending profile。旧连接始终保留。
- 登录会话回归 9 项通过（包括安全摘要不会包含合成秘密），日志 `/tmp/minget-postauth-tests.log`。新 App 构建记录 `/tmp/minget-google-postauth-build.log`。仍待真实双账号验收。

## 2026-10-01 09:59 保留授权并继续首次引导

- 真实 A 提交后失败摘要显示 Enter 继续与裸 403。重启同一 pending profile 的官方 CLI 直接进入配色引导，没有请求新授权。确认真实提示为 `Choose your color scheme:`，属于缺失适配；原先裸数字匹配不能证明 HTTP 403，已改为 HTTP 状态上下文匹配。
- 官方 CLI 的配色示例静态展示会出现示例工具/模型文字，不是执行模型任务；此次仅默认配色确认，没有提交模型提示。
- 修复 VT 解析 CSI E/F/d 和 CSI 1J，消除旧画面与旧复选框残留；修复可选数据收集行同时含 agree/improve 时被误标为同意条款；固定标签显示完整主题选项、条款 Done 入口与收集开关。
- 候选 QA 恢复入口仅接受尚未连接的现存 profile UUID，继续同一 CLI 自有目录，未复制或解析认证文件；正式交付前移除候选恢复参数。
- 登录会话 12 项回归通过（`/tmp/minget-onboarding-final-tests.log`），新包签名通过（`/tmp/minget-google-onboarding-build.log`）。
- 真实 UI 已显示可选交互数据收集“未勾选”，已导航至 Done。等待用户亲自确认官方条款。尚未取得正式身份或额度，不记录为连接成功。

## 2026-10-01 条款底部按钮误标修复

- 用户报告选完成后仍循环，实际官方 CLI（同一保留 pending profile，无新授权）观测确认：复选框后第一次向下选中 `> Previous [Done]`，旧转换因整行包含 done 而错误标为“完成引导”。确认动作因此实际返回配色页面。不是用户操作错误。
- 分别显示、解析 Previous 与 Done 的箭头，删除静态样例中的“继续”伪选项；仅在条款页启用切换勾选，使用官方要求的 Enter Toggle。
- 13 项登录会话回归通过，包含真实 footer 结构的上下文测试（`/tmp/minget-footer-fix-tests.log`）；真实条款确认、账号身份和额度仍待继续，不记录完成。

- 追加真实 UI 验证：Terms 底部的 Previous/Done 横向排列，向下只到 Previous，再向下不移动。已新增左右导航；新包实测依次关闭数据收集、向下到 Previous、向右到 Done，界面明确显示箭头指向“完成引导”，可选收集保持未勾选。候选严格签名通过（`/tmp/minget-google-horizontal-build.log`），等待用户本人完成条款确认。

## 2026-10-01 账号 A 正式连接与真实取数

- 用户自行确认条款后进入专用目录信任；确认目录后，新 official CLI 会话成功读到身份。Minget 使用同一 pending profile 重试身份，正常完成回调提交 slot A。`connections.json` 现有一条 A 连接；官方授权文件始终由 CLI 管理，未读取或复制。
- 正式 profile 的官方固定 `/usage` JSON 成功，status SUCCESS、num_turns=0、五类模型 token 均 0。Gemini 五小时 remaining_fraction=0.9980915784835815，weekly=0.998515248298645；重置 UTC 分别为 2026-10-01T06:40:36Z、2026-10-06T11:50:18Z。另有官方 Claude and GPT shared group，未拆分假定独立模型额度。
- 新候选包重启后的正常账号管理 UI 显示 A“已登录 / 额度已更新”，B 未登录。原 OpenAI 两账号、DeepSeek、Command Code 也回到既有已连接状态。
- 追加 alternate-screen/saved cursor 解析，防止已结束 Trust 引导残留覆盖真实身份；14 项会话回归通过（`/tmp/minget-alternate-screen-tests.log`）。严格签名通过（`/tmp/minget-google-account-a-build.log`）；候选 QA 恢复启动参数已移除。
- A 连接与后台取数、重启已通过本机实测；正常卡片逐字段对照、B 登录、双账号实测、续期与第二 Mac 仍待继续。

## 2026-10-01 双账号正式连接与本机回归

- B 官方完成引导后的身份头部含 `(Google AI Pro)`；旧解析器只接受裸邮箱，导致授权已完成却未提交连接。只在固定版本官方头部下一行接受单个规范邮箱与已实测的该套餐后缀；未知后缀及任意提示中的邮箱仍拒绝。正常登录完成回调已提交 B，没有复制、解析官方认证文件。
- 正式 A：account-a@example.com；正式 B：account-b@example.com。两账号 UUID 独立，后台使用各自绝对 HOME/appdata/workspace/tmp。用户自行关闭可选数据收集并确认条款。
- 2026-10-01 10:28–10:29 本机正式 profile 的官方固定 `/usage` 及正常应用卡片一致：A Gemini 五小时 99.81%、周 99.85%，B Gemini 五小时 98.90%、周 98.34%。卡片进度值与官方 fraction 逐项相等；A Gemini 重置分别为 10-01 14:40 / 10-06 19:50，B 为 10-01 14:40 / 10-04 11:51（Asia/Shanghai，界面显示至分钟）。Claude/GPT 按官方共享组显示，周分别 97.99% / 93.76%，五小时均 100.00%。官方未消耗窗口的重置时间在后续查询可变化，保持官方最新值，不自行固定。
- 两份报告均 SUCCESS、num_turns=0、所有模型 token=0。退出候选、正常重开账号管理后，两账号均“已登录”，自动及手动刷新均“额度已更新”；实际卡片均显示更新时间和真实重置时间。未出现后台 OAuth 浏览器、引导或更新器子进程。
- 移除仅供候选恢复 pending B 的临时参数和公开 UUID 注入入口。正常重新登录仍创建全新 profile；同一失败窗口的重试使用私有待提交 profile。增加管理窗口“继续登录”，修正启动已有连接提示，以及超时后可重试的提示。卡片百分比显示两位小数，避免 99.81% 被显示为 100%。
- 全量：`MINGET_AGY_REAL_PROBE=1 swift test --scratch-path /tmp/minget-google-implementation-20261001 --disable-sandbox`，Core 449、App 171；合计 620，619 通过、1 个既有 AX 测试跳过、0 失败。日志 `/tmp/minget-google-final-full.log`。
- Release 构建与 run/archive 严格签名通过，日志 `/tmp/minget-google-final-build.log`。`git diff --check` 通过。旧安装版备份保留；尚无远端推送或公开发布。
- 第二台 Apple Silicon Mac 首次安装、双账号登录及重启验收：用户明确要求以后再考虑，本轮延期，不记通过。真实令牌自然续期及撤销后的恢复未实测；合成失败、取消、超时、重复身份、并发隔离及旧请求回写由自动测试覆盖。

## 2026-10-01 10:32 本机交付

- 在不修改任何账号认证目录的前提下，将 Minget 专用 CLI 可执行文件临时保留为 `antigravity-1.2.13.before-installer-qa-20261001`。通过正常“准备官方 CLI”入口真实下载 Google 固定官方安装包；界面显示“官方 CLI 已准备”。下载后的 executable SHA-512 与固定值匹配，Google TeamIdentifier EQHXZ8M8AV 严格签名要求通过。原 CLI 备份保留。此项验证本机缺少 executable 的下载准备，不代替第二台 Mac 整体首次安装。
- 使用 `ditto` 创建 staging，严格签名校验通过后备份并替换 `/Users/<user>/Applications/Minget.app`。最新旧版备份：`/Users/<user>/Applications/Minget-backups/Minget-before-official-cli-20261001-103155.app`，此前备份也保留。
- 正式安装路径启动后，真实管理窗口两账号都“已登录 / 额度已更新”，正式卡片显示本次成功时间 10:32、与候选相同的真实 fraction/周期/重置时间。当前运行进程来自正式安装路径。
- CPA 进程 `/Users/<user>/Library/Application Support/AntigravityProxy/bin/cli-proxy-api` 仍在运行；没有更改 CPA 配置、系统网络出口或其他客户端配置。Minget 仅清理自身旧代理设置、Keychain 管理密钥项与旧代理缓存。
- 本地签名应用压缩包：`dist/Minget-1.6.0-official-cli-arm64.zip`；SHA-256：`a32a2bfaeea5fea8316d7d99f4001f46470d6eacd4b7ca849fb25546c37963cc`。应用包不包含账号 profile 或授权文件。签名身份为 Minget Local Signing，未进行公开分发、公证、Git 推送或 GitHub 发布。
- 结论：本轮本机官方 CLI 双账号功能交付通过。延期及长期现场验证项继续保留，不把合成测试或本机下载算作跨设备、自然续期或授权撤销验收。

## 2026-10-01 发布准备最终检查

- 本轮新增 `ReleaseScreenshotTests` 仅用于显式导出生产 SwiftUI 组件的公开示例图，不启动 CLI 或读取真实账号；四张 PNG 均已目视检查，示例标记、显示名称及管理按钮完整。双卡采用实际固定高度，额外共享组在内嵌区域滚动展示。
- `MINGET_AGY_REAL_PROBE=1 MINGET_RELEASE_SCREENSHOTS="$PWD/assets/screenshots/v1.6.0" swift test --scratch-path /tmp/minget-google-implementation-20261001 --disable-sandbox`：Core 449、App 172，总计 621；620 通过，1 个既有 CommandCode AX 环境测试跳过，0 失败。截图导出实测包含在本次执行中。完整本地日志 `/tmp/minget-160-release-preflight-tests.log`。
- `CI=true MINGET_SIGN_IDENTITY=-` 配合隔离构建/输出目录执行 `scripts/build.sh` 成功；run/archive 两份 App 严格签名校验通过。本次为本地 CI 风格检查，不是远端 GitHub Actions 结果。日志 `/tmp/minget-160-release-preflight-build.log`。
- `git diff --check`、README/CHANGELOG/发布说明/索引本地相对链接检查通过。新增/变更文本未发现个人 Gmail/iCloud 邮箱、Google OAuth access token/client secret、JWT、私钥或常见长 API Key；模板占位符和合成测试输入保留。该扫描不声称覆盖所有秘密格式。
- 个人邮箱、本机用户名和正式 profile UUID 已脱敏，私有文档原件在本地临时目录保留，不纳入 Git 或源码包。构建缓存、应用包、官方 CLI、账号目录和元数据不纳入公开源码包。
- 本地 main 是当前开发分支祖先；此次没有 fetch、push、合并 main、标签、GitHub PR 或 Release。发布时仍需重新检查远端 main 和实际 CI。
- 公开政策延续源码分发，Release / PR / 提交文案与 README 已准备；1.5.0 纳入 1.6.0 说明已补齐。第二 Mac、自然续期/撤销及真实唤醒保持待验收。

## 2026-10-01 发布时 CI 编译兼容性修复

- 首次远端 CI [36808851569](https://github.com/ym911x/Minget/actions/runs/36808851569) 在编译阶段失败：ChatGPT 登录回调的嵌套 MainActor Task 引用了外层弱捕获变量。尚未创建发布标签或 Release。
- 修改 `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift`：嵌套 Task 显式使用 `[weak self]`，保留原有弱引用和 MainActor 回调语义。
- 本机 `swift test --scratch-path /tmp/minget-google-implementation-20261001 --disable-sandbox`：621 项，616 通过、5 跳过、0 失败。此次未启用四项显式官方 CLI probe，另有一项既有 AX 环境跳过；此前真实服务验收不变。日志 `/tmp/minget-160-publication-tests.log`。
- 本轮仅修复并发捕获的编译兼容性；没有操作账号、点火或替换安装应用。后续构建、远端 CI 和公开核验记入发布记录。

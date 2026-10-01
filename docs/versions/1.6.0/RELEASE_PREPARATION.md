# Minget 1.6.0 GitHub 发布准备

准备日期：2026-10-01（Asia/Shanghai）。本次只准备本地文件和提交。**尚未推送、合并 main、创建标签、GitHub PR 或 Release。** 用户将另行安排远端操作。

## 发布元数据

| 字段 | 准备内容 |
| --- | --- |
| 仓库 | `ym911x/Minget` |
| 工作分支 | `codex/minget-google-quota` |
| 拟用标签 | `v1.6.0`，本次未创建 |
| Release 标题 | 明明有数 · Minget 1.6.0：Google 官方 CLI 双账号额度 |
| 版本 | `VERSION` = `1.6.0` |
| 日期 | 发布时填写真实发布日期，2026-10-01 仅为准备日期 |
| 分发 | 延续源码分发；本地签名应用不作为未经公证的公开下载附件 |
| 范围 | 官方 Google CLI 接入，同时包含此前未独立发布的 1.5.0 工作 |

## 已准备文件

| 文件 | 内容 |
| --- | --- |
| [RELEASE_NOTES.md](RELEASE_NOTES.md) | 完整中文更新说明、登录步骤、源码构建和验证边界 |
| [GITHUB_RELEASE_BODY.md](GITHUB_RELEASE_BODY.md) | 可直接粘贴的 Release 正文，含拟用标签的公开图片链接 |
| [PR_BODY.md](PR_BODY.md) | 需要走 PR 时使用的变更、实现与验收描述 |
| [COMMIT_MESSAGE.txt](COMMIT_MESSAGE.txt) | 本地准备提交说明 |
| 根目录 README / CHANGELOG | 当前版本、Google 使用步骤、界面预览、1.5.0 纳入说明 |
| assets/screenshots/v1.6.0/ | 四张公开展示副本和可复现渲染说明 |
| REQUIREMENTS / IMPLEMENTATION_TASKS / REVIEW / ACCEPTANCE | 最新实施、审核、真实验收及保留事项 |
| PROVIDER_ENDPOINTS / SECURITY | 官方 CLI 数据来源、固定版本及授权数据边界 |
| docs/versions/README.md | 1.5.0 / 1.6.0 文档索引 |

Release 正文的 `v1.6.0` 图片/文档链接在实际标签推送前尚不存在，属于已备好的发布目标地址。若后续更改标签，需同步替换这些链接。

## 本地验证

- 双账号真实官方授权、固定 `/usage`、真实卡片对账、手动刷新、退出重启及应用内官方下载安装已有实测通过记录。
- 本轮仅新增展示渲染和文档准备，产品代码保持本机已验收版本；渲染使用隔离示例数据，不读取或修改真实账号。
- 全量测试、CI 风格 ad-hoc 构建、差异空白检查、资料相对链接、脱敏及压缩包内容检查结果见本文件下方最终记录。
- 旧版应用备份及当前安装版保留。本次未替换安装应用、修改 CPA 或网络配置。

## 公开材料边界

本轮待提交文本已检查个人邮箱、OAuth access token/client secret、JWT、私钥及常见 API Key 模式；检查的是文件与差异，没有打开任何认证目录。1.6.0 文档中的个人邮箱、本机用户名和正式 profile UUID 已替换为示例标识，未脱敏原件仅保留在本地临时目录且不纳入仓库/源码包。

公开源码包只从准备提交的 Git tree 导出，不包含工作目录的 `dist`、构建缓存、App 包、官方 CLI、profiles、连接元数据或 Keychain。早期历史基线继续保留，`docs/archive/v1.0/` 不改动。

## 继续保留的验收项

- 第二台 Apple Silicon Mac 首次安装、双账号登录、读取和重启，按用户要求延期。
- 自然令牌续期、撤销授权后的恢复和真实睡眠唤醒，尚无现场验收证据。
- 官方 CLI 仅固定并验证 1.2.13 arm64，未验证其他版本或 Intel Google 接入。
- 远端 CI、发布标签、最终 Release 链接和公开内容检查，必须在用户安排推送后执行。

## 用户安排推送时的执行顺序

1. 读取本地 `dist/release-preparation/v1.6.0/PREPARED_REVISION.txt`，确认待推送提交与材料匹配；检查工作树有无后续修改。
2. 拉取最新远端状态并检查 main 与发布分支差异。当前本地 main 是工作分支祖先，但不以旧本地引用代替发布时的远端检查。
3. 按用户安排推送分支并创建 PR，或将经确认的内容合入 main；PR 正文使用 `PR_BODY.md`。
4. 等待实际远端 CI 成功，核对 `VERSION`、文档和公开截图。没有成功结果不得写“CI 已通过”。
5. 在最终目标提交创建并推送注释标签 `v1.6.0`；再用 `GITHUB_RELEASE_BODY.md` 和上方标题创建 Release，填写实际发布日期。
6. 延续 GitHub 自动 Source code 附件，不上传本地签名 App；如果分发政策另行改变，应先完成公证及对应验收。
7. 核对标签提交、图片、源码下载和 Release 链接，再更新 CHANGELOG / README / 验收状态。将创建的 PR 关联到相应聊天。

本次没有执行上述远端步骤。

## 2026-10-01 发布准备最终检查

- 本轮新增 `ReleaseScreenshotTests` 仅用于显式导出生产 SwiftUI 组件的公开示例图，不启动 CLI 或读取真实账号；四张 PNG 均已目视检查，示例标记、显示名称及管理按钮完整。双卡采用实际固定高度，额外共享组在内嵌区域滚动展示。
- `MINGET_AGY_REAL_PROBE=1 MINGET_RELEASE_SCREENSHOTS="$PWD/assets/screenshots/v1.6.0" swift test --scratch-path /tmp/minget-google-implementation-20261001 --disable-sandbox`：Core 449、App 172，总计 621；620 通过，1 个既有 CommandCode AX 环境测试跳过，0 失败。截图导出实测包含在本次执行中。完整本地日志 `/tmp/minget-160-release-preflight-tests.log`。
- `CI=true MINGET_SIGN_IDENTITY=-` 配合隔离构建/输出目录执行 `scripts/build.sh` 成功；run/archive 两份 App 严格签名校验通过。本次为本地 CI 风格检查，不是远端 GitHub Actions 结果。日志 `/tmp/minget-160-release-preflight-build.log`。
- `git diff --check`、README/CHANGELOG/发布说明/索引本地相对链接检查通过。新增/变更文本未发现个人 Gmail/iCloud 邮箱、Google OAuth access token/client secret、JWT、私钥或常见长 API Key；模板占位符和合成测试输入保留。该扫描不声称覆盖所有秘密格式。
- 个人邮箱、本机用户名和正式 profile UUID 已脱敏，私有文档原件在本地临时目录保留，不纳入 Git 或源码包。构建缓存、应用包、官方 CLI、账号目录和元数据不纳入公开源码包。
- 本地 main 是当前开发分支祖先；此次没有 fetch、push、合并 main、标签、GitHub PR 或 Release。发布时仍需重新检查远端 main 和实际 CI。
- 公开政策延续源码分发，Release / PR / 提交文案与 README 已准备；1.5.0 纳入 1.6.0 说明已补齐。第二 Mac、自然续期/撤销及真实唤醒保持待验收。

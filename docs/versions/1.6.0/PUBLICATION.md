# Minget 1.6.0 发布记录

发布日期：2026-10-01 11:12:40（Asia/Shanghai）。用户已明确授权发布。

## 公开结果

- [GitHub Release](https://github.com/ym911x/Minget/releases/tag/v1.6.0)：明明有数 · Minget 1.6.0：Google 官方 CLI 双账号额度。
- 已公开、非草稿、非预发布，并通过 latest API 核验为最新版本。
- 发布代码提交：`081eb194fd9070ee4cd796e5852ce7fda3bf6f3d`。
- 注释标签 `v1.6.0`：对象 `c26bc479009cca8795f59153eeb97355d836d766`，解引用为上述代码提交。发布时远端 main 同指该提交；后续发布台账作为独立文档提交，不移动发布标签。
- main 从原公开基线快进，包含此前未独立发布的 1.5.0 与本次 1.6.0。未创建 PR，无合并冲突。
- 延续源码分发；Release 自定义附件为空，GitHub 自动提供 Source code。不上传未经公证的本机签名 App。

## 修复与验证

- 首次 [CI 36808851569](https://github.com/ym911x/Minget/actions/runs/36808851569) 编译失败：Swift 5.10 不接受 ChatGPT 登录回调中嵌套 Task 的隐式弱捕获。补上 `[weak self]`，保留弱引用和 MainActor 回调语义，提交为 `081eb19`。
- 修复后本机全量测试 621 项：616 通过、5 跳过、0 失败。4 项显式官方 CLI probe 未启用，1 项既有 AX 环境跳过。此前官方 CLI 实测记录继续保留。
- 本机隔离输出的 Release 构建及 run/archive 严格签名校验通过，未替换已安装 App。日志 `/tmp/minget-160-publication-tests.log`、`/tmp/minget-160-publication-build.log`。
- 发布提交 [CI 36809159528](https://github.com/ym911x/Minget/actions/runs/36809159528) 结论 success：Swift 5.10，621 项测试，568 通过、53 跳过、0 失败；Release 构建通过。跳过项为 49 项需要 WindowServer/登录会话的 AppKit/签名应用测试及 4 项显式官方 CLI probe，不代替本机真实界面验收。
- 四张标签下公开 PNG 均 HTTP 200 / image/png；发布说明和验收台账均 HTTP 200；GitHub 源码 ZIP 下载和 CRC 完整性检查通过，共 428 个路径。
- Git tree 导出的源码包路径检查通过，无构建缓存、dist、App、账号 profile 或认证文件；四张公开图重新目视检查，均标注示例展示。
- Release 标题、正文、标签、Latest、源码附件和远端引用均已核对。

## 保留事项

第二台 Apple Silicon Mac 首次安装和双账号验收按用户要求延期；自然令牌续期、撤销后的恢复和真实睡眠唤醒待现场验证。官方 CLI 固定 1.2.13 arm64；其他版本及 Intel Google 接入未验证。

发布后的状态更新只修改文档，标签保留在经过远端 CI 的发布代码提交。早期准备、原型和未通过记录保留当时状态，不改写历史验收。

# 1.4.3 GitHub 发布核验

用户于 2026-09-27 明确授权将 1.4.3 同步到 GitHub。正式 Release 已公开发布，继续源码分发；未上传未经公证的安装包。

| 项目 | 核验结果 |
| --- | --- |
| 仓库 | ym911x/Minget，main |
| 发布提交 | `dceb9f92b4a56385e56111b6156fecca416934bf` |
| 注释标签 | `v1.4.3`，标签对象 `24c1088d0252b271362c0c7246f5311f079c0ee3`，远端解引用指向发布提交 |
| 正式 Release | [Minget v1.4.3](https://github.com/ym911x/Minget/releases/tag/v1.4.3)，非 draft、非 prerelease，Latest |
| 发布时间 | 2026-09-27 08:13:06 +08:00 |
| 公开页面 | Release 页面 HTTP 200；标签下原始 VERSION 返回 `1.4.3`、HTTP 200 |
| 发布提交 CI | [36281723231](https://github.com/ym911x/Minget/actions/runs/36281723231)，completed / success；测试与应用构建均通过 |
| 分发 | GitHub 源码归档，无安装包附件；本机安装包此前已严格签名验证 |
| 文档收尾 | 发布后将本核验及 README、CHANGELOG、ROADMAP、REVIEW、版本索引和验收台账以单独记录提交同步 main；版本标签保持发布代码提交，不移动已公开标签 |

此次发布复用同一实现阶段已完成的 551 项本机测试（550 通过、1 项既有 AX 环境跳过）和签名构建，不重复本机检查；GitHub CI 对实际发布提交重新执行测试和构建。公开证据的本机路径使用 `$HOME` 或 `$PROJECT_ROOT`，未公开凭证、账号身份或真实用量截图。

真实详情页点击/浮窗关闭重开/视觉验收尚待补充；第二台 Mac 未实测，隔离安装组合测试不代替换机实测。以上边界已同时写入公开 Release。

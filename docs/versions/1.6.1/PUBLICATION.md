# Minget 1.6.1 发布记录

2026-10-01，用户明确授权发布。已完成公开发布。

发布内容与说明见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。延续 1.6.0 的源码分发方式，不上传本机签名 App。标签在发布提交 CI 成功后创建；main、标签、Latest 与 Release 状态已核对。

本机发布前全量测试：Core 449 + App 177，共 626 项，621 通过、5 跳过、0 失败。日志见 evidence/publication-tests.log。最新正式包签名与指纹见 evidence/logo-navigation-verification.json。

最终导航的离屏示例图已生成检查，但测试进程未加载 App 品牌资源，部分 Logo 使用备用符号，设置页离屏渲染也有选中行文字异常，因此没有将这些图作为最终公开预览。此前示例图保留其原始证据状态，本次 Release 以文字说明和实际签名界面验收记录为依据。

## 最终远端结果

- [GitHub Release v1.6.1](https://github.com/ym911x/Minget/releases/tag/v1.6.1)，发布于 2026-10-01 14:33:06（Asia/Shanghai）；非草稿、非预发布，latest API 返回 v1.6.1。
- 发布代码提交 `cab88c8332ddea06fab7c6a82e5c52374dc9bcd4`；注释标签对象 `eab870f264de50e6532dffefd2ed941ca073a118`，解引用为该提交。发布时 main 同指该提交，后续台账文档不移动标签。
- [CI 36825095420](https://github.com/ym911x/Minget/actions/runs/36825095420) success：Swift 5.10，626 项，572 通过、54 跳过、0 失败；Release 构建成功。跳过项包含 50 项需要 WindowServer/登录会话的界面、签名启动与原生弹层测试以及 4 项显式 CLI probe，不代替本机验收。
- Release 自定义附件为空，GitHub 自动提供源码。Source ZIP HTTP 200，466 个路径，CRC 完整性通过；标签下发布说明 HTTP 200。Python HTTPS 读取因本机证书链配置失败，改用正常验证证书的 curl 完成下载检查，没有绕过 TLS 验证。
- 未创建 PR；主目录 main 已快进整合本轮开发。原冻结版本和安装备份保留。用户本次明确授权公开发布，第二 Mac 与其他现场边界继续保留。

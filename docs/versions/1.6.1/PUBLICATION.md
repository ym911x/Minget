# Minget 1.6.1 发布记录

2026-10-01，用户明确授权发布。当前为发布准备状态，最终远端结果随后补记。

发布内容与说明见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。延续 1.6.0 的源码分发方式，不上传本机签名 App。标签将在发布提交 CI 成功后创建，最终核对 main、标签、Latest 与 Release 状态。

本机发布前全量测试：Core 449 + App 177，共 626 项，621 通过、5 跳过、0 失败。日志见 evidence/publication-tests.log。最新正式包签名与指纹见 evidence/logo-navigation-verification.json。

最终导航的离屏示例图已生成检查，但测试进程未加载 App 品牌资源，部分 Logo 使用备用符号，设置页离屏渲染也有选中行文字异常，因此没有将这些图作为最终公开预览。此前示例图保留其原始证据状态，本次 Release 以文字说明和实际签名界面验收记录为依据。

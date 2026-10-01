# 1.6.3 实施任务

开发入口：主目录 `codex/minget-1-6-3`，起点 `ee7bc0a`。

1. 账号注册表、元数据迁移、动态 Google Profile 和 ChatGPT Runtime。
2. API 实例凭证键、独立 reader/engine/cache，账号级刷新与失败处理。
3. 统一添加表单、平台入口、命名、重新连接和确认移除。
4. 动态概览、详情、菜单栏选择和点火计划，保持 1.6.2 展示样式。
5. 迁移、隔离、取消、重复身份、失败移除、串行假 CLI、布局回归和完整测试。
6. Release 候选严格签名、真实界面核验、备份安装、文档与验收台账。

任务 1–6 已完成本机实施、自动回归、签名、备份安装和入口检查。真实新增账号及服务端操作保留待验收，见 IMPLEMENTATION_REPORT.md、REVIEW.md、ACCEPTANCE.md。

7. 用户现场反馈后补充 Google 地区资格错误分类和真实缓存标记。实施与验证记录见 GOOGLE_ELIGIBILITY_FIX.md。

8. 用户现场反馈后取消概要固定高度限制，完整概要无滚动容器，保留详情滚动和物理屏幕兜底。见 OVERVIEW_HEIGHT_FIX.md。

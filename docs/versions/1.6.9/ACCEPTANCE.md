# 1.6.9 验收

| 项目 | 状态 |
| --- | --- |
| 需求与任务 | 已落 [REQUIREMENTS.md](REQUIREMENTS.md)、[IMPLEMENTATION_TASKS.md](IMPLEMENTATION_TASKS.md) |
| 代码与自动验证 | 通过：706 项（Core 457 + App 249），701 通过、5 项既有跳过、0 失败；日志 [evidence/logs/swift-tests.log](evidence/logs/swift-tests.log) |
| 签名构建与安装 | 通过：Release 严格签名，staging、正式路径与归档三处可执行文件哈希一致（`68c09e57…`）；记录 [evidence/records/local-install.txt](evidence/records/local-install.txt) |
| 真实界面与请求节奏 | **已通过**：用户 2026-10-17 在正式安装版上复验，结论「可以了」，同意固化并准备发布 |

## 用户复验要点

1. 菜单栏显示的账号按原有节奏刷新（ChatGPT 约 30/60/120 秒自适应，DeepSeek、Command Code、Google 约 5 分钟；低额度加速仍按设置生效）；未在菜单栏显示的账号在后台不再有请求。
2. 打开概览页：未在菜单栏显示的账号补刷一次；5 分钟内重复打开不触发，超过 5 分钟再打开触发一次。
3. 打开某个品牌页（如 ChatGPT）：只补刷该品牌中未显示的账号，其他品牌不动；5 分钟规则一致。
4. 面板内切换标签：切到哪个页面就按该页面补刷一次，同样遵守 5 分钟门槛。
5. 页头「刷新全部」、品牌页「刷新」与点火后的确认读取不受门槛限制，点击立即执行。

用户复验时间与结论：2026-10-17，「可以了，1.6.9 可以固化了准备发布」。本版本随后的发布准备见 [PUBLICATION.md](PUBLICATION.md)。

## 发布后发现

本次独立复核发现 ChatGPT 并发刷新下页面补刷可能被丢弃的 P2，尚未修复。确定性复现及绕过方式见 [复核记录](evidence/records/post-publication-review.md)。此前用户验收结论保留，新增场景不记通过。

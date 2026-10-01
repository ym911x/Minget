# 1.6.3 发布记录

2026-10-01（Asia/Shanghai）：用户明确表示已检查完成，并授权“现在直接发布 GitHub”。此前仅本机交付的边界由本次授权变更，现可推送 main、新增 annotated tag v1.6.3 并创建公开 Latest Release。

发布范围：ym911x/Minget 的源码及版本资料，不附本机签名 App。沿用已完成的 660 项本机回归、签名安装和用户界面验收；真实新账号的资格/取数、移除及点火待验收项保留，不因为发布而记为通过。

公开前核对 main 可快进、VERSION 与正式 App 均为 1.6.3、安装指纹及证据 manifest 一致。本轮版本文本内的本机路径统一为 $HOME / $PROJECT_ROOT，不公开真实截图、认证文件、Key 或原始服务报告。测试结果不改写，manifest 按当前文件重算。

## 完成与核验

- 发布时间：2026-10-01 22:35:07（Asia/Shanghai）。
- Release：[v1.6.3](https://github.com/ym911x/Minget/releases/tag/v1.6.3)，Latest、非草稿、非预发布；公开页面 HTTP 200，无自定义附件，继续源码分发。
- 发布代码：`a5c504327b41aba3f24a2b8f0cb74af88a112546`。
- Annotated tag：`cf633806c155a5ecd17c76224788c1b06259409a`，解引用到上述发布提交，远端引用一致。
- [GitHub CI](https://github.com/ym911x/Minget/actions/runs/36877035643) 对发布提交成功：660 项，605 通过、55 项 CI 环境跳过、0 失败；构建及 ad-hoc 包严格校验通过。环境跳过不记为通过。本机记录为 655 通过/5 跳过，二者环境不同。
- 主目录 main 已从 1.6.2 基线快进到发布代码，本次后续文档提交同步最终台账，版本标签保持不变。
- 后续提交仅修改文档及脱敏证据，使用 `[skip ci]` 避免重复构建；源码、测试、构建脚本和版本相对发布标签无变化。CI 通过针对上述发布代码，不宣称后续文档提交另跑 CI。
- 本机正式 App 保持 1.6.3，严格签名及 overview-install.txt 指纹一致；发布期间未重新构建、替换应用或修改登录与计划。
- evidence/github-ci-summary.json、github-release-summary.json 保存远端核验摘要；root README、状态、审核和版本索引同步发布结论。

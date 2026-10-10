# 当前审核状态

当前对象为 **1.6.6 Gemini 其他额度组直显与概览条等长**。Gemini 详情卡把 `Claude and GPT models` 一组直接显示在主额度下方并改用 Claude 橙 `#D97757`（低于 20% 仍为红），删去「最近成功 hh:mm / 缓存数据」行与「其他额度组」折叠控件；概览页 ChatGPT 与 Gemini 的额度图示由 164 pt 加宽到 224 pt，与 Command Code 双列等长，名称列压到约 92 pt 后名称截断、状态小字先缩字号再截断。构建与 689 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名后装入正式路径；Codex 正式界面检查与 Gemini 只读刷新通过，用户体验及未执行项保留，见 [验收台账](docs/versions/1.6.6/ACCEPTANCE.md)。

- [当前项目状态](PROJECT_STATUS.md)
- [实施记录](docs/versions/1.6.6/IMPLEMENTATION_REPORT.md)
- [代码与验证审核](docs/versions/1.6.6/REVIEW.md)
- [验收台账](docs/versions/1.6.6/ACCEPTANCE.md)

上一发布版本 1.6.5 已公开发布，远端测试与应用构建通过，核验见 [1.6.5 发布记录](docs/versions/1.6.5/PUBLICATION.md)。其现场待验收项不因本版本改变；历史版本记录保持原样。

用户已明确授权发布，独立回归复测 689 项通过；远端结果见 [1.6.6 发布记录](docs/versions/1.6.6/PUBLICATION.md)。回滚路径与备份见 [1.6.6 回滚](docs/versions/1.6.6/ROLLBACK.md)。

1.6.6 已公开发布为 Latest，发布提交 `78c57ba` 的 GitHub CI 首次通过：689 项、634 通过、55 项环境跳过、0 失败；Release 构建与严格签名校验通过。主目录 main 已同步发布提交及台账，正式 App 指纹一致。首次本机回归失败与复测结果保留在发布记录中。

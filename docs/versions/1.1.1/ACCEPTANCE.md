# 1.1.1 验收台账

| 项目 | 状态 | 依据 |
| --- | --- | --- |
| GLM 运行时代码、网络和 WebKit 路径移除 | 已完成 | 代码与自动测试构建 |
| 旧 GLM 本应用数据迁移 | 已实现 | `ProviderRetirementMigration` |
| 服务设置模块、退出文案、项目主页链接 | 已通过真实界面检查 | 正常启动 `/Users/yuyimeng/Applications/Minget.app`，确认 OpenAI Codex 与 DeepSeek 合并服务模块、退出文案、关于弹层和 GitHub 链接 |
| 自动化测试 | 通过 | `swift test`，292 项通过 |
| Release 构建与签名 | 通过 | `scripts/build.sh`，`codesign --verify --deep --strict` 与 Info.plist 版本 1.1.1 已检查 |
| 关于弹层关闭 | 已通过真实界面检查 | 弹层外点击与 Escape 均可关闭；GitHub 链接触发默认浏览器 |
| 退出按钮真实点击 | 未执行 | 为避免中断当前菜单栏进程，本轮未点击；受控停机自动测试通过 |
| DeepSeek 与真实 Codex 服务请求 | 未重新验证 | 本轮未重新发起真实账号或本机服务请求 |

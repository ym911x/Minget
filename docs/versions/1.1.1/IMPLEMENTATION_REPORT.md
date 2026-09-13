# 1.1.1 实施报告

日期：2026-09-13

## 完成内容

- GLM 的 provider、控制台会话、WebKit 视图、设置、详情卡片、诊断与专属测试已删除。
- `ProviderPlatform` 只保留 `codex` 和 `deepseek`。生产组合根只构造 DeepSeek reader。
- `ProviderRetirementMigration` 在初始化读取器前清理旧 GLM 的两个本应用 Keychain account 名称、`glm#` 缓存项、连接模式与 `detail.showGLM`。没有记录或读取凭据值。删除失败时不设置完成标记，因此下次启动继续尝试。
- 设置页使用一个“服务”模块；OpenAI Codex 显示固定详情状态，DeepSeek 显示状态、开关和管理入口。退出文案与关于链接已更新。

## 已执行验证

- `swift test`：292 项通过，0 失败。
- `scripts/build.sh`：Release 构建、项目签名、Info.plist 版本 1.1.1 及严格签名检查通过。

## 独立复核与限制

- 正常启动 `/Users/yuyimeng/Applications/Minget.app` 后已确认服务设置模块、退出文案、关于弹层、弹层外点击、Escape 和 GitHub 链接。
- DeepSeek 真实账号和 OpenAI Codex 本机服务未在本次实现中重新请求；真实 Keychain 迁移仍需在带有旧 GLM 数据的升级环境确认。

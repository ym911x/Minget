# 变更记录

## 1.0.1（2026-09-10）

### 品牌

- 对外产品品牌由工程代号 UsageMonitor 更新为「明明有数 · Minget」。
- 确立品牌视觉符号 `M²`，以及固定的中英文 Slogan。
- 更新 README、应用显示名称、关于页面、菜单栏识别和应用图标。
- Swift Package、Target、Bundle Identifier、缓存键以及 v1.0 历史归档继续保留原工程标识。

## 1.0.0（2026-09-10）

首个完成实际运行验证的正式版本。

### 功能

- 在 macOS 菜单栏显示 Codex 额度，并展示 5 小时额度、周额度、重置时间和更新时间。
- 显示当前 Codex 账号名称。
- 检测菜单栏状态项与屏幕刘海安全区域的关系，在屏幕切换、唤醒、位置变化及每 10 秒本地检查时更新状态。
- 通过 DeepSeek 官方余额接口读取总余额、充值余额和赠送余额。
- 通过智谱控制台独立登录会话读取余额、累计充值、累计赠送、累计消费和冻结金额。
- 使用 macOS Keychain 保存服务凭据，并在本机保存非敏感缓存和偏好设置。
- 支持手动刷新、自动刷新、开机启动及菜单栏显示方式设置。

### 验证

- 自动化测试：274 项通过，0 项失败。
- Release 应用完成构建、Info.plist 校验和代码签名校验。
- 用户完成 Codex、DeepSeek 和智谱 GLM 的实际连接与余额显示验证。

### 已知限制

- 智谱取数依赖控制台当前的网页接口和登录会话，控制台改版后可能需要适配。
- 长时间运行下的智谱登录会话寿命仍需在后续版本持续观察。
- 当前为 Apple Silicon 构建，尚未制作通用二进制或公证安装包。

---

## English summary

### 1.0.1 (2026-09-10)

- Updated the public product identity from the `UsageMonitor` engineering name to **明明有数 · Minget**.
- Added the M² app icon, bilingual slogans, About view, branded app bundle name, and public documentation.
- Retained internal package, target, bundle identifier, persistence keys, and frozen v1.0 archive names for compatibility.

### 1.0.0 (2026-09-10)

The first user-validated release. It displays Codex usage windows and account identity, DeepSeek balances, and Zhipu GLM console balances. The release passed 274 automated tests and a local Apple Silicon release build. The app is ad-hoc signed and is not yet notarized for public binary distribution.

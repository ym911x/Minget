# Minget 1.4.1 外观优化说明

## 详情页

- 放大标题、额度和辅助文字，按头部、周期组、摘要使用留白分层；卡片内不再使用细分隔线。
- 版本号与“明明有数”同行显示。
- ChatGPT 头部改为自定义名称、套餐加连接绿点两行结构；DeepSeek 增加服务器状态和官方状态页入口。
- 保持 5 小时 5 格、周额度 7 格；Command Code 月度重置时间使用连续条并显示 `天数 · 日期`。
- Command Code 当前计费周期拆为 Token／成本和请求／结果两行。
- 短屏只滚动卡片区，标题和页面结构保持稳定。
- OpenAI Logo 使用官方 SVG 的裁边矢量副本，提升小尺寸清晰度；DeepSeek Logo 按鲸鱼图案边界裁去画布空白，增大实际图案并校准左缘；Command Code 使用默认名称时，副标题不再重复显示品牌名。

## 名称偏好

- 设置页新增 OpenAI 账号 A、OpenAI 账号 B、DeepSeek、Command Code 的本地显示名称输入。
- 名称支持保存、恢复默认、首尾空白清理和 40 个字符限制；允许重名。
- 详情页、设置来源、点火计划和相关辅助功能使用同一名称偏好；菜单栏仍保留 A/B/DS 短标签。

## 验证

- 517 项自动测试执行，516 通过、1 项既有 AX 环境测试跳过、0 失败。
- Release arm64 构建、staging/install/archive 严格签名和已安装应用重启通过。
- 用户通过真实签名应用界面确认整体布局、显示名称以及 OpenAI／DeepSeek Logo 的清晰度、比例和对齐。

## 获取与构建

本 Release 提供 GitHub 自动生成的源码归档。项目当前使用本地稳定签名，尚未经过 Apple Developer ID 公证，因此不附带面向普通用户分发的安装包。Apple Silicon Mac 可从源码执行 `./scripts/build.sh`，生成并安装到 `~/Applications/Minget.app`。

本版本不改变账号绑定、Keychain、缓存、刷新、点火计划执行逻辑或网络接口。

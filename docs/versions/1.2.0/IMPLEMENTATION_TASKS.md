# 1.2.0 实施任务

| 项目 | 状态 | 依据 |
| --- | --- | --- |
| Provider 类型、用量模型、缓存兼容 | 已实现 | 可选 Codable 字段保持旧 DeepSeek 缓存可解码 |
| Keychain 凭证、刷新引擎、认证暂停和断开清理 | 已实现 | 复用既有凭证协调器与 ProviderRefreshEngine |
| 精确请求白名单和模型端点阻断 | 已实现 | CommandCodeProviderTests 与 ProviderRequestGuard |
| 设置、显示偏好、固定高度详情卡 | 已实现 | 320/420/530/630 点布局测试 |
| API 响应解析与失败保守处理 | 已实现 | 合成 fixture、401、缺字段、零上限和订阅可选失败测试 |
| 官方浅色和深色 Logomark 资源 | 已实现 | 纳入品牌页提供的两份原始符号资源，不与 Wordmark 组合 |
| 真实 API Key 字段与周期核对 | 待用户验收 | 不读取任何现有浏览器或 CLI 凭证 |
| 真实界面检查、Release 构建和签名检查 | 部分完成 | 用户截图确认真实双卡和返回数据；Release 构建与严格签名通过；修复后的持续显示仍待复验 |

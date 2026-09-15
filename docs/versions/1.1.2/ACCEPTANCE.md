# 1.1.2 验收台账

| 项目 | 状态 | 依据 |
| --- | --- | --- |
| 菜单栏不再进入仅 `5H` 模式 | 已验证 | 状态机、渲染和 AppKit 接线测试；Release 包已正常启动 |
| OpenAI 重置数量和到期显示 | 已验证 | 解析和格式化测试；真实 `codex app-server` 样本返回数量与最近到期时间；真实详情窗口已显示 |
| 缓存和非法重置字段安全处理 | 已验证 | 快照兼容、缓存来源隔离和异常字段测试 |
| DeepSeek 卡片布局调整 | 已验证 | CUA 真实详情窗口确认 Logo、同列垂直居中余额和 Logo 下方状态 |
| 详情页整页显示 | 已验证 | 移除纵向滚动容器；固定高度与无 `NSScrollView` 回归测试 |
| DeepSeek 请求边界未扩展 | 已实现 | 代码差异和 Provider 允许路径测试 |
| 自动化测试 | 已验证 | `swift test`：301 项通过，0 失败 |
| Release 构建和严格签名 | 已验证 | `./scripts/build.sh`、Info.plist 版本检查、`codesign --verify --deep --strict` |
| 远端发布 | 已完成 | [GitHub Release v1.1.2](https://github.com/ym911x/Minget/releases/tag/v1.1.2)，标签与发布说明对应本次验收内容 |

## 真实证据

1. `open /Users/yuyimeng/Applications/Minget.app` 正常启动安装包。
2. `/Users/yuyimeng/Applications/Minget.app/Contents/MacOS/MingetCLI --timeout 10` 使用真实 `codex app-server`，握手成功；当次响应返回两个可用重置并带最近有效到期时间，缓存往返检查通过。
3. CUA 读取详情窗口，确认 OpenAI 重置摘要和 DeepSeek 同列余额重排，未见滚动条。真实邮箱、余额和截图未写入仓库。
4. 对于未提供重置字段的账号响应，测试和运行时均记录为“重置信息暂不可用”，没有用 fixture 替代真实结论。

## 未执行项

- 未调用 `account/rateLimitResetCredit/consume`，没有新增写操作。
- 已按用户授权推送 `main`、创建 `v1.1.2` 标签并发布 GitHub Release；未执行重置消费或其他写操作。
- 未将含个人信息的实时画面作为 1.1.2 公开截图；README 继续使用明确标注的 1.1.1 脱敏基线。

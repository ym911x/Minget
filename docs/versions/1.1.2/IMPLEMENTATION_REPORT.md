# 1.1.2 实施报告

日期：2026-09-14

结论：1.1.2 的三项修订及本次详情布局细节已经实现。代码、自动测试、Release 构建、严格签名和一次真实服务与真实详情界面检查均已完成，并已按用户授权推送远端、创建 `v1.1.2` 标签和发布 [GitHub Release](https://github.com/ym911x/Minget/releases/tag/v1.1.2)。

## 已实现

- Core 增加 `RateLimitResetCredits`，只保存 OpenAI `rateLimitResetCredits` 的规范化可用数量和最近未来到期时间，不保存重置 ID、标题或描述。
- 快照持久化增加可选重置摘要字段，旧 1.1.1 缓存仍可解码；缓存、字段缺失和非法值统一显示“重置信息暂不可用”，不会把缓存权益当作当前权益。
- 菜单栏生产状态机只保留完整和紧凑双额度模式。紧凑模式固定保留 `5H`、`W` 和两排重置时间条；空间不足时打开详情窗口，不输出残缺的单行 `5H`。
- OpenAI 详情卡在额度轨道下增加可用重置摘要行，支持数量为 0、只有数量和数量加最近到期时间三种显示状态。本版没有消费按钮或写请求。
- DeepSeek 详情卡保留鲸鱼 Logo 和现有文字标识，真实余额与品牌同列右侧并垂直居中，状态位于 Logo 下方。未连接、缓存和余额不可用时继续使用原有设置入口。
- 详情页移除纵向滚动容器，按 DeepSeek 显示开关使用 420/320 点固定高度，整页内容直接可见并收紧底部留白。
- 未新增 DeepSeek 请求、账号接口或浏览器会话读取路径。

## 自动验证

- `swift test`：301 项测试通过，0 失败。
- `./scripts/build.sh`：Swift Release 构建、暂存包校验、安装包校验和归档包生成均通过。
- `plutil -p /Users/yuyimeng/Applications/Minget.app/Contents/Info.plist`：`CFBundleShortVersionString` 为 `1.1.2`。
- `codesign --verify --deep --strict --verbose=2 /Users/yuyimeng/Applications/Minget.app`：通过，使用项目本地签名身份。
- `git diff --check`：通过。

## 真实验证

- 使用正常 `open /Users/yuyimeng/Applications/Minget.app` 启动安装包，再运行 `MingetCLI --timeout 10`。CLI 完成真实 `codex app-server` 握手，实时响应返回两个额度窗口和 `availableCount=2`，并提供最近有效到期时间；缓存往返检查通过。
- 通过 CUA 读取真实详情窗口。画面显示版本 `1.1.2`、OpenAI 可用重置摘要，以及 DeepSeek 的 Logo、同列右侧余额和 Logo 下方状态。真实账号邮箱和余额未写入文档或公开截图。
- 真实服务是否返回重置字段取决于当次账号响应。若响应缺失、为空或非法，程序按“重置信息暂不可用”处理；本次设备样本提供了可验证字段。

## 截图与边界

本轮真实详情画面含个人账号和余额，因此没有把原始截图写入仓库。README 保留已脱敏的 1.1.1 历史基线，并明确标注版本；后续若补充 1.1.2 公开截图，只使用明确标注的脱敏副本。`.workbuddy/` 保持未跟踪，凭证未改动；远端发布状态以本报告开头的 GitHub Release 链接为准。

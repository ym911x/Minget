# 1.4.1 审核状态

状态：代码、构建、真实界面和 GitHub 发布审核完成；完整自动测试、Release arm64 构建、严格签名和发布提交 CI 已通过。用户已确认 OpenAI 与 DeepSeek Logo 的可见边界修订。

## 当前审核结论

- 详情页仍由 `UsagePanelView`、`CodexProfileCard`、`DeepSeekOverviewCard` 和 `CommandCodeOverviewCard` 组成，四张卡片共用固定 440 pt 单列几何。
- 卡片高度和页面首选高度由 `DetailPageLayout` 统一计算；短屏只把滚动区域放在卡片区，标题保持可见。
- `DisplayNamePreferences` 只保存四个固定服务／Profile ID 的显示文字，不接触凭证、缓存或网络层。
- ChatGPT 绿点只在实时 `UsageDisplay.live` 时出现；DeepSeek 绿点只在 `ProviderConnectionState.connected` 时出现。其他状态继续输出文字。
- Command Code 的月度条使用连续进度模型，统计两行按 Token／请求分组，未知字段保持 `—`。

## 待完成检查

- [x] 编译通过，核心与界面布局定向测试通过。
- [x] 明暗模式示例渲染测试通过。
- [x] 名称偏好持久化、默认恢复和输入边界测试通过。
- [x] 完整自动测试结果记录：Core 360 项通过；App 157 项执行，156 通过、1 项因 XCTest 环境没有 AX 窗口而跳过；合计 517 项执行，516 通过、0 失败。
- [x] Release arm64 构建、严格签名和安装包版本核对：`CFBundleShortVersionString=1.4.1`，`codesign --verify --strict --verbose=2` 通过。
- [x] 用户提供真实 1.4.1 截图，确认版本同行、名称同步、两行头部、时间条和统计分组整体可接受；唯一明确问题是 OpenAI Logo 偏小。
- [x] 检查确认 OpenAI 官方 SVG 的图案只占 716 × 716 画布中央约 356 × 356；保留原件并新增裁剪 `viewBox` 的矢量 UI 副本，取消会使小图标发虚的 `.scaleEffect(2)`。Command Code 默认名称下的副标题同时去除重复品牌字样。
- [x] 检查确认 DeepSeek 92 × 84 px 图片中的鲸鱼实际约为 64 × 48 px；透明 UI 副本按图案边界裁边并保留 2 px 余量，使 34 pt 槽内可见图案约为 32 × 24 pt，并以模板色适配明暗模式。
- [x] 修订后 517 项测试执行，516 通过、1 项既有 AX 环境跳过、0 失败；Release arm64 构建、严格签名、安装和应用重启通过。
- [x] 用户确认 OpenAI 与 DeepSeek Logo 的清晰度、比例和对齐，并授权正式发布和推送。
- [x] `v1.4.1` annotated tag 指向发布提交 `2d05344`；GitHub Release 为非草稿、非预发布并标记 Latest；CI `35549933542` 成功。

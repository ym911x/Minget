# Minget 1.6.0 公开展示截图

全部使用当前正式 SwiftUI 组件、隔离示例账号和固定示例数据生成。图片内标注“展示副本 · 示例账号与数据”；不是实际账号截图，不作为真实取数或跨设备验收证据。

| 文件 | 用途 |
| --- | --- |
| `google-dual-light.png` | 浅色双账号额度卡片，README / Release 主图 |
| `google-dual-dark.png` | 深色双账号额度卡片 |
| `google-accounts-light.png` | 已连接账号管理、登录/额度状态、改名与本机断开 |
| `google-connect-light.png` | 没有连接时的官方 CLI 准备与两个登录入口 |

卡片保留正式固定高度及内嵌滚动区域；图片主要显示 Gemini 5 小时和周额度，更多共享额度组可在实际应用中滚动查看。没有修改真实账号、替换运行应用的缓存或发起登录/网络调用。

## 复现

在项目根目录运行：

```sh
MINGET_RELEASE_SCREENSHOTS="$PWD/assets/screenshots/v1.6.0" \
  swift test --scratch-path "${TMPDIR:-/tmp}/minget-release-screenshots" \
  --filter ReleaseScreenshotTests
```

需要本机 macOS WindowServer。渲染器位于 `Tests/UsageMonitorAppTests/ReleaseScreenshotTests.swift`；没有输出变量时不导出截图。重新生成后应逐图目视检查文字、裁切、示例标记及账号信息。

## 导出文件校验

| 文件 | 像素 | SHA-256 |
| --- | --- | --- |
| `google-accounts-light.png` | 920 × 860 | `d695578c291ccd72e64a0f4de0577c1ef2026b9874f9c43ac468f03c41c80873` |
| `google-connect-light.png` | 920 × 720 | `d1d59e3541332c54ed27ce5787ba723c80185c20a9264f5393b0b8f93e6431c5` |
| `google-dual-dark.png` | 920 × 1292 | `5589da25b908d766b3261a37452795be7ac281b1d62c94ece4f0448bb42719dc` |
| `google-dual-light.png` | 920 × 1292 | `0b3d013430e69375bfd6244e0dbfeb7b0cb81c9ed6f6b1c403f3552f2dfd95de` |

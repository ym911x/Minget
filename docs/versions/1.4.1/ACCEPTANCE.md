# 1.4.1 验收台账

当前状态：发布验收通过，用户于 2026-09-21 确认 OpenAI 与 DeepSeek Logo 修订并授权正式发布；待创建 `v1.4.1` 标签与 GitHub Release。

| 项目 | 当前状态 | 验收依据 |
| --- | --- | --- |
| 440 pt 单列与首选高度 | 自动通过 | `DetailPanelLayoutTests` 锁定四种显示组合与卡片几何 |
| 短屏滚动范围 | 自动通过 | 首选高度无滚动；短 viewport 只出现一个卡片区滚动容器 |
| ChatGPT 两行头部和绿点 | 自动通过 | `CodexProfileCard` 视图与状态测试；实时／缓存／失败状态分支 |
| DeepSeek 两行头部和服务器状态 | 自动通过 | `DeepSeekOverviewCard` 渲染测试；状态文案按实际状态映射 |
| 5／7 格时间条与连续月度条 | 自动通过 | `DetailPanelLayoutTests` 时间条断言 |
| Command Code 两行统计 | 自动通过 | Token／成本和请求／成功率分组断言，缺失值保持 `—` |
| 名称保存与恢复默认 | 自动通过 | `DisplayNamePreferencesTests`，UserDefaults 版本键和 40 字符限制 |
| 名称显示同步 | 通过 | 用户真实界面截图确认详情页名称；详情页、设置来源、点火计划和辅助标签共用 `DisplayNamePreferences` |
| 明暗模式与示例渲染 | 自动通过 | `DetailEvidenceRenderTests` 输出临时目录明暗 PNG |
| 完整自动测试 | 通过 | `swift test --disable-sandbox --scratch-path ...`：Core 360 通过；App 157 执行、156 通过、1 跳过；合计 517 执行、516 通过、0 失败 |
| Release 构建与严格签名 | 通过 | `scripts/build.sh` 完成 arm64 staging/install/archive；安装包 `CFBundleShortVersionString=1.4.1`，严格签名验证通过 |
| 真实签名应用界面 | 通过 | 用户提供真实 1.4.1 截图并确认整体效果；Logo 修订包重新签名安装并重启后，用户确认可正式发布 |
| OpenAI Logo 清晰度与比例 | 通过 | 保留官方 SVG 原件，以裁剪 `viewBox` 的 UI 矢量副本移除约 50% 透明画布；28 pt 槽内直接矢量渲染，不再后置放大；用户确认 |
| DeepSeek Logo 比例与对齐 | 通过 | 按 64 × 48 px 鲸鱼图案裁去原 92 × 84 px 画布空白和白底并保留 2 px 余量；34 pt 槽内可见图案约 32 × 24 pt，模板色适配明暗模式；用户确认 |
| 发布与远端推送 | 已授权，待执行 | 用户于 2026-09-21 明确授权正式发布到 GitHub |

# 1.6.6 验收台账

日期：2026-10-10，Asia/Singapore。本轮为本机小版本迭代：已完成编码、完整回归、示例渲染、Release 严格签名并装入正式路径。用户随后明确要求审核并发布 1.6.6，发布结果单独记录在 [PUBLICATION.md](PUBLICATION.md)。

## 自动验证

| 项目 | 结果与依据 |
| --- | --- |
| 构建 | `swift build --build-tests` 退出码 0，无新增警告 |
| 完整回归 | 689 项执行（Core 462 + App 227），684 通过、5 项既有跳过、0 失败，退出码 0；日志 `evidence/logs/swift-tests.log` |
| Claude 橙口径 | 100/50.01/50/20 → `#D97757`，19.99/0 → 红，NaN/∞/−1/101 → 次要灰；`levels` 三档（>50 绿 / 20–50 橙 / <20 红）未变 |
| 主组与分组选择 | `otherGroups` 排除主组且保持服务端顺序；主组 `levels`、`Claude and GPT models` `claudeModels` |
| 概览图示宽度 | `.codex` 与 `.gemini` 两列为 224 pt；Command Code 单列仍 164 pt；余额行 164 pt |
| 弹层稳定性 | 品牌切换（含 Gemini 页）不替换浮窗宿主、不移动浮窗；折叠状态移除后仍通过 |
| 示例渲染 | Gemini 卡片、Gemini 品牌页、概览页与概览边界行明暗各一张；`evidence/screenshots/` |
| 配色像素核对 | `google-dual-light.png` 中该组「剩余 73.50%」文字像素转换为 sRGB 后为 (217, 119, 87) = `#D97757` |
| Release 构建与签名 | `Minget Local Signing`，staging / 安装路径 / archive 三处严格校验通过；`evidence/logs/release-build-staging.log` |
| 本机安装 | `/Applications/Minget.app` = 1.6.6，安装前后可执行文件哈希一致；`evidence/records/local-install.txt` |

跳过项：4 项未开启的显式官方 CLI 探针（Core）与 1 项测试运行器未获辅助功能信任的 AX 用例（App），均为既有跳过，未为通过而修改断言。

## 现场验收状态

| 场景 | 状态 |
| --- | --- |
| Gemini 详情卡中两组额度直接相连，无「最近成功」行与「其他额度组」折叠控件 | Codex 在正式 1.6.6 的三个真实账号中检查通过；用户体验复验未单独确认 |
| `Claude and GPT models` 一组用量为 Claude 橙、低于 20% 为红，重置时间条仍为蓝 | 正式界面橙色与蓝色通过；真实账号未处于低于 20% 状态，红档仅由自动测试覆盖 |
| 主额度组与 ChatGPT 卡片的绿/橙/红分级未变 | 正式界面绿/橙通过；红档由自动测试覆盖 |
| 概览中 ChatGPT 与 Gemini 的额度条与 Command Code 双列等长 | Codex 正式界面目视通过，无文字重叠 |
| 名称列压缩后名称完整性与状态小字压缩/截断可接受 | 正式界面现有短名称与状态完整可见；长名称边界见示例渲染，用户体验未单独确认 |
| 菜单栏显示、拖动排序、其它品牌详情页无变化 | 代码差异与自动回归覆盖；本轮未做拖动与菜单栏现场操作，不记现场通过 |
| Gemini 品牌只读刷新及三账号完整卡片滚动 | Codex 操作正式 App，通过：三账号刷新返回「额度已更新」，底部组与添加账号入口可达；品牌切换窗口稳定 |
| VoiceOver 现场朗读两组额度的组名与数值 | 未执行，不记通过 |
| 第二台 Mac | 未执行，不记通过 |

## 取舍记录

- 删除「最近成功 hh:mm」后不再单独显示快照取数时间；缓存与刷新状态由标题栏右侧状态文字表达（缓存时为橙色「缓存 · 上次额度」）。若后续需要精确到分钟的取数时间，需要另行恢复。
- 名称列由约 152 pt 压到约 92 pt 是「与 Command Code 等长」的直接代价，已与用户确认：名称保持 15 pt 并截断，状态小字先缩字号再截断，全文保留在悬停与无障碍文本中。

## 与发布的关系

用户于 2026-10-10 明确授权审核并发布。Codex 的真实界面观察记录见 `evidence/records/publication-local-review.txt`，用户体验、VoiceOver、第二台 Mac 等未完成项保留，不因发布改记通过。发布与 CI 核验见 [PUBLICATION.md](PUBLICATION.md)。回滚方式与备份路径见 [ROLLBACK.md](ROLLBACK.md)。

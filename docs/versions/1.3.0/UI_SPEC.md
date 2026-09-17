# 1.3.0 UI 规格

本文件是当前实现约束。2026-09-17 用户实测后的第三轮界面微调已并入本文；`REVISION_SPEC.md` 中仍记录的 520 pt 第二轮目标属于上一阶段历史，尺寸和展示文案以本文为准。

## 1. 总体原则

- 详情页和设置页都不得使用 `ScrollView`、`List`、`NSScrollView` 或出现滚动条。
- 详情页恢复 1.2.1 的窄幅单列视觉语言，一排只放一张卡片。
- OpenAI/ChatGPT 卡片以 `assets/screenshots/v1.2.1/detail-redacted.png` 为视觉基线，必须同时显示额度剩余轨道和重置时间轨道。
- 沿用 `.regularMaterial` 页面背景、14 pt 圆角卡片、浅色/深色自适应和现有品牌资源。
- 动态文字使用固定行数和省略，不通过增加卡片高度适配。

## 2. 详情页尺寸和顺序

公共尺寸：

- 页面宽度：`440 pt`
- 外边距：`12 pt`
- 内容宽度：`416 pt`
- Header：`416 × 36 pt`
- 纵向间距：`6 pt`

卡片从上到下固定为：

1. ChatGPT A：`416 × 129 pt`
2. ChatGPT B：`416 × 129 pt`
3. DeepSeek：`416 × 48 pt`
4. Command Code：`416 × 162 pt`

| 显示状态 | 页面尺寸 |
| --- | --- |
| DeepSeek + Command Code | `440 × 552 pt` |
| 仅 Command Code | `440 × 498 pt` |
| 仅 DeepSeek | `440 × 384 pt` |
| 两者都隐藏 | `440 × 330 pt` |

禁止双列、网格和横向滚动。

## 3. Header

- 左侧显示“明明有数”/“Minget”和 `v1.3.0`。
- 右侧依次显示全局更新时间、刷新按钮、设置按钮。
- Header 高度固定 `36 pt`，所有文字单行。
- 刷新按钮同时刷新两个 ChatGPT Profile、DeepSeek、Command Code 和 DeepSeek 状态页。

## 4. ChatGPT 卡片

卡片内边距 `10 pt`。从上到下固定为：Header 26 pt、账号行 13 pt、5 小时窗口 25 pt、周额度窗口 25 pt、Footer 13 pt。5 小时与周额度两个窗口块之间固定留 `4 pt`，其他相邻区域保持 `1 pt`。

Header：

- Blossom：`26 × 26 pt`。
- Profile 名称：`13 pt semibold`；套餐在下方，`9 pt secondary`。
- 右侧点火按钮：`76 × 22 pt`；运行中显示“点火中…”并禁用。

账号行：左侧连接状态，右侧邮箱；均为 9 pt 单行，邮箱中间省略并可复制。

每个额度窗口固定两行：

- 主行：标签、`6 pt` 高额度剩余轨道、“剩余 N%”。
- 次行：“重置时间”、`3 pt` 高蓝色时间轨道、绝对重置时刻。
- 5 小时时间轨道 5 段，周额度 7 段。
- 所有亮色轨道都表示“剩余”；随额度消耗或时间流逝，右端向左收缩。
- 未知时间显示灰色轨道和 `?`；已到期显示“等待刷新”。

Footer：左侧 reset credits，右侧点火结果；右侧完整优先。

## 5. DeepSeek 卡片

- 卡片固定 `416 × 48 pt`，全部内容位于同一水平行：鲸鱼 Logo、`deepseek` wordmark、连接状态、可点击的官方服务状态、余额。
- 余额使用 `110.00 CNY` 行内格式，不再把金额和币种分成上下两层。
- 多币种正常最多横向显示 3 项；超过 3 项时第三项显示“另有 N 个币种”。极端长金额无法容纳时完整保留主币种金额，其余合并为“另有 N 个币种”。
- 不换算、不合计、不把缺失显示为 0。

## 6. Command Code 卡片

- Header 高 24 pt，显示 Logo、名称和套餐/连接状态。
- 固定三个 25 pt 窗口块：5 小时、周额度、本月；相邻窗口块之间固定留 `4 pt`。
- 每个窗口块第一行显示额度剩余轨道和 `$X.XX / $Y.YY`，不重复显示“剩余”和百分比。
- 额度 fraction 固定为 `remaining / limit`，品牌紫色，轨道高 `5 pt`；使用量增加时亮色右端向左收缩。
- 第二行显示时间剩余轨道。5 小时和周只显示绝对重置日期时间；本月保留“剩余 N 天 · 日期”。5 小时 5 段、周额度 7 段、本月连续单条无刻度；颜色为 system indigo，轨道高 `3 pt`。
- 本月只有真实起止时间都存在时才绘制 fraction；不得假设 30 天。
- 底部三行摘要沿用当前顺序，`9 pt secondary`，全部单行。

## 7. 设置页

- 固定 `520 × 600 pt`，无滚动容器。
- 菜单栏来源顺序：Codex 账号、Hermes / OpenClaw 账号、DeepSeek。
- DeepSeek 多币种时显示币种 Picker。
- 服务行顺序：Codex、Hermes / OpenClaw、DeepSeek、Command Code。
- 两个 ChatGPT 只显示状态和 `CODEX_HOME` 尾段，不提供登录或路径编辑。
- DeepSeek、Command Code 管理表单维持单开 accordion。

## 8. 菜单栏

| 来源 | 完整模式 | 紧凑模式 | 时间条 |
| --- | --- | --- | --- |
| ChatGPT A | `A 5H 78% \| W 42%` | `A 78% 42%` | 两排 |
| ChatGPT B | `B 5H 78% \| W 42%` | `B 78% 42%` | 两排 |
| DeepSeek | `DS CNY 123.45`（13 pt medium，7 pt 词间距） | `DS CNY 123.45`（12 pt medium，4 pt 词间距） | 无 |

缓存或失败最多显示一个前置警告图标。紧凑模式仍放不下时打开普通详情窗口，不显示截断文字。

## 9. 弹层和窗口

- popover 与 hosting controller 在显示前设置相同的 `440 × preferredHeight`。
- popover 使用状态按钮 `midX` 的 2 pt 中心锚点。
- 能居中时严格居中；无法居中时优先保证完整落在 `visibleFrame` 的 8 pt 安全边距内。
- 当前屏幕无法容纳时改开普通详情窗口。
- 普通详情窗口首次位置也以菜单栏图标为水平中心后做 visibleFrame clamp。

## 10. 启动行为

- 应用入口使用显式 AppKit lifecycle，不声明空 SwiftUI Settings Scene。
- 冷启动只安装菜单栏图标，不出现空窗口。
- 设置窗口只由用户点击设置入口创建。

## 11. 视觉证据

渲染证据必须脱敏并写入 `$TMPDIR/Minget-1.3.0-Evidence/`。至少包含全卡片浅色/深色、仅双 ChatGPT、Command Code 三种时间线、ChatGPT 未知时间状态和 popover 三个菜单栏位置。

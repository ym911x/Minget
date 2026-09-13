# 明明有数 · Minget v1.1.0 实施报告

| 项目 | 值 |
| --- | --- |
| 目标版本 | 1.1.0 |
| 需求与边界 | `DEVELOPMENT_PLAN.md` |
| 设计基准 | `assets/detail-reference.png`，公开版已脱敏，SHA-256 `26a1b2fcf2daac3046c5d038b7755fd3f5f8f3793578a8937f3b96985752e512` |
| 检查基线提交 | `51ef670029a45a75f38cc3daaef20f15f0bbd7f8` |
| 工作区状态 | 1.1.0 源码与标签已推送至 GitHub，CI run `34739103545` 通过；用户已有 `.workbuddy/` 未跟踪文件未触碰 |
| `VERSION` | `1.0.2` 改为 `1.1.0` |
| 运行候选包 | `/Users/yuyimeng/Applications/Minget.app` |
| 归档候选包 | `dist/Minget.app` |
| 当前结论 | 1.1.0 追加视觉修订、371 项自动测试和构建已完成；用户已确认当前详情页体验 |

## 1. 实施边界

本轮在已完成的 1.1.0 详情页和精简设置基础上，继续处理用户确认的品牌、套餐和 DeepSeek 状态页修订。余额取数、凭证存储、认证协议和缓存格式保持原有边界。状态页读取是无凭证的独立公开请求，不改变余额刷新策略，也没有新增刷新周期、通知、主题、排序、多账号或其他未存在的设置项。

没有读取全局 Codex 或 Claude 认证文件，没有读取浏览器 Cookie，没有把凭证写入源码、UserDefaults、日志、测试快照或文档，也没有调用模型端点验证凭证。

## 2. 代码修改

### 2.1 详情页

| 文件 | 修改 |
| --- | --- |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 重构为标题行、Codex 卡片和可选余额卡片；刷新状态位于顶部；齿轮调用设置窗口；余额卡片按平台整行堆叠，隐藏后按内容缩短面板 |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 新增 `CodexQuotaGrid`、连续额度条和详情专用分段时间条；四行共享标签、轨道、数值三列；时间条复用真实 `ResetTimeModel`；多币种余额逐项呈现 |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | Codex 使用用户提供的原始 OpenAI Blossom SVG/PNG 资源和真实套餐类型；DeepSeek、智谱 GLM 改为各自整行卡片；DeepSeek 使用鲸鱼图标和只保留 `deepseek` 的透明文字标识，并把官方整体状态压缩到顶部小号元数据区 |
| `Sources/UsageMonitorCore/Models/CodexAccount.swift` | 增加 `displayPlanType`，只显示 `account/read` 的套餐字段；API Key 会显示固定账户类型，缺失套餐不猜测 |
| `Sources/UsageMonitorCore/Providers/DeepSeekStatusProvider.swift` | 新增无认证公开状态页读取、稳定标题解析、跨域/路径守卫复用和不可用时的 fail-closed 状态 |
| `Sources/UsageMonitorApp/ViewModels/UsageViewModel.swift` | 将 DeepSeek 状态页读取与余额刷新分离，启动、面板打开、定时周期或手动刷新触发，状态页正常间隔五分钟，测试可注入 reader |
| `Sources/UsageMonitorApp/UsageMonitorApp.swift` | 生产组合根注入状态页 reader，继续共用现有 transport |
| `scripts/build.sh`、`assets/brand/*` | 打包 OpenAI Blossom 原始 SVG 与 PNG 回退、用户提供的 DeepSeek 黑色鲸鱼图标、原始文字标识及两种透明展示派生资源；缺失资源时 UI 回退至 SF Symbol |
| `Sources/UsageMonitorApp/Views/MingetSettingsView.swift` | 移除设置页垂直 `ScrollView`，默认 440 × 420 pt 窗口直接展示现有内容，不增加设置项 |
| `Sources/UsageMonitorApp/StatusItem/StatusItemController.swift` | 弹层、普通详情窗口和设置窗口共享一个 `UsageViewModel`；详情弹层锚定到菜单栏按钮水平中心并继承当前系统外观；设置窗口高度同步为 420 pt |
| `Sources/UsageMonitorApp/Views/ProviderViews.swift` | 保留原有更新时间页脚定义，供连接管理视图继续使用 |

Codex 账号邮箱现在位于 Codex 卡片第一行右侧，套餐名称来自 `account/read`，Blossom 图标 frame 从 34 pt 调整为 50 pt。详情页不显示旧版冗余账号说明、连接明细和诊断文本。正常状态下余额卡片不提供滚动内容；异常文本由窗口的垂直滚动兜底。DeepSeek 与智谱均使用整行卡片，DeepSeek 的鲸鱼图标、文字标识、连接状态和服务状态均位于同一顶部元数据区。

### 2.2 金额和时间文字

| 文件 | 修改 |
| --- | --- |
| `Sources/UsageMonitorCore/Utilities/DecimalFormatting.swift` | 新增 `overviewBalanceText` 与 `overviewBalanceLabel`；优先 `available`，否则 `total`；CNY 使用 `¥`；Decimal 舍入到两位；小额显示 `< ¥0.01` 或带币种代码的等价提示 |
| `Sources/UsageMonitorCore/Utilities/UsageFormatting.swift` | 新增绝对本地重置点 `MM-dd HH:mm` 格式 |
| `Sources/UsageMonitorApp/Views/UsagePanelView.swift` | 过期时间条显示“等待刷新”，缺失显示“时间未知”，非法窗口显示“时间不可用”，不显示虚构日期 |

### 2.3 精简设置

| 文件 | 修改 |
| --- | --- |
| `Sources/UsageMonitorApp/ViewModels/DetailPreferences.swift` | 新增两个非敏感 UserDefaults 偏好：`detail.showDeepSeek`、`detail.showGLM`，默认均为开启 |
| `Sources/UsageMonitorApp/Views/MingetSettingsView.swift` | 新增单页设置；包含两项详情显示开关、既有 DeepSeek/GLM 连接管理、默认折叠的高级诊断、版本、关于、打开详情和退出 |
| `Sources/UsageMonitorApp/Views/MingetAboutView.swift` | 无法从 Bundle 读取版本时的回退文案更新为 `1.1.0` |

开关只保存显示偏好。隐藏平台仍在设置页中保留连接管理，也不暂停既有后台刷新和认证策略。

### 2.4 测试与版本

| 文件 | 修改 |
| --- | --- |
| `Tests/UsageMonitorAppTests/DetailPreferencesTests.swift` | 覆盖默认开启和两个键的持久化 |
| `Tests/UsageMonitorCoreTests/ProviderModelsTests.swift` | 覆盖 total-only、available、美元和小额概览格式 |
| `Tests/UsageMonitorCoreTests/UsageFormattingTests.swift` | 覆盖绝对本地重置点与缺失时间 |
| `Tests/UsageMonitorCoreTests/DeepSeekStatusProviderTests.swift` | 覆盖官方健康标题、历史故障干扰、异常状态、HTML 清理、无认证请求和 HTTP 失败 |
| `Tests/UsageMonitorCoreTests/CodexAccountTests.swift` | 覆盖套餐显示和 API Key 类型回退 |
| `Tests/UsageMonitorAppTests/DetailPanelLayoutTests.swift` | 覆盖可见平台组合对应的详情高度收紧 |
| `VERSION` | 版本更新为 `1.1.0` |

### 2.5 本轮追加视觉收口

| 反馈 | 实现 |
| --- | --- |
| ChatGPT/OpenAI 标识偏小 | Codex 卡片 Blossom 资源容器调整为 50 × 50 pt，仍由同源黑白资源按外观切换 |
| DeepSeek 缺少用户提供的文字标识 | 新增 `deepseek-wordmark-black.png`，卡片使用鲸鱼图标和“deepseek 开放平台”图片文字标识；不再用 `Text("DeepSeek")` 代替 |
| DeepSeek 状态占用独立行 | 删除分隔线与独立状态摘要，将连接文字、状态点、状态文字和官方状态页链接放入顶部小号元数据区 |
| 详情页底部留白 | 可见平台高度更新为 300 / 370 / 400 / 475 pt 四档，保持隐藏平台后自动收紧 |
| 设置页滚动条 | `MingetSettingsView` 去除垂直 `ScrollView`，`SettingsWindowController` 与视图统一为 440 × 420 pt |
| 标题与弹层定位 | 顶部并列显示中英文产品名并在英文名下显示版本；弹层使用状态项按钮中心窄锚点并继承 `NSApp.effectiveAppearance` |

### 2.6 最新三项微调

| 用户标注 | 实现 |
| --- | --- |
| 英文产品名需要与中文标题并列 | 标题改为同一行显示“明明有数”和 `Minget`，版本号以更小字号放在英文名下方 |
| DeepSeek 金额与状态层级不清 | 金额行改为“余额 + 金额”，金额保持主视觉；连接和服务状态行移至金额下方，继续使用原 10 pt 字号 |
| 文字标识有浅色矩形且偏小 | 使用只保留 `deepseek` 的 `deepseek-wordmark-text-transparent.png` RGBA 资源，显示容器调整为 128 × 28 pt；原始黑色素材不覆盖 |

资源来源与校验：OpenAI Blossom 原始 SVG 来自用户指定目录 `/Users/yuyimeng/Downloads/OpenAI-logos/SVGs/`，黑色 SVG SHA-256 为 `75c1e9fffa5e8c437bec1d67197a73992bca45d166c6ff23215185dea8fae92a`，白色 SVG SHA-256 为 `01d158767c4eec0e47bd617e67759c33da0accd1438be1a8d29dfdb99ce87285`；PNG 继续保留为回退；DeepSeek 黑色鲸鱼图标来自用户上传附件，SHA-256 为 `ce09326d34dcfb0c9a4324d0ecd222fbf6eaf81843fcaff0333dd0567b9422ef`；DeepSeek 原始文字标识 SHA-256 为 `afd5cf1e78f1e161cc6844e9eb1c6e08772c13e929c537a775ed91b5025e98de`；完整透明文字资源 SHA-256 为 `5338f877f0a25fb817246eaa4a898cd8acc6733300845e5d50bf4d32f7f`，只保留 `deepseek` 的透明派生资源 SHA-256 为 `428bf89ff8f5bf8e0a834e9c4263050b0b1eaff0f5101ab9f8657fcd3a4a26ef`。构建脚本把六份 PNG 和两份 SVG Provider 资源放入 `Contents/Resources`，图片缺失时界面回退至 SF Symbol。

### 2.7 本轮最终细节修订

| 用户反馈 | 实现 |
| --- | --- |
| 英文名不应默认与中文并列 | 标题只保留名称与版本号；`UsagePanelView.productName` 按 `Locale.preferredLanguages` 首选语言选择中文或英文，不增加额外设置项 |
| OpenAI 图形清晰度和对齐 | 优先加载用户提供的原始 Blossom SVG，PNG 作为回退；保留 50 pt 资源槽并补偿透明画布偏移，使可见左边界与 DeepSeek 图形对齐 |
| DeepSeek 文字标识和状态被挤压 | 新增去除“开放平台”字样的透明 `deepseek` 资源，显示框改为 128 × 28 pt；状态行使用固定完整宽度，不再显示省略号 |

## 3. 关键设计决定

1. 四条轨道必须共用中间列宽。标签宽度固定为同一列，日期和值固定为同一列，只有轨道列伸缩，避免 5 段、7 段与连续额度条左右端错位。
2. 时间轨道的蓝色只表达时间进度，额度轨道继续使用额度的绿、橙、红语义。两种进度不混用。
3. 用户要求的是重置时间点，所以有效时间显示绝对本地日期和时间，不显示倒计时。到期后继续等待服务刷新，避免本地时钟虚构一个新窗口。
4. 余额卡片的醒目数字服从接口字段语义。DeepSeek 当前只有 `total` 时显示“余额”，不能把示意图中的“可用余额”硬套到所有平台。
5. 设置页没有引入不存在的功能。连接表单和诊断内容属于原有能力，新增内容只有 DeepSeek 与智谱 GLM 的详情显示开关。
6. DeepSeek 状态页是公开 HTML，不把旧 `/api/v2` JSON 当成当前契约。只解析整体标题，遇到页面变化或网络失败显示“状态暂不可用”，并提供官方页面入口。
7. 所有平台卡片采用纵向整行，后续平台沿用同一插槽，避免再次引入并排卡片造成主次信息过密。

## 4. 自动验证

在仓库根目录执行：

```text
swift test
```

结果：本轮执行结果为 371 项通过，0 项失败，0 项跳过。新增状态页解析、套餐字段、系统语言名称选择、原始 SVG 和资源打包路径均有自动化或构建覆盖。

另执行：

```text
git diff --check
```

结果：通过，无空白错误。

## 5. 候选构建与签名

执行：

```text
./scripts/build.sh
plutil -lint dist/Minget.app/Contents/Info.plist
codesign --verify --strict --verbose=2 /Users/yuyimeng/Applications/Minget.app
```

`./scripts/build.sh` 成功完成 Release 构建，staging 与运行候选包 `/Users/yuyimeng/Applications/Minget.app` 通过严格校验，并确认版本为 `1.1.0`。签名身份为现有 `Minget Local Signing`。`dist/Minget.app` 的普通签名校验通过；构建脚本已记录 iCloud 文件提供方属性导致归档路径严格校验受限，运行验收应使用 `/Users/yuyimeng/Applications/Minget.app`。

编译输出只有既有 `SecKeychain*` API 弃用警告，未新增编译错误或签名错误。状态页 reader 的默认时钟使用无捕获闭包，未新增并发警告。

## 6. 真实运行检查

构建后通过正常 `open /Users/yuyimeng/Applications/Minget.app` 重启候选包，进程可启动并保持运行。CUA 初次状态没有暴露这个 accessory/status-item 应用，后续短暂取得了一次 accessibility snapshot；截图、滚动和点击仍未完成，不能据此宣称完整视觉与交互验收，也没有使用 shell 截图绕过 CUA 限制。

补充：上一轮候选包的一次可用 CUA accessibility snapshot 曾读到真实套餐、已脱敏的 Codex 账号、DeepSeek 图像的可访问名称、余额、连接状态和 `状态页` 链接。最终资源修订后，CUA 截图调用再次超时或返回 `noWindowsAvailable`，因此该历史文本检查不能替代本轮完整视觉与交互验收；本轮可访问名称已同步为 `DeepSeek`。

本轮透明资源和布局代码构建后再次执行 `open /Users/yuyimeng/Applications/Minget.app`，系统返回 Launch Services 错误 `-600`，Codex 未取得新的独立窗口截图。用户随后确认当前详情页体验并授权发布；该确认记录为用户体验证据，仍不替代下列边界场景的逐项回归。

发布后用户补充提供了 1.1.0 菜单栏、详情页和设置页截图。公开展示使用原始菜单栏与设置页图片；详情页原图包含真实邮箱，仓库只收录明确标注的脱敏展示副本。菜单栏展示已据此修正为实际额度文字与两排重置时间进度，不再使用单独图标表达状态项。

待后续真实验收的最小集合：

- 打开菜单栏详情，核对四条轨道的端点、5/7 段数量和字体截断；
- 点击顶部刷新和齿轮，确认设置窗口焦点与关闭行为；
- 分别关闭 DeepSeek、智谱、两者，确认整行卡片和无余额区域的高度；
- 重启后核对开关持久化，并确认开关没有引发凭证弹窗或断开服务；
- 在真实缓存、失败、长邮箱、浅深色和辅助功能字号下截图；
- 按既有授权边界完成一次真实服务取数回归。

## 7. 未完成事项与交付边界

用户已确认当前详情页体验。真实窗口边界交互、异常视觉矩阵和本轮真实服务重新取数仍是未验证项，分别记录在 `ACCEPTANCE.md` 的 A10 至 A12，不以自动测试、代码阅读、生成图或发布动作替代。

本轮按用户授权推送源码并创建 `v1.1.0` 标签，不上传未经 Apple 公证的安装包，不清理用户已有 `.workbuddy/` 文件，也不消耗额度重置信用。

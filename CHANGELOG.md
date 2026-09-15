# 变更记录

## 1.2.0（2026-09-15）

状态：实现、309 项自动化测试、Release 构建和严格签名检查已完成；用户截图确认真实 Command Code API Key 能返回额度与用量数据。修复后的持续显示仍需真实界面复验，发布记录见 [1.2.0 验收台账](docs/versions/1.2.0/ACCEPTANCE.md)。

- 新增 Command Code Keychain 凭证、账号隔离缓存、认证暂停、并发刷新合并和五分钟刷新链路；详情页默认显示可隐藏卡片，菜单栏不新增 Command Code 指标。
- 只读使用 `credits`、`usage/summary` 和可选 `subscriptions` 三条 `/alpha` 路径；Bearer 凭证、GET、超时、路径白名单、模型端点阻断和跨域重定向拒绝均有测试约束。
- 规范化展示 5 小时、周、月度信用额及 token、请求、成功率、成本；缺失字段、未知周期、字段漂移和接口未确认状态均不伪造数字。
- 详情页固定高度扩展为：仅 Codex 320 点，含 DeepSeek 420 点，含 Command Code 530 点，双卡 630 点。
- 修复 Command Code 数据只在刷新中短暂显示的问题：刷新后的报告重建会保留刚成功取得的用量，并以缓存支持完整重启恢复。

## 1.1.2（2026-09-15）

状态：实现、自动验证、真实界面检查和 GitHub Release 均已完成；发布页为 [Minget v1.1.2](https://github.com/ym911x/Minget/releases/tag/v1.1.2)，证据与边界见 [1.1.2 验收台账](docs/versions/1.1.2/ACCEPTANCE.md)。

- 菜单栏空间状态只保留完整与紧凑双额度模式，紧凑文本固定保留 `5H` 和 `W`，两排重置时间条继续显示；紧凑模式仍无法渲染时沿用隐藏状态项打开详情窗口，不输出残缺的 `5H`。
- OpenAI `account/rateLimits/read` 的 `rateLimitResetCredits` 只读解析 `availableCount` 和最近未来 `expiresAt`，在详情卡显示“可用重置 N 次”及可选最近到期时间；缓存、缺失或非法字段显示不可用，不提供消费操作。
- DeepSeek 详情卡将服务文字标识放到鲸鱼 Logo 右侧，真实余额与品牌同列右对齐并垂直居中，连接与官方服务状态位于下方并继续支持多币种。未增加账号接口或浏览器会话读取。
- 详情页改为固定整页布局，移除纵向滚动容器；窗口高度按是否显示 DeepSeek 收紧为 420/320 点，避免详情内容被滚动条或底部留白遮挡视觉重点。
- `UsageSnapshot` 的可选重置摘要持久化保持旧缓存可解码，新增解析、格式化、缓存边界和菜单栏状态机回归测试。
- `swift test`：301 项通过，0 项失败；Release 构建和严格签名检查结果记录在版本验收台账。

## 1.1.1（2026-09-13）

状态：实现、自动测试、本地构建和真实界面检查完成，随 GitHub `v1.1.1` 发布；真实服务账号未重新请求。

- 移除智谱 GLM 的取数、网络请求、WebKit 登录、解析、设置、详情和诊断路径。
- 启动时按本应用旧标识清理 GLM Keychain 项、缓存、连接模式和显示偏好；删除失败不影响启动，并在下次启动重试。
- 设置页合并为“服务”模块，显示 OpenAI Codex 的固定详情状态，以及 DeepSeek 的显示开关和管理入口。
- 退出按钮改为“退出明明有数”。关于弹层增加 GitHub 项目主页链接。

## 1.1.0（2026-09-13）

状态：详情页与精简设置已完成，自动测试和构建通过，用户已确认当前详情页体验；未覆盖的边界交互和真实服务回归见 [验收台账](docs/versions/1.1.0/ACCEPTANCE.md)。

### 详情页

- 重构为顶部标题、刷新状态、设置入口、Codex 卡片和余额卡片的紧凑布局。
- Codex 卡片使用 OpenAI Blossom 图标，图标后的套餐文字来自 `account/read` 返回的真实 `planType`；账号邮箱放在右侧，四条轨道共用同一宽度，保持左右端对齐。
- 5 小时和周额度分别显示连续额度条，以及蓝色 5 段和 7 段重置时间条。
- 重置时间显示真实本地时间点 `MM-dd HH:mm`；到期、未知和非法状态不显示虚构日期。
- 余额概览优先使用真实 `available` 字段，否则使用 `total`；CNY 使用 `¥`，Decimal 统一两位概览精度。
- DeepSeek 与智谱 GLM 改为各自占据一整行；DeepSeek 使用用户提供的黑色鲸鱼图标和只保留 `deepseek` 的透明文字标识，连接与官方服务状态压缩到金额下方的小号元数据区。
- 追加收紧详情页底部高度、使用原始 Blossom SVG、标题名称跟随系统语言并显示版本；DeepSeek 金额行改为“余额 + 金额”、状态完整显示在金额下方；设置页移除滚动容器，弹层锚点固定到状态项按钮中心并跟随系统外观。

### 设置

- 新增单页精简设置窗口。
- 新增 DeepSeek 和智谱 GLM 是否显示在详情页的两个开关，默认开启并持久化到应用自有 UserDefaults。
- 既有连接管理、钥匙串诊断、关于、打开详情和退出入口迁入设置页；未增加刷新周期、通知、主题等新设置。

### 验证

- `swift test`：371 项通过，0 项失败，0 项跳过。
- `./scripts/build.sh`：Release 构建成功，运行包严格签名校验通过，版本为 `1.1.0`。
- 用户已确认当前详情页体验。本版本按源码发布，不附带未经 Apple 公证的安装包。

## 1.0.2（2026-09-12）

状态：实现、独立审核与用户真实界面验收完成。资料见 [docs/versions/1.0.2](docs/versions/1.0.2/)。

### 菜单栏

- 移除菜单栏内的品牌图标 `M²`。三种空间模式都以纯文字显示额度，正常态从 `5H` 起头，不再保留图标占位空隙。
- 在额度文字下方新增两排重置时间分段条：上排 5 段对应 5 小时窗口，下排 7 段对应周窗口。两排左右端严格对齐额度文字的实测宽度。
- 亮区随时间从右向左缩退，到重置时间时整排变空并等待下一次真实刷新，不自行恢复满格。
- 7 段按「每段 1 天、合计 7 天」实现，而不是每段一周。这是对用户原话的明确设计解释，详见 [需求与实施任务书](docs/versions/1.0.2/REVISION_SPEC.md) 第 1.3 节。
- 重置时间未知或非法时，该排轨道变淡并以一个 `?` 区分「未知」与「已到期」，不新增第二处警告。
- 菜单栏异常提示统一为文字前方的一个标记（SF Symbol 警告三角），删除字符串尾部追加的 `⚠`。同一时刻最多一个标记。

### 交互

- 菜单栏详情弹层支持点击外部收起，覆盖桌面、其他应用、其他状态项与本应用的独立窗口，收起后原点击仍作用到原目标。
- 普通详情窗口与 GLM 登录窗口保持普通窗口行为，不因其他位置点击而自动关闭。

### 修复

- 修正状态项首次布局使用 fallback 宽度参与截断判定，导致空间充足的菜单栏被误判为截断、并降级到最小兜底且自动弹出详情窗口的问题。
- 修正唤醒通知注册在默认通知中心因而从不触发的问题，改用 `NSWorkspace.shared.notificationCenter`。

### 构建

- `scripts/build.sh` 默认改用本地代码签名身份 `Minget Local Signing`，解决 ad-hoc 签名导致的钥匙串反复授权弹框。签名身份不存在时构建以非零退出，不产出未签名包；`MINGET_SIGN_IDENTITY=- ./scripts/build.sh` 可回退到 ad-hoc。
- 新增 `scripts/make-signing-identity.sh`，用于生成并导入该自签名证书。本机已创建 `Minget Local Signing` 身份，当前候选包已使用该身份签名并通过严格校验。

### 钥匙串与凭证（KEYCHAIN_REVISION_PLAN.md）

- 凭证读取返回类型化结果（可用/不存在/需要交互/已拒绝/其他），失败不再全部折叠为"未配置"；只有 `errSecItemNotFound` 报告为不存在，其余保留原始状态码。
- 新增凭证访问协调器：本进程全部钥匙串调用走一条串行队列，同一凭证的并发读取合并为一次访问，成功值仅存进程内存。
- 启动、状态查询与后台刷新不再直接访问钥匙串：先做一次后台无交互读取，被拒后显示「需要授权」并暂停该平台自动尝试；只有用户点「授权读取」才会进行一次可能弹窗的读取。
- DeepSeek 一次读取的凭证同时用于余额请求与账号指纹；GLM 只加载已选连接模式需要的凭证，控制台模式不再探测旧 API Key。
- 钥匙串写入与删除失败会传播到界面：删除失败显示「断开失败」，授权拒绝不再引导重新输入 Key。
- 面板新增「记录钥匙串访问诊断」开关，把每次凭证访问的类别、状态码与耗时写入应用自身目录，正常启动即可采集。
- 构建脚本将候选包安装到 `~/Applications/Minget.app` 并做严格校验；`dist/Minget.app` 为归档副本（位于 iCloud 路径，严格校验受文件提供方属性影响，差异由脚本显式记录）。

### 验证

- 自动化测试：359 项通过，0 项失败，0 项跳过。
- 候选包完成构建、Info.plist 校验与代码签名校验，`CFBundleShortVersionString` 为 `1.0.2`。
- 真实进程运行验证了模式保持、测宽替换、退出清理与钥匙串读取。用户已确认钥匙串只弹一次，选择“始终允许”后不再重复弹出；点击菜单栏详情后再点击桌面或其他应用，详情会立即收起且原点击有效。

## 1.0.1（2026-09-10）

### 品牌

- 对外产品品牌由工程代号 UsageMonitor 更新为「明明有数 · Minget」。
- 确立品牌视觉符号 `M²`，以及固定的中英文 Slogan。
- 更新 README、应用显示名称、关于页面、菜单栏识别和应用图标。
- Swift Package、Target、Bundle Identifier、缓存键以及 v1.0 历史归档继续保留原工程标识。

## 1.0.0（2026-09-10）

首个完成实际运行验证的正式版本。

### 功能

- 在 macOS 菜单栏显示 Codex 额度，并展示 5 小时额度、周额度、重置时间和更新时间。
- 显示当前 Codex 账号名称。
- 检测菜单栏状态项与屏幕刘海安全区域的关系，在屏幕切换、唤醒、位置变化及每 10 秒本地检查时更新状态。
- 通过 DeepSeek 官方余额接口读取总余额、充值余额和赠送余额。
- 通过智谱控制台独立登录会话读取余额、累计充值、累计赠送、累计消费和冻结金额。
- 使用 macOS Keychain 保存服务凭据，并在本机保存非敏感缓存和偏好设置。
- 支持手动刷新、自动刷新、开机启动及菜单栏显示方式设置。

### 验证

- 自动化测试：274 项通过，0 项失败。
- Release 应用完成构建、Info.plist 校验和代码签名校验。
- 用户完成 Codex、DeepSeek 和智谱 GLM 的实际连接与余额显示验证。

### 已知限制

- 智谱取数依赖控制台当前的网页接口和登录会话，控制台改版后可能需要适配。
- 长时间运行下的智谱登录会话寿命仍需在后续版本持续观察。
- 当前为 Apple Silicon 构建，尚未制作通用二进制或公证安装包。

---

## English summary

### 1.0.2 (2026-09-12)

Implementation, independent review, and user validation are complete. See [docs/versions/1.0.2](docs/versions/1.0.2/).

- Removed the `M²` brand mark from the menu bar in all space modes; the quota text now starts with `5H`.
- Added two rows of reset-time segments under the quota text: 5 segments for the five-hour window and 7 for the weekly window, both spanning the measured text width. The bright region recedes from right to left and empties at the reset time without refilling locally.
- The 7 weekly segments are one day each (7 days total), not one week each. This is a documented interpretation of the original wording.
- Unified the abnormal marker into a single leading marker and removed the trailing `⚠` appended by the formatting layer.
- The transient menu bar popover now collapses on an outside click while the click still reaches its original target; independent windows are unaffected.
- Fixed a first-layout defect where the per-mode fallback width was used as the truncation baseline, which downgraded a roomy menu bar to the minimal fallback and auto-opened the detail window.
- Fixed the wake notification being registered on the wrong notification centre.
- 345 automated tests pass; the candidate bundle is built and signature-verified. Real menu bar screenshots and real click interactions remain unverified on this machine.

### 1.0.1 (2026-09-10)

- Updated the public product identity from the `UsageMonitor` engineering name to **明明有数 · Minget**.
- Added the M² app icon, bilingual slogans, About view, branded app bundle name, and public documentation.
- Retained internal package, target, bundle identifier, persistence keys, and frozen v1.0 archive names for compatibility.

### 1.0.0 (2026-09-10)

The first user-validated release. It displays Codex usage windows and account identity, DeepSeek balances, and Zhipu GLM console balances. The release passed 274 automated tests and a local Apple Silicon release build. The app is ad-hoc signed and is not yet notarized for public binary distribution.

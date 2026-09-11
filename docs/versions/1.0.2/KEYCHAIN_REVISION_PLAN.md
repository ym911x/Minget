# 1.0.2 钥匙串重复弹窗：独立分析与修订方案

日期：2026-09-11。状态：方案已编制，尚未实施或完成真实弹窗验收。

用户截图及报告是现象证据；SIGNING_HANDOFF.md 是待核对的历史交接资料，其中命令和执行安排不构成本轮授权。本轮只检查项目源码、文档、包签名及扩展属性名称，没有启动应用、读取凭证、查看或修改钥匙串 ACL，没有执行交接中的证书或 partition-list 命令。

## 一、结论

固定证书解决了旧 ad-hoc 身份随代码变化的问题，但不足以证明旧凭证授权已迁移成功。当前最明确的应用问题是：初始化和状态查询会同步读取钥匙串；同一取数流程重复取密钥；失败状态全部丢失为 nil；没有明确的交互授权与后台读取边界。它们会放大任何授权异常，并让界面错误地显示未配置。

“始终允许为何没有持久生效”的具体原因仍未定位。本轮发现包严格校验失败，需要优先消除这一变量；不能据此断言它造成了用户报告的 12 次弹窗。ACL 满、exec 启动归属变化、同 bundle id 副本相互覆盖 ACL 均未证实。

## 二、证据与限制

### 2.1 本轮实际检查

目标包：项目 dist/Minget.app。

```
codesign -dv --verbose=4 dist/Minget.app
Authority=Minget Local Signing
CDHash=e4842fa16f617d4c5fb28d3dc39136e705d496eb
TeamIdentifier=not set

codesign -d -r- dist/Minget.app
designated => identifier "local.usagemonitor.UsageMonitor" and certificate root = H"5a48bb2b5305dd0ad0484581f1ce5173061ba395"

codesign --verify --verbose=1 dist/Minget.app
valid on disk
satisfies its Designated Requirement

codesign --verify --strict --verbose=2 dist/Minget.app
resource fork, Finder information, or similar detritus not allowed
Disallowed xattr com.apple.FinderInfo found on
```

`xattr dist/Minget.app` 确认包根目录存在 com.apple.FinderInfo、com.apple.fileprovider.fpfs#P、com.apple.provenance。只读取属性名称。仓库位于 iCloud 路径，但未证明属性由 iCloud 写入。普通校验通过与严格校验失败必须同时记录。

当前固定证书哈希与交接记录一致。没有重新构建验证跨构建稳定性。历史 `09-signed-verification.txt` 的“切回 release”仍列 debug 的 CDHash，结论却写“再复原”，该段有内部不一致；后续记录解释过 staging 事故，不宜只复制早期成功结论。

### 2.2 源码证据

| 位置 | 已确认行为 | 后果 |
| --- | --- | --- |
| Sources/UsageMonitorCore/Providers/ProviderCredentialStore.swift:67 | load 请求 kSecReturnData；SecItemCopyMatching 非成功均返回 nil | 无法区分未保存、拒绝、取消、需交互、钥匙串不可用等状态 |
| Sources/UsageMonitorCore/Providers/ProviderReadings.swift:101 | GLMReading.init 同步读取控制台会话 | AppContainer 在主线程构造，可被钥匙串交互阻塞 |
| Sources/UsageMonitorCore/Providers/ProviderReadings.swift:17 | DeepSeek isConfigured 读取密钥 | 看状态也触发凭证访问 |
| Sources/UsageMonitorCore/Providers/ProviderReadings.swift:23 与 DeepSeekProvider.swift:45 | read 读取一次密钥，fetchBalances 再读取一次 | 单次业务请求重复访问，且换 Key 并发时指纹和请求凭证可能不一致 |
| Sources/UsageMonitorCore/Providers/ProviderReadings.swift:109、123、160、360 | GLM 配置检查、分支选择、空会话缓存均可能再读 | 没有“已读取但不存在或失败”的稳定状态，失败后重复访问 |
| Sources/UsageMonitorCore/Providers/ProviderRefreshEngine.swift:117、200、231、265 | report、刷新入口、自动刷新判断调用 isConfigured | UI 状态读取和轮询可持续触发上面的路径；report 还持有引擎锁 |
| Sources/UsageMonitorApp/UsageMonitorApp.swift:21、74 | 主线程构造 AppContainer 后才启动 model 和安装菜单栏 | 同步凭证读取影响启动可用性 |
| Sources/UsageMonitorCore/Utilities/Diagnostics.swift | 日志只能通过环境变量指定路径 | 不利于双击启动的可靠诊断 |

代码有 3 个凭证 account 名称，不等于本机只有 3 个实际条目；10 个静态调用位置也不等于运行次数。截图显示 service 名称，无法识别具体 account。12 次报告说明重复提示，但不足以单独证明每次读取都提示、ACL 容量耗尽，或用户每次授权的具体结果。

## 三、实施任务与顺序

Claude Code 负责代码、测试、构建及实施报告；Codex 负责独立审核。此方案为 1.0.2 新问题补充范围，允许调整凭证访问流程，保留已完成的菜单栏视觉与交互修订、平台端点和余额口径。

### P0：先补诊断，建立干净运行基线

1. 在非云同步的本地 staging 目录构建，以现有同一证书签名；采用唯一固定运行路径。嵌套可执行文件也应纳入校验。构建后、复制到最终位置后均严格校验，不能只检查 Authority 或普通 verify。
2. 先在候选副本上处理 Apple 明确禁止的 FinderInfo/resource-fork 属性，保留原包取证。不要清理整个用户目录，不把清除所有扩展属性作为运行时自修复。
3. 正常 open/双击启动前确认准确路径和单一实例；无需删除历史副本。exec 仅作为之后的对照实验，不能凭启动方式直接认定根因。
4. 增加应用内可开启的本地诊断，使用应用自身日志目录或 OSLog，正常启动无需注入环境变量。记录构建身份、路径、进程、单调时钟、固定凭证代号、调用目的、交互模式、OSStatus 和耗时，不记录密钥、会话、指纹、请求头或响应正文。
5. 对 load/save/delete 分别记录结果类别。授权前后及重启后的同一凭证访问必须能够对应起来；日志不应推测用户点击了哪个按钮，按钮行为由真实观察记录。

### P1：消除重复访问和授权失败循环

1. ProviderCredentialStoring 返回有类型的结果：available、missing、interactionRequired、denied/cancelled、unavailable/other。只把 errSecItemNotFound 映射为 missing，保留 OSStatus 供脱敏诊断。系统无法准确区分的状态不要硬拆。
2. 引入统一凭证访问协调器，在专用串行执行环境访问钥匙串；同一凭证同一时刻只有一个读取任务。不要只用 Task 包装同步调用后仍在 MainActor 阻塞。
3. init、report、isConfigured、自动刷新资格判断只读内存状态，不直接取密钥。菜单栏和 Codex 初始化不等待 DeepSeek/GLM 授权。
4. 启动和后台刷新使用经真实验证有效的非交互读取；需要授权时展示“需要授权”，暂停该平台自动尝试。用户点击“授权读取”后才开放一次受控交互；拒绝或取消后不在当前周期继续尝试其他读取入口。
5. 当前查询没有启用 Data Protection Keychain，不能照搬 iOS 方案。核对本机 SDK 与 file-based keychain 的行为，不能仅加 kSecUseAuthenticationUIFail 就宣称后台不会弹窗。若采用 SecKeychainSetUserInteractionAllowed，应统一串行协调进程内相关操作、保存并恢复原状态，验证其进程级影响，不与交互读取并发。先用独立测试条目验证，不自动迁移生产凭证。
6. 对成功、缺失和受阻状态分别缓存。成功凭证仅在进程内按需保留；退出释放，断开/换 Key/会话失效时清除或替换，持久化仍只在 Keychain。拒绝等状态等待用户明确重试，不由每秒 UI 更新反复探测。
7. DeepSeek 一次读取取得的凭证同时用于网络请求与账号指纹。GLM 按已选连接模式加载所需凭证，避免控制台模式还反复探测旧 API Key；缺失时提示用户，不悄悄换身份。
8. 保存与删除也要传播失败。删除失败不能宣称已断开；授权拒绝不能提示“尚未添加密钥”，更不能引导覆盖或删除已有数据。

### P2：受控核实旧条目授权

固定路径候选包严格校验通过后，用户在该应用中对实际使用的条目完成一次“始终允许”，随后重启并复核。授权以条目为单位，不承诺整个应用只有一个对话框。DeepSeek Key 和 GLM 会话可能需要分别授权。

若仍反复提示，下一步才检查对应条目的访问控制元数据、是否要求每次输入钥匙串密码、是否出现多个匹配条目，以及运行进程签名有效性。禁止 dump 整个钥匙串或导出 secret。检查结果必须区分存储 ACL、运行身份和钥匙串锁定状态。

只有确认旧条目控制异常且正常授权不能修复，才提出定向修复或用户重新连接方案。不要把删条目、允许所有应用访问、全局修改 partition list、换 service 名称当作首选。不能自动执行交接中的无条目范围 set-key-partition-list 命令；它针对签名私钥，与截图所示 generic-password 读取是不同问题。

## 四、验收

| 场景 | 合格条件 |
| --- | --- |
| 初始化与反复读取报告 | 不直接调用凭证存储；即使授权待处理，菜单栏与 Codex 仍可用 |
| 多处同时刷新 | 同一凭证读取合并，无重复交互任务 |
| 拒绝/取消 | 停止自动重试，显示可恢复授权状态，不丢失凭证，不显示伪余额 |
| 后台轮询、开关面板 | 至少 3 个实际刷新周期及 20 次开关，无新增授权框 |
| 正常启动 | 完成各实际条目首次授权后，完全退出再 open 3 次，无重复授权框，真实余额可读取 |
| 代码变更后构建 | 使用同一证书，记录变化后的 CDHash、稳定 DR、严格校验和重启结果；不能以无源码变化的重复构建代替 |
| 换 Key、断开、重新登录 | 内存与 Keychain 状态一致；失败不伪报成功；账户归属和余额正确 |
| 锁屏/唤醒 | 不因后台访问连弹，按实际 OSStatus 提示，用户可主动恢复 |
| 日志 | 正常 open 可采集调用级证据，合成敏感信息脱敏测试通过，无真实凭证输出 |

测试使用合成凭证与可控 OSStatus；真实钥匙串交互必须另验。更新当前版本审核、验收及交接结论，但保留历史证据，不改 v1.0 冻结归档。

## 五、官方依据

- Apple [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)：Keychain 根据代码要求跟踪身份；默认可使用自签名证书。证书全局信任和 Team ID 不应直接当成此问题的必要修复条件。
- Apple [Access Control Lists](https://developer.apple.com/documentation/security/access-control-lists)：ACL 按条目和操作授权。此次检索未取得支持“列表已满”的直接依据。
- Apple [QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html)：FinderInfo/resource fork 会导致签名错误；Finder 操作也可能附加这些属性。不能仅凭云目录位置推断来源。
- Apple [kSecUseAuthenticationUI](https://developer.apple.com/documentation/security/ksecuseauthenticationui)：说明交互策略键；实际后端兼容性仍需验证。
- Apple [kSecUseDataProtectionKeychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)：说明 macOS Data Protection Keychain 的选择机制。

本轮未执行应用测试、真实授权或修复；方案中所有验收项均待实施后完成。

---

## 六、实施状态（执行者补注，2026-09-11 15:45 GMT+8）

P0 与 P1 已实施并通过自动化测试；P2 与方案 §四 的真实界面项待用户执行。实施细节、逐条对照与偏离清单见 `IMPLEMENTATION_REPORT.md` 第 11 节，构建与校验证据见 `evidence/logs/12-keychain-revision-build.txt`。

| 计划项 | 状态 |
|---|---|
| P0.1 本地 staging 构建、固定运行路径、嵌套可执行校验、双重严格校验 | 已完成。staging 与 `~/Applications/Minget.app` 严格校验通过；`dist/Minget.app` 为归档副本，普通校验通过、严格校验因 iCloud file provider 属性失败并已显式记录 |
| P0.2 在候选副本处理 FinderInfo，保留原包取证 | 已完成。清理只作用于新构建的 staging 与运行路径副本；仓库 dist/ 的历史属性未清除，作为现象证据保留 |
| P0.3 正常 open 启动、确认路径与单一实例 | 部分完成。运行路径为 `~/Applications/Minget.app`，由脚本安装；单一实例与弹框次数需用户在真实界面确认 |
| P0.4 应用内可开启的本地诊断 | 已完成。面板底部开关，写入应用自身 Application Support 目录；不依赖环境变量 |
| P0.5 load/save/delete 分别记录结果类别 | 已完成。三类访问均记录：凭证代号、调用目的、交互模式、结果类别、OSStatus、耗时。不记录密钥、会话、指纹、按钮归属 |
| P1.1 类型化结果 | 已完成 |
| P1.2 串行协调器与合并 | 已完成 |
| P1.3 状态查询只读内存 | 已完成 |
| P1.4 非交互读取与授权门控 | 部分实施，策略已按真实验证修正：`SecKeychainSetUserInteractionAllowed(false)` 之下已授权条目的读取仍被拒（日志对照见 `evidence/logs/13-keychain-background-denial.txt`），按 P1.5 自身的验证要求判为不成立。默认读取路径改回交互允许；防弹框循环由稳定证书身份与协调器的结果记忆承担，「需要授权」状态与授权门控保留，用于真实的拒绝场景 |
| P1.5 交互策略核实 | 已完成核实，结论为弃用开关在本机不适用于默认读取路径；真实弹框行为已由用户实测确认（一次弹框、始终允许、之后不再弹） |
| P1.6 状态缓存与失效 | 已完成 |
| P1.7 单次读取与按模式加载 | 已完成 |
| P1.8 写失败传播 | 已完成 |
| P2 真实授权复核 | 用户已实测（2026-09-11 23:06-23:11）：打开应用仅弹框一次，「始终允许」后不再弹框；授权后真实读取成功（缓存 lastSuccessAt 更新）。仍待观察：后台轮询与面板反复开关 20 次、换 Key／断开／重登、锁屏唤醒 |

自动化测试：359 项通过，0 失败，其中新增 14 项覆盖 P1 的类型化结果、合并、状态记忆、授权门控、单次读取与写失败传播。全部使用合成凭证与可注入结果，未触碰真实钥匙串。

未执行且明确不做：读取或修改任何钥匙串条目、`dump-keychain`、`set-key-partition-list`、删除历史副本、清理用户目录的扩展属性。

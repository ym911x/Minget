# 1.6.3 新增 Google 账号资格错误诊断与修正

日期：2026-10-01，Asia/Shanghai。接续 `fe45d15`，分支仍为 `codex/minget-1-6-3`。版本仍为本机 1.6.3，无远端操作。

## 现场原因

用户添加第三个 Google 账号后，身份与独立连接已保存，但卡片从未成功获取额度。应用元数据显示 Google 连接为三行，目标账号不是停用状态，appdata/workspace/tmp 独立目录均存在。没有打开、读取或复制任何 CLI 认证文件。

通过固定 Google 签名 Antigravity CLI 1.2.13，在该账号已有隔离 HOME/appdata/workspace/tmp 内运行相同沙箱、系统代理、30 秒总超时和只读 `/usage`。返回 exit 1、JSON `status=ERROR`、num_turns=0、total_tokens=0、无额度组。临时解析的错误确认：Google 官方资格检查认为此账号当前所在地不支持 Antigravity。只保存枚举/状态/输出字节计数，原始报告、错误流、身份和授权资料不落盘。

同一应用窗口的两个原 Google 账号仍显示成功更新。此证据定位为目标账号的官方资格拒绝，无法由新增按钮或本机读取逻辑修复服务端资格。没有取得该账号实际登记国家/地区、Google 付款地区或具体服务端判定依据，不补造这些事实。

Google [官方 FAQ](https://www.antigravity.google/docs/faq/#what-is-google-antigravitys-geographical-availability) 指示检查 Google 条款页显示的国家/地区，若登记错误按官方流程申请更正。此次未读取或更改用户 Google 设置，没有代替用户申请地区更改。

## 应用修正

- CLI 原先只分类明确 429，其他 exit 1 统一落到 `nonZeroExit`，最终显示“无法获取数据”，丢失可操作原因。
- 只对 `status=ERROR` 且同时出现已实测的资格失败和地区不可用文案，映射固定 `accountRegionUnavailable`；不保留上游错误原文、不凭 HTTP 403 推断地区。
- 账号行及卡片显示“Google 账号地区不支持 Antigravity”，卡片提供官方说明链接。它不等于凭证过期，不引导用户反复重新登录，不会暂停其他账号。
- `hasCachedData` 必须同时满足存在快照和缓存状态。无快照时不显示“缓存数据”，额度继续为未知；存在旧成功快照时仍正确保留自身缓存。

修改 `AntigravityCLIProcess`、`ProviderFailure`、`AntigravityModel`、`AntigravityViews`、`UsagePanelView`，补充进程分类和模型隔离测试。未知错误仍按原失败策略处理。

## 验证与安装

资格/缓存/账号隔离定向 15 项通过，新增自动测试使用假 CLI 和假 reader，不发模型请求。完整回归 658 项，653 通过、5 项既有环境跳过、0 失败。Release 严格签名通过，候选、archive 和正式安装版指纹一致。备份初版 1.6.3 后安装到 `/Applications/Minget.app`。真实 AX 与截图确认第三行显示具体地区限制及官方说明，无错误缓存标签，原两个 Google 账号仍独立成功刷新。详见 ACCEPTANCE.md 本轮追加项。初版 1.6.3 的证据保留，不将此次服务端拒绝写成真实新账号取数通过。

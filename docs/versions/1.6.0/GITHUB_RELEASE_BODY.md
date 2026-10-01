# 明明有数 · Minget 1.6.0：Google 官方 CLI 双账号额度

本版新增 Google / Antigravity 双账号登录与官方额度读取，并纳入此前尚未单独发布的 1.5.0 界面更新。

## 主要更新

- **两个 Google 账号独立管理**：登录、重新登录、修改显示名称和断开本机，分别显示登录状态与额度读取状态。
- **官方额度来源**：通过 Google 官方 Antigravity CLI 1.2.13 的 `/usage` 查看 Gemini、Claude/GPT 共享组的 5 小时及周额度、剩余百分比和重置时间。无需 CPA。
- **应用内准备 CLI**：从 Google 官方下载固定 Apple Silicon 版本，校验哈希和签名。
- **日常刷新**：独立账号缓存与失败状态，五分钟自动刷新、手动刷新、唤醒补刷，支持菜单栏选择账号与额度组。
- **修复登录闭环**：改善授权码提交反馈、超时重试、首次引导导航及身份确认；后台仅查询用量，不通过模型调用验证账号。
- **界面更新**：供应商切换、共用账号管理、首次连接入口和固定底部操作，并修复菜单栏浮窗交互问题。

## 界面预览

以下为正式界面组件生成的**展示副本**，使用示例账号、比例和时间，不是实时账号数据。更多共享额度组可在卡片中滚动查看。

<img src="https://raw.githubusercontent.com/ym911x/Minget/v1.6.0/assets/screenshots/v1.6.0/google-dual-light.png" alt="Google 双账号浅色展示副本" width="360">
<img src="https://raw.githubusercontent.com/ym911x/Minget/v1.6.0/assets/screenshots/v1.6.0/google-dual-dark.png" alt="Google 双账号深色展示副本" width="360">

<img src="https://raw.githubusercontent.com/ym911x/Minget/v1.6.0/assets/screenshots/v1.6.0/google-accounts-light.png" alt="Google 账号管理展示副本" width="460">

## 使用与构建

延续源码分发，不提供未经公证的本机签名安装包。需要 macOS 13+、Swift 5.9+；Google 功能目前支持 Apple Silicon。

下载下方 Source code，进入项目目录执行：

```sh
MINGET_SIGN_IDENTITY=- ./scripts/build.sh
```

启动后进入“管理账号”，点击“准备官方 CLI”，再分别登录 A/B。官方授权完成后将一次性授权码粘贴到 Minget，按提示完成官方引导。已有固定本机签名证书时，可执行 `./scripts/build.sh`。

## 验证与限制

本机双账号真实登录、官方用量对账、卡片显示、手动刷新、退出重启和官方下载校验已通过。查询未产生模型轮次和 token。详细测试记录见[验收台账](https://github.com/ym911x/Minget/blob/v1.6.0/docs/versions/1.6.0/ACCEPTANCE.md)。

第二台 Mac 首次安装验收延期；自然授权续期、撤销后的恢复和真实睡眠唤醒仍待现场验证。官方 CLI 固定为 1.2.13，其他版本及 Intel Mac 的 Google 接入未验证。

[完整更新说明](https://github.com/ym911x/Minget/blob/v1.6.0/docs/versions/1.6.0/RELEASE_NOTES.md) · [变更记录](https://github.com/ym911x/Minget/blob/v1.6.0/CHANGELOG.md)

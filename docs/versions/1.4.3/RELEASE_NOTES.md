# 明明有数 · Minget 1.4.3

修复两个 Codex 账号在官方 App 更新或从 Finder 启动后无法读取用量的问题。原有程序路径变化时自动查找新位置；已有 Node CLI 使用完整运行环境启动。

## 变更

- 自动识别系统及用户 Applications 下的 ChatGPT/Codex 官方 App 新旧布局，优先使用内置原生 Codex。
- 用量读取与应用内已授权点火共用启动描述；Node CLI 使用绝对 Node 路径及解析后的程序入口，保留 A/B 独立账号目录。
- 候选程序执行有超时的本地版本探测，失败可回退；显式路径覆盖失败直接报错。连接重建重新解析，正式接口失败不触发额外模型请求。
- 缓存及无数据状态显示具体故障；设置页区分未安装、缺少 Node、启动失败和未登录，提供处理说明。
- 项目默认由 Codex 直接实现，只有用户明确要求时才委托 Claude Code。

## 验证与兼容性

- 本机自动测试：551 项执行，550 通过、1 项既有辅助功能环境跳过、0 失败。
- Release arm64 严格签名、本机备份安装、Finder 启动、双账号真实只读读取、连续自动刷新及退出重启恢复均已核验；备用 Node CLI 的真实只读读取也通过。
- 详情页真实点击刷新、浮窗关闭重开及视觉验收尚待补充；第二台 Mac 尚未实测，安装组合由隔离测试覆盖。
- 原账号隔离、缓存、Keychain 和定时计划保留。未通过真实点火或消费重置权益进行测试。

## 源码构建

本次继续采用源码分发，不提供未经公证的安装包。需要 macOS 13 或以上、Swift 5.9 或以上，并已安装受支持的官方 Codex App 或 CLI；若使用 Node CLI，还需 Node。Minget 不捆绑或自动安装这些依赖。

下载本 Release 的 Source code，进入项目目录后执行 `./scripts/build.sh`。默认使用本机已有的 Minget Local Signing 证书；首次构建没有该证书时可使用 `MINGET_SIGN_IDENTITY=- ./scripts/build.sh` 进行本地 ad-hoc 签名。

完整验收及证据见仓库 `docs/versions/1.4.3/ACCEPTANCE.md`。

# v1.0.2 证据目录说明

本目录只放 1.0.2 候选包的验收证据。所有图与日志均为本轮实际生成，未使用历史版本产物。

采集条件（全部证据共用）

| 项目 | 值 |
| --- | --- |
| 运行包 | `dist/Minget.app`，`CFBundleShortVersionString` = `1.0.2` |
| 运行方式 | 复制到 `/tmp/minget-run/Minget.app` 后直接启动可执行文件，避免与仓库内旧包混淆 |
| 流水线 | `swift test`（XCTest 宿主进程）与真实 GUI 进程两种，分别在图与日志中标注 |
| 显示环境 | 内建屏 1512 × 982，带刘海，`NSStatusBar.system.thickness` = 22.0 pt |
| 时间 | 2026-09-11（UTC+8） |
| 采集时间戳 | 见每份日志首行或 `logs/01`、`logs/02` 的采集时间 |

## 图片：真实视图代码的离屏渲染（夹具，不是截图）

这些 PNG 由 `Tests/UsageMonitorAppTests/MenuBarEvidenceRenderTests.swift` 生成，渲染的是生产代码里的 `MenuBarLabelContent` 与 `ResetTimeBarsView`，输入是固定锚点时间 `1800000000` 的夹具数据。它们**不是**真实菜单栏截图，原因见下。用途是核对布局本身：段数、两排对齐、方向、前方唯一标记、`?` 状态、以及 `M²` 已消失。

| 文件 | 内容 | 比例 |
| --- | --- | --- |
| `01-menubar-states-light.png` | 浅色下 15 种状态的菜单栏标签全貌 | 4x |
| `02-menubar-states-dark.png` | 同上，深色 | 4x |
| `03-direction-light.png` | 5 小时行从满格到归零的 7 个时间点 | 4x |
| `04-weekly-direction-light.png` | 周行从 7 天到归零的 5 个时间点 | 4x |
| `05-bars-detail-light.png` | 仅两排条，放大核对段数、间距与 `?` | 6x |
| `06-bars-detail-dark.png` | 同上，深色 | 6x |
| `07-menubar-band-light.png` | 22 pt 裁切带：左侧按状态项真实高度裁切，右侧不裁切对照 | 6x |
| `08-menubar-band-dark.png` | 同上，深色 | 6x |

`07` 与 `08` 是判断「文字与细线是否被状态项裁切」的主要依据，因为真实状态项给标签的高度就是 22 pt 并会裁切溢出内容。

为什么没有真实截图：本环境没有屏幕录制权限，`screencapture -x` 无法执行。需求文件 §8.2 允许在环境无法覆盖时记录未验证项。

## 日志

| 文件 | 内容 |
| --- | --- |
| `logs/01-test-and-repo.txt` | 采集时间、`git rev-parse HEAD`、`git status --short`、`VERSION`、`swift test` 汇总（345 项通过） |
| `logs/02-build-and-bundle.txt` | `./scripts/build.sh` 输出、`plutil -lint`、Info.plist 关键字段、`codesign --verify`、`codesign -dv`、二进制架构 |
| `logs/03-real-run-after-fix.log` | 修复后、单实例、从 `/tmp/minget-run` 启动的真实运行。授予宽度 116 pt，`requested` 与 `baseline` 均等于实测值，`truncated:n`，`mode:full` 稳定 20 余次检查，退出路径干净 |
| `logs/04-real-run-truncation-defect-before-fix.log` | 修复前、单实例、同样从 `/tmp/minget-run` 启动的真实运行。授予宽度同为 116 pt，但 `requested:132`（未测量的 fallback）判为 `truncated:y`，几秒内降级到最小兜底并自动打开详情窗口。与 `03` 构成 A/B |
| `logs/05-real-run-first-candidate.log` | 修复前、从仓库目录启动的真实运行。同为 116 pt 授予宽度却保持 `mode:full`，说明第 5 节的缺陷是竞态 |
| `logs/06-real-run-truncation-defect-with-measure-diagnostics.log` | 修复前、带临时测宽诊断的一次运行。含三种模式的实际测宽（无数据 67／61／28，真实数据 100／94／28）。该次采集时另有 1 个实例在运行，因此授予宽度偏小（83／77／44 pt），仅用于读取测宽数值与观察降级过程 |
| `logs/07-signing-state.txt` | 签名改造执行前的现状：构建脚本未改动、本机无签名证书、候选包仍为 ad-hoc、DR 仍为 cdhash、三个副本 DR 互不相同。用于与 `SIGNING_HANDOFF.md` 的验收标准对照 |
| `logs/08-signing-build-path.txt` | 签名改造执行后的两条路径实测：默认路径在无证书时 `exit=1` 且不改动 `dist/Minget.app`（DR、mtime、大小逐字段不变），ad-hoc 回退路径构建与校验通过。另记录「源码未变时重建 cdhash 不变」这一事实修正 |
| `logs/09-signed-verification.txt` | 证书创建后的复核：`find-identity` 的两种情况对比，交接文件 §4 第 1、2、4 条的实测，§4 第 3 条的 release 到 debug 到 release 对照（CDHash 变化而 DR 证书哈希不变），以及三次签名启动的启动间隔 |
| `logs/10-staging-fail-closed.txt` | 一次真实的 staging 静默失败：`rm -rf` 被环境拒绝后原脚本继续 staging，把 debug 构建留在 `dist/` 并误报成功。含新增失败保护后的实测行为与修复后的包状态 |
| `logs/11-dialog-investigation.txt` | 弹框未消除的调查记录：用户报告的 12 次弹框、代码侧 3 个条目对 10 处访问点的对比、exec 启动与 LaunchServices 启动的方法差异、正常启动路径无法采集应用内日志的原因、间接计时的噪声说明，以及下一步的判别观察 |
| `logs/12-keychain-revision-build.txt` | `KEYCHAIN_REVISION_PLAN.md` 执行后的构建与校验：本地 staging 严格校验通过、运行路径 `~/Applications/Minget.app` 严格校验通过、归档副本的普通与严格校验差异、运行候选包的签名身份与 DR、359 项测试结果 |

日志来自 `USAGE_MONITOR_LOG_FILE` 指向的诊断文件，默认关闭。内容只有生命周期事件与几何数值（模式、frame、请求宽度、判定基线、截断标志、连接状态类别、账号类别），不含任何额度数值明细、凭证、Cookie 或用户输入。已用关键词扫描确认无 `sk-`、`bearer`、`api_key`、`token`、`eyJ`、`password`、`secret` 形态内容。

`logs/09` 末尾附有一段执行者更正：该文件「切回 release」一行的 CDHash 实为 debug 构建（staging 事故所致），已注明原因并指向 `logs/10`，历史记录未改写。此外，自 `KEYCHAIN_REVISION_PLAN.md` 实施起另有应用内的钥匙串访问日志（面板可开关，写入应用自身的 Application Support 目录），不依赖环境变量，属运行期证据，不在本目录归档范围内。

# 2026-11-18 本机验证

| 核验 | 结果 |
| --- | --- |
| 正式安装基线 | 1.6.10 主程序 SHA-256 与发布记录一致。远端 main 为 `973366f`，Latest 为 v1.6.10。 |
| 真实套餐 | 4 个本机已登记账号通过生产 `AntigravityUsageService.read`，分别成功返回匹配身份、有效额度组和套餐，合计 Ultra 3 个、Pro 1 个。探测期间使用固定官方 CLI，仅执行内置用量查询和只读观察欢迎页。 |
| 拖动 | 生产 `UsagePanelView` 在 macOS 窗口中加载隔离示例账号。发送鼠标拖放事件将 1、2、3 改为 2、1、3。五账号测试在视口底部停留，再松到原本在屏外的第四个位置，落位顺序为 2、3、4、1、5。 |
| 共享与持久化 | `OverviewReorderTests` 20 项通过，覆盖同品牌插入、其它品牌位置、新账号追加、无效拖动和从本地偏好重建。 |
| 渲染 | `MINGET_RELEASE_SCREENSHOTS=… swift test --filter ReleaseScreenshotTests` 通过，实际检查示例卡片副标题的 Google AI Pro 和 Google AI Ultra 均完整可见。 |
| 回归 | `swift test --scratch-path /tmp/minget-1611-integrated --disable-sandbox`，Core 460 项、App 251 项，共 711 项，706 通过、5 跳过、0 失败。 |
| 构建 | `scripts/build.sh` 生成 1.6.11 Release 测试包，使用 Minget Local Signing，staging、review 和 archive 三处严格签名校验通过。 |

本机交付包在主目录 `artifacts/1.6.11/Minget-1.6.11.zip`，SHA-256 为 `f45194131af6564d19cf59f71621059a51da89c0f2bf4653502b5b6e308d6cec`。主程序 SHA-256 为 `2c5698f26d8a4fba378875c311da543f75ce164d96e9ded038db49bf1bd42452`。从 ZIP 重新解包后，`codesign --verify --deep --strict` 通过。

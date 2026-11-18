# 1.6.12 实施

- 核对截图账号的官方额度组名、周期、比例和重置时间字段。
- 修改 `AntigravityViews.swift`、`SharedQuotaViews.swift` 和 `UsagePanelView.swift`，按 Argon 实际返回的额度桶渲染并估算面板高度。颜色沿用 Gemini 的额度阈值。
- 修改 `DetailPreferences.swift` 和 `MingetSettingsView.swift`，将新开关独立持久化，绑定至所有 Google 详情卡。
- 在 `AntigravityModelTests.swift` 增加开关持久化、其他组独立性和不同周期的卡片布局回归。执行完整 `swift test` 和签名 Release 构建，具体结果见[验收](ACCEPTANCE.md)。

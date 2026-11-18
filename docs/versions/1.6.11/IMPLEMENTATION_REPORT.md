# 1.6.11 实施记录

- `AntigravityTerminal`、`AntigravityLoginSession`、`AntigravityUsageService` 和 `AntigravityProvider` 实现套餐读取与可选缓存。`AntigravityModel` 传递上次核对结果，`AntigravityViews` 将套餐显示在名称下方。
- `DetailAccountReorder`、`SharedQuotaViews`、`UsagePanelView` 和 `OverviewAccountOrderPreferences` 接入系统拖放与同品牌排序。单账号无需排序，多账号支持拖到视口边缘自动滚动。
- 核对了额度模型、PTY 延迟渲染、身份错配、取消、缓存兼容和同品牌排序测试，使用生产面板测试鼠标事件并导出示例卡片。命令和结果见[验证记录](evidence/verification.md)。

# 1.6.1 最后调整：Logo 导航

2026-10-01，代码 `0f7d667`。正式安装版已更新，未推送或发布。

## 要求与实现

用户要求概览和服务平铺显示 Logo、单击直接切换、更新状态移到刷新旁。截图红色框按位置标注处理。

`Sources/UsageMonitorApp/Views/UsagePanelView.swift` 移除服务 Picker 和返回概览文案，按概览、ChatGPT、Gemini、DeepSeek、Command Code 排列图标按钮。概览使用四格图标，服务复用已有品牌图标。按钮 44×36 pt、间距 8 pt，图标不显示名称；悬停提示和无障碍标签保留名称，浅色底及边框指示选中状态。禁用显示的服务不显示按钮。点击直接写入原 selectedTab，继续使用现有内容页和稳定窗口。

聚合更新状态移到头部刷新按钮左侧，状态口径与刷新动作未改变。44 pt 导航行和外层 440×640 pt 几何不变，固定窗口及隐藏滚动条继续保留。

## 验证

- 应用测试 177 项，176 通过、1 项既有跳过、0 失败，包括真实弹层服务切换/折叠 frame 不变回归。见 [日志](evidence/logo-navigation-tests.log)。未新增与布局实现重复的测试。
- Release arm64 签名构建，候选及正式安装严格签名验证通过。见 [构建日志](evidence/logo-navigation-build.log) 和 [指纹](evidence/logo-navigation-verification.json)。
- Finder 固定路径启动正式 App，经 CUA 逐一点击五个图标，内容页面与 AX 已选中状态均对应，截图确认只有 Logo、聚合状态在刷新旁。最终返回概览。未点击点火或修改凭证。
- 本次启动时 Gemini 读取状态为缓存/无法获取数据，界面正确保留该状态；因此本轮证明导航和显示，不宣称实时 Google 取数验收。此 UI 修改没有改变取数代码。
- 用户最终使用确认、第二 Mac、实际深色/短屏仍待复验；本次没有新增签名包启动自动测试，沿用窗口补修的 2 项结果并补充正式 App Finder 启动检查。

## 回退与记录

修复前备份：`~/Applications/Minget Backups/1.6.1-before-logo-nav-20261001-142458/Minget.app`。正式安装 executable SHA-256：`fe341c32cfc417aa21bec558cafd2c08bb2c85632eeb5bc8b04bfb0ff50ef440`。旧指纹与旧日志保持原样，不覆盖历史证据。

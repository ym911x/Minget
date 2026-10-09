# 当前审核状态

当前对象为 **1.6.4 概要页拖动排序**。跨平台全局混排与仅概要持久化的顺序偏好已实现；拖动位移在窗口坐标系测量（消除跟手反馈），被拖行精确跟手、其余行按整格滑让，页面级动画抑制已移除使滑动动画生效。构建与 679 项完整回归（5 项既有跳过、0 失败）通过，Release 严格签名后按用户要求装入正式路径；用户复测确认拖动跟手、无抖动、按下即可拖动，本轮固化。拖动期间刷新不打乱行序、重启恢复顺序、键盘与 VoiceOver 现场项仍待核对，拖动到视口边缘不自动滚动为已知边界。现场验收项见 [验收台账](docs/versions/1.6.4/ACCEPTANCE.md)。

- [当前项目状态](PROJECT_STATUS.md)
- [实施记录](docs/versions/1.6.4/IMPLEMENTATION_REPORT.md)
- [代码与验证审核](docs/versions/1.6.4/REVIEW.md)
- [验收台账](docs/versions/1.6.4/ACCEPTANCE.md)

上一版本 1.6.3 已公开发布，GitHub CI 测试与构建通过；其现场待验收项不因本版本改变，见 [1.6.3 发布记录](docs/versions/1.6.3/PUBLICATION.md) 与 [1.6.3 验收](docs/versions/1.6.3/ACCEPTANCE.md)。历史版本记录保持原样。

# 明明有数 · Minget 1.2.1

这是针对 Command Code 详情卡的显示修订。

## 本次更新

- Command Code 的已用、剩余和成本金额统一显示到小数点后 2 位。
- 移除 Command Code 卡片底部重复的“刚刚更新”“更新于 X 分钟前”等文字，继续使用详情页顶部的全局刷新状态。
- 收紧 Command Code 卡片占用的详情页高度，减少无效空白。

## 验证

- `swift test`：310 项通过，0 项失败。
- Release 构建、版本检查和严格签名验证通过。
- 用户真实界面确认金额精度、更新时间移除和完整布局均符合要求。

![Minget 1.2.1 详情页脱敏示例](https://raw.githubusercontent.com/ym911x/Minget/v1.2.1/assets/screenshots/v1.2.1/detail-redacted.png)

截图中的邮箱、余额和用量均为示例数据，菜单栏已移除其他第三方程序图标。

当前发布继续提供源码构建说明，不附带未经 Apple Developer ID 公证的安装包。

# Minget 1.6.5：Command Code 月额度与品牌单独刷新

概览页的 Command Code 行同时显示 5H 与月额度，周额度继续保留在详情卡。月度剩余不可读时显示周额度，两者都缺失时只显示 5H；缺失金额显示 `—`，缓存数据保持明确标记。

ChatGPT、Gemini、DeepSeek、Command Code 详情页新增刷新按钮，只刷新当前品牌的账号。刷新中显示进度并禁用按钮；概览页继续使用页头全局刷新。

本机独立完整回归 686 项，681 通过、5 项既有环境跳过、0 失败；Release 严格签名与正式安装版指纹核对通过，用户已复验双列显示及四个品牌刷新范围。

验证边界：VoiceOver 现场朗读、Command Code Studio 同刻对账、第二台 Mac 尚未完成。月度上限沿用详情卡的已用加剩余规则，字段语义仍为 C 级。详细状态见 [验收台账](https://github.com/ym911x/Minget/blob/v1.6.5/docs/versions/1.6.5/ACCEPTANCE.md)。

本次继续通过 GitHub 分发源码，不附本机签名 App。

GitHub CI 对发布提交测试、Release 构建和严格签名校验通过：686 项，631 通过、55 项 CI 环境跳过、0 失败。[查看 CI](https://github.com/ym911x/Minget/actions/runs/38029112741)。

# 1.6.11 验收

四个已登录 Google 账号的真实套餐与额度读取通过。已在隔离测试窗口中验证账号图标拖动、跨屏内外卡片落位，并核对同品牌排序保存与示例卡片渲染。711 项回归中 706 通过、5 项既有跳过、0 失败。详见[验证记录](evidence/verification.md)。

2026-11-18 经用户确认，已将本机签名 Release 安装到 `/Applications/Minget.app` 并从该路径重启。版本号、主程序 SHA-256 和严格签名校验通过。旧版本已备份至 `~/Library/Application Support/Minget Backups/Minget-1.6.10-20261118.zip`，重新解包后验证了版本号、指纹与签名。第二台 Mac、VoiceOver 现场操作和用户使用反馈尚无本次记录。公开发布基线仍为 1.6.10。

# 1.3.0 修订 Agent 交接说明

## 当前任务

首轮 1.3.0 已实现，但未通过用户界面验收。你负责按 `REVISION_SPEC.md` 完成回归修订，不重新设计产品。

开始前按此顺序完整阅读：

1. 根目录 `AGENTS.md`
2. 根目录 `README.md`、`ROADMAP.md`、`PROVIDER_ENDPOINTS.md`
3. `docs/versions/1.3.0/REVISION_SPEC.md`
4. `docs/versions/1.3.0/REQUIREMENTS.md`
5. `docs/versions/1.3.0/UI_SPEC.md`
6. `docs/versions/1.3.0/IMPLEMENTATION_TASKS.md`
7. `docs/versions/1.3.0/REVIEW.md` 和 `ACCEPTANCE.md`
8. 根目录双 ChatGPT 账号点火实施记录

`REVISION_SPEC.md` 是本轮最高优先级依据。尺寸、顺序、字号、进度含义、方向、颜色、刻度、文案、缺失状态、popover 降级和测试项均已决定，不要自行取舍。

2026-09-17 第三轮界面微调后，最终尺寸和展示文案改由 `UI_SPEC.md` 当前内容约束。`REVISION_SPEC.md` 中的 520 pt 第二轮尺寸只作为历史背景。

## 必须完成

1. 删除 `Settings { EmptyView() }`，改用显式 AppKit lifecycle，冷启动不再弹空设置窗口。
2. 详情页改为 520 pt 单列，固定顺序 A、B、DeepSeek、Command Code；四卡全开为 `520 × 560 pt`，无任何滚动容器。
3. ChatGPT 恢复 1.2.1 的额度轨道和 5/7 段重置时间轨道；双账号仍保持独立状态和点火按钮。
4. Command Code 主轨道改为 `remaining / limit`，增加 5/7 段和无刻度月度时间线，显示额度剩余和时间剩余。
5. popover 在 show 前设置明确尺寸，以菜单栏按钮 `midX` 为锚点；无法容纳时改开普通详情窗口。
6. `ChatGPTFireService` 增加幂等 `stopAll()`，退出时终止并回收 A/B 仍运行的点火进程。
7. 点火后只有 `FetchResult.isLive == true` 的刷新可以确认新窗口；缓存结果必须触发第二次刷新。
8. 更新测试、脱敏渲染、实施报告、审核和验收台账，并同步根目录中仍写 720 pt 双列或旧测试数的文档。

## 不得改变

- 双 ChatGPT Profile ID、默认名称和两个隔离 `CODEX_HOME`。
- 菜单栏 A/B/DeepSeek 三来源选择和 DeepSeek 币种逻辑。
- 点火使用的固定 Codex CLI 参数、120 秒超时、3 秒 terminate grace。
- DeepSeek/Command Code API Key 只进 Keychain。
- 现有 LaunchAgent、`minget-fire`、两个 `CODEX_HOME` 内容。
- 任何认证文件、浏览器 Cookie、密码和 raw 点火日志都不得读取或写入项目。

## 工作区边界

当前工作树包含首轮 1.3.0 的大量未提交修改，以及用户已有的 `.workbuddy/`、`.commandcode/`、1.0.2 evidence PNG 和根目录实施记录。不得清理、回退或覆盖这些内容。

渲染测试只写 `$TMPDIR/Minget-1.3.0-Evidence/`，不得改写任何历史 evidence。

## 验证命令

测试 scratch path 必须位于仓库和 iCloud Drive 之外：

```bash
MINGET_TEST_SCRATCH="$(mktemp -d /tmp/minget-swift-test.XXXXXX)"
swift test --scratch-path "$MINGET_TEST_SCRATCH"
```

之后执行 `./scripts/build.sh`，验证 Release 构建、staging 严格签名和固定安装路径严格签名。

## 停止和交付

不发布、不推送、不打标签、不创建 GitHub Release，不执行真实点火。完成后把以下内容写入 `IMPLEMENTATION_REPORT.md`：

- 修改文件
- 实际命令
- 测试总数和结果
- Release 构建与签名结果
- 脱敏渲染路径
- 冷启动、popover 边界和退出清理的真实运行结果
- 已知问题和未完成事项

然后停止，等待 Codex 独立复核和用户真实界面验收。

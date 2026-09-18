# assets/screenshots/

本目录保存**可公开**的界面截图，用作视觉基线。不是每个版本都有截图目录——只有具备公开展示价值或需要固定视觉基线的版本才保存，缺目录不代表资料遗失。

## 内容

| 目录 | 内容 | 说明 |
| --- | --- | --- |
| `v1.1.0/` | `menu-bar.png`、`detail-redacted.png`、`settings.png` | 详情页重构与精简设置后的界面基线 |
| `v1.1.1/` | `menu-bar.png`、`detail-redacted.png`、`settings.png` | 移除 GLM 入口后的界面基线 |
| `v1.2.1/` | `detail-redacted.png` | Command Code 金额与详情卡片空间修订后的详情页 |
| `v1.3.0/` | `detail-redacted.png` | 440 pt 单列、双 ChatGPT 账号、DeepSeek 单行卡与 Command Code 三周期卡 |

## 约定

- 所有入库截图必须是**脱敏副本**：邮箱、余额、额度、重置时间、用量和统计数据一律替换为示例值，并在引用处标注为展示副本。
- 不使用含真实账号、真实余额或真实 API Key 的原始截图。
- 历史截图作为视觉基线保留，不因后续版本改版而重绘；需要新基线时新建版本目录。
- 自动化渲染证据不写入本目录：渲染测试输出到 `$TMPDIR/Minget-1.3.0-Evidence/`，需要入库的脱敏图片在人工审核后单独复制进来。
- 只有本地实测的证据图（例如 `docs/versions/1.0.2/evidence/`）保留在对应的版本目录内，不放这里。

## 引用位置

截图按需由相关版本资料、根目录 `README.md` 或 `docs/versions/README.md` 的索引引用。新增或移动截图时请同步更新对应引用。

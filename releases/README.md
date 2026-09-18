# releases/

本目录只保留早期版本的**本地发布说明**。它不是发布源的完整记录。

## 内容

| 目录 | 保留内容 | 状态 |
| --- | --- | --- |
| `v1.0.0/` | `README.md` | 已入库 |
| `v1.0.1/` | `README.md` | 已入库 |

两个版本的 App 包与源码 ZIP 曾经放在本目录，但它们是构建产物，可随时重新生成，也不适合留在 Git 仓库中；现已移出仓库。校验和文件随对应的 ZIP 一并移出，因为校验一个已不在本机的文件没有意义。

## 发布源

- **`v1.0.0`、`v1.0.1`**：以本目录的发布说明为准，另见 [CHANGELOG.md](../CHANGELOG.md) 中对应条目与 Git 标签 `v1.0.0`、`v1.0.1`。
- **`v1.1.0` 起**：以 GitHub Releases 和 [CHANGELOG.md](../CHANGELOG.md) 为发布源，本目录不再新增内容。
  - 发布页入口：[Minget Releases](https://github.com/ym911x/Minget/releases)

## 约定

- 不在 Git 仓库保存 App 包、源码 ZIP 或其它构建产物。
- `.gitignore` 已忽略 `releases/**/*.zip` 和 `releases/**/SHA256SUMS.txt`，避免误提交。
- 当前正式运行候选位于 `~/Applications/Minget.app`，由 `scripts/build.sh` 生成并做严格签名校验，不属于发布记录。

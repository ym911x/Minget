# 1.4.2 本机回滚

仅在需要回滚时执行。本次升级保留应用、三个外部脚本的原件；不删除日志、Keychain 或账号数据。应用与脚本可以分别回滚。

## 应用

先从 Minget 菜单退出应用。确认目标保留目录尚不存在，再执行：

```sh
test ! -e "$HOME/Applications/Minget-1.4.2-retained.app" && \
mv "$HOME/Applications/Minget.app" "$HOME/Applications/Minget-1.4.2-retained.app"
ditto "$HOME/Applications/Minget-1.4.1-backup-J32BHM/Minget.app" "$HOME/Applications/Minget.app"
codesign --verify --deep --strict --verbose=2 "$HOME/Applications/Minget.app"
open "$HOME/Applications/Minget.app"
```

若第一步失败，停止，不继续覆盖。旧版与新版均保留，可再次切换。

## 外部脚本

先检查 `launchctl print gui/$(id -u)/com.minget.chatgpt-fire`，仅在任务未运行、且不接近计划时刻时恢复。此次安装的备份后缀为 `backup-20260923T065233Z-60917`。以下逐个暂存后原子替换；任一命令失败即停止：

```sh
(
set -e
for target in "$HOME/.local/bin/minget-fire" \
  "$HOME/.local/libexec/minget-fire/read-codex-reset.py" \
  "$HOME/.local/libexec/minget-fire/run-with-timeout.py"; do
  test -f "$target.backup-20260923T065233Z-60917"
done
for target in "$HOME/.local/bin/minget-fire" \
  "$HOME/.local/libexec/minget-fire/read-codex-reset.py" \
  "$HOME/.local/libexec/minget-fire/run-with-timeout.py"; do
  test ! -e "$target.rollback-stage"
  cp -p "$target.backup-20260923T065233Z-60917" "$target.rollback-stage"
  mv "$target.rollback-stage" "$target"
done
)
```

不修改 plist、不重载 launchd、不手动点火；下一次原计划会读取恢复后的脚本。此后日志重新采用旧版语义，不能把旧版的窗口未推进退出码与 1.4.2 混为一谈。

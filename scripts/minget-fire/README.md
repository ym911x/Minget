# Minget external fire scheduler — template (1.4.2)

A reproducible copy of the external scheduler that runs the fixed Command Code fire
schedule outside the app: account A, 15 s later account B, 15 s later Command Code,
each request bounded by 120 s. The template mirrors the installed
`~/.local/bin/minget-fire` and `~/.local/libexec/minget-fire/` helpers, with the 1.4.2
semantics:

- **Request outcome and reset observation are separated.** `exit 0` covers all three
  "the request ran" outcomes; the observation (advanced / unchanged / unavailable) is
  logged separately and never turns a successful request into a failure. Only a process
  failure or a timeout exits nonzero (124 on timeout).
- **Sanitized logs.** Log lines use the fixed vocabulary — `target`, `start`, `end`,
  `exit`, `duration`, `window`, `used`, `reset` — and nothing else. Child output is
  discarded; no identity, path or raw payload ever reaches the log.
- **Read-only confirmation.** After each request the 5-hour window is read twice
  (2 s, then 5 s later if the first read says nothing). No second model request is
  ever made.
- **Observation, not proof.** A reset time ≥ 60 s later than before means the reported
  reset time advanced — not that a new window opened.

## Layout

| File | Purpose |
| --- | --- |
| `bin/minget-fire` | The scheduler: `a`, `b`, `c`/`commandcode`, `all`. |
| `libexec/minget-fire/read-codex-reset.py` | Reads the 5-hour window over the app-server JSON-RPC protocol. Byte-buffered `os.read`, one monotonic total deadline, tolerant of fragmented and coalesced JSON, kills the whole process group on the way out. |
| `libexec/minget-fire/run-with-timeout.py` | Runs one request under a hard timeout; SIGTERM then SIGKILL on the process group; exit 124 on timeout. |
| `tests/run_tests.sh` | Fake-CLI test suite (serial order, timeout continuation, aggregation, fragmented/coalesced JSON, total deadline, process-group cleanup, sanitized logs). |
| `SHA256SUMS` | Expected hashes of the three installable files; verified by the installer. |

## Installing

`scripts/install-minget-fire.sh` is the only supported path. It verifies the template
hashes and preflights all installed files before writing anything. Existing files must
match either the exact recorded pre-1.4.2 hashes or the current template; otherwise the
installer refuses to overwrite them. It backs up all recognized legacy files next to
their targets with a UTC-stamped name and hash verification, stages and verifies all
replacements, then replaces atomically (temp file + rename) and prints exact rollback
commands. It **never** touches launchd: no plist writes, no `launchctl load/reload`, and
no signal to a running `com.minget.chatgpt-fire` job. Because the scheduled command still
uses the same `~/.local/bin/minget-fire` path, no plist reload is needed.

```sh
scripts/install-minget-fire.sh --check   # verify hashes, show the plan, write nothing
scripts/install-minget-fire.sh           # install
```

`--check` verifies both the template hashes and every existing installation target;
it exits nonzero when templates differ from `SHA256SUMS` or an installed file does not
match a recorded legacy hash or current template.

## Overridable environment

Every path, timeout and delay is overridable with `MINGET_FIRE_*` variables; the
defaults are exactly the production values. This is what lets `tests/run_tests.sh`
exercise the real scheduler logic against fake CLIs.

| Variable | Default |
| --- | --- |
| `MINGET_FIRE_CODEX` | `/opt/homebrew/bin/codex` |
| `MINGET_FIRE_CMD` | `/opt/homebrew/bin/cmd` |
| `MINGET_FIRE_WORKDIR` | `/tmp/minget-fire` |
| `MINGET_FIRE_LOGDIR` | `$HOME/Library/Logs/Minget` |
| `MINGET_FIRE_TIMEOUT_HELPER` | `$HOME/.local/libexec/minget-fire/run-with-timeout.py` |
| `MINGET_FIRE_RATE_READER` | `$HOME/.local/libexec/minget-fire/read-codex-reset.py` |
| `MINGET_FIRE_CODEX_HOME_A` / `_B` | `$HOME/.codex-minget-a` / `$HOME/.codex-minget-b` |
| `MINGET_FIRE_REQUEST_TIMEOUT` | `120` |
| `MINGET_FIRE_VERIFY_TIMEOUT` | `8` |
| `MINGET_FIRE_INTER_TARGET_DELAY` | `15` |

The commands, models and schedule are unchanged from production and are deliberately
not parameterised: `codex exec --ephemeral --sandbox read-only --skip-git-repo-check
-C "$WORKDIR" -m gpt-5.6-luna -c 'model_reasoning_effort="none"' 'Reply exactly: OK'`
per account, and `cmd --model deepseek/deepseek-v4.1-flash -p 'Reply exactly: OK'` for
Command Code.

## Running

```sh
~/.local/bin/minget-fire all    # A -> 15 s -> B -> 15 s -> Command Code (strict serial)
~/.local/bin/minget-fire a      # one account
~/.local/bin/minget-fire c      # Command Code
```

`all` never cancels the remaining targets after a failure or timeout; its aggregate
exit code is 0 only when every request succeeded.

## Testing

```sh
scripts/minget-fire/tests/run_tests.sh
```

Runs in a `/tmp` sandbox with fake `codex`/`cmd` executables. No network, no model
call, no real account data.

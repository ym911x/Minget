#!/bin/zsh
# Minget 1.4.2 — scheduler template test suite.
#
# Exercises scripts/minget-fire/bin/minget-fire and the two libexec helpers against
# fake `codex` and `cmd` executables. No network, no model call, no real account:
# every fake writes only to the sandbox and to fixed-value JSON.
#
# Covered:
# - strict serial order in `all`: A -> delay -> B -> delay -> Command Code,
# - request timeout (124) with `all` continuing to the remaining targets,
# - aggregate exit codes: all-success 0, any failure 1,
# - unchanged / unavailable reset observation exits 0 when the request succeeded,
# - the reader tolerates fragmented JSON (one message split across reads) and
#   coalesced JSON (two responses in one write),
# - the reader enforces ONE total deadline (a server that never answers id 2 is cut
#   off on the shared budget, not a per-message budget),
# - process-group cleanup: descendants die even when the direct child exits first,
#   and descendants that ignore TERM are escalated to KILL,
# - logs keep the sanitized vocabulary (target/start/end/exit/duration/window/used/
#   reset) and never contain child output or identity markers.

set -u
unsetopt errexit 2>/dev/null || true

HERE="${0:A:h}"
TEMPLATE_BIN="$HERE/../bin/minget-fire"
READER="$HERE/../libexec/minget-fire/read-codex-reset.py"
HELPER="$HERE/../libexec/minget-fire/run-with-timeout.py"
INSTALLER="$HERE/../../install-minget-fire.sh"

SANDBOX=$(mktemp -d /tmp/minget-fire-tests.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

FAILURES=0
PASS() { print -r -- "ok - $1"; }
FAIL() { print -r -- "not ok - $1"; FAILURES=$((FAILURES + 1)); }
assert_eq() {
    local desc="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then PASS "$desc"; else FAIL "$desc (want [$want] got [$got])"; fi
}

for f in "$TEMPLATE_BIN" "$READER" "$HELPER"; do
    [[ -f "$f" ]] || { print -r -- "missing $f"; exit 1; }
done
[[ -f "$INSTALLER" ]] || { print -r -- "missing $INSTALLER"; exit 1; }

# --- Fake executables -------------------------------------------------------------
FAKE_BIN="$SANDBOX/fake-codex"
cat > "$FAKE_BIN" <<'PYEOF'
#!/usr/bin/python3
import json, os, subprocess, sys, time

RECORD = os.environ.get("FAKE_RECORD", "")
PIDFILE = os.environ.get("FAKE_PIDFILE", "")
MODE = os.environ.get("FAKE_SERVER_MODE", "normal")
RESET_BASE = int(os.environ.get("FAKE_RESET_BASE", "1700000000"))
RESET_STEP = int(os.environ.get("FAKE_RESET_STEP", "0"))
USED = int(os.environ.get("FAKE_USED", "42"))
EXEC_SLEEP = float(os.environ.get("FAKE_EXEC_SLEEP", "0"))
EXEC_EXIT = int(os.environ.get("FAKE_EXEC_EXIT", "0"))
COUNTFILE = os.environ.get("FAKE_COUNTFILE", "")
SECRET = "SECRETMARKER-a@example.com"


def record(entry):
    if RECORD:
        with open(RECORD, "a") as f:
            f.write(json.dumps(entry) + "\n")


def write_line(obj, fragmented=False):
    msg = (json.dumps(obj, separators=(",", ":")) + "\n").encode()
    out = sys.stdout.buffer
    if fragmented:
        for i in range(0, len(msg), 7):
            out.write(msg[i:i + 7])
            out.flush()
            time.sleep(0.02)
    else:
        out.write(msg)
        out.flush()


def rate_result(reset):
    # `note` carries a marker that must never leak into any log.
    return {"rateLimitsByLimitId": {"codex": {
        "primary": {"usedPercent": USED, "windowDurationMins": 300, "resetsAt": reset},
        "secondary": {"usedPercent": 1, "windowDurationMins": 10080, "resetsAt": RESET_BASE + 99999},
        "note": SECRET,
    }}}


def server():
    grandchild = None
    if PIDFILE:
        if os.environ.get("FAKE_SPAWN_GRANDCHILD") == "1":
            if os.environ.get("FAKE_GRANDCHILD_IGNORE_TERM") == "1":
                grandchild = subprocess.Popen([
                    sys.executable, "-c",
                    "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(300)",
                ])
            else:
                grandchild = subprocess.Popen(["/bin/sleep", "300"])
        with open(PIDFILE, "w") as f:
            f.write(json.dumps({"pid": os.getpid(), "pgid": os.getpgid(0),
                                "grandchild": grandchild.pid if grandchild else 0}) + "\n")
    reads = 0

    def next_sequence():
        # Read numbering: a fresh app-server process serves every observation, so the
        # sequence must survive across processes via a counter file when one is given.
        nonlocal reads
        if COUNTFILE:
            n = 0
            if os.path.exists(COUNTFILE):
                with open(COUNTFILE) as f:
                    n = int(f.read() or "0")
            with open(COUNTFILE, "w") as f:
                f.write(str(n + 1))
            return n
        seq = reads
        reads += 1
        return seq

    while True:
        line = sys.stdin.readline()
        if not line:
            break
        try:
            msg = json.loads(line)
        except Exception:
            continue
        mid = msg.get("id")
        method = msg.get("method")
        if method == "initialize":
            write_line({"id": 1, "result": {"ok": True}}, fragmented=(MODE == "fragmented"))
            if MODE == "exit-after-init":
                return
        elif method == "account/rateLimits/read":
            if MODE == "silent-after-init":
                time.sleep(300)  # never answer; the reader's total deadline must cut us off
                return
            if MODE == "unavailable":
                write_line({"id": mid, "error": {"code": -1, "message": SECRET}})
                continue
            reset = RESET_BASE + next_sequence() * RESET_STEP
            if MODE == "coalesced":
                # The initialize response is repeated unsolicited, and both JSON messages
                # leave in ONE write: the reader must drain the coalesced buffer.
                both = (json.dumps({"id": 1, "result": {"ok": True}}, separators=(",", ":")) + "\n"
                        + json.dumps({"id": mid, "result": rate_result(reset)}, separators=(",", ":")) + "\n")
                sys.stdout.buffer.write(both.encode())
                sys.stdout.buffer.flush()
            else:
                write_line({"id": mid, "result": rate_result(reset)}, fragmented=(MODE == "fragmented"))


def fire():
    record({"kind": "fire-start", "ts": time.time()})
    # Sleep is per account so a timeout test can wedged only A while B stays healthy.
    sleep_s = EXEC_SLEEP
    home = os.environ.get("CODEX_HOME", "")
    if home.endswith("b"):
        sleep_s = float(os.environ.get("FAKE_EXEC_SLEEP_B", EXEC_SLEEP))
    if sleep_s:
        time.sleep(sleep_s)
    record({"kind": "fire-end", "ts": time.time(), "exit": EXEC_EXIT})
    sys.exit(EXEC_EXIT)


if sys.argv[1:2] == ["app-server"]:
    server()
elif sys.argv[1:2] == ["exec"]:
    fire()
else:
    sys.exit(9)
PYEOF
chmod 755 "$FAKE_BIN"

FAKE_CMD="$SANDBOX/fake-cmd"
cat > "$FAKE_CMD" <<'PYEOF'
#!/usr/bin/python3
import json, os, sys, time
RECORD = os.environ.get("FAKE_RECORD", "")
EXIT = int(os.environ.get("FAKE_CMD_EXIT", "0"))
SLEEP = float(os.environ.get("FAKE_CMD_SLEEP", "0"))
if RECORD:
    with open(RECORD, "a") as f:
        f.write(json.dumps({"kind": "fire-commandcode", "ts": time.time()}) + "\n")
if SLEEP:
    time.sleep(SLEEP)
sys.exit(EXIT)
PYEOF
chmod 755 "$FAKE_CMD"

# --- Shared run helper --------------------------------------------------------------
# Runs one `all` cycle with the given overrides; leaves logs in $1/logs, records in
# $1/records.jsonl. Prints nothing; the caller inspects the artifacts.
run_all() {
    local dir="$1" step="$2" exec_exit="$3" cmd_exit="$4" mode="$5" \
          delay="$6" req_timeout="$7" exec_sleep="${8:-0}" exec_sleep_b="${9:-0}"
    mkdir -p "$dir/logs" "$dir/home-a" "$dir/home-b"
    : > "$dir/records.jsonl"
    : > "$dir/reads.count"
    env \
        MINGET_FIRE_CODEX="$FAKE_BIN" \
        MINGET_FIRE_CMD="$FAKE_CMD" \
        MINGET_FIRE_WORKDIR="$dir/work" \
        MINGET_FIRE_LOGDIR="$dir/logs" \
        MINGET_FIRE_CODEX_HOME_A="$dir/home-a" \
        MINGET_FIRE_CODEX_HOME_B="$dir/home-b" \
        MINGET_FIRE_TIMEOUT_HELPER="$HELPER" \
        MINGET_FIRE_RATE_READER="$READER" \
        MINGET_FIRE_REQUEST_TIMEOUT="$req_timeout" \
        MINGET_FIRE_INTER_TARGET_DELAY="$delay" \
        FAKE_RECORD="$dir/records.jsonl" \
        FAKE_SERVER_MODE="$mode" \
        FAKE_RESET_BASE="1700000000" \
        FAKE_RESET_STEP="$step" \
        FAKE_COUNTFILE="$dir/reads.count" \
        FAKE_EXEC_EXIT="$exec_exit" \
        FAKE_EXEC_SLEEP="$exec_sleep" \
        FAKE_EXEC_SLEEP_B="$exec_sleep_b" \
        FAKE_CMD_EXIT="$cmd_exit" \
        "$TEMPLATE_BIN" all >"$dir/stdout.txt" 2>"$dir/stderr.txt"
}

log_has() {
    local file="$1" pattern="$2"
    /usr/bin/grep -qE "$pattern" "$file"
}

# --- 1. Production defaults are still the defaults ---------------------------------
grep -q 'MINGET_FIRE_CODEX:-/opt/homebrew/bin/codex' "$TEMPLATE_BIN" \
    && PASS "default codex binary is the production path" \
    || FAIL "default codex binary changed"
grep -q 'MINGET_FIRE_CMD:-/opt/homebrew/bin/cmd' "$TEMPLATE_BIN" \
    && PASS "default cmd binary is the production path" \
    || FAIL "default cmd binary changed"
grep -q 'MINGET_FIRE_REQUEST_TIMEOUT:-120' "$TEMPLATE_BIN" \
    && PASS "default request timeout is 120 s" \
    || FAIL "default request timeout is not 120"
grep -q 'MINGET_FIRE_INTER_TARGET_DELAY:-15' "$TEMPLATE_BIN" \
    && PASS "default inter-target delay is 15 s" \
    || FAIL "default inter-target delay is not 15"
grep -q 'MINGET_FIRE_VERIFY_TIMEOUT:-8' "$TEMPLATE_BIN" \
    && PASS "default verify timeout is 8 s" \
    || FAIL "default verify timeout is not 8"
grep -q 'MINGET_FIRE_WORKDIR:-/tmp/minget-fire' "$TEMPLATE_BIN" \
    && PASS "default workdir is /tmp/minget-fire" \
    || FAIL "default workdir changed"
grep -q 'MINGET_FIRE_LOGDIR:-\$HOME/Library/Logs/Minget' "$TEMPLATE_BIN" \
    && PASS "default log dir is ~/Library/Logs/Minget" \
    || FAIL "default log dir changed"
grep -q 'sleep 2' "$TEMPLATE_BIN" && grep -q 'sleep 5' "$TEMPLATE_BIN" \
    && PASS "confirmation waits stay 2 s then 5 s" \
    || FAIL "confirmation waits changed"

# --- 2. Strict serial order with the configured delays ------------------------------
D="$SANDBOX/serial"
run_all "$D" 0 0 0 normal 2 20
assert_eq "all succeeds when every request succeeds" "0" "$?"
/usr/bin/awk -F'"' '
    /fire-start/    { print $0 }
    /fire-end/      { print $0 }
    /fire-commandcode/ { print $0 }
' "$D/records.jsonl" > "$D/order.txt"
A_START=$(grep -m1 fire-start "$D/order.txt" | /usr/bin/awk -F'"ts": ' '{print $2}' | tr -d ' ,}')
A_END=$(grep fire-end "$D/order.txt" | head -1 | /usr/bin/awk -F'"ts": ' '{print $2}' | tr -d ' ,}')
B_START=$(grep fire-start "$D/order.txt" | tail -1 | /usr/bin/awk -F'"ts": ' '{print $2}' | tr -d ' ,}')
C_TS=$(grep fire-commandcode "$D/order.txt" | /usr/bin/awk -F'"ts": ' '{print $2}' | tr -d ' ,}')
if [[ -n "$A_START" && -n "$A_END" && -n "$B_START" && -n "$C_TS" ]] \
   && /usr/bin/awk -v a="$A_START" -v b="$A_END" 'BEGIN { exit (b > a) ? 0 : 1 }' \
   && /usr/bin/awk -v a="$A_END" -v b="$B_START" -v d="1.5" 'BEGIN { exit (b - a >= d) ? 0 : 1 }' \
   && /usr/bin/awk -v a="$B_START" -v b="$C_TS" 'BEGIN { exit (b > a) ? 0 : 1 }'; then
    PASS "all runs A, then the delay, then B, then Command Code"
else
    FAIL "serial order or inter-target delay violated (A=$A_START..$A_END B=$B_START C=$C_TS)"
fi

# --- 3. Timeout (124) does not stop `all` -------------------------------------------
D="$SANDBOX/timeout"
run_all "$D" 0 0 0 normal 1 2 8 0
assert_eq "a timed-out target fails the aggregate run" "1" "$?"
log_has "$D/logs/fire-A.log" 'END target=A exit=124' \
    && PASS "account A reports exit=124 on timeout" \
    || { FAIL "account A did not report exit=124"; sed -n '1,20p' "$D/logs/fire-A.log"; }
/usr/bin/grep -q 'kind": "fire-commandcode"' "$D/records.jsonl" \
    && PASS "Command Code still runs after A times out" \
    || FAIL "Command Code was skipped after A timed out"
log_has "$D/logs/fire-B.log" 'END target=B exit=0' \
    && PASS "account B still runs and succeeds after A times out" \
    || FAIL "account B did not run cleanly after A timed out"

# --- 4. Aggregation of plain failures ------------------------------------------------
D="$SANDBOX/failure"
run_all "$D" 0 3 0 normal 1 20
assert_eq "a nonzero child exit fails the aggregate run" "1" "$?"
log_has "$D/logs/fire-A.log" 'END target=A exit=3' \
    && PASS "the child's exit status is preserved in the log" \
    || FAIL "child exit status missing from the log"
D="$SANDBOX/failure-c"
run_all "$D" 0 0 5 normal 1 20
assert_eq "a failing Command Code fails the aggregate run" "1" "$?"

# --- 5. Observation outcomes are not request failures ---------------------------------
D="$SANDBOX/unchanged"
run_all "$D" 0 0 0 normal 1 20
assert_eq "unchanged reset observation still exits 0" "0" "$?"
log_has "$D/logs/fire-A.log" 'OBSERVATION_RESET_UNCHANGED target=A' \
    && PASS "unchanged observation is logged as UNCHANGED" \
    || FAIL "unchanged observation missing from the log"
D="$SANDBOX/advanced"
run_all "$D" 120 0 0 normal 1 20
assert_eq "advanced reset observation exits 0" "0" "$?"
log_has "$D/logs/fire-A.log" 'OBSERVATION_RESET_ADVANCED target=A' \
    && PASS "advanced observation is logged as ADVANCED" \
    || FAIL "advanced observation missing from the log"
log_has "$D/logs/fire-A.log" 'window=5h' \
    && PASS "observation lines carry the window field" \
    || FAIL "window field missing"
log_has "$D/logs/fire-A.log" 'used_before=[0-9]+ used_after=[0-9]+' \
    && PASS "observation lines carry before and after used values" \
    || FAIL "used_before/used_after missing"
log_has "$D/logs/fire-A.log" 'drift=1[0-9][0-9]s' \
    && PASS "observation lines carry the measured drift" \
    || FAIL "drift missing"
D="$SANDBOX/unavailable"
run_all "$D" 0 0 0 unavailable 1 20
assert_eq "unavailable reset observation still exits 0" "0" "$?"
log_has "$D/logs/fire-A.log" 'OBSERVATION_RESET_UNAVAILABLE target=A' \
    && PASS "unavailable observation is logged as UNAVAILABLE" \
    || FAIL "unavailable observation missing from the log"

# --- 6. Sanitized logs only -----------------------------------------------------------
for log in "$SANDBOX/advanced"/logs/fire-*.log; do
    if /usr/bin/grep -vE '^$|^\[[-0-9 :]+\] (START target=[a-zA-Z]+|END target=[a-zA-Z]+ exit=[0-9]+ duration=[0-9]+s|OBSERVATION_RESET_(ADVANCED|UNCHANGED) target=[a-zA-Z]+ window=5h duration=[0-9]+s used_before=[0-9na]+ used_after=[0-9na]+ reset_before=[-0-9 :]+ reset_after=[-0-9 :]+ drift=-?[0-9]+s|OBSERVATION_RESET_UNAVAILABLE target=[a-zA-Z]+ window=5h duration=[0-9]+s used_before=[0-9na]+ used_after=[0-9na]+)$' "$log" | /usr/bin/grep -q .; then
        FAIL "log $log contains lines outside the fixed vocabulary"
    else
        PASS "log $(basename "$log") stays inside the sanitized vocabulary"
    fi
done
if /usr/bin/grep -Rq 'SECRETMARKER' "$SANDBOX" --include='*.log'; then
    FAIL "an identity marker leaked into the logs"
else
    PASS "no identity marker appears in any log"
fi

# --- 7. Reader: fragmented and coalesced JSON ------------------------------------------
read_with() {
    local mode="$1" timeout="$2"
    env MINGET_FIRE_CODEX="$FAKE_BIN" \
        FAKE_SERVER_MODE="$mode" FAKE_RESET_BASE="1700000000" \
        FAKE_RESET_STEP="0" FAKE_USED="42" \
        "$READER" "$timeout" 2>/dev/null
}

OUT=$(read_with fragmented 10)
assert_eq "fragmented JSON still yields the observation" "1700000000 42" "$OUT"
OUT=$(read_with coalesced 10)
assert_eq "coalesced JSON still yields the observation" "1700000000 42" "$OUT"

# --- 8. Reader: one total deadline ------------------------------------------------------
D="$SANDBOX/deadline"
mkdir -p "$D"
START_S=$SECONDS
OUT=$(env MINGET_FIRE_CODEX="$FAKE_BIN" FAKE_SERVER_MODE="silent-after-init" \
      FAKE_RESET_BASE="1700000000" "$READER" 2 2>/dev/null)
READER_EXIT=$?
ELAPSED=$((SECONDS - START_S))
assert_eq "a silent server yields UNAVAILABLE" "UNAVAILABLE" "$OUT"
assert_eq "the reader exits 1 without an observation" "1" "$READER_EXIT"
if (( ELAPSED < 6 )); then
    PASS "the total deadline cut the conversation off in ${ELAPSED}s (per-message timeouts would need 4+)"
else
    FAIL "the reader took ${ELAPSED}s; the total deadline is not shared across messages"
fi

# --- 9. Process-group cleanup -------------------------------------------------------------
D="$SANDBOX/cleanup"
mkdir -p "$D"
OUT=$(env MINGET_FIRE_CODEX="$FAKE_BIN" FAKE_SERVER_MODE="silent-after-init" \
      FAKE_SPAWN_GRANDCHILD="1" FAKE_PIDFILE="$D/pids.json" \
      FAKE_RESET_BASE="1700000000" "$READER" 2 2>/dev/null)
assert_eq "cleanup scenario also ends UNAVAILABLE" "UNAVAILABLE" "$OUT"
GC=$(/usr/bin/python3 -c 'import json;print(json.load(open("'"$D"'/pids.json"))["grandchild"])')
DEAD=1
for _ in {1..20}; do
    if ! kill -0 "$GC" 2>/dev/null; then DEAD=0; break; fi
    sleep 0.1
done
assert_eq "the app-server's grandchild dies with its process group" "0" "$DEAD"

D="$SANDBOX/cleanup-leader-exits"
mkdir -p "$D"
OUT=$(env MINGET_FIRE_CODEX="$FAKE_BIN" FAKE_SERVER_MODE="exit-after-init" \
      FAKE_SPAWN_GRANDCHILD="1" FAKE_GRANDCHILD_IGNORE_TERM="1" \
      FAKE_PIDFILE="$D/pids.json" "$READER" 3 2>/dev/null)
assert_eq "an app-server that exits after init still yields UNAVAILABLE" "UNAVAILABLE" "$OUT"
GC=$(/usr/bin/python3 -c 'import json;print(json.load(open("'"$D"'/pids.json"))["grandchild"])')
DEAD=1
for _ in {1..40}; do
    GC_STATE=$(ps -o stat= -p "$GC" 2>/dev/null | tr -d ' ')
    if ! kill -0 "$GC" 2>/dev/null || [[ "$GC_STATE" == Z* ]]; then DEAD=0; break; fi
    sleep 0.1
done
assert_eq "a TERM-ignoring grandchild dies after its leader exits" "0" "$DEAD"

FAKE_DAEMON="$SANDBOX/fake-daemon"
cat > "$FAKE_DAEMON" <<'PYEOF'
#!/usr/bin/python3
import os, signal, subprocess, sys, time
child = subprocess.Popen([
    sys.executable, "-c",
    "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(300)",
])
with open(os.environ["FAKE_DAEMON_PIDS"], "w") as f:
    f.write(f"{os.getpid()} {child.pid}\n")
if sys.argv[1:] == ["wait"]:
    time.sleep(300)
PYEOF
chmod 755 "$FAKE_DAEMON"
process_is_dead() {
    local pid="$1" state
    state=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -z "$state" || "$state" == Z* ]]
}

D="$SANDBOX/timeout-helper-cleanup"
mkdir -p "$D"
FAKE_DAEMON_PIDS="$D/pids-normal" "$HELPER" 10 "$FAKE_DAEMON" > /dev/null 2>&1
assert_eq "timeout helper preserves a normal child exit" "0" "$?"
PIDS=($(cat "$D/pids-normal"))
DEAD=1
for _ in {1..40}; do
    if process_is_dead "$PIDS[2]"; then DEAD=0; break; fi
    sleep 0.1
done
assert_eq "timeout helper kills stubborn descendants after the leader exits" "0" "$DEAD"

D="$SANDBOX/timeout-helper-timeout"
mkdir -p "$D"
FAKE_DAEMON_PIDS="$D/pids-timeout" "$HELPER" 1 "$FAKE_DAEMON" wait > /dev/null 2>&1
assert_eq "timeout helper maps an expired deadline to 124" "124" "$?"
PIDS=($(cat "$D/pids-timeout"))
DEAD=1
for _ in {1..40}; do
    if process_is_dead "$PIDS[1]" && process_is_dead "$PIDS[2]"; then DEAD=0; break; fi
    sleep 0.1
done
assert_eq "timeout helper reaps both leader and TERM-ignoring descendant" "0" "$DEAD"

# --- 10. Installer preflight and rollback guidance -----------------------------------
D="$SANDBOX/install-refuse"
mkdir -p "$D/home/.local/bin" "$D/home/.local/libexec/minget-fire"
cp "$TEMPLATE_BIN" "$D/home/.local/bin/minget-fire" # accepted current template
print -r -- 'unexpected local edit' > "$D/home/.local/libexec/minget-fire/read-codex-reset.py"
BEFORE_HASH=$(shasum -a 256 "$D/home/.local/libexec/minget-fire/read-codex-reset.py" | awk '{print $1}')
if HOME="$D/home" "$INSTALLER" --check > "$D/check.log" 2>&1; then
    FAIL "installer --check accepted an unrecognized installed file"
else
    PASS "installer --check refuses an unrecognized installed file"
fi
AFTER_HASH=$(shasum -a 256 "$D/home/.local/libexec/minget-fire/read-codex-reset.py" | awk '{print $1}')
assert_eq "installer preflight leaves unexpected files untouched" "$BEFORE_HASH" "$AFTER_HASH"
if [[ ! -e "$D/home/.local/libexec/minget-fire/run-with-timeout.py" ]] \
   && ! find "$D/home" -name '*.backup-*' -print -quit | grep -q .; then
    PASS "installer preflight performs no partial writes or backups"
else
    FAIL "installer wrote a later target or backup before preflight finished"
fi

D="$SANDBOX/install-empty"
mkdir -p "$D/home"
if HOME="$D/home" "$INSTALLER" > "$D/install.log" 2>&1; then
    PASS "installer installs all files into an isolated empty HOME"
else
    FAIL "installer failed in an isolated empty HOME"
fi
for pair in \
    "$TEMPLATE_BIN|$D/home/.local/bin/minget-fire" \
    "$READER|$D/home/.local/libexec/minget-fire/read-codex-reset.py" \
    "$HELPER|$D/home/.local/libexec/minget-fire/run-with-timeout.py"; do
    src="${pair%%|*}" dst="${pair#*|}"
    SRC_HASH=$(shasum -a 256 "$src" | awk '{print $1}')
    DST_HASH=$(shasum -a 256 "$dst" | awk '{print $1}')
    assert_eq "installed copy matches its checked-in template ($(basename "$dst"))" "$SRC_HASH" "$DST_HASH"
done
if grep -q '/bin/rm -f -- .*minget-fire' "$D/install.log"; then
    PASS "installer prints exact rollback commands for newly created files"
else
    FAIL "installer omitted a concrete rollback command for new files"
fi
if HOME="$D/home" "$INSTALLER" --check > "$D/rerun-check.log" 2>&1; then
    PASS "installer --check accepts already-current files without rewriting"
else
    FAIL "installer --check rejected already-current files"
fi
if ! find "$D/home" -name '*.backup-*' -print -quit | grep -q .; then
    PASS "current files are not backed up or rewritten redundantly"
else
    FAIL "the no-op check unexpectedly created backups"
fi

# --- Summary --------------------------------------------------------------------------------
if (( FAILURES == 0 )); then
    print -r -- "all scheduler template tests passed"
    exit 0
fi
print -r -- "$FAILURES scheduler template test(s) failed"
exit 1

#!/usr/bin/python3
# Minget external fire scheduler — 5-hour window reader, template v1.4.2.
#
# Rewrite of the installed ~/.local/libexec/minget-fire/read-codex-reset.py:
# - one monotonic TOTAL deadline covers the whole conversation (handshake plus
#   rate-limit read) instead of a fresh timeout per message,
# - stdout is consumed as raw bytes with os.read and buffered explicitly, so
#   fragmented JSON (one message split across reads) and coalesced JSON (several
#   messages arriving in one read) both parse,
# - the child runs in its own process group (start_new_session) and cleanup
#   escalates SIGTERM -> SIGKILL on the whole group, never just the direct child.
#
# Contract with the scheduler: `read-codex-reset.py [timeout]` prints
#   "<reset-epoch> <used-percent>"
# on success, or "UNAVAILABLE" with exit 1 on any failure. The binary comes from
# MINGET_FIRE_CODEX when set, so tests can point it at a fake CLI. Nothing from the
# child's output is ever echoed verbatim: only the two numeric fields survive.

import json
import os
import select
import signal
import subprocess
import sys
import time

CODEX = os.environ.get("MINGET_FIRE_CODEX", "/opt/homebrew/bin/codex")
READ_CHUNK = 65536


def terminate_process_group(process, grace_seconds=2.0):
    """Reap the child and any descendants in its dedicated process group."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass

    deadline = time.monotonic() + grace_seconds
    while time.monotonic() < deadline:
        process.poll()  # reap the direct child when possible
        try:
            os.killpg(process.pid, 0)
        except (ProcessLookupError, PermissionError):
            break
        time.sleep(min(0.05, max(0.0, deadline - time.monotonic())))

    # The direct child may already have exited while a grandchild ignores TERM. Always
    # escalate the dedicated group after its grace period, not only when wait() times out.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        process.wait(timeout=2)
    except Exception:
        pass


def find_five_hour_window(result):
    """Picks the 300-minute window out of an account/rateLimits/read result.

    Returns (reset_epoch, used_text) or None. Same bucket logic as the production
    helper: the `codex` entry of rateLimitsByLimitId, falling back to the legacy
    flat rateLimits object.
    """
    by_id = result.get("rateLimitsByLimitId")
    if isinstance(by_id, dict) and by_id:
        bucket = by_id.get("codex")
    else:
        legacy = result.get("rateLimits")
        if isinstance(legacy, dict) and legacy.get("limitId") in (None, "codex"):
            bucket = legacy
        else:
            bucket = None

    if not isinstance(bucket, dict):
        return None

    windows = []
    for key in ("primary", "secondary", "tertiary", "windows"):
        value = bucket.get(key)
        if isinstance(value, dict):
            windows.append(value)
        elif isinstance(value, list):
            windows.extend(item for item in value if isinstance(item, dict))

    for window in windows:
        duration = window.get("windowDurationMins")
        try:
            if float(duration) != 300:
                continue
        except (TypeError, ValueError):
            continue

        value = window.get("resetsAt")
        if isinstance(value, bool):
            continue
        try:
            reset = int(float(value))
        except (TypeError, ValueError):
            continue
        if reset <= 0:
            continue

        try:
            used_text = str(int(float(window.get("usedPercent"))))
        except (TypeError, ValueError):
            used_text = "na"
        return reset, used_text

    return None


class Unavailable(Exception):
    """Any condition that ends the conversation without an observation."""


def main():
    try:
        timeout = float(sys.argv[1]) if len(sys.argv) > 1 else 8.0
    except ValueError:
        timeout = 8.0

    # One deadline for everything: handshake and read share the same budget.
    deadline = time.monotonic() + timeout
    process = None
    buffer = b""

    try:
        process = subprocess.Popen(
            [CODEX, "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=os.environ.copy(),
            start_new_session=True,
        )
        out_fd = process.stdout.fileno()

        def send(payload):
            line = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
            process.stdin.write(line)
            process.stdin.flush()

        def receive(wanted_id):
            nonlocal buffer
            while True:
                # Coalesced messages: drain every complete line already in the buffer.
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    if not line.strip():
                        continue
                    try:
                        message = json.loads(line)
                    except Exception:
                        continue
                    if isinstance(message, dict) and message.get("id") == wanted_id:
                        return message

                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise Unavailable("total deadline elapsed")
                try:
                    ready, _, _ = select.select([out_fd], [], [], remaining)
                except (InterruptedError, OSError):
                    raise Unavailable("select failed")
                if not ready:
                    raise Unavailable("total deadline elapsed")

                # Fragmented messages: os.read returns whatever arrived; a partial
                # JSON line simply stays in the buffer until the rest shows up.
                chunk = os.read(out_fd, READ_CHUNK)
                if not chunk:
                    raise Unavailable("child closed stdout")
                buffer += chunk

        send({
            "method": "initialize",
            "id": 1,
            "params": {"clientInfo": {"name": "MingetFireVerifier", "version": "1.4.2"}},
        })

        initialized = receive(1)
        if "error" in initialized:
            raise Unavailable("initialize rejected")

        send({"method": "initialized"})
        send({"method": "account/rateLimits/read", "id": 2, "params": {}})

        response = receive(2)
        if "error" in response:
            raise Unavailable("rate limit read rejected")

        result = response.get("result")
        if not isinstance(result, dict):
            raise Unavailable("malformed result")

        window = find_five_hour_window(result)
        if window is None:
            raise Unavailable("no 5-hour window")

        reset, used = window
        print(f"{reset} {used}")
        return 0

    except Exception:
        print("UNAVAILABLE")
        return 1

    finally:
        if process is not None:
            try:
                process.stdin.close()
            except Exception:
                pass
            # The process group is ours (start_new_session): descendants are included.
            terminate_process_group(process)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/python3
# Minget external fire scheduler — bounded command runner, template v1.4.2.
#
# Identical behaviour to the installed ~/.local/libexec/minget-fire/run-with-timeout.py:
# `run-with-timeout.py <seconds> <command...>` runs the command in its own process
# group, waits at most <seconds>, then SIGTERMs the group and escalates to SIGKILL.
# Exit 124 means the timeout fired; any other exit is the child's own. Output is
# discarded here — the scheduler logs only its fixed sanitized vocabulary.
import os
import signal
import subprocess
import sys
import time


def terminate_process_group(process, grace_seconds=2.0):
    """Reap the child and all descendants in the dedicated process group."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

    deadline = time.monotonic() + grace_seconds
    while time.monotonic() < deadline:
        process.poll()
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            break
        time.sleep(min(0.05, max(0.0, deadline - time.monotonic())))

    # The leader may have exited while a descendant ignored TERM, so escalate the group
    # unconditionally once the grace period ends.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=2)
    except Exception:
        pass


def main():
    if len(sys.argv) < 3:
        return 2

    try:
        timeout = float(sys.argv[1])
    except ValueError:
        return 2

    try:
        process = subprocess.Popen(
            sys.argv[2:],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=os.environ.copy(),
            start_new_session=True,
        )
    except OSError:
        return 127

    try:
        result = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        terminate_process_group(process)
        return 124

    # A normally exiting CLI can also leave helper descendants behind. Clean only this
    # command's isolated process group and preserve its real exit status.
    terminate_process_group(process)
    return result if result >= 0 else 128 + (-result)


if __name__ == "__main__":
    sys.exit(main())

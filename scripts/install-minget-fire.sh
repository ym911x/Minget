#!/bin/zsh
# Minget 1.4.2 — explicit installer for the external fire scheduler template.
#
# Installs scripts/minget-fire/bin/minget-fire and
# scripts/minget-fire/libexec/minget-fire/{read-codex-reset,run-with-timeout}.py
# into ~/.local/bin and ~/.local/libexec/minget-fire.
#
# Safety model:
# - expected-hash checking: every template file is verified against
#   scripts/minget-fire/SHA256SUMS before anything is touched; a mismatch aborts,
# - installed-file preflight: only the recorded pre-1.4.2 files or the current template
#   may be replaced; any other existing file aborts before directories, backups, or
#   targets are written,
# - timestamped backups: legacy installed files are copied next to their targets as
#   <target>.backup-<UTC stamp>, and all backup hashes are verified before replacement,
# - atomic replacement: each file lands via a temporary file in the target
#   directory plus one rename,
# - exact rollback commands are printed at the end, including removal of newly created
#   files,
# - this script NEVER touches launchd: no plist writes, no `launchctl` load/reload,
#   no kill of a running scheduler. It also never runs from the app bundle or the
#   build directory — it only ever installs the checked-in template files.
#
# Usage:
#   scripts/install-minget-fire.sh            install (or update) the three files
#   scripts/install-minget-fire.sh --check    verify hashes and show the plan, no writes

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
TEMPLATE_DIR="$REPO_ROOT/scripts/minget-fire"
SUMS_FILE="$TEMPLATE_DIR/SHA256SUMS"

# Exact pre-1.4.2 files observed in the user's installed ~/.local tree on 2026-09-23.
# Anything else is treated as an unexpected local modification and is never overwritten.
LEGACY_HASHES=(
    "ad641a7152235a4624bb55a86b7bad2e4755acb7e68447d101c2349e46c2f203"
    "fe4ddfa0c128266bcdb480e2e7b8cecf358abb37f3dce4063165415cfc0990e7"
    "cad1b68c69bac43428731f15b1bbe1333600665fc580c2b71293634dec83ec99"
)

BIN_SRC="$TEMPLATE_DIR/bin/minget-fire"
LIBEXEC_SRC_DIR="$TEMPLATE_DIR/libexec/minget-fire"
LIBEXEC_SRCS=("$LIBEXEC_SRC_DIR/read-codex-reset.py" "$LIBEXEC_SRC_DIR/run-with-timeout.py")

BIN_TARGET="$HOME/.local/bin/minget-fire"
LIBEXEC_TARGET_DIR="$HOME/.local/libexec/minget-fire"

CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=1
fi

info()  { print -r -- "install-minget-fire: $*"; }
fail()  { print -r -- "install-minget-fire: ERROR: $*" >&2; exit 1; }

hash_of() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

[[ -f "$SUMS_FILE" ]] || fail "missing $SUMS_FILE — refusing to install unverified files"
[[ -f "$BIN_SRC" ]] || fail "missing template $BIN_SRC"
for src in "${LIBEXEC_SRCS[@]}"; do
    [[ -f "$src" ]] || fail "missing template $src"
done

# --- Step 1: verify the templates against the expected hashes -------------------
info "verifying template hashes against SHA256SUMS"
( cd "$TEMPLATE_DIR" && /usr/bin/shasum -a 256 -c SHA256SUMS ) >/dev/null \
    || fail "template hash check failed — the files do not match the recorded sums"

# --- Step 2: plan the targets ----------------------------------------------------
typeset -a SRC_PATHS TGT_PATHS MODES LABELS SRC_HASHES TO_INSTALL BACKUPS MADE TEMP_PATHS
SRC_PATHS=("$BIN_SRC" "${LIBEXEC_SRCS[@]}")
TGT_PATHS=("$BIN_TARGET" "$LIBEXEC_TARGET_DIR/read-codex-reset.py" "$LIBEXEC_TARGET_DIR/run-with-timeout.py")
MODES=("755" "700" "700")
LABELS=("minget-fire" "read-codex-reset.py" "run-with-timeout.py")

# --- Step 2: preflight every installed target before any writes ------------------
info "preflighting every installed target against the known legacy baseline"
for i in {1..3}; do
    src="$SRC_PATHS[$i]" tgt="$TGT_PATHS[$i]" label="$LABELS[$i]"
    SRC_HASHES[$i]=$(hash_of "$src")
    if [[ -e "$tgt" || -L "$tgt" ]]; then
        [[ -f "$tgt" && ! -L "$tgt" ]] \
            || fail "unexpected non-regular installed target $tgt — refusing to modify anything"
        installed_hash=$(hash_of "$tgt")
        if [[ "$installed_hash" == "$SRC_HASHES[$i]" ]]; then
            TO_INSTALL[$i]=0
            info "$tgt is already current (sha256 $installed_hash)"
        elif [[ "$installed_hash" == "$LEGACY_HASHES[$i]" ]]; then
            TO_INSTALL[$i]=1
            info "$tgt matches the recorded pre-1.4.2 baseline and may be backed up"
        else
            fail "$tgt has an unrecognized sha256 ($installed_hash); expected current template $SRC_HASHES[$i] or recorded legacy hash $LEGACY_HASHES[$i]. No files were written."
        fi
    else
        TO_INSTALL[$i]=1
        info "$tgt does not exist and may be installed"
    fi
done

if (( CHECK_ONLY )); then
    for i in {1..3}; do
        src="$SRC_PATHS[$i]" tgt="$TGT_PATHS[$i]" mode="$MODES[$i]"
        if (( TO_INSTALL[$i] )); then
            if [[ -e "$tgt" ]]; then
                info "would back up and replace $tgt (mode $mode)"
            else
                info "would install $tgt (mode $mode)"
            fi
        else
            info "$tgt needs no change"
        fi
    done
    info "check only: nothing was written"
    exit 0
fi

STAMP=$( /bin/date -u '+%Y%m%dT%H%M%SZ' )-$$
typeset -a BACKUP_PATHS

# Create directories only after the full preflight above has passed.
for i in {1..3}; do
    tgt="$TGT_PATHS[$i]"
    tgt_dir="$tgt:h"
    if (( TO_INSTALL[$i] )); then
        mkdir -p "$tgt_dir" || fail "cannot create $tgt_dir"
    fi
done

# Back up every legacy file before replacing any target.
for i in {1..3}; do
    tgt="$TGT_PATHS[$i]"
    if (( TO_INSTALL[$i] )) && [[ -e "$tgt" ]]; then
        backup="$tgt.backup-$STAMP"
        /bin/cp -p "$tgt" "$backup" || fail "cannot back up $tgt"
        original_hash=$(hash_of "$tgt")
        backup_hash=$(hash_of "$backup")
        [[ "$original_hash" == "$backup_hash" ]] \
            || fail "backup $backup does not match the original (hash mismatch); aborting before any replacement"
        BACKUPS[$i]="$backup"
        info "backed up $tgt -> $backup (sha256 $backup_hash)"
    fi
done

# Stage and verify every replacement before making any one of them live.
for i in {1..3}; do
    if (( TO_INSTALL[$i] )); then
        src="$SRC_PATHS[$i]" tgt="$TGT_PATHS[$i]" mode="$MODES[$i]"
        tmp="$tgt.tmp.$$"
        /bin/cat "$src" > "$tmp" || { /bin/rm -f "$tmp"; fail "cannot stage $tmp"; }
        /bin/chmod "$mode" "$tmp" || { /bin/rm -f "$tmp"; fail "cannot chmod $tmp"; }
        staged_hash=$(hash_of "$tmp")
        [[ "$staged_hash" == "$SRC_HASHES[$i]" ]] \
            || { /bin/rm -f "$tmp"; fail "staged $tmp does not match $src; aborting"; }
        TEMP_PATHS[$i]="$tmp"
    fi
done

for i in {1..3}; do
    if (( TO_INSTALL[$i] )); then
        src="$SRC_PATHS[$i]" tgt="$TGT_PATHS[$i]" tmp="$TEMP_PATHS[$i]"
        mode="$MODES[$i]" src_hash="$SRC_HASHES[$i]"
        # Atomic replacement uses a temporary file in the target directory.
        /bin/mv -f "$tmp" "$tgt" || { /bin/rm -f "$tmp"; fail "cannot move $tmp into place"; }
        MADE[$i]="$tgt"
        info "installed $tgt (mode $mode, sha256 $src_hash)"
    fi
done

info ""
info "Rollback commands (run only if you choose to restore the previous scripts):"
for i in {1..3}; do
    tgt="$TGT_PATHS[$i]"
    if [[ -n "${BACKUPS[$i]:-}" ]]; then
        printf -v quoted_backup '%q' "${BACKUPS[$i]}"
        printf -v quoted_target '%q' "$tgt"
        info "  /bin/mv -f -- $quoted_backup $quoted_target"
    elif [[ -n "${MADE[$i]:-}" ]]; then
        printf -v quoted_target '%q' "$tgt"
        info "  /bin/rm -f -- $quoted_target"
    fi
done

info ""
info "The existing launchd job still points to the same script path. No plist edit or launchctl reload is needed."
info "This installer never touches the plist or running scheduler."

#!/bin/bash
# Build the Minget app bundle from the UsageMonitor Swift package.
#
# Usage: scripts/build.sh [--debug]
#   default: release build, signed with the local identity "Minget Local Signing"
#   --debug: debug build (faster, used during development)
#
# Environment:
#   MINGET_SIGN_IDENTITY   code signing identity name. `-` selects ad-hoc signing, which
#                          restores the previous behaviour but makes the keychain ask for
#                          authorisation again after every code change.
#   MINGET_STAGING_DIR     where the bundle is built, signed and strictly verified.
#                          Defaults to a local directory outside the repository.
#   MINGET_RUN_PATH        the fixed path the verified bundle is installed to.
#                          Defaults to ~/Applications/Minget.app.
#
# Why the bundle is not built straight into the repository: the repository lives in iCloud
# Drive, and the file provider re-attaches `com.apple.FinderInfo` to everything it syncs. A
# strict code-signature check refuses a bundle carrying that attribute, even though the
# build never created it (KEYCHAIN_REVISION_PLAN.md §2.1 and P0.1). So the flow is:
#
#   stage and sign in a local directory
#     -> strict verification there (bundle and both nested executables)
#     -> install to the fixed run path, strict verification again
#     -> leave a review copy in dist/ (a plain verify passes there; a strict one cannot,
#        because iCloud rewrites the attributes, and that difference is recorded, not hidden)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_VERSION="$(tr -d '[:space:]' < VERSION)"

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG="debug"
fi

APP_NAME="Minget"
EXECUTABLE_NAME="UsageMonitor"
BUNDLE_ID="local.usagemonitor.UsageMonitor"
DIST="dist"

# --- signing identity -------------------------------------------------------------
# A stable certificate identity is what keeps the keychain access control list matching.
# An ad-hoc signature has no certificate, so its designated requirement degrades to the
# binary's cdhash, which changes whenever the binary content changes. After the next code
# change macOS stops matching the stored ACL and the app asks for keychain access again.
# (Rebuilding unchanged source does not change the cdhash; see
# docs/versions/1.0.2/evidence/logs/08-signing-build-path.txt.)
#
# MINGET_SIGN_IDENTITY=- falls back to ad-hoc signing. GitHub Actions runners do not carry
# the machine-local identity, so CI defaults to ad-hoc unless an explicit identity is set.
if [[ -n "${MINGET_SIGN_IDENTITY+x}" ]]; then
  SIGN_IDENTITY="$MINGET_SIGN_IDENTITY"
elif [[ "${CI:-}" == "true" ]]; then
  SIGN_IDENTITY="-"
else
  SIGN_IDENTITY="Minget Local Signing"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "== signing: ad-hoc (MINGET_SIGN_IDENTITY=-) =="
else
  # Resolved before anything is compiled or staged, so a missing identity cannot leave a
  # freshly staged but unsigned bundle behind, and cannot waste a full compile.
  #
  # `find-identity` is deliberately called without -v. An untrusted self-signed certificate
  # is omitted from the "valid identities only" list even though codesign accepts it, so -v
  # would report a working identity as missing.
  if ! security find-identity -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
    echo "error: signing identity '$SIGN_IDENTITY' not found in the keychain" >&2
    echo "       create it once:  scripts/make-signing-identity.sh" >&2
    echo "       or build ad-hoc: MINGET_SIGN_IDENTITY=- scripts/build.sh" >&2
    exit 1
  fi
  echo "== signing identity: $SIGN_IDENTITY =="
fi

# --- staging and run paths --------------------------------------------------------
STAGING_DIR="${MINGET_STAGING_DIR:-${TMPDIR:-/tmp}/minget-staging/Minget.app}"
RUN_PATH="${MINGET_RUN_PATH:-$HOME/Applications/Minget.app}"
ARCHIVE_PATH="$DIST/$APP_NAME.app"
STAGING_CONTENTS="$STAGING_DIR/Contents"

echo "== swift build ($CONFIG) =="
# `--disable-sandbox` concerns SwiftPM's manifest sandbox only: on this machine, wrapping an
# already-sandboxed process makes the inner `sandbox-exec` fail with EPERM, and the manifest
# of this first-party project is reviewed source like everything else.
swift build --package-path . -c "$CONFIG" --disable-sandbox

BIN_DIR="$(swift build --package-path . -c "$CONFIG" --show-bin-path --disable-sandbox)"
EXEC_APP="$BIN_DIR/UsageMonitorApp"
EXEC_CLI="$BIN_DIR/UsageMonitorCLI"
[[ -x "$EXEC_APP" ]] || { echo "missing $EXEC_APP" >&2; exit 1; }
[[ -x "$EXEC_CLI" ]] || { echo "missing $EXEC_CLI" >&2; exit 1; }

# Removes one bundle and fails closed when the removal is refused. Without the check, a
# refused `rm -rf` (for example an environment that blocks bulk deletion) is silent: staging
# would then copy into the leftover bundle and the script would still report `built:`,
# producing a mixed bundle that is neither the previous build nor the new one. This was hit
# for real on 2026-09-11 (evidence/logs/10-staging-fail-closed.txt).
remove_bundle() {
  local path="$1"
  rm -rf "$path"
  if [[ -e "$path" ]]; then
    echo "error: could not remove $path" >&2
    echo "       remove it manually, then run this script again" >&2
    exit 1
  fi
}

echo "== staging $STAGING_DIR =="
remove_bundle "$STAGING_DIR"
mkdir -p "$STAGING_CONTENTS/MacOS" "$STAGING_CONTENTS/Resources"

cp "$EXEC_APP" "$STAGING_CONTENTS/MacOS/$EXECUTABLE_NAME"
cp "$EXEC_CLI" "$STAGING_CONTENTS/MacOS/${APP_NAME}CLI"   # QA smoke diagnostic, same production service
cp "assets/brand/Minget.icns" "$STAGING_CONTENTS/Resources/Minget.icns"
cp "assets/brand/OAI_OpenAI-Blossom_Black.png" "$STAGING_CONTENTS/Resources/OAI_OpenAI-Blossom_Black.png"
cp "assets/brand/OAI_OpenAI-Blossom_White.png" "$STAGING_CONTENTS/Resources/OAI_OpenAI-Blossom_White.png"
cp "assets/brand/OAI_OpenAI-Blossom_Black.svg" "$STAGING_CONTENTS/Resources/OAI_OpenAI-Blossom_Black.svg"
cp "assets/brand/OAI_OpenAI-Blossom_White.svg" "$STAGING_CONTENTS/Resources/OAI_OpenAI-Blossom_White.svg"
cp "assets/brand/deepseek-whale-black.png" "$STAGING_CONTENTS/Resources/deepseek-whale-black.png"
cp "assets/brand/deepseek-wordmark-black.png" "$STAGING_CONTENTS/Resources/deepseek-wordmark-black.png"
cp "assets/brand/deepseek-wordmark-transparent.png" "$STAGING_CONTENTS/Resources/deepseek-wordmark-transparent.png"
cp "assets/brand/deepseek-wordmark-text-transparent.png" "$STAGING_CONTENTS/Resources/deepseek-wordmark-text-transparent.png"

cat > "$STAGING_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>明明有数 · Minget</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>Minget</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableUsageDescription</key>
    <string>Reads Codex account usage via the local codex app-server. No credentials are read, stored or transmitted.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$STAGING_CONTENTS/PkgInfo"

cat > "$STAGING_CONTENTS/Resources/README.txt" <<'TXT'
明明有数 · Minget
你的 AI 使用，心里有数。
Your AI usage, at a glance.

Runs a single `codex app-server` child process for the app's lifetime and reads
account rate limits over stdio JSON-RPC. Only normalized usage numbers are cached.

Contents/MacOS/MingetCLI is the QA smoke diagnostic:
  Minget.app/Contents/MacOS/MingetCLI
It prints normalized usage and child lifecycle events only.
TXT

echo "== codesign ($SIGN_IDENTITY) =="
# Fail closed: a bundle that cannot be signed or verified must not be reported as built.
xattr -cr "$STAGING_DIR"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  if ! codesign --force --sign - "$STAGING_DIR"; then
    echo "error: ad-hoc codesign failed" >&2
    exit 1
  fi
else
  # --timestamp=none: a self-signed certificate has no timestamp authority, so asking for a
  # timestamp would only add a failing network round trip.
  if ! codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$STAGING_DIR"; then
    echo "error: codesign with '$SIGN_IDENTITY' failed" >&2
    echo "       if it keeps asking for the private key password, run once:" >&2
    echo "       security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <login password> \"\$HOME/Library/Keychains/login.keychain-db\"" >&2
    exit 1
  fi
fi

echo "== strict verification in staging =="
# Strict is the check that refuses foreign attributes; the plain one accepts a bundle whose
# contents were touched after signing, which is exactly what the file provider does here.
codesign --verify --strict --verbose=2 "$STAGING_DIR" || {
  echo "error: strict verification failed in staging" >&2
  exit 1
}
# Both nested executables are signed objects of their own and are verified explicitly, so a
# broken helper can never hide behind a healthy bundle.
for inner in "$STAGING_CONTENTS/MacOS/$EXECUTABLE_NAME" "$STAGING_CONTENTS/MacOS/${APP_NAME}CLI"; do
  codesign --verify --strict "$inner" || {
    echo "error: strict verification failed for $inner" >&2
    exit 1
  }
done
plutil -lint "$STAGING_CONTENTS/Info.plist" || exit 1

echo "== install to $RUN_PATH =="
mkdir -p "$(dirname "$RUN_PATH")"
remove_bundle "$RUN_PATH"
# `ditto` preserves the bundle layout; the attributes are cleared after the copy because the
# destination may be freshly written, and they are cleared before the verification that must
# pass.
ditto "$STAGING_DIR" "$RUN_PATH"
xattr -cr "$RUN_PATH"
codesign --verify --strict --verbose=2 "$RUN_PATH" || {
  echo "error: strict verification failed at the run path" >&2
  exit 1
}

echo "== archive copy to $ARCHIVE_PATH =="
remove_bundle "$ARCHIVE_PATH"
ditto "$STAGING_DIR" "$ARCHIVE_PATH"
# The archive lives inside iCloud Drive, so a strict check may fail there for attributes the
# build never created. The plain verify is what is recorded for this copy, and the strict
# result is printed too rather than skipped, so the difference stays visible.
codesign --verify --verbose=1 "$ARCHIVE_PATH" || exit 1
if ! codesign --verify --strict "$ARCHIVE_PATH" 2>/dev/null; then
  echo "note: strict verification of $ARCHIVE_PATH fails on file-provider attributes;"
  echo "      the verified run candidate is $RUN_PATH"
fi

echo "built:   $RUN_PATH"
echo "archive: $ARCHIVE_PATH"

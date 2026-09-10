#!/bin/bash
# Build the Minget app bundle from the UsageMonitor Swift package.
#
# Usage: scripts/build.sh [--debug]
#   default: release build
#   --debug: debug build (faster, used during development)
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
CONTENTS="$DIST/$APP_NAME.app/Contents"

echo "== swift build ($CONFIG) =="
swift build --package-path . -c "$CONFIG"

BIN_DIR="$(swift build --package-path . -c "$CONFIG" --show-bin-path)"
EXEC_APP="$BIN_DIR/UsageMonitorApp"
EXEC_CLI="$BIN_DIR/UsageMonitorCLI"
[[ -x "$EXEC_APP" ]] || { echo "missing $EXEC_APP" >&2; exit 1; }
[[ -x "$EXEC_CLI" ]] || { echo "missing $EXEC_CLI" >&2; exit 1; }

echo "== staging $DIST/$APP_NAME.app =="
rm -rf "$DIST/$APP_NAME.app"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$EXEC_APP" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
cp "$EXEC_CLI" "$CONTENTS/MacOS/${APP_NAME}CLI"   # QA smoke diagnostic, same production service
cp "assets/brand/Minget.icns" "$CONTENTS/Resources/Minget.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
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

printf 'APPL????' > "$CONTENTS/PkgInfo"

cat > "$CONTENTS/Resources/README.txt" <<'TXT'
明明有数 · Minget
你的 AI 使用，心里有数。
Your AI usage, at a glance.

Runs a single `codex app-server` child process for the app's lifetime and reads
account rate limits over stdio JSON-RPC. Only normalized usage numbers are cached.

Contents/MacOS/MingetCLI is the QA smoke diagnostic:
  Minget.app/Contents/MacOS/MingetCLI
It prints normalized usage and child lifecycle events only.
TXT

echo "== codesign (ad-hoc) =="
# Fail closed: a bundle that cannot be signed or verified must not be reported as built.
xattr -cr "$DIST/$APP_NAME.app"
if ! codesign --force --sign - "$DIST/$APP_NAME.app"; then
  echo "error: ad-hoc codesign failed" >&2
  exit 1
fi

echo "== verify =="
codesign --verify --verbose=1 "$DIST/$APP_NAME.app" || exit 1
plutil -lint "$CONTENTS/Info.plist" || exit 1
echo "built: $DIST/$APP_NAME.app"

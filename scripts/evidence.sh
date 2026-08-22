#!/usr/bin/env bash
# Boots the simulator, installs Listnr, captures one screenshot per tab as
# PR evidence into artifacts/.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEST_ID=$(xcrun simctl list devices | grep "iPhone 17 Pro (" | head -1 | grep -oE '[A-F0-9-]{36}')
xcrun simctl boot "$DEST_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEST_ID" -b

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Listnr-*/Build/Products/Debug-iphonesimulator/Listnr.app | head -1)
xcrun simctl install "$DEST_ID" "$APP"
mkdir -p artifacts

shot_tab() {
    local tab="$1" file="$2" wait="${3:-3}"
    xcrun simctl terminate "$DEST_ID" com.luisKisters.Listnr 2>/dev/null || true
    xcrun simctl launch "$DEST_ID" com.luisKisters.Listnr -uitest -tab "$tab" >/dev/null
    sleep "$wait"
    xcrun simctl io "$DEST_ID" screenshot "artifacts/$file" >/dev/null
    echo "[evidence] $file"
}

shot_tab library 01-library.png
shot_tab audiobook 02-player.png
shot_tab reader 03-reader-construction.png
shot_tab scan 04-scan-construction.png
echo "[evidence] done: $(ls artifacts)"

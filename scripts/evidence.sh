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

# newest build first — several worktrees share the DerivedData folder
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Listnr-*/Build/Products/Debug-iphonesimulator/Listnr.app | head -1)
xcrun simctl install "$DEST_ID" "$APP"
mkdir -p artifacts

# shot <file> <tab> [extra launch args...]
shot() {
    local file="$1" tab="$2"; shift 2
    xcrun simctl terminate "$DEST_ID" com.luisKisters.Listnr 2>/dev/null || true
    xcrun simctl launch "$DEST_ID" com.luisKisters.Listnr -uitest -tab "$tab" "$@" >/dev/null
    sleep 3
    xcrun simctl io "$DEST_ID" screenshot "artifacts/$file" >/dev/null
    echo "[evidence] $file"
}

shot 01-library.png library
shot 02-player.png audiobook
shot 03-reader-construction.png reader
shot 04-scan-construction.png scan
# the sheets: -sheet opens them on launch (AppModel.init)
shot 05-import-sheet.png library -sheet import
shot 06-note-sheet.png audiobook -sheet note
echo "[evidence] done: $(ls artifacts)"

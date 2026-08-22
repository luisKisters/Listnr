#!/usr/bin/env bash
# One entry point for the native Xcode test suites.
#   scripts/test.sh dev    fast unit suite on the simulator
#   scripts/test.sh full   unit + UI golden paths on the simulator
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

MODE="${1:-dev}"
DEST='platform=iOS Simulator,name=iPhone 17 Pro'
start=$(date +%s)

case "$MODE" in
  dev)
    xcodebuild test -project Listnr.xcodeproj -scheme Listnr \
      -destination "$DEST" -only-testing:ListnrTests ;;
  full)
    xcodebuild test -project Listnr.xcodeproj -scheme Listnr \
      -destination "$DEST" ;;
  *)
    echo "Usage: scripts/test.sh [dev|full]"; exit 2 ;;
esac
result=$?
end=$(date +%s)
echo "[test] $MODE took $((end - start))s"
exit $result

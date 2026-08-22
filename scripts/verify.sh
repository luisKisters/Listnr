#!/usr/bin/env bash
# Pre-push verification gate for Listnr.
# Usage: scripts/verify.sh            (grep gates + swiftlint + build + unit tests)
#        scripts/verify.sh --no-tests (gates + swiftlint only)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

FAILURES=0
log()  { echo "[verify] $*"; }
pass() { echo "[verify] PASS: $*"; }
fail() { echo "[verify] FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# ---------------------------------------------------------------------------
# Grep gates. A gate trips when grep finds a match in app sources.
# ---------------------------------------------------------------------------
gate() {
    local desc="$1"; shift
    local matches
    matches=$(grep -rn "$@" App/Sources 2>/dev/null | grep -v "// gate-ok" || true)
    if [[ -n "$matches" ]]; then
        local count
        count=$(echo "$matches" | wc -l | tr -d ' ')
        fail "$desc ($count occurrence(s)):"
        echo "$matches" | head -8 | sed 's/^/         /'
    else
        pass "$desc"
    fi
}

log "grep gates"
gate "no emoji in app code"          -P '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' --include='*.swift'
gate "no print() outside engine log" --include='*.swift' -e 'print(' \
    || true
gate "no try! in app code"           --include='*.swift' -e 'try!'
gate "no fatalError in app code"     --include='*.swift' -e 'fatalError'
gate "no TODO/FIXME without owner"   --include='*.swift' -E 'TODO|FIXME'

# Buttons and interactive controls need accessibility labels (dead-control rule).
missing_a11y=$(python3 - <<'PY'
import re, sys, pathlib
bad = []
for p in pathlib.Path("App/Sources").rglob("*.swift"):
    src = p.read_text()
    for m in re.finditer(r"Button\s*(?:\(|\s*\{)", src):
        # find the enclosing view body chunk up to the next top-level brace
        start = m.start()
        chunk = src[start:start+1500]
        if "accessibilityLabel" not in chunk and "// gate-ok" not in chunk:
            line = src[:start].count("\n") + 1
            bad.append(f"{p}:{line}")
if bad:
    print("\n".join(bad))
PY
)
if [[ -n "$missing_a11y" ]]; then
    fail "buttons without nearby accessibilityLabel:"
    echo "$missing_a11y" | head -8 | sed 's/^/         /'
else
    pass "buttons carry accessibility labels"
fi

# ---------------------------------------------------------------------------
# SwiftLint
# ---------------------------------------------------------------------------
if command -v swiftlint >/dev/null; then
    if swiftlint --quiet --reporter emoji | grep -qE '[1-9][0-9]*'; then
        fail "swiftlint reported violations"
        swiftlint --quiet | head -10 | sed 's/^/         /'
    else
        pass "swiftlint clean"
    fi
else
    fail "swiftlint not installed (brew install swiftlint)"
fi

[[ "${1:-}" == "--no-tests" ]] && {
    [[ $FAILURES -eq 0 ]] && log "ALL GATES GREEN" || log "$FAILURES failure(s)"
    exit $((FAILURES > 0))
}

# ---------------------------------------------------------------------------
# Build + fast unit suite
# ---------------------------------------------------------------------------
log "building"
if xcodebuild build -project Listnr.xcodeproj -scheme Listnr \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet > /tmp/listnr-build.log 2>&1; then
    pass "build"
else
    fail "build — see /tmp/listnr-build.log"
    tail -5 /tmp/listnr-build.log | sed 's/^/         /'
    exit 1
fi

log "unit tests"
result=0
xcodebuild test -project Listnr.xcodeproj -scheme Listnr \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:ListnrTests > /tmp/listnr-unit.log 2>&1 || result=$?
if [[ $result -eq 0 ]]; then
    pass "unit suite"
else
    fail "unit suite — see /tmp/listnr-unit.log"
    grep -E "Test Case.*failed" /tmp/listnr-unit.log | head -6 | sed 's/^/         /'
fi

[[ $FAILURES -eq 0 ]] && log "ALL GATES GREEN" || log "$FAILURES failure(s)"
exit $((FAILURES > 0))

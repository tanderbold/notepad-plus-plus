#!/bin/bash
# Build if needed, then run the built-in suite. Exit code is the result.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/macos/build/NotepadMac.app/Contents/MacOS/NotepadMac"
[ -x "$APP" ] || bash "$ROOT/macos/build.sh"
LOG="$ROOT/macos/build/last-test-run.txt"
set +e
NPPMAC_TEST=1 "$APP" 2>/dev/null | tee "$LOG"
status=${PIPESTATUS[0]}
set -e
# Keep the output; an occasional failure is otherwise impossible to diagnose.
if [ "$status" -ne 0 ]; then
    echo
    echo "suite failed (exit $status); full output kept at $LOG"
fi
exit "$status" 

#!/bin/bash
# Build if needed, then run the built-in suite. Exit code is the result.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/macos/build/NotepadMac.app/Contents/MacOS/NotepadMac"
[ -x "$APP" ] || bash "$ROOT/macos/build.sh"
NPPMAC_TEST=1 "$APP" 2>/dev/null

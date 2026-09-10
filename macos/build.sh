#!/bin/bash
# Build the portable foundation of Notepad++ on macOS:
#   Lexilla (all lexers incl. Notepad++'s UDL) + Scintilla core + Scintilla/Cocoa,
# then link the proof-of-concept editor into a signed .app bundle.
#
# Requires only Xcode Command Line Tools (no full Xcode, no Qt).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCI="$ROOT/scintilla"
LEX="$ROOT/lexilla"
OUT="$ROOT/macos/build"
CXXFLAGS=(-std=c++17 -DNDEBUG -DSCI_LEXER -O2 -fPIC -Wno-deprecated-declarations)
INCLUDES=(-I"$SCI/include" -I"$SCI/src" -I"$SCI/cocoa" -I"$LEX/include")

mkdir -p "$OUT/obj"

echo "==> Lexilla"
make -C "$LEX/src" -j"$(sysctl -n hw.ncpu)"

echo "==> Scintilla core"
for f in "$SCI"/src/*.cxx; do
    clang++ "${CXXFLAGS[@]}" "${INCLUDES[@]}" -c "$f" -o "$OUT/obj/$(basename "${f%.cxx}").o"
done

echo "==> Scintilla Cocoa layer"
for f in PlatCocoa ScintillaCocoa ScintillaView InfoBar; do
    clang++ "${CXXFLAGS[@]}" "${INCLUDES[@]}" -fobjc-arc -c "$SCI/cocoa/$f.mm" -o "$OUT/obj/$f.o"
done

echo "==> libscintilla-cocoa.a"
libtool -static -o "$OUT/libscintilla-cocoa.a" "$OUT"/obj/*.o 2>/dev/null

echo "==> proof-of-concept editor"
clang++ -std=c++17 -fobjc-arc -O2 "${INCLUDES[@]}" \
    "$ROOT/macos/proof/main.mm" \
    "$OUT/libscintilla-cocoa.a" "$LEX/bin/liblexilla.a" \
    -framework Cocoa -framework QuartzCore \
    -o "$OUT/NotepadMac"

echo "==> NotepadMac.app"
APP="$OUT/NotepadMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/NotepadMac" "$APP/Contents/MacOS/NotepadMac"
cp "$ROOT/macos/proof/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo
echo "Built: $APP"
echo "Run:   open $APP"
echo "Test:  NPPMAC_SELFTEST=1 $APP/Contents/MacOS/NotepadMac"

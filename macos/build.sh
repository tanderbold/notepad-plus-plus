#!/bin/bash
# Build NotepadMac.app on macOS: Lexilla + Scintilla core + Scintilla/Cocoa,
# then the editor itself, bundled with Notepad++'s own language and style data.
#
# Requires only Xcode Command Line Tools (no full Xcode, no Qt).
#
#   ./macos/build.sh              universal (arm64 + x86_64)
#   NPPMAC_ARCH=native ./macos/build.sh   host architecture only, ~2x faster
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCI="$ROOT/scintilla"
LEX="$ROOT/lexilla"
SRC="$ROOT/macos/app"
OUT="$ROOT/macos/build"

if [ "${NPPMAC_ARCH:-universal}" = "native" ]; then
    ARCHS=()
else
    ARCHS=(-arch arm64 -arch x86_64)
fi

CXXFLAGS=(-std=c++17 -DNDEBUG -DSCI_LEXER -O2 -fPIC -Wno-deprecated-declarations ${ARCHS[@]+"${ARCHS[@]}"})
INCLUDES=(-I"$SCI/include" -I"$SCI/src" -I"$SCI/cocoa" -I"$LEX/include" -I"$SRC")

mkdir -p "$OUT/obj"

echo "==> Lexilla"
make -C "$LEX/src" -j"$(sysctl -n hw.ncpu)" >/dev/null

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

echo "==> NotepadMac"
APPOBJ="$OUT/appobj"
mkdir -p "$APPOBJ"
for f in LanguageCatalog StyleCatalog FunctionListCatalog WorkspacePanel DocumentListPanel FunctionListPanel AuxPanels EditorController EditCommands SearchCommands ViewCommands EncodingCommands AdvancedEditCommands ToolsCommands SettingsCommands SettingsPanels Toolbar BackupAndPrint BehaviourCommands TypingCommands AppDelegate Tests main; do
    clang++ "${CXXFLAGS[@]}" "${INCLUDES[@]}" -fobjc-arc -c "$SRC/$f.mm" -o "$APPOBJ/$f.o"
done
clang++ -std=c++17 -fobjc-arc -O2 ${ARCHS[@]+"${ARCHS[@]}"} "$APPOBJ"/*.o \
    "$OUT/libscintilla-cocoa.a" "$LEX/bin/liblexilla.a" \
    -framework Cocoa -framework QuartzCore \
    -o "$OUT/NotepadMac"

echo "==> NotepadMac.app"
APP="$OUT/NotepadMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/NotepadMac" "$APP/Contents/MacOS/NotepadMac"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
# Notepad++'s own language and colour definitions, read at runtime.
cp "$ROOT/PowerEditor/src/langs.model.xml"   "$APP/Contents/Resources/"
cp "$ROOT/PowerEditor/src/stylers.model.xml" "$APP/Contents/Resources/"
# read back by the coverage meta-test in the built-in suite
cp "$ROOT/macos/implemented.txt"            "$APP/Contents/Resources/"
# Notepad++'s own colour themes; the Style Configurator and Preferences list these.
mkdir -p "$APP/Contents/Resources/themes"
cp "$ROOT"/PowerEditor/installer/themes/*.xml "$APP/Contents/Resources/themes/"
# Notepad++'s own function-list parsers, read by the Function List panel.
mkdir -p "$APP/Contents/Resources/functionList"
cp "$ROOT"/PowerEditor/installer/functionList/*.xml "$APP/Contents/Resources/functionList/"
codesign --force --deep --sign - "$APP" 2>/dev/null

echo
echo "Built: $APP"
echo "Run:   open $APP"
echo "Test:  NPPMAC_TEST=1 $APP/Contents/MacOS/NotepadMac"

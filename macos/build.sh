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
INCLUDES=(-I"$SCI/include" -I"$SCI/src" -I"$SCI/cocoa" -I"$LEX/include" -I"$SRC"
          -I"$(xcrun --show-sdk-path)/usr/include/libxml2")

mkdir -p "$OUT/obj"

echo "==> Lexilla"
make -C "$LEX/src" -j"$(sysctl -n hw.ncpu)" >/dev/null

echo "==> Scintilla core"
for f in "$SCI"/src/*.cxx; do
    o="$OUT/obj/$(basename "${f%.cxx}").o"
    # Scintilla does not change from one build of the editor to the next.
    [ "$o" -nt "$f" ] && [ "$o" -nt "$0" ] && continue
    clang++ "${CXXFLAGS[@]}" "${INCLUDES[@]}" -c "$f" -o "$o"
done

echo "==> Scintilla Cocoa layer"
for f in PlatCocoa ScintillaCocoa ScintillaView InfoBar; do
    o="$OUT/obj/$f.o"
    [ "$o" -nt "$SCI/cocoa/$f.mm" ] && [ "$o" -nt "$0" ] && continue
    clang++ "${CXXFLAGS[@]}" "${INCLUDES[@]}" -fobjc-arc -c "$SCI/cocoa/$f.mm" -o "$o"
done

echo "==> libscintilla-cocoa.a"
libtool -static -o "$OUT/libscintilla-cocoa.a" "$OUT"/obj/*.o 2>/dev/null

echo "==> NotepadMac"
APPOBJ="$OUT/appobj"
mkdir -p "$APPOBJ"
for f in NppPanel NppRegex ApiCatalog LanguageCatalog LanguageModel LanguageDetection StyleCatalog FunctionListCatalog TabBarView FtpClient WorkspacePanel DocumentListPanel FunctionListPanel AuxPanels EditorController EditCommands SearchCommands FindCommands ViewCommands EncodingCommands AdvancedEditCommands ToolsCommands SettingsCommands SettingsPanels Toolbar BackupAndPrint BehaviourCommands TypingCommands CompareCommands JsonCommands FtpCommands XmlCommands RunCommands AppDelegate Tests main; do
    clang++ "${CXXFLAGS[@]}" "${INCLUDES[@]}" -fobjc-arc -c "$SRC/$f.mm" -o "$APPOBJ/$f.o"
done
clang++ -std=c++17 -fobjc-arc -O2 ${ARCHS[@]+"${ARCHS[@]}"} "$APPOBJ"/*.o \
    "$OUT/libscintilla-cocoa.a" "$LEX/bin/liblexilla.a" \
    -framework Cocoa -framework QuartzCore -framework Security -lcurl -lxml2 -lz \
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
cp "$ROOT/macos/resources/encoding-reference.txt" "$APP/Contents/Resources/"
# The trained language model, fitted offline by macos/train-language-model.py.
cp "$ROOT/macos/resources/language-model.bin"    "$APP/Contents/Resources/"
# The FTP tests need a server to talk to; this one exists only for them.
cp "$ROOT/macos/test-ftp-server.py"         "$APP/Contents/Resources/"
# Notepad++'s own colour themes; the Style Configurator and Preferences list these.
mkdir -p "$APP/Contents/Resources/themes"
cp "$ROOT"/PowerEditor/installer/themes/*.xml "$APP/Contents/Resources/themes/"
# Notepad++'s own function-list parsers, read by the Function List panel.
mkdir -p "$APP/Contents/Resources/toolbar/light" "$APP/Contents/Resources/toolbar/dark"
cp "$ROOT"/macos/resources/toolbar/order.txt        "$APP/Contents/Resources/toolbar/"
cp "$ROOT"/macos/resources/toolbar/light/*.png      "$APP/Contents/Resources/toolbar/light/"
cp "$ROOT"/macos/resources/toolbar/dark/*.png       "$APP/Contents/Resources/toolbar/dark/"

mkdir -p "$APP/Contents/Resources/APIs"
cp "$ROOT"/PowerEditor/installer/APIs/*.xml "$APP/Contents/Resources/APIs/"

mkdir -p "$APP/Contents/Resources/functionList"
cp "$ROOT"/PowerEditor/installer/functionList/*.xml "$APP/Contents/Resources/functionList/"

mkdir -p "$APP/Contents/Resources/urlCorpus"
cp "$ROOT"/macos/resources/url-corpus/* "$APP/Contents/Resources/urlCorpus/"

mkdir -p "$APP/Contents/Resources/functionListCorpus"
cp -R "$ROOT"/macos/resources/functionList-corpus/* "$APP/Contents/Resources/functionListCorpus/"

mkdir -p "$APP/Contents/Resources/functionListCorrections"
cp "$ROOT"/macos/resources/functionList-corrections/*.xml "$APP/Contents/Resources/functionListCorrections/"
codesign --force --deep --sign - "$APP" 2>/dev/null

echo
echo "Built: $APP"
echo "Run:   open $APP"
echo "Test:  NPPMAC_TEST=1 $APP/Contents/MacOS/NotepadMac"

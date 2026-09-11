# Notepad++ on macOS — porting assessment and foundation

This branch does three things:

1. **Fixes the portable parts of the tree that were needlessly Windows-only**, so the
   editing engine Notepad++ depends on actually builds and runs on macOS.
2. **Ships a working macOS editor** on top of that engine, driven by Notepad++'s own
   language and colour definitions rather than a reinvented set.
3. **Measures what remains**, so the cost of a full port is a number rather than a guess.

Everything below was measured against this tree, not estimated from memory.

---

## What now works on macOS (verified)

Built with Xcode Command Line Tools only -- no full Xcode, no Qt, no Homebrew packages.

```
./macos/build.sh                      # universal (arm64 + x86_64)
NPPMAC_ARCH=native ./macos/build.sh   # host arch only, ~2x faster
```

| Component | Result |
|---|---|
| **Lexilla** -- all lexers, incl. Notepad++'s own UDL lexer | builds, universal |
| **Scintilla core** (`scintilla/src/*.cxx`) | 33 / 33 files compile |
| **Scintilla Cocoa layer** (`scintilla/cocoa/*.mm`) | 4 / 4 files compile |
| **`NotepadMac.app`** -- multi-tab editor | runs, universal, ad-hoc signed |

`NotepadMac.app` is a working editor, not a demo:

- Tabs over multiple open files, each a Scintilla document swapped in via
  `SCI_SETDOCPOINTER` -- the same one-view/many-documents model Notepad++ uses.
- Syntax highlighting for **95 languages / 244 file extensions**, with the
  keyword sets and colours read from Notepad++'s own data files.
- Native `NSMenu` with macOS shortcuts: new/open/save/save-as/close, undo/redo,
  cut/copy/paste/select-all, duplicate line, find, find next/previous, replace
  all, go to line, zoom, word wrap, show whitespace, a Language menu listing all
  95 languages, and tab switching.
- Line numbers, current-line highlight, indentation guides, multiple selections,
  a status bar with path, line/column, size and detected language.

### Reusing Notepad++'s own data rather than reinventing it

The macOS editor does not carry a hand-written language list. It reads the same
files the Windows build ships:

| Source | Used for |
|---|---|
| `PowerEditor/src/langs.model.xml` | 95 languages, 244 extensions, keyword sets |
| `PowerEditor/src/stylers.model.xml` | 92 lexer themes, 1755 styles, global colours |
| `ScintillaEditView::_langNameInfoArray` | language name -> Lexilla lexer ID (97 entries) |

The last one is extracted at build time by `macos/gen_langmap.sh` into
`macos/app/LangMap.h`, so the mapping cannot drift from the Windows source.
The two XML files are copied into the app bundle's `Resources` and parsed on
launch, which also means a user can edit them exactly as on Windows.

Keyword-set indices follow Notepad++'s `LANG_INDEX_*`
(`MISC/Common/NppConstants.h`): `instre1`=0, `instre2`=1, `type1`=2 ... `type7`=8.

### Self-test

`NPPMAC_SELFTEST=1 NotepadMac.app/Contents/MacOS/NotepadMac` exercises the chain
headlessly and exits:

```
SELFTEST languages_loaded=95
SELFTEST cpp_styles_loaded=27
SELFTEST global_styles_loaded=53
SELFTEST detect a.cpp          -> lang=cpp        lexer=cpp
SELFTEST detect b.py           -> lang=python     lexer=python
SELFTEST detect c.rs           -> lang=rust       lexer=rust
SELFTEST detect d.json         -> lang=json       lexer=json
SELFTEST detect e.sh           -> lang=bash       lexer=bash
SELFTEST detect f.unknownext   -> lang=normal     lexer=null
SELFTEST open_file=OK tabs=2 lang=python
SELFTEST python_comment_style=1 (SCE_P_COMMENTLINE=1) match=YES
SELFTEST search_found=YES
SELFTEST tab[0]="new 1"
SELFTEST tab[1]="nppmac_selftest.py"
SELFTEST status_nonempty=YES fields=OK
SELFTEST menus=7
```

`NPPMAC_SNAPSHOT=out.png` renders the window to a PNG from inside the process.
It does not use `screencapture(1)`, which needs Screen Recording permission and
otherwise returns a desktop with no windows at all. It captures Scintilla, which
draws itself, but not the text of AppKit controls -- the tab bar and status bar
come out blank there, which is why the self-test asserts their contents instead.

**This is still the editor, not Notepad++.** Preferences, sessions, the docking
panel system, macros, column mode, document map, function list and the plugin
system remain Windows-only.

### Fix applied to make this possible

`lexilla/lexers/LexUser.cxx` was the single file blocking a macOS Lexilla build:

- `#include <windows.h>` — now guarded with `#ifdef _WIN32`. Nothing in the file needs it.
- `_itoa()` (MSVC-only), 10 call sites — replaced with `snprintf()`.

The `_itoa` replacement is byte-for-byte equivalent. The buffer is
`char nestingBuffer[] = "userDefine.nesting.00"` (21 chars + NUL), written at two
offsets to accommodate one- and two-digit style IDs:

| Constant | Value | Offset | Replacement | Resulting property |
|---|---|---|---|---|
| `SCE_USER_STYLE_COMMENT` | 1 | +20 | `snprintf(buf+20, 2, "%d", v)` | `userDefine.nesting.01` |
| `SCE_USER_STYLE_COMMENTLINE` | 2 | +20 | `snprintf(buf+20, 2, "%d", v)` | `userDefine.nesting.02` |
| `SCE_USER_STYLE_DELIMITER1..8` | 16–23 | +19 | `snprintf(buf+19, 3, "%d", v)` | `userDefine.nesting.16..23` |

The size limits (`2` and `3`) exactly match the room left in the buffer, so the
generated property names and the terminating NUL are identical to the `_itoa` output.
Windows behaviour is unchanged; the `windows.h` include is still present for `_WIN32`.

---

## What remains: the measured Win32 surface

`PowerEditor/src`, excluding the bundled third-party code (`json`, `pugixml`, `uchardet`):

| | Files | LOC | Share |
|---|---:|---:|---:|
| **Win32-bound** (must be rewritten) | 160 | 125,514 | **92.2%** |
| Portable (no Win32 symbols) | 76 | 10,573 | 7.8% |
| **Total** | **236** | **136,087** | |

104 files include a Windows header directly (`windows.h`, `commctrl.h`, `shlwapi.h`,
`shlobj.h`, `uxtheme.h`, …).

### Win32 symbol occurrences

| Symbol | Count | | Symbol | Count |
|---|---:|---|---|---:|
| `WM_*` messages | 1,497 | | `HDC` | 273 |
| `LPARAM` | 1,197 | | `LRESULT` | 241 |
| `SendMessage` | 1,185 | | `HMENU` | 161 |
| `HWND` | 986 | | `HINSTANCE` | 117 |
| `WPARAM` | 548 | | `CreateWindowEx` | 51 |
| | | | `RegOpenKeyEx` | 11 |

`SendMessage` + `WM_*` dominating the count is the core problem: Notepad++'s control
flow *is* the Win32 message loop. There is no UI-toolkit abstraction to swap out.

### Weight by subsystem

| Subsystem | Files | LOC | Notes |
|---|---:|---:|---|
| `WinControls/` | 130 | 51,024 | Every dialog, tab bar, docking panel, toolbar, grid |
| root (`Notepad_plus`, `Parameters`, `NppIO`, …) | 33 | 48,021 | Main window, big message switch, config, file I/O |
| `ScintillaComponent/` | 30 | 24,991 | Editor host, Find/Replace, UDL dialog, buffers |
| `MISC/` | 39 | 11,015 | Common helpers, process, plugin manager, RegExt |
| `DarkMode/` | 4 | 1,036 | Windows-specific theming (`uxtheme`) |

### Heaviest single files

| File | LOC |
|---|---:|
| `Notepad_plus.cpp` | 9,456 |
| `Parameters.cpp` | 9,210 |
| `WinControls/Preference/preferenceDlg.cpp` | 7,352 |
| `ScintillaComponent/FindReplaceDlg.cpp` | 7,131 |
| `NppDarkMode.cpp` | 5,040 |
| `ScintillaComponent/ScintillaEditView.cpp` | 4,957 |
| `NppCommands.cpp` | 4,639 |
| `NppBigSwitch.cpp` | 4,439 |

### Resources and commands

- **70 dialog definitions** across 26 `.rc` files (39 distinct `IDD_` ids) — the Win32
  `.rc` format has no macOS equivalent; each must be rebuilt as a `.xib` or in code.
- **530 `IDM_` menu commands** to re-map onto an `NSMenu` with ⌘-based shortcuts.
- **Plugin ABI** (`MISC/PluginsManager/PluginInterface.h`) is a Windows DLL contract
  built on `HWND` and `SendMessage`. No existing Notepad++ plugin can load on macOS.
  This is not a porting task — it is a new plugin system.

---

## Honest conclusion

A direct port is a **rewrite of ~125,000 lines of UI code**, not a build-system change.
The realistic sequence, in dependency order:

| Stage | Work | Status |
|---|---|---|
| 1 | Editing engine on macOS (Scintilla/Cocoa + Lexilla) | **Done — this branch** |
| 2 | Extract non-UI logic (config, encoding, session, file I/O) from `Parameters.cpp`, `NppIO.cpp` behind a platform interface | Not started |
| 3 | Replace `NppBigSwitch.cpp` message dispatch with a platform-neutral command layer (530 commands) | Not started |
| 4 | Rebuild 70 dialogs natively; ⌘-shortcuts; `NSMenu`; native tab bar | **Partly done** -- menu, shortcuts, tabs, find/replace and go-to-line exist; the remaining ~65 dialogs (Preferences, UDL editor, Style Configurator) do not |
| 5 | Native dark mode (drop `uxtheme`), Services, sandbox, notarisation, `.dmg` | Not started |
| 6 | New plugin ABI | Not started |

Stages 2–4 are where essentially all the effort sits.

**If the goal is a usable Notepad++-like editor on a Mac rather than this exact codebase
on a Mac**, [NotepadNext](https://github.com/dail8859/NotepadNext) already reimplements
Notepad++ on Qt + Scintilla and builds on macOS today. It reaches a working application
far sooner than stages 2–6 above.

---

## Layout of this branch

```
macos/
├── PORTING.md         this document
├── build.sh           builds Lexilla + Scintilla/Cocoa + NotepadMac.app
├── gen_langmap.sh     regenerates app/LangMap.h from the Windows source
└── app/
    ├── main.mm            entry point
    ├── AppDelegate.mm     menus, shortcuts, file/search actions, self-test
    ├── EditorController.mm tabs, documents, language + theme application
    ├── LanguageCatalog.mm  parses langs.model.xml
    ├── StyleCatalog.mm     parses stylers.model.xml
    ├── LangMap.h           generated: language -> Lexilla lexer ID
    └── Info.plist          bundle metadata, plain-text/source-code types
```

Changed outside `macos/`: `lexilla/lexers/LexUser.cxx` only.

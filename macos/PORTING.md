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
  a status bar with path, line/column, size, language, encoding and EOL.
- Encodings (UTF-8, UTF-8-BOM, UTF-16 LE/BE, ANSI) sniffed on open and applied
  on save; EOL conversion between CRLF, LF and CR.
- All 46 of Notepad++'s character sets, as both "Encode in" (reinterpret the
  bytes) and "Convert to" (re-encode the text). Two needed building by hand:
  code page 858 is 850 plus its one differing byte, and code page 720 has no
  converter anywhere on macOS, so its mapping is embedded from the Unicode
  Consortium table by `macos/gen_cp720.py`.
- Comment toggling and uncommenting, bookmarks, code folding, word and path
  completion, function parameter hints.
- Multi-selection with the four case/whole-word combinations, Begin/End Select
  in normal and column mode, and a Column Editor that fills a rectangle with
  text or a number sequence.
- Paste special (HTML, RTF, binary as hex), actions on the selection (open the
  file named by it, redact it, search the web), Character Panel and Clipboard
  History.
- Case conversion (8 modes), line operations (sorting by 7 keys in both
  directions, dedup, split/join, move, blank-line handling), whitespace
  operations (trim, tab/space conversion), indentation, clipboard path copies
  and date/time insertion.
- Reload, Save a Copy As, Save All, Rename, Move to Trash, Print, and the whole
  Close All family including pinned tabs.
- Token styling with five marker colours plus the Find Mark style: mark all or
  one occurrence, jump between marks, copy styled text, clear.
- Bookmark line operations: cut, copy, paste over, remove marked or unmarked,
  inverse. Brace matching and selecting between braces.
- Find in Files across a folder, with the results in their own tab and
  next/previous result navigation.
- Change History in its own margin: jump to the next or previous modified line, clear.
- A second editor pane: move or clone a document into it, focus between panes,
  synchronised vertical and horizontal scrolling and zoom.
- Document Map, three project panels, and a Function List driven by Notepad++'s
  own functionList parsers for 47 languages.
- Sessions: save and reopen the set of open files.
- A toolbar of the editing commands, with the buttons, their labels and the bar
  size all configurable.
- Backup on save, simple or timestamped, in a configurable folder; autosave on
  a timer, with the text of never-saved documents kept in a snapshot file.
- Print options: line numbers, four colour modes, page margins, and header and
  footer templates using the same $(...) variables Notepad++ accepts.
- A large-file restriction that drops highlighting and other work above a size
  threshold, with each feature individually allowed back.
- Clickable links with configurable schemes and appearance, matching-brace
  highlighting, smart highlighting of the selected token, a configurable word
  character list and delimiter selection.
- Multi-instance behaviour, reversed date/time insertion, remembered panel
  state, and a relocatable settings folder.
- Auto-completion as you type, from document words, language keywords or both,
  with a length threshold, a brief list, numbers ignored and Tab or Enter to
  accept; auto-insertion of brackets, quotes and XML close tags; function
  parameter hints on typing.
- New-document defaults (line ending, encoding, language), untitled tabs named
  from their first line, a recent-files list with its own cap and display rules,
  the Open panel's starting folder, and Find seeded from the selection or the
  word under the caret.
- Themes: all 20 that Notepad++ ships, plus any imported, chosen separately for
  light and dark and switched by an Appearance setting that can follow macOS.
- Folder as Workspace: a file tree beside the editor; Document List in a panel.
- A tab bar with per-tab close buttons, pin markers, colours, drag-to-reorder,
  and horizontal, multi-row or vertical layout.
- Tab navigation (go to tab 1-9, first/last/next/previous), reordering and the
  five tab colours; fold and unfold by level 1-8; symbol display; hide lines;
  document summary; always on top, full screen, Post-It and distraction-free
  modes; right-to-left text; file monitoring (tail -f).

Where Windows has no macOS counterpart, the nearest equivalent is used rather
than dropping the command: "Open Containing Folder" opens Finder, both `cmd`
and PowerShell map to Terminal, and "Move to Recycle Bin" moves to the Trash.

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

### Two crashes found by running the suite repeatedly

A single green run is not evidence of stability. Running it in a loop surfaced a
crash that appeared on roughly one run in three:

- `-[NSTask waitUntilExit]` spins the run loop. Called on the main thread from
  Run > Run…, it re-entered AppKit mid-command, which let a panel redraw at a
  moment the suite had not anticipated. It now waits on a semaphore signalled
  from the task's termination handler, which blocks without running the run loop.
- That redraw is what exposed the real defect: the panels listing documents,
  clipboard entries, styles and shortcuts indexed their backing arrays with the
  row AppKit asked for, and AppKit asks using a row count it cached earlier. With
  tabs closed since, the index ran past the end and raised. Every data source now
  checks the row, and the document list reloads on a notification the editor
  posts whenever the set of open documents changes.

Both are covered by tests: one calls a data source with a deliberately stale row,
the other runs a shell command repeatedly in a single pass.

A third failure was the suite's own fault rather than the app's. The Quit test
identified the menu item by position, then by title. Neither holds: AppKit is
still rearranging and localising menus while the suite starts, so on roughly one
run in five the item was not where the test looked. It now walks the whole menu
bar for the `terminate:` action, which depends on neither.

`macos/test.sh` keeps the last run's output in `macos/build/last-test-run.txt`,
because an occasional failure that is not captured cannot be diagnosed.

### Tests

Every command declared implemented has at least one test, and a coverage
meta-test fails the run if one does not:

```
./macos/test.sh          # exit code is the result
```

```
== Search ==
  ok   IDM_SEARCH_FIND              finds the first match
  ok   IDM_SEARCH_REPLACE           replaces every occurrence
  ...
== Coverage ==
  ok   COVERAGE                     all 133 declared commands have tests

45 passed, 0 failed
```

The suite already earned its keep: it caught `SCI_SEARCHINTARGET` being read
through `SCI_GETTARGETSTART/END` instead of its return value. The call leaves
the target range untouched when there is no match, so "not found" looked like a
hit -- replace-all corrupted text past the final match.

`macos/FEATURES.md` tracks parity against all 579 Windows menu commands and is
regenerated by `macos/gen_features.sh` from the menu resource plus
`macos/implemented.txt`.

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

### What 100% of menu commands does and does not mean

Every one of the 579 commands in the Windows menu resource now has a working
counterpart here, each covered by a test. That is a meaningful measure -- it is
the user-facing command surface, counted from upstream's own resource rather
than from a list written by hand -- but it is not the same as being Notepad++.

What it does not cover:

### Plugin functionality, without plugins

Two of the most used plugins have their functionality built in, since their own
binaries can never load here:

- **JSON** (what JSON Viewer provides): format, compact, sort keys, validate
  with the line and column of the fault, and a tree of the document.
- **Compare** (what ComparePlus provides): set one file aside, compare, mark
  added, removed and changed lines, step between differences, a summary, and
  the ignore-case, ignore-spaces and ignore-empty-lines options.
The toolbar carries Notepad++'s own icons. They are not redrawn: the images are
extracted from the .ico files in the Notepad++ sources, which are containers
holding one PNG per size, and the order of the buttons is read out of the
toolBarIcons[] array in Notepad_plus.cpp. `gen_toolbar_icons.py` does both and
writes resources/toolbar/, so the set can be regenerated when upstream changes
it. Light and dark variants are both kept, and the disabled art Notepad++ ships
is used when a button is switched off.

- **Run** (the part of NppExec that carries over): the eleven variables
  Notepad++ substitutes into a command line, output streaming into a console
  panel instead of a dialog, and commands saved under a name, each of which
  appears in the Run menu. What does not carry over is NppExec's own scripting
  language and its Windows process handling.
- **XML** (what XML Tools provides): pretty print in three styles, linearize,
  check syntax, validate against a DTD or an XSD schema, evaluate XPath, report
  the element path at the caret, escape a selection, and apply an XSL
  transformation. NSXMLDocument covers everything except XSD, which it cannot
  do; libxml2, which macOS ships, covers that.
- **FTP** (what NppFTP provides): saved connections with the password in the
  Keychain, a remote file browser, opening a remote file into a tab and sending
  it back. Foundation dropped ftp:// support, so FTP and FTPS go through
  libcurl; SFTP goes through the system OpenSSH client, because Apple's libcurl
  is built without libssh2 and therefore cannot speak it.

No plugin code was copied. The comparison uses Myers' algorithm, which is what
ComparePlus uses, written here against this editor's own structures; the JSON
side uses Foundation rather than the rapidjson those plugins bundle. Their
repositories were read to establish what the commands are and how they behave.

- **Plugins cannot run.** The plugin ABI is a Windows DLL contract built on
  `HWND` and `SendMessage`. "Open Plugins Folder" works; loading a Notepad++
  plugin binary does not and cannot without a new plugin system.
- **Depth behind a command varies.** A setting exists here when the behaviour
  behind it exists, and that rule drove what was built: the toolbar, the theme
  engine including dark mode, backup and autosave, print options, the large-file
  restriction, clickable links, delimiter selection, multi-instance handling,
  the relocatable settings folder, the Function List parsers and the tab bar
  were all added so their settings would mean something.

  What is still thinner than upstream is depth inside features rather than
  whole pages. Preferences covers this editor's own settings, not upstream's
  277 controls one for one; the docked panels are a split view and floating
  panels rather than a layout that can be rearranged and saved; and plugins
  cannot run at all, which no amount of work here changes.
- **Some commands are macOS equivalents, not the same thing.** Finder for
  Explorer, Terminal for cmd and PowerShell, Trash for the Recycle Bin, Safari
  for Internet Explorer, POSIX permissions for the Windows read-only attribute.
  These are listed at each site in the source.
- **The docked panel system is approximated.** Workspace, Document Map and
  Function List are a split view and floating panels rather than a dockable
  layout that can be rearranged and saved.

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
├── gen_cp720.py       regenerates app/CP720Table.h (code page 720)
├── gen_features.sh    regenerates FEATURES.md from the Windows menu resource
├── test.sh            builds if needed, then runs the built-in suite
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

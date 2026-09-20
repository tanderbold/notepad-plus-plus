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
- Backup on save, simple or timestamped, in a configurable folder; a periodic
  backup of every modified document's unsaved text to the backup folder,
  never to the file itself, listed in the session and restored from it after
  a crash or a quit - untitled documents included.
- Files changed or removed by another program are noticed when the
  application comes to the front, with reload and keep prompts; files that
  cannot be written open read-only; the character set of a file that is not
  UTF-8 is found by uchardet, compiled in from Notepad++'s own copy.
- The command-line switches Notepad++ takes (-n -c -p -l -ro -nosession
  -openSession -r -openFoldersAsWorkspace -monitor -alwaysOnTop -notabbar
  -titleAdd= -settingsDir= -qt= -qf= -notepadStyleCmdline -z).
- User Defined Languages from userDefineLang.xml and userDefineLangs/,
  driven into the user lexer exactly as Windows drives it.
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
The Function List reads Notepad++'s own functionList definitions and runs their
patterns as what they are: PCRE. macOS ships libpcre2, which is loaded at run
time, so subroutine calls like `(?&VALID_ID)`, named groups written
`(?'NAME'...)`, atomic groups and `\K` all work as written. NSRegularExpression
is ICU and has no equivalent for the first two; fifteen of the parsers, C's among
them, were unusable on it. There is no pcre2.h in the SDK, so the handful of
entry points are declared by hand and the option values are checked against the
library's own behaviour by a test rather than trusted from memory.

Clickable-link detection is the state machine from Notepad_plus.cpp, not a
regular expression: scan to a supported scheme that is not preceded by a word
character, walk the host, path, query and fragment by their own rules, then drop
the trailing punctuation a sentence leaves behind -- a closing bracket only counts
when an opening one inside the URL answers it. Notepad++'s own corpus for this is
bundled and all 148 of its cases are checked.

Every panel is an `NppPanel`, which does what a dialog on this platform is
expected to do and what AppKit gives only to sheets and alerts: Escape puts it
away, and it opens where the user last left it or, failing that, in the middle of
the screen. A window made with a content rectangle at the origin opens in the
bottom left corner, which is where all of them were appearing.

Preferences are laid out as Notepad++ lays them out: the categories down the
left, one page at a time on the right, under its own names for them -- General,
Toolbar, Editing 1 and 2, Dark Mode, Margins/Border/Edge, and the rest. A test
checks the categories are there and that every setting that reaches Scintilla has
a control to set it from.

Notepad++'s own settings model -- `ScintillaViewParams` and `NppGUI` in
Parameters.h -- is the other list worth comparing against, and it found what the
Scintilla-message comparison could not: auto-indent, Cut and Copy taking the
whole line when nothing is selected, the current line's highlight mode, the fold
and bookmark margins, the wrap method, the padding around the text, and Mark
All's own case and whole-word settings.

Which Scintilla messages Notepad++ sends and which this port sends can be
compared directly, and doing so is a good way to find a setting that was never
carried over. It turned up five: the typing mode (INS/OVR, which Notepad++ shows
in the status bar), the vertical edge in all three of its forms, the caret's
width and blink rate, scrolling past the last line, and virtual space. Most of
what remains in that difference is Scintilla's own key commands, which the Cocoa
port binds itself, and Windows rendering settings that have no counterpart.

`macos/test-upstream.sh` runs the suites that come with the projects this port is
built on -- Lexilla's lexers against its 208 example files, Lexilla's and
Scintilla's unit tests -- and validates the function-list files this port adds
against Notepad++'s own schema in `PowerEditor/Test/xmlValidator`.

Notepad++ ships its own test corpus for the Function List in
`PowerEditor/Test/FunctionList`: forty languages, each with a file and the result
it should produce. It is bundled and run as a test, and it is what settled
several questions that guesswork had got wrong. Thirty-six of the thirty-nine it covers match exactly;
the three that do not (perl, inno, sql) differ by one entry each.

Five things about the definition files are easy to get wrong: the several
`nameExpr` entries are applied one after another, each narrowing what the last
one found, rather than being alternatives; an empty match is no use as a name, so
narrowing takes the first non-empty one (ini's pattern matches nothing at all
before it reaches the word); `classRange` matches only as far as the opening
brace, and the body has to be found by counting `openSymbole` and `closeSymbole`;
the patterns are matched **without regard to case** -- upstream searches without
SCFIND_MATCHCASE, which is why they opt back in with `(?-i:...)` where they mean
it, and why hollywood.xml writes `function` for a language that spells it
`Function`; and the patterns must keep the newlines they were written with, because XML would
otherwise fold them into spaces and the `#` comments in a `(?x)` pattern would
then swallow everything after the first one.

Matching runs over UTF-8 bytes, which is what PCRE2 works in and what Scintilla
stores, so no offset is ever translated.

A few of upstream's parsers do not find declarations they plainly should, and
`macos/resources/functionList-corrections/` replaces those. The files are in the
same format and are loaded after the originals, so one of them replaces the
parser with the same id; each says at its top what it changes and what the
original did. There are four: Rust, whose list of modifiers before `fn` has no
`pub` and which has no `impl` ranges; TypeScript, which finds only a bare
`function` and so misses methods, return-type annotations and arrow functions;
JavaScript, which misses arrow functions bound to a name; and C#, which reads a
return type as a bare word with an optional `[\w,\s<>]+` generic list, leaving
no room for `Task<string?>`, `byte[]?` or a tuple. A language whose
upstream parser is right has no file there.

"Sort Lines As Integers" is a natural sort, not a reading of each line as a
number: Notepad++ walks both lines in chunks and compares runs of digits
numerically, so `item2` comes before `item10`. The decimal sorts are the other
kind -- they read each line as a number, set aside a line that holds no number at
all, and refuse the whole sort, naming the line, when one cannot be read.

The Find dialog carries the tabs Notepad++ gives it -- Find, Replace, Find in
Files, Find in Projects, Mark -- with the fields each one needs and the search
modes and options shared beneath them. Find in Files takes patterns such as
`*.cpp *.h`, searches sub-folders and hidden folders by choice, and can replace
across the files it matched.

Find and Replace carry Notepad++'s three search modes -- the text as typed,
Extended with its `\n`, `\xHH` and the rest, and regular expressions -- together
with match case, whole word, wrap, direction and in-selection, and replacement
that understands `\1` and `$1`. All three modes are compiled to one PCRE
pattern, so there is a single path through the engine. Before this, Find looked
for a literal string and had no options at all.

Single-byte code pages are decoded from generated tables rather than from the
system converters. macOS has converters for nearly all of them, but they do not
always agree with Windows, and Notepad++ is Windows: its Icelandic (DOS) table is
another code page's outright, sixty-seven bytes of a hundred and twenty-eight
wrong; its Arabic (Windows-1256) one leaves out eight letters; and a dozen more
differ in one or two bytes. `gen_encoding_reference.py` takes the mappings from
Python's codecs, which do agree with Windows, and writes both the tables the
editor uses and a reference the tests check every one of those 5,103 bytes
against.

Auto-completion and call tips use the function lists Notepad++ ships in
`PowerEditor/installer/APIs` -- thirty-four files, one per language, carrying the
names to complete and, for a function, its return value, parameters and
description. Before, completion offered the lexer's keywords and a call tip was
built by scanning the open file for lines that mentioned the word, which is not
the same thing at all. A language with no file shipped still completes from its
keywords.

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
  plugin binary does not and cannot without a new plugin system. NppExec-style
  scripts are built in instead; see "Plugins: what was decided".
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

### Tools: hashes, Base encodings and passwords

Upstream's Tools menu is four digests. Here they sit under **Tools > Hashes**
with what the port adds, the ids and shortcuts of upstream's twelve commands
kept (`ShortcutMapper` finds them one level further down):

- **Digests**: MD5, SHA-1, SHA-256, SHA-512 as upstream, and SHA-224, SHA-384,
  SHA3-256, SHA3-512, BLAKE2b and CRC-32. Each has upstream's three commands.
  The window is upstream's dialog - the digest follows the text as it is typed,
  "Treat each line as a separate string", Copy to Clipboard - with one addition,
  an optional HMAC key for the digests HMAC is defined over. From files writes
  `digest  name` lines, as `shasum` does.
- **Password hashes**: bcrypt (cost, `$2a$`/`$2b$`/`$2y$`), scrypt (N, r, p),
  Argon2 (id, i, d; memory, iterations, parallelism) and PBKDF2 (SHA-1, -256,
  -512; iterations). Each has the digests' three commands and the digests'
  window - the text, each line on its own if wanted, the result, or files
  chosen and a line for each - with its own settings above it. The salt is
  given in hexadecimal or, left empty, made anew for every hash; the result
  is the string one stores, or the bare key in hexadecimal. **Verify** reads
  any such string back and says whether the text matches it. "Into clipboard"
  uses the kind's default settings. The work is done off the main thread, and
  only the last thing asked for is shown. Settings that would need gigabytes
  are refused in words; past 72 bytes bcrypt says that it reads no further.
- **Tools > Base**: Base64, Base58 and Base32, a window each that offers no
  other encoding; Base64's has a box for the URL alphabet, Base58's one for
  Base58Check. Encoding takes a text or bytes written in hexadecimal
  (`48656c`, `48 65 6C`, `0x48, 0x65`, `48:65`); decoding gives the text and
  the bytes in hexadecimal, or the bytes alone when they are not UTF-8. The
  window opens with the editor's selection.
- **Tools > Password Generator**: length, how many, upper and lower case, digits, a
  list of symbols one can edit, look-alikes left out, at least one of each
  kind. Characters are drawn with `SecRandomCopyBytes` and rejection sampling,
  so none is likelier than another; the entropy is shown; the settings are
  remembered; Insert into Document puts the result at the caret. A hash of
  each password can be had beside it - any of the four password hashes with
  its default settings, or any digest - which is what one stores where the
  password is to be checked.

Where the code comes from: CommonCrypto for the SHA-2 family, HMAC and PBKDF2;
zlib for CRC-32; Argon2 and BLAKE2b are the reference implementation
(`macos/third_party/argon2`, CC0, built without threads); bcrypt, scrypt,
SHA-3, Base58 and Base32 are written here (`app/CryptoTools.mm`), Blowfish's
tables being generated from pi by `gen_blowfish_tables.py` rather than copied.
All of it is held against published vectors in the suite: RFC 7914 for scrypt,
the reference implementations' own output for bcrypt and Argon2, RFC 4648,
Bitcoin's address example for Base58Check. The windows are laid out by
constraints, so their texts fit in every language by construction, and the
suite checks that they do.

### Plugins: what was decided

Notepad++'s plugins are Windows DLLs. A plugin exports `setInfo`,
`getFuncsArray`, `beNotified` and `messageProc`, receives the `HWND`s of the
main window and both Scintilla views, and then drives the editor with
`SendMessage`: 118 `NPPM_*` messages to Notepad++, the whole `SCI_*` set to
Scintilla, and 33 `NPPN_*` notifications back. Most plugins also create Win32
dialogs and docked windows of their own. None of that can load on macOS, and a
recompiled plugin would still be Win32 code from its first `CreateWindow`.
Three ways forward were weighed:

1. **Nothing more**: the built-in stand-ins (JSON, Compare, XML Tools, FTP,
   Run, the Function List) are the end state.
2. **A plugin API of this port's own**: Objective-C bundles loaded from the
   plugins folder, given a subset of the `NPPM_*` messages as methods (current
   file, buffer text, open/save/switch, menu commands, the Scintilla views
   themselves) and the `NPPN_*` notifications as a delegate. Plugins would have
   to be written for it; none of the existing ones would work unchanged.
3. **Scripts as NppExec runs them**: a language users already write, stored
   in the same `npes_saved.txt`, reaching the editor through NppExec's own
   commands and everything else through the shell.

**Decision: (3) is built, (2) is deferred.** Scripts cover what most people use
plugins for on a daily basis -- build, run, lint, transform the selection, open
the result -- with nothing to install, and existing NppExec scripts carry over.
A bundle API is a commitment to keep an interface stable for authors who do not
exist yet; it is worth doing only when someone wants to write a plugin a script
cannot express (a panel of its own, a lexer, per-keystroke behaviour).

What (3) is, in `ScriptCommands.mm`:

- Plugins > NppExec: Execute NppExec Script… (F6) with NppExec's dialog
  (a saved script or a temporary one, Save…, Delete), Execute Previous
  (Ctrl+F6), the console, and every saved script as a menu entry.
- NppExec's commands: `ECHO`, `CLS`, `CD`, `SET` (and `SET x ~ expression`
  for arithmetic), `UNSET`, `ENV_SET`/`ENV_UNSET`, `LABEL`/`:label`, `GOTO`,
  `IF … GOTO`, `IF`/`ELSE IF`/`ELSE`/`ENDIF`, `EXIT`, `SLEEP`, `INPUTBOX`,
  `NPP_OPEN` (with masks), `NPP_SWITCH`, `NPP_SAVE`, `NPP_SAVEAS`,
  `NPP_SAVEALL`, `NPP_CLOSE`, `NPP_RUN`, `NPP_EXEC` with arguments,
  `NPP_MENUCOMMAND` (by menu path), `NPP_CONSOLE`, `SEL_SETTEXT[+]` and
  `SCI_SENDMSG` with numeric messages. Anything else is a program run in the
  script's folder, its output in the console and in `$(OUTPUT)`, `$(OUTPUT1)`,
  `$(OUTPUTL)`, its status in `$(EXITCODE)`.
- Variables: the script's own, `$(ARGV)`, `$(ARGV[n])`, `$(ARGC)`,
  `$(INPUT)`, `$(SYS.NAME)` for the environment, `$(#n)` for the open files,
  `$(SELECTED_TEXT)`, `$(CLIPBOARD_TEXT)`, `$(PLUGINS_CONFIG_DIR)`, and every
  Run-menu variable. Values spliced into a shell line are quoted for the
  shell, as the Run dialog does.
- A script runs off the main thread and comes back to it for the editor, so
  the console fills while it runs; an endless loop is stopped after a step
  limit instead of hanging the editor.

Not carried over: `NPP_SENDMSG` and the other Windows-message commands
(reported as unavailable, and the script goes on), the console's own input
line for interactive programs, and NppExec's highlight filters.

### Working out a language from its contents

Notepad++ has nothing of the kind; it is offered here as a setting, and only
consulted when the name says nothing: a file with no extension, or a fragment
pasted into an empty document. The answer is a set - one language, a list of
up to ten to choose from, or nothing when more than ten would fit - and it
comes from two places only:

1. **What the text says outright**: a shebang line, `<?php`, `<?xml`, an HTML
   doctype, an editor modeline, JSON that parses. Taken as given; this is
   reading a declaration, not guessing.
2. **A trained model**, `macos/resources/language-model.bin`, read by
   `app/LanguageModel.mm`, for everything else. Ninety-one independent
   yes-or-no judgements, one per language, so that a text two languages could
   have written scores well for both and both are offered.

There is nothing else. An earlier layer of hand-written marks (`End Sub`,
`\documentclass`, a regular expression for a C# type declaration) and the
keyword-list rules under it are gone: each was a patch over something the
model had not seen, and the cure for that is to show it. What it gets wrong
is put right in its training data or its features, and nowhere else.

**What it learns from** (`macos/train-language-model.py`): the Linguist
samples; Rosetta Code; Lexilla's lexer examples; the function-list corpus;
this repository's own files; examples written for the languages nothing else
has (`macos/resources/language-samples`); generated Intel HEX, S-record and
Tektronix hex images; and **real projects** (`macos/fetch-language-corpus.py`,
about 3 GB, not in the repository): shallow clones of some ninety well-known
repositories - the classes, enums, handlers and configuration people actually
paste, which Rosetta's puzzles are not - and, for the languages no well-known
project is written in (INI, registry files, KiXtart, AutoIt, COBOL...), files
found by extension through GitHub's code search, two from a repository at
most, so that no one author is the language. Files are labelled by extension
as Notepad++ would open them; `Makefile` and `CMakeLists.txt` by name; `.tex`
as LaTeX or plain TeX by what its first lines say. No project gives more than
120 files to a language. It was the lack of this that made a plain C# enum
unrecognisable: C# had been ten real files and 150 puzzles.

**Features** are byte n-grams (2, 3, 4), whole words, the first word and the
first and last character of each line, and **pairs of neighbouring words**
(`public enum`, `end sub`, `def __init__`), every one a 64-bit key the
application computes the same way; the trainer reads its own file back and
the two answer identically. It trains on pieces of three to forty lines as
well as whole files, because pieces are what it is asked about. The scale at
which scores become likelihoods, the level a language has to reach, and the
second level above which one language is applied on its own (below it the
best three are offered instead) are fitted on held-back files, for the rule
itself: as many right answers as possible with as few lists as possible. All
three are in the model file (format 5), so a retrain moves them without a
code change. Held-back files are split from the training ones by project
folder and, for Rosetta Code, by task, so two versions of one program never
sit on both sides.

Measured on files the model never saw (the half of the held-back files not
used to fit the rule; about 3,200 of each kind, two thirds of them from the
real projects, which are harder than what was measured before them):

| Text | Right first | Right in what is offered | One language | One and right | A list | Nothing |
|---|---|---|---|---|---|---|
| whole file | 92.3% | 94.6% | 80% | 98% | 17% | 3% |
| 40 lines | 90.9% | 93.5% | 76% | 97% | 21% | 3% |
| 20 lines | 89.4% | 92.5% | 72% | 97% | 25% | 3% |
| 10 lines | 86.7% | 91.2% | 64% | 96% | 33% | 3% |
| 5 lines | 81.8% | 88.8% | 50% | 95% | 47% | 3% |
| quoting another language | 61.3% | 71.7% | 57% | 70% | 35% | 8% |

By source, whole files: real projects 90.7% first, Linguist 86.8%, the
repository's own files 96.2%, Rosetta Code 97.4%. What is misread is mostly
family or emptiness: plain TeX and sparse XML as plain text, C++ as C and C as
C++, INI as properties, ASP as HTML.

The last row is the known weakness, measured so that it can be held to: a
piece of one language with a block of another set into it - a script that
writes out a unit file, a program with a query in it. A bag of features
cannot tell the quotation from the text around it, and when the quotation is
most of the lines it wins: a PowerShell script that is one line of PowerShell
and nine of a systemd unit is read as INI. Training on such pieces was tried
and moved the first choice from 61% to 63% while turning many sure answers
into lists, so it is not done; the hand-written mark that used to rescue that
script is not coming back either.

```
python3 macos/fetch-language-corpus.py <repos>        # needs git, and gh logged in for the search
python3 macos/train-language-model.py --linguist <github-linguist> --rosetta <RosettaCodeData> --repos <repos> --report
python3 macos/train-language-model.py --model macos/resources/language-model.bin --try file...
```

Training takes about four minutes and needs numpy. The corpora are not in
this repository: Linguist is github.com/github-linguist/linguist, Rosetta
Code is github.com/acmeism/RosettaCodeData.

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
| 6 | New plugin ABI | Decided against for now: NppExec-style scripts are built in; a bundle API waits for a plugin a script cannot express |

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
├── train-language-model.py  fits resources/language-model.bin
├── fetch-language-corpus.py fetches real-world code for it to learn from
├── gen_blowfish_tables.py   regenerates app/BlowfishTables.h (bcrypt) from pi
├── third_party/argon2       Argon2's reference implementation (CC0)
└── app/
    ├── main.mm            entry point
    ├── AppDelegate.mm     menus, shortcuts, file/search actions, self-test
    ├── EditorController.mm tabs, documents, language + theme application
    ├── LanguageCatalog.mm  parses langs.model.xml
    ├── LanguageDetection.mm a language from a file's contents
    ├── LanguageModel.mm    reads the trained model
    ├── CryptoTools.mm      password hashes, SHA-3, Base58/32, passwords
    ├── ToolsWindows.mm     the windows of the Tools menu
    ├── StyleCatalog.mm     parses stylers.model.xml
    ├── LangMap.h           generated: language -> Lexilla lexer ID
    └── Info.plist          bundle metadata, plain-text/source-code types
```

Changed outside `macos/`: `lexilla/lexers/LexUser.cxx` only.

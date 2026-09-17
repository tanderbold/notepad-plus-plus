# What the macOS build still gets wrong, and what it lacks

An audit of the port against the Windows source, made on 2026-09-17. Five
reviews read the port's sources file by file and the Windows implementation
of each area; the clang static analyzer ran over `macos/app`; the built-in
suite stood at 583 passing checks. Every bug below was confirmed by tracing
the code path, and each carries the place to start from. `FEATURES.md` says
all 579 menu commands exist; this document is about what the commands do
once chosen, and about what has no menu command at all.

## Bugs

Most serious first. "Data" means the user can lose or corrupt text.

### Data

1. **Quit and closing the window never ask about unsaved documents.** The
   Quit item calls `terminate:` directly (`AppDelegate.mm:265`), there is no
   `applicationShouldTerminate:` and the window has no delegate, and
   `EditorController.mm:545` also terminates outright. Type, press Cmd+Q,
   the edits are gone. Fix: an `applicationShouldTerminate:` that runs the
   Save / Don't Save / Cancel alert for every modified document and returns
   `NSTerminateCancel`; route `windowShouldClose:` through it.
2. **Files handed to a fresh instance are dropped.** `application:openFile:`
   (`AppDelegate.mm:211`) arrives before `applicationDidFinishLaunching:`
   creates the editor, so `self.editor` is nil and nothing opens. Double
   clicking a file in Finder opens an empty editor; "Always a new instance"
   hands every file to an instance that discards it; "Open in new instance"
   then closes the modified original without a prompt. Fix: queue paths
   received before launch finishes, or create the editor in
   `applicationWillFinishLaunching:`.
3. **A NUL byte truncates the document on open and on save.**
   `[sciView setString:]` hands `UTF8String` to `SCI_SETTEXT`, which stops
   at the first NUL, and `[sciView string]` reads back with `c_str()`
   (`EditorController.mm:419,498`, `scintilla/cocoa/ScintillaView.mm:1705`).
   A log with an embedded NUL, or UTF-16 without a BOM, is shown cut short
   and saved cut short. Fix: `SCI_ADDTEXT` with the data length and
   `SCI_GETTEXT` sized by `SCI_GETLENGTH`, or refuse binaries as Windows does.
4. **Shift-JIS goes through a single-byte table.** `CodePageTables.h:72`
   lists 932 among the tables although it is double-byte; every lead byte is
   marked invalid, so Japanese text decodes to U+FFFD, and after
   `reinterpretAsCodepage:` every save turns non-ASCII into `?`. Fix: drop
   932 (and never table 936/949/950) so the CoreFoundation converter is used.
5. **Run… splices document text into `sh -c` unquoted.** `RunCommands.mm:243`
   runs the expanded command through `/bin/sh -c`; `$(CURRENT_LINESTR)` and
   `$(CURRENT_WORD)` come from the buffer, so a line containing a backtick or
   `$(...)` executes it, and a path with a space splits. Fix: single-quote
   every substituted value, or build argv.
6. **FTP: two remote files with one name share one cache file.**
   `FtpCommands.mm:143` caches under `ftp-cache/<lastPathComponent>`; opening
   `/b/index.html` after `/a/index.html` overwrites the cache, keeps a's tab,
   and remaps the upload path to b, so saving writes a's text over b. Also
   `FtpClient.mm:32` builds `ftp://host/dir` paths relative to the login home
   rather than absolute (`%2F` is needed) and does not percent-encode names;
   and `sftp -b` echoes each command, which `parseListing` (`FtpClient.mm:130`)
   turns into a phantom file in every SFTP directory. Fix: cache under a
   per-profile mirror of the remote path; encode paths; skip `sftp>` lines.
7. **Changing the encoding marks the buffer clean underneath.**
   `setEncoding:withBOM:` sends `SCI_SETSAVEPOINT` then sets `modified`
   (`EditorController.mm:977`); typing and undoing reaches the savepoint and
   clears the flag, so Close discards the pending encoding change without
   asking. Fix: drop the savepoint call.
8. **Reload forgets the code page but Save still uses it.**
   `reloadCurrentDocument:` resets encoding and BOM, not `codepage`
   (`EditorController.mm:575`); the text is decoded as UTF-8/Latin-1 and
   re-encoded through the old code page on save. Fix: clear `codepage` on
   reload, or decode through it.

### Behaviour

9. **Tab width, spaces and indent guides are hard-coded and reset on every
   tab switch.** `applyDocumentSettings` (`EditorController.mm:245`) sends
   4 / 4 / spaces / guides on every `selectDocumentAtIndex:`, undoing the
   preferences `applyToEditor:` set once. Fix: read `NppPreferences` there.
   There is no per-language tab setting at all (Windows: `Lang::_tabSize`).
10. **EOL detection picks CR when an LF comes first.** `DetectEOL`
    (`EditorController.mm:94`) finds the first CR and the first LF and, when
    they are not adjacent, answers CR without checking which came first;
    "a\nb\r\n" reports Classic Mac endings. Fix: compare the positions.
11. **The session restores the wrong tab.** The active index is taken over
    all documents but the file list skips unsaved ones, and loading appends
    after the untitled tab (`EditorController.mm:797,827`). Fix: store the
    active path. Unsaved tabs are not in the session at all (see Session below).
12. **Find Next loops on a zero-length regex match.** `findNext:`
    (`FindCommands.mm:200`) picks the first match at or after the caret, and
    an empty match at the caret is itself; `^`, `$`, `\b` and lookarounds
    never advance. Fix: skip a candidate equal to the current selection.
13. **A single Replace fails for regexes that look past the match.** The
    subject is cut at the selection end (`FindCommands.mm:353`,
    `NppRegex.mm:165`), so `foo(?=bar)` never matches on Replace while
    Replace All works. Fix: match over the whole document from the start of
    the selection and accept the match whose range equals it.
14. **Line transforms add a newline the file did not have.**
    `transformSelectedLines:` (`EditCommands.mm:107`) recognises the tail by
    input index, so Join, Remove Empty, Remove Duplicate and Split on an
    unterminated last line append "\n". Fix: define the tail by output index.
15. **Mark misplaces after an emoji.** `markCharactersInRangeFrom:to:`
    (`SearchCommands.mm:635`) advances by `lengthOfBytesUsingEncoding:` per
    UTF-16 unit, which is 0 for a lone surrogate; every mark after a non-BMP
    character lands four bytes early. Fix: walk composed character sequences.
16. **The Column Editor ignores virtual space and never replaces the block.**
    `AdvancedEditCommands.mm:158` inserts at each row's selection start; on a
    short line that is the line end, and a two-wide block gets text inserted
    before it rather than replaced. Fix: pad to the virtual-space offset, then
    `SCI_SETTARGETRANGE` + `SCI_REPLACETARGET` per row.
17. **Compare treats CR as content.** Lines are split on "\n" only
    (`CompareCommands.mm:15,210`), so a CRLF file against an LF file reports
    every line changed, and a CR-only file misaligns markers. Fix: split on
    all three endings and strip the CR.
18. **Linearize XML deletes newlines inside text.** `XmlCommands.mm:104`
    removes every newline in the serialised document, including those in
    text nodes and attribute values. Fix: only between `>` and `<`.
19. **An Extended-mode replacement containing `\0` is cut there.** Replace
    passes length -1 to `SCI_REPLACETARGET` (`FindCommands.mm:347`). Fix: pass
    the UTF-8 length, as `pasteOverBookmarkedLines` does.
20. **The Document Map shows the document that was current when it was
    opened.** Nothing rebinds `docMapView` on tab switch or close
    (`EditorController.mm:1369`). Fix: `SCI_SETDOCPOINTER` in
    `selectDocumentAtIndex:`.
21. **Recent Window records a stale index.** `closeDocumentAtIndex:` removes
    from `docs` first, then `selectDocumentAtIndex:` remembers the old index
    (`EditorController.mm:439,551`). Fix: remember the document, not an index.
22. **A system appearance change undoes View toggles.** The KVO handler
    (`AppDelegate.mm:1016`) re-runs `applyToEditor:`, which pushes the stored
    wrap, whitespace, guides and font over what the View menu changed
    (`AppDelegate.mm:1940`); the View toggles never write the preference and
    only touch the active view. Fix: have the toggles write the preference.
23. **The Style Configurator pins a background to the current appearance.**
    `SettingsPanels.mm:661` always stores fg and bg, with bg defaulting to
    the resolved `textBackgroundColor`; ticking Bold on a keyword in light
    mode leaves keywords on white boxes in the dark theme. Fix: store only
    what changed.
24. **Preferences Reset leaves stale controls.** `resetAll:`
    (`SettingsPanels.mm:518`) clears the defaults, not the controls, and the
    next Apply writes the old values back. Fix: refresh from the preferences.
25. **Custom word characters cannot be turned off.** `BehaviourCommands.mm:374`
    returns early when disabled and nothing sends `SCI_SETCHARSDEFAULT`.
26. **Saved macros do not survive a restart.** `macros.json` is written
    (`ToolsCommands.mm:157`) and never read.
27. **Print headers ignore `$(SHORT_DATE)`, `$(LONG_DATE)` and `$(TIME)`**
    (`BackupAndPrint.mm:197`), the names in Windows' default header.
28. **Timestamped backups collide within one second** and the earlier one is
    deleted first (`BackupAndPrint.mm:91`).
29. **Function List lines are wrong for CR-only files**: `LineAtByte`
    counts only "\n" (`FunctionListCatalog.mm:302`).
30. **`userDefineLang.xml` is written unescaped** (`SettingsCommands.mm:417`),
    so a name with `"` or `&` breaks the file for Windows too.
31. **Auto-close pairs are inserted unconditionally and the closer is never
    typed over** (`TypingCommands.mm:73,187`): typing `()` yields `())`.
    Windows inserts only before a blank or closer and swallows the typed
    closer. The close-tag runs in every language, not only HTML/XML, and
    does not skip void elements (`TypingCommands.mm:86`).
32. **Smart highlighting with Match case or Whole word does nothing**:
    `BehaviourCommands.mm:357` builds a multi-selection and restores it
    instead of filling the indicator, and beeps on zero hits.
33. **Find in Files exclusion patterns are not understood.** `!*.log` is
    tried as a glob (`FindCommands.mm:390`) and excludes everything else.
34. **Whole word in regex mode rewrites the pattern** as `\b(?:...)\b`
    (`FindCommands.mm:161`), which changes patterns that start or end with
    a non-word character; Windows applies whole-word to literal modes only.
35. **`.` always matches a newline.** Every pattern compiles with DOTALL
    (`NppRegex.mm:83`) and the dialog has no ". matches newline" box; the
    Windows default is the opposite. Regex error offsets are also shifted by
    the injected `(*ANYCRLF)` and `(?i)` prefixes (`NppRegex.mm:71,87`).

Cosmetic but real: the analyzer's four `nil returned from a non-null method`
warnings (`EditorController.mm:202`, `Toolbar.mm:232,245`,
`WorkspacePanel.mm:103`) are missing `nullable` annotations; callers check.

## What the Windows version has and this does not

Grouped by area. "Property only" means the setting exists in
`NppPreferences` and works, but no control in Preferences reaches it.

**File handling.** No file-change detection on activation (Windows asks to
reload, offers "keep non-existing file", can update silently and scroll to
the end); a buffer changed on disk is silently stale. No command-line
switches at all (`main.mm` ignores argv): `-n<line> -c<col> -l<lang> -ro
-nosession -multiInst -openSession -notepadStyleCmdline -z -qn/-qt/-qf`.
No character-set detection: BOM, then valid UTF-8, then Latin-1
(`EditorController.mm:88`); Windows runs uchardet and has "Open ANSI as
UTF-8". File monitoring follows one document per controller. Read-only
files are not detected on open. Large files are not streamed.

**Session.** JSON of `{path, language}` plus an index. Windows keeps caret,
scroll, selection, folds, marks, encoding, read-only, tab colour, the second
view, untitled buffers and the file browser roots.

**Preferences.** 16 pages and about 75 controls against 24 pages and about
277. Whole pages absent: Tab Bar, Default Directory, Recent Files History,
Language menu, Searching, Search Engine, MISC. Property only: tab bar
layout/lock/close buttons/pin, recent-files cap and display, default
directory, "fill find from selection", "word under caret", default EOL /
encoding / language for new documents, untitled tab named from its first
line, "deactivate wrap above size", "allow autocomplete/smart highlight
above size", print header middle / footer left and right / header font.
Absent with no property: localisation picker, hide menu / status bar,
toolbar icon sets and accent colour, smooth font, custom selection colour,
EOL display and colour, non-printing character appearance, dark-mode tones
and custom colours, fold margin style, border width, dynamic line-number
width, change-history margin toggle, distraction-free width, per-language
indent, backspace-unindent setting (always on), Highlight Matching Tags,
smart highlight in the other view / with Find settings, formfeed page
break, header/footer variable picker, user-defined auto-insert pairs,
custom date/time format, per-panel "remember state", File Status
Auto-Detection, Document Switcher MRU, Document Peeker, auto-updater
settings, mute sounds, file-name-only title bar, Save All confirmation.
The dialog has Apply and Reset but no Cancel.

**Style Configurator.** Present: language and style pickers, fg/bg, bold /
italic / underline, font name and size, live application. Absent: the seven
global overrides, default and user extensions, default and user keywords,
theme picker in the dialog, Save & Close / Cancel (changes are immediate and
irreversible), writing back to the theme XML (overrides live only in
`NSUserDefaults`).

**User Defined Language.** There is no editor: `defineUserLanguage:` is four
text prompts writing a two-keyword-set `userDefineLang.xml`. Nothing sends
`SCI_SETPROPERTY userDefine.*`, so no UDL, imported or not, is ever
highlighted; the "user" lexer is created unconfigured. No import, export,
rename, remove, folding, delimiters, comment and number styling, `-udl=`.

**Shortcut Mapper and context menu.** A single list of menu items that
already have a key; items without one cannot be assigned; a text prompt for
the key; no Scintilla commands, macro or Run command shortcuts, filter or
conflict check; nothing in `shortcuts.xml`. The context menu is a
comma-separated list of titles in a prompt; no `contextMenu.xml`, submenus
or tab-bar menu.

**Docking.** Workspace and project trees sit left in a split view, the map
right at a fixed width; Function List, Document List, Clipboard History,
Character Panel and the console float in separate windows. No dock / undock,
tabbing panels together, top or bottom containers, or saved layout.

**Project panels.** All three are folder trees (the Folder as Workspace
view). No virtual folders, adding single files, rename, move, `.xml`
workspace save / load, or Find in Projects over a real project.

**Search.** Present: three modes, match case / whole word / wrap / backward /
in selection, Find, Replace, Find in Files, Find in Projects and Mark tabs,
Count, Find All, Replace All, Replace in Files with confirmation, filters
with several globs, recursion, hidden folders, "From doc". Absent: ". matches
newline", transparency, find / replace / filter / directory histories with
dropdowns, "In selection" greyed without a selection, per-search folding,
collapse / expand and the context menu in the results panel, "Purge for each
search" and "Copy Marked Text" on the Mark tab, a distinct Volatile Find,
`${name}`, `$&`, `` $` ``, `$'`, `$$` and two-digit references in
replacements. Unverified: Find All / Replace All in All Opened Documents.
The engine is PCRE2, a superset of what Boost offers, so regex syntax
itself is not the gap.

**Editing assist.** Ctrl+Space lists only document words; Windows separates
function completion (Ctrl+Space, from the API files) and word completion
(Ctrl+Enter, inserting a sole match). Document words are gathered by
splitting on `[A-Za-z0-9_]` and matched case-sensitively; `SCI_AUTOCSETIGNORECASE`
is never set. Calltips appear on `(` only and are not re-evaluated on `,`
or closed on `)`. Path completion is case-sensitive and shows bare names.
Auto-indent handles the newline only: no brace realignment, no
indent-after-`if` for C-like languages, no Python `:`. No "no autocomplete
while recording a macro". Defaults differ from Windows: completion off,
threshold 3, hints off, spaces on, smart-highlight whole-word off.

**Panels.** Document Map is a zoomed mirror without the view-zone overlay,
click-to-scroll or scroll sync. Document List is one column (Windows: name,
extension, path, sortable, MRU switcher). Character Panel lists 32-255 as
Unicode, not the document's code page with hex / HTML columns. No Document
Peeker.

**Platform.** English only, no `nativeLang` loading. No plugin loading, no
NPPM/NPPN messages, no Plugins Admin; the built-in stand-ins are JSON,
Compare, XML Tools, FTP, Run and the Function List. Check for Updates opens
the releases page; the stored proxy is never used. Debug Info lists four
items. About is the stock Cocoa panel.

## Where to start

In this order, each a day or less of work and each closing a hole a daily
user falls into:

1. Bugs 1 to 3 (quit prompt, launch files, NUL) - all three lose text.
2. Bugs 9 to 11 (tab settings, EOL, session tab) - they show on every launch.
3. File-change detection on activation, with reload / keep prompts.
4. Bugs 4 to 8 (Shift-JIS, Run quoting, FTP cache and paths, encoding flag,
   reload code page).
5. Command-line switches, at least `-n -c -l -ro -nosession -multiInst`.
6. Character-set detection (uchardet is in `PowerEditor/src/uchardet`, and
   builds on macOS) and "Open ANSI as UTF-8".
7. Session depth: caret, scroll, folds, marks, encoding, untitled buffers.
8. Search bugs 12, 13, 33, 34, 35 and the ". matches newline" box.
9. Loading `userDefineLang.xml` into the lexer; a UDL editor after that.
10. Preferences controls for the settings that already exist.

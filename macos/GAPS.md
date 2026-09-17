# What the macOS build still gets wrong, and what it lacks

An audit of the port against the Windows source, made on 2026-09-17. Five
reviews read the port's sources file by file and the Windows implementation
of each area; the clang static analyzer ran over `macos/app`; the built-in
suite stood at 583 passing checks. Every bug below was confirmed by tracing
the code path, and each carries the place to start from. `FEATURES.md` says
all 579 menu commands exist; this document is about what the commands do
once chosen, and about what has no menu command at all.

## Bugs

The thirty-five bugs the audit found were fixed on 2026-09-18, in five
commits after the audit's own, each with a test that fails on the old code
(the suite went from 583 checks to 613). In brief: nothing that can throw
text away does so unasked (closing a tab, Close All and its variants, the
window, quitting, Reload); files opened at launch open; a NUL byte is
content; a changed encoding stays a change; Reload keeps the code page and
the scroll position; Save a Copy As writes what Save would; tab settings,
line-ending detection, the session's active tab, the Document Map, Recent
Window and the View toggles behave; closing another tab leaves the front
one in front; Find Next leaves an empty match behind; Replace matches over
the rest of the document; '.' stays on its line unless asked; whole word
leaves a regex alone; !pattern and !\folder work in Find in Files; line
transforms keep the end of the file; marks count bytes by code point; the
Column Editor pads and replaces; Shift-JIS decodes; Run… quotes what it
splices; FTP caches by whole path, uses absolute encoded addresses and
ignores sftp's echo; Compare and Linearize leave line endings and text
alone; the Style Configurator, Preferences Reset, word characters, saved
macros, print variables, backups, the Function List, userDefineLang.xml,
auto-close pairs and smart highlighting do what they say.

### Still open

Found by the same audit, not yet fixed. Most serious first.

1. **Periodic "autosave" writes the user's file** (`BackupAndPrint.mm:148`).
   Windows' periodic backup writes `backup\NAME@timestamp` and never the
   file itself; the port's setting is called autosave and presented as
   such, but a user coming from Windows expects a snapshot. The snapshot
   of unsaved documents (`snapshot.json`) is written and never restored.
2. **No read-only detection on open** (`EditorController.mm:386`): a file
   without write permission is editable until Save fails.
3. **Save As does not refuse a path already open in another tab**
   (`EditorController.mm:478`); Save All skips untitled documents and does
   not confirm; Rename of an untitled document writes it to disk.
4. **Restore Last Closed File and Open All Recent Files are missing**, and
   the recent list is filled by opening rather than closing
   (`EditorController.mm:429`).
5. **Insert Date/Time**: the order is inverted against Windows (time
   first by default), the long form has seconds, and the selection is not
   replaced (`EditCommands.mm:607`).
6. **Paste to Bookmarked Lines** hands clipboard line i to bookmark i;
   Windows replaces every marked line with the whole clipboard. Copy and
   Cut of bookmarked lines drop the line endings (`SearchCommands.mm:232`).
7. **Go To Line** has no offset mode and no range check
   (`AppDelegate.mm:2914`); Select All Between Matching Braces excludes the
   braces where Windows includes them (`SearchCommands.mm:326`).
8. **Proper Case and Sentence Case** differ from Windows on apostrophes,
   digits and sentence boundaries (`EditCommands.mm:164`); Trim removes
   every Unicode space where Windows removes tabs and spaces.
9. **Large files** are decided on after a full decode, with no too-big
   guard and backups not suppressed (`BehaviourCommands.mm:17`).
10. **Close All But Pinned** keeps pinned tabs anywhere; Windows keeps the
    leading run and moves pinned tabs left. No drag and drop of files onto
    the window.
11. **Column Editor** lacks repeat count, number base and the from-caret
    mode; Sort Lines ignores a rectangular selection's column range.
12. **The secondary view can be left on a released document**: nothing
    tracks which document the other pane shows, and closing that document
    from the main pane (`EditorController.mm`, `closeDocumentAtIndex:`)
    releases it while the pane still points at it. Pre-existing.
13. Cosmetic: four `nullable` annotations missing (`EditorController.mm:202`,
    `Toolbar.mm:232,245`, `WorkspacePanel.mm:103`).

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

1. File-change detection on activation, with reload / keep prompts.
2. Snapshot restore of unsaved documents, and periodic backup that does
   not touch the file (still-open bug 1).
3. Command-line switches, at least `-n -c -l -ro -nosession -multiInst`.
4. Character-set detection (uchardet is in `PowerEditor/src/uchardet`, and
   builds on macOS) and "Open ANSI as UTF-8".
5. Session depth: caret, scroll, folds, marks, encoding, untitled buffers.
6. Still-open bugs 2 to 8.
7. Loading `userDefineLang.xml` into the lexer; a UDL editor after that.
8. Preferences controls for the settings that already exist.

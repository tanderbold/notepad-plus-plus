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

The thirteen bugs listed here after the first round were fixed on
2026-09-18 as well (commits from "the still-open bugs, batch one" on),
with the exceptions below.

1. **Save All does not confirm** when more than one document is dirty;
   Windows asks unless the setting says not to. Small.
2. Cosmetic: the `outlineView:child:ofItem:` delegate method in
   `WorkspacePanel.mm` returns nil for an absent root; callers guard.

## What the Windows version has and this does not

Grouped by area. "Property only" means the setting exists in
`NppPreferences` and works, but no control in Preferences reaches it.

**File handling.** Done since the audit: file-change detection on
activation with the reload / keep prompts and the silent and scroll-to-end
settings; the command-line switches; uchardet for the character set and
UTF-16 without a mark; read-only detection on open; the large-file
decision by size on disk. Still: file monitoring follows one document per
controller; large files are not streamed; "Open ANSI as UTF-8" has no
setting (pure-ASCII files already read as UTF-8).

**Session.** Done since the audit: caret, scroll, selection, bookmarks,
pinned state, tab colour, encoding and code page, and untitled buffers
through the periodic backup. Still: folds, user read-only, the second view
and the file browser roots.

**Preferences.** 20 pages now. Done since the audit: Tab Bar, Recent Files
History, Default Directory and Searching pages, and every setting that
existed only as a property has a control; File Status Auto-Detection and
character-set detection have theirs. Still absent: Language menu, Search
Engine and MISC pages, and, with no property behind them: localisation picker, hide menu / status bar,
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

**User Defined Language.** Done since the audit: `userDefineLang.xml` and
`userDefineLangs/*.xml` are read, listed, claim their extensions and drive
the user lexer with the same properties, keyword lists and styles Windows
sends, and `-udl=` works. Still no editor: `defineUserLanguage:` is four
text prompts writing a minimal file. No import, export, rename or remove.

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

1. A UDL editor with import and export, now that UDLs highlight.
2. The Shortcut Mapper: any command, Scintilla commands, macros, conflicts.
3. Session depth: folds, the second view, the file browser roots.
4. Project panels with virtual folders and `.xml` workspaces.
5. Style Configurator: global overrides, Cancel, writing to the theme XML.
6. Document Map view zone and click-to-scroll; Document List columns.
7. Docking of panels, with the layout saved.
8. Localisation from `nativeLang`.

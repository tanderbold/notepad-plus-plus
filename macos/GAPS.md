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

Plan item 3.5 (2026-09-18) tidied what the audit left: the compiler and
the static analyzer are silent over `macos/app` (nullability annotations,
two dead stores, three nil paths); a Project Panel with no workspace shows
an empty tree instead of a nil row; a zero-width column sort takes the rest
of the line, as upstream's `getSortKey` does, and every sort is stable in
both directions; tabs are not dragged across the edge of the pinned run, so
Close All But Pinned keeps exactly the tabs at the left. No `kNppCP…` table
was unused, so none was removed.

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
decision by size on disk. Plan 2.5: monitoring (tail -f) is per document,
read-only while watched, stops when the file goes, catches up when a tab
comes to the front, and is kept in the session; "Apply to opened ANSI
files" decides whether seven-bit files are UTF-8 or ANSI, as upstream's
uni7Bit rule; files of 64 MB and more are mapped and handed to Scintilla as
bytes without a string in between; files of 2 GB and more open after
upstream's warning (which Performance can suppress) instead of being
refused. Plan 2.6: -export=functionList writes <file>.result.json in
upstream's JSON and quits, -quickPrint prints and quits (both without a
session), -x / -y place the window, -monitor watches every file given, and
-pluginMessage= is accepted and reported as ignored, there being no plugins.

**Session.** Done since the audit: caret, scroll, selection, bookmarks,
pinned state, tab colour, encoding and code page, and untitled buffers
through the periodic backup. Plan 1.4: folds (which now also survive tab
switches, opening files, a second view on the document and a change of
language or theme - each of those used to unfold everything), the user's
read-only, the second view with its document and position, monitoring,
and the Folder as Workspace roots, of which there can now be several as
upstream has them, with its right-click menu (Add, Remove, Remove All,
Copy path, Copy file name, Find in Files..., Reveal in Finder, Terminal
here, Run by system, Fold / Unfold all, Locate current file). The session
file is still the port's JSON, not upstream's session XML.

**Preferences.** 24 pages. Done since the audit (plan 2.4): Language
(menu hiding, compact letter submenus, SQL backslash), Search Engine and
MISC. pages (Document Switcher with MRU, Document Peeker, file name only in
the title, Save All confirmation, mute sounds, session / workspace file
extensions, symlinks in Folder as Workspace); hide the status bar; toolbar
regular or filled Fluent icons with upstream's colour choices and partial
or complete colorization; smooth font, custom selected text colour, EOL and
non-printing character appearance with custom colours, multi-editing, no C0
typing, toggleable fold commands; fold margin style, line number display
and dynamic / constant width, Change History in margin and text,
distraction-free width; per-language indentation and Backspace unindent;
Highlight Matching Tags with attributes, smart highlighting with Find
settings and in the other view; form feed page breaks and the header
variable list; the custom date format with preview; the Searching extras;
inactive-tab colours, active-tab bar, reduced tabs and label length;
Remember panel state per panel; a Cancel button. Not applicable on macOS,
so left out on purpose: hiding the menu bar (it belongs to the system),
dark-mode tones and custom dark colours (the system's dark appearance draws
the chrome), the 3D border width, DirectWrite rendering modes, minimize /
close to the tray, "alternate icons" and "show only pinned button" (the
port's tabs draw no such buttons). The localisation picker lists every
`nativeLang` file by the name it gives itself.

**Style Configurator.** Done since the audit: the dialog edits a copy of
the theme's XML, previews each change and writes the user's copy on Save &
Close (`stylers.xml` for the default theme, `themes/<name>.xml` otherwise),
which is read in preference to the shipped one; Cancel restores the theme.
It has the theme picker, Global Styles, the seven Global override switches,
default and user extensions (user ones win, as in `getLangFromExt`),
default and user-defined keywords, font family and size pickers, and
transparency. Older overrides kept in `NSUserDefaults` are folded into the
theme the first time it is saved.

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

**Search.** Done since the audit: histories of ten for find, replace,
filters and directories in drop-downs, kept between launches; the swap
button; "In selection" greyed and cleared without a selection and ticked
for one of 1024 characters or more; transparency on losing focus or always;
Find All / Replace All in All Opened Documents; Replace in Projects; "Purge
for each search" and "Copy Marked Text" on Mark. Replacements go through a
port of Boost's `format_all` formatter, as Notepad++ calls it, so `$&`,
`` $` ``, `$'`, `$$`, `$n`, `${n}`, `$+{name}`, `$MATCH` and friends,
`\n` (one digit; `$10` for two), octal, `\x{…}`, parentheses and `?N…:…`
conditionals give the same text as on Windows. Volatile Find was already
there. The results tab now behaves as the Search results panel: searches
stack newest first with the older ones folded (search, file, hit levels),
and its context menu has Fold all, Unfold all, Copy Selected Line(s),
Copy Selected Pathname(s), Select all, Clear all, Delete This Search, Open
Selected Pathname(s) and Purge for every search. Still different: it is a
tab rather than a docked panel, and hits are not coloured.

**Editing assist.** Done since the audit, following AutoCompletion.cpp,
FunctionCallTip.cpp and maintainIndentation: Function Completion (⌃Space,
the API list) and Word Completion (⌘Return, a sole match typed in) are
separate; case is ignored where the API file says so and respected in
plain text; the brief list means "only what fits". Parameter hints follow
the typing (open on `(`, highlight the parameter on `,`, close on `)`,
arrows step overloads). Path completion takes the whole path, spaces and
all, ignoring case, folders with a trailing slash. Advanced auto-indent
has the braceless `if/for/while`, `{`/`}` realignment and Python's `:`.
Nothing is added while a macro records or plays; column mode gets no
pairs; up to three user pairs. Defaults now match Windows.

**Panels.** Done since the audit: the Document Map draws its view zone,
scrolls the editor on a click, drag or wheel, follows the editor and takes
its colours and wrapping. The Document List has Name / Ext. / Path columns
with a header menu, sorting, click to switch, a double click below the
files for a new one, the tab menu on a file and Close / Save Selected Files
on several; tabs have their right-click menu as upstream lays it out. The
Character Panel is the ASCII Codes Insertion Panel: 0-255 in the document's
code page with Hex and the three HTML columns, inserting the cell clicked.
The Document Peeker previews a hovered tab in a window or in the map
(Preferences > MISC.). Plan 2.7: panels dock in four containers around the
editor (left, right, top, bottom) as tabs, where upstream puts them by
default (Folder as Workspace, Project Panels and Document List left; Function
List, Document Map, ASCII panel and Clipboard History right); a panel's tab
dragged to an edge of the window docks it there and anywhere else floats it,
its right-click menu offers the same, a double click floats it or docks it
back; places, floating frames and dock sizes are kept. Still different: the
Search results stay a tab rather than a bottom panel, and the Document List
has no "Group by View".

**Localisation.** Done since the audit: upstream's `nativeLang` files load
unchanged and switch without a restart. Menus are translated by command id
and menu id (so `russian.xml` leaves only language names, code pages and
Mac-only commands in English), dialogs and message boxes by their English
text, tabs and windows by the titles upstream gives them. Push buttons widen
to fit a longer translation. Still different: the port's own wording (most
Preferences checkboxes, the port-only panels) has no upstream key and stays
English, and right-to-left languages are not mirrored.

**Platform.** No plugin loading, no
NPPM/NPPN messages, no Plugins Admin; the built-in stand-ins are JSON,
Compare, XML Tools, FTP, Run, the Function List and NppExec-style scripts
(Plugins > NppExec, with `npes_saved.txt`; see PORTING.md, "Plugins: what
was decided").

**Updates, About, Debug Info.** Done since the audit: the auto-updater asks
the port's GitHub Releases (the repository is a setting) through the stored
proxy, on startup or on exit and at most every 15 days as upstream's
`nextUpdateDate` rule has it; Check for Updates answers as WinGUp does. It
offers the release page rather than installing: there is no signed package
to install yet. About is upstream's box (chameleon, version and bitness,
build time, links, licence) and Debug Info has upstream's fields in
upstream's order, with the Mac's values and a Copy button.

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

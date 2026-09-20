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

### Still open: the review of the finished plan (2026-09-18)

After the plan was finished three independent reviews read stages 1, 2 and
3 against `PLAN.md` and the Windows source; a fresh clone builds universal
without warnings, passes the suite and packages. What they found and what
was fixed at once is in the commits "macos: review - …": a reassigned
Scintilla key kept firing; the API completion list was unsorted; Preferences
wrote stale values back over settings changed elsewhere; searching all open
documents reordered Ctrl+Tab; the results tab could be typed into; negative
`-x`/`-y`; NppExec scripts (`IF … THEN`, operators inside values, `SET`
words quoted as one, a 30 s limit on programs, no Stop, injection inside
the shell's `$( )`); localisation put labels back to their first text,
left context menus and column headers English, emptied the editor's context
menu under a translation, and gave the main menu the tab menu's wording.

The rest of what the reviews found was fixed on 2026-09-19, each with a
test: macros from a Windows `shortcuts.xml` keep and play their menu-command
and Find steps; big files in a code page are detected and converted piece by
piece; a project workspace writes untouched paths as it read them and a
renamed file renames its path; Find and Replace in Files read and keep a
file's own character set; the UDL styler keeps every nesting bit and honours
transparent colours, and shows a change while it is typed; monitoring
follows a rotated log; messages, sheets and Find's status line use upstream's
words with their placeholders, so translations apply; the Style Configurator
opens the system font panel; the divider between the two views and the front
tab of each dock container are kept; a column sort covers the rectangle's
lines, thin selections included; Select and Find Next is no longer Volatile
Find; a wrapped Document Map wraps where the editor does; a dragged panel
shows where it would land; the results tab is known by a flag; `EXIT` in a
nested NppExec script returns to its caller; a macro records the menu
commands upstream records by id (192 of them, read from `NppCommands.cpp`)
and the Find dialog's searches; the language model has examples
of asn1, fortran77, gui4cli, hollywood and json5.

Since then: a floating dock window holds several panels as tabs (drop one
on another's window); the Document List has "Group by View"; Preferences
never cuts a text short - labels widen or go onto a second line, a choice
that is a sentence is a radio button - and its labels use upstream's wording,
so every nativeLang file translates them; what the port says and Windows
does not (JSON, Compare, XML, FTP, NppExec, updates, its own settings) is
translated from `macos/resources/nativeLang-extra/<language>.xml`, which
exists for Russian.

What is left of that list, none of it a defect in what exists:

1. `nativeLang-extra` has a file for each of the 92 translated languages,
   written by a model from each language's own nativeLang vocabulary and
   read by no native speaker. 54 are complete; in the small languages an
   item nobody could vouch for was left out and stays English (Samogitian
   has none, Abkhazian 12, Kabyle 19, Aranese 28). `README.md` there says
   how to add to them, `check_nativelang_extra.py` checks them.
2. The plan's wording was wrong in two places and nothing is missing:
   `${name}` and two-digit `\\10` are not Boost's syntax (`$+{name}` and
   `$10` are, and work); Notepad++ has no "line context" in its results.
3. Working out a language from a text is the trained model's alone now: the
   hand-written marks and keyword rules beside it are removed, and it learns
   from real projects as well (PORTING.md has the sources and the numbers).
   Its known weakness is a text that quotes another language at length - a
   script that writes out a unit file is read as the unit file - which the
   trainer measures ("quoting", 61% right first) rather than patches.

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
file is upstream's `session.xml` (mainView / subView, Mark, Fold,
FileBrowser): one written on Windows is read here and the other way round,
what only the port keeps riding in `mac…` attributes Windows ignores; a
`session.json` from an earlier build is read once and replaced.

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
sends, and `-udl=` works. Plan 1.1: the editor - upstream's four tabs, the
styler for each group with its nesting and transparent colours, Create,
Rename, Remove, Save As, Import and Export, a change shown in the document
while it is typed - writing `userDefineLang.xml` in upstream's format.

**Shortcut Mapper and context menu.** Plan 1.2: five tabs (menu, macros,
Run commands, plugin commands - empty - and Scintilla commands), a filter,
any command assignable, conflicts shown before saving, `shortcuts.xml` in
upstream's format read and written, macros from Windows with every kind of
step. The editor's context menu is `contextMenu.xml` in upstream's format
(commands by menu and item name or by id, FolderName submenus, ItemNameAs,
separators), upstream's default the first time, read at every right click;
`tabContextMenu.xml` does the same for the tabs when there is one. Commands
of Windows plugins named there (MIME Tools, NppExport) are left out.

**What each lexer is told.** Found from "an HTML page cannot be folded": the
port set `fold` and sent each language's word lists to the lexer under
Notepad++'s own numbers, where `ScintillaEditView.cpp` has a function per
family. Now as upstream: `fold.html` and `fold.hypertext.comment` for HTML,
PHP, ASP, JSP and XML (without them the hypertext lexer works out no fold
levels at all); `fold.comment`, `fold.preprocessor`, no guessing at `#if`
for the C family; backquoted strings for Go, TypeScript and JavaScript;
escape sequences for JSON and comments for JSON5. Word lists go where each
lexer reads them - in the C family types are list 1 and were never coloured;
Objective-C, Tcl, TypeScript and XML have their own order - and a page is
given HTML's, JavaScript's, PHP's and ASP's words and styles together. A
`.php` file is lexed as the page it is (`hypertext`), not as bare
`phpscript`.

**Tools.** Beyond upstream: Hashes (six more digests, HMAC, bcrypt, scrypt,
Argon2, PBKDF2 with their settings and a verifier), Base (Base64, Base58,
Base32 both ways, text or bytes in hexadecimal), a password generator, and
HTTP Request (a request as curl would send it, the answer shown, curl
commands pasted in and copied out); see
PORTING.md. Upstream's digest dialogs are reproduced, and its twelve command
ids kept. The 75 texts of these windows are in `nativeLang-extra` for every
language, model-made like the rest of that folder and as much in want of a
native speaker's eye.

**Docking.** Done since the audit (plan 2.7): four containers with tabs,
drag between docked and floating, the layout saved. Still different: see the
review list above.

**Project panels.** Done since the audit (plan 1.3): virtual folders, files
added singly and recursively, rename, move up and down, Windows `.xml`
workspaces, Find in Projects. Still different: see the review list above.


## Where to start

Every item of the list that stood here is done (`PLAN.md`). What is left
is the review list under "Still open", in its order.


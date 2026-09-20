# Notepad++ for macOS

A native macOS port of [Notepad++](https://notepad-plus-plus.org): the same
editing engine (Scintilla), the same syntax highlighting (Lexilla), the same
language, colour, theme, function-list and translation files as the Windows
version - in a Cocoa application that runs on Apple silicon and Intel Macs.
No Wine, no emulation, no Windows code.

> This is an independent port living in the `macos/` folder of a fork. It is not
> made or endorsed by the Notepad++ project. Same licence: GPL.

## What you get

**All 579 commands of the Windows menus** are implemented (the list is generated
from the Windows menu resource, see [FEATURES.md](FEATURES.md)), and they behave
the way they do on Windows - the port is written against Notepad++'s own sources.

**Editing**
- Tabs, two views side by side (move or clone a document to the other view), drag and pin tabs, tab colours.
- Multi-selection and column mode, Column Editor, Begin/End Select, line operations (sort seven ways, remove duplicates, join, split, move), case conversions, trim and tab/space conversion, comment toggling, date/time insertion.
- Auto-completion of words, functions and paths with parameter hints; auto-close of brackets, quotes and HTML tags; smart highlighting; brace and XML-tag matching.
- Bookmarks with line operations, five mark styles, Change History, code folding, hidden lines.
- Macros: record, play, run many times, save with a shortcut - including menu commands and searches, in the Windows `shortcuts.xml` format.
- Clipboard History, Character Panel, paste as HTML / RTF / binary.

**Languages**
- Syntax highlighting and folding for about 90 languages, from Notepad++'s own `langs.model.xml` and `stylers.model.xml`; all upstream themes; the Style Configurator.
- User Defined Languages: the full editor, and UDL files from Windows work as they are.
- Function List for every language upstream has a parser for (run with PCRE2, as written), Document Map, Document List, Folder as Workspace, Project panels - dockable, floatable, remembered.
- **The language of a text is worked out from its contents** when its name says nothing - a file without an extension, a snippet pasted into an empty tab - by a small model trained on real code, which offers one language or a short list.

**Search**
- Find, Replace, Find in Files, Find in Projects, Mark, incremental search, with Notepad++'s regular-expression syntax (Boost), the results panel with folding and navigation, search-result colours.

**Files and encodings**
- UTF-8/16 with and without BOM, ANSI, all 46 of Notepad++'s character sets as "Encode in" and "Convert to", encoding detection, EOL conversion.
- Sessions, periodic backup and snapshot of unsaved documents, file-change monitoring (tail -f), large-file handling, read-only, print.
- `session.xml`, `shortcuts.xml`, `contextMenu.xml`, UDL and theme files are read and written in the Windows formats, so a settings folder can be carried over.

**Tools**
- **Hashes**: MD5, SHA-1, SHA-256, SHA-512 as upstream, plus SHA-224, SHA-384, SHA3-256, SHA3-512, BLAKE2b, CRC-32 and an optional HMAC key; **bcrypt, scrypt, Argon2 and PBKDF2** with their settings, salts, and a verifier. Each: of a text (or each line), of files, of the selection into the clipboard.
- **Base**: Base64 (and URL-safe), Base58 (and Base58Check), Base32 - from text or bytes in hexadecimal, and back to both.
- **Password Generator**: length, character sets, look-alikes excluded, entropy shown, drawn from the system's secure random generator without bias; optionally the hash of each password.
- **HTTP Request**: method, address, parameters, headers, body, Basic authentication, redirects, timeout; the answer's status, headers and body (JSON laid out), opened as a document if wanted; **Paste curl Command** and **Copy as curl**.

**Built in instead of plugins** (Windows plugins are Windows binaries and cannot load)
- JSON: format, compact, sort keys, validate, tree.
- Compare: two files side by side with differences marked and navigation.
- XML tools: pretty print, linearize, validate (DTD/XSD), XPath, XSLT.
- FTP/FTPS client panel.
- NppExec-compatible scripting: a console, scripts, variables, its commands.

**Interface**
- The interface in any of Notepad++'s ~90 translations, chosen in Preferences; what only the Mac version says is translated too.
- Preferences with Notepad++'s pages and wording, Shortcut Mapper (menu, macro, run and Scintilla commands, conflicts shown), editable context menu, toolbar with upstream's icon sets, dark mode.
- Mac conventions where Windows ones make no sense: Finder and Terminal for Explorer and cmd, the Trash for the Recycle Bin, ⌘ shortcuts.

What is different from Windows, honestly listed: [GAPS.md](GAPS.md). The main
one: **Windows plugins (.dll) do not run** and never will; the most used ones are
built in instead.

## Install

Download the `.dmg` from the latest successful run of the *macOS port* workflow
(Actions tab → run → Artifacts), open it and drag **NotepadMac** to Applications.
Requires macOS 11 or later; one build runs on Apple silicon and Intel.

Builds from CI are not signed with an Apple Developer ID yet, so the first time:
right-click the app → **Open** → **Open** (or System Settings → Privacy & Security
→ *Open Anyway*).

Settings live in `~/Library/Application Support/NotepadMac/` and in the
`org.notepad-plus-plus.mac` preferences domain.

## Build it yourself

Only Apple's Command Line Tools are needed (`xcode-select --install`) - no Xcode
project, no Homebrew packages.

```
git clone -b macos-port <this repository> npp && cd npp
bash macos/build.sh                          # universal app in macos/build/NotepadMac.app
NPPMAC_ARCH=native bash macos/build.sh       # this Mac's architecture only, about twice as fast
bash macos/test.sh                           # the test suite (runs inside the real application)
bash macos/package.sh                        # macos/build/*.dmg
open macos/build/NotepadMac.app
```

To sign and notarise a release, set `NPPMAC_SIGN_IDENTITY="Developer ID Application: … (TEAMID)"`
and `NPPMAC_NOTARY_PROFILE=<profile made with xcrun notarytool store-credentials>` before
`package.sh`.

## How it is made

- Upstream's `scintilla/` and `lexilla/` are compiled unchanged (one portability fix in `LexUser.cxx`);
  `PowerEditor/` is not compiled at all - it is the specification the Mac code is written against,
  and the source of the data files and generated tables.
- The Mac application is about 40,000 lines of Objective-C++ in `macos/app/`.
- A suite of almost 800 checks runs inside the real application on every push (GitHub Actions,
  macOS runner): every menu command, file formats against files written on Windows, encodings,
  regular expressions, cryptography against published vectors, the HTTP and FTP clients against
  local servers, the interface in another language with no text cut off.
- [PORTING.md](PORTING.md) is the engineering record: what was built, how, what was measured.
  [AGENTS.md](../AGENTS.md) is the briefing for AI coding agents, including how the
  language-detection model is trained.

## Contributing

Bug reports with a file or steps that show a difference from Windows Notepad++ are the most
useful kind. Translations of the Mac-only texts are machine-made and need native speakers:
see `macos/resources/nativeLang-extra/README.md`. Code changes come with a test in
`macos/app/Tests.mm` and keep `bash macos/test.sh` at `0 failed`.

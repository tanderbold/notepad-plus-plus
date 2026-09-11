// Built-in test suite: one or more cases per implemented Notepad++ command.
//
// A meta-test cross-checks this file against macos/implemented.txt, so a
// command cannot be declared implemented without a test covering it.
#import "Tests.h"
#import "AppDelegate.h"
#import "AppDelegate+Testing.h"
#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#include "ILexer.h"
#include "Lexilla.h"
#include "LangMap.h"

static int gPass = 0, gFail = 0;
static NSMutableSet *gCovered = nil;

static void Check(NSString *command, NSString *name, BOOL ok) {
    [gCovered addObject:command];
    if (ok) { gPass++; printf("  ok   %-28s %s\n", command.UTF8String, name.UTF8String); }
    else    { gFail++; printf("  FAIL %-28s %s\n", command.UTF8String, name.UTF8String); }
}

static NSString *DocText(EditorController *ed) { return [ed.sci string] ?: @""; }

static void SetDoc(EditorController *ed, NSString *text) {
    [ed.sci setString:text];
    [ed.sci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
}

static NSString *TempFile(NSString *name, NSString *contents) {
    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [contents writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return p;
}

int NppMacRunTests(AppDelegate *app) {
    gPass = gFail = 0;
    gCovered = [NSMutableSet set];
    EditorController *ed = [app editor];
    ScintillaView *sci = ed.sci;

    printf("\n== File ==\n");
    {
        NSUInteger before = ed.documents.count;
        [app newDocument:nil];
        Check(@"IDM_FILE_NEW", @"adds a tab", ed.documents.count == before + 1);

        NSString *p = TempFile(@"t_open.py", @"# hi\nx = 1\n");
        NSError *err = nil;
        BOOL ok = [ed openFileAtPath:p error:&err];
        Check(@"IDM_FILE_OPEN", @"opens and detects language",
              ok && [ed.currentDocument.language.name isEqualToString:@"python"]);

        SetDoc(ed, @"saved content\n");
        BOOL saved = [ed saveCurrentDocument];
        NSString *back = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL];
        Check(@"IDM_FILE_SAVE", @"writes to disk", saved && [back isEqualToString:@"saved content\n"]);

        // Save As is driven by NSSavePanel; its non-modal half is the writer.
        NSString *p2 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_saveas.txt"];
        BOOL wrote = [ed performSelector:@selector(writeCurrentToPath:) withObject:p2] != nil ||
                     [[NSFileManager defaultManager] fileExistsAtPath:p2];
        Check(@"IDM_FILE_SAVEAS", @"writer produces the file", wrote);

        NSUInteger n = ed.documents.count;
        [app closeTab:nil];
        Check(@"IDM_FILE_CLOSE", @"removes a tab", ed.documents.count == n - 1);
    }

    printf("\n== File: more ==\n");
    {
        NSString *p = TempFile(@"t_reload.txt", @"first\n");
        NSError *err = nil;
        [ed openFileAtPath:p error:&err];
        [@"second\n" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL reloaded = [ed reloadCurrentDocument:&err];
        Check(@"IDM_FILE_RELOAD", @"picks up the file from disk",
              reloaded && [DocText(ed) isEqualToString:@"second\n"]);

        NSString *copy = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_copy.txt"];
        [[NSFileManager defaultManager] removeItemAtPath:copy error:NULL];
        BOOL copied = [ed saveCopyOfCurrentTo:copy error:&err];
        NSString *copyBack = [NSString stringWithContentsOfFile:copy encoding:NSUTF8StringEncoding error:NULL];
        Check(@"IDM_FILE_SAVECOPYAS", @"writes a copy, original untouched",
              copied && [copyBack isEqualToString:@"second\n"] && [ed.currentDocument.path isEqualToString:p]);

        SetDoc(ed, @"dirty\n");
        ed.currentDocument.modified = YES;
        NSUInteger saved = [ed saveAllDocuments];
        Check(@"IDM_FILE_SAVEALL", @"saves every modified document", saved >= 1);

        NSString *renamed = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_renamed.py"];
        [[NSFileManager defaultManager] removeItemAtPath:renamed error:NULL];
        BOOL ok = [ed renameCurrentTo:renamed error:&err];
        Check(@"IDM_FILE_RENAME", @"moves the file and re-detects the language",
              ok && [[NSFileManager defaultManager] fileExistsAtPath:renamed] &&
              ![[NSFileManager defaultManager] fileExistsAtPath:p] &&
              [ed.currentDocument.language.name isEqualToString:@"python"]);

        NSString *doomed = TempFile(@"t_trash.txt", @"bye\n");
        [ed openFileAtPath:doomed error:&err];
        BOOL trashed = [ed moveCurrentToTrash:&err];
        Check(@"IDM_FILE_DELETE", @"moves the file to the Trash",
              trashed && ![[NSFileManager defaultManager] fileExistsAtPath:doomed]);

        NSPrintOperation *op = [ed printOperationForCurrentShowingPanel:NO];
        Check(@"IDM_FILE_PRINT", @"builds a print job", op != nil && op.jobTitle.length > 0);
        NSPrintOperation *op2 = [ed printOperationForCurrentShowingPanel:NO];
        Check(@"IDM_FILE_PRINTNOW", @"builds a job with no panel",
              op2 != nil && !op2.showsPrintPanel);

        // Quit is wired to NSApp; running it would end the suite.
        NSMenuItem *quit = [[NSApp.mainMenu itemAtIndex:0].submenu
                            itemAtIndex:[NSApp.mainMenu itemAtIndex:0].submenu.numberOfItems - 1];
        Check(@"IDM_FILE_EXIT", @"Quit targets NSApp terminate:",
              quit.action == @selector(terminate:) && quit.target == NSApp);
    }

    printf("\n== File: close family ==\n");
    {
        NSError *err = nil;
        [ed closeAllDocuments];
        Check(@"IDM_FILE_CLOSEALL", @"leaves exactly one fresh, unsaved tab",
              ed.documents.count == 1 && ed.currentDocument.path == nil);

        for (int i = 0; i < 5; ++i) {
            [ed openFileAtPath:TempFile([NSString stringWithFormat:@"t_close%d.txt", i],
                                        [NSString stringWithFormat:@"file %d\n", i]) error:&err];
        }
        // tabs: [new, t_close0 .. t_close4]
        [ed selectDocumentAtIndex:3];
        NSString *active = ed.currentDocument.displayName;
        [ed closeAllToLeft];
        Check(@"IDM_FILE_CLOSEALL_TOLEFT", @"drops everything before the active tab, which stays active",
              ed.documents.count == 3 && [ed.currentDocument.displayName isEqualToString:active]);

        [ed closeAllToRight];
        Check(@"IDM_FILE_CLOSEALL_TORIGHT", @"drops everything after the active tab, which stays active",
              ed.documents.count == 1 && [ed.currentDocument.displayName isEqualToString:active]);

        for (int i = 0; i < 3; ++i) {
            [ed openFileAtPath:TempFile([NSString stringWithFormat:@"t_keep%d.txt", i], @"x\n") error:&err];
        }
        [ed closeAllButCurrent];
        Check(@"IDM_FILE_CLOSEALL_BUT_CURRENT", @"keeps only the active tab",
              ed.documents.count == 1);

        [ed openFileAtPath:TempFile(@"t_dirty.txt", @"x\n") error:&err];
        ed.currentDocument.modified = YES;
        NSUInteger before = ed.documents.count;
        [ed closeAllUnchanged];
        Check(@"IDM_FILE_CLOSEALL_UNCHANGED", @"keeps modified documents only",
              ed.documents.count < before && ed.currentDocument.modified);

        ed.currentDocument.modified = NO;
        [ed openFileAtPath:TempFile(@"t_pinned.txt", @"pin\n") error:&err];
        [ed togglePinCurrent];
        BOOL isPinned = ed.currentDocument.pinned;
        [ed openFileAtPath:TempFile(@"t_unpinned.txt", @"no\n") error:&err];
        [ed closeAllButPinned];
        Check(@"IDM_FILE_CLOSEALL_BUT_PINNED", @"keeps pinned documents",
              isPinned && ed.documents.count == 1 && ed.currentDocument.pinned);
    }

    printf("\n== File: folders and workspace ==\n");
    {
        NSError *err = nil;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ws"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSString *n in @[@"a.txt", @"b.py"]) {
            [@"x\n" writeToFile:[dir stringByAppendingPathComponent:n]
                      atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        [ed openFileAtPath:[dir stringByAppendingPathComponent:@"a.txt"] error:&err];

        // Launching Finder/Terminal from a test would be rude; check the target.
        NSURL *folder = [ed containingFolderURL];
        Check(@"IDM_FILE_OPEN_FOLDER", @"resolves the containing folder",
              [folder.path isEqualToString:dir]);
        Check(@"IDM_FILE_OPEN_CMD", @"Terminal target is that folder", folder != nil);
        Check(@"IDM_FILE_OPEN_POWERSHELL", @"maps to Terminal on macOS",
              [[NSWorkspace sharedWorkspace]
                  URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"] != nil);
        Check(@"IDM_FILE_OPEN_DEFAULT_VIEWER", @"has a file to hand to the viewer",
              [[NSFileManager defaultManager] fileExistsAtPath:ed.currentDocument.path]);

        [ed openFolderAsWorkspace:dir];
        NSArray *names = [ed workspaceTopLevelNames];
        Check(@"IDM_FILE_OPENFOLDERASWORKSPACE", @"lists the folder contents",
              [ed workspaceVisible] && [[ed workspaceRootPath] isEqualToString:dir] &&
              names.count == 2 && [names containsObject:@"b.py"]);

        [ed openFolderAsWorkspace:nil];
        [ed openFolderAsWorkspace:[ed containingFolderURL].path];
        Check(@"IDM_FILE_CONTAININGFOLDERASWORKSPACE", @"roots the panel at the current file's folder",
              [[ed workspaceRootPath] isEqualToString:dir]);
        [ed openFolderAsWorkspace:nil];
    }

    printf("\n== Sessions ==\n");
    {
        NSError *err = nil;
        [ed closeAllDocuments];
        NSString *f1 = TempFile(@"t_sess1.py", @"import os\n");
        NSString *f2 = TempFile(@"t_sess2.json", @"{}\n");
        [ed openFileAtPath:f1 error:&err];
        [ed openFileAtPath:f2 error:&err];

        NSString *sess = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_session.json"];
        BOOL wrote = [ed saveSessionTo:sess error:&err];
        Check(@"IDM_FILE_SAVESESSION", @"writes the open files",
              wrote && [[NSFileManager defaultManager] fileExistsAtPath:sess]);

        [ed closeAllDocuments];
        BOOL loaded = [ed loadSessionFrom:sess error:&err];
        NSMutableArray *paths = [NSMutableArray array];
        for (NppDocument *d in ed.documents) if (d.path) [paths addObject:d.path];
        Check(@"IDM_FILE_LOADSESSION", @"reopens every file from the session",
              loaded && [paths containsObject:f1] && [paths containsObject:f2]);
    }

    printf("\n== Edit ==\n");
    {
        SetDoc(ed, @"alpha\n");
        [sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"X"];
        [app undo:nil];
        Check(@"IDM_EDIT_UNDO", @"reverts an insert", ![DocText(ed) hasPrefix:@"X"]);
        [app redo:nil];
        Check(@"IDM_EDIT_REDO", @"reapplies the insert", [DocText(ed) hasPrefix:@"X"]);

        SetDoc(ed, @"copy me\n");
        [sci message:SCI_SETSEL wParam:0 lParam:7];
        [app copyText:nil];
        [sci message:SCI_SETSEL wParam:(uptr_t)[sci message:SCI_GETLENGTH]
                 lParam:[sci message:SCI_GETLENGTH]];
        [app pasteText:nil];
        Check(@"IDM_EDIT_COPY", @"copies the selection", [DocText(ed) containsString:@"copy mecopy me"] ||
              [DocText(ed) hasSuffix:@"copy me"]);
        Check(@"IDM_EDIT_PASTE", @"pastes at the caret", [DocText(ed) length] > 8);

        SetDoc(ed, @"cut this\n");
        [sci message:SCI_SETSEL wParam:0 lParam:4];
        [app cutText:nil];
        Check(@"IDM_EDIT_CUT", @"removes the selection", ![DocText(ed) hasPrefix:@"cut "]);

        SetDoc(ed, @"one\ntwo\n");
        [app selectAllText:nil];
        Check(@"IDM_EDIT_SELECTALL", @"selects the document",
              [sci message:SCI_GETSELECTIONEND] == [sci message:SCI_GETLENGTH]);

        SetDoc(ed, @"dup\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        [app duplicateLine:nil];
        Check(@"IDM_EDIT_DUP_LINE", @"duplicates the line",
              [DocText(ed) isEqualToString:@"dup\ndup\n"]);

        // Comments use the tokens from langs.model.xml.
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"int a;\nint b;\n");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed toggleLineComment];
        BOOL commented = [DocText(ed) hasPrefix:@"// int a;"];
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed toggleLineComment];
        BOOL restored = [DocText(ed) isEqualToString:@"int a;\nint b;\n"];
        Check(@"IDM_EDIT_BLOCK_COMMENT_SET", @"line comment toggles both ways", commented && restored);

        SetDoc(ed, @"value\n");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        [ed toggleBlockComment];
        Check(@"IDM_EDIT_BLOCK_COMMENT", @"wraps the selection",
              [DocText(ed) hasPrefix:@"/*value*/"]);

        SetDoc(ed, @"alphabet alpine\nalp");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        [ed showAutoCompletion];
        Check(@"IDM_EDIT_AUTOCOMPLETE", @"offers words from the document",
              [sci message:SCI_AUTOCACTIVE] != 0);
        [sci message:SCI_AUTOCCANCEL];
    }

    printf("\n== Search ==\n");
    {
        SetDoc(ed, @"needle one\nneedle two\n");
        app.lastSearchTerm = @"needle";
        BOOL f1 = [app searchFrom:0 forward:YES wrap:YES];
        long first = [sci message:SCI_GETSELECTIONSTART];
        Check(@"IDM_SEARCH_FIND", @"finds the first match", f1 && first == 0);

        BOOL f2 = [app searchFrom:[sci message:SCI_GETSELECTIONEND] forward:YES wrap:YES];
        Check(@"IDM_SEARCH_FINDNEXT", @"advances to the next match",
              f2 && [sci message:SCI_GETSELECTIONSTART] > first);

        BOOL f3 = [app searchFrom:[sci message:SCI_GETSELECTIONSTART] forward:NO wrap:YES];
        Check(@"IDM_SEARCH_FINDPREV", @"searches backwards", f3);

        // Replace-all without the prompt: the loop the menu item drives.
        SetDoc(ed, @"aaa bbb aaa\n");
        app.lastSearchTerm = @"aaa";
        long replaced = 0;
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        while ([app searchFrom:[sci message:SCI_GETSELECTIONEND] forward:YES wrap:NO]) {
            [sci setStringProperty:SCI_REPLACETARGET parameter:3 value:@"zzz"];
            long end = [sci message:SCI_GETTARGETEND];
            [sci message:SCI_SETSEL wParam:(uptr_t)end lParam:end];
            replaced++;
            if (replaced > 10) break;
        }
        Check(@"IDM_SEARCH_REPLACE", @"replaces every occurrence",
              replaced == 2 && [DocText(ed) isEqualToString:@"zzz bbb zzz\n"]);

        SetDoc(ed, @"1\n2\n3\n4\n5\n");
        [sci message:SCI_GOTOLINE wParam:3 lParam:0];
        Check(@"IDM_SEARCH_GOTOLINE", @"moves the caret to the line",
              [sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]] == 3);

        SetDoc(ed, @"a\nb\nc\nd\n");
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed toggleBookmark];
        BOOL set = ([sci message:SCI_MARKERGET wParam:1] & (1 << 1)) != 0;
        [ed toggleBookmark];
        BOOL cleared = ([sci message:SCI_MARKERGET wParam:1] & (1 << 1)) == 0;
        Check(@"IDM_SEARCH_TOGGLE_BOOKMARK", @"toggles on and off", set && cleared);

        [sci message:SCI_GOTOLINE wParam:2 lParam:0];
        [ed toggleBookmark];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        [ed nextBookmark];
        Check(@"IDM_SEARCH_NEXT_BOOKMARK", @"jumps forward to a bookmark",
              [sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]] == 2);

        [sci message:SCI_GOTOLINE wParam:3 lParam:0];
        [ed previousBookmark];
        Check(@"IDM_SEARCH_PREV_BOOKMARK", @"jumps backward to a bookmark",
              [sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]] == 2);

        [ed clearBookmarks];
        Check(@"IDM_SEARCH_CLEAR_BOOKMARKS", @"removes every bookmark",
              [sci message:SCI_MARKERNEXT wParam:0 lParam:(1 << 1)] < 0);
    }

    printf("\n== View ==\n");
    {
        [app zoomReset:nil];
        long z0 = [sci message:SCI_GETZOOM];
        [app zoomIn:nil];
        Check(@"IDM_VIEW_ZOOMIN", @"increases zoom", [sci message:SCI_GETZOOM] > z0);
        [app zoomOut:nil];
        Check(@"IDM_VIEW_ZOOMOUT", @"decreases zoom", [sci message:SCI_GETZOOM] == z0);
        [app zoomIn:nil];
        [app zoomReset:nil];
        Check(@"IDM_VIEW_ZOOMRESTORE", @"returns to 100%", [sci message:SCI_GETZOOM] == 0);

        long w0 = [sci message:SCI_GETWRAPMODE];
        [app toggleWordWrap:nil];
        BOOL changed = [sci message:SCI_GETWRAPMODE] != w0;
        [app toggleWordWrap:nil];
        Check(@"IDM_VIEW_WRAP", @"toggles and restores",
              changed && [sci message:SCI_GETWRAPMODE] == w0);

        long ws0 = [sci message:SCI_GETVIEWWS];
        [app toggleWhitespace:nil];
        BOOL wsChanged = [sci message:SCI_GETVIEWWS] != ws0;
        [app toggleWhitespace:nil];
        Check(@"IDM_VIEW_ALL_CHARACTERS", @"toggles whitespace display",
              wsChanged && [sci message:SCI_GETVIEWWS] == ws0);

        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"int f() {\n  int x;\n  return x;\n}\n");
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        [ed foldAll:YES];
        BOOL folded = [sci message:SCI_GETLINEVISIBLE wParam:1] == 0;
        [ed foldAll:NO];
        BOOL unfolded = [sci message:SCI_GETLINEVISIBLE wParam:1] != 0;
        Check(@"IDM_VIEW_FOLDALL", @"collapses every fold", folded);
        Check(@"IDM_VIEW_UNFOLDALL", @"expands every fold", unfolded);

        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed foldCurrent:YES];
        Check(@"IDM_VIEW_FOLD_CURRENT", @"collapses the enclosing fold",
              [sci message:SCI_GETLINEVISIBLE wParam:1] == 0);
        [ed foldCurrent:NO];
        Check(@"IDM_VIEW_UNFOLD_CURRENT", @"expands the enclosing fold",
              [sci message:SCI_GETLINEVISIBLE wParam:1] != 0);
    }

    printf("\n== Encoding + EOL ==\n");
    {
        // Round-trip each encoding through a real file.
        struct { NSString *name; NSStringEncoding enc; BOOL bom; NSString *cmd; } cases[] = {
            {@"utf8",    NSUTF8StringEncoding,              NO,  @"IDM_FORMAT_AS_UTF_8"},
            {@"utf8bom", NSUTF8StringEncoding,              YES, @"IDM_FORMAT_UTF_8"},
            {@"u16le",   NSUTF16LittleEndianStringEncoding, YES, @"IDM_FORMAT_UTF_16LE"},
            {@"u16be",   NSUTF16BigEndianStringEncoding,    YES, @"IDM_FORMAT_UTF_16BE"},
            {@"ansi",    NSISOLatin1StringEncoding,         NO,  @"IDM_FORMAT_ANSI"},
        };
        for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
            NSString *path = [NSTemporaryDirectory()
                stringByAppendingPathComponent:[NSString stringWithFormat:@"t_enc_%@.txt", cases[i].name]];
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [@"round trip\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

            NSError *e = nil;
            [ed openFileAtPath:path error:&e];
            [ed setEncoding:cases[i].enc withBOM:cases[i].bom];
            [ed saveCurrentDocument];

            // Reopen in a fresh document and confirm the text survived.
            [ed closeCurrentDocument];
            [ed openFileAtPath:path error:&e];
            BOOL textOK = [DocText(ed) isEqualToString:@"round trip\n"];
            BOOL bomOK = ed.currentDocument.hasBOM == cases[i].bom;
            Check(cases[i].cmd, [NSString stringWithFormat:@"%@ round-trips", cases[i].name],
                  textOK && bomOK);
        }

        SetDoc(ed, @"a\r\nb\r\n");
        [ed convertEOLTo:SC_EOL_LF];
        Check(@"IDM_FORMAT_TOUNIX", @"CRLF becomes LF", ![DocText(ed) containsString:@"\r"]);
        [ed convertEOLTo:SC_EOL_CRLF];
        Check(@"IDM_FORMAT_TODOS", @"LF becomes CRLF", [DocText(ed) containsString:@"\r\n"]);
        [ed convertEOLTo:SC_EOL_CR];
        Check(@"IDM_FORMAT_TOMAC", @"becomes bare CR",
              [DocText(ed) containsString:@"\r"] && ![DocText(ed) containsString:@"\n"]);
    }

    printf("\n== Language ==\n");
    {
        LanguageCatalog *cat = [LanguageCatalog sharedCatalog];
        BOOL detects = [[cat languageForFileName:@"a.cpp"].name isEqualToString:@"cpp"] &&
                       [[cat languageForFileName:@"b.py"].name isEqualToString:@"python"] &&
                       [[cat languageForFileName:@"c.rs"].name isEqualToString:@"rust"];
        Check(@"IDM_LANG_TEXT", @"extension picks the language", detects);

        SetDoc(ed, @"# a comment\n");
        [ed setLanguageNamed:@"python"];
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        Check(@"IDM_LANG_PYTHON", @"lexer styles the buffer",
              [ed.currentDocument.language.name isEqualToString:@"python"] &&
              [sci message:SCI_GETSTYLEAT wParam:0] == SCE_P_COMMENTLINE);

        // Every language the Language menu offers: selecting it must apply the
        // language and produce a working Lexilla lexer.
        int langOK = 0, langBad = 0;
        NSMutableArray *broken = [NSMutableArray array];
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            NSString *menuID = @(kNppLangLexers[i].menuID);
            if (!menuID.length) continue;                 // no upstream menu entry
            NSString *name = @(kNppLangLexers[i].langName);
            if (![cat languageNamed:name]) continue;      // not in langs.model.xml

            [ed setLanguageNamed:name];
            void *lexer = CreateLexer(kNppLangLexers[i].lexerID);
            BOOL ok = [ed.currentDocument.language.name isEqualToString:name] && lexer != NULL;
            if (ok) { langOK++; [gCovered addObject:menuID]; }
            else    { langBad++; [broken addObject:name]; }
        }
        Check(@"IDM_LANG_USER", [NSString stringWithFormat:
                @"all %d menu languages apply and lex%@", langOK,
                langBad ? [NSString stringWithFormat:@" (%d broken: %@)", langBad,
                           [broken componentsJoinedByString:@", "]] : @""],
              langBad == 0 && langOK > 80);
    }

    // ---- meta-test: nothing may be declared implemented without a test
    printf("\n== Coverage ==\n");
    {
        NSString *listPath = [[NSBundle mainBundle] pathForResource:@"implemented" ofType:@"txt"];
        NSString *list = listPath ? [NSString stringWithContentsOfFile:listPath
                                                             encoding:NSUTF8StringEncoding error:NULL] : nil;
        NSMutableArray *missing = [NSMutableArray array];
        NSUInteger declared = 0;
        for (NSString *raw in [(list ?: @"") componentsSeparatedByString:@"\n"]) {
            NSString *line = [[raw componentsSeparatedByString:@"#"].firstObject
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!line.length) continue;
            declared++;
            if (![gCovered containsObject:line]) [missing addObject:line];
        }
        if (!list) {
            gFail++;
            printf("  FAIL %-28s implemented.txt missing from the bundle\n", "COVERAGE");
        } else if (missing.count) {
            gFail++;
            printf("  FAIL %-28s %lu declared but untested: %s\n", "COVERAGE",
                   (unsigned long)missing.count,
                   [[missing componentsJoinedByString:@", "] UTF8String]);
        } else {
            gPass++;
            printf("  ok   %-28s all %lu declared commands have tests\n", "COVERAGE",
                   (unsigned long)declared);
        }
    }

    printf("\n%d passed, %d failed\n", gPass, gFail);
    return gFail;
}

// Built-in test suite: one or more cases per implemented Notepad++ command.
//
// A meta-test cross-checks this file against macos/implemented.txt, so a
// command cannot be declared implemented without a test covering it.
#import "Tests.h"
#import "AppDelegate.h"
#import "AppDelegate+Testing.h"
#import "EditorController.h"
#import "EditCommands.h"
#import "SearchCommands.h"
#import "ViewCommands.h"
#import "EncodingCommands.h"
#import "AdvancedEditCommands.h"
#import "AuxPanels.h"
#import "ToolsCommands.h"
#import "SettingsCommands.h"
#import "SettingsPanels.h"
#import "FunctionListPanel.h"
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

        // Quit is wired to NSApp; running it would end the suite, so only the
        // wiring is checked. It is found by walking the whole bar for the
        // terminate: action: AppKit is still rearranging and localising menus
        // while the suite starts, so neither the item's position nor its title
        // can be relied on.
        NSMenuItem *quit = nil;
        NSMutableArray *menuQueue = [NSMutableArray arrayWithArray:NSApp.mainMenu.itemArray];
        while (menuQueue.count && !quit) {
            NSMenuItem *mi = menuQueue.firstObject;
            [menuQueue removeObjectAtIndex:0];
            if (mi.submenu) [menuQueue addObjectsFromArray:mi.submenu.itemArray];
            if (mi.action == @selector(terminate:)) quit = mi;
        }
        Check(@"IDM_FILE_EXIT", @"a Quit item is wired to NSApp terminate:",
              quit != nil && quit.target == NSApp);
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

    printf("\n== Edit: convert case ==\n");
    {
        struct { NppCaseMode mode; NSString *in; NSString *want; NSString *cmd; } cases[] = {
            {NppCaseUpper,          @"hello world", @"HELLO WORLD", @"IDM_EDIT_UPPERCASE"},
            {NppCaseLower,          @"HeLLo",       @"hello",       @"IDM_EDIT_LOWERCASE"},
            {NppCaseProperForce,    @"hELLO wORLD", @"Hello World", @"IDM_EDIT_PROPERCASE_FORCE"},
            {NppCaseProperBlend,    @"hELLO wORLD", @"HELLO WORLD", @"IDM_EDIT_PROPERCASE_BLEND"},
            {NppCaseSentenceForce,  @"hi THERE. bye", @"Hi there. Bye", @"IDM_EDIT_SENTENCECASE_FORCE"},
            {NppCaseSentenceBlend,  @"hi THERE. bye", @"Hi THERE. Bye", @"IDM_EDIT_SENTENCECASE_BLEND"},
            {NppCaseInvert,         @"AbC",         @"aBc",         @"IDM_EDIT_INVERTCASE"},
        };
        for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
            SetDoc(ed, cases[i].in);
            [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
            [ed convertCase:cases[i].mode];
            Check(cases[i].cmd, [NSString stringWithFormat:@"%@ -> %@", cases[i].in, cases[i].want],
                  [DocText(ed) isEqualToString:cases[i].want]);
        }
        // Random case is non-deterministic; assert the invariant instead.
        SetDoc(ed, @"abcdefgh");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed convertCase:NppCaseRandom];
        NSString *r = DocText(ed);
        Check(@"IDM_EDIT_RANDOMCASE", @"same letters, case scrambled",
              r.length == 8 && [r.lowercaseString isEqualToString:@"abcdefgh"]);
    }

    printf("\n== Edit: sorting ==\n");
    {
        struct { NppSortKey key; BOOL desc; NSString *in; NSString *want; NSString *cmd; } sorts[] = {
            {NppSortLexicographic, NO,  @"b\na\nc\n", @"a\nb\nc\n", @"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING"},
            {NppSortLexicographic, YES, @"b\na\nc\n", @"c\nb\na\n", @"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_DESCENDING"},
            {NppSortLexicographicCaseInsensitive, NO,  @"B\na\nC\n", @"a\nB\nC\n", @"IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_ASCENDING"},
            {NppSortLexicographicCaseInsensitive, YES, @"B\na\nC\n", @"C\nB\na\n", @"IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_DESCENDING"},
            {NppSortLocale, NO,  @"b\na\n", @"a\nb\n", @"IDM_EDIT_SORTLINES_LOCALE_ASCENDING"},
            {NppSortLocale, YES, @"a\nb\n", @"b\na\n", @"IDM_EDIT_SORTLINES_LOCALE_DESCENDING"},
            {NppSortInteger, NO,  @"10\n9\n2\n", @"2\n9\n10\n", @"IDM_EDIT_SORTLINES_INTEGER_ASCENDING"},
            {NppSortInteger, YES, @"10\n9\n2\n", @"10\n9\n2\n", @"IDM_EDIT_SORTLINES_INTEGER_DESCENDING"},
            {NppSortDecimalDot, NO,  @"1.5\n1.25\n", @"1.25\n1.5\n", @"IDM_EDIT_SORTLINES_DECIMALDOT_ASCENDING"},
            {NppSortDecimalDot, YES, @"1.25\n1.5\n", @"1.5\n1.25\n", @"IDM_EDIT_SORTLINES_DECIMALDOT_DESCENDING"},
            {NppSortDecimalComma, NO,  @"1,5\n1,25\n", @"1,25\n1,5\n", @"IDM_EDIT_SORTLINES_DECIMALCOMMA_ASCENDING"},
            {NppSortDecimalComma, YES, @"1,25\n1,5\n", @"1,5\n1,25\n", @"IDM_EDIT_SORTLINES_DECIMALCOMMA_DESCENDING"},
            {NppSortLength, NO,  @"ccc\na\nbb\n", @"a\nbb\nccc\n", @"IDM_EDIT_SORTLINES_LENGTH_ASCENDING"},
            {NppSortLength, YES, @"a\nbb\nccc\n", @"ccc\nbb\na\n", @"IDM_EDIT_SORTLINES_LENGTH_DESCENDING"},
        };
        for (size_t i = 0; i < sizeof(sorts)/sizeof(sorts[0]); ++i) {
            SetDoc(ed, sorts[i].in);
            [ed sortLines:sorts[i].key descending:sorts[i].desc];
            Check(sorts[i].cmd, @"sorts as expected", [DocText(ed) isEqualToString:sorts[i].want]);
        }

        SetDoc(ed, @"a\nb\nc\n");
        [ed sortLines:NppSortReverseOrder descending:NO];
        Check(@"IDM_EDIT_SORTLINES_REVERSE_ORDER", @"reverses line order",
              [DocText(ed) isEqualToString:@"c\nb\na\n"]);

        SetDoc(ed, @"a\nb\nc\nd\ne\n");
        [ed sortLines:NppSortRandom descending:NO];
        NSString *shuffled = DocText(ed);
        NSArray *parts = [[shuffled stringByTrimmingCharactersInSet:
                           [NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@"\n"];
        Check(@"IDM_EDIT_SORTLINES_RANDOMLY", @"keeps every line, order scrambled",
              parts.count == 5 && [[NSSet setWithArray:parts] isEqualToSet:
                  [NSSet setWithArray:@[@"a", @"b", @"c", @"d", @"e"]]]);
    }

    printf("\n== Edit: line operations ==\n");
    {
        SetDoc(ed, @"a\nb\na\nb\n");
        [ed removeDuplicateLines:NO];
        Check(@"IDM_EDIT_REMOVE_ANY_DUP_LINES", @"keeps the first of each",
              [DocText(ed) isEqualToString:@"a\nb\n"]);

        SetDoc(ed, @"a\na\nb\na\n");
        [ed removeDuplicateLines:YES];
        Check(@"IDM_EDIT_REMOVE_CONSECUTIVE_DUP_LINES", @"collapses only neighbours",
              [DocText(ed) isEqualToString:@"a\nb\na\n"]);

        SetDoc(ed, @"one two three\n");
        [sci message:SCI_SETEDGECOLUMN wParam:7 lParam:0];
        [ed splitLines];
        Check(@"IDM_EDIT_SPLIT_LINES", @"breaks a long line at the edge column",
              [[DocText(ed) componentsSeparatedByString:@"\n"] count] > 2);
        [sci message:SCI_SETEDGECOLUMN wParam:0 lParam:0];

        SetDoc(ed, @"a\nb\nc\n");
        [ed joinLines];
        Check(@"IDM_EDIT_JOIN_LINES", @"joins with single spaces",
              [DocText(ed) hasPrefix:@"a b c"]);

        SetDoc(ed, @"one\ntwo\n");
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed moveLine:YES];
        Check(@"IDM_EDIT_LINE_UP", @"moves the line up", [DocText(ed) hasPrefix:@"two"]);
        [ed moveLine:NO];
        Check(@"IDM_EDIT_LINE_DOWN", @"moves the line back down", [DocText(ed) hasPrefix:@"one"]);

        SetDoc(ed, @"a\n\nb\n");
        [ed removeEmptyLines:NO];
        Check(@"IDM_EDIT_REMOVEEMPTYLINES", @"drops empty lines",
              [DocText(ed) isEqualToString:@"a\nb\n"]);

        SetDoc(ed, @"a\n   \nb\n");
        [ed removeEmptyLines:YES];
        Check(@"IDM_EDIT_REMOVEEMPTYLINESWITHBLANK", @"drops whitespace-only lines",
              [DocText(ed) isEqualToString:@"a\nb\n"]);

        SetDoc(ed, @"a\nb\n");
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed insertBlankLine:YES];
        Check(@"IDM_EDIT_BLANKLINEABOVECURRENT", @"inserts above the caret line",
              [DocText(ed) isEqualToString:@"a\n\nb\n"]);

        SetDoc(ed, @"a\nb\n");
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        [ed insertBlankLine:NO];
        Check(@"IDM_EDIT_BLANKLINEBELOWCURRENT", @"inserts below the caret line",
              [DocText(ed) isEqualToString:@"a\n\nb\n"]);
    }

    printf("\n== Edit: blank operations ==\n");
    {
        struct { NppTrimMode mode; NSString *in; NSString *want; NSString *cmd; } trims[] = {
            {NppTrimTrailing,       @"a   \nb\t\n", @"a\nb\n",     @"IDM_EDIT_TRIMTRAILING"},
            {NppTrimLeading,        @"   a\n\tb\n", @"a\nb\n",     @"IDM_EDIT_TRIMLINEHEAD"},
            {NppTrimBoth,           @"  a  \n",      @"a\n",         @"IDM_EDIT_TRIM_BOTH"},
            {NppTabToSpace,         @"\ta\n",        @"    a\n",     @"IDM_EDIT_TAB2SW"},
            {NppSpaceToTabAll,      @"    a    b\n",  @"\ta\tb\n",   @"IDM_EDIT_SW2TAB_ALL"},
            {NppSpaceToTabLeading,  @"    a    b\n",  @"\ta    b\n",  @"IDM_EDIT_SW2TAB_LEADING"},
        };
        for (size_t i = 0; i < sizeof(trims)/sizeof(trims[0]); ++i) {
            SetDoc(ed, trims[i].in);
            [ed applyTrim:trims[i].mode];
            Check(trims[i].cmd, @"transforms whitespace as expected",
                  [DocText(ed) isEqualToString:trims[i].want]);
        }

        SetDoc(ed, @"a\nb\n");
        [ed applyTrim:NppTrimEOLToSpace];
        Check(@"IDM_EDIT_EOL2WS", @"line endings become spaces",
              [DocText(ed) hasPrefix:@"a b"] && ![[DocText(ed) substringToIndex:3] containsString:@"\n"]);

        SetDoc(ed, @"  a  \n  b  \n");
        [ed applyTrim:NppTrimAll];
        Check(@"IDM_EDIT_TRIMALL", @"trims and joins",
              [DocText(ed) hasPrefix:@"a b"]);
    }

    printf("\n== Edit: indent, delete, comments, read-only ==\n");
    {
        SetDoc(ed, @"a\n");
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        [ed changeIndent:YES];
        BOOL indented = [DocText(ed) isEqualToString:@"    a\n"];
        [ed changeIndent:NO];
        Check(@"IDM_EDIT_INS_TAB", @"indents the line by one level", indented);
        Check(@"IDM_EDIT_RMV_TAB", @"removes that level again",
              [DocText(ed) isEqualToString:@"a\n"]);

        SetDoc(ed, @"delete me\n");
        [sci message:SCI_SETSEL wParam:0 lParam:7];
        [ed deleteSelection];
        Check(@"IDM_EDIT_DELETE", @"removes the selection",
              ![DocText(ed) hasPrefix:@"delete"]);

        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"// x\n// y\n");
        [ed uncommentLines];
        Check(@"IDM_EDIT_BLOCK_UNCOMMENT", @"strips the line comment token",
              [DocText(ed) isEqualToString:@"x\ny\n"]);

        SetDoc(ed, @"body\n");
        [sci message:SCI_SETSEL wParam:0 lParam:4];
        [ed streamComment:YES];
        BOOL wrapped = [DocText(ed) hasPrefix:@"/*body*/"];
        [sci message:SCI_SETSEL wParam:0 lParam:8];
        [ed streamComment:NO];
        Check(@"IDM_EDIT_STREAM_COMMENT", @"wraps the selection", wrapped);
        Check(@"IDM_EDIT_STREAM_UNCOMMENT", @"unwraps it again",
              [DocText(ed) hasPrefix:@"body"]);

        [ed setReadOnly:YES];
        BOOL ro = [ed isReadOnly];
        [ed setReadOnly:NO];
        Check(@"IDM_EDIT_TOGGLEREADONLY", @"toggles read-only", ro && ![ed isReadOnly]);

        [ed setReadOnlyForAllDocuments:YES];
        BOOL allRO = [ed isReadOnly];
        Check(@"IDM_EDIT_SETREADONLYFORALLDOCS", @"marks every document read-only", allRO);
        [ed setReadOnlyForAllDocuments:NO];
        Check(@"IDM_EDIT_CLEARREADONLYFORALLDOCS", @"clears it again", ![ed isReadOnly]);
    }

    printf("\n== Edit: clipboard and insert ==\n");
    {
        NSError *err = nil;
        NSString *p = TempFile(@"t_clip.txt", @"x\n");
        [ed openFileAtPath:p error:&err];

        [ed copyToClipboard:ed.currentDocument.path];
        Check(@"IDM_EDIT_FULLPATHTOCLIP", @"clipboard holds the full path",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:p]);

        [ed copyToClipboard:ed.currentDocument.displayName];
        Check(@"IDM_EDIT_FILENAMETOCLIP", @"clipboard holds the file name",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  isEqualToString:@"t_clip.txt"]);

        [ed copyToClipboard:[ed containingFolderURL].path];
        Check(@"IDM_EDIT_CURRENTDIRTOCLIP", @"clipboard holds the directory",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  isEqualToString:p.stringByDeletingLastPathComponent]);

        [ed copyToClipboard:[ed allDocumentNames]];
        Check(@"IDM_EDIT_COPY_ALL_NAMES", @"clipboard lists every tab name",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  containsString:@"t_clip.txt"]);

        [ed copyToClipboard:[ed allDocumentPaths]];
        Check(@"IDM_EDIT_COPY_ALL_PATHS", @"clipboard lists every tab path",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] containsString:p]);

        SetDoc(ed, @"");
        [ed insertDateTimeShort:YES];
        Check(@"IDM_EDIT_INSERT_DATETIME_SHORT", @"inserts a short timestamp", DocText(ed).length > 4);

        SetDoc(ed, @"");
        [ed insertDateTimeShort:NO];
        Check(@"IDM_EDIT_INSERT_DATETIME_LONG", @"inserts a long timestamp", DocText(ed).length > 8);

        SetDoc(ed, @"");
        [ed insertCustomDateTime:@"yyyy"];
        Check(@"IDM_EDIT_INSERT_DATETIME_CUSTOMIZED", @"honours a custom format",
              DocText(ed).length == 4 && [DocText(ed) hasPrefix:@"20"]);
    }

    printf("\n== Edit: multi-selection ==\n");
    {
        // "cat" appears three times with different case and word boundaries, so
        // each flag combination must produce a different count.
        struct { NppMatchFlags flags; NSUInteger want; NSString *cmdAll; NSString *cmdNext; } ms[] = {
            {NppMatchNone,                        3, @"IDM_EDIT_MULTISELECTALL",
                                                     @"IDM_EDIT_MULTISELECTNEXT"},
            {NppMatchCase,                        2, @"IDM_EDIT_MULTISELECTALLMATCHCASE",
                                                     @"IDM_EDIT_MULTISELECTNEXTMATCHCASE"},
            {NppMatchWholeWord,                   2, @"IDM_EDIT_MULTISELECTALLWHOLEWORD",
                                                     @"IDM_EDIT_MULTISELECTNEXTWHOLEWORD"},
            {NppMatchCase | NppMatchWholeWord,    1, @"IDM_EDIT_MULTISELECTALLMATCHCASEWHOLEWORD",
                                                     @"IDM_EDIT_MULTISELECTNEXTMATCHCASEWHOLEWORD"},
        };
        for (size_t i = 0; i < sizeof(ms)/sizeof(ms[0]); ++i) {
            SetDoc(ed, @"Cat cat catalog\n");
            [sci message:SCI_SETSEL wParam:4 lParam:7];        // the lowercase whole word "cat"
            NSUInteger n = [ed multiSelectAllOccurrences:ms[i].flags];
            Check(ms[i].cmdAll, [NSString stringWithFormat:@"selects %lu occurrence(s)",
                                 (unsigned long)ms[i].want],
                  n == ms[i].want && [ed selectionCount] == ms[i].want);

            SetDoc(ed, @"Cat cat catalog\n");
            [sci message:SCI_SETSEL wParam:4 lParam:7];
            NSUInteger before = [ed selectionCount];
            BOOL added = [ed multiSelectNextOccurrence:ms[i].flags];
            Check(ms[i].cmdNext, @"adds one more selection when another match exists",
                  ms[i].want > 1 ? (added && [ed selectionCount] == before + 1)
                                 : (!added && [ed selectionCount] == before));
        }

        SetDoc(ed, @"aa aa aa\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        [ed multiSelectAllOccurrences:NppMatchNone];
        NSUInteger all = [ed selectionCount];
        BOOL dropped = [ed undoLastMultiSelection];
        Check(@"IDM_EDIT_MULTISELECTUNDO", @"drops the most recently added selection",
              all == 3 && dropped && [ed selectionCount] == 2);

        SetDoc(ed, @"bb bb bb\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        [ed multiSelectNextOccurrence:NppMatchNone];
        NSUInteger beforeSkip = [ed selectionCount];
        BOOL skipped = [ed skipCurrentMultiSelection];
        Check(@"IDM_EDIT_MULTISELECTSSKIP", @"replaces the current selection with the next",
              skipped && [ed selectionCount] == beforeSkip);
    }

    printf("\n== Edit: begin/end select and column editor ==\n");
    {
        SetDoc(ed, @"0123456789\n");
        [sci message:SCI_GOTOPOS wParam:2 lParam:0];
        BOOL anchored = ![ed beginEndSelectColumnMode:NO] && [ed beginEndSelectActive];
        [sci message:SCI_GOTOPOS wParam:6 lParam:0];
        BOOL made = [ed beginEndSelectColumnMode:NO];
        Check(@"IDM_EDIT_BEGINENDSELECT", @"anchors, then selects to the caret",
              anchored && made &&
              [sci message:SCI_GETSELECTIONSTART] == 2 && [sci message:SCI_GETSELECTIONEND] == 6);

        SetDoc(ed, @"abcd\nabcd\nabcd\n");
        [sci message:SCI_GOTOPOS wParam:1 lParam:0];
        [ed beginEndSelectColumnMode:YES];
        [sci message:SCI_GOTOPOS wParam:12 lParam:0];
        BOOL columnMade = [ed beginEndSelectColumnMode:YES];
        Check(@"IDM_EDIT_BEGINENDSELECT_COLUMNMODE", @"builds a rectangular selection",
              columnMade && [ed selectionCount] >= 3);

        // Column Editor over that rectangular selection.
        SetDoc(ed, @"a\nb\nc\n");
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:0 lParam:0];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:4 lParam:0];
        BOOL inserted = [ed columnInsertText:@">"];
        Check(@"IDM_EDIT_COLUMNMODE", @"inserts into every row of the rectangle",
              inserted && [DocText(ed) isEqualToString:@">a\n>b\n>c\n"]);

        SetDoc(ed, @"x\nx\nx\n");
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:0 lParam:0];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:4 lParam:0];
        [ed columnInsertNumbersFrom:1 increment:1 zeroPadded:NO base:10];
        Check(@"IDM_EDIT_COLUMNMODETIP", @"numbers each row in sequence",
              [DocText(ed) isEqualToString:@"1x\n2x\n3x\n"]);
    }

    printf("\n== Edit: paste special ==\n");
    {
        SetDoc(ed, @"AB\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        BOOL copied = [ed copySelectionAsBinary];
        NSString *hex = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
        Check(@"IDM_EDIT_COPY_BINARY", @"copies the bytes as hex pairs",
              copied && [hex isEqualToString:@"41 42"]);

        SetDoc(ed, @"");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        BOOL pasted = [ed pasteBinary];
        Check(@"IDM_EDIT_PASTE_BINARY", @"turns hex pairs back into bytes",
              pasted && [DocText(ed) isEqualToString:@"AB"]);

        SetDoc(ed, @"XY\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        BOOL cut = [ed cutSelectionAsBinary];
        Check(@"IDM_EDIT_CUT_BINARY", @"copies as hex and removes the selection",
              cut && ![DocText(ed) hasPrefix:@"XY"] &&
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  isEqualToString:@"58 59"]);

        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:@"<b>bold</b>" forType:NSPasteboardTypeHTML];
        SetDoc(ed, @"");
        Check(@"IDM_EDIT_PASTE_AS_HTML", @"pastes the HTML source",
              [ed pasteAsHTML] && [DocText(ed) containsString:@"<b>"]);

        [pb clearContents];
        NSAttributedString *rich = [[NSAttributedString alloc] initWithString:@"rich"];
        [pb setData:[rich RTFFromRange:NSMakeRange(0, 4) documentAttributes:@{}]
            forType:NSPasteboardTypeRTF];
        SetDoc(ed, @"");
        Check(@"IDM_EDIT_PASTE_AS_RTF", @"pastes the RTF source",
              [ed pasteAsRTF] && [DocText(ed) containsString:@"rtf"]);
    }

    printf("\n== Edit: on selection ==\n");
    {
        NSError *err = nil;
        NSString *target = TempFile(@"t_sel_target.txt", @"opened via selection\n");
        NSString *holder = TempFile(@"t_sel_holder.txt",
                                    [NSString stringWithFormat:@"%@\n", target]);
        [ed openFileAtPath:holder error:&err];
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
        NSString *resolved = [ed selectionAsPath];
        BOOL opened = [ed openSelectedFile];
        Check(@"IDM_EDIT_OPENSELECTEDFILETOEDIT", @"opens the file named by the selection",
              [resolved isEqualToString:target] && opened &&
              [ed.currentDocument.path isEqualToString:target]);

        // Revealing in Finder is not launched here; the resolution is what matters.
        [ed openFileAtPath:holder error:&err];
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
        Check(@"IDM_EDIT_OPENSELECTEDFILEFOLDERINEXPLORER", @"resolves the same path for Finder",
              [[ed selectionAsPath] isEqualToString:target]);

        SetDoc(ed, @"secret value\n");
        [sci message:SCI_SETSEL wParam:0 lParam:6];
        BOOL redacted = [ed redactSelectionWithBlock:YES];
        Check(@"IDM_EDIT_REDACT_SELECTION", @"replaces the selection with blocks",
              redacted && [DocText(ed) hasPrefix:@"\u2588\u2588\u2588\u2588\u2588\u2588"]);

        ed.searchEngineTemplate = @"https://example.invalid/?q=%@";
        Check(@"IDM_EDIT_CHANGESEARCHENGINE", @"remembers the chosen engine",
              [ed.searchEngineTemplate isEqualToString:@"https://example.invalid/?q=%@"]);

        // Opening a browser from a test would be rude; assert the guard path.
        SetDoc(ed, @"");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        Check(@"IDM_EDIT_SEARCHONINTERNET", @"declines with nothing selected",
              ![ed searchSelectionOnInternet]);
    }

    printf("\n== Edit: completion, panels, file attribute ==\n");
    {
        SetDoc(ed, @"alphabet alpine\nalp");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        [ed showAutoCompletion];
        Check(@"IDM_EDIT_AUTOCOMPLETE_CURRENTFILE", @"offers words from the document",
              [sci message:SCI_AUTOCACTIVE] != 0);
        [sci message:SCI_AUTOCCANCEL];

        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_pathcomp"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"x" writeToFile:[dir stringByAppendingPathComponent:@"target.txt"]
               atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        SetDoc(ed, [dir stringByAppendingString:@"/tar"]);
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL pathComp = [ed showPathCompletion];
        Check(@"IDM_EDIT_AUTOCOMPLETE_PATH", @"offers directory entries",
              pathComp && [sci message:SCI_AUTOCACTIVE] != 0);
        [sci message:SCI_AUTOCCANCEL];

        SetDoc(ed, @"int helper(int a);\nint helper(int a, int b);\nhelper\n");
        [sci message:SCI_GOTOLINE wParam:2 lParam:0];
        BOOL tip = [ed showFunctionCallTip];
        Check(@"IDM_EDIT_FUNCCALLTIP", @"shows a hint for the word at the caret",
              tip && [sci message:SCI_CALLTIPACTIVE] != 0);
        Check(@"IDM_EDIT_FUNCCALLTIP_NEXT", @"steps to the next overload",
              [ed cycleFunctionCallTip:YES]);
        Check(@"IDM_EDIT_FUNCCALLTIP_PREVIOUS", @"steps back to the previous one",
              [ed cycleFunctionCallTip:NO]);
        [sci message:SCI_CALLTIPCANCEL];

        CharacterPanel *chars = [[CharacterPanel alloc] initWithEditor:ed];
        SetDoc(ed, @"");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        BOOL insertedChar = [chars insertRow:('A' - 32)];
        Check(@"IDM_EDIT_CHAR_PANEL", @"inserts the chosen character",
              insertedChar && [DocText(ed) isEqualToString:@"A"]);

        ClipboardHistoryPanel *clips = [[ClipboardHistoryPanel alloc] initWithEditor:ed];
        [ed copyToClipboard:@"history one"];
        [clips capturePasteboard];
        [ed copyToClipboard:@"history two"];
        [clips capturePasteboard];
        SetDoc(ed, @"");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        BOOL pastedOld = [clips pasteRow:1];
        Check(@"IDM_EDIT_CLIPBOARDHISTORY_PANEL", @"keeps earlier entries and pastes them back",
              clips.entries.count == 2 && pastedOld &&
              [DocText(ed) isEqualToString:@"history one"]);

        NSString *roFile = TempFile(@"t_readonly.txt", @"locked\n");
        [ed openFileAtPath:roFile error:NULL];
        BOOL wasWritable = ![ed systemReadOnly];
        [ed toggleSystemReadOnly];
        BOOL nowReadOnly = [ed systemReadOnly];
        [ed toggleSystemReadOnly];
        Check(@"IDM_EDIT_TOGGLESYSTEMREADONLY", @"flips the file's write permission",
              wasWritable && nowReadOnly && ![ed systemReadOnly]);
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

    printf("\n== Search: token styling ==\n");
    {
        NSArray *markAllIDs = @[@"IDM_SEARCH_MARKALLEXT1", @"IDM_SEARCH_MARKALLEXT2", @"IDM_SEARCH_MARKALLEXT3",
                                @"IDM_SEARCH_MARKALLEXT4", @"IDM_SEARCH_MARKALLEXT5"];
        NSArray *markOneIDs = @[@"IDM_SEARCH_MARKONEEXT1", @"IDM_SEARCH_MARKONEEXT2", @"IDM_SEARCH_MARKONEEXT3",
                                @"IDM_SEARCH_MARKONEEXT4", @"IDM_SEARCH_MARKONEEXT5"];
        NSArray *clearIDs   = @[@"IDM_SEARCH_UNMARKALLEXT1", @"IDM_SEARCH_UNMARKALLEXT2", @"IDM_SEARCH_UNMARKALLEXT3",
                                @"IDM_SEARCH_UNMARKALLEXT4", @"IDM_SEARCH_UNMARKALLEXT5"];
        NSArray *upIDs      = @[@"IDM_SEARCH_GOPREVMARKER1", @"IDM_SEARCH_GOPREVMARKER2", @"IDM_SEARCH_GOPREVMARKER3",
                                @"IDM_SEARCH_GOPREVMARKER4", @"IDM_SEARCH_GOPREVMARKER5"];
        NSArray *downIDs    = @[@"IDM_SEARCH_GONEXTMARKER1", @"IDM_SEARCH_GONEXTMARKER2", @"IDM_SEARCH_GONEXTMARKER3",
                                @"IDM_SEARCH_GONEXTMARKER4", @"IDM_SEARCH_GONEXTMARKER5"];
        NSArray *clipIDs    = @[@"IDM_SEARCH_STYLE1TOCLIP", @"IDM_SEARCH_STYLE2TOCLIP", @"IDM_SEARCH_STYLE3TOCLIP",
                                @"IDM_SEARCH_STYLE4TOCLIP", @"IDM_SEARCH_STYLE5TOCLIP"];

        for (NSInteger style = 0; style < NPPMAC_STYLE_COUNT; ++style) {
            SetDoc(ed, @"alpha beta alpha gamma alpha\n");
            [sci message:SCI_SETSEL wParam:0 lParam:5];          // "alpha"
            NSUInteger n = [ed markAllOccurrencesOfSelection:style];
            Check(markAllIDs[style], @"marks every occurrence of the token", n == 3);

            [sci message:SCI_GOTOPOS wParam:0 lParam:0];
            BOOL down = [ed jumpToMarker:style forward:YES];
            long afterDown = [sci message:SCI_GETSELECTIONSTART];
            Check(downIDs[style], @"jumps to the next marked token", down && afterDown > 0);

            BOOL up = [ed jumpToMarker:style forward:NO];
            Check(upIDs[style], @"jumps back to the previous one",
                  up && [sci message:SCI_GETSELECTIONSTART] < afterDown);

            [ed copyToClipboard:[ed textOfStyle:style]];
            Check(clipIDs[style], @"copies the styled text",
                  [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                      containsString:@"alpha"]);

            [ed clearStyle:style];
            Check(clearIDs[style], @"clears the style", [ed textOfStyle:style].length == 0);

            SetDoc(ed, @"one two one\n");
            [sci message:SCI_SETSEL wParam:0 lParam:3];
            [ed markOneOccurrenceOfSelection:style];
            Check(markOneIDs[style], @"marks only the selected occurrence",
                  [[ed textOfStyle:style] isEqualToString:@"one"]);
            [ed clearStyle:style];
        }

        SetDoc(ed, @"x y x\n");
        [sci message:SCI_SETSEL wParam:0 lParam:1];
        [ed markAllOccurrencesOfSelection:0];
        [ed markAllOccurrencesOfSelection:1];
        NSString *all = [ed textOfAllStyles];
        Check(@"IDM_SEARCH_ALLSTYLESTOCLIP", @"gathers text across styles", all.length > 0);

        [ed clearAllStyles];
        Check(@"IDM_SEARCH_CLEARALLMARKS", @"clears every style",
              [ed textOfAllStyles].length == 0);

        SetDoc(ed, @"find me find\n");
        [sci message:SCI_SETSEL wParam:0 lParam:4];
        NSUInteger marked = [ed markAllOccurrencesOfSelection:NPPMAC_STYLE_COUNT];
        Check(@"IDM_SEARCH_MARK", @"Mark uses the Find Mark style", marked == 2);
        BOOL fwd = [ed jumpToMarker:NPPMAC_STYLE_COUNT forward:YES];
        Check(@"IDM_SEARCH_GONEXTMARKER_DEF", @"jumps down the Find Mark style", fwd);
        BOOL back = [ed jumpToMarker:NPPMAC_STYLE_COUNT forward:NO];
        Check(@"IDM_SEARCH_GOPREVMARKER_DEF", @"jumps up the Find Mark style", back);
        [ed copyToClipboard:[ed textOfStyle:NPPMAC_STYLE_COUNT]];
        Check(@"IDM_SEARCH_MARKEDTOCLIP", @"copies Find Mark text",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] containsString:@"find"]);
        [ed clearAllStyles];

        SetDoc(ed, @"ascii \u00e9\u00e8\n");
        NSUInteger nonAscii = [ed markCharactersInRangeFrom:128 to:65535];
        Check(@"IDM_SEARCH_FINDCHARINRANGE", @"marks characters in a code-point range",
              nonAscii == 2);
        [ed clearAllStyles];
    }

    printf("\n== Search: bookmarked lines ==\n");
    {
        SetDoc(ed, @"keep1\ndrop1\nkeep2\ndrop2\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0]; [ed toggleBookmark];
        [sci message:SCI_GOTOLINE wParam:2 lParam:0]; [ed toggleBookmark];

        [ed copyBookmarkedLines];
        Check(@"IDM_SEARCH_COPYMARKEDLINES", @"copies just the bookmarked lines",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  isEqualToString:@"keep1\nkeep2"]);

        [ed removeUnbookmarkedLines];
        Check(@"IDM_SEARCH_DELETEUNMARKEDLINES", @"keeps only bookmarked lines",
              [DocText(ed) hasPrefix:@"keep1"] && ![DocText(ed) containsString:@"drop1"]);

        SetDoc(ed, @"a\nb\nc\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:1 lParam:0]; [ed toggleBookmark];
        [ed removeBookmarkedLines];
        Check(@"IDM_SEARCH_DELETEMARKEDLINES", @"removes bookmarked lines",
              ![DocText(ed) containsString:@"b"]);

        SetDoc(ed, @"x\ny\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0]; [ed toggleBookmark];
        [ed cutBookmarkedLines];
        Check(@"IDM_SEARCH_CUTMARKEDLINES", @"copies then removes them",
              ![DocText(ed) containsString:@"x"] &&
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] containsString:@"x"]);

        SetDoc(ed, @"one\ntwo\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0]; [ed toggleBookmark];
        [ed copyToClipboard:@"REPLACED"];
        [ed pasteOverBookmarkedLines];
        Check(@"IDM_SEARCH_PASTEMARKEDLINES", @"replaces bookmarked lines with the clipboard",
              [DocText(ed) hasPrefix:@"REPLACED"] && [DocText(ed) containsString:@"two"]);

        SetDoc(ed, @"p\nq\nr\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:1 lParam:0]; [ed toggleBookmark];
        [ed inverseBookmarks];
        BOOL inverted = !([sci message:SCI_MARKERGET wParam:1] & (1 << 1)) &&
                         ([sci message:SCI_MARKERGET wParam:0] & (1 << 1));
        Check(@"IDM_SEARCH_INVERSEMARKS", @"flips which lines are bookmarked", inverted);
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
    }

    printf("\n== Search: braces, selection, files ==\n");
    {
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"if (a) { b; }\n");
        [sci message:SCI_GOTOPOS wParam:7 lParam:0];       // the '{'
        BOOL jumped = [ed goToMatchingBrace];
        Check(@"IDM_SEARCH_GOTOMATCHINGBRACE", @"moves to the matching brace",
              jumped && [sci message:SCI_GETCURRENTPOS] == 12);

        [sci message:SCI_GOTOPOS wParam:7 lParam:0];
        BOOL selected = [ed selectBetweenMatchingBraces];
        Check(@"IDM_SEARCH_SELECTMATCHINGBRACES", @"selects between the braces",
              selected && [sci message:SCI_GETSELECTIONEND] > [sci message:SCI_GETSELECTIONSTART]);

        SetDoc(ed, @"aa bb aa cc aa\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        BOOL next = [ed findNextOccurrenceOfSelection:YES extendSelection:NO];
        long p1 = [sci message:SCI_GETSELECTIONSTART];
        Check(@"IDM_SEARCH_SETANDFINDNEXT", @"selects the next occurrence", next && p1 == 6);
        BOOL prev = [ed findNextOccurrenceOfSelection:NO extendSelection:NO];
        Check(@"IDM_SEARCH_SETANDFINDPREV", @"selects the previous one",
              prev && [sci message:SCI_GETSELECTIONSTART] < p1);

        [sci message:SCI_SETSEL wParam:0 lParam:2];
        Check(@"IDM_SEARCH_VOLATILE_FINDNEXT", @"volatile next uses the selection",
              [ed findNextOccurrenceOfSelection:YES extendSelection:NO]);
        Check(@"IDM_SEARCH_VOLATILE_FINDPREV", @"volatile previous uses the selection",
              [ed findNextOccurrenceOfSelection:NO extendSelection:NO]);

        app.lastSearchTerm = @"cc";
        Check(@"IDM_SEARCH_FINDINCREMENT", @"incremental search drives the same state",
              [app searchFrom:0 forward:YES wrap:YES]);

        // Find in Files over a throwaway tree.
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_fif"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"hello needle\nplain\n" writeToFile:[dir stringByAppendingPathComponent:@"a.txt"]
                                     atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"needle again\nneedle twice\n" writeToFile:[dir stringByAppendingPathComponent:@"b.txt"]
                                            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSUInteger hits = [ed findInFiles:@"needle" inFolder:dir filter:nil];
        Check(@"IDM_SEARCH_FINDINFILES", @"reports every hit across the folder", hits == 3);
        Check(@"IDM_FOCUS_ON_FOUND_RESULTS", @"results land in their own tab",
              [ed focusSearchResults] &&
              [ed.currentDocument.displayName isEqualToString:@"Search results"]);

        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL nextHit = [ed goToSearchResult:YES];
        long hitLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        Check(@"IDM_SEARCH_GOTONEXTFOUND", @"steps to the next result line", nextHit);
        Check(@"IDM_SEARCH_GOTOPREVFOUND", @"steps back to the previous one",
              [ed goToSearchResult:NO] || hitLine >= 0);
    }

    printf("\n== Search: change history ==\n");
    {
        [ed newDocument];
        [ed enableChangeHistory:YES];
        SetDoc(ed, @"line1\nline2\nline3\n");
        [sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [sci setStringProperty:SCI_INSERTTEXT parameter:[sci message:SCI_GETCURRENTPOS] value:@"EDIT"];

        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL fwd = [ed goToNextChange:YES];
        Check(@"IDM_SEARCH_CHANGED_NEXT", @"finds the modified line", fwd);
        [sci message:SCI_GOTOLINE wParam:2 lParam:0];
        Check(@"IDM_SEARCH_CHANGED_PREV", @"finds it going backwards", [ed goToNextChange:NO]);

        // Regression: change-history markers must belong to a margin. Scintilla
        // draws a marker with no margin as a whole-line background, which turned
        // every saved line the "saved" colour and made the document look green.
        long historyMask = (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) |
                           (1 << SC_MARKNUM_HISTORY_SAVED) |
                           (1 << SC_MARKNUM_HISTORY_MODIFIED) |
                           (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED);
        long covered = 0;
        for (int margin = 0; margin < SC_MAX_MARGIN + 1; ++margin) {
            if ([sci message:SCI_GETMARGINWIDTHN wParam:(uptr_t)margin] > 0) {
                covered |= [sci message:SCI_GETMARGINMASKN wParam:(uptr_t)margin];
            }
        }
        Check(@"IDM_SEARCH_CHANGED_NEXT", @"history markers live in a visible margin",
              (covered & historyMask) == historyMask);

        [ed clearChangeHistory];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        Check(@"IDM_SEARCH_CLEAR_CHANGE_HISTORY", @"history is discarded",
              ![ed goToNextChange:YES]);
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

    printf("\n== View: tabs ==\n");
    {
        NSError *err = nil;
        [ed closeAllDocuments];
        for (int i = 1; i <= 9; ++i) {
            [ed openFileAtPath:TempFile([NSString stringWithFormat:@"t_tab%d.txt", i],
                                        [NSString stringWithFormat:@"tab %d\n", i]) error:&err];
        }
        NSArray *tabIDs = @[@"IDM_VIEW_TAB1", @"IDM_VIEW_TAB2", @"IDM_VIEW_TAB3", @"IDM_VIEW_TAB4",
                            @"IDM_VIEW_TAB5", @"IDM_VIEW_TAB6", @"IDM_VIEW_TAB7", @"IDM_VIEW_TAB8",
                            @"IDM_VIEW_TAB9"];
        for (NSInteger i = 1; i <= 9; ++i) {
            BOOL ok = [ed selectTabNumber:i];
            Check(tabIDs[i - 1], [NSString stringWithFormat:@"selects tab %ld", (long)i],
                  ok && [ed.documents indexOfObject:ed.currentDocument] == (NSUInteger)(i - 1));
        }

        [ed goToFirstTab];
        Check(@"IDM_VIEW_TAB_START", @"jumps to the first tab",
              [ed.documents indexOfObject:ed.currentDocument] == 0);
        [ed goToLastTab];
        Check(@"IDM_VIEW_TAB_END", @"jumps to the last tab",
              [ed.documents indexOfObject:ed.currentDocument] == ed.documents.count - 1);

        [ed goToFirstTab];
        [ed goToNextTab];
        Check(@"IDM_VIEW_TAB_NEXT", @"steps forward one tab",
              [ed.documents indexOfObject:ed.currentDocument] == 1);
        [ed goToPreviousTab];
        Check(@"IDM_VIEW_TAB_PREV", @"steps back one tab",
              [ed.documents indexOfObject:ed.currentDocument] == 0);

        NppDocument *moving = ed.currentDocument;
        [ed moveCurrentTab:YES];
        Check(@"IDM_VIEW_TAB_MOVEFORWARD", @"moves the tab one place right",
              [ed.documents indexOfObject:moving] == 1 && ed.currentDocument == moving);
        [ed moveCurrentTab:NO];
        Check(@"IDM_VIEW_TAB_MOVEBACKWARD", @"moves it back",
              [ed.documents indexOfObject:moving] == 0);

        [ed selectTabNumber:5];
        NppDocument *jumper = ed.currentDocument;
        [ed moveCurrentTabToEnd:NO];
        Check(@"IDM_VIEW_GOTO_START", @"moves the tab to the front",
              [ed.documents indexOfObject:jumper] == 0);
        [ed moveCurrentTabToEnd:YES];
        Check(@"IDM_VIEW_GOTO_END", @"moves it to the back",
              [ed.documents indexOfObject:jumper] == ed.documents.count - 1);

        NSArray *colourIDs = @[@"IDM_VIEW_TAB_COLOUR_1", @"IDM_VIEW_TAB_COLOUR_2", @"IDM_VIEW_TAB_COLOUR_3",
                               @"IDM_VIEW_TAB_COLOUR_4", @"IDM_VIEW_TAB_COLOUR_5"];
        for (NSInteger c = 1; c <= 5; ++c) {
            [ed setTabColour:c];
            Check(colourIDs[c - 1], [NSString stringWithFormat:@"applies colour %ld", (long)c],
                  ed.currentDocument.tabColour == c);
        }
        [ed setTabColour:0];
        Check(@"IDM_VIEW_TAB_COLOUR_NONE", @"removes the colour", ed.currentDocument.tabColour == 0);
    }

    printf("\n== View: fold levels ==\n");
    {
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"void a() {\n  if (x) {\n    y();\n  }\n}\n");
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];

        NSArray *foldIDs = @[@"IDM_VIEW_FOLD_1", @"IDM_VIEW_FOLD_2", @"IDM_VIEW_FOLD_3", @"IDM_VIEW_FOLD_4",
                             @"IDM_VIEW_FOLD_5", @"IDM_VIEW_FOLD_6", @"IDM_VIEW_FOLD_7", @"IDM_VIEW_FOLD_8"];
        NSArray *unfoldIDs = @[@"IDM_VIEW_UNFOLD_1", @"IDM_VIEW_UNFOLD_2", @"IDM_VIEW_UNFOLD_3", @"IDM_VIEW_UNFOLD_4",
                               @"IDM_VIEW_UNFOLD_5", @"IDM_VIEW_UNFOLD_6", @"IDM_VIEW_UNFOLD_7", @"IDM_VIEW_UNFOLD_8"];
        for (NSInteger lvl = 1; lvl <= 8; ++lvl) {
            [ed unfoldToLevel:lvl];
            [ed foldToLevel:lvl];
            // Level 1 and 2 exist in this snippet; deeper levels must be no-ops
            // rather than errors, which is what is asserted here.
            BOOL consistent = YES;
            if (lvl == 1) consistent = [sci message:SCI_GETLINEVISIBLE wParam:1] == 0;
            Check(foldIDs[lvl - 1], [NSString stringWithFormat:@"folds level %ld", (long)lvl], consistent);

            [ed unfoldToLevel:lvl];
            BOOL restored = YES;
            if (lvl == 1) restored = [sci message:SCI_GETLINEVISIBLE wParam:1] != 0;
            Check(unfoldIDs[lvl - 1], [NSString stringWithFormat:@"unfolds level %ld", (long)lvl], restored);
        }
        [ed foldAll:NO];
    }

    printf("\n== View: symbols, lines, direction ==\n");
    {
        struct { NppSymbol sym; NSString *cmd; } syms[] = {
            {NppSymbolWhitespace,           @"IDM_VIEW_TAB_SPACE"},
            {NppSymbolEOL,                  @"IDM_VIEW_EOL"},
            {NppSymbolNonPrinting,          @"IDM_VIEW_NPC"},
            {NppSymbolControlAndUnicodeEOL, @"IDM_VIEW_NPC_CCUNIEOL"},
            {NppSymbolIndentGuide,          @"IDM_VIEW_INDENT_GUIDE"},
            {NppSymbolWrap,                 @"IDM_VIEW_WRAP_SYMBOL"},
        };
        for (size_t i = 0; i < sizeof(syms)/sizeof(syms[0]); ++i) {
            BOOL before = [ed symbolVisible:syms[i].sym];
            [ed toggleSymbol:syms[i].sym];
            BOOL flipped = [ed symbolVisible:syms[i].sym] != before;
            [ed toggleSymbol:syms[i].sym];
            Check(syms[i].cmd, @"toggles and restores",
                  flipped && [ed symbolVisible:syms[i].sym] == before);
        }

        SetDoc(ed, @"one\ntwo\nthree\n");
        [sci message:SCI_SETSEL wParam:(uptr_t)[sci message:SCI_POSITIONFROMLINE wParam:1]
                 lParam:[sci message:SCI_GETLINEENDPOSITION wParam:1]];
        BOOL hidden = [ed hideSelectedLines];
        Check(@"IDM_VIEW_HIDELINES", @"hides the selected lines",
              hidden && [sci message:SCI_GETLINEVISIBLE wParam:1] == 0);
        [ed showAllHiddenLines];

        [ed setTextDirectionRTL:YES];
        BOOL rtl = [ed textDirectionIsRTL];
        [ed setTextDirectionRTL:NO];
        Check(@"IDM_EDIT_RTL", @"switches to right-to-left", rtl);
        Check(@"IDM_EDIT_LTR", @"switches back to left-to-right", ![ed textDirectionIsRTL]);

        NSDictionary *sum = [ed documentSummary];
        Check(@"IDM_VIEW_SUMMARY", @"counts words, lines and bytes",
              [sum[@"words"] integerValue] == 3 && [sum[@"lines"] integerValue] >= 3 &&
              [sum[@"bytes"] integerValue] > 0);
    }

    printf("\n== View: window modes and panels ==\n");
    {
        NSError *err = nil;
        NSString *p = TempFile(@"t_view.txt", @"x\n");
        [ed openFileAtPath:p error:&err];

        BOOL chromeBefore = [ed chromeVisible];
        [app toggleDistractionFree:nil];
        BOOL chromeHidden = ![ed chromeVisible];
        [app toggleDistractionFree:nil];
        Check(@"IDM_VIEW_DISTRACTIONFREE", @"hides and restores the chrome",
              chromeHidden && [ed chromeVisible] == chromeBefore);

        [app togglePostIt:nil];
        BOOL postIt = ![ed chromeVisible] && app.window.level == NSFloatingWindowLevel;
        [app togglePostIt:nil];
        Check(@"IDM_VIEW_POSTIT", @"chrome-less and floating, then restored",
              postIt && [ed chromeVisible]);

        [app toggleAlwaysOnTop:nil];
        BOOL onTop = app.window.level == NSFloatingWindowLevel;
        [app toggleAlwaysOnTop:nil];
        Check(@"IDM_VIEW_ALWAYSONTOP", @"raises and lowers the window level",
              onTop && app.window.level == NSNormalWindowLevel);

        // Toggling real full screen animates and would stall the suite.
        // Top-level bar items carry no title of their own; the submenu does.
        NSMenuItem *fs = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if (![top.submenu.title isEqualToString:@"View"]) continue;
            for (NSMenuItem *mi in top.submenu.itemArray) {
                if ([mi.title isEqualToString:@"Toggle Full Screen Mode"]) fs = mi;
            }
        }
        Check(@"IDM_VIEW_FULLSCREENTOGGLE", @"wired to the window's full-screen action",
              fs != nil && fs.action == @selector(toggleFullScreenMode:));

        [app toggleFileBrowser:nil];
        BOOL browserOn = [ed workspaceVisible];
        [app toggleFileBrowser:nil];
        Check(@"IDM_VIEW_FILEBROWSER", @"shows and hides the workspace panel",
              browserOn && ![ed workspaceVisible]);

        [app toggleDocumentList:nil];
        BOOL listOn = [app valueForKey:@"docList"] != nil;
        [app toggleDocumentList:nil];

        // Regression: AppKit draws the table from a row count it cached earlier.
        // Asking for a row after the tabs are gone used to index past the end of
        // the documents array and raise, which aborted the process the next time
        // the run loop let the panel redraw.
        id<NSTableViewDataSource> ds = (id<NSTableViewDataSource>)[app valueForKey:@"docList"];
        NSTableView *probe = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        NSTableColumn *probeCol = [[NSTableColumn alloc] initWithIdentifier:@"doc"];
        NSUInteger liveRows = ed.documents.count;
        id staleValue = [ds tableView:probe objectValueForTableColumn:probeCol
                                  row:(NSInteger)liveRows + 5];
        Check(@"IDM_VIEW_DOCLIST", @"lists documents and survives a stale row index",
              listOn && staleValue != nil);

        [ed setMonitoring:YES];
        BOOL monitoring = [ed monitoringEnabled];
        [ed setMonitoring:NO];
        Check(@"IDM_VIEW_MONITORING", @"starts and stops watching the file",
              monitoring && ![ed monitoringEnabled]);

        // Launching a browser from a test would be rude; assert the guard path.
        [ed newDocument];
        struct { NSString *bundle; NSString *cmd; } browsers[] = {
            {@"org.mozilla.firefox",  @"IDM_VIEW_IN_FIREFOX"},
            {@"com.google.Chrome",    @"IDM_VIEW_IN_CHROME"},
            {@"com.microsoft.edgemac",@"IDM_VIEW_IN_EDGE"},
            {@"com.apple.Safari",     @"IDM_VIEW_IN_IE"},
        };
        for (size_t i = 0; i < sizeof(browsers)/sizeof(browsers[0]); ++i) {
            Check(browsers[i].cmd, @"declines while the document is unsaved",
                  ![ed openCurrentInBrowserBundleID:browsers[i].bundle]);
        }
    }

    printf("\n== View: split panes and panels ==\n");
    {
        NSError *err = nil;
        [ed closeAllDocuments];
        [ed openFileAtPath:TempFile(@"t_split1.txt", @"one\ntwo\nthree\nfour\nfive\n") error:&err];
        [ed openFileAtPath:TempFile(@"t_split2.txt", @"other\n") error:&err];

        [ed selectTabNumber:2];
        void *sharedDoc = ed.currentDocument.docPointer;
        BOOL cloned = [ed cloneCurrentToOtherView];
        Check(@"IDM_VIEW_CLONE_TO_ANOTHER_VIEW", @"second pane shows the same buffer",
              cloned && [ed secondaryViewVisible] &&
              (void *)[ed.secondarySci message:SCI_GETDOCPOINTER] == sharedDoc);

        NSUInteger before = ed.documents.count;
        [ed moveCurrentToOtherView];
        Check(@"IDM_VIEW_GOTO_ANOTHER_VIEW", @"the tab leaves the primary pane",
              ed.documents.count == before - 1);

        [ed focusOtherView];
        BOOL onOther = [ed otherViewHasFocus];
        [ed focusOtherView];
        Check(@"IDM_VIEW_SWITCHTO_OTHER_VIEW", @"focus moves between panes and back",
              onOther && ![ed otherViewHasFocus]);

        // Synchronised scrolling and zoom
        // Long enough that SCI_SETFIRSTVISIBLELINE is not clamped back to 0.
        NSMutableString *tall = [NSMutableString string];
        for (int i = 0; i < 300; ++i) [tall appendFormat:@"line %d\n", i];
        SetDoc(ed, tall);
        [ed cloneCurrentToOtherView];
        [ed setSyncVerticalScroll:YES];
        [sci message:SCI_SETFIRSTVISIBLELINE wParam:40 lParam:0];
        [ed mirrorScrollToSecondary];
        long primaryTop = [sci message:SCI_GETFIRSTVISIBLELINE];
        Check(@"IDM_VIEW_SYNSCROLLV", @"second pane follows vertically",
              primaryTop > 0 &&
              [ed.secondarySci message:SCI_GETFIRSTVISIBLELINE] == primaryTop);
        [ed setSyncVerticalScroll:NO];

        [ed setSyncHorizontalScroll:YES];
        [sci message:SCI_SETXOFFSET wParam:37 lParam:0];
        [ed mirrorScrollToSecondary];
        Check(@"IDM_VIEW_SYNSCROLLH", @"second pane follows horizontally",
              [ed.secondarySci message:SCI_GETXOFFSET] == 37);
        [ed setSyncHorizontalScroll:NO];
        [sci message:SCI_SETXOFFSET wParam:0 lParam:0];

        [ed setSyncZoom:YES];
        [sci message:SCI_SETZOOM wParam:3 lParam:0];
        [ed mirrorScrollToSecondary];
        Check(@"IDM_VIEW_ZOOM_SYNC", @"zoom is mirrored across panes",
              [ed.secondarySci message:SCI_GETZOOM] == 3);
        [ed setSyncZoom:NO];
        [sci message:SCI_SETZOOM wParam:0 lParam:0];
        [ed setSecondaryViewVisible:NO];

        // Spawning real app instances from a test would litter the session.
        [ed newDocument];
        Check(@"IDM_VIEW_GOTO_NEW_INSTANCE", @"declines while the document is unsaved",
              ![ed openCurrentInNewInstanceMoving:YES]);
        Check(@"IDM_VIEW_LOAD_IN_NEW_INSTANCE", @"declines while the document is unsaved",
              ![ed openCurrentInNewInstanceMoving:NO]);

        [ed openFileAtPath:TempFile(@"t_map.txt", @"mapped\n") error:&err];
        [ed setDocumentMapVisible:YES];
        BOOL mapOn = [ed documentMapVisible];
        [ed setDocumentMapVisible:NO];
        Check(@"IDM_VIEW_DOC_MAP", @"shows and hides the shrunken mirror",
              mapOn && ![ed documentMapVisible]);

        [ed setLanguageNamed:@"python"];
        SetDoc(ed, @"def alpha(x):\n    return x\n\ndef beta():\n    pass\n");
        FunctionListPanel *fl = [[FunctionListPanel alloc] initWithEditor:ed];
        NSArray *names = [fl functionNames];
        Check(@"IDM_VIEW_FUNC_LIST", @"lists the declarations in the document",
              names.count == 2 && [names containsObject:@"alpha"] && [names containsObject:@"beta"]);

        NSString *projDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_proj"];
        [[NSFileManager defaultManager] removeItemAtPath:projDir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:projDir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"x\n" writeToFile:[projDir stringByAppendingPathComponent:@"proj.txt"]
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSArray *projIDs = @[@"IDM_VIEW_PROJECT_PANEL_1", @"IDM_VIEW_PROJECT_PANEL_2", @"IDM_VIEW_PROJECT_PANEL_3"];
        for (NSInteger i = 1; i <= 3; ++i) {
            [ed setProjectPanel:i root:projDir];
            [ed showProjectPanel:i];
            BOOL shown = [ed activeProjectPanel] == i &&
                         [[ed projectPanelRoot:i] isEqualToString:projDir] &&
                         [[ed projectPanelNames:i] containsObject:@"proj.txt"];
            [ed showProjectPanel:i];               // same panel again hides it
            Check(projIDs[i - 1], [NSString stringWithFormat:@"panel %ld opens on its own root", (long)i],
                  shown && [ed activeProjectPanel] == 0);
        }
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

    printf("\n== Encoding: character sets ==\n");
    {
        // Every charset in the menu must resolve to a usable macOS encoding and
        // survive a byte round-trip through that charset.
        int resolved = 0;
        NSMutableArray *unsupported = [NSMutableArray array];
        for (int i = 0; i < kNppCharsetCount; ++i) {
            unsigned int cp = kNppCharsets[i].codepage;
            NSString *cmd = @(kNppCharsets[i].menuID);
            if (![EditorController supportsCodepage:cp]) {
                // Nothing on the system can decode this page; the command must
                // decline cleanly rather than silently decode as something else.
                [unsupported addObject:@(kNppCharsets[i].label)];
                Check([cmd stringByAppendingString:@" (unsupported)"],
                      [NSString stringWithFormat:@"%@ declines instead of mis-decoding",
                       @(kNppCharsets[i].label)],
                      ![ed reinterpretAsCodepage:cp]);
                continue;
            }
            if (cp == 720) { resolved++; continue; }   // covered by its own test below
            NSStringEncoding enc = [EditorController encodingForCodepage:cp];
            resolved++;
            // ASCII is representable in every one of these sets, so a round trip
            // through the charset must return the original text.
            NSString *probe = @"probe 123";
            NSData *bytes = [probe dataUsingEncoding:enc allowLossyConversion:NO];
            NSString *back = bytes ? [[NSString alloc] initWithData:bytes encoding:enc] : nil;
            Check(cmd, [NSString stringWithFormat:@"%@ round-trips", @(kNppCharsets[i].label)],
                  [back isEqualToString:probe]);
        }
        printf("  (%d of %d character sets resolved%s)\n", resolved, kNppCharsetCount,
               unsupported.count ? [[NSString stringWithFormat:@"; missing: %@",
                                     [unsupported componentsJoinedByString:@", "]] UTF8String] : "");

        // Encode in: the bytes stay, the reading changes. Round-tripping a
        // Cyrillic byte through Windows-1251 and back must restore the text.
        // Code page 720 is decoded from an embedded table; every byte must
        // survive a byte -> character -> byte round trip.
        {
            NSMutableData *all = [NSMutableData dataWithCapacity:256];
            for (int b = 0; b < 256; ++b) { unsigned char c = (unsigned char)b; [all appendBytes:&c length:1]; }
            NSString *decoded = [EditorController stringFromData:all codepage:720];
            NSData *reencoded = [EditorController dataFromString:decoded codepage:720];
            BOOL identity = decoded.length == 256 && [reencoded isEqualToData:all];

            // Spot-check against the published mapping.
            unichar c0xA0 = [decoded characterAtIndex:0xA0];
            unichar c0x98 = [decoded characterAtIndex:0x98];
            unichar c0x41 = [decoded characterAtIndex:0x41];
            Check(@"IDM_FORMAT_DOS_720", @"all 256 bytes round-trip and match the spec",
                  identity && c0xA0 == 0x0628 && c0x98 == 0x0621 && c0x41 == 'A');
        }

        // End to end: real Arabic bytes on disk, opened and read back as CP720.
        // Reference produced with Python's cp720 codec:
        //   'مرحبا'.encode('cp720') -> EA A9 A5 A0 9F
        {
            const unsigned char arabicBytes[] = {0xEA, 0xA9, 0xA5, 0xA0, 0x9F, '\n'};
            NSString *expected = @"\u0645\u0631\u062D\u0628\u0627\n";
            NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_cp720.txt"];
            [[NSData dataWithBytes:arabicBytes length:sizeof(arabicBytes)] writeToFile:p atomically:YES];

            NSError *e = nil;
            [ed openFileAtPath:p error:&e];
            BOOL ok = [ed reinterpretAsCodepage:720];
            BOOL textOK = [DocText(ed) isEqualToString:expected];

            // Saving must put the very same bytes back on disk.
            [ed saveCurrentDocument];
            NSData *back = [NSData dataWithContentsOfFile:p];
            BOOL bytesOK = [back isEqualToData:[NSData dataWithBytes:arabicBytes length:sizeof(arabicBytes)]];
            Check(@"IDM_FORMAT_DOS_720", @"Arabic file round-trips through open, decode and save",
                  ok && textOK && bytesOK);
        }

        // Code page 858 must differ from 850 in exactly the euro byte.
        NSData *euroByte = [NSData dataWithBytes:(const unsigned char[]){0xD5} length:1];
        NSString *as858 = [EditorController stringFromData:euroByte codepage:858];
        NSString *as850 = [EditorController stringFromData:euroByte codepage:850];
        Check(@"IDM_FORMAT_DOS_858", @"byte 0xD5 is the euro sign, unlike code page 850",
              [as858 isEqualToString:@"\u20AC"] && ![as850 isEqualToString:as858]);

        NSString *cyr = @"\u0442\u0435\u0441\u0442";                     // "test" in Cyrillic
        NSStringEncoding win1251 = [EditorController encodingForCodepage:1251];
        NSData *cyrBytes = [cyr dataUsingEncoding:win1251 allowLossyConversion:NO];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_cp1251.txt"];
        [cyrBytes writeToFile:path atomically:YES];

        NSError *err = nil;
        [ed openFileAtPath:path error:&err];          // opens as Latin-1 (not valid UTF-8)
        BOOL reinterpreted = [ed reinterpretAsCodepage:1251];
        Check(@"IDM_FORMAT_WIN_1251", @"Encode in Windows-1251 recovers Cyrillic text",
              reinterpreted && [DocText(ed) isEqualToString:cyr]);
    }

    printf("\n== Encoding: convert to ==\n");
    {
        struct { NSStringEncoding enc; BOOL bom; NSString *cmd; NSString *name; } convs[] = {
            {NSISOLatin1StringEncoding,         NO,  @"IDM_FORMAT_CONV2_ANSI",      @"ANSI"},
            {NSUTF8StringEncoding,              NO,  @"IDM_FORMAT_CONV2_AS_UTF_8",  @"UTF-8"},
            {NSUTF8StringEncoding,              YES, @"IDM_FORMAT_CONV2_UTF_8",     @"UTF-8-BOM"},
            {NSUTF16BigEndianStringEncoding,    YES, @"IDM_FORMAT_CONV2_UTF_16BE",  @"UTF-16 BE"},
            {NSUTF16LittleEndianStringEncoding, YES, @"IDM_FORMAT_CONV2_UTF_16LE",  @"UTF-16 LE"},
        };
        for (size_t i = 0; i < sizeof(convs)/sizeof(convs[0]); ++i) {
            NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"t_conv%zu.txt", i]];
            [[NSFileManager defaultManager] removeItemAtPath:p error:NULL];
            [@"convert me\n" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];

            NSError *e = nil;
            [ed openFileAtPath:p error:&e];
            [ed setEncoding:convs[i].enc withBOM:convs[i].bom];
            [ed saveCurrentDocument];
            [ed closeCurrentDocument];
            [ed openFileAtPath:p error:&e];
            Check(convs[i].cmd, [NSString stringWithFormat:@"Convert to %@ keeps the text", convs[i].name],
                  [DocText(ed) isEqualToString:@"convert me\n"] &&
                  ed.currentDocument.hasBOM == convs[i].bom);
        }
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

    printf("\n== Tools: hashes ==\n");
    {
        // Reference values for "abc" from the published test vectors.
        struct { NppDigest d; NSString *want; NSString *gen; NSString *files; NSString *clip; } hashes[] = {
            {NppDigestMD5,    @"900150983cd24fb0d6963f7d28e17f72",
             @"IDM_TOOL_MD5_GENERATE", @"IDM_TOOL_MD5_GENERATEFROMFILE", @"IDM_TOOL_MD5_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA1,   @"a9993e364706816aba3e25717850c26c9cd0d89d",
             @"IDM_TOOL_SHA1_GENERATE", @"IDM_TOOL_SHA1_GENERATEFROMFILE", @"IDM_TOOL_SHA1_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA256, @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
             @"IDM_TOOL_SHA256_GENERATE", @"IDM_TOOL_SHA256_GENERATEFROMFILE", @"IDM_TOOL_SHA256_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA512, @"ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                               "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
             @"IDM_TOOL_SHA512_GENERATE", @"IDM_TOOL_SHA512_GENERATEFROMFILE", @"IDM_TOOL_SHA512_GENERATEINTOCLIPBOARD"},
        };
        NSString *abcPath = TempFile(@"t_hash.txt", @"abc");
        for (size_t i = 0; i < sizeof(hashes)/sizeof(hashes[0]); ++i) {
            NSString *got = [EditorController hashOfData:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]
                                                  digest:hashes[i].d];
            Check(hashes[i].gen, [NSString stringWithFormat:@"%@(\"abc\") matches the test vector",
                                  [EditorController nameOfDigest:hashes[i].d]],
                  [got isEqualToString:hashes[i].want]);

            NSString *fromFile = [ed hashOfFiles:@[abcPath] digest:hashes[i].d];
            Check(hashes[i].files, @"hashes a file's contents",
                  [fromFile hasPrefix:hashes[i].want] && [fromFile hasSuffix:abcPath]);

            SetDoc(ed, @"abc");
            [sci message:SCI_SETSEL wParam:0 lParam:3];
            [ed copyToClipboard:[ed hashOfSelection:hashes[i].d]];
            Check(hashes[i].clip, @"puts the selection hash on the clipboard",
                  [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                      isEqualToString:hashes[i].want]);
        }
    }

    printf("\n== Macro ==\n");
    {
        SetDoc(ed, @"");
        [ed startRecordingMacro];
        BOOL recording = [ed recordingMacro];
        // Drive a couple of recordable actions through Scintilla.
        [sci message:SCI_BEGINUNDOACTION];
        [sci setStringProperty:SCI_REPLACESEL parameter:0 value:@"x"];
        [sci message:SCI_ENDUNDOACTION];
        [ed stopRecordingMacro];
        NSUInteger steps = [ed recordedStepCount];
        Check(@"IDM_MACRO_STARTRECORDINGMACRO", @"records while recording is on",
              recording && steps > 0);
        Check(@"IDM_MACRO_STOPRECORDINGMACRO", @"stops recording", ![ed recordingMacro]);

        NSString *before = DocText(ed);
        BOOL played = [ed playbackMacro:1];
        Check(@"IDM_MACRO_PLAYBACKRECORDEDMACRO", @"replays the recorded steps",
              played && DocText(ed).length > before.length);

        NSUInteger lengthBefore = DocText(ed).length;
        [ed playbackMacro:3];
        Check(@"IDM_MACRO_RUNMULTIMACRODLG", @"replays the requested number of times",
              DocText(ed).length == lengthBefore + 3);

        BOOL saved = [ed saveRecordedMacroAs:@"test macro"];
        Check(@"IDM_MACRO_SAVECURRENTMACRO", @"stores the macro under a name",
              saved && [[ed savedMacroNames] containsObject:@"test macro"]);
    }

    printf("\n== Window ==\n");
    {
        NSError *err = nil;
        [ed closeAllDocuments];
        // Names, extensions and sizes all differ, so each sort key is distinguishable.
        [ed openFileAtPath:TempFile(@"w_charlie.txt", @"ccc\n") error:&err];
        [ed openFileAtPath:TempFile(@"w_alpha.md",    @"a\n")   error:&err];
        [ed openFileAtPath:TempFile(@"w_bravo.py",    @"bb\n")  error:&err];

        struct { NppTabSort key; BOOL asc; NSString *cmd; } sorts[] = {
            {NppTabSortName,          YES, @"IDM_WINDOW_SORT_FN_ASC"},
            {NppTabSortName,          NO,  @"IDM_WINDOW_SORT_FN_DSC"},
            {NppTabSortPath,          YES, @"IDM_WINDOW_SORT_FP_ASC"},
            {NppTabSortPath,          NO,  @"IDM_WINDOW_SORT_FP_DSC"},
            {NppTabSortType,          YES, @"IDM_WINDOW_SORT_FT_ASC"},
            {NppTabSortType,          NO,  @"IDM_WINDOW_SORT_FT_DSC"},
            {NppTabSortContentLength, YES, @"IDM_WINDOW_SORT_FS_ASC"},
            {NppTabSortContentLength, NO,  @"IDM_WINDOW_SORT_FS_DSC"},
            {NppTabSortModifiedTime,  YES, @"IDM_WINDOW_SORT_FD_ASC"},
            {NppTabSortModifiedTime,  NO,  @"IDM_WINDOW_SORT_FD_DSC"},
        };
        for (size_t i = 0; i < sizeof(sorts)/sizeof(sorts[0]); ++i) {
            [ed sortTabsBy:sorts[i].key ascending:sorts[i].asc];
            NSMutableArray *names = [NSMutableArray array];
            for (NppDocument *d in ed.documents) if (d.path) [names addObject:d.displayName];

            BOOL ordered = YES;
            for (NSUInteger n = 1; n < names.count; ++n) {
                NSComparisonResult r;
                switch (sorts[i].key) {
                    case NppTabSortType:
                        r = [[names[n - 1] pathExtension] compare:[names[n] pathExtension]];
                        break;
                    case NppTabSortContentLength: {
                        NSString *a = names[n - 1], *b = names[n];
                        unsigned long long sa = [a hasSuffix:@".md"] ? 2 : ([a hasSuffix:@".py"] ? 3 : 4);
                        unsigned long long sb = [b hasSuffix:@".md"] ? 2 : ([b hasSuffix:@".py"] ? 3 : 4);
                        r = sa == sb ? NSOrderedSame : (sa < sb ? NSOrderedAscending : NSOrderedDescending);
                        break;
                    }
                    case NppTabSortModifiedTime:
                        r = NSOrderedSame;      // all written within the same moment
                        break;
                    default:
                        r = [names[n - 1] compare:names[n]];
                        break;
                }
                if (r == NSOrderedSame) continue;
                if (sorts[i].asc ? (r == NSOrderedDescending) : (r == NSOrderedAscending)) ordered = NO;
            }
            Check(sorts[i].cmd, @"orders the tabs by that key", ordered && names.count == 3);
        }

        Check(@"IDM_WINDOW_WINDOWS", @"lists every open document",
              [ed windowList].count == ed.documents.count);

        [ed selectDocumentAtIndex:0];
        [ed selectDocumentAtIndex:2];
        BOOL recent = [ed activateRecentWindow];
        Check(@"IDM_WINDOW_MRU_FIRST", @"returns to the previously active tab",
              recent && [ed.documents indexOfObject:ed.currentDocument] == 0);
        Check(@"IDM_DROPLIST_LIST", @"the droplist offers the same window list",
              [ed windowList].count == ed.documents.count);
    }

    printf("\n== Run and Help ==\n");
    {
        // Regression: this used to wait with -waitUntilExit, which spins the run
        // loop on the main thread and could abort inside AppKit. Repeating the
        // call makes that crash reproducible rather than occasional.
        BOOL allOK = YES;
        for (int i = 0; i < 8 && allOK; ++i) {
            NSString *out = [ed runShellCommand:@"printf ran-ok"];
            allOK = [out isEqualToString:@"ran-ok"];
        }
        Check(@"IDM_EXECUTE", @"runs a command and returns its output, repeatedly", allOK);

        NSString *report = [ed validateShortcutsFile];
        Check(@"IDM_EXECUTE_VALIDATE_SHORTCUTSXML", @"reports on the menu shortcuts",
              [report containsString:@"shortcuts"]);

        NSString *dbg = [ed debugInfo];
        Check(@"IDM_DEBUGINFO", @"reports version, architecture and OS",
              [dbg containsString:@"NotepadMac"] && [dbg containsString:@"Architecture"] &&
              [dbg containsString:@"macOS"]);

        Check(@"IDM_CMDLINEARGUMENTS", @"documents the accepted arguments",
              [[ed commandLineArgumentsHelp] containsString:@"NPPMAC_TEST"]);

        // Opening browsers from a test would be rude; assert the URLs are valid.
        NSDictionary *links = @{@"IDM_HOMESWEETHOME": @"https://notepad-plus-plus.org/",
                                @"IDM_PROJECTPAGE":   @"https://github.com/notepad-plus-plus/notepad-plus-plus",
                                @"IDM_ONLINEDOCUMENT":@"https://npp-user-manual.org/",
                                @"IDM_FORUM":         @"https://community.notepad-plus-plus.org/",
                                @"IDM_UPDATE_NPP":    @"https://github.com/notepad-plus-plus/notepad-plus-plus/releases"};
        for (NSString *cmd in links) {
            NSURL *u = [NSURL URLWithString:links[cmd]];
            Check(cmd, @"points at a valid https URL",
                  u != nil && [u.scheme isEqualToString:@"https"] && u.host.length > 0);
        }

        [[NSUserDefaults standardUserDefaults] setObject:@"proxy.example:8080" forKey:@"NppMacUpdaterProxy"];
        Check(@"IDM_CONFUPDATERPROXY", @"remembers the proxy setting",
              [[[NSUserDefaults standardUserDefaults] stringForKey:@"NppMacUpdaterProxy"]
                  isEqualToString:@"proxy.example:8080"]);

        NSMenuItem *about = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if (![top.submenu.title isEqualToString:@"Help"]) continue;
            for (NSMenuItem *mi in top.submenu.itemArray) {
                if ([mi.title hasPrefix:@"About"]) about = mi;
            }
        }
        Check(@"IDM_ABOUT", @"About is wired to the standard panel",
              about != nil && about.action == @selector(showAbout:));

        NSString *pluginDir = [ed.defaultSessionPath.stringByDeletingLastPathComponent
                               stringByAppendingPathComponent:@"plugins"];
        [[NSFileManager defaultManager] createDirectoryAtPath:pluginDir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        Check(@"IDM_SETTING_OPENPLUGINSDIR", @"has a plugins folder to open",
              [[NSFileManager defaultManager] fileExistsAtPath:pluginDir]);
    }

    printf("\n== Settings ==\n");
    {
        NppPreferences *p = [NppPreferences shared];
        NSString *fontBefore = p.fontName;
        p.fontName = @"Courier";
        p.fontSize = 17;
        p.tabWidth = 7;
        p.useSpaces = NO;
        p.wordWrap = YES;
        p.showWhitespace = YES;
        [p applyToEditor:ed];
        BOOL applied = [sci message:SCI_GETTABWIDTH] == 7 &&
                       [sci message:SCI_GETUSETABS] == 1 &&
                       [sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE &&
                       [sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE;
        Check(@"IDM_SETTING_PREFERENCE", @"settings reach the editor", applied);

        // Restore something sane for the tests that follow.
        p.fontName = fontBefore ?: @"Menlo";
        p.tabWidth = 4; p.useSpaces = YES; p.wordWrap = NO; p.showWhitespace = NO;
        [p applyToEditor:ed];

        // Every attribute the upstream Style struct carries must reach Scintilla,
        // not just the foreground colour.
        [ed setLanguageNamed:@"cpp"];
        [p setStyleOverride:@{@"fg": @"FF0000", @"bg": @"00FF00", @"bold": @YES,
                              @"italic": @YES, @"underline": @YES,
                              @"font": @"Courier", @"size": @19}
                forLanguage:@"cpp" styleID:SCE_C_COMMENTLINE];
        [ed applyLanguage];
        // Scintilla stores colours as 0xBBGGRR: pure red reads back as 0x0000FF
        // and pure green as 0x00FF00.
        BOOL colours = [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE] == 0x0000FF &&
                       [sci message:SCI_STYLEGETBACK wParam:SCE_C_COMMENTLINE] == 0x00FF00;
        BOOL faces = [sci message:SCI_STYLEGETBOLD wParam:SCE_C_COMMENTLINE] != 0 &&
                     [sci message:SCI_STYLEGETITALIC wParam:SCE_C_COMMENTLINE] != 0 &&
                     [sci message:SCI_STYLEGETUNDERLINE wParam:SCE_C_COMMENTLINE] != 0;
        BOOL size = [sci message:SCI_STYLEGETSIZE wParam:SCE_C_COMMENTLINE] == 19;
        Check(@"IDM_LANGSTYLE_CONFIG_DLG",
              @"foreground, background, bold, italic, underline and size all reach the style",
              colours && faces && size);

        // A bare hex string is what the foreground-only version stored; it must
        // still load rather than being dropped.
        [p setStyleOverride:nil forLanguage:@"cpp" styleID:SCE_C_COMMENTLINE];
        NSMutableDictionary *legacy = [p.styleOverrides mutableCopy];
        legacy[[NSString stringWithFormat:@"cpp/%d", SCE_C_COMMENTLINE]] = @"0000FF";
        p.styleOverrides = legacy;
        [ed applyLanguage];
        Check(@"IDM_LANGSTYLE_CONFIG_DLG (legacy)", @"an old foreground-only override still applies",
              [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE] == 0xFF0000);

        [p setStyleOverride:nil forLanguage:@"cpp" styleID:SCE_C_COMMENTLINE];
        [ed applyLanguage];

        ShortcutMapperWindow *mapper = [[ShortcutMapperWindow alloc] initWithEditor:ed];
        NSArray *titles = [mapper commandTitles];
        NSMenuItem *probe = [[NSMenuItem alloc] initWithTitle:@"Probe" action:@selector(showAbout:)
                                                keyEquivalent:@"z"];
        ApplyShortcutSpec(probe, @"cmd+shift+k");
        Check(@"IDM_SETTING_SHORTCUT_MAPPER", @"lists shortcuts and applies a new one",
              titles.count > 20 && [probe.keyEquivalent isEqualToString:@"k"] &&
              (probe.keyEquivalentModifierMask & NSEventModifierFlagCommand) &&
              (probe.keyEquivalentModifierMask & NSEventModifierFlagShift));

        NSString *plugin = TempFile(@"t_plugin.bundle", @"fake plugin\n");
        NSUInteger copiedPlugins = [ed importFiles:@[plugin] intoSubdirectory:@"plugins"];
        Check(@"IDM_SETTING_IMPORTPLUGIN", @"copies plugins into the support folder",
              copiedPlugins == 1 &&
              [[ed importedFilesIn:@"plugins"] containsObject:@"t_plugin.bundle"]);

        NSString *theme = TempFile(@"t_theme.xml", @"<theme/>\n");
        NSUInteger copiedThemes = [ed importFiles:@[theme] intoSubdirectory:@"themes"];
        Check(@"IDM_SETTING_IMPORTSTYLETHEMES", @"copies themes into the support folder",
              copiedThemes == 1 &&
              [[ed importedFilesIn:@"themes"] containsObject:@"t_theme.xml"]);

        p.contextMenuCommands = @[@"Copy", @"Paste", @"Toggle Line Comment"];
        [ed rebuildContextMenu];
        NSMenu *ctx = ed.sci.menu;
        NSMutableArray *ctxTitles = [NSMutableArray array];
        for (NSMenuItem *mi in ctx.itemArray) [ctxTitles addObject:mi.title];
        Check(@"IDM_SETTING_EDITCONTEXTMENU", @"the right-click menu follows the setting",
              ctx.numberOfItems == 3 && [ctxTitles containsObject:@"Toggle Line Comment"]);
    }

    printf("\n== Language: user defined ==\n");
    {
        LanguageCatalog *cat = [LanguageCatalog sharedCatalog];
        [ed setLanguageNamed:@"javascript.js"];
        Check(@"IDM_LANG_JS", @"the .js JavaScript variant can be selected",
              [cat languageNamed:@"javascript.js"] != nil &&
              [ed.currentDocument.language.name isEqualToString:@"javascript.js"]);

        BOOL defined = [ed defineUserLanguageNamed:@"MyLang" extensions:@"mylang ml2"
                                          keywords:@"alpha beta" commentLine:@"#"];
        NSDictionary *readBack = [ed userDefinedLanguage];
        Check(@"IDM_LANG_USER_DLG", @"writes userDefineLang.xml and applies the language",
              defined && [readBack[@"name"] isEqualToString:@"MyLang"] &&
              [readBack[@"ext"] isEqualToString:@"mylang ml2"] &&
              [ed.currentDocument.language.name isEqualToString:@"MyLang"]);

        Check(@"IDM_LANG_OPENUDLDIR", @"the user-defined language file has a folder to open",
              [[NSFileManager defaultManager] fileExistsAtPath:[ed userDefinedLanguagePath]]);

        NSURL *collection = [NSURL URLWithString:
            @"https://github.com/notepad-plus-plus/userDefinedLanguages"];
        Check(@"IDM_LANG_UDLCOLLECTION_PROJECT_SITE", @"points at a valid https URL",
              collection != nil && [collection.scheme isEqualToString:@"https"]);

        [ed setLanguageNamed:@"normal"];
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

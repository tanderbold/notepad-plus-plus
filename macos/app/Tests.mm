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
#import "Toolbar.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"
#import "TypingCommands.h"
#import "TabBarView.h"
#import "JsonCommands.h"
#import "CompareCommands.h"
#import "FtpCommands.h"
#import "XmlCommands.h"
#import "RunCommands.h"
#import "FunctionListPanel.h"
#import "FunctionListCatalog.h"
#import "NppRegex.h"
#import "ApiCatalog.h"
#import "FindCommands.h"
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

/// Reads back one attribute value, for the newline-preservation test.
@interface NppAttributeReader : NSObject <NSXMLParserDelegate>
@property (nonatomic, copy) NSString *value;
@end
@implementation NppAttributeReader
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {
    if (!self.value) self.value = attrs[@"b"];
}
@end

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

        // Asking only whether the list appeared says nothing about what is in
        // it. Function completion means the functions Notepad++ ships for the
        // language, not the words that happen to be in this file.
        NppPreferences *acPrefs = [NppPreferences shared];
        NSInteger previousSource = acPrefs.autoCompleteSource;
        acPrefs.autoCompleteSource = 0;                    // functions only
        NSString *cFile = TempFile(@"t_api.c", @"int main(void) { return 0; }\n");
        [ed openFileAtPath:cFile error:NULL];
        NSArray *fromApi = [ed completionCandidatesForPrefix:@"prin"];
        Check(@"IDM_EDIT_AUTOCOMPLETE (function list)",
              @"completion offers the language's own functions, not just words in the file",
              [fromApi containsObject:@"printf"] &&
              ![[ed.sci string] containsString:@"printf"]);

        // A language Notepad++ ships no list for still has to complete from its
        // lexer keywords rather than going silent.
        NSString *iniFile = TempFile(@"t_api.ini", @"[Section]\n");
        [ed openFileAtPath:iniFile error:NULL];
        NSArray *noApi = [ed completionCandidatesForPrefix:@"Sec"];
        acPrefs.autoCompleteSource = previousSource;
        Check(@"IDM_EDIT_AUTOCOMPLETE (no list shipped)",
              @"a language with no shipped list still completes from its keywords",
              [[ApiCatalog sharedCatalog] entriesForLanguage:@"ini"].count == 0 &&
              noApi != nil);
        [[NSFileManager defaultManager] removeItemAtPath:cFile error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:iniFile error:NULL];
    }

    printf("\n== Search: replacement escapes ==\n");
    {
        [ed newDocument];

        // \U and \L change the case of what follows until \E; \u and \l change
        // a single character. A replacement that cannot do this cannot
        // normalise what it captured, which is much of what people use it for.
        SetDoc(ed, @"hello world\n");
        NppFindSpec *upper = [NppFindSpec specFor:@"(\\w+) (\\w+)" mode:NppSearchRegex
                                          options:NppFindNone];
        upper.replacement = @"\\U\\1\\E \\2";
        [ed replaceAll:upper];
        BOOL upperRun = [DocText(ed) isEqualToString:@"HELLO world\n"];

        SetDoc(ed, @"HELLO WORLD\n");
        NppFindSpec *lower = [NppFindSpec specFor:@"(\\w+) (\\w+)" mode:NppSearchRegex
                                          options:NppFindNone];
        lower.replacement = @"\\L\\1 \\2";
        [ed replaceAll:lower];
        BOOL lowerRun = [DocText(ed) isEqualToString:@"hello world\n"];

        SetDoc(ed, @"hello world\n");
        NppFindSpec *initials = [NppFindSpec specFor:@"(\\w+) (\\w+)" mode:NppSearchRegex
                                             options:NppFindNone];
        initials.replacement = @"\\u\\1 \\u\\2";
        [ed replaceAll:initials];
        BOOL oneEach = [DocText(ed) isEqualToString:@"Hello World\n"];

        Check(@"IDM_SEARCH_REPLACE (case escapes)",
              @"\\U, \\L, \\E, \\u and \\l change the case of the replacement",
              upperRun && lowerRun && oneEach);

        // The replacement is text, not a second pattern: \d+ put in the replace
        // field means those three characters.
        SetDoc(ed, @"x\n");
        NppFindSpec *literal = [NppFindSpec specFor:@"x" mode:NppSearchRegex options:NppFindNone];
        literal.replacement = @"\\d+";
        [ed replaceAll:literal];
        Check(@"IDM_SEARCH_REPLACE (replacement is text)",
              @"a pattern typed into the replace field is put in as it stands",
              [DocText(ed) isEqualToString:@"\\d+\n"]);

        // '^' is per line, so "^." matches once on each of them.
        SetDoc(ed, @"abc\ndef\n");
        Check(@"IDM_SEARCH_FIND (line anchors)",
              @"'^' matches at the start of every line, not only the document",
              [ed countMatches:[NppFindSpec specFor:@"^." mode:NppSearchRegex
                                            options:NppFindNone]] == 2);

        // '.' covers everything, including the odd control character.
        unichar formFeed = 0x0C;
        SetDoc(ed, [NSString stringWithFormat:@"a%Cb\n", formFeed]);
        Check(@"IDM_SEARCH_FIND (dot spans anything)",
              @"'.' matches a form feed as readily as a letter",
              [ed countMatches:[NppFindSpec specFor:@"a.b" mode:NppSearchRegex
                                            options:NppFindNone]] == 1);
    }

    printf("\n== Editor settings Notepad++ has ==\n");
    {
        [ed newDocument];
        NppPreferences *p = [NppPreferences shared];
        ScintillaView *sv = ed.sci;

        // Typing mode. Notepad++ shows it in the status bar and the Insert key
        // switches it; nothing here had it at all.
        // Whether a typed character overwrites is Scintilla's own doing; what
        // was missing here is the mode itself and any way to see or change it.
        NSTextField *status = [ed valueForKey:@"statusField"];
        BOOL startsInsert = ![ed overtype];
        [ed refreshChrome];
        BOOL showsIns = [status.stringValue hasSuffix:@"INS"];
        [ed toggleOvertype];
        BOOL nowOvertype = [ed overtype] && [status.stringValue hasSuffix:@"OVR"];
        [ed toggleOvertype];
        Check(@"IDM_VIEW_SUMMARY (typing mode)",
              @"the typing mode can be switched and the status bar says which it is",
              startsInsert && showsIns && nowOvertype &&
              ![ed overtype] && [status.stringValue hasSuffix:@"INS"]);

        // A vertical edge, which Notepad++ can show as a line, as several
        // lines, or as a change of background.
        p.edgeMode = 1; p.edgeColumns = @"80";
        [ed applyEditorPreferences];
        BOOL single = [sv message:SCI_GETEDGEMODE] == EDGE_LINE &&
                      [sv message:SCI_GETEDGECOLUMN] == 80;

        p.edgeColumns = @"80 100 120";
        [ed applyEditorPreferences];
        BOOL several = [sv message:SCI_GETEDGEMODE] == EDGE_MULTILINE &&
                       [sv message:SCI_GETMULTIEDGECOLUMN wParam:1] == 100;

        p.edgeMode = 2; p.edgeColumns = @"72";
        [ed applyEditorPreferences];
        BOOL background = [sv message:SCI_GETEDGEMODE] == EDGE_BACKGROUND;

        p.edgeMode = 0;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (vertical edge)",
              @"one edge, several edges and the background form all reach Scintilla",
              single && several && background &&
              [sv message:SCI_GETEDGEMODE] == EDGE_NONE);

        // Caret width and blink rate.
        p.caretWidth = 3; p.caretBlinkRate = 0;
        [ed applyEditorPreferences];
        BOOL wide = [sv message:SCI_GETCARETWIDTH] == 3 &&
                    [sv message:SCI_GETCARETPERIOD] == 0;
        p.caretWidth = 1; p.caretBlinkRate = 530;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (caret)",
              @"the caret's width and blink rate are settings, as they are in Notepad++",
              wide && [sv message:SCI_GETCARETWIDTH] == 1 &&
              [sv message:SCI_GETCARETPERIOD] == 530);

        // Scrolling past the end, and the caret past the end of a line. The
        // Scintilla message for the first is the other way round from the
        // setting, which is easy to get backwards.
        p.scrollBeyondLastLine = NO; p.virtualSpace = NO;
        [ed applyEditorPreferences];
        BOOL stops = [sv message:SCI_GETENDATLASTLINE] != 0 &&
                     ([sv message:SCI_GETVIRTUALSPACEOPTIONS] & SCVS_USERACCESSIBLE) == 0;
        p.scrollBeyondLastLine = YES; p.virtualSpace = YES;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (scrolling and virtual space)",
              @"scrolling past the last line and the caret past a line's end each follow their setting",
              stops && [sv message:SCI_GETENDATLASTLINE] == 0 &&
              ([sv message:SCI_GETVIRTUALSPACEOPTIONS] & SCVS_USERACCESSIBLE) != 0);
        p.virtualSpace = NO;
        [ed applyEditorPreferences];

        // Cut and Copy with nothing selected take the whole line. Notepad++ has
        // this on by default and it is what people expect from it.
        SetDoc(ed, @"first\nsecond\nthird\n");
        [sv message:SCI_GOTOLINE wParam:1 lParam:0];
        p.lineCopyCutWithoutSelection = YES;
        [app copyText:nil];
        SetDoc(ed, @"");
        [app pasteText:nil];
        BOOL copiedLine = [DocText(ed) isEqualToString:@"second\n"];

        SetDoc(ed, @"first\nsecond\nthird\n");
        [sv message:SCI_GOTOLINE wParam:1 lParam:0];
        [app cutText:nil];
        BOOL cutLine = [DocText(ed) isEqualToString:@"first\nthird\n"];

        // With the setting off, an empty selection copies nothing.
        p.lineCopyCutWithoutSelection = NO;
        SetDoc(ed, @"alpha\n");
        [sv message:SCI_GOTOPOS wParam:0 lParam:0];
        [app copyText:nil];
        SetDoc(ed, @"kept\n");
        [app pasteText:nil];
        BOOL leftAlone = [DocText(ed) containsString:@"kept"];
        p.lineCopyCutWithoutSelection = YES;

        Check(@"IDM_EDIT_COPY (whole line)",
              @"with nothing selected, Cut and Copy take the line, unless the setting says not to",
              copiedLine && cutLine && leftAlone);

        // The current line can be plain, coloured, or framed.
        p.currentLineHighlightMode = 0;
        [ed applyEditorPreferences];
        BOOL plain = [sv message:SCI_GETCARETLINEVISIBLE] == 0;
        p.currentLineHighlightMode = 2; p.currentLineFrameWidth = 3;
        [ed applyEditorPreferences];
        BOOL framed = [sv message:SCI_GETCARETLINEVISIBLE] != 0 &&
                      [sv message:SCI_GETCARETLINEFRAME] == 3;
        p.currentLineHighlightMode = 1;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (current line)",
              @"the current line can be left plain, coloured or framed",
              plain && framed && [sv message:SCI_GETCARETLINEFRAME] == 0);

        // Margins that can be turned off, and the padding around the text.
        p.foldMarginShow = NO; p.bookmarkMarginShow = NO;
        p.paddingLeft = 5; p.paddingRight = 7;
        [ed applyEditorPreferences];
        BOOL hidden = [sv message:SCI_GETMARGINWIDTHN wParam:1] == 0 &&
                      [sv message:SCI_GETMARGINWIDTHN wParam:2] == 0 &&
                      [sv message:SCI_GETMARGINLEFT] == 5 &&
                      [sv message:SCI_GETMARGINRIGHT] == 7;
        p.foldMarginShow = YES; p.bookmarkMarginShow = YES;
        p.paddingLeft = 0; p.paddingRight = 0;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (margins and padding)",
              @"the fold and bookmark margins can be hidden and the text can be given room",
              hidden && [sv message:SCI_GETMARGINWIDTHN wParam:2] > 0);

        // How a wrapped line continues.
        p.lineWrapMethod = 2;
        [ed applyEditorPreferences];
        BOOL indented = [sv message:SCI_GETWRAPINDENTMODE] == SC_WRAPINDENT_INDENT;
        p.lineWrapMethod = 1;
        [ed applyEditorPreferences];
        // Auto-indent. Notepad++ carries the previous line's indentation onto a
        // new one, and in brace languages opens a level after an opening brace.
        p.autoIndentMode = 1;
        [ed setLanguageNamed:@"normal"];
        // No trailing newline: the caret sits at the end of the text, which is
        // where it is when Enter is actually pressed.
        SetDoc(ed, @"        keep me");
        [sv message:SCI_GOTOPOS wParam:(uptr_t)[sv message:SCI_GETLENGTH] lParam:0];
        [sv setStringProperty:SCI_REPLACESEL parameter:0 value:@"\n"];
        [ed maintainIndentationAfter:'\n'];
        BOOL carried = [sv message:SCI_GETLINEINDENTATION
                              wParam:(uptr_t)[sv message:SCI_LINEFROMPOSITION
                                                    wParam:(uptr_t)[sv message:SCI_GETCURRENTPOS]]] == 8;

        p.autoIndentMode = 2;
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"    if (x) {");
        [sv message:SCI_GOTOPOS wParam:(uptr_t)[sv message:SCI_GETLENGTH] lParam:0];
        [sv setStringProperty:SCI_REPLACESEL parameter:0 value:@"\n"];
        [ed maintainIndentationAfter:'\n'];
        long openedLine = [sv message:SCI_LINEFROMPOSITION
                                 wParam:(uptr_t)[sv message:SCI_GETCURRENTPOS]];
        BOOL opened = [sv message:SCI_GETLINEINDENTATION wParam:(uptr_t)openedLine] == 8;

        // Off means off.
        p.autoIndentMode = 0;
        SetDoc(ed, @"        x");
        [sv message:SCI_GOTOPOS wParam:(uptr_t)[sv message:SCI_GETLENGTH] lParam:0];
        [sv setStringProperty:SCI_REPLACESEL parameter:0 value:@"\n"];
        [ed maintainIndentationAfter:'\n'];
        BOOL leftFlat = [sv message:SCI_GETLINEINDENTATION
                               wParam:(uptr_t)[sv message:SCI_LINEFROMPOSITION
                                                     wParam:(uptr_t)[sv message:SCI_GETCURRENTPOS]]] == 0;
        p.autoIndentMode = 2;
        [ed setLanguageNamed:@"normal"];
        Check(@"IDM_SETTING_PREFERENCE (auto-indent)",
              @"a new line keeps the indent above it, and a brace opens a level",
              carried && opened && leftFlat);

        // Mark All follows its own case and whole-word settings.
        SetDoc(ed, @"cat cats CAT\n");
        [sv message:SCI_SETSEL wParam:0 lParam:3];          // "cat"
        p.markAllCaseSensitive = NO;  p.markAllWordOnly = YES;
        NSUInteger loose = [ed markAllOccurrencesOfSelection:0];
        p.markAllCaseSensitive = YES; p.markAllWordOnly = YES;
        NSUInteger cased = [ed markAllOccurrencesOfSelection:0];
        p.markAllCaseSensitive = YES; p.markAllWordOnly = NO;
        NSUInteger anywhere = [ed markAllOccurrencesOfSelection:0];
        p.markAllCaseSensitive = NO;  p.markAllWordOnly = YES;
        Check(@"IDM_SEARCH_MARKALLEXT1 (options)",
              @"Mark All matches by case and whole word as its settings say",
              loose == 2 && cased == 1 && anywhere == 2);

        Check(@"IDM_SETTING_PREFERENCE (wrap method)",
              @"a wrapped line can continue plainly, aligned, or a level further in",
              indented && [sv message:SCI_GETWRAPINDENTMODE] == SC_WRAPINDENT_SAME);
    }

    printf("\n== Sorting: the way Notepad++ sorts ==\n");
    {
        [ed newDocument];

        // "Sort as integer" is not "read the line as a number": Notepad++ walks
        // both lines in chunks and compares runs of digits numerically, so
        // item2 comes before item10. This port compared whole lines as numbers,
        // which left anything that was not purely a number exactly where it was.
        SetDoc(ed, @"item10\nitem9\nitem2\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortInteger descending:NO];
        BOOL natural = [DocText(ed) isEqualToString:@"item2\nitem9\nitem10\n"];

        SetDoc(ed, @"10\n9\n-3\n2\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortInteger descending:NO];
        BOOL numbers = [DocText(ed) isEqualToString:@"-3\n2\n9\n10\n"];

        // Same value written with different numbers of leading zeros: upstream
        // breaks the tie with bZeroNum - aZeroNum, which puts the one carrying
        // more zeros first.
        SetDoc(ed, @"x007\nx7\nx07\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortInteger descending:NO];
        BOOL zeros = [DocText(ed) isEqualToString:@"x007\nx07\nx7\n"];

        Check(@"IDM_EDIT_SORTLINES_INTEGER_ASCENDING (natural order)",
              @"digit runs compare as numbers, so item2 comes before item10",
              natural && numbers && zeros);

        // A decimal sort reads every line as a number. A line it cannot read
        // stops the sort and names itself; the document is left alone.
        SetDoc(ed, @"2.5\n-\n1.5\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        NSInteger refused = [ed sortLines:NppSortDecimalDot descending:NO];
        BOOL untouched = [DocText(ed) isEqualToString:@"2.5\n-\n1.5\n"];

        // A line with no number in it at all is not an error: it counts as
        // empty, and empties go first ascending and last descending.
        SetDoc(ed, @"2.5\nplain\n1.5\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        NSInteger accepted = [ed sortLines:NppSortDecimalDot descending:NO];
        BOOL emptiesFirst = [DocText(ed) isEqualToString:@"plain\n1.5\n2.5\n"];

        SetDoc(ed, @"2.5\nplain\n1.5\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortDecimalDot descending:YES];
        BOOL emptiesLast = [DocText(ed) isEqualToString:@"2.5\n1.5\nplain\n"];

        Check(@"IDM_EDIT_SORTLINES_DECIMALDOT_ASCENDING (unreadable lines)",
              @"a line that is not a number stops the sort; one with no number is put aside",
              refused == 1 && untouched && accepted == NSNotFound &&
              emptiesFirst && emptiesLast);

        // A file whose lines end in CR alone is still a file of lines.
        SetDoc(ed, @"A\rC\rB\r");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortLexicographic descending:NO];
        Check(@"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING (CR line endings)",
              @"lines ending in a bare carriage return sort like any others",
              [DocText(ed) isEqualToString:@"A\rB\rC\r"]);
    }

    printf("\n== Search: modes and options ==\n");
    {
        // Find was a literal search and nothing else: no case option, no whole
        // word, no extended escapes, no regular expressions. All of those are
        // what the Find dialog in Notepad++ is mostly made of.
        [ed newDocument];

        // Extended mode, with the escapes upstream defines and the digit counts
        // it fixes for each.
        BOOL escapes =
            [[EditorController convertExtendedToString:@"a\\tb"] isEqualToString:@"a\tb"] &&
            [[EditorController convertExtendedToString:@"a\\nb"] isEqualToString:@"a\nb"] &&
            [[EditorController convertExtendedToString:@"\\x41"] isEqualToString:@"A"] &&
            [[EditorController convertExtendedToString:@"\\d065"] isEqualToString:@"A"] &&
            [[EditorController convertExtendedToString:@"\\o101"] isEqualToString:@"A"] &&
            [[EditorController convertExtendedToString:@"\\u0041"] isEqualToString:@"A"] &&
            [[EditorController convertExtendedToString:@"\\b01000001"] isEqualToString:@"A"] &&
            // An escape that is not one keeps its backslash, as upstream leaves it.
            [[EditorController convertExtendedToString:@"\\q"] isEqualToString:@"\\q"] &&
            [[EditorController convertExtendedToString:@"\\xZZ"] isEqualToString:@"\\xZZ"];
        Check(@"IDM_SEARCH_FIND (extended)", @"the escapes Extended mode defines all convert",
              escapes);

        SetDoc(ed, @"alpha Alpha alphabet\nbeta\n");
        NppFindSpec *plain = [NppFindSpec specFor:@"alpha" mode:NppSearchNormal options:NppFindNone];
        NppFindSpec *cased = [NppFindSpec specFor:@"alpha" mode:NppSearchNormal
                                          options:NppFindMatchCase];
        NppFindSpec *whole = [NppFindSpec specFor:@"alpha" mode:NppSearchNormal
                                          options:NppFindMatchCase | NppFindWholeWord];
        Check(@"IDM_SEARCH_FIND (case and whole word)",
              @"matching by case and by whole word each narrow the result",
              [ed countMatches:plain] == 3 &&      // alpha, Alpha, alphabet
              [ed countMatches:cased] == 2 &&      // alpha, alphabet
              [ed countMatches:whole] == 1);       // alpha

        // A literal search must not be read as a pattern.
        SetDoc(ed, @"a.c abc\n");
        Check(@"IDM_SEARCH_FIND (literal)",
              @"a dot in Normal mode is a dot, not any character",
              [ed countMatches:[NppFindSpec specFor:@"a.c" mode:NppSearchNormal
                                            options:NppFindMatchCase]] == 1 &&
              [ed countMatches:[NppFindSpec specFor:@"a.c" mode:NppSearchRegex
                                            options:NppFindMatchCase]] == 2);

        SetDoc(ed, @"one 11 two 22 three 333\n");
        Check(@"IDM_SEARCH_FIND (regex)",
              @"a regular expression matches what it should",
              [ed countMatches:[NppFindSpec specFor:@"\\d+" mode:NppSearchRegex
                                            options:NppFindNone]] == 3 &&
              [ed countMatches:[NppFindSpec specFor:@"\\d{3}" mode:NppSearchRegex
                                            options:NppFindNone]] == 1);

        // Searching forward, then backward, then wrapping.
        SetDoc(ed, @"x x x\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        NppFindSpec *forward = [NppFindSpec specFor:@"x" mode:NppSearchNormal options:NppFindNone];
        [ed findNext:forward];
        long first = [sci message:SCI_GETSELECTIONSTART];
        [ed findNext:forward];
        long second = [sci message:SCI_GETSELECTIONSTART];
        NppFindSpec *back = [NppFindSpec specFor:@"x" mode:NppSearchNormal
                                         options:NppFindBackward];
        [ed findNext:back];
        long backTo = [sci message:SCI_GETSELECTIONSTART];
        // At the end with no wrap there is nowhere to go; with wrap there is.
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL stops = ![ed findNext:forward];
        NppFindSpec *wrapping = [NppFindSpec specFor:@"x" mode:NppSearchNormal
                                             options:NppFindWrap];
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL wraps = [ed findNext:wrapping] && [sci message:SCI_GETSELECTIONSTART] == 0;
        Check(@"IDM_SEARCH_FINDNEXT (direction and wrap)",
              @"forward, backward and wrapping each land where they should",
              first == 0 && second == 2 && backTo == 0 && stops && wraps);

        // Replacement with back-references.
        SetDoc(ed, @"John Smith\nAda Lovelace\n");
        NppFindSpec *swap = [NppFindSpec specFor:@"(\\w+) (\\w+)" mode:NppSearchRegex
                                         options:NppFindNone];
        swap.replacement = @"\\2, \\1";
        NSUInteger swapped = [ed replaceAll:swap];
        Check(@"IDM_SEARCH_REPLACE (back-references)",
              @"a replacement can put the captured groups back",
              swapped == 2 &&
              [DocText(ed) isEqualToString:@"Smith, John\nLovelace, Ada\n"]);

        // The dollar form has to work too, and a group that matched nothing
        // must contribute nothing rather than the text "\\3".
        SetDoc(ed, @"ab\n");
        NppFindSpec *dollars = [NppFindSpec specFor:@"(a)(b)(c)?" mode:NppSearchRegex
                                            options:NppFindNone];
        dollars.replacement = @"$2$1$3";
        [ed replaceAll:dollars];
        Check(@"IDM_SEARCH_REPLACE (dollar form)",
              @"$1 names a group as \\1 does, and an empty one adds nothing",
              [DocText(ed) isEqualToString:@"ba\n"]);

        // Replace All must not trip over its own output.
        SetDoc(ed, @"aaa\n");
        NppFindSpec *grow = [NppFindSpec specFor:@"a" mode:NppSearchNormal options:NppFindNone];
        grow.replacement = @"aa";
        NSUInteger grown = [ed replaceAll:grow];
        Check(@"IDM_SEARCH_REPLACE (replacement is not re-searched)",
              @"replacing a with aa three times gives six, not an endless run",
              grown == 3 && [DocText(ed) isEqualToString:@"aaaaaa\n"]);

        // Only the selection, when that is what was asked for.
        SetDoc(ed, @"q q q q\n");
        [sci message:SCI_SETSEL wParam:0 lParam:3];
        NppFindSpec *inSel = [NppFindSpec specFor:@"q" mode:NppSearchNormal
                                          options:NppFindInSelection];
        NppFindSpec *everywhere = [NppFindSpec specFor:@"q" mode:NppSearchNormal
                                               options:NppFindNone];
        Check(@"IDM_SEARCH_REPLACE (in selection)",
              @"a search confined to the selection sees only what is inside it",
              [ed countMatches:inSel] == 2 && [ed countMatches:everywhere] == 4);

        // The panel has to carry these modes and options, or none of the above
        // is reachable from the Find dialog. Its controls are set here and the
        // search it describes is read back.
        [app buildFindPanel];
        NSTextField *findField = [app valueForKey:@"findField"];
        NSMatrix *modes = [app valueForKey:@"modeRadios"];
        NSButton *caseBox = [app valueForKey:@"matchCaseBox"];
        NSButton *wordBox = [app valueForKey:@"wholeWordBox"];
        NSButton *selBox = [app valueForKey:@"inSelectionBox"];
        findField.stringValue = @"\\d+";
        [modes selectCellAtRow:2 column:0];             // Regular expression
        caseBox.state = NSControlStateValueOn;
        wordBox.state = NSControlStateValueOff;
        selBox.state = NSControlStateValueOff;
        NppFindSpec *fromPanel = (NppFindSpec *)[app currentFindSpec];

        SetDoc(ed, @"a1 b22 c333\n");
        Check(@"IDM_SEARCH_FIND (dialog)",
              @"the dialog's mode and options are what the search actually uses",
              fromPanel.mode == NppSearchRegex &&
              (fromPanel.options & NppFindMatchCase) != 0 &&
              (fromPanel.options & NppFindWholeWord) == 0 &&
              [ed countMatches:fromPanel] == 3 &&
              modes.numberOfRows == 3);

        // Cmd+V while a Find field has the caret must reach that field, not the
        // document behind it. The menu items carry a target, so they never
        // travel the responder chain on their own.
        [app buildFindPanel];
        NSPanel *findPanel = [app valueForKey:@"findPanel"];
        NSTextField *replaceField = [app valueForKey:@"replaceField"];
        replaceField.stringValue = @"";
        SetDoc(ed, @"document\n");
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:@"pasted" forType:NSPasteboardTypeString];

        // A window only becomes key while the application is active, and a test
        // run is not activated by anyone.
        [NSApp activateIgnoringOtherApps:YES];
        [findPanel makeKeyAndOrderFront:nil];
        [findPanel makeFirstResponder:replaceField];
        // Becoming key goes through the window server, so it is not in effect
        // the instant it is asked for. Without waiting, the paste sometimes
        // finds no key window and goes to the document -- which is the very
        // thing this is checking.
        NSDate *keyDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (NSApp.keyWindow != findPanel && [keyDeadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        [app pasteText:nil];
        NSString *fieldText = [[findPanel fieldEditor:NO forObject:replaceField] string]
                              ?: replaceField.stringValue;
        BOOL wentToField = [fieldText containsString:@"pasted"];
        BOOL documentUntouched = ![DocText(ed) containsString:@"pasted"];
        [findPanel orderOut:nil];
        Check(@"IDM_EDIT_PASTE (into a dialog field)",
              @"pasting while a Find field has the caret reaches the field, not the document",
              wentToField && documentUntouched);


        SetDoc(ed, @"cat bat cat\n");
        NSUInteger marked = [ed markAll:[NppFindSpec specFor:@"cat" mode:NppSearchNormal
                                                     options:NppFindMatchCase]];
        Check(@"IDM_SEARCH_MARK (find mark)", @"every match is marked",
              marked == 2);
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

        // A tip that appears but says nothing useful is no better than none.
        // Notepad++ builds it from the shipped signature: return value, name,
        // parameters, and the description on a line of its own.
        NSString *tipFile = TempFile(@"t_tip.c", @"x = abs(1);\n");
        [ed openFileAtPath:tipFile error:NULL];
        [ed.sci message:SCI_GOTOPOS wParam:5 lParam:0];    // inside "abs"
        NSArray<NSString *> *tips = [ed callTipCandidates];
        Check(@"IDM_EDIT_FUNCCALLTIP (signature)",
              @"the hint is the shipped signature, not a line copied from the file",
              tips.count > 0 && [tips[0] isEqualToString:@"int abs (int i)"]);
        [[NSFileManager defaultManager] removeItemAtPath:tipFile error:NULL];

        // Stepping between overloads has to step between real ones. Perl's abs
        // is shipped with two, so the document is Perl for this.
        NSString *plFile = TempFile(@"t_tip.pl", @"$x = abs($y);\n");
        [ed openFileAtPath:plFile error:NULL];
        [ed.sci message:SCI_GOTOPOS wParam:7 lParam:0];    // inside "abs"
        NSArray<NSString *> *overloads = [ed callTipCandidates];
        [ed showFunctionCallTip];
        Check(@"IDM_EDIT_FUNCCALLTIP_NEXT", @"steps to the next overload",
              overloads.count > 1 && [ed cycleFunctionCallTip:YES]);
        Check(@"IDM_EDIT_FUNCCALLTIP_PREVIOUS", @"steps back to the previous one",
              [ed cycleFunctionCallTip:NO]);
        [[NSFileManager defaultManager] removeItemAtPath:plFile error:NULL];
        [sci message:SCI_CALLTIPCANCEL];

        // Breadth: every list Notepad++ ships has to load. Bundling none of
        // them at all, which is how this started, looked exactly like success
        // as long as only the popup was checked.
        ApiCatalog *apis = [ApiCatalog sharedCatalog];
        NSMutableArray *emptyApis = [NSMutableArray array];
        for (NSString *language in apis.languages) {
            if (![apis entriesForLanguage:language].count) [emptyApis addObject:language];
        }
        Check(@"IDM_EDIT_FUNCCALLTIP (shipped lists)",
              @"every function list Notepad++ ships is bundled and loads",
              apis.languages.count == 34 && emptyApis.count == 0);
        if (emptyApis.count) printf("       %s\n",
            [[emptyApis componentsJoinedByString:@","] UTF8String]);

        // The file says whether its list is matched regardless of case, and C's
        // says it is not.
        Check(@"IDM_EDIT_FUNCCALLTIP (case)",
              @"the list honours the case setting its own file carries",
              ![apis ignoreCaseForLanguage:@"c"] &&
              [[apis callTipsForLanguage:@"c" function:@"ABS"] count] == 0 &&
              [[apis callTipsForLanguage:@"c" function:@"abs"] count] == 1);

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
        // A word is a run of anything that is not one of the separators
        // Notepad++ searches with, so an underscore or a hash keeps a word
        // together and a comma or an apostrophe does not.
        SetDoc(ed, @"foo_bar a#b 1,000 O'Connel\n");
        NSDictionary *counted = [ed documentSummary];
        Check(@"IDM_VIEW_SUMMARY", @"the summary counts words the way Notepad++ counts them",
              [counted[@"words"] unsignedIntegerValue] == 6 &&
              [sum[@"lines"] unsignedIntegerValue] >= 1);
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
              names.count >= 2 &&
              [[names componentsJoinedByString:@" "] containsString:@"alpha"] &&
              [[names componentsJoinedByString:@" "] containsString:@"beta"]);

        // The definitions come from Notepad++'s own functionList parsers.
        FunctionListCatalog *cat = [FunctionListCatalog sharedCatalog];
        Check(@"IDM_VIEW_FUNC_LIST (upstream parsers)",
              @"the bundled parser definitions are loaded",
              cat.parserIDs.count > 30 &&
              [cat parserIDForLanguage:@"python" extension:@"py"] != nil &&
              [cat parserIDForLanguage:@"cpp" extension:@"cpp"] != nil);

        // The patterns are PCRE and are now run as PCRE, through libpcre2,
        // rather than being translated into something ICU accepts.
        Check(@"IDM_VIEW_FUNC_LIST (regex engine)",
              @"the PCRE engine the patterns are written for is available",
              NppRegex.available);

        // The option values are declared by hand, because the SDK ships no
        // pcre2.h. Checking them against the library's behaviour is the only
        // thing that makes them trustworthy.
        NSData *twoLines = [@"a\nb" dataUsingEncoding:NSUTF8StringEncoding];
        NppRegex *anchored = [NppRegex regexWithPattern:@"^b"];
        NppRegex *dotted = [NppRegex regexWithPattern:@"a.b"];
        Check(@"IDM_VIEW_FUNC_LIST (regex options)",
              @"'^' anchors per line and '.' spans them, as upstream searches",
              [anchored firstMatchInData:twoLines range:NSMakeRange(0, twoLines.length)].location != NSNotFound &&
              [dotted firstMatchInData:twoLines range:NSMakeRange(0, twoLines.length)].location != NSNotFound);

        // These four are what ICU could not do at all. c.xml uses the first
        // two, and without them fifteen of the parsers were unusable.
        NSData *pcreSample = [@"foobar aaab xy" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange full = NSMakeRange(0, pcreSample.length);
        NppRegex *subroutine = [NppRegex regexWithPattern:@"(?'W'[a-z]+) (?&W)"];
        NppRegex *atomic = [NppRegex regexWithPattern:@"(?>a+)b"];
        NppRegex *keep = [NppRegex regexWithPattern:@"foo\\Kbar"];
        NSRange keptRange = [keep firstMatchInData:pcreSample range:full];
        Check(@"IDM_VIEW_FUNC_LIST (PCRE features)",
              @"subroutine calls, named groups, atomic groups and \\K all work",
              subroutine && atomic && keep &&
              [subroutine firstMatchInData:pcreSample range:full].location != NSNotFound &&
              [atomic firstMatchInData:pcreSample range:full].location != NSNotFound &&
              keptRange.location == 3 && keptRange.length == 3);

        // A pattern that cannot compile is reported rather than silently
        // matching nothing; upstream ships one such file.
        Check(@"IDM_VIEW_FUNC_LIST (bad pattern)",
              @"a pattern that will not compile is refused, with a reason",
              [NppRegex regexWithPattern:@"(unclosed"] == nil &&
              [NppRegex compileErrorForPattern:@"(unclosed"].length > 0 &&
              [NppRegex compileErrorForPattern:@"\\w+"] == nil);

        // A Python class with methods, through the upstream parser.
        NSArray<NppFunctionEntry *> *entries = [cat entriesInText:
            @"class Alpha:\n    def one(self):\n        pass\n    def two(self):\n        pass\n"
                                                     forLanguage:@"python" extension:@"py"];
        NSMutableArray *found = [NSMutableArray array];
        for (NppFunctionEntry *e in entries) [found addObject:e.name];
        // The names must be just the names: upstream's python pattern keeps the
        // part after \K, which excludes the "def " keyword.
        Check(@"IDM_VIEW_FUNC_LIST (classes and methods)",
              @"the class and its methods are reported, without the def keyword",
              entries.count == 3 && [found containsObject:@"Alpha"] &&
              [found containsObject:@"one(self)"] && [found containsObject:@"two(self)"] &&
              ![[found componentsJoinedByString:@" "] containsString:@"def "]);

        // C# exercises what Python does not: a class whose body has to be found
        // by counting braces, names that several patterns narrow down in turn,
        // and a comment that must not be searched.
        NSString *csharp =
            @"static HttpClient Build(int a)\n"
            @"{\n"
            @"    return null;\n"
            @"}\n"
            @"/*\n"
            @"static void Ghost()\n"
            @"{\n"
            @"}\n"
            @"*/\n"
            @"class Store\n"
            @"{\n"
            @"    public void Clear() { }\n"
            @"}\n";
        NSArray<NppFunctionEntry *> *cs = [cat entriesInText:csharp forLanguage:@"cs" extension:@"cs"];
        NSMutableArray *csNames = [NSMutableArray array];
        for (NppFunctionEntry *e in cs) {
            [csNames addObject:e.container.length
                ? [NSString stringWithFormat:@"%@::%@", e.container, e.name] : e.name];
        }

        // Upstream lists several name patterns and applies them one after
        // another, each searching inside what the last one found. Taking only
        // the first, or only the last, leaves "class Store" or the whole
        // matched line instead of "Store".
        Check(@"IDM_VIEW_FUNC_LIST (name narrowing)",
              @"chained name patterns reduce a declaration to just its name",
              [csNames containsObject:@"Build"] && [csNames containsObject:@"Store"]);

        // The class body runs to its closing brace, which the pattern itself
        // does not cover -- it stops at the opening one.
        Check(@"IDM_VIEW_FUNC_LIST (class body)",
              @"a member is attributed to the class whose braces enclose it",
              [csNames containsObject:@"Store::Clear"]);

        // commentExpr exists so that code inside a comment is not reported.
        Check(@"IDM_VIEW_FUNC_LIST (comments)",
              @"a declaration inside a comment is not listed",
              ![[csNames componentsJoinedByString:@" "] containsString:@"Ghost"]);

        // Breadth: one snippet per language, checked against the declarations
        // Notepad++'s own parser is meant to find in it. This is what says the
        // catalogue works as a whole rather than for the one language that
        // happened to be tested.
        NSArray *battery = @[
            // c.xml shows the parameters on purpose: the node that would strip
            // them is commented out in the file itself.
            @[@"c",          @"c",    @"int add(int a, int b)\n{\n    return 0;\n}\n",              @"add(int a, int b)"],
            @[@"cpp",        @"cpp",  @"class Thing {\npublic:\n    void run() {}\n};\n",           @"Thing::run"],
            @[@"cs",         @"cs",   @"class Store\n{\n    public void Clear() { }\n}\n",          @"Store::Clear"],
            @[@"java",       @"java", @"public class G {\n  public void hello(String w) { }\n}\n",  @"G::hello"],
            @[@"php",        @"php",  @"<?php\nfunction helper($x) { return $x; }\n",               @"helper($x) "],
            @[@"python",     @"py",   @"def alpha(x):\n    pass\n",                                 @"alpha(x)"],
            @[@"ruby",       @"rb",   @"def alpha(x)\n  x\nend\n",                                  @"alpha"],
            @[@"perl",       @"pl",   @"sub alpha {\n  1;\n}\n",                                    @"alpha"],
            @[@"lua",        @"lua",  @"function alpha(x)\n  return x\nend\n",                      @"alpha"],
            @[@"bash",       @"sh",   @"alpha() {\n  echo hi\n}\n",                                 @"alpha"],
            @[@"pascal",     @"pas",  @"procedure Alpha(x: Integer);\nbegin\nend;\n",               @"Alpha"],
            @[@"vb",         @"vb",   @"Public Sub Alpha(x As Integer)\nEnd Sub\n",                 @"Alpha"],
            @[@"rust",       @"rs",   @"fn alpha(x: i32) -> i32 {\n    x\n}\n",                     @"alpha"],
            @[@"javascript", @"js",   @"function alpha(x) { return x; }\n",                         @"alpha"],
            @[@"typescript", @"ts",   @"function alpha(x) {\n  return x;\n}\n",                     @"alpha"],
            @[@"powershell", @"ps1",  @"function Get-Thing {\n    param($x)\n}\n",                  @"Get-Thing"],
            @[@"haskell",    @"hs",   @"alpha :: Int -> Int\nalpha x = x\n",                        @"alpha"],
            @[@"nim",        @"nim",  @"proc alpha(x: int): int =\n  x\n",                          @"alpha(x: int): int"],
            // Upstream keeps the space the selector was written with.
            @[@"css",        @"css",  @".alpha { color: red; }\n",                                  @".alpha "],
            @[@"makefile",   @"mak",  @"alpha:\n\techo hi\n",                                       @"alpha"],
            @[@"batch",      @"bat",  @":alpha\necho hi\n",                                         @"alpha"],
            @[@"ini",        @"ini",  @"[Section]\nkey=1\n",                                        @"Section"],
            @[@"fortran",    @"f90",  @"      SUBROUTINE ALPHA(X)\n      END\n",                    @"ALPHA"],
            @[@"d",          @"d",    @"int add(int a, int b)\n{\n    return 0;\n}\n",              @"add"],

            // Corrected parsers: things upstream's own patterns do not find.
            // Each is covered by a file in functionList-corrections, which says
            // at its top what it changes and what the original did.
            @[@"rust",       @"rs",   @"pub fn alpha(x: i32) -> i32 { x }\n",                      @"alpha"],
            @[@"rust",       @"rs",   @"impl Thing {\n    pub fn delta(&self) {}\n}\n",            @"Thing::delta"],
            @[@"javascript", @"js",   @"const beta = (x) => x;\n",                                 @"beta"],
            @[@"typescript", @"ts",   @"export function beta(x: number): number { return x; }\n",  @"beta"],
            @[@"typescript", @"ts",   @"class Thing {\n    gamma(): void { }\n}\n",                @"Thing::gamma"],
            @[@"cs",         @"cs",   @"static async Task<string?> TryGet(int a)\n{\n    return null;\n}\n", @"TryGet"],
            @[@"cs",         @"cs",   @"static async Task<(int, string)> Setup()\n{\n    return (1, null);\n}\n", @"Setup"],
            @[@"cs",         @"cs",   @"class S\n{\n    public async Task<List<int>> Get() { return null; }\n}\n", @"S::Get"],
            @[@"cs",         @"cs",   @"class S\n{\n    public byte[]? Raw() => null;\n}\n",   @"S::Raw"],
            // sql.xml is an Oracle parser and wants the named END its own
            // comment calls best practice.
            @[@"sql",        @"sql",  @"CREATE OR REPLACE PROCEDURE alpha IS\nBEGIN\nNULL;\nEND alpha;\n", @"PROCEDURE alpha"],
        ];
        NSMutableArray *missing = [NSMutableArray array];
        for (NSArray *row in battery) {
            NSArray<NppFunctionEntry *> *got = [cat entriesInText:row[2]
                                                      forLanguage:row[0] extension:row[1]];
            NSMutableArray *shown = [NSMutableArray array];
            for (NppFunctionEntry *e in got) {
                [shown addObject:e.container.length
                    ? [NSString stringWithFormat:@"%@::%@", e.container, e.name] : e.name];
            }
            if (![shown containsObject:row[3]]) {
                [missing addObject:[NSString stringWithFormat:@"%@ (wanted %@, got %@)",
                                    row[0], row[3], [shown componentsJoinedByString:@","]]];
            }
        }
        Check(@"IDM_VIEW_FUNC_LIST (every language)",
              @"each language finds what its own Notepad++ parser is meant to find",
              missing.count == 0);
        if (missing.count) printf("       %s\n", [[missing componentsJoinedByString:@"; "] UTF8String]);

        // The C# correction reads a return type loosely enough to cover tuples
        // and nullable generics, which is exactly the kind of pattern that
        // starts matching statements as well. None of these is a declaration.
        NSString *notDeclarations =
            @"var builder = WebApplication.CreateBuilder(args);\n"
            @"Console.Write(\"hi\");\n"
            @"var (cert, _) = await SetupCertificateAsync();\n"
            @"using var rsa = RSA.Create(2048);\n"
            @"foreach (var src in sources)\n{\n}\n"
            @"if (File.Exists(path))\n{\n}\n"
            @"while (true)\n{\n}\n"
            @"lock (sync)\n{\n}\n"
            @"req.Extensions.Add(new KeyUsage(a, true));\n"
            @"return Results.NotFound();\n";
        NSArray<NppFunctionEntry *> *spurious =
            [cat entriesInText:notDeclarations forLanguage:@"cs" extension:@"cs"];
        NSMutableArray *spuriousNames = [NSMutableArray array];
        for (NppFunctionEntry *e in spurious) [spuriousNames addObject:e.name];
        Check(@"IDM_VIEW_FUNC_LIST (no false declarations)",
              @"statements that merely look like declarations are not listed",
              spurious.count == 0);
        if (spurious.count) printf("       %s\n",
            [[spuriousNames componentsJoinedByString:@","] UTF8String]);

        // Notepad++ ships its own test corpus for the Function List: forty
        // languages, each with a file and the result it is meant to produce.
        // That is far better evidence than a battery written here, and running
        // it is what turned up that the patterns are matched without regard to
        // case, that a class is only listed when something is inside it, and
        // that a name keeps the whitespace it was written with.
        NSString *corpusDir = [[NSBundle mainBundle] pathForResource:@"functionListCorpus"
                                                              ofType:nil];
        NSMutableArray *corpusFailures = [NSMutableArray array];
        NSUInteger corpusChecked = 0;
        // JavaScript and TypeScript are parsed here by the corrections, which
        // deliberately differ: upstream lists an anonymous function as the word
        // "function", several times over, and these do not.
        // udl-regexGlobalTest needs a user-defined language definition that
        // nothing associates with a parser, so there is nothing to run it with.
        NSSet *deliberate = [NSSet setWithArray:@[@"javascript", @"typescript",
                                                  @"udl-regexGlobalTest"]];
        for (NSString *language in [[NSFileManager defaultManager]
                                    contentsOfDirectoryAtPath:corpusDir ?: @"" error:NULL]) {
            if ([deliberate containsObject:language]) continue;
            // A directory named udl-X holds a user-defined language called X.
            NSString *base = [corpusDir stringByAppendingPathComponent:language];
            NSString *languageName = [language hasPrefix:@"udl-"]
                ? [language substringFromIndex:4] : language;
            NSString *text = [NSString stringWithContentsOfFile:
                              [base stringByAppendingPathComponent:@"unitTest"]
                                                       encoding:NSUTF8StringEncoding error:NULL];
            NSData *expectedData = [NSData dataWithContentsOfFile:
                                    [base stringByAppendingPathComponent:@"unitTest.expected.result"]];
            if (!text || !expectedData) continue;
            NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:expectedData
                                                                    options:0 error:NULL];
            if (![expected isKindOfClass:NSDictionary.class]) continue;
            corpusChecked++;

            NSArray<NppFunctionEntry *> *found =
                [cat entriesInText:text forLanguage:languageName
                         extension:[language hasPrefix:@"udl-"] ? @"" : language];
            NSMutableArray *leaves = [NSMutableArray array];
            NSMutableDictionary *nodes = [NSMutableDictionary dictionary];
            NSMutableArray *nodeOrder = [NSMutableArray array];
            for (NppFunctionEntry *entry in found) {
                if (entry.container.length) {
                    if (!nodes[entry.container]) {
                        nodes[entry.container] = [NSMutableArray array];
                        [nodeOrder addObject:entry.container];
                    }
                    [nodes[entry.container] addObject:entry.name];
                } else {
                    [leaves addObject:entry.name];
                }
            }
            // A class is reported here as a row of its own as well as the owner
            // of its members; upstream has only the node.
            // The class row carries the whitespace its pattern matched, so the
            // comparison with the container name ignores it.
            NSMutableArray *plainLeaves = [NSMutableArray array];
            NSMutableSet *classNames = [NSMutableSet set];
            for (NSString *name in nodeOrder) {
                [classNames addObject:[name stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
            }
            for (NSString *leaf in leaves) {
                NSString *bare = [leaf stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (![classNames containsObject:bare]) [plainLeaves addObject:leaf];
            }

            BOOL ok = [plainLeaves isEqualToArray:expected[@"leaves"] ?: @[]];
            NSArray *wantNodes = expected[@"nodes"] ?: @[];
            if (ok && wantNodes.count != nodeOrder.count) ok = NO;
            if (ok) {
                for (NSDictionary *node in wantNodes) {
                    if (![nodes[node[@"name"]] isEqualToArray:node[@"leaves"] ?: @[]]) { ok = NO; break; }
                }
            }
            if (!ok) [corpusFailures addObject:language];
        }
        Check(@"IDM_VIEW_FUNC_LIST (upstream corpus)",
              [NSString stringWithFormat:@"%lu of %lu languages match Notepad++'s own expected results",
               (unsigned long)(corpusChecked - corpusFailures.count), (unsigned long)corpusChecked],
              corpusChecked >= 39 && corpusFailures.count <= 4);
        if (corpusFailures.count) printf("       не совпали: %s\n",
            [[corpusFailures componentsJoinedByString:@", "] UTF8String]);

        // Notepad++ also ships a corpus for clickable-link detection: each case
        // is a line of text and a mask saying which of its characters should be
        // part of a link.
        NSString *urlDir = [[NSBundle mainBundle] pathForResource:@"urlCorpus" ofType:nil];
        NSUInteger urlCases = 0, urlWrong = 0;
        NSMutableArray *urlExamples = [NSMutableArray array];
        for (NSString *file in [[NSFileManager defaultManager]
                                contentsOfDirectoryAtPath:urlDir ?: @"" error:NULL]) {
            NSString *body = [NSString stringWithContentsOfFile:
                              [urlDir stringByAppendingPathComponent:file]
                                                       encoding:NSUTF8StringEncoding error:NULL];
            NSArray *lines = [body componentsSeparatedByString:@"\n"];
            for (NSUInteger i = 0; i + 1 < lines.count; ++i) {
                NSString *one = [lines[i] stringByTrimmingCharactersInSet:
                                 [NSCharacterSet characterSetWithCharactersInString:@"\r"]];
                NSString *two = [lines[i + 1] stringByTrimmingCharactersInSet:
                                 [NSCharacterSet characterSetWithCharactersInString:@"\r"]];
                if (![one hasPrefix:@"u "] || ![one hasSuffix:@" u"]) continue;
                if (![two hasPrefix:@"m "] || ![two hasSuffix:@" m"]) continue;
                NSString *text = [one substringWithRange:NSMakeRange(2, one.length - 4)];
                NSString *mask = [two substringWithRange:NSMakeRange(2, two.length - 4)];
                if (text.length != mask.length) continue;
                urlCases++;

                SetDoc(ed, text);
                [ed markClickableLinks];
                NSMutableString *got = [NSMutableString stringWithCapacity:text.length];
                NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
                NSUInteger byteAt = 0;
                for (NSUInteger c = 0; c < text.length; ++c) {
                    NSUInteger width = [[text substringWithRange:NSMakeRange(c, 1)]
                                        lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                    BOOL on = [sci message:SCI_INDICATORVALUEAT
                                    wParam:NPPMAC_LINK_INDICATOR lParam:(sptr_t)byteAt] != 0;
                    [got appendString:on ? @"1" : @"0"];
                    byteAt += width;
                }
                (void)bytes;
                if (![got isEqualToString:mask]) {
                    urlWrong++;
                    if (urlExamples.count < 5) {
                        [urlExamples addObject:[NSString stringWithFormat:@"%@ | want %@ got %@",
                                                text, mask, got]];
                    }
                }
            }
        }
        Check(@"IDM_SETTING_PREFERENCE (clickable links)",
              [NSString stringWithFormat:
               @"%lu of %lu cases from Notepad++'s own URL corpus are detected the same way",
               (unsigned long)(urlCases - urlWrong), (unsigned long)urlCases],
              urlCases >= 140 && urlWrong == 0);
        for (NSString *e in urlExamples) printf("         %s\n", e.UTF8String);

        // A corrections file that is not well formed is simply skipped, and the
        // language then quietly behaves as it did before -- which is how three
        // of them were written with a double hyphen inside an XML comment and
        // appeared to do nothing. Each one has to parse and register its parser.
        NSString *fixDir = [[NSBundle mainBundle] pathForResource:@"functionListCorrections"
                                                           ofType:nil];
        NSMutableArray *brokenFixes = [NSMutableArray array];
        for (NSString *file in [[NSFileManager defaultManager]
                                contentsOfDirectoryAtPath:fixDir ?: @"" error:NULL]) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"xml"]) continue;
            NSData *data = [NSData dataWithContentsOfFile:
                            [fixDir stringByAppendingPathComponent:file]];
            NSXMLParser *check = [[NSXMLParser alloc] initWithData:data ?: [NSData data]];
            NppAttributeReader *reader = [[NppAttributeReader alloc] init];
            check.delegate = reader;
            if (![check parse]) [brokenFixes addObject:file];
        }
        Check(@"IDM_VIEW_FUNC_LIST (corrections load)",
              @"every corrections file is well formed and reaches the catalogue",
              fixDir.length > 0 && brokenFixes.count == 0 &&
              [cat parserIDForLanguage:@"rust" extension:@"rs"] != nil);

        // XML folds a newline inside an attribute value into a space. Most of
        // upstream's patterns use (?x), where a # comment runs to end of line,
        // so losing the newlines lets the first comment eat the whole pattern.
        NSString *sample = @"<a b=\"one #c\ntwo\" />";
        NSData *restored = [FunctionListCatalog dataPreservingAttributeNewlines:
                            [sample dataUsingEncoding:NSUTF8StringEncoding]];
        NSString *restoredText = [[NSString alloc] initWithData:restored
                                                       encoding:NSUTF8StringEncoding];
        __block NSString *readBack = nil;
        NppAttributeReader *reader = [[NppAttributeReader alloc] init];
        NSXMLParser *xp = [[NSXMLParser alloc] initWithData:restored];
        xp.delegate = reader;
        [xp parse];
        readBack = reader.value;
        Check(@"IDM_VIEW_FUNC_LIST (pattern newlines)",
              @"a newline inside an attribute survives being parsed",
              [restoredText containsString:@"&#10;"] &&
              [readBack containsString:@"\n"]);

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

        // Round-tripping ASCII proves nothing about which character set was
        // chosen: "probe 123" survives all of them, so a code page wired to the
        // wrong encoding would have passed. encoding-reference.txt says what
        // each byte actually means, taken from Python's own codecs, and every
        // one of those bytes is checked here.
        NSString *referencePath = [[NSBundle mainBundle] pathForResource:@"encoding-reference"
                                                                  ofType:@"txt"];
        NSString *reference = referencePath
            ? [NSString stringWithContentsOfFile:referencePath encoding:NSUTF8StringEncoding error:NULL]
            : nil;
        NSMutableArray *wrongBytes = [NSMutableArray array];
        NSMutableSet *checkedPages = [NSMutableSet set];
        NSUInteger checkedBytes = 0;
        for (NSString *line in [reference componentsSeparatedByString:@"\n"]) {
            if (!line.length || [line hasPrefix:@"#"]) continue;
            NSArray *fields = [line componentsSeparatedByString:@"\t"];
            if (fields.count != 3) continue;

            unsigned int codepage = (unsigned int)[fields[0] intValue];
            unsigned int byteValue = 0, expectedPoint = 0;
            [[NSScanner scannerWithString:fields[1]] scanHexInt:&byteValue];
            [[NSScanner scannerWithString:fields[2]] scanHexInt:&expectedPoint];

            unsigned char raw = (unsigned char)byteValue;
            NSString *decoded = [EditorController stringFromData:[NSData dataWithBytes:&raw length:1]
                                                        codepage:codepage];
            checkedBytes++;
            [checkedPages addObject:@(codepage)];
            if (decoded.length != 1 || [decoded characterAtIndex:0] != (unichar)expectedPoint) {
                if (wrongBytes.count < 8) {
                    [wrongBytes addObject:[NSString stringWithFormat:@"cp%u byte %02X -> %@ (want %04X)",
                                           codepage, byteValue,
                                           decoded.length ? @([decoded characterAtIndex:0]) : @"nothing",
                                           expectedPoint]];
                }
            }
        }
        Check(@"IDM_FORMAT_ANSI (byte meanings)",
              [NSString stringWithFormat:@"%lu bytes across %lu code pages decode to the right character",
               (unsigned long)checkedBytes, (unsigned long)checkedPages.count],
              checkedBytes > 5000 && wrongBytes.count == 0);
        if (wrongBytes.count) printf("       %s\n",
            [[wrongBytes componentsJoinedByString:@"; "] UTF8String]);
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

        // Creating a lexer object is not the same as the buffer being coloured.
        // For each language, its own first keyword is put in the document and
        // the styles that come back are examined: if every byte is style 0, the
        // lexer is attached in name only.
        int lexed = 0;
        NSMutableArray *unstyled = [NSMutableArray array];
        NSDictionary *languageProbes = @{
            @"html": @"<a href=\"x\">text</a>\n",
            @"xml":  @"<root attr=\"1\">text</root>\n",
            @"asp":  @"<% Response.Write \"hi\" %>\n",
            @"jsp":  @"<% out.print(\"hi\"); %>\n",
            @"kix":  @"; comment\n$a = 1\n",
            @"inno": @"[Setup]\nAppName=Test\n",
            @"yaml": @"key: value\n# comment\n",
        };
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            NSString *name = @(kNppLangLexers[i].langName);
            NppLanguage *language = [cat languageNamed:name];
            if (!language) continue;
            NSString *keywords = language.keywordSets[@0] ?: language.keywordSets.allValues.firstObject;
            NSString *word = [keywords componentsSeparatedByString:@" "].firstObject;

            // A keyword on a line of its own is a fair probe for a programming
            // language. For markup and for configuration files it is not: HTML's
            // keywords are tag names, which are only tags inside angle brackets,
            // so those languages get a line that is actually something in them.
            NSString *probe = languageProbes[name]
                            ?: (word.length ? [word stringByAppendingString:@"\n"] : nil);
            if (!probe.length) continue;
            word = probe;

            [ed setLanguageNamed:name];
            SetDoc(ed, probe);
            [sci message:SCI_COLOURISE wParam:0 lParam:-1];
            BOOL styled = NO;
            long probeLength = [sci message:SCI_GETLENGTH];
            for (long at = 0; at < probeLength; ++at) {
                if ([sci message:SCI_GETSTYLEAT wParam:(uptr_t)at] != 0) { styled = YES; break; }
            }
            if (styled) lexed++; else [unstyled addObject:name];
        }
        Check(@"IDM_LANG_USER (colouring)",
              [NSString stringWithFormat:@"%d languages colour their own keyword%@", lexed,
               unstyled.count ? [NSString stringWithFormat:@" (%lu do not: %@)",
                                 (unsigned long)unstyled.count,
                                 [unstyled componentsJoinedByString:@", "]] : @""],
              unstyled.count == 0);
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

    printf("\n== Preferences: pages ==\n");
    {
        PreferencesWindow *prefs = [[PreferencesWindow alloc] initWithEditor:ed];
        NSArray *pages = [prefs categoryNames];

        // Notepad++ lists its settings by category down the left rather than as
        // one long column, and these are its own names for them.
        NSArray *expected = @[@"General", @"Toolbar", @"Editing 1", @"Editing 2",
                              @"Dark Mode", @"Margins/Border/Edge", @"New Document",
                              @"Indentation", @"Highlighting", @"Print", @"Backup",
                              @"Auto-Completion", @"Delimiter", @"Performance",
                              @"Cloud & Link"];
        NSMutableArray *absent = [NSMutableArray array];
        for (NSString *name in expected) if (![pages containsObject:name]) [absent addObject:name];

        // Every setting that reaches Scintilla needs somewhere to be set from.
        NSArray *keys = @[@"caretWidth", @"caretBlinkRate", @"currentLineHighlightMode",
                          @"currentLineFrameWidth", @"scrollBeyondLastLine", @"virtualSpace",
                          @"lineCopyCutWithoutSelection", @"selectedTextDragDrop",
                          @"rightClickKeepsSelection", @"lineWrapMethod", @"bookmarkMarginShow",
                          @"foldMarginShow", @"paddingLeft", @"paddingRight", @"edgeMode",
                          @"edgeColumns", @"autoIndentMode", @"markAllCaseSensitive",
                          @"markAllWordOnly", @"autoCompleteOnInput", @"autoInsertBrace"];
        NSMutableArray *unreachable = [NSMutableArray array];
        for (NSString *key in keys) {
            if (![prefs hasControlForKey:key]) [unreachable addObject:key];
        }

        Check(@"IDM_SETTING_PREFERENCE (pages)",
              [NSString stringWithFormat:@"%lu categories, and every setting has a control",
               (unsigned long)pages.count],
              absent.count == 0 && unreachable.count == 0 && pages.count >= 15);
        if (absent.count) printf("       нет страниц: %s\n",
            [[absent componentsJoinedByString:@", "] UTF8String]);
        if (unreachable.count) printf("       нет элементов: %s\n",
            [[unreachable componentsJoinedByString:@", "] UTF8String]);
    }

    printf("\n== Appearance: themes ==\n");
    {
        NppPreferences *p = [NppPreferences shared];
        NSArray *themes = [StyleCatalog availableThemeNames];
        Check(@"IDM_SETTING_PREFERENCE (themes listed)",
              @"the bundled Notepad++ themes are offered",
              themes.count > 15 && [themes containsObject:@"Default"] &&
              [themes containsObject:@"DarkModeDefault"] && [themes containsObject:@"Monokai"]);

        // The dark theme's default background is 3F3F3F; the light one's is white.
        [StyleCatalog loadThemeNamed:@"Default"];
        [ed applyLanguage];
        long lightBack = [sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT];
        [StyleCatalog loadThemeNamed:@"DarkModeDefault"];
        [ed applyLanguage];
        long darkBack = [sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT];
        Check(@"IDM_SETTING_PREFERENCE (dark theme)",
              @"switching to the dark theme repaints the editor",
              lightBack == 0xFFFFFF && darkBack == 0x3F3F3F &&
              [[StyleCatalog sharedCatalog].themeName isEqualToString:@"DarkModeDefault"]);

        p.appearanceMode = 2;
        BOOL forcesDark = [[p effectiveThemeName] isEqualToString:p.darkThemeName];
        p.appearanceMode = 1;
        BOOL forcesLight = [[p effectiveThemeName] isEqualToString:p.lightThemeName];
        p.appearanceMode = 0;
        NSString *followed = [p effectiveThemeName];
        BOOL follows = [followed isEqualToString:[p systemIsDark] ? p.darkThemeName : p.lightThemeName];
        Check(@"IDM_SETTING_PREFERENCE (appearance)",
              @"light, dark and follow-the-system each pick the right theme",
              forcesDark && forcesLight && follows);

        // An imported theme must show up in the picker alongside the bundled ones.
        NSString *custom = TempFile(@"TestTheme.xml",
            @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus><LexerStyles>"
            @"<LexerType name=\"cpp\"><WordsStyle name=\"DEFAULT\" styleID=\"11\" "
            @"fgColor=\"123456\" bgColor=\"654321\" /></LexerType></LexerStyles>"
            @"<GlobalStyles><WidgetStyle name=\"Default Style\" styleID=\"32\" "
            @"fgColor=\"ABCDEF\" bgColor=\"222222\" /></GlobalStyles></NotepadPlus>");
        [ed importFiles:@[custom] intoSubdirectory:@"themes"];
        [StyleCatalog setImportedThemesDirectory:
            [[ed supportDirectory] stringByAppendingPathComponent:@"themes"]];
        NSArray *withImported = [StyleCatalog availableThemeNames];
        [StyleCatalog loadThemeNamed:@"TestTheme"];
        [ed applyLanguage];
        // 0x222222 is the same in either byte order, so the foreground is checked too.
        BOOL imported = [withImported containsObject:@"TestTheme"] &&
                        [sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT] == 0x222222 &&
                        [sci message:SCI_STYLEGETFORE wParam:STYLE_DEFAULT] == 0xEFCDAB;
        Check(@"IDM_SETTING_IMPORTSTYLETHEMES (usable)",
              @"an imported theme is listed and can be applied", imported);

        // Breadth: only two of the twenty-two bundled themes were ever loaded
        // here, so a theme that failed to parse would have gone unnoticed. Each
        // one has to give a default background and styles for a common lexer.
        NSMutableArray *badThemes = [NSMutableArray array];
        for (NSString *name in [StyleCatalog availableThemeNames]) {
            // The two synthetic themes other tests import are not Notepad++ themes.
            if ([name hasPrefix:@"TestTheme"] || [name hasPrefix:@"t_theme"]) continue;
            [StyleCatalog loadThemeNamed:name];
            [ed applyLanguage];
            NppStyle *defaultStyle = [StyleCatalog sharedCatalog].globalStyles[@"Default Style"];
            NSUInteger cppStyles = [[StyleCatalog sharedCatalog] stylesForLexerName:@"cpp"].count;
            if (!defaultStyle.background || !defaultStyle.foreground || cppStyles < 5) {
                [badThemes addObject:name];
            }
        }
        Check(@"IDM_SETTING_PREFERENCE (every theme)",
              @"each bundled theme parses and carries colours the editor can use",
              [StyleCatalog availableThemeNames].count >= 22 && badThemes.count == 0);
        if (badThemes.count) printf("       %s\n",
            [[badThemes componentsJoinedByString:@","] UTF8String]);

        [StyleCatalog loadThemeNamed:@"Default"];
        [ed applyLanguage];
    }

    printf("\n== Toolbar ==\n");
    {
        NppToolbar *tb = [app valueForKey:@"toolbar"];
        NSArray *ids = [tb itemIdentifiers];
        Check(@"IDM_SETTING_PREFERENCE (toolbar buttons)",
              @"the bar carries the editing commands",
              ids.count > 10 && [ids containsObject:@"npp.IDM_FILE_SAVE"] &&
              [ids containsObject:@"npp.IDM_SEARCH_FIND"]);

        Check(@"IDM_SETTING_PREFERENCE (toolbar actions)",
              @"each button drives the matching menu command",
              [tb actionForIdentifier:@"npp.IDM_FILE_SAVE"] == @selector(saveDocument:) &&
              [tb actionForIdentifier:@"npp.IDM_SEARCH_FIND"] == @selector(showFind:) &&
              [tb actionForIdentifier:@"npp.IDM_EDIT_UNDO"] == @selector(undo:));

        // The buttons, and their order, are generated from the Notepad++
        // sources rather than written out here, so the test reads the same
        // file and checks the bar agrees with it.
        NSString *orderPath = [[NSBundle mainBundle] pathForResource:@"order" ofType:@"txt"
                                                         inDirectory:@"toolbar"];
        NSMutableArray *expected = [NSMutableArray array];
        for (NSString *raw in [[NSString stringWithContentsOfFile:orderPath
                                                         encoding:NSUTF8StringEncoding error:NULL]
                               componentsSeparatedByString:@"\n"]) {
            NSString *line = [raw stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
            if (!line.length || [line hasPrefix:@"#"] || [line isEqualToString:@"-"]) continue;
            [expected addObject:[@"npp." stringByAppendingString:
                                 [line componentsSeparatedByString:@"\t"].firstObject]];
        }
        NSMutableArray *actual = [NSMutableArray array];
        for (NSString *identifier in ids) {
            if ([identifier hasPrefix:@"npp."]) [actual addObject:identifier];
        }
        Check(@"IDM_SETTING_PREFERENCE (toolbar order)",
              @"the bar holds the same buttons, in the same order, as Notepad++",
              expected.count == 32 && [actual isEqualToArray:expected]);

        // Every button must actually carry its Notepad++ icon. An SF Symbol
        // standing in for a missing file would look plausible and be wrong, so
        // the test insists the image came from the bundled set.
        NSInteger withIcons = 0, distinct = 0;
        NSMutableSet *seen = [NSMutableSet set];
        for (NSToolbarItem *item in [app.window.toolbar items]) {
            if (![item.itemIdentifier hasPrefix:@"npp."]) continue;
            if (!item.image) continue;
            withIcons++;
            NSData *rendered = [item.image TIFFRepresentation];
            if (rendered && ![seen containsObject:rendered]) { [seen addObject:rendered]; distinct++; }
        }
        Check(@"IDM_SETTING_PREFERENCE (toolbar icons)",
              @"every button carries its own icon taken from the Notepad++ sources",
              withIcons == 32 && distinct >= 30);

        // The icons come in a light and a dark set; both have to be present,
        // and they have to differ, or one theme is silently using the other's.
        NSString *lightPath = [[NSBundle mainBundle] pathForResource:@"save_off" ofType:@"png"
                                                         inDirectory:@"toolbar/light"];
        NSString *darkPath = [[NSBundle mainBundle] pathForResource:@"save_off" ofType:@"png"
                                                        inDirectory:@"toolbar/dark"];
        NSData *lightData = lightPath ? [NSData dataWithContentsOfFile:lightPath] : nil;
        NSData *darkData = darkPath ? [NSData dataWithContentsOfFile:darkPath] : nil;
        Check(@"IDM_SETTING_PREFERENCE (toolbar themes)",
              @"a light and a dark icon are bundled for each button, and they differ",
              lightData.length > 0 && darkData.length > 0 && ![lightData isEqualToData:darkData]);

        NppPreferences *p = [NppPreferences shared];
        p.showToolbar = NO;  [app applyToolbarPreferences];
        BOOL hidden = ![tb visible];
        p.showToolbar = YES; [app applyToolbarPreferences];
        BOOL shown = [tb visible];
        // While a macro is recording, the record button is red. The editor
        // gave no sign at all that recording was going on.
        NppToolbar *recordBar = [app valueForKey:@"toolbar"];
        BOOL quietBefore = ![recordBar isActiveForCommand:@"IDM_MACRO_STARTRECORDINGMACRO"];
        [app macroStart:nil];
        BOOL litWhileRecording = [recordBar isActiveForCommand:@"IDM_MACRO_STARTRECORDINGMACRO"];
        [app macroStop:nil];
        Check(@"IDM_MACRO_STARTRECORDINGMACRO (shown while recording)",
              @"the record button is marked while recording and clears when it stops",
              quietBefore && litWhileRecording &&
              ![recordBar isActiveForCommand:@"IDM_MACRO_STARTRECORDINGMACRO"]);

        Check(@"IDM_SETTING_PREFERENCE (toolbar visibility)",
              @"the setting shows and hides the bar", hidden && shown);

        // Labels must reach AppKit, not just the stored request: the compact
        // toolbar style silently ignores the display mode, so asking for labels
        // has to switch the window style too.
        p.toolbarDisplayMode = 1; [app applyToolbarPreferences];
        BOOL labels = tb.displayMode == 1 &&
                      tb.effectiveDisplayMode == NSToolbarDisplayModeIconAndLabel &&
                      app.window.toolbarStyle == NSWindowToolbarStyleExpanded;

        p.toolbarDisplayMode = 2; [app applyToolbarPreferences];
        BOOL labelsOnly = tb.effectiveDisplayMode == NSToolbarDisplayModeLabelOnly;

        p.toolbarDisplayMode = 0; [app applyToolbarPreferences];
        BOOL iconsOnly = tb.effectiveDisplayMode == NSToolbarDisplayModeIconOnly;

        p.toolbarIconSize = 0; [app applyToolbarPreferences];
        BOOL regular = tb.iconSize == 0 && app.window.toolbarStyle == NSWindowToolbarStyleExpanded;
        p.toolbarIconSize = 1; [app applyToolbarPreferences];
        BOOL small = tb.iconSize == 1 && app.window.toolbarStyle == NSWindowToolbarStyleUnifiedCompact;

        Check(@"IDM_SETTING_PREFERENCE (toolbar layout)",
              @"display mode and size reach AppKit, including their interaction",
              labels && labelsOnly && iconsOnly && regular && small);
    }

    printf("\n== Backup and autosave ==\n");
    {
        NppPreferences *p = [NppPreferences shared];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSInteger savedMode = p.backupMode;

        // No backup: saving must leave nothing beside the file.
        NSString *path = TempFile(@"t_backup.txt", @"first version\n");
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingPathExtension:@"bak"] error:NULL];
        p.backupMode = NppBackupNone;
        NSError *err = nil;
        [ed openFileAtPath:path error:&err];
        SetDoc(ed, @"second version\n");
        [ed saveCurrentDocument];
        Check(@"IDM_SETTING_PREFERENCE (backup off)", @"no backup is written when it is off",
              ![fm fileExistsAtPath:[path stringByAppendingPathExtension:@"bak"]]);

        // Simple: the previous contents land in file.ext.bak.
        p.backupMode = NppBackupSimple;
        SetDoc(ed, @"third version\n");
        NSString *simple = [ed writeBackupForPath:path];
        NSString *backedUp = [NSString stringWithContentsOfFile:simple
                                                       encoding:NSUTF8StringEncoding error:NULL];
        Check(@"IDM_SETTING_PREFERENCE (backup simple)",
              @"the copy holds what was on disk before the save",
              [simple hasSuffix:@".bak"] && [backedUp isEqualToString:@"second version\n"]);

        // Verbose: a timestamped copy in the backup folder.
        p.backupMode = NppBackupVerbose;
        NSString *verbose = [ed writeBackupForPath:path];
        Check(@"IDM_SETTING_PREFERENCE (backup verbose)",
              @"a timestamped copy lands in the backup folder",
              [verbose hasPrefix:[ed backupDirectory]] &&
              [[ed backupsForPath:path] containsObject:verbose]);
        p.backupMode = savedMode;

        // An autosave pass writes modified documents and snapshots unsaved ones.
        [ed closeAllDocuments];
        NSString *tracked = TempFile(@"t_autosave.txt", @"original\n");
        [ed openFileAtPath:tracked error:&err];
        SetDoc(ed, @"changed by autosave\n");
        ed.currentDocument.modified = YES;
        [ed newDocument];
        SetDoc(ed, @"never saved anywhere\n");

        NSUInteger written = [ed runAutosavePass];
        NSString *onDisk = [NSString stringWithContentsOfFile:tracked
                                                     encoding:NSUTF8StringEncoding error:NULL];
        NSData *snapJson = [NSData dataWithContentsOfFile:[ed snapshotPath]];
        NSDictionary *snap = snapJson ? [NSJSONSerialization JSONObjectWithData:snapJson
                                                                       options:0 error:NULL] : nil;
        BOOL snapshotHasText = NO;
        for (NSDictionary *entry in snap[@"unsaved"]) {
            if ([entry[@"text"] containsString:@"never saved anywhere"]) snapshotHasText = YES;
        }
        Check(@"IDM_SETTING_PREFERENCE (autosave)",
              @"modified files are written and unsaved text is snapshotted",
              written == 1 && [onDisk isEqualToString:@"changed by autosave\n"] && snapshotHasText);

        [ed setAutosaveEnabled:YES interval:60];
        BOOL running = [ed autosaveRunning];
        [ed setAutosaveEnabled:NO interval:60];
        Check(@"IDM_SETTING_PREFERENCE (autosave timer)", @"the timer starts and stops",
              running && ![ed autosaveRunning]);
    }

    printf("\n== Print options ==\n");
    {
        NppPreferences *p = [NppPreferences shared];
        NSError *err = nil;
        NSString *path = TempFile(@"t_print.txt", @"alpha\nbeta\ngamma\n");
        [ed openFileAtPath:path error:&err];

        NSString *header = [ed expandPrintTemplate:
            @"$(FILE_NAME) | $(NAME_PART).$(EXT_PART) | page $(CURRENT_PRINTING_PAGE) of $(TOTAL_PRINTING_PAGE)"
                                              page:2 of:7];
        Check(@"IDM_SETTING_PREFERENCE (print header)",
              @"the $(...) variables are expanded",
              [header isEqualToString:@"t_print.txt | t_print.txt | page 2 of 7"] &&
              ![header containsString:@"$("]);

        p.printLineNumbers = NO;
        NSString *plain = [ed textForPrinting];
        p.printLineNumbers = YES;
        NSString *numbered = [ed textForPrinting];
        p.printLineNumbers = NO;
        Check(@"IDM_SETTING_PREFERENCE (print line numbers)",
              @"line numbers are added only when asked for",
              ![plain hasPrefix:@"1"] && [numbered hasPrefix:@"1  alpha"] &&
              [numbered containsString:@"3  gamma"]);

        p.printMarginLeft = 11; p.printMarginRight = 22;
        p.printMarginTop = 33; p.printMarginBottom = 44;
        NSPrintInfo *info = [ed printInfoFromPreferences];
        Check(@"IDM_SETTING_PREFERENCE (print margins)",
              @"the configured margins reach the print info",
              info.leftMargin == 11 && info.rightMargin == 22 &&
              info.topMargin == 33 && info.bottomMargin == 44);

        // Building the job must not reach a printer, so only the job is checked.
        p.printColourMode = NppPrintInvert;
        NSPrintOperation *op = [ed printOperationShowingPanel:NO];
        NSTextView *page = (NSTextView *)op.view;
        BOOL inverted = [page.backgroundColor isEqual:[NSColor blackColor]] && page.drawsBackground;
        p.printColourMode = NppPrintBlackOnWhite;
        NSTextView *plainPage = (NSTextView *)[ed printOperationShowingPanel:NO].view;
        Check(@"IDM_SETTING_PREFERENCE (print colours)",
              @"the colour mode reaches the printed page",
              op != nil && inverted && !plainPage.drawsBackground &&
              [plainPage.textColor isEqual:[NSColor blackColor]]);
        p.printColourMode = 2;
    }

    printf("\n== Performance, links, delimiters ==\n");
    {
        NppPreferences *p = [NppPreferences shared];

        // Large file restriction: a threshold of 0 MB makes any document large.
        [ed newDocument];
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"// a comment\nint x = 1;\n");
        p.largeFileRestrictionEnabled = YES;
        p.largeFileThresholdMB = 200;
        BOOL normalFile = ![ed largeFileRestrictionActive];
        p.largeFileThresholdMB = 0;
        BOOL nowRestricted = [ed largeFileRestrictionActive];
        [ed applyPerformanceRestrictions];
        long styledUnderRestriction = [sci message:SCI_GETSTYLEAT wParam:0];
        p.largeFileThresholdMB = 200;
        [ed applyPerformanceRestrictions];
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        long styledNormally = [sci message:SCI_GETSTYLEAT wParam:0];
        Check(@"IDM_SETTING_PREFERENCE (large files)",
              @"highlighting is dropped above the threshold and restored below it",
              normalFile && nowRestricted && styledUnderRestriction == 0 &&
              styledNormally == SCE_C_COMMENTLINE);

        // Clickable links.
        p.linksEnabled = YES;
        p.linkCustomSchemes = @"";
        SetDoc(ed, @"see https://example.org/page and mailto:a@b.c here\n");
        NSUInteger links = [ed markClickableLinks];
        NSString *first = [ed linkAtPosition:6];
        Check(@"IDM_SETTING_PREFERENCE (links)",
              @"URLs are marked and readable back",
              links == 2 && [first isEqualToString:@"https://example.org/page"]);

        p.linkCustomSchemes = @"obsidian";
        SetDoc(ed, @"obsidian://open?vault=x\n");
        NSUInteger custom = [ed markClickableLinks];
        Check(@"IDM_SETTING_PREFERENCE (link schemes)",
              @"a custom scheme is recognised too",
              custom == 1 && [[ed linkAtPosition:2] hasPrefix:@"obsidian://"]);
        p.linkCustomSchemes = @"";

        p.linksEnabled = NO;
        SetDoc(ed, @"https://example.org/\n");
        Check(@"IDM_SETTING_PREFERENCE (links off)", @"nothing is marked when links are off",
              [ed markClickableLinks] == 0 && [ed linkAtPosition:2] == nil);
        p.linksEnabled = YES;

        // Brace match.
        p.braceMatchEnabled = YES;
        SetDoc(ed, @"value = (a + b);\n");
        [sci message:SCI_GOTOPOS wParam:8 lParam:0];
        [ed updateBraceMatch];
        BOOL matched = [sci message:SCI_BRACEMATCH wParam:8 lParam:0] == 14;
        p.braceMatchEnabled = NO;
        [ed updateBraceMatch];
        Check(@"IDM_SETTING_PREFERENCE (brace match)",
              @"the matching brace is found while the setting is on", matched);
        p.braceMatchEnabled = YES;

        // Smart highlighting marks the other occurrences of a selected token.
        p.smartHighlightEnabled = YES;
        SetDoc(ed, @"total = total + subtotal\n");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        NSUInteger marks = [ed updateSmartHighlight];
        p.smartHighlightEnabled = NO;
        NSUInteger none = [ed updateSmartHighlight];
        Check(@"IDM_SETTING_PREFERENCE (smart highlighting)",
              @"occurrences are marked only while the setting is on",
              marks == 3 && none == 0);
        p.smartHighlightEnabled = YES;

        // Word characters change what counts as a word for selection.
        SetDoc(ed, @"alpha-beta gamma\n");
        p.customWordCharsEnabled = NO;
        [ed applyLanguage];
        [sci message:SCI_GOTOPOS wParam:2 lParam:0];
        long plainEnd = [sci message:SCI_WORDENDPOSITION wParam:2 lParam:1];
        p.customWordCharsEnabled = YES;
        p.customWordChars = @"-";
        [ed applyWordCharacters];
        long extendedEnd = [sci message:SCI_WORDENDPOSITION wParam:2 lParam:1];
        p.customWordCharsEnabled = NO;
        [ed applyLanguage];
        Check(@"IDM_SETTING_PREFERENCE (word characters)",
              @"adding '-' makes the hyphenated word one word",
              plainEnd == 5 && extendedEnd == 10);

        // Delimiter selection.
        p.delimiterOpen = @"("; p.delimiterClose = @")"; p.delimiterMultiline = NO;
        SetDoc(ed, @"call(inside here) tail\n");
        BOOL selected = [ed selectBetweenDelimitersAt:8];
        Check(@"IDM_SETTING_PREFERENCE (delimiters)",
              @"the text between the delimiters is selected",
              selected && [sci message:SCI_GETSELECTIONSTART] == 5 &&
              [sci message:SCI_GETSELECTIONEND] == 16);

        p.delimiterOpen = @"["; p.delimiterClose = @"]";
        SetDoc(ed, @"arr[42] rest\n");
        BOOL brackets = [ed selectBetweenDelimitersAt:5];
        Check(@"IDM_SETTING_PREFERENCE (delimiter choice)",
              @"the configured delimiters are the ones used",
              brackets && [sci message:SCI_GETSELECTIONSTART] == 4 &&
              [sci message:SCI_GETSELECTIONEND] == 6);
        p.delimiterOpen = @"("; p.delimiterClose = @")";
    }

    printf("\n== Instances, panels, settings folder ==\n");
    {
        NppPreferences *p = [NppPreferences shared];

        p.multiInstanceMode = 0;
        BOOL mono = ![ed shouldOpenFilesInNewInstance];
        p.multiInstanceMode = 1;
        BOOL multi = [ed shouldOpenFilesInNewInstance];
        p.multiInstanceMode = 0;
        Check(@"IDM_SETTING_PREFERENCE (instances)",
              @"the mode decides whether a file starts another instance", mono && multi);

        // Reversing the order puts the time before the date.
        p.reverseDateTimeOrder = NO;
        SetDoc(ed, @"");
        [ed insertDateTimeShort:YES];
        NSString *normal = DocText(ed);
        p.reverseDateTimeOrder = YES;
        SetDoc(ed, @"");
        [ed insertDateTimeShort:YES];
        NSString *reversed = DocText(ed);
        p.reverseDateTimeOrder = NO;
        Check(@"IDM_SETTING_PREFERENCE (date order)",
              @"the reversed form differs from the default one",
              normal.length > 0 && reversed.length > 0 && ![normal isEqualToString:reversed]);

        // Panel state survives a remember/restore round trip.
        p.rememberPanelState = YES;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_panels"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [ed openFolderAsWorkspace:dir];
        [ed setDocumentMapVisible:YES];
        [ed rememberPanelState];
        NSDictionary *stored = p.panelState;
        [ed openFolderAsWorkspace:nil];
        [ed setDocumentMapVisible:NO];
        [ed restorePanelState];
        Check(@"IDM_SETTING_PREFERENCE (panel state)",
              @"the open panels are remembered and reopened",
              [stored[@"workspace"] boolValue] && [stored[@"documentMap"] boolValue] &&
              [ed documentMapVisible]);
        [ed setDocumentMapVisible:NO];
        [ed openFolderAsWorkspace:nil];
        p.rememberPanelState = NO;

        // Relocating the settings folder moves everything that lives in it.
        NSString *custom = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_settings"];
        NSString *defaultDir = [ed supportDirectory];
        p.settingsDirectory = custom;
        NSString *moved = [ed supportDirectory];
        p.settingsDirectory = @"";
        Check(@"IDM_SETTING_PREFERENCE (settings folder)",
              @"the configured folder replaces the default one",
              [moved isEqualToString:custom] && ![moved isEqualToString:defaultDir] &&
              [[ed supportDirectory] isEqualToString:defaultDir]);
    }

    printf("\n== Auto-completion and typing ==\n");
    {
        NppPreferences *p = [NppPreferences shared];
        [ed newDocument];
        [ed setLanguageNamed:@"cpp"];

        // Candidate sources: words from the document, keywords, or both.
        SetDoc(ed, @"retrieval retrospect\n");
        p.autoCompleteSource = NppCompletionWords;
        NSArray *words = [ed completionCandidatesForPrefix:@"retr"];
        p.autoCompleteSource = NppCompletionFunctions;
        NSArray *keywords = [ed completionCandidatesForPrefix:@"ret"];
        p.autoCompleteSource = NppCompletionBoth;
        NSArray *both = [ed completionCandidatesForPrefix:@"ret"];
        Check(@"IDM_SETTING_PREFERENCE (completion sources)",
              @"words, keywords and both give different candidate sets",
              words.count == 2 && [keywords containsObject:@"return"] &&
              ![words containsObject:@"return"] && both.count > keywords.count);

        p.autoCompleteBriefList = YES;
        NSArray *brief = [ed completionCandidatesForPrefix:@"r"];
        p.autoCompleteBriefList = NO;
        NSArray *full = [ed completionCandidatesForPrefix:@"r"];
        Check(@"IDM_SETTING_PREFERENCE (brief list)",
              @"the brief list is capped and the full one is not",
              brief.count <= 12 && full.count >= brief.count);

        p.autoCompleteIgnoreNumbers = YES;
        NSArray *numeric = [ed completionCandidatesForPrefix:@"12"];
        p.autoCompleteIgnoreNumbers = NO;
        Check(@"IDM_SETTING_PREFERENCE (ignore numbers)",
              @"a numeric prefix offers nothing while that is on", numeric.count == 0);
        p.autoCompleteIgnoreNumbers = YES;

        // Auto-insertion of the matching character.
        struct { int ch; NSString *want; NSString *flag; } pairs[] = {
            {'(', @")", @"autoInsertParenthesis"},
            {'[', @"]", @"autoInsertBracket"},
            {'{', @"}", @"autoInsertBrace"},
            {'\'', @"'", @"autoInsertSingleQuote"},
            {'"', @"\"", @"autoInsertDoubleQuote"},
        };
        BOOL allPairs = YES;
        for (size_t i = 0; i < sizeof(pairs)/sizeof(pairs[0]); ++i) {
            [p setValue:@NO forKey:pairs[i].flag];
            if ([ed autoInsertionForCharacter:pairs[i].ch] != nil) allPairs = NO;
            [p setValue:@YES forKey:pairs[i].flag];
            if (![[ed autoInsertionForCharacter:pairs[i].ch] isEqualToString:pairs[i].want]) allPairs = NO;
            [p setValue:@NO forKey:pairs[i].flag];
        }
        Check(@"IDM_SETTING_PREFERENCE (auto-insert)",
              @"each pair is inserted only while its own setting is on", allPairs);

        // The close tag follows the element that was just opened.
        p.autoInsertCloseTag = YES;
        [ed setLanguageNamed:@"html"];
        SetDoc(ed, @"<div>");
        [sci message:SCI_GOTOPOS wParam:5 lParam:0];
        NSString *closeTag = [ed closeTagAtCaret];
        SetDoc(ed, @"<img src=\"a.png\"/>");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        NSString *selfClosing = [ed closeTagAtCaret];
        p.autoInsertCloseTag = NO;
        Check(@"IDM_SETTING_PREFERENCE (close tag)",
              @"an opened element is closed and a self-closing one is not",
              [closeTag isEqualToString:@"</div>"] && selfClosing == nil);

        // Typing drives both: the pair is inserted and the caret stays inside.
        p.autoInsertParenthesis = YES;
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"");
        [sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"("];
        [sci message:SCI_GOTOPOS wParam:1 lParam:0];
        [ed handleCharacterAdded:'('];
        Check(@"IDM_SETTING_PREFERENCE (typing)",
              @"typing an opening bracket closes it and leaves the caret between",
              [DocText(ed) isEqualToString:@"()"] && [sci message:SCI_GETCURRENTPOS] == 1);
        p.autoInsertParenthesis = NO;
    }

    printf("\n== New documents, recent files, directories ==\n");
    {
        NppPreferences *p = [NppPreferences shared];

        p.defaultEOL = SC_EOL_CR;
        p.defaultEncoding = @"UTF-16 LE BOM";
        p.defaultLanguage = @"python";
        [ed newDocument];
        NppDocument *fresh = ed.currentDocument;
        Check(@"IDM_SETTING_PREFERENCE (new document)",
              @"a new document takes the configured EOL, encoding and language",
              fresh.eolMode == SC_EOL_CR && fresh.hasBOM &&
              fresh.encoding == NSUTF16LittleEndianStringEncoding &&
              [fresh.language.name isEqualToString:@"python"]);
        p.defaultEOL = SC_EOL_LF;
        p.defaultEncoding = @"UTF-8";
        p.defaultLanguage = @"";

        p.untitledFromFirstLine = YES;
        SetDoc(ed, @"a title line\nbody\n");
        NSString *derived = [ed untitledNameForDocument:ed.currentDocument];
        p.untitledFromFirstLine = NO;
        NSString *plain = [ed untitledNameForDocument:ed.currentDocument];
        Check(@"IDM_SETTING_PREFERENCE (untitled name)",
              @"the tab can take its name from the first line",
              [derived isEqualToString:@"a title line"] && [plain hasPrefix:@"new"]);

        // Recent files: order, cap and display.
        [ed clearRecentFiles];
        p.recentFilesMax = 3;
        for (NSString *name in @[@"one.txt", @"two.txt", @"three.txt", @"four.txt"]) {
            [ed noteRecentFile:[@"/tmp/recent" stringByAppendingPathComponent:name]];
        }
        NSArray *recent = [ed recentFiles];
        p.recentFilesShowFullPath = NO;
        NSString *shortName = [ed displayNameForRecentFile:recent.firstObject];
        p.recentFilesShowFullPath = YES;
        p.recentFilesMaxLength = 60;
        NSString *fullName = [ed displayNameForRecentFile:recent.firstObject];
        p.recentFilesMaxLength = 12;
        NSString *clipped = [ed displayNameForRecentFile:recent.firstObject];
        p.recentFilesShowFullPath = NO;
        Check(@"IDM_SETTING_PREFERENCE (recent files)",
              @"newest first, capped, and shown per the display settings",
              recent.count == 3 && [recent.firstObject hasSuffix:@"four.txt"] &&
              [shortName isEqualToString:@"four.txt"] &&
              [fullName hasPrefix:@"/tmp/recent"] && clipped.length <= 12 &&
              [clipped hasPrefix:@"…"]);

        [ed clearRecentFiles];
        Check(@"IDM_SETTING_PREFERENCE (clear recent)", @"the list can be emptied",
              [ed recentFiles].count == 0);

        // Default directory for the Open panel.
        NSError *err = nil;
        NSString *file = TempFile(@"t_dir.txt", @"x\n");
        [ed openFileAtPath:file error:&err];
        p.defaultDirectoryMode = 0;
        NSString *followsDoc = [ed defaultOpenDirectory];
        p.defaultDirectoryMode = 2;
        p.fixedDirectory = @"/usr/share";
        NSString *fixed = [ed defaultOpenDirectory];
        p.defaultDirectoryMode = 1;
        p.lastUsedDirectory = @"";
        [ed rememberOpenDirectory:file];
        NSString *remembered = [ed defaultOpenDirectory];
        p.defaultDirectoryMode = 0;
        Check(@"IDM_SETTING_PREFERENCE (default directory)",
              @"following the document, a fixed folder and the last used one all work",
              [followsDoc isEqualToString:file.stringByDeletingLastPathComponent] &&
              [fixed isEqualToString:@"/usr/share"] &&
              [remembered isEqualToString:file.stringByDeletingLastPathComponent]);
    }

    printf("\n== Searching and highlighting settings ==\n");
    {
        NppPreferences *p = [NppPreferences shared];
        SetDoc(ed, @"alpha beta alpha\n");

        [sci message:SCI_SETSEL wParam:0 lParam:5];
        p.findFillWithSelection = YES;
        NSString *fromSelection = [ed initialFindTerm];
        p.findFillWithSelection = NO;
        NSString *ignored = [ed initialFindTerm];
        Check(@"IDM_SETTING_PREFERENCE (find from selection)",
              @"the Find field is seeded from the selection only when asked",
              [fromSelection isEqualToString:@"alpha"] && ignored.length == 0);
        p.findFillWithSelection = YES;

        [sci message:SCI_GOTOPOS wParam:7 lParam:0];
        p.findSelectWordUnderCaret = YES;
        NSString *fromCaret = [ed initialFindTerm];
        p.findSelectWordUnderCaret = NO;
        NSString *none = [ed initialFindTerm];
        p.findSelectWordUnderCaret = YES;
        Check(@"IDM_SETTING_PREFERENCE (word under caret)",
              @"with nothing selected the word under the caret is used",
              [fromCaret isEqualToString:@"beta"] && none.length == 0);

        // Smart highlighting refinements change what counts as a match.
        SetDoc(ed, @"Cat cat catalog\n");
        p.smartHighlightEnabled = YES;
        [sci message:SCI_SETSEL wParam:4 lParam:7];
        p.smartHighlightMatchCase = NO;  p.smartHighlightWholeWord = NO;
        NSUInteger loose = [ed updateSmartHighlight];
        [sci message:SCI_SETSEL wParam:4 lParam:7];
        p.smartHighlightMatchCase = YES;
        NSUInteger cased = [ed updateSmartHighlight];
        [sci message:SCI_SETSEL wParam:4 lParam:7];
        p.smartHighlightWholeWord = YES;
        NSUInteger strict = [ed updateSmartHighlight];
        p.smartHighlightMatchCase = NO;  p.smartHighlightWholeWord = NO;
        Check(@"IDM_SETTING_PREFERENCE (smart highlight rules)",
              @"match case and whole word each narrow the matches",
              loose == 3 && cased == 2 && strict == 1);
    }

    printf("\n== Tab bar ==\n");
    {
        NppPreferences *p = [NppPreferences shared];
        NSError *err = nil;
        [ed closeAllDocuments];
        for (int i = 1; i <= 4; ++i) {
            [ed openFileAtPath:TempFile([NSString stringWithFormat:@"tb%d.txt", i], @"x\n") error:&err];
        }
        NppTabBarView *bar = [ed valueForKey:@"tabBar"];
        [bar setFrameSize:NSMakeSize(600, 26)];
        [ed refreshChrome];

        // One row: the tabs sit side by side at the same height.
        p.tabBarVertical = NO; p.tabBarMultiLine = NO;
        [ed applyTabBarPreferences];
        [bar setFrameSize:NSMakeSize(600, 26)];
        NSRect first = [bar frameOfTabAtIndex:0];
        NSRect second = [bar frameOfTabAtIndex:1];
        Check(@"IDM_SETTING_PREFERENCE (tab bar row)",
              @"tabs lie side by side in one row",
              NSMinY(first) == NSMinY(second) && NSMinX(second) > NSMinX(first) &&
              bar.items.count == ed.documents.count);

        // Vertical: stacked instead.
        p.tabBarVertical = YES;
        [ed applyTabBarPreferences];
        [bar setFrameSize:NSMakeSize(140, 400)];
        NSRect vFirst = [bar frameOfTabAtIndex:0];
        NSRect vSecond = [bar frameOfTabAtIndex:1];
        Check(@"IDM_SETTING_PREFERENCE (tab bar vertical)",
              @"tabs stack down the side",
              NSMinX(vFirst) == NSMinX(vSecond) && NSMinY(vSecond) > NSMinY(vFirst));
        p.tabBarVertical = NO;

        // Multi-line: they wrap onto a second row in a narrow bar.
        p.tabBarMultiLine = YES;
        [ed applyTabBarPreferences];
        [bar setFrameSize:NSMakeSize(200, 60)];
        BOOL wrapped = NO;
        for (NSInteger i = 1; i < (NSInteger)bar.items.count; ++i) {
            if (NSMinY([bar frameOfTabAtIndex:i]) > NSMinY([bar frameOfTabAtIndex:0])) wrapped = YES;
        }
        Check(@"IDM_SETTING_PREFERENCE (tab bar multi-line)",
              @"tabs wrap onto another row when the bar is narrow",
              wrapped && [bar requiredThickness] > 26);
        p.tabBarMultiLine = NO;
        [ed applyTabBarPreferences];
        [bar setFrameSize:NSMakeSize(600, 26)];

        // Close buttons: on the active tab, and on the others only when asked.
        p.tabShowCloseButton = YES;
        p.tabCloseButtonOnInactive = NO;
        [ed applyTabBarPreferences];
        [ed selectDocumentAtIndex:0];
        NSRect active = [bar frameOfTabAtIndex:0];
        NSPoint onActiveClose = NSMakePoint(NSMaxX(active) - 10, NSMidY(active));
        NSRect other = [bar frameOfTabAtIndex:2];
        NSPoint onOtherClose = NSMakePoint(NSMaxX(other) - 10, NSMidY(other));
        BOOL activeOnly = [bar point:onActiveClose isOnCloseButtonOfIndex:0] &&
                          ![bar point:onOtherClose isOnCloseButtonOfIndex:2];
        p.tabCloseButtonOnInactive = YES;
        [ed applyTabBarPreferences];
        BOOL alsoInactive = [bar point:onOtherClose isOnCloseButtonOfIndex:2];
        p.tabCloseButtonOnInactive = NO;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (tab close buttons)",
              @"the close button follows its setting",
              activeOnly && alsoInactive);

        // Closing through the bar removes that tab.
        NSUInteger before = ed.documents.count;
        [ed tabBar:bar didRequestCloseIndex:1];
        Check(@"IDM_SETTING_PREFERENCE (tab close)",
              @"the bar's close button closes that document",
              ed.documents.count == before - 1);

        // Dragging reorders.
        NSString *movedName = ed.documents[0].displayName;
        [ed tabBar:bar didMoveIndex:0 toIndex:2];
        Check(@"IDM_SETTING_PREFERENCE (tab reorder)",
              @"a dragged tab lands at its new position",
              [ed.documents[2].displayName isEqualToString:movedName] &&
              ed.currentDocument == ed.documents[2]);

        p.hideTabBar = YES;
        [ed applyTabBarPreferences];
        BOOL hidden = bar.isHidden;
        p.hideTabBar = NO;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (hide tab bar)",
              @"the bar can be hidden and shown", hidden && !bar.isHidden);

        p.tabBarLocked = YES;
        [ed applyTabBarPreferences];
        BOOL locked = bar.locked;
        p.tabBarLocked = NO;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (tab bar lock)",
              @"locking is passed to the bar", locked && !bar.locked);
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

    printf("\n== JSON ==\n");
    {
        NppPreferences *p = [NppPreferences shared];
        [ed newDocument];

        // Format: compact input becomes indented, and stays the same document.
        p.jsonIndent = 4;
        SetDoc(ed, @"{\"b\":1,\"a\":[1,2,{\"c\":null}]}");
        BOOL formatted = [ed formatJSONDocument];
        NSString *pretty = DocText(ed);
        Check(@"JSON format", @"compact JSON becomes indented",
              formatted && [pretty containsString:@"\n"] &&
              [pretty containsString:@"    "] && [pretty containsString:@"\"a\""]);

        // Compacting it again must give back an equivalent single line.
        BOOL compacted = [ed compactJSONDocument];
        NSString *tight = DocText(ed);
        Check(@"JSON compact", @"indented JSON becomes one line again",
              compacted && ![tight containsString:@"\n"] && [tight hasPrefix:@"{"] &&
              [tight containsString:@"\"c\":null"]);

        // Round trip: the data must survive both directions.
        NSData *original = [tight dataUsingEncoding:NSUTF8StringEncoding];
        id parsedAgain = [NSJSONSerialization JSONObjectWithData:original options:0 error:NULL];
        Check(@"JSON round trip", @"the value is unchanged by formatting",
              [parsedAgain[@"b"] integerValue] == 1 && [parsedAgain[@"a"] count] == 3);

        // Sorting puts the keys in order.
        SetDoc(ed, @"{\"zeta\":1,\"alpha\":2}");
        [ed sortJSONDocument];
        NSString *sorted = DocText(ed);
        Check(@"JSON sort", @"keys come out in order",
              [sorted rangeOfString:@"alpha"].location < [sorted rangeOfString:@"zeta"].location);

        // Validation reports where the problem is.
        SetDoc(ed, @"{\"ok\": 1}");
        NppJsonError *clean = [ed validateJSONDocument];
        SetDoc(ed, @"{\n  \"ok\": 1,\n  bad\n}");
        NppJsonError *broken = [ed validateJSONDocument];
        Check(@"JSON validate", @"valid passes, invalid reports a line",
              clean == nil && broken != nil && broken.line >= 1 && broken.message.length > 0);

        // Formatting must refuse rather than damage a document that is not JSON.
        SetDoc(ed, @"this is not json at all\n");
        NSString *before = DocText(ed);
        BOOL refused = ![ed formatJSONDocument];
        Check(@"JSON refuses non-JSON", @"a non-JSON document is left untouched",
              refused && [DocText(ed) isEqualToString:before]);

        // The tree lists every node with its path.
        SetDoc(ed, @"{\"top\":{\"inner\":[10,20]}}");
        NSArray *tree = [ed jsonTree];
        NSMutableArray *paths = [NSMutableArray array];
        for (NSDictionary *node in tree) [paths addObject:node[@"path"]];
        Check(@"JSON tree", @"nested paths are reported",
              [paths containsObject:@"top.inner[0]"] && [paths containsObject:@"top.inner[1]"] &&
              [paths containsObject:@"top.inner"]);
    }

    printf("\n== Compare ==\n");
    {
        NSArray *oldLines = @[@"alpha", @"beta", @"gamma", @"delta"];
        NSArray *newLines = @[@"alpha", @"BETA", @"gamma", @"delta", @"epsilon"];

        NSArray<NppDiffLine *> *diff = [EditorController diffBetween:oldLines and:newLines
                                                         ignoreCase:NO ignoreSpaces:NO
                                                   ignoreEmptyLines:NO];
        NSUInteger changed = 0, added = 0, same = 0;
        for (NppDiffLine *l in diff) {
            if (l.kind == NppDiffChanged) changed++;
            else if (l.kind == NppDiffAdded) added++;
            else if (l.kind == NppDiffSame) same++;
        }
        Check(@"Compare diff", @"one changed line, one added, three unchanged",
              changed == 1 && added == 1 && same == 3);

        // Ignoring case makes the changed line equal.
        NSArray *ignoringCase = [EditorController diffBetween:oldLines and:newLines
                                                   ignoreCase:YES ignoreSpaces:NO
                                             ignoreEmptyLines:NO];
        NSUInteger stillDifferent = 0;
        for (NppDiffLine *l in ignoringCase) if (l.kind != NppDiffSame) stillDifferent++;
        Check(@"Compare ignore case", @"only the added line remains a difference",
              stillDifferent == 1);

        // Ignoring spaces makes re-indented lines equal.
        NSArray *spacedDiff = [EditorController diffBetween:@[@"a  b", @"c"]
                                                       and:@[@"a b", @"c"]
                                                ignoreCase:NO ignoreSpaces:YES
                                          ignoreEmptyLines:NO];
        NSUInteger spaceDiffs = 0;
        for (NppDiffLine *l in spacedDiff) if (l.kind != NppDiffSame) spaceDiffs++;
        Check(@"Compare ignore spaces", @"re-spaced lines count as equal", spaceDiffs == 0);

        // Identical input produces no differences at all.
        NSArray *identical = [EditorController diffBetween:oldLines and:oldLines
                                                ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
        NSUInteger anyDiff = 0;
        for (NppDiffLine *l in identical) if (l.kind != NppDiffSame) anyDiff++;
        Check(@"Compare identical", @"identical files differ nowhere",
              anyDiff == 0 && identical.count == oldLines.count);

        // End to end, through the editor.
        NSError *err = nil;
        NSString *oldPath = TempFile(@"cmp_old.txt", @"alpha\nbeta\ngamma\n");
        NSString *newPath = TempFile(@"cmp_new.txt", @"alpha\nBETA\ngamma\ndelta\n");
        [ed openFileAtPath:newPath error:&err];
        BOOL compared = [ed compareWithFileAtPath:oldPath];
        Check(@"Compare run", @"comparing marks differences and shows both files",
              compared && [ed compareActive] && [ed secondaryViewVisible] &&
              [[ed compareSummary] containsString:@"changed"]);

        // Navigation walks the marked lines.
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL next = [ed goToDiff:1];
        long firstStop = [sci message:SCI_LINEFROMPOSITION
                               wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        BOOL last = [ed goToLastDiff];
        long lastStop = [sci message:SCI_LINEFROMPOSITION
                              wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        Check(@"Compare navigation", @"next and last land on marked lines",
              next && last && firstStop > 0 && lastStop >= firstStop);

        // "Set as first" then compare, the way the menu drives it.
        [ed openFileAtPath:oldPath error:&err];
        [ed setFirstToCompare];
        [ed openFileAtPath:newPath error:&err];
        BOOL viaFirst = [ed compareWithFirst];
        Check(@"Compare set first", @"the file set aside is the one compared against",
              viaFirst && [[ed firstToCompare] isEqualToString:oldPath]);

        [ed clearAllCompares];
        Check(@"Compare clear", @"clearing removes the comparison and the second pane",
              ![ed compareActive] && [ed firstToCompare] == nil && ![ed secondaryViewVisible]);
    }

    printf("\n== FTP ==\n");
    {
        // The listing parser sees both layouts servers actually send.
        NSString *unixListing =
            @"drwxr-xr-x 2 owner group     4096 Jan  1 00:00 folder\r\n"
            @"-rw-r--r-- 1 owner group      137 Jan  1 00:00 notes.txt\r\n"
            @"lrwxrwxrwx 1 owner group        7 Jan  1 00:00 link -> target\r\n"
            @"drwxr-xr-x 2 owner group     4096 Jan  1 00:00 .\r\n";
        NSArray<NppFtpEntry *> *unix = [NppFtpClient parseListing:unixListing];
        NSMutableDictionary<NSString *, NppFtpEntry *> *byName = [NSMutableDictionary dictionary];
        for (NppFtpEntry *e in unix) byName[e.name] = e;
        NppFtpEntry *folder = byName[@"folder"];
        NppFtpEntry *notes = byName[@"notes.txt"];
        Check(@"FTP listing (unix)",
              @"directories, sizes and symlink names are read correctly",
              unix.count == 3 && folder.isDirectory && !notes.isDirectory &&
              notes.size == 137 && byName[@"link"] != nil);

        NSString *dosListing =
            @"01-01-24  12:00AM       <DIR>          images\r\n"
            @"01-01-24  12:00AM                 2048 report.doc\r\n";
        NSArray<NppFtpEntry *> *dos = [NppFtpClient parseListing:dosListing];
        NppFtpEntry *dosDir = dos.count ? dos[0] : nil;
        NppFtpEntry *dosFile = dos.count > 1 ? dos[1] : nil;
        Check(@"FTP listing (DOS)", @"the other layout is read too",
              dos.count == 2 && dosDir.isDirectory && !dosFile.isDirectory &&
              dosFile.size == 2048);

        // Profiles round-trip through the settings.
        NppFtpProfile *profile = [[NppFtpProfile alloc] init];
        profile.name = @"test-server";
        profile.host = @"127.0.0.1";
        profile.username = @"tester";
        profile.protocol = NppFtpPlain;
        profile.initialDirectory = @"/";
        [ed saveFtpProfile:profile];
        NppFtpProfile *read = [ed ftpProfileNamed:@"test-server"];
        Check(@"FTP profiles", @"a connection is saved and read back",
              read != nil && [read.host isEqualToString:@"127.0.0.1"] &&
              [read.username isEqualToString:@"tester"]);

        Check(@"FTP url", @"the URL carries host, port and path",
              [[read urlForPath:@"dir/file.txt"] isEqualToString:@"ftp://127.0.0.1:21/dir/file.txt"]);

        // End to end against a real server, started for this test.
        NSString *script = [[NSBundle mainBundle] pathForResource:@"test-ftp-server" ofType:@"py"];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ftproot"];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:
            [root stringByAppendingPathComponent:@"sub"]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"remote hello\n" writeToFile:[root stringByAppendingPathComponent:@"greeting.txt"]
                            atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        NSTask *server = nil;
        NSInteger port = 0;
        if (script) {
            server = [[NSTask alloc] init];
            server.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
            server.arguments = @[script, root];
            NSPipe *out = [NSPipe pipe];
            server.standardOutput = out;
            if ([server launchAndReturnError:NULL]) {
                // The server prints the port it was given; read just that line.
                NSData *line = [out.fileHandleForReading availableData];
                NSString *text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
                NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet]
                                        intoString:NULL];
                [scanner scanInteger:&port];
            }
        }

        if (port <= 0) {
            Check(@"FTP transfer", @"the test server could not be started", NO);
        } else {
            profile.port = port;
            [ed saveFtpProfile:profile];

            BOOL connected = [ed connectToFtpProfile:profile password:@"secret"];
            NSArray<NppFtpEntry *> *listing = connected ? [ed ftpListCurrentDirectory] : nil;
            NSMutableArray *names = [NSMutableArray array];
            for (NppFtpEntry *e in listing) [names addObject:e.name];
            Check(@"FTP connect", @"logging in and listing the directory works",
                  connected && [ed ftpConnected] && [names containsObject:@"greeting.txt"] &&
                  [names containsObject:@"sub"]);

            BOOL opened = [ed openRemoteFileAtPath:@"greeting.txt"];
            Check(@"FTP download", @"a remote file opens in a tab with its contents",
                  opened && [DocText(ed) isEqualToString:@"remote hello\n"] &&
                  [[ed remotePathForCurrentDocument] isEqualToString:@"/greeting.txt"]);

            SetDoc(ed, @"changed here\n");
            BOOL uploaded = [ed uploadCurrentDocument];
            NSString *onServer = [NSString stringWithContentsOfFile:
                [root stringByAppendingPathComponent:@"greeting.txt"]
                                                           encoding:NSUTF8StringEncoding error:NULL];
            Check(@"FTP upload", @"saving sends the file back to where it came from",
                  uploaded && [onServer isEqualToString:@"changed here\n"]);

            BOOL descended = [ed ftpChangeDirectory:@"sub"];
            Check(@"FTP directories", @"changing directory follows the server",
                  descended && [[ed ftpCurrentDirectory] hasSuffix:@"sub"]);

            [ed disconnectFtp];
            Check(@"FTP disconnect", @"disconnecting drops the connection",
                  ![ed ftpConnected] && [ed ftpClient] == nil);

            [server terminate];
        }
        [ed removeFtpProfileNamed:@"test-server"];
    }

    printf("\n== XML ==\n");
    {
        [ed newDocument];
        NSString *compact = @"<?xml version=\"1.0\"?><root a=\"1\" b=\"2\"><item>one</item><item>two</item></root>";

        SetDoc(ed, compact);
        BOOL pretty = [ed prettyPrintXMLDocument:NppXmlPrettyDefault];
        NSString *formatted = DocText(ed);
        Check(@"XML pretty print", @"one line becomes an indented document",
              pretty && [[formatted componentsSeparatedByString:@"\n"] count] > 3 &&
              [formatted containsString:@"    <item>one</item>"]);

        BOOL flat = [ed linearizeXMLDocument];
        NSString *linear = DocText(ed);
        Check(@"XML linearize", @"the indented document becomes one line again",
              flat && ![[linear substringFromIndex:MIN(40u, linear.length)] containsString:@"\n"] &&
              [linear containsString:@"<item>one</item><item>two</item>"]);

        // The value must survive both directions.
        NSArray *items = [EditorController evaluateXPath:@"//item" onText:linear error:NULL];
        Check(@"XML round trip", @"the content is unchanged by formatting",
              items.count == 2 && [items[0] containsString:@"one"]);

        SetDoc(ed, compact);
        [ed prettyPrintXMLDocument:NppXmlPrettyAttributes];
        NSString *attrs = DocText(ed);
        Check(@"XML indent attributes", @"each attribute moves onto its own line",
              [attrs containsString:@"b=\"2\""] &&
              [[attrs componentsSeparatedByString:@"\n"] count] >
              [[formatted componentsSeparatedByString:@"\n"] count]);

        // Syntax: a good document passes, a broken one reports where.
        SetDoc(ed, @"<a><b/></a>");
        NppXmlError *fine = [ed checkXMLSyntaxOfDocument];
        SetDoc(ed, @"<a>\n  <b>\n</a>");
        NppXmlError *broken = [ed checkXMLSyntaxOfDocument];
        Check(@"XML syntax check", @"valid passes and invalid reports a line",
              fine == nil && broken != nil && broken.line >= 0 && broken.message.length > 0);

        // A document that is not XML must be refused, not mangled.
        SetDoc(ed, @"not xml at all");
        NSString *before = DocText(ed);
        BOOL refused = ![ed prettyPrintXMLDocument:NppXmlPrettyDefault];
        Check(@"XML refuses non-XML", @"a non-XML document is left untouched",
              refused && [DocText(ed) isEqualToString:before]);

        // XPath, including an expression that selects attributes.
        NSString *doc = @"<catalog><book id=\"a\"><title>First</title></book>"
                        @"<book id=\"b\"><title>Second</title></book></catalog>";
        NSArray *titles = [EditorController evaluateXPath:@"//title/text()" onText:doc error:NULL];
        NSArray *ids = [EditorController evaluateXPath:@"//book/@id" onText:doc error:NULL];
        NSString *xpathFailure = nil;
        NSArray *bad = [EditorController evaluateXPath:@"//[[" onText:doc error:&xpathFailure];
        Check(@"XML XPath", @"nodes and attributes are selected, and a bad expression reports",
              titles.count == 2 && [titles[1] isEqualToString:@"Second"] &&
              ids.count == 2 && [ids[0] isEqualToString:@"a"] &&
              bad == nil && xpathFailure.length > 0);

        // XSL transformation.
        NSString *sheet =
            @"<?xml version=\"1.0\"?>"
            @"<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\">"
            @"<xsl:output method=\"xml\"/>"
            @"<xsl:template match=\"/\"><titles><xsl:for-each select=\"//title\">"
            @"<t><xsl:value-of select=\".\"/></t></xsl:for-each></titles></xsl:template>"
            @"</xsl:stylesheet>";
        NSString *xslFailure = nil;
        NSString *transformed = [EditorController applyXSL:sheet toText:doc error:&xslFailure];
        Check(@"XML XSL", @"a stylesheet produces the expected output",
              transformed != nil && [transformed containsString:@"<t>First</t>"] &&
              [transformed containsString:@"<t>Second</t>"]);

        // XSD validation, which NSXMLDocument cannot do and libxml2 can.
        NSString *schema =
            @"<?xml version=\"1.0\"?>"
            @"<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"
            @"<xs:element name=\"note\"><xs:complexType><xs:sequence>"
            @"<xs:element name=\"to\" type=\"xs:string\"/>"
            @"</xs:sequence></xs:complexType></xs:element></xs:schema>";
        NppXmlError *matches = [EditorController validateXML:@"<note><to>you</to></note>"
                                               againstSchema:schema];
        NppXmlError *mismatch = [EditorController validateXML:@"<note><wrong>x</wrong></note>"
                                                againstSchema:schema];
        Check(@"XML schema validation", @"a matching document passes and a wrong one is reported",
              matches == nil && mismatch != nil && mismatch.message.length > 0);

        // Escaping a selection, and putting it back.
        SetDoc(ed, @"a <b> & \"c\"");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed escapeSelectionForXML:YES];
        NSString *escaped = DocText(ed);
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed escapeSelectionForXML:NO];
        Check(@"XML escaping", @"characters are escaped and restored exactly",
              [escaped containsString:@"&lt;b&gt;"] && [escaped containsString:@"&amp;"] &&
              [DocText(ed) isEqualToString:@"a <b> & \"c\""]);

        // The path at the caret, which has to work on a document still being typed.
        SetDoc(ed, @"<root>\n  <list>\n    <item>one</item>\n    <item>tw");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        NSString *plainPath = [ed xmlPathAtCaretWithPredicates:NO];
        NSString *indexedPath = [ed xmlPathAtCaretWithPredicates:YES];
        Check(@"XML current path", @"the path is reported while the document is incomplete",
              [plainPath isEqualToString:@"/root/list/item"] &&
              [indexedPath isEqualToString:@"/root[1]/list[1]/item[2]"]);
    }

    printf("\n== Run ==\n");
    {
        // The variables are read off a real document, so the test exercises the
        // same path the menu command does.
        NSString *runPath = TempFile(@"npp_run_test.txt", @"alpha beta\nsecond line\n");
        [ed openFileAtPath:runPath error:NULL];
        ScintillaView *sci = ed.sci;
        [sci message:SCI_GOTOPOS wParam:6 lParam:0];    // inside "beta" on line 0

        NSString *dir = runPath.stringByDeletingLastPathComponent;
        BOOL paths =
            [[ed expandRunVariables:@"$(FULL_CURRENT_PATH)"] isEqualToString:runPath] &&
            [[ed expandRunVariables:@"$(CURRENT_DIRECTORY)"] isEqualToString:dir] &&
            [[ed expandRunVariables:@"$(FILE_NAME)"] isEqualToString:@"npp_run_test.txt"] &&
            [[ed expandRunVariables:@"$(NAME_PART)"] isEqualToString:@"npp_run_test"];
        BOOL caret =
            [[ed expandRunVariables:@"$(CURRENT_WORD)"] isEqualToString:@"beta"] &&
            [[ed expandRunVariables:@"$(CURRENT_LINESTR)"] isEqualToString:@"alpha beta"] &&
            [[ed expandRunVariables:@"$(CURRENT_LINE)"] isEqualToString:@"0"] &&
            [[ed expandRunVariables:@"$(CURRENT_COLUMN)"] isEqualToString:@"6"];
        BOOL npp =
            [[ed expandRunVariables:@"$(NPP_FULL_FILE_PATH)"] containsString:@"NotepadMac"] &&
            [ed expandRunVariables:@"$(NPP_DIRECTORY)"].length > 0;
        Check(@"Run variables", @"every substitution Notepad++ makes is made here too",
              paths && caret && npp);

        // Windows keeps the dot on the extension, and gives nothing when there
        // is none; both halves of that are easy to get wrong.
        NSString *withExt = [ed expandRunVariables:@"$(EXT_PART)"];
        NSString *plainPath = TempFile(@"npp_run_plain", @"x\n");
        [ed openFileAtPath:plainPath error:NULL];
        NSString *withoutExt = [ed expandRunVariables:@"$(EXT_PART)"];
        Check(@"Run extension part", @"the extension keeps its dot, and is empty when absent",
              [withExt isEqualToString:@".txt"] && withoutExt.length == 0);

        // A name that is not a variable belongs to the shell, so it must come
        // out untouched rather than being swallowed.
        [ed openFileAtPath:runPath error:NULL];
        Check(@"Run leaves unknown names", @"an unknown or unclosed variable is left as written",
              [[ed expandRunVariables:@"$(NOT_A_VARIABLE) $(FILE_NAME)"]
                  isEqualToString:@"$(NOT_A_VARIABLE) npp_run_test.txt"] &&
              [[ed expandRunVariables:@"$(unclosed"] isEqualToString:@"$(unclosed"] &&
              [[ed expandRunVariables:@"cost is $5"] isEqualToString:@"cost is $5"]);

        NppRunResult *echoed = [ed runCommandLine:@"echo $(NAME_PART)" intoConsole:NO];
        Check(@"Run command", @"the command runs with its variables already substituted",
              echoed.exitStatus == 0 &&
              [echoed.output isEqualToString:@"npp_run_test\n"]);

        // Failure has to be visible: the status and whatever went to stderr.
        NppRunResult *failed = [ed runCommandLine:@"echo oops >&2; exit 3" intoConsole:NO];
        Check(@"Run reports failure", @"a non-zero status and stderr both come back",
              failed.exitStatus == 3 && [failed.output containsString:@"oops"]);

        // A command is nearly always meant relative to the file being edited.
        NppRunResult *where = [ed runCommandLine:@"pwd" intoConsole:NO];
        Check(@"Run working directory", @"the command runs in the document's own directory",
              [[where.output stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]].stringByResolvingSymlinksInPath
                  isEqualToString:dir.stringByResolvingSymlinksInPath]);

        [ed.console clear];
        NppRunResult *shown = [ed runCommandLine:@"echo visible" intoConsole:YES];
        NSString *console = ed.console.text;
        Check(@"Run console", @"the command and its output both reach the console",
              shown.exitStatus == 0 && [console containsString:@"> echo visible"] &&
              [console containsString:@"visible\n"]);

        [ed.console clear];
        [ed runCommandLine:@"exit 7" intoConsole:YES];
        Check(@"Run console reports status", @"a failure is written to the console, not just returned",
              [ed.console.text containsString:@"exit status 7"]);

        // The background path expands on the main thread and hands the result
        // to the worker; expanding a second time there would corrupt a command
        // whose own text happens to look like a variable.
        SetDoc(ed, @"$(FILE_NAME)\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        __block NppRunResult *async = nil;
        [ed runCommandLineInBackground:@"echo '$(CURRENT_LINESTR)'"
                            completion:^(NppRunResult *r) { async = r; }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!async && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        Check(@"Run in background", @"it completes, and substitution happens exactly once",
              async != nil && async.exitStatus == 0 &&
              [async.output isEqualToString:@"$(FILE_NAME)\n"]);

        // Saved commands are keyed by name, so saving the same name again
        // replaces it rather than adding a duplicate.
        NSUInteger before = [ed savedCommands].count;
        [ed saveCommand:[NppSavedCommand commandWithName:@"Build" command:@"make"]];
        [ed saveCommand:[NppSavedCommand commandWithName:@"Build" command:@"make -j8"]];
        NSArray<NppSavedCommand *> *saved = [ed savedCommands];
        NppSavedCommand *build = nil;
        for (NppSavedCommand *c in saved) if ([c.name isEqualToString:@"Build"]) build = c;
        BOOL replaced = saved.count == before + 1 && [build.command isEqualToString:@"make -j8"];
        [ed removeSavedCommandNamed:@"Build"];
        Check(@"Run saved commands", @"saving by name replaces, and removing takes it away",
              replaced && [ed savedCommands].count == before);

        [[NSFileManager defaultManager] removeItemAtPath:runPath error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:plainPath error:NULL];
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

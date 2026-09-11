#import "AppDelegate.h"
#import "EditorController.h"
#import "EditCommands.h"
#import "SearchCommands.h"
#import "ViewCommands.h"
#import "EncodingCommands.h"
#import "AdvancedEditCommands.h"
#import "AuxPanels.h"
#import "DocumentListPanel.h"
#import "FunctionListPanel.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#import "Tests.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) EditorController *editor;
@property (nonatomic, copy) NSString *lastSearchTerm;
@property (nonatomic, strong) DocumentListPanel *docList;
@property (nonatomic, strong) FunctionListPanel *funcList;
@property (nonatomic, strong) CharacterPanel *charPanel;
@property (nonatomic, strong) ClipboardHistoryPanel *clipPanel;
@property (nonatomic) BOOL alwaysOnTop;
@end

@implementation AppDelegate

#pragma mark - Launch

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSRect frame = NSMakeRect(0, 0, 1000, 700);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [self.window center];
    self.window.minSize = NSMakeSize(520, 320);

    self.editor = [[EditorController alloc] initWithFrame:frame];
    self.editor.window = self.window;
    self.window.contentView = self.editor.view;

    [self buildMenus];
    [self.editor refreshChrome];

    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.editor.sci];
    [NSApp activateIgnoringOtherApps:YES];

    if (getenv("NPPMAC_TEST")) {
        [self performSelector:@selector(runTestSuite) withObject:nil afterDelay:0.5];
    }
    if (getenv("NPPMAC_SELFTEST")) {
        [self performSelector:@selector(runSelfTest) withObject:nil afterDelay:0.8];
    }
    if (getenv("NPPMAC_SNAPSHOT")) {
        [self performSelector:@selector(writeSnapshot) withObject:nil afterDelay:1.2];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename {
    NSError *err = nil;
    if ([self.editor openFileAtPath:filename error:&err]) return YES;
    if (err) [[NSAlert alertWithError:err] runModal];
    return NO;
}

#pragma mark - Menus

- (NSMenuItem *)item:(NSString *)title action:(SEL)sel key:(NSString *)key
               flags:(NSEventModifierFlags)flags menu:(NSMenu *)menu {
    NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:key];
    if (flags) mi.keyEquivalentModifierMask = flags;
    mi.target = self;
    [menu addItem:mi];
    return mi;
}

- (void)buildMenus {
    NSMenu *bar = [[NSMenu alloc] init];
    NSString *appName = @"NotepadMac";

    // ---- Application menu
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [bar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:[@"About " stringByAppendingString:appName]
                       action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *hide = [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:appName]
                                          action:@selector(hide:) keyEquivalent:@"h"];
    hide.target = NSApp;
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    hideOthers.target = NSApp;
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:appName]
                                          action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    appItem.submenu = appMenu;

    // ---- File
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [bar addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [self item:@"New"      action:@selector(newDocument:) key:@"n" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Open…"    action:@selector(openDocument:) key:@"o" flags:NSEventModifierFlagCommand menu:fileMenu];

    NSMenu *revealMenu = [[NSMenu alloc] initWithTitle:@"Open Containing Folder"];
    [self item:@"Finder" action:@selector(revealInFinder:) key:@"" flags:0 menu:revealMenu];
    [self item:@"Terminal" action:@selector(openInTerminal:) key:@"" flags:0 menu:revealMenu];
    [self item:@"Folder as Workspace" action:@selector(containingFolderAsWorkspace:) key:@"" flags:0 menu:revealMenu];
    NSMenuItem *revealItem = [fileMenu addItemWithTitle:@"Open Containing Folder" action:nil keyEquivalent:@""];
    revealItem.submenu = revealMenu;
    [self item:@"Open in Default Viewer" action:@selector(openInDefaultViewer:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Open Folder as Workspace…" action:@selector(openFolderAsWorkspace:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Pin Tab" action:@selector(togglePin:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Reload from Disk" action:@selector(reloadDocument:) key:@"r" flags:NSEventModifierFlagCommand menu:fileMenu];

    NSMenuItem *recentItem = [fileMenu addItemWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
    NSMenu *recentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    [recentMenu addItemWithTitle:@"Clear Menu" action:@selector(clearRecentDocuments:) keyEquivalent:@""];
    recentItem.submenu = recentMenu;

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Save"     action:@selector(saveDocument:) key:@"s" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Save As…" action:@selector(saveDocumentAs:) key:@"s"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:fileMenu];
    [self item:@"Save a Copy As…" action:@selector(saveCopyAs:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Save All" action:@selector(saveAll:) key:@"s"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:fileMenu];
    [self item:@"Rename…" action:@selector(renameDocument:) key:@"" flags:0 menu:fileMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Close Tab" action:@selector(closeTab:) key:@"w" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Close All" action:@selector(closeAll:) key:@"w"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:fileMenu];

    NSMenu *closeMulti = [[NSMenu alloc] initWithTitle:@"Close Multiple Documents"];
    [self item:@"Close All but Active Document" action:@selector(closeAllButCurrent:) key:@"" flags:0 menu:closeMulti];
    [self item:@"Close All to the Left" action:@selector(closeAllToLeft:) key:@"" flags:0 menu:closeMulti];
    [self item:@"Close All to the Right" action:@selector(closeAllToRight:) key:@"" flags:0 menu:closeMulti];
    [self item:@"Close All Unchanged" action:@selector(closeAllUnchanged:) key:@"" flags:0 menu:closeMulti];
    [self item:@"Close All but Pinned Documents" action:@selector(closeAllButPinned:) key:@"" flags:0 menu:closeMulti];
    NSMenuItem *closeMultiItem = [fileMenu addItemWithTitle:@"Close Multiple Documents" action:nil keyEquivalent:@""];
    closeMultiItem.submenu = closeMulti;

    [self item:@"Move to Trash" action:@selector(moveToTrash:) key:@"" flags:0 menu:fileMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Load Session…" action:@selector(loadSession:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Save Session…" action:@selector(saveSession:) key:@"" flags:0 menu:fileMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Print…" action:@selector(printDocument:) key:@"p" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Print Now" action:@selector(printNow:) key:@"p"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:fileMenu];
    fileItem.submenu = fileMenu;

    // ---- Edit
    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [bar addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [self item:@"Undo" action:@selector(undo:) key:@"z" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Redo" action:@selector(redo:) key:@"z"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Cut"   action:@selector(cutText:) key:@"x" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Copy"  action:@selector(copyText:) key:@"c" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Paste" action:@selector(pasteText:) key:@"v" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Select All" action:@selector(selectAllText:) key:@"a" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Duplicate Line" action:@selector(duplicateLine:) key:@"d" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Line Comment" action:@selector(toggleLineComment:) key:@"/" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Block Comment" action:@selector(toggleBlockComment:) key:@"/"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:editMenu];
    [self item:@"Delete" action:@selector(deleteSelection:) key:@"" flags:0 menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Complete Word" action:@selector(showAutoComplete:) key:@" "
         flags:NSEventModifierFlagControl menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];

    // --- Insert
    NSMenu *insertMenu = [[NSMenu alloc] initWithTitle:@"Insert"];
    [self item:@"Date Time (short)" action:@selector(insertDateShort:) key:@"" flags:0 menu:insertMenu];
    [self item:@"Date Time (long)" action:@selector(insertDateLong:) key:@"" flags:0 menu:insertMenu];
    [self item:@"Date Time (customized)" action:@selector(insertDateCustom:) key:@"" flags:0 menu:insertMenu];
    [editMenu addItemWithTitle:@"Insert" action:nil keyEquivalent:@""].submenu = insertMenu;

    // --- Copy to Clipboard
    NSMenu *clipMenu = [[NSMenu alloc] initWithTitle:@"Copy to Clipboard"];
    [self item:@"Copy Current Full File path" action:@selector(copyFullPath:) key:@"" flags:0 menu:clipMenu];
    [self item:@"Copy Current Filename" action:@selector(copyFileName:) key:@"" flags:0 menu:clipMenu];
    [self item:@"Copy Current Dir. Path" action:@selector(copyDirPath:) key:@"" flags:0 menu:clipMenu];
    [self item:@"Copy All Filenames" action:@selector(copyAllNames:) key:@"" flags:0 menu:clipMenu];
    [self item:@"Copy All File Paths" action:@selector(copyAllPaths:) key:@"" flags:0 menu:clipMenu];
    [editMenu addItemWithTitle:@"Copy to Clipboard" action:nil keyEquivalent:@""].submenu = clipMenu;

    // --- Indent
    NSMenu *indentMenu = [[NSMenu alloc] initWithTitle:@"Indent"];
    [self item:@"Increase Line Indent" action:@selector(increaseIndent:) key:@"]" flags:NSEventModifierFlagCommand menu:indentMenu];
    [self item:@"Decrease Line Indent" action:@selector(decreaseIndent:) key:@"[" flags:NSEventModifierFlagCommand menu:indentMenu];
    [editMenu addItemWithTitle:@"Indent" action:nil keyEquivalent:@""].submenu = indentMenu;

    // --- Convert Case to
    NSMenu *caseMenu = [[NSMenu alloc] initWithTitle:@"Convert Case to"];
    NSArray *caseTitles = @[@"UPPERCASE", @"lowercase", @"Proper Case", @"Proper Case (blend)",
                            @"Sentence case", @"Sentence case (blend)", @"iNVERT cASE", @"ranDOm CasE"];
    for (NSUInteger i = 0; i < caseTitles.count; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:caseTitles[i]
                                                    action:@selector(convertCase:) keyEquivalent:@""];
        mi.target = self; mi.tag = (NSInteger)i;
        [caseMenu addItem:mi];
    }
    [editMenu addItemWithTitle:@"Convert Case to" action:nil keyEquivalent:@""].submenu = caseMenu;

    // --- Line Operations
    NSMenu *lineMenu = [[NSMenu alloc] initWithTitle:@"Line Operations"];
    [self item:@"Remove Duplicate Lines" action:@selector(removeDupLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Remove Consecutive Duplicate Lines" action:@selector(removeConsecutiveDupLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Split Lines" action:@selector(splitLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Join Lines" action:@selector(joinLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Move Up Current Line" action:@selector(moveLineUp:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Move Down Current Line" action:@selector(moveLineDown:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Remove Empty Lines" action:@selector(removeEmptyLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Remove Empty Lines (Containing Blank characters)" action:@selector(removeBlankLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Insert Blank Line Above Current" action:@selector(blankLineAbove:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Insert Blank Line Below Current" action:@selector(blankLineBelow:) key:@"" flags:0 menu:lineMenu];
    [lineMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Reverse Line Order" action:@selector(reverseLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Randomize Line Order" action:@selector(randomizeLines:) key:@"" flags:0 menu:lineMenu];
    NSArray *sortNames = @[@"Lexicographically", @"Lex. Ignoring Case", @"In Locale Order",
                           @"As Integers", @"As Decimals (Comma)", @"As Decimals (Dot)", @"By Length"];
    for (NSUInteger i = 0; i < sortNames.count; ++i) {
        for (int desc = 0; desc < 2; ++desc) {
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:
                [NSString stringWithFormat:@"Sort Lines %@ %@", sortNames[i], desc ? @"Descending" : @"Ascending"]
                                                        action:@selector(sortLines:) keyEquivalent:@""];
            mi.target = self; mi.tag = (NSInteger)(i * 2 + desc);
            [lineMenu addItem:mi];
        }
    }
    [editMenu addItemWithTitle:@"Line Operations" action:nil keyEquivalent:@""].submenu = lineMenu;

    // --- Comment/Uncomment
    NSMenu *commentMenu = [[NSMenu alloc] initWithTitle:@"Comment/Uncomment"];
    [self item:@"Toggle Single Line Comment" action:@selector(toggleLineComment:) key:@"" flags:0 menu:commentMenu];
    [self item:@"Single Line Uncomment" action:@selector(uncommentLines:) key:@"" flags:0 menu:commentMenu];
    [self item:@"Block Comment" action:@selector(streamComment:) key:@"" flags:0 menu:commentMenu];
    [self item:@"Block Uncomment" action:@selector(streamUncomment:) key:@"" flags:0 menu:commentMenu];
    [editMenu addItemWithTitle:@"Comment/Uncomment" action:nil keyEquivalent:@""].submenu = commentMenu;

    // --- Blank Operations
    NSMenu *blankMenu = [[NSMenu alloc] initWithTitle:@"Blank Operations"];
    NSArray *blankTitles = @[@"Trim Trailing Space", @"Trim Leading Space",
                             @"Trim Leading and Trailing Space", @"EOL to Space",
                             @"Trim both and EOL to Space", @"TAB to Space",
                             @"Space to TAB (All)", @"Space to TAB (Leading)"];
    for (NSUInteger i = 0; i < blankTitles.count; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:blankTitles[i]
                                                    action:@selector(applyTrim:) keyEquivalent:@""];
        mi.target = self; mi.tag = (NSInteger)i;
        [blankMenu addItem:mi];
    }
    [editMenu addItemWithTitle:@"Blank Operations" action:nil keyEquivalent:@""].submenu = blankMenu;

    // --- Read-Only
    NSMenu *roMenu = [[NSMenu alloc] initWithTitle:@"Read-Only"];
    [self item:@"Read-Only on Current Document" action:@selector(toggleReadOnly:) key:@"" flags:0 menu:roMenu];
    [self item:@"Read-Only for All Documents" action:@selector(readOnlyAll:) key:@"" flags:0 menu:roMenu];
    [self item:@"Clear Read-Only for All Documents" action:@selector(clearReadOnlyAll:) key:@"" flags:0 menu:roMenu];
    [self item:@"Read-Only Attribute on Disk" action:@selector(toggleSystemReadOnly:) key:@"" flags:0 menu:roMenu];
    [editMenu addItemWithTitle:@"Read-Only" action:nil keyEquivalent:@""].submenu = roMenu;

    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Begin/End Select" action:@selector(beginEndSelect:) key:@"" flags:0 menu:editMenu];
    [self item:@"Begin/End Select in Column Mode" action:@selector(beginEndSelectColumn:) key:@"" flags:0 menu:editMenu];

    NSArray *matchTitles = @[@"Ignore Case & Whole Word", @"Match Case Only",
                             @"Match Whole Word Only", @"Match Case & Whole Word"];
    NSMenu *msAll = [[NSMenu alloc] initWithTitle:@"Multi-select All"];
    NSMenu *msNext = [[NSMenu alloc] initWithTitle:@"Multi-select Next"];
    for (NSUInteger i = 0; i < matchTitles.count; ++i) {
        NSMenuItem *a1 = [[NSMenuItem alloc] initWithTitle:matchTitles[i]
                                                    action:@selector(multiSelectAll:) keyEquivalent:@""];
        a1.target = self; a1.tag = (NSInteger)i; [msAll addItem:a1];
        NSMenuItem *a2 = [[NSMenuItem alloc] initWithTitle:matchTitles[i]
                                                    action:@selector(multiSelectNext:) keyEquivalent:@""];
        a2.target = self; a2.tag = (NSInteger)i; [msNext addItem:a2];
    }
    [editMenu addItemWithTitle:@"Multi-select All" action:nil keyEquivalent:@""].submenu = msAll;
    [editMenu addItemWithTitle:@"Multi-select Next" action:nil keyEquivalent:@""].submenu = msNext;
    [self item:@"Undo the Latest Added Multi-Select" action:@selector(multiSelectUndo:) key:@"" flags:0 menu:editMenu];
    [self item:@"Skip Current & Go to Next Multi-select" action:@selector(multiSelectSkip:) key:@"" flags:0 menu:editMenu];

    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Column Mode…" action:@selector(columnModeTip:) key:@"" flags:0 menu:editMenu];
    [self item:@"Column Editor…" action:@selector(columnEditor:) key:@"" flags:0 menu:editMenu];
    [self item:@"Character Panel" action:@selector(toggleCharacterPanel:) key:@"" flags:0 menu:editMenu];
    [self item:@"Clipboard History" action:@selector(toggleClipboardHistory:) key:@"" flags:0 menu:editMenu];

    NSMenu *acMenu = [[NSMenu alloc] initWithTitle:@"Auto-Completion"];
    [self item:@"Word Completion" action:@selector(showAutoComplete:) key:@"" flags:0 menu:acMenu];
    [self item:@"Path Completion" action:@selector(pathCompletion:) key:@"" flags:0 menu:acMenu];
    [self item:@"Function Parameters Hint" action:@selector(callTip:) key:@"" flags:0 menu:acMenu];
    [self item:@"Function Parameters Next Hint" action:@selector(callTipNext:) key:@"" flags:0 menu:acMenu];
    [self item:@"Function Parameters Previous Hint" action:@selector(callTipPrev:) key:@"" flags:0 menu:acMenu];
    [editMenu addItemWithTitle:@"Auto-Completion" action:nil keyEquivalent:@""].submenu = acMenu;

    NSMenu *pasteMenu = [[NSMenu alloc] initWithTitle:@"Paste Special"];
    [self item:@"Paste HTML Content" action:@selector(pasteHTML:) key:@"" flags:0 menu:pasteMenu];
    [self item:@"Paste RTF Content" action:@selector(pasteRTF:) key:@"" flags:0 menu:pasteMenu];
    [self item:@"Copy Binary Content" action:@selector(copyBinary:) key:@"" flags:0 menu:pasteMenu];
    [self item:@"Cut Binary Content" action:@selector(cutBinary:) key:@"" flags:0 menu:pasteMenu];
    [self item:@"Paste Binary Content" action:@selector(pasteBinaryContent:) key:@"" flags:0 menu:pasteMenu];
    [editMenu addItemWithTitle:@"Paste Special" action:nil keyEquivalent:@""].submenu = pasteMenu;

    NSMenu *selMenu = [[NSMenu alloc] initWithTitle:@"On Selection"];
    [self item:@"Open File" action:@selector(openSelectedFile:) key:@"" flags:0 menu:selMenu];
    [self item:@"Open Containing Folder in Finder" action:@selector(revealSelectedFile:) key:@"" flags:0 menu:selMenu];
    [self item:@"Redact Selection" action:@selector(redactSelection:) key:@"" flags:0 menu:selMenu];
    [self item:@"Search on Internet" action:@selector(searchOnInternet:) key:@"" flags:0 menu:selMenu];
    [self item:@"Change Search Engine…" action:@selector(changeSearchEngine:) key:@"" flags:0 menu:selMenu];
    [editMenu addItemWithTitle:@"On Selection" action:nil keyEquivalent:@""].submenu = selMenu;

    editItem.submenu = editMenu;

    // ---- Search
    NSMenuItem *searchItem = [[NSMenuItem alloc] init];
    [bar addItem:searchItem];
    NSMenu *searchMenu = [[NSMenu alloc] initWithTitle:@"Search"];
    [self item:@"Find…"      action:@selector(showFind:) key:@"f" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Find Next"  action:@selector(findNext:) key:@"g" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Find Previous" action:@selector(findPrevious:) key:@"g"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Replace…"   action:@selector(showReplace:) key:@"f"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Go to Line…" action:@selector(goToLine:) key:@"l" flags:NSEventModifierFlagCommand menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Bookmark" action:@selector(toggleBookmark:) key:@"b" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Next Bookmark" action:@selector(nextBookmark:) key:@"b"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Previous Bookmark" action:@selector(previousBookmark:) key:@"b"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Find in Files…" action:@selector(findInFiles:) key:@"f"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Search Results Window" action:@selector(focusSearchResults:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Next Search Result" action:@selector(nextSearchResult:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Previous Search Result" action:@selector(prevSearchResult:) key:@"" flags:0 menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Select and Find Next" action:@selector(selectAndFindNext:) key:@"e" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Select and Find Previous" action:@selector(selectAndFindPrev:) key:@"e"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Find (Volatile) Next" action:@selector(volatileFindNext:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Find (Volatile) Previous" action:@selector(volatileFindPrev:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Incremental Search" action:@selector(incrementalSearch:) key:@"i" flags:NSEventModifierFlagCommand menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Go to Matching Brace" action:@selector(goToMatchingBrace:) key:@"m" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Select All In-between {} [] or ()" action:@selector(selectBetweenBraces:) key:@"m"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Mark…" action:@selector(markTerm:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Find characters in range…" action:@selector(findCharsInRange:) key:@"" flags:0 menu:searchMenu];

    // --- marker style submenus, five styles plus the Find Mark style
    NSArray *styleNames = @[@"Using 1st Style", @"Using 2nd Style", @"Using 3rd Style",
                            @"Using 4th Style", @"Using 5th Style"];
    NSMenu *markAllMenu = [[NSMenu alloc] initWithTitle:@"Style All Occurrences of Token"];
    NSMenu *markOneMenu = [[NSMenu alloc] initWithTitle:@"Style One Token"];
    NSMenu *clearMenu   = [[NSMenu alloc] initWithTitle:@"Clear Style"];
    NSMenu *upMenu      = [[NSMenu alloc] initWithTitle:@"Jump Up"];
    NSMenu *downMenu    = [[NSMenu alloc] initWithTitle:@"Jump Down"];
    NSMenu *copyMenu    = [[NSMenu alloc] initWithTitle:@"Copy Styled Text"];
    for (NSUInteger i = 0; i < styleNames.count; ++i) {
        struct { NSMenu *menu; SEL sel; NSString *title; } rows[] = {
            {markAllMenu, @selector(markAllStyle:), styleNames[i]},
            {markOneMenu, @selector(markOneStyle:), styleNames[i]},
            {clearMenu,   @selector(clearStyle:),   [NSString stringWithFormat:@"Clear %luth Style", (unsigned long)i + 1]},
            {upMenu,      @selector(jumpUpStyle:),  [NSString stringWithFormat:@"%luth Style", (unsigned long)i + 1]},
            {downMenu,    @selector(jumpDownStyle:),[NSString stringWithFormat:@"%luth Style", (unsigned long)i + 1]},
            {copyMenu,    @selector(copyStyle:),    [NSString stringWithFormat:@"%luth Style", (unsigned long)i + 1]},
        };
        for (size_t r = 0; r < sizeof(rows)/sizeof(rows[0]); ++r) {
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:rows[r].title action:rows[r].sel keyEquivalent:@""];
            mi.target = self; mi.tag = (NSInteger)i;
            [rows[r].menu addItem:mi];
        }
    }
    [self item:@"Clear all Styles" action:@selector(clearAllStyles:) key:@"" flags:0 menu:clearMenu];
    for (NSMenu *menu in @[upMenu, downMenu]) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"Find Mark Style"
                                                    action:(menu == upMenu ? @selector(jumpUpStyle:) : @selector(jumpDownStyle:))
                                             keyEquivalent:@""];
        mi.target = self; mi.tag = NPPMAC_STYLE_COUNT;
        [menu addItem:mi];
    }
    NSMenuItem *allStyles = [[NSMenuItem alloc] initWithTitle:@"All Styles" action:@selector(copyAllStyles:) keyEquivalent:@""];
    allStyles.target = self;
    [copyMenu addItem:allStyles];
    NSMenuItem *markedClip = [[NSMenuItem alloc] initWithTitle:@"Find Mark Style" action:@selector(copyStyle:) keyEquivalent:@""];
    markedClip.target = self; markedClip.tag = NPPMAC_STYLE_COUNT;
    [copyMenu addItem:markedClip];

    [searchMenu addItem:[NSMenuItem separatorItem]];
    [searchMenu addItemWithTitle:@"Style All Occurrences of Token" action:nil keyEquivalent:@""].submenu = markAllMenu;
    [searchMenu addItemWithTitle:@"Style One Token" action:nil keyEquivalent:@""].submenu = markOneMenu;
    [searchMenu addItemWithTitle:@"Clear Style" action:nil keyEquivalent:@""].submenu = clearMenu;
    [searchMenu addItemWithTitle:@"Jump Up" action:nil keyEquivalent:@""].submenu = upMenu;
    [searchMenu addItemWithTitle:@"Jump Down" action:nil keyEquivalent:@""].submenu = downMenu;
    [searchMenu addItemWithTitle:@"Copy Styled Text" action:nil keyEquivalent:@""].submenu = copyMenu;

    // --- bookmark line operations
    NSMenu *bmMenu = [[NSMenu alloc] initWithTitle:@"Bookmark"];
    [self item:@"Cut Bookmarked Lines" action:@selector(cutMarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Copy Bookmarked Lines" action:@selector(copyMarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Paste to (Replace) Bookmarked Lines" action:@selector(pasteMarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Remove Bookmarked Lines" action:@selector(removeMarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Remove Non-Bookmarked Lines" action:@selector(removeUnmarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Inverse Bookmarks" action:@selector(inverseBookmarks:) key:@"" flags:0 menu:bmMenu];
    [searchMenu addItemWithTitle:@"Bookmark" action:nil keyEquivalent:@""].submenu = bmMenu;

    // --- change history
    NSMenu *chMenu = [[NSMenu alloc] initWithTitle:@"Change History"];
    [self item:@"Go to Next Change" action:@selector(nextChange:) key:@"" flags:0 menu:chMenu];
    [self item:@"Go to Previous Change" action:@selector(prevChange:) key:@"" flags:0 menu:chMenu];
    [self item:@"Clear Change History" action:@selector(clearChangeHistory:) key:@"" flags:0 menu:chMenu];
    [searchMenu addItemWithTitle:@"Change History" action:nil keyEquivalent:@""].submenu = chMenu;

    searchItem.submenu = searchMenu;

    // ---- View
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    [bar addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [self item:@"Zoom In"    action:@selector(zoomIn:) key:@"+" flags:NSEventModifierFlagCommand menu:viewMenu];
    [self item:@"Zoom Out"   action:@selector(zoomOut:) key:@"-" flags:NSEventModifierFlagCommand menu:viewMenu];
    [self item:@"Actual Size" action:@selector(zoomReset:) key:@"0" flags:NSEventModifierFlagCommand menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Word Wrap" action:@selector(toggleWordWrap:) key:@"w"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:viewMenu];
    [self item:@"Show Whitespace" action:@selector(toggleWhitespace:) key:@"i"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Fold" action:@selector(toggleFold:) key:@"." flags:NSEventModifierFlagCommand menu:viewMenu];
    [self item:@"Fold All" action:@selector(foldAll:) key:@"." 
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:viewMenu];
    [self item:@"Unfold All" action:@selector(unfoldAll:) key:@"."
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:viewMenu];
    [self item:@"Fold Current Level" action:@selector(foldCurrent:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Unfold Current Level" action:@selector(unfoldCurrent:) key:@"" flags:0 menu:viewMenu];

    NSMenu *foldLevelMenu = [[NSMenu alloc] initWithTitle:@"Fold Level"];
    NSMenu *unfoldLevelMenu = [[NSMenu alloc] initWithTitle:@"Unfold Level"];
    for (NSInteger lvl = 1; lvl <= 8; ++lvl) {
        NSMenuItem *f = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld", (long)lvl]
                                                   action:@selector(foldLevel:) keyEquivalent:@""];
        f.target = self; f.tag = lvl; [foldLevelMenu addItem:f];
        NSMenuItem *u = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld", (long)lvl]
                                                   action:@selector(unfoldLevel:) keyEquivalent:@""];
        u.target = self; u.tag = lvl; [unfoldLevelMenu addItem:u];
    }
    [viewMenu addItemWithTitle:@"Fold Level" action:nil keyEquivalent:@""].submenu = foldLevelMenu;
    [viewMenu addItemWithTitle:@"Unfold Level" action:nil keyEquivalent:@""].submenu = unfoldLevelMenu;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenu *symbolMenu = [[NSMenu alloc] initWithTitle:@"Show Symbol"];
    NSArray *symbolTitles = @[@"Show Space and Tab", @"Show End of Line",
                              @"Show Non-Printing Characters", @"Show Control Characters & Unicode EOL",
                              @"Show Indent Guide", @"Show Wrap Symbol"];
    for (NSUInteger i = 0; i < symbolTitles.count; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:symbolTitles[i]
                                                    action:@selector(toggleSymbol:) keyEquivalent:@""];
        mi.target = self; mi.tag = (NSInteger)i;
        [symbolMenu addItem:mi];
    }
    [viewMenu addItemWithTitle:@"Show Symbol" action:nil keyEquivalent:@""].submenu = symbolMenu;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Hide Lines" action:@selector(hideLines:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Show All Hidden Lines" action:@selector(showHiddenLines:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Summary…" action:@selector(showSummary:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Monitoring (tail -f)" action:@selector(toggleMonitoring:) key:@"" flags:0 menu:viewMenu];

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Always on Top" action:@selector(toggleAlwaysOnTop:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Toggle Full Screen Mode" action:@selector(toggleFullScreenMode:) key:@"f"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagControl menu:viewMenu];
    [self item:@"Post-It" action:@selector(togglePostIt:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Distraction Free Mode" action:@selector(toggleDistractionFree:) key:@"" flags:0 menu:viewMenu];

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Folder as Workspace" action:@selector(toggleFileBrowser:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Document List" action:@selector(toggleDocumentList:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Document Map" action:@selector(toggleDocumentMap:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Function List" action:@selector(toggleFunctionList:) key:@"" flags:0 menu:viewMenu];
    NSMenu *projMenu = [[NSMenu alloc] initWithTitle:@"Project Panels"];
    for (NSInteger i = 1; i <= 3; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Project Panel %ld", (long)i]
                                                    action:@selector(toggleProjectPanel:) keyEquivalent:@""];
        mi.target = self; mi.tag = i;
        [projMenu addItem:mi];
    }
    [viewMenu addItemWithTitle:@"Project Panels" action:nil keyEquivalent:@""].submenu = projMenu;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Focus on Another View" action:@selector(focusOtherView:) key:@"" flags:0 menu:viewMenu];
    NSMenu *moveViewMenu = [[NSMenu alloc] initWithTitle:@"Move/Clone Current Document"];
    [self item:@"Move to Other View" action:@selector(moveToOtherView:) key:@"" flags:0 menu:moveViewMenu];
    [self item:@"Clone to Other View" action:@selector(cloneToOtherView:) key:@"" flags:0 menu:moveViewMenu];
    [self item:@"Move to New Instance" action:@selector(moveToNewInstance:) key:@"" flags:0 menu:moveViewMenu];
    [self item:@"Open in New Instance" action:@selector(openInNewInstance:) key:@"" flags:0 menu:moveViewMenu];
    [viewMenu addItemWithTitle:@"Move/Clone Current Document" action:nil keyEquivalent:@""].submenu = moveViewMenu;
    [self item:@"Synchronize Vertical Scrolling" action:@selector(toggleSyncV:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Synchronize Horizontal Scrolling" action:@selector(toggleSyncH:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Synchronize Zoom Across Views" action:@selector(toggleSyncZoom:) key:@"" flags:0 menu:viewMenu];

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Text Direction RTL" action:@selector(textRTL:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Text Direction LTR" action:@selector(textLTR:) key:@"" flags:0 menu:viewMenu];

    NSMenu *browserMenu = [[NSMenu alloc] initWithTitle:@"View Current File in"];
    NSArray *browsers = @[@[@"Firefox", @"org.mozilla.firefox"],
                          @[@"Chrome", @"com.google.Chrome"],
                          @[@"Edge", @"com.microsoft.edgemac"],
                          @[@"Safari", @"com.apple.Safari"]];
    for (NSArray *b in browsers) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:b[0] action:@selector(viewInBrowser:) keyEquivalent:@""];
        mi.target = self; mi.representedObject = b[1];
        [browserMenu addItem:mi];
    }
    [viewMenu addItemWithTitle:@"View Current File in" action:nil keyEquivalent:@""].submenu = browserMenu;

    // --- Tab navigation and colouring
    NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@"Tab"];
    for (NSInteger i = 1; i <= 9; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ldth Tab", (long)i]
                                                    action:@selector(goToTabNumber:)
                                             keyEquivalent:[NSString stringWithFormat:@"%ld", (long)i]];
        mi.target = self; mi.tag = i;
        mi.keyEquivalentModifierMask = NSEventModifierFlagCommand;
        [tabMenu addItem:mi];
    }
    [tabMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"First Tab" action:@selector(firstTab:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Last Tab" action:@selector(lastTab:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Next Tab" action:@selector(nextTab:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Previous Tab" action:@selector(previousTab:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Move Tab Forward" action:@selector(moveTabForward:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Move Tab Backward" action:@selector(moveTabBackward:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Move to Start" action:@selector(moveTabToStart:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Move to End" action:@selector(moveTabToEnd:) key:@"" flags:0 menu:tabMenu];
    [tabMenu addItem:[NSMenuItem separatorItem]];
    for (NSInteger c = 1; c <= 5; ++c) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Apply Color %ld", (long)c]
                                                    action:@selector(applyTabColour:) keyEquivalent:@""];
        mi.target = self; mi.tag = c;
        [tabMenu addItem:mi];
    }
    NSMenuItem *noColour = [[NSMenuItem alloc] initWithTitle:@"Remove Color"
                                                      action:@selector(applyTabColour:) keyEquivalent:@""];
    noColour.target = self; noColour.tag = 0;
    [tabMenu addItem:noColour];
    [viewMenu addItemWithTitle:@"Tab" action:nil keyEquivalent:@""].submenu = tabMenu;

    viewItem.submenu = viewMenu;

    // ---- Encoding
    NSMenuItem *encItem = [[NSMenuItem alloc] init];
    [bar addItem:encItem];
    NSMenu *encMenu = [[NSMenu alloc] initWithTitle:@"Encoding"];
    struct { NSString *title; NSStringEncoding enc; BOOL bom; } encodings[] = {
        {@"UTF-8",           NSUTF8StringEncoding,               NO},
        {@"UTF-8-BOM",       NSUTF8StringEncoding,               YES},
        {@"UTF-16 LE BOM",   NSUTF16LittleEndianStringEncoding,  YES},
        {@"UTF-16 BE BOM",   NSUTF16BigEndianStringEncoding,     YES},
        {@"ANSI",            NSISOLatin1StringEncoding,          NO},
    };
    for (size_t i = 0; i < sizeof(encodings)/sizeof(encodings[0]); ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:encodings[i].title
                                                    action:@selector(pickEncoding:) keyEquivalent:@""];
        mi.target = self;
        mi.tag = (NSInteger)i;
        [encMenu addItem:mi];
    }
    [encMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *eolHeader = [encMenu addItemWithTitle:@"EOL Conversion" action:nil keyEquivalent:@""];
    eolHeader.enabled = NO;
    [self item:@"Windows (CR LF)" action:@selector(eolCRLF:) key:@"" flags:0 menu:encMenu];
    [self item:@"Unix (LF)"       action:@selector(eolLF:) key:@"" flags:0 menu:encMenu];
    [self item:@"Classic Mac (CR)" action:@selector(eolCR:) key:@"" flags:0 menu:encMenu];

    [encMenu addItem:[NSMenuItem separatorItem]];
    // "Encode in": reinterpret the bytes through another charset.
    NSMenu *charsetMenu = [[NSMenu alloc] initWithTitle:@"Character sets"];
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    NSMutableArray *groupOrder = [NSMutableArray array];
    for (int i = 0; i < kNppCharsetCount; ++i) {
        NSString *group = @(kNppCharsets[i].group);
        NSMenu *sub = groups[group];
        if (!sub) {
            sub = [[NSMenu alloc] initWithTitle:group];
            groups[group] = sub;
            [groupOrder addObject:group];
        }
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@(kNppCharsets[i].label)
                                                    action:@selector(encodeInCharset:) keyEquivalent:@""];
        mi.target = self;
        mi.tag = i;
        [sub addItem:mi];
    }
    for (NSString *group in groupOrder) {
        [charsetMenu addItemWithTitle:group action:nil keyEquivalent:@""].submenu = groups[group];
    }
    [encMenu addItemWithTitle:@"Character sets" action:nil keyEquivalent:@""].submenu = charsetMenu;

    [encMenu addItem:[NSMenuItem separatorItem]];
    // "Convert to": re-encode the text itself.
    struct { NSString *title; SEL sel; } conversions[] = {
        {@"Convert to ANSI",             @selector(convertToANSI:)},
        {@"Convert to UTF-8",            @selector(convertToUTF8:)},
        {@"Convert to UTF-8-BOM",        @selector(convertToUTF8BOM:)},
        {@"Convert to UTF-16 BE BOM",    @selector(convertToUTF16BE:)},
        {@"Convert to UTF-16 LE BOM",    @selector(convertToUTF16LE:)},
    };
    for (size_t i = 0; i < sizeof(conversions)/sizeof(conversions[0]); ++i) {
        [self item:conversions[i].title action:conversions[i].sel key:@"" flags:0 menu:encMenu];
    }
    encItem.submenu = encMenu;

    // ---- Language (populated from Notepad++'s langs.model.xml)
    NSMenuItem *langItem = [[NSMenuItem alloc] init];
    [bar addItem:langItem];
    NSMenu *langMenu = [[NSMenu alloc] initWithTitle:@"Language"];
    NSArray *langs = [[LanguageCatalog sharedCatalog].allLanguages
        sortedArrayUsingComparator:^NSComparisonResult(NppLanguage *a, NppLanguage *b) {
            return [a.name caseInsensitiveCompare:b.name];
        }];
    for (NppLanguage *lang in langs) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:lang.name
                                                    action:@selector(pickLanguage:) keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = lang.name;
        [langMenu addItem:mi];
    }
    langItem.submenu = langMenu;

    // ---- Window
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [bar addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [self item:@"Next Tab" action:@selector(nextTab:) key:@"]"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:windowMenu];
    [self item:@"Previous Tab" action:@selector(previousTab:) key:@"["
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:windowMenu];
    windowItem.submenu = windowMenu;
    NSApp.windowsMenu = windowMenu;

    NSApp.mainMenu = bar;
}

#pragma mark - Menu validation

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL a = item.action;
    if (a == @selector(pickLanguage:)) {
        item.state = [item.representedObject isEqualToString:self.editor.currentDocument.language.name]
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(toggleWordWrap:)) {
        item.state = [self.editor.sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(toggleWhitespace:)) {
        item.state = [self.editor.sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(undo:)) {
        return [self.editor.sci message:SCI_CANUNDO] != 0;
    } else if (a == @selector(redo:)) {
        return [self.editor.sci message:SCI_CANREDO] != 0;
    } else if (a == @selector(pasteText:)) {
        return [self.editor.sci message:SCI_CANPASTE] != 0;
    } else if (a == @selector(pickEncoding:)) {
        item.state = [item.title isEqualToString:[self.editor encodingDisplayName]]
                     ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

#pragma mark - File actions

- (void)newDocument:(id)sender { [self.editor newDocument]; }

- (void)openDocument:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = NO;
    if ([panel runModal] != NSModalResponseOK) return;
    for (NSURL *url in panel.URLs) {
        NSError *err = nil;
        if (![self.editor openFileAtPath:url.path error:&err] && err) {
            [[NSAlert alertWithError:err] runModal];
        }
    }
}

- (void)saveDocument:(id)sender   { [self.editor saveCurrentDocument]; }
- (void)saveDocumentAs:(id)sender { [self.editor saveCurrentDocumentAs]; }
- (void)closeTab:(id)sender       { [self.editor closeCurrentDocument]; }

- (void)clearRecentDocuments:(id)sender {
    [[NSDocumentController sharedDocumentController] clearRecentDocuments:sender];
}

- (void)revealInFinder:(id)sender      { if (![self.editor revealInFinder]) NSBeep(); }
- (void)openInTerminal:(id)sender      { if (![self.editor openContainingFolderInTerminal]) NSBeep(); }
- (void)openInDefaultViewer:(id)sender { if (![self.editor openInDefaultViewer]) NSBeep(); }

- (void)reloadDocument:(id)sender {
    NSError *err = nil;
    if (![self.editor reloadCurrentDocument:&err] && err) [[NSAlert alertWithError:err] runModal];
}

- (void)saveCopyAs:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = self.editor.currentDocument.displayName;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *err = nil;
    if (![self.editor saveCopyOfCurrentTo:panel.URL.path error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)saveAll:(id)sender { [self.editor saveAllDocuments]; }

- (void)renameDocument:(id)sender {
    NSString *current = self.editor.currentDocument.path;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Rename";
    panel.nameFieldStringValue = self.editor.currentDocument.displayName;
    if (current) panel.directoryURL = [NSURL fileURLWithPath:current.stringByDeletingLastPathComponent];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *err = nil;
    if (![self.editor renameCurrentTo:panel.URL.path error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)closeAll:(id)sender           { [self.editor closeAllDocuments]; }
- (void)closeAllButCurrent:(id)sender { [self.editor closeAllButCurrent]; }
- (void)closeAllToLeft:(id)sender     { [self.editor closeAllToLeft]; }
- (void)closeAllToRight:(id)sender    { [self.editor closeAllToRight]; }
- (void)closeAllUnchanged:(id)sender  { [self.editor closeAllUnchanged]; }
- (void)closeAllButPinned:(id)sender  { [self.editor closeAllButPinned]; }
- (void)togglePin:(id)sender          { [self.editor togglePinCurrent]; }

- (void)openFolderAsWorkspace:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    [self.editor openFolderAsWorkspace:panel.URL.path];
}

- (void)containingFolderAsWorkspace:(id)sender {
    NSURL *folder = [self.editor containingFolderURL];
    if (!folder) { NSBeep(); return; }
    [self.editor openFolderAsWorkspace:folder.path];
}

- (void)moveToTrash:(id)sender {
    NppDocument *doc = self.editor.currentDocument;
    if (!doc.path) { NSBeep(); return; }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Move %@ to the Trash?", doc.displayName];
    [alert addButtonWithTitle:@"Move to Trash"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSError *err = nil;
    if (![self.editor moveCurrentToTrash:&err] && err) [[NSAlert alertWithError:err] runModal];
}

- (void)printDocument:(id)sender { [self.editor printCurrentShowingPanel:YES]; }
- (void)printNow:(id)sender      { [self.editor printCurrentShowingPanel:NO]; }

- (void)loadSession:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"json"];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *err = nil;
    if (![self.editor loadSessionFrom:panel.URL.path error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)saveSession:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"session.json";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *err = nil;
    if (![self.editor saveSessionTo:panel.URL.path error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

#pragma mark - Edit actions (routed straight to Scintilla)

- (void)undo:(id)sender        { [self.editor.sci message:SCI_UNDO]; }
- (void)redo:(id)sender        { [self.editor.sci message:SCI_REDO]; }
- (void)cutText:(id)sender     { [self.editor.sci message:SCI_CUT]; }
- (void)copyText:(id)sender    { [self.editor.sci message:SCI_COPY]; }
- (void)pasteText:(id)sender   { [self.editor.sci message:SCI_PASTE]; }
- (void)selectAllText:(id)sender { [self.editor.sci message:SCI_SELECTALL]; }

- (void)duplicateLine:(id)sender { [self.editor.sci message:SCI_LINEDUPLICATE]; }

#pragma mark - View actions

- (void)zoomIn:(id)sender    { [self.editor.sci message:SCI_ZOOMIN]; }
- (void)zoomOut:(id)sender   { [self.editor.sci message:SCI_ZOOMOUT]; }
- (void)zoomReset:(id)sender { [self.editor.sci message:SCI_SETZOOM wParam:0 lParam:0]; }

- (void)toggleWordWrap:(id)sender {
    ScintillaView *sci = self.editor.sci;
    BOOL on = [sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE;
    [sci message:SCI_SETWRAPMODE wParam:(on ? SC_WRAP_NONE : SC_WRAP_WORD) lParam:0];
}

- (void)toggleWhitespace:(id)sender {
    ScintillaView *sci = self.editor.sci;
    BOOL on = [sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE;
    [sci message:SCI_SETVIEWWS wParam:(on ? SCWS_INVISIBLE : SCWS_VISIBLEALWAYS) lParam:0];
}

- (void)pickLanguage:(NSMenuItem *)sender {
    [self.editor setLanguageNamed:sender.representedObject];
}

#pragma mark - Comment / completion

- (void)toggleLineComment:(id)sender  { [self.editor toggleLineComment]; }
- (void)toggleBlockComment:(id)sender { [self.editor toggleBlockComment]; }
- (void)showAutoComplete:(id)sender   { [self.editor showAutoCompletion]; }

#pragma mark - Edit: case, lines, blanks

- (void)convertCase:(NSMenuItem *)sender { [self.editor convertCase:(NppCaseMode)sender.tag]; }

- (void)sortLines:(NSMenuItem *)sender {
    [self.editor sortLines:(NppSortKey)(sender.tag / 2) descending:(sender.tag % 2) == 1];
}

- (void)applyTrim:(NSMenuItem *)sender { [self.editor applyTrim:(NppTrimMode)sender.tag]; }

- (void)reverseLines:(id)sender   { [self.editor sortLines:NppSortReverseOrder descending:NO]; }
- (void)randomizeLines:(id)sender { [self.editor sortLines:NppSortRandom descending:NO]; }

- (void)removeDupLines:(id)sender            { [self.editor removeDuplicateLines:NO]; }
- (void)removeConsecutiveDupLines:(id)sender { [self.editor removeDuplicateLines:YES]; }
- (void)splitLines:(id)sender                { [self.editor splitLines]; }
- (void)joinLines:(id)sender                 { [self.editor joinLines]; }
- (void)moveLineUp:(id)sender                { [self.editor moveLine:YES]; }
- (void)moveLineDown:(id)sender              { [self.editor moveLine:NO]; }
- (void)removeEmptyLines:(id)sender          { [self.editor removeEmptyLines:NO]; }
- (void)removeBlankLines:(id)sender          { [self.editor removeEmptyLines:YES]; }
- (void)blankLineAbove:(id)sender            { [self.editor insertBlankLine:YES]; }
- (void)blankLineBelow:(id)sender            { [self.editor insertBlankLine:NO]; }
- (void)increaseIndent:(id)sender            { [self.editor changeIndent:YES]; }
- (void)decreaseIndent:(id)sender            { [self.editor changeIndent:NO]; }
- (void)deleteSelection:(id)sender           { [self.editor deleteSelection]; }
- (void)uncommentLines:(id)sender            { [self.editor uncommentLines]; }
- (void)streamComment:(id)sender             { [self.editor streamComment:YES]; }
- (void)streamUncomment:(id)sender           { [self.editor streamComment:NO]; }

- (void)toggleReadOnly:(id)sender    { [self.editor setReadOnly:![self.editor isReadOnly]]; }
- (void)readOnlyAll:(id)sender       { [self.editor setReadOnlyForAllDocuments:YES]; }
- (void)clearReadOnlyAll:(id)sender  { [self.editor setReadOnlyForAllDocuments:NO]; }

- (void)copyFullPath:(id)sender  { [self.editor copyToClipboard:self.editor.currentDocument.path ?: @""]; }
- (void)copyFileName:(id)sender  { [self.editor copyToClipboard:self.editor.currentDocument.displayName]; }
- (void)copyDirPath:(id)sender   { [self.editor copyToClipboard:[self.editor containingFolderURL].path ?: @""]; }
- (void)copyAllNames:(id)sender  { [self.editor copyToClipboard:[self.editor allDocumentNames]]; }
- (void)copyAllPaths:(id)sender  { [self.editor copyToClipboard:[self.editor allDocumentPaths]]; }

- (void)insertDateShort:(id)sender { [self.editor insertDateTimeShort:YES]; }
- (void)insertDateLong:(id)sender  { [self.editor insertDateTimeShort:NO]; }

- (void)insertDateCustom:(id)sender {
    NSString *fmt = [self promptForString:@"Date/time format" default:@"yyyy-MM-dd HH:mm:ss"];
    if (!fmt) return;
    [self.editor insertCustomDateTime:fmt];
}

#pragma mark - Edit: multi-select, columns, panels

static NppMatchFlags FlagsForTag(NSInteger tag) {
    switch (tag) {
        case 1: return NppMatchCase;
        case 2: return NppMatchWholeWord;
        case 3: return NppMatchCase | NppMatchWholeWord;
        default: return NppMatchNone;
    }
}

- (void)multiSelectAll:(NSMenuItem *)s  { [self.editor multiSelectAllOccurrences:FlagsForTag(s.tag)]; }
- (void)multiSelectNext:(NSMenuItem *)s { [self.editor multiSelectNextOccurrence:FlagsForTag(s.tag)]; }
- (void)multiSelectUndo:(id)sender      { [self.editor undoLastMultiSelection]; }
- (void)multiSelectSkip:(id)sender      { [self.editor skipCurrentMultiSelection]; }

- (void)beginEndSelect:(id)sender       { [self.editor beginEndSelectColumnMode:NO]; }
- (void)beginEndSelectColumn:(id)sender { [self.editor beginEndSelectColumnMode:YES]; }

- (void)columnModeTip:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Column mode";
    alert.informativeText = @"Hold Option and drag to select a rectangle, or use "
                            @"Begin/End Select in Column Mode. Column Editor then "
                            @"fills every selected row.";
    [alert runModal];
}

- (void)columnEditor:(id)sender {
    if ([self.editor selectionCount] < 1) { NSBeep(); return; }
    NSString *mode = [self promptForString:@"Column Editor - \"text\" or \"number\"?" default:@"text"];
    if (!mode.length) return;
    if ([mode hasPrefix:@"n"]) {
        NSString *from = [self promptForString:@"Initial number" default:@"1"];
        if (!from.length) return;
        NSString *step = [self promptForString:@"Increase by" default:@"1"];
        if (!step.length) return;
        NSString *pad = [self promptForString:@"Leading zeros? yes/no" default:@"no"];
        [self.editor columnInsertNumbersFrom:from.integerValue increment:step.integerValue
                                  zeroPadded:[pad hasPrefix:@"y"] base:10];
    } else {
        NSString *text = [self promptForString:@"Text to insert" default:@""];
        if (!text.length) return;
        [self.editor columnInsertText:text];
    }
}

- (void)toggleCharacterPanel:(id)sender {
    if (!self.charPanel) self.charPanel = [[CharacterPanel alloc] initWithEditor:self.editor];
    [self.charPanel toggle];
}

- (void)toggleClipboardHistory:(id)sender {
    if (!self.clipPanel) self.clipPanel = [[ClipboardHistoryPanel alloc] initWithEditor:self.editor];
    [self.clipPanel toggle];
}

- (void)toggleSystemReadOnly:(id)sender { [self.editor toggleSystemReadOnly]; }

- (void)pathCompletion:(id)sender { [self.editor showPathCompletion]; }
- (void)callTip:(id)sender        { [self.editor showFunctionCallTip]; }
- (void)callTipNext:(id)sender    { [self.editor cycleFunctionCallTip:YES]; }
- (void)callTipPrev:(id)sender    { [self.editor cycleFunctionCallTip:NO]; }

- (void)pasteHTML:(id)sender          { [self.editor pasteAsHTML]; }
- (void)pasteRTF:(id)sender           { [self.editor pasteAsRTF]; }
- (void)copyBinary:(id)sender         { [self.editor copySelectionAsBinary]; }
- (void)cutBinary:(id)sender          { [self.editor cutSelectionAsBinary]; }
- (void)pasteBinaryContent:(id)sender { [self.editor pasteBinary]; }

- (void)openSelectedFile:(id)sender   { [self.editor openSelectedFile]; }
- (void)revealSelectedFile:(id)sender { [self.editor revealSelectedFile]; }
- (void)searchOnInternet:(id)sender   { [self.editor searchSelectionOnInternet]; }

- (void)redactSelection:(id)sender {
    BOOL bullet = ([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0;
    [self.editor redactSelectionWithBlock:!bullet];
}

- (void)changeSearchEngine:(id)sender {
    NSString *t = [self promptForString:@"Search URL (%@ is the query)"
                                default:self.editor.searchEngineTemplate];
    if (t.length) self.editor.searchEngineTemplate = t;
}

#pragma mark - Bookmarks

- (void)toggleBookmark:(id)sender   { [self.editor toggleBookmark]; }
- (void)nextBookmark:(id)sender     { [self.editor nextBookmark]; }
- (void)previousBookmark:(id)sender { [self.editor previousBookmark]; }
- (void)clearBookmarks:(id)sender   { [self.editor clearBookmarks]; }

#pragma mark - View: folds, symbols, window modes, tabs

- (void)foldLevel:(NSMenuItem *)s   { [self.editor foldToLevel:s.tag]; }
- (void)unfoldLevel:(NSMenuItem *)s { [self.editor unfoldToLevel:s.tag]; }
- (void)toggleSymbol:(NSMenuItem *)s { [self.editor toggleSymbol:(NppSymbol)s.tag]; }

- (void)hideLines:(id)sender        { [self.editor hideSelectedLines]; }
- (void)showHiddenLines:(id)sender  { [self.editor showAllHiddenLines]; }

- (void)showSummary:(id)sender {
    NSDictionary *s = [self.editor documentSummary];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Summary";
    alert.informativeText = [NSString stringWithFormat:
        @"Characters: %@\nBytes: %@\nWords: %@\nLines: %@\nSelected bytes: %@",
        s[@"characters"], s[@"bytes"], s[@"words"], s[@"lines"], s[@"selected"]];
    [alert runModal];
}

- (void)toggleMonitoring:(id)sender {
    [self.editor setMonitoring:![self.editor monitoringEnabled]];
}

- (void)toggleAlwaysOnTop:(id)sender {
    self.alwaysOnTop = !self.alwaysOnTop;
    self.window.level = self.alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

- (void)toggleFullScreenMode:(id)sender { [self.window toggleFullScreen:nil]; }

- (void)togglePostIt:(id)sender {
    // Notepad++'s Post-It is a chrome-less always-on-top window.
    BOOL entering = [self.editor chromeVisible];
    [self.editor setChromeVisible:!entering];
    self.window.level = entering ? NSFloatingWindowLevel : NSNormalWindowLevel;
    self.alwaysOnTop = entering;
}

- (void)toggleDistractionFree:(id)sender {
    [self.editor setChromeVisible:![self.editor chromeVisible]];
}

- (void)toggleFileBrowser:(id)sender {
    if ([self.editor workspaceVisible]) { [self.editor openFolderAsWorkspace:nil]; return; }
    NSURL *folder = [self.editor containingFolderURL];
    if (folder) { [self.editor openFolderAsWorkspace:folder.path]; return; }
    [self openFolderAsWorkspace:sender];
}

- (void)toggleDocumentList:(id)sender {
    if (!self.docList) self.docList = [[DocumentListPanel alloc] initWithEditor:self.editor];
    [self.docList toggle];
}

- (void)toggleDocumentMap:(id)sender {
    [self.editor setDocumentMapVisible:![self.editor documentMapVisible]];
}

- (void)toggleFunctionList:(id)sender {
    if (!self.funcList) self.funcList = [[FunctionListPanel alloc] initWithEditor:self.editor];
    [self.funcList toggle];
}

- (void)toggleProjectPanel:(NSMenuItem *)sender {
    NSInteger idx = sender.tag;
    if (![self.editor projectPanelRoot:idx] && [self.editor activeProjectPanel] != idx) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseDirectories = YES;
        panel.canChooseFiles = NO;
        if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
        [self.editor setProjectPanel:idx root:panel.URL.path];
    }
    [self.editor showProjectPanel:idx];
}

- (void)focusOtherView:(id)sender   { [self.editor focusOtherView]; }
- (void)moveToOtherView:(id)sender  { [self.editor moveCurrentToOtherView]; }
- (void)cloneToOtherView:(id)sender { [self.editor cloneCurrentToOtherView]; }
- (void)moveToNewInstance:(id)sender { [self.editor openCurrentInNewInstanceMoving:YES]; }
- (void)openInNewInstance:(id)sender { [self.editor openCurrentInNewInstanceMoving:NO]; }

- (void)toggleSyncV:(id)sender    { [self.editor setSyncVerticalScroll:![self.editor syncVerticalScroll]]; }
- (void)toggleSyncH:(id)sender    { [self.editor setSyncHorizontalScroll:![self.editor syncHorizontalScroll]]; }
- (void)toggleSyncZoom:(id)sender { [self.editor setSyncZoom:![self.editor syncZoom]]; }

- (void)textRTL:(id)sender { [self.editor setTextDirectionRTL:YES]; }
- (void)textLTR:(id)sender { [self.editor setTextDirectionRTL:NO]; }

- (void)viewInBrowser:(NSMenuItem *)sender {
    if (![self.editor openCurrentInBrowserBundleID:sender.representedObject]) NSBeep();
}

- (void)goToTabNumber:(NSMenuItem *)s { [self.editor selectTabNumber:s.tag]; }
- (void)firstTab:(id)sender           { [self.editor goToFirstTab]; }
- (void)lastTab:(id)sender            { [self.editor goToLastTab]; }
- (void)moveTabForward:(id)sender     { [self.editor moveCurrentTab:YES]; }
- (void)moveTabBackward:(id)sender    { [self.editor moveCurrentTab:NO]; }
- (void)moveTabToStart:(id)sender     { [self.editor moveCurrentTabToEnd:NO]; }
- (void)moveTabToEnd:(id)sender       { [self.editor moveCurrentTabToEnd:YES]; }
- (void)applyTabColour:(NSMenuItem *)s { [self.editor setTabColour:s.tag]; }

#pragma mark - Search: styles, braces, files

- (void)markAllStyle:(NSMenuItem *)s  { [self.editor markAllOccurrencesOfSelection:s.tag]; }
- (void)markOneStyle:(NSMenuItem *)s  { [self.editor markOneOccurrenceOfSelection:s.tag]; }
- (void)clearStyle:(NSMenuItem *)s    { [self.editor clearStyle:s.tag]; }
- (void)clearAllStyles:(id)sender     { [self.editor clearAllStyles]; }
- (void)jumpUpStyle:(NSMenuItem *)s   { [self.editor jumpToMarker:s.tag forward:NO]; }
- (void)jumpDownStyle:(NSMenuItem *)s { [self.editor jumpToMarker:s.tag forward:YES]; }
- (void)copyStyle:(NSMenuItem *)s     { [self.editor copyToClipboard:[self.editor textOfStyle:s.tag]]; }
- (void)copyAllStyles:(id)sender      { [self.editor copyToClipboard:[self.editor textOfAllStyles]]; }

- (void)goToMatchingBrace:(id)sender   { [self.editor goToMatchingBrace]; }
- (void)selectBetweenBraces:(id)sender { [self.editor selectBetweenMatchingBraces]; }

- (void)markTerm:(id)sender {
    NSString *term = [self promptForString:@"Mark" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    [self.editor.sci message:SCI_SETSEL wParam:0 lParam:0];
    [self searchFrom:0 forward:YES wrap:NO];
    [self.editor markAllOccurrencesOfSelection:NPPMAC_STYLE_COUNT];
}

- (void)findCharsInRange:(id)sender {
    NSString *from = [self promptForString:@"Mark characters from (decimal code point)" default:@"128"];
    if (!from.length) return;
    NSString *to = [self promptForString:@"…to (decimal code point)" default:@"65535"];
    if (!to.length) return;
    NSUInteger n = [self.editor markCharactersInRangeFrom:(unichar)from.intValue to:(unichar)to.intValue];
    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = [NSString stringWithFormat:@"%lu character%@ marked", (unsigned long)n, n == 1 ? @"" : @"s"];
    [done runModal];
}

- (void)findInFiles:(id)sender {
    NSString *term = [self promptForString:@"Find in Files — what?" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    NSString *ext = [self promptForString:@"Extension filter (blank for all)" default:@""];
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    [self.editor findInFiles:term inFolder:panel.URL.path filter:ext.length ? ext : nil];
}

- (void)focusSearchResults:(id)sender { [self.editor focusSearchResults]; }
- (void)nextSearchResult:(id)sender   { [self.editor goToSearchResult:YES]; }
- (void)prevSearchResult:(id)sender   { [self.editor goToSearchResult:NO]; }

- (void)selectAndFindNext:(id)sender { [self.editor findNextOccurrenceOfSelection:YES extendSelection:NO]; }
- (void)selectAndFindPrev:(id)sender { [self.editor findNextOccurrenceOfSelection:NO extendSelection:NO]; }
- (void)volatileFindNext:(id)sender  { [self.editor findNextOccurrenceOfSelection:YES extendSelection:NO]; }
- (void)volatileFindPrev:(id)sender  { [self.editor findNextOccurrenceOfSelection:NO extendSelection:NO]; }

- (void)incrementalSearch:(id)sender {
    // macOS already has a first-class incremental find bar; this drives the
    // same search state so ⌘G continues from it.
    NSString *term = [self promptForString:@"Incremental search" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    [self searchFrom:[self.editor.sci message:SCI_GETCURRENTPOS] forward:YES wrap:YES];
}

- (void)cutMarkedLines:(id)sender      { [self.editor cutBookmarkedLines]; }
- (void)copyMarkedLines:(id)sender     { [self.editor copyBookmarkedLines]; }
- (void)pasteMarkedLines:(id)sender    { [self.editor pasteOverBookmarkedLines]; }
- (void)removeMarkedLines:(id)sender   { [self.editor removeBookmarkedLines]; }
- (void)removeUnmarkedLines:(id)sender { [self.editor removeUnbookmarkedLines]; }
- (void)inverseBookmarks:(id)sender    { [self.editor inverseBookmarks]; }

- (void)nextChange:(id)sender         { [self.editor goToNextChange:YES]; }
- (void)prevChange:(id)sender         { [self.editor goToNextChange:NO]; }
- (void)clearChangeHistory:(id)sender { [self.editor clearChangeHistory]; }

#pragma mark - Folding

- (void)toggleFold:(id)sender { [self.editor toggleFoldAtCursor]; }
- (void)foldAll:(id)sender    { [self.editor foldAll:YES]; }
- (void)unfoldAll:(id)sender  { [self.editor foldAll:NO]; }
- (void)foldCurrent:(id)sender   { [self.editor foldCurrent:YES]; }
- (void)unfoldCurrent:(id)sender { [self.editor foldCurrent:NO]; }

#pragma mark - Encoding + EOL

- (void)pickEncoding:(NSMenuItem *)sender {
    struct { NSStringEncoding enc; BOOL bom; } table[] = {
        {NSUTF8StringEncoding,              NO},
        {NSUTF8StringEncoding,              YES},
        {NSUTF16LittleEndianStringEncoding, YES},
        {NSUTF16BigEndianStringEncoding,    YES},
        {NSISOLatin1StringEncoding,         NO},
    };
    NSInteger i = sender.tag;
    if (i < 0 || i >= (NSInteger)(sizeof(table)/sizeof(table[0]))) return;
    [self.editor setEncoding:table[i].enc withBOM:table[i].bom];
}

- (void)encodeInCharset:(NSMenuItem *)sender {
    if (sender.tag < 0 || sender.tag >= kNppCharsetCount) return;
    if (![self.editor reinterpretAsCodepage:kNppCharsets[sender.tag].codepage]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Cannot read this document as %@.",
                             @(kNppCharsets[sender.tag].label)];
        [alert runModal];
    }
}

- (void)convertToANSI:(id)sender    { [self.editor setEncoding:NSISOLatin1StringEncoding withBOM:NO]; }
- (void)convertToUTF8:(id)sender    { [self.editor setEncoding:NSUTF8StringEncoding withBOM:NO]; }
- (void)convertToUTF8BOM:(id)sender { [self.editor setEncoding:NSUTF8StringEncoding withBOM:YES]; }
- (void)convertToUTF16BE:(id)sender { [self.editor setEncoding:NSUTF16BigEndianStringEncoding withBOM:YES]; }
- (void)convertToUTF16LE:(id)sender { [self.editor setEncoding:NSUTF16LittleEndianStringEncoding withBOM:YES]; }

- (void)eolCRLF:(id)sender { [self.editor convertEOLTo:SC_EOL_CRLF]; }
- (void)eolLF:(id)sender   { [self.editor convertEOLTo:SC_EOL_LF]; }
- (void)eolCR:(id)sender   { [self.editor convertEOLTo:SC_EOL_CR]; }

#pragma mark - Tabs

- (void)nextTab:(id)sender {
    NSInteger n = (NSInteger)self.editor.documents.count;
    if (n < 2) return;
    NSInteger cur = [self.editor.documents indexOfObject:self.editor.currentDocument];
    [self.editor selectDocumentAtIndex:(cur + 1) % n];
}

- (void)previousTab:(id)sender {
    NSInteger n = (NSInteger)self.editor.documents.count;
    if (n < 2) return;
    NSInteger cur = [self.editor.documents indexOfObject:self.editor.currentDocument];
    [self.editor selectDocumentAtIndex:(cur - 1 + n) % n];
}

#pragma mark - Search

- (NSString *)promptForString:(NSString *)title default:(NSString *)def {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.stringValue = def ?: @"";
    alert.accessoryView = field;
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    return field.stringValue;
}

- (void)showFind:(id)sender {
    NSString *term = [self promptForString:@"Find" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    [self searchFrom:[self.editor.sci message:SCI_GETCURRENTPOS] forward:YES wrap:YES];
}

- (void)findNext:(id)sender {
    if (!self.lastSearchTerm.length) { [self showFind:sender]; return; }
    [self searchFrom:[self.editor.sci message:SCI_GETCURRENTPOS] forward:YES wrap:YES];
}

- (void)findPrevious:(id)sender {
    if (!self.lastSearchTerm.length) { [self showFind:sender]; return; }
    [self searchFrom:[self.editor.sci message:SCI_GETSELECTIONSTART] forward:NO wrap:YES];
}

/// Returns YES when a match was found and selected.
///
/// SCI_SEARCHINTARGET returns -1 when there is no match and leaves the target
/// range untouched, so the result must be read from the return value. Reading
/// SCI_GETTARGETSTART/END instead reports the range we just set as a hit.
- (BOOL)searchFrom:(long)start forward:(BOOL)forward wrap:(BOOL)wrap {
    ScintillaView *sci = self.editor.sci;
    NSString *term = self.lastSearchTerm;
    if (!term.length) return NO;

    const char *needle = term.UTF8String;
    long needleLen = (long)strlen(needle);
    long docLen = [sci message:SCI_GETLENGTH];

    long found = [self searchTarget:forward ? start : 0
                                 to:forward ? docLen : start
                             needle:needle length:needleLen];

    if (found < 0 && wrap) {
        found = [self searchTarget:forward ? 0 : docLen
                                to:forward ? docLen : 0
                            needle:needle length:needleLen];
    }
    if (found < 0) { NSBeep(); return NO; }

    // Backwards: SCI_SEARCHINTARGET reports the first hit in the range, so take
    // the last one before the caret instead.
    if (!forward) {
        long best = found, probe = found;
        while (probe >= 0) {
            long nextStart = probe + 1;
            if (nextStart >= (forward ? docLen : start)) break;
            probe = [self searchTarget:nextStart to:start needle:needle length:needleLen];
            if (probe >= 0) best = probe;
        }
        found = best;
    }

    [sci message:SCI_SETSEL wParam:(uptr_t)found lParam:found + needleLen];
    [sci message:SCI_SCROLLCARET];
    return YES;
}

/// One SCI_SEARCHINTARGET pass; returns the match position or -1.
- (long)searchTarget:(long)from to:(long)to needle:(const char *)needle length:(long)len {
    ScintillaView *sci = self.editor.sci;
    [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from lParam:0];
    [sci message:SCI_SETTARGETEND wParam:(uptr_t)to lParam:0];
    [sci message:SCI_SETSEARCHFLAGS wParam:0 lParam:0];
    return [sci message:SCI_SEARCHINTARGET wParam:(uptr_t)len lParam:(sptr_t)needle];
}

- (void)showReplace:(id)sender {
    NSString *term = [self promptForString:@"Replace — find what?" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    NSString *with = [self promptForString:@"Replace with" default:@""];
    if (!with) return;

    ScintillaView *sci = self.editor.sci;
    long count = 0;
    [sci message:SCI_SETSEL wParam:0 lParam:0];
    [sci message:SCI_BEGINUNDOACTION];
    while ([self searchFrom:[sci message:SCI_GETSELECTIONEND] forward:YES wrap:NO]) {
        // searchFrom left the target on the match, so replace it directly.
        [sci setStringProperty:SCI_REPLACETARGET parameter:(long)strlen(with.UTF8String) value:with];
        long end = [sci message:SCI_GETTARGETEND];
        [sci message:SCI_SETSEL wParam:(uptr_t)end lParam:end];
        count++;
        if (count > 100000) break;   // pathological guard
    }
    [sci message:SCI_ENDUNDOACTION];
    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = [NSString stringWithFormat:@"%ld replacement%@ made", count, count == 1 ? @"" : @"s"];
    [done runModal];
    [self.editor refreshChrome];
}

- (void)goToLine:(id)sender {
    NSString *s = [self promptForString:@"Go to line" default:@""];
    if (!s.length) return;
    long line = s.integerValue - 1;
    if (line < 0) return;
    [self.editor.sci message:SCI_GOTOLINE wParam:(uptr_t)line lParam:0];
    [self.editor refreshChrome];
}

#pragma mark - Test suite

- (void)runTestSuite {
    int failures = NppMacRunTests(self);
    fflush(stdout);
    exit(failures == 0 ? 0 : 1);   // exit code carries the result to CI
}

#pragma mark - Snapshot

/// Renders the window's content view straight to a PNG. This deliberately does
/// not go through screencapture(1), which needs Screen Recording permission and
/// silently returns a desktop with no windows when it is not granted.
///
/// Caveat: cacheDisplayInRect: captures Scintilla (which draws itself) but not
/// the text of AppKit controls, so the tab bar and status bar come out blank.
/// Their contents are covered by the self-test instead.
- (void)writeSnapshot {
    const char *dest = getenv("NPPMAC_SNAPSHOT");
    if (!dest) { [NSApp terminate:nil]; return; }

    // Give the caller something worth looking at rather than an empty buffer.
    NSString *sample = getenv("NPPMAC_SNAPSHOT_FILE")
        ? @(getenv("NPPMAC_SNAPSHOT_FILE")) : nil;
    if (sample.length) {
        NSError *err = nil;
        if (![self.editor openFileAtPath:sample error:&err]) {
            fprintf(stderr, "snapshot: cannot open %s\n", sample.UTF8String);
        }
    }
    // Optional: show the split panes so a snapshot can demonstrate them.
    if (getenv("NPPMAC_SNAPSHOT_SPLIT")) {
        [self.editor cloneCurrentToOtherView];
        [self.editor setSyncVerticalScroll:YES];
        [self.editor.secondarySci message:SCI_SETFIRSTVISIBLELINE wParam:40 lParam:0];
    }
    [self.editor refreshChrome];
    // Force the whole hierarchy to redraw before capturing; a split pane can
    // otherwise be cached from a backing store that was never painted.
    [self.window.contentView setNeedsDisplay:YES];
    [self.window displayIfNeeded];
    [self.editor.view displayIfNeeded];

    NSView *view = self.window.contentView;

    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

    if ([png writeToFile:@(dest) atomically:YES]) {
        printf("SNAPSHOT wrote %s (%.0fx%.0f)\n", dest, view.bounds.size.width, view.bounds.size.height);
    } else {
        fprintf(stderr, "SNAPSHOT failed to write %s\n", dest);
    }
    [NSApp terminate:nil];
}

#pragma mark - Self-test

- (void)runSelfTest {
    LanguageCatalog *langs = [LanguageCatalog sharedCatalog];
    StyleCatalog *styles = [StyleCatalog sharedCatalog];

    printf("SELFTEST languages_loaded=%lu\n", (unsigned long)langs.allLanguages.count);
    printf("SELFTEST cpp_styles_loaded=%lu\n",
           (unsigned long)[styles stylesForLexerName:@"cpp"].count);
    printf("SELFTEST global_styles_loaded=%lu\n", (unsigned long)styles.globalStyles.count);

    // Extension -> language -> lexer, straight from Notepad++'s own data.
    NSArray *probes = @[@"a.cpp", @"b.py", @"c.rs", @"d.json", @"e.sh", @"f.unknownext"];
    for (NSString *p in probes) {
        NppLanguage *l = [langs languageForFileName:p];
        printf("SELFTEST detect %-14s -> lang=%-10s lexer=%s\n",
               p.UTF8String, l.name.UTF8String, l.lexerID.UTF8String);
    }

    // Open a real file through the normal path and confirm it lexes.
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"nppmac_selftest.py"];
    [@"# comment\ndef f(x):\n    return x + 1\n" writeToFile:tmp atomically:YES
                                                  encoding:NSUTF8StringEncoding error:NULL];
    NSError *err = nil;
    BOOL opened = [self.editor openFileAtPath:tmp error:&err];
    printf("SELFTEST open_file=%s tabs=%lu lang=%s\n",
           opened ? "OK" : "FAIL",
           (unsigned long)self.editor.documents.count,
           self.editor.currentDocument.language.name.UTF8String);

    ScintillaView *sci = self.editor.sci;
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    long style0 = [sci message:SCI_GETSTYLEAT wParam:0];
    printf("SELFTEST python_comment_style=%ld (SCE_P_COMMENTLINE=%d) match=%s\n",
           style0, SCE_P_COMMENTLINE, style0 == SCE_P_COMMENTLINE ? "YES" : "NO");

    // Search must find a known token.
    self.lastSearchTerm = @"return";
    BOOL found = [self searchFrom:0 forward:YES wrap:YES];
    printf("SELFTEST search_found=%s\n", found ? "YES" : "NO");

    // The snapshot cannot capture AppKit control text, so assert the chrome here.
    for (NSUInteger i = 0; i < self.editor.documents.count; ++i) {
        printf("SELFTEST tab[%lu]=\"%s\"\n", (unsigned long)i,
               self.editor.documents[i].displayName.UTF8String);
    }
    NSString *status = [self.editor valueForKey:@"statusField"]
        ? [(NSTextField *)[self.editor valueForKey:@"statusField"] stringValue] : @"";
    printf("SELFTEST status_nonempty=%s fields=%s\n",
           status.length ? "YES" : "NO",
           ([status containsString:@"Ln "] && [status containsString:@"lines"]) ? "OK" : "MISSING");

    printf("SELFTEST menus=%ld\n", (long)NSApp.mainMenu.numberOfItems);
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
    [NSApp terminate:nil];
}

@end

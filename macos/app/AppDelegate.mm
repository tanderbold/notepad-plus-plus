#import "AppDelegate.h"
#import "EditorController.h"
#import "EditCommands.h"
#import "SearchCommands.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#import "Tests.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) EditorController *editor;
@property (nonatomic, copy) NSString *lastSearchTerm;
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
    [editMenu addItemWithTitle:@"Read-Only" action:nil keyEquivalent:@""].submenu = roMenu;

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

#pragma mark - Bookmarks

- (void)toggleBookmark:(id)sender   { [self.editor toggleBookmark]; }
- (void)nextBookmark:(id)sender     { [self.editor nextBookmark]; }
- (void)previousBookmark:(id)sender { [self.editor previousBookmark]; }
- (void)clearBookmarks:(id)sender   { [self.editor clearBookmarks]; }

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
    [self.editor refreshChrome];
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

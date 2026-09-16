#import "SettingsPanels.h"
#import "SettingsCommands.h"
#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#import "Toolbar.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"

#pragma mark - Preferences

@interface PreferencesWindow () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSMutableDictionary *controls;
/// Notepad++ lists its categories down the left and shows one page at a time;
/// this keeps the pages in that order, by the names it gives them.
@property (nonatomic, strong) NSMutableArray<NSString *> *pageNames;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *pages;
@property (nonatomic, strong) NSTableView *categories;
@property (nonatomic, strong) NSView *pageHost;
@property (nonatomic, strong) NSScrollView *pageScroller;
@end

@implementation PreferencesWindow

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _controls = [NSMutableDictionary dictionary];
    _pageNames = [NSMutableArray array];
    _pages = [NSMutableDictionary dictionary];

    NSRect frame = NSMakeRect(0, 0, 700, 560);
    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable |
                                                   NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Preferences";
    _panel.releasedWhenClosed = NO;

    // A plain NSView paints nothing, which leaves white behind the buttons and,
    // in dark mode, white labels on it. This follows the appearance instead.
    NSVisualEffectView *content = [[NSVisualEffectView alloc] initWithFrame:frame];
    content.material = NSVisualEffectMaterialWindowBackground;
    content.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    content.state = NSVisualEffectStateActive;

    // The category list, down the left as Notepad++ has it.
    NSScrollView *listScroller = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 52, 190, 508)];
    listScroller.hasVerticalScroller = YES;
    listScroller.autoresizingMask = NSViewHeightSizable;
    _categories = [[NSTableView alloc] initWithFrame:listScroller.bounds];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"page"];
    column.width = 170;
    [_categories addTableColumn:column];
    _categories.headerView = nil;
    _categories.dataSource = self;
    _categories.delegate = self;
    _categories.rowHeight = 22;
    listScroller.documentView = _categories;
    [content addSubview:listScroller];

    // The page itself, scrolling in case a page is taller than the window.
    _pageScroller = [[NSScrollView alloc] initWithFrame:NSMakeRect(190, 52, 510, 508)];
    _pageScroller.hasVerticalScroller = YES;
    // The scroller paints the standard background. Leaving it transparent shows
    // white behind the page, and in dark mode the labels are white too.
    _pageScroller.drawsBackground = YES;
    _pageScroller.backgroundColor = NSColor.windowBackgroundColor;
    _pageScroller.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:_pageScroller];

    [self buildPages];

    NSButton *apply = [[NSButton alloc] initWithFrame:NSMakeRect(580, 12, 100, 28)];
    apply.title = @"Apply";
    apply.bezelStyle = NSBezelStyleRounded;
    apply.target = self;
    apply.action = @selector(apply:);
    apply.autoresizingMask = NSViewMinXMargin;
    [content addSubview:apply];

    NSButton *reset = [[NSButton alloc] initWithFrame:NSMakeRect(470, 12, 100, 28)];
    reset.title = @"Reset";
    reset.bezelStyle = NSBezelStyleRounded;
    reset.target = self;
    reset.action = @selector(resetAll:);
    reset.autoresizingMask = NSViewMinXMargin;
    [content addSubview:reset];

    _panel.contentView = content;
    [_categories selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self showPageAtIndex:0];
    return self;
}

#pragma mark - Pages

/// Starts a page and returns the y to begin laying out at. Pages are tall
/// enough for their contents; the scroller deals with the rest.
- (CGFloat)beginPage:(NSString *)name {
    NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 520)];
    [self.pageNames addObject:name];
    self.pages[name] = page;
    return 480;
}

- (NSView *)page:(NSString *)name { return self.pages[name]; }

/// Sizes the page to what was actually put on it, so short pages do not scroll.
- (void)endPage:(NSString *)name atY:(CGFloat)y {
    NSView *page = self.pages[name];
    CGFloat used = 500 - y;
    CGFloat height = MAX((CGFloat)500, used + 40);
    NSRect frame = page.frame;
    // Everything was laid out from the top of a 520-tall page, so when the page
    // grows the contents have to move with it.
    CGFloat shift = height - NSHeight(frame);
    if (shift != 0) {
        for (NSView *child in page.subviews) {
            NSRect r = child.frame;
            r.origin.y += shift;
            child.frame = r;
        }
    }
    frame.size.height = height;
    page.frame = frame;
}

- (void)showPageAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.pageNames.count) return;
    NSView *page = self.pages[self.pageNames[(NSUInteger)index]];
    self.pageScroller.documentView = page;
    [self.pageScroller.contentView scrollToPoint:
        NSMakePoint(0, MAX((CGFloat)0, NSHeight(page.frame) - NSHeight(self.pageScroller.bounds)))];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.pageNames.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column
            row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.pageNames.count) return @"";
    return self.pageNames[(NSUInteger)row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self showPageAtIndex:self.categories.selectedRow];
}

/// Every page, with the names and the grouping Notepad++ uses.
- (void)buildPages {
    NppPreferences *p = [NppPreferences shared];
    NSView *v; CGFloat y;

    y = [self beginPage:@"General"]; v = [self page:@"General"];
    y = [self addCheckbox:@"Restore the previous session on launch" key:@"restoreSession"
                       on:p.restoreSession to:v atY:y];
    y = [self addCheckbox:@"Remember which panels were open" key:@"rememberPanelState"
                       on:p.rememberPanelState to:v atY:y];
    y = [self addPopup:@"Instances" key:@"multiInstanceMode"
                 items:@[@"Default (one instance)", @"Always a new instance",
                         @"A session per instance"]
              selected:p.multiInstanceMode to:v atY:y];
    [self endPage:@"General" atY:y];

    y = [self beginPage:@"Toolbar"]; v = [self page:@"Toolbar"];
    y = [self addCheckbox:@"Show the toolbar" key:@"showToolbar" on:p.showToolbar to:v atY:y];
    y = [self addPopup:@"Toolbar buttons" key:@"toolbarDisplayMode"
                 items:@[@"Icons only", @"Icons and labels", @"Labels only"]
              selected:p.toolbarDisplayMode to:v atY:y];
    y = [self addPopup:@"Toolbar size" key:@"toolbarIconSize" items:@[@"Regular", @"Small"]
              selected:p.toolbarIconSize to:v atY:y];
    [self endPage:@"Toolbar" atY:y];

    y = [self beginPage:@"Editing 1"]; v = [self page:@"Editing 1"];
    y = [self addField:@"Font" key:@"fontName" value:p.fontName to:v atY:y];
    y = [self addField:@"Font size" key:@"fontSize"
                  value:[@(p.fontSize) stringValue] to:v atY:y];
    y = [self addPopup:@"Caret width" key:@"caretWidth"
                 items:@[@"Hidden", @"1 pixel", @"2 pixels", @"3 pixels"]
              selected:p.caretWidth to:v atY:y];
    y = [self addField:@"Caret blink rate (ms, 0 steady)" key:@"caretBlinkRate"
                  value:[@(p.caretBlinkRate) stringValue] to:v atY:y];
    y = [self addPopup:@"Current line" key:@"currentLineHighlightMode"
                 items:@[@"Not marked", @"Background", @"Frame"]
              selected:p.currentLineHighlightMode to:v atY:y];
    y = [self addField:@"Frame width (1-6)" key:@"currentLineFrameWidth"
                  value:[@(p.currentLineFrameWidth) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Scroll beyond the last line" key:@"scrollBeyondLastLine"
                       on:p.scrollBeyondLastLine to:v atY:y];
    y = [self addCheckbox:@"Let the caret go past the end of a line" key:@"virtualSpace"
                       on:p.virtualSpace to:v atY:y];
    y = [self addCheckbox:@"Cut and Copy take the whole line when nothing is selected"
                      key:@"lineCopyCutWithoutSelection"
                       on:p.lineCopyCutWithoutSelection to:v atY:y];
    y = [self addCheckbox:@"Selected text can be dragged" key:@"selectedTextDragDrop"
                       on:p.selectedTextDragDrop to:v atY:y];
    y = [self addCheckbox:@"A right-click keeps the selection" key:@"rightClickKeepsSelection"
                       on:p.rightClickKeepsSelection to:v atY:y];
    [self endPage:@"Editing 1" atY:y];

    y = [self beginPage:@"Editing 2"]; v = [self page:@"Editing 2"];
    y = [self addCheckbox:@"Word wrap" key:@"wordWrap" on:p.wordWrap to:v atY:y];
    y = [self addPopup:@"Wrapped lines" key:@"lineWrapMethod"
                 items:@[@"Plain", @"Aligned with the line above", @"Indented a level further"]
              selected:p.lineWrapMethod to:v atY:y];
    y = [self addCheckbox:@"Show whitespace" key:@"showWhitespace"
                       on:p.showWhitespace to:v atY:y];
    y = [self addCheckbox:@"Show indent guides" key:@"showIndentGuides"
                       on:p.showIndentGuides to:v atY:y];
    [self endPage:@"Editing 2" atY:y];

    y = [self beginPage:@"Dark Mode"]; v = [self page:@"Dark Mode"];
    y = [self addPopup:@"Appearance" key:@"appearanceMode"
                 items:@[@"Follow the system", @"Light", @"Dark"]
              selected:p.appearanceMode to:v atY:y];
    NSArray *themes = [StyleCatalog availableThemeNames];
    y = [self addPopup:@"Light theme" key:@"lightThemeName" items:themes
              selected:[themes indexOfObject:p.lightThemeName ?: @"Default"] to:v atY:y];
    y = [self addPopup:@"Dark theme" key:@"darkThemeName" items:themes
              selected:[themes indexOfObject:p.darkThemeName ?: @"DarkModeDefault"] to:v atY:y];
    [self endPage:@"Dark Mode" atY:y];

    y = [self beginPage:@"Margins/Border/Edge"]; v = [self page:@"Margins/Border/Edge"];
    y = [self addCheckbox:@"Show the bookmark margin" key:@"bookmarkMarginShow"
                       on:p.bookmarkMarginShow to:v atY:y];
    y = [self addCheckbox:@"Show the fold margin" key:@"foldMarginShow"
                       on:p.foldMarginShow to:v atY:y];
    y = [self addField:@"Padding left (0-9)" key:@"paddingLeft"
                  value:[@(p.paddingLeft) stringValue] to:v atY:y];
    y = [self addField:@"Padding right (0-9)" key:@"paddingRight"
                  value:[@(p.paddingRight) stringValue] to:v atY:y];
    y = [self addPopup:@"Vertical edge" key:@"edgeMode"
                 items:@[@"None", @"A line", @"Background past the column"]
              selected:p.edgeMode to:v atY:y];
    y = [self addField:@"Columns (space separated)" key:@"edgeColumns"
                  value:p.edgeColumns to:v atY:y];
    [self endPage:@"Margins/Border/Edge" atY:y];

    y = [self beginPage:@"New Document"]; v = [self page:@"New Document"];
    y = [self addField:@"Default encoding" key:@"defaultEncoding"
                  value:p.defaultEncoding to:v atY:y];
    [self endPage:@"New Document" atY:y];

    y = [self beginPage:@"Indentation"]; v = [self page:@"Indentation"];
    y = [self addField:@"Tab width" key:@"tabWidth"
                  value:[@(p.tabWidth) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Insert spaces instead of tabs" key:@"useSpaces"
                       on:p.useSpaces to:v atY:y];
    y = [self addPopup:@"Auto-indent" key:@"autoIndentMode"
                 items:@[@"None", @"Keep the indent of the line above",
                         @"Also open a level after a brace"]
              selected:p.autoIndentMode to:v atY:y];
    [self endPage:@"Indentation" atY:y];

    y = [self beginPage:@"Highlighting"]; v = [self page:@"Highlighting"];
    y = [self addCheckbox:@"Highlight matching braces" key:@"braceMatchEnabled"
                       on:p.braceMatchEnabled to:v atY:y];
    y = [self addCheckbox:@"Smart highlighting" key:@"smartHighlightEnabled"
                       on:p.smartHighlightEnabled to:v atY:y];
    y = [self addCheckbox:@"Smart highlighting matches case" key:@"smartHighlightMatchCase"
                       on:p.smartHighlightMatchCase to:v atY:y];
    y = [self addCheckbox:@"Smart highlighting matches whole words" key:@"smartHighlightWholeWord"
                       on:p.smartHighlightWholeWord to:v atY:y];
    y = [self addCheckbox:@"Mark All matches case" key:@"markAllCaseSensitive"
                       on:p.markAllCaseSensitive to:v atY:y];
    y = [self addCheckbox:@"Mark All matches whole words" key:@"markAllWordOnly"
                       on:p.markAllWordOnly to:v atY:y];
    [self endPage:@"Highlighting" atY:y];

    y = [self beginPage:@"Print"]; v = [self page:@"Print"];
    y = [self addCheckbox:@"Print line numbers" key:@"printLineNumbers"
                       on:p.printLineNumbers to:v atY:y];
    y = [self addPopup:@"Print colours" key:@"printColourMode"
                 items:@[@"As shown", @"Inverted", @"Black on white", @"No background"]
              selected:p.printColourMode to:v atY:y];
    y = [self addField:@"Header (left)" key:@"printHeaderLeft"
                  value:p.printHeaderLeft to:v atY:y];
    y = [self addField:@"Header (right)" key:@"printHeaderRight"
                  value:p.printHeaderRight to:v atY:y];
    y = [self addField:@"Footer (middle)" key:@"printFooterMiddle"
                  value:p.printFooterMiddle to:v atY:y];
    [self endPage:@"Print" atY:y];

    y = [self beginPage:@"Backup"]; v = [self page:@"Backup"];
    y = [self addPopup:@"Backup on save" key:@"backupMode"
                 items:@[@"None", @"Simple", @"Verbose (timestamped)"]
              selected:p.backupMode to:v atY:y];
    y = [self addField:@"Backup folder" key:@"backupDirectory"
                  value:p.backupDirectory to:v atY:y];
    y = [self addCheckbox:@"Autosave modified documents" key:@"autosaveEnabled"
                       on:p.autosaveEnabled to:v atY:y];
    y = [self addField:@"Autosave every (seconds)" key:@"autosaveInterval"
                  value:[@(p.autosaveInterval) stringValue] to:v atY:y];
    [self endPage:@"Backup" atY:y];

    y = [self beginPage:@"Auto-Completion"]; v = [self page:@"Auto-Completion"];
    y = [self addCheckbox:@"Complete as you type" key:@"autoCompleteOnInput"
                       on:p.autoCompleteOnInput to:v atY:y];
    y = [self addPopup:@"Complete from" key:@"autoCompleteSource"
                 items:@[@"Functions", @"Words in the document", @"Both"]
              selected:p.autoCompleteSource to:v atY:y];
    y = [self addField:@"Characters before it opens" key:@"autoCompleteThreshold"
                  value:[@(p.autoCompleteThreshold) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Show a short list" key:@"autoCompleteBriefList"
                       on:p.autoCompleteBriefList to:v atY:y];
    y = [self addCheckbox:@"Ignore numbers" key:@"autoCompleteIgnoreNumbers"
                       on:p.autoCompleteIgnoreNumbers to:v atY:y];
    y = [self addCheckbox:@"Tab accepts the choice (otherwise Enter)" key:@"autoCompleteUseTab"
                       on:p.autoCompleteUseTab to:v atY:y];
    y = [self addCheckbox:@"Show the parameters of a function" key:@"functionHintOnInput"
                       on:p.functionHintOnInput to:v atY:y];
    y = [self addCheckbox:@"Close ( automatically" key:@"autoInsertParenthesis"
                       on:p.autoInsertParenthesis to:v atY:y];
    y = [self addCheckbox:@"Close [ automatically" key:@"autoInsertBracket"
                       on:p.autoInsertBracket to:v atY:y];
    y = [self addCheckbox:@"Close { automatically" key:@"autoInsertBrace"
                       on:p.autoInsertBrace to:v atY:y];
    y = [self addCheckbox:@"Close ' automatically" key:@"autoInsertSingleQuote"
                       on:p.autoInsertSingleQuote to:v atY:y];
    y = [self addCheckbox:@"Close \" automatically" key:@"autoInsertDoubleQuote"
                       on:p.autoInsertDoubleQuote to:v atY:y];
    y = [self addCheckbox:@"Close an HTML or XML tag" key:@"autoInsertCloseTag"
                       on:p.autoInsertCloseTag to:v atY:y];
    [self endPage:@"Auto-Completion" atY:y];

    y = [self beginPage:@"Multi-Instance & Date"]; v = [self page:@"Multi-Instance & Date"];
    y = [self addCheckbox:@"Reverse the date and time order" key:@"reverseDateTimeOrder"
                       on:p.reverseDateTimeOrder to:v atY:y];
    [self endPage:@"Multi-Instance & Date" atY:y];

    y = [self beginPage:@"Delimiter"]; v = [self page:@"Delimiter"];
    y = [self addCheckbox:@"Add characters to the word list" key:@"customWordCharsEnabled"
                       on:p.customWordCharsEnabled to:v atY:y];
    y = [self addField:@"Word characters" key:@"customWordChars"
                  value:p.customWordChars to:v atY:y];
    y = [self addField:@"Delimiter open" key:@"delimiterOpen"
                  value:p.delimiterOpen to:v atY:y];
    y = [self addField:@"Delimiter close" key:@"delimiterClose"
                  value:p.delimiterClose to:v atY:y];
    y = [self addCheckbox:@"Delimiter selection over several lines" key:@"delimiterMultiline"
                       on:p.delimiterMultiline to:v atY:y];
    [self endPage:@"Delimiter" atY:y];

    y = [self beginPage:@"Performance"]; v = [self page:@"Performance"];
    y = [self addCheckbox:@"Large file restriction (no syntax highlighting)"
                      key:@"largeFileRestrictionEnabled"
                       on:p.largeFileRestrictionEnabled to:v atY:y];
    y = [self addField:@"Large file size (MB)" key:@"largeFileThresholdMB"
                  value:[@(p.largeFileThresholdMB) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Allow brace match above that size" key:@"largeFileAllowBraceMatch"
                       on:p.largeFileAllowBraceMatch to:v atY:y];
    y = [self addCheckbox:@"Allow clickable links above that size"
                      key:@"largeFileAllowClickableLinks"
                       on:p.largeFileAllowClickableLinks to:v atY:y];
    [self endPage:@"Performance" atY:y];

    y = [self beginPage:@"Cloud & Link"]; v = [self page:@"Cloud & Link"];
    y = [self addCheckbox:@"Clickable links" key:@"linksEnabled" on:p.linksEnabled to:v atY:y];
    y = [self addCheckbox:@"Links without underline" key:@"linksNoUnderline"
                       on:p.linksNoUnderline to:v atY:y];
    y = [self addField:@"Extra URI schemes" key:@"linkCustomSchemes"
                  value:p.linkCustomSchemes to:v atY:y];
    y = [self addField:@"Settings folder" key:@"settingsDirectory"
                  value:p.settingsDirectory to:v atY:y];
    [self endPage:@"Cloud & Link" atY:y];
}

- (CGFloat)addField:(NSString *)label key:(NSString *)key value:(NSString *)value
                 to:(NSView *)content atY:(CGFloat)y {
    NSTextField *caption = [NSTextField labelWithString:label];
    caption.frame = NSMakeRect(20, y, 190, 20);
    [content addSubview:caption];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(220, y - 2, 180, 22)];
    field.stringValue = value ?: @"";
    [content addSubview:field];
    self.controls[key] = field;
    return y - 30;
}

- (CGFloat)addPopup:(NSString *)label key:(NSString *)key items:(NSArray<NSString *> *)items
           selected:(NSInteger)selected to:(NSView *)content atY:(CGFloat)y {
    NSTextField *caption = [NSTextField labelWithString:label];
    caption.frame = NSMakeRect(20, y, 190, 20);
    [content addSubview:caption];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(220, y - 4, 220, 26)];
    [popup addItemsWithTitles:items];
    if (selected >= 0 && selected < (NSInteger)items.count) [popup selectItemAtIndex:selected];
    [content addSubview:popup];
    self.controls[key] = popup;
    return y - 32;
}

- (CGFloat)addCheckbox:(NSString *)label key:(NSString *)key on:(BOOL)on
                    to:(NSView *)content atY:(CGFloat)y {
    NSButton *box = [NSButton checkboxWithTitle:label target:nil action:nil];
    box.frame = NSMakeRect(20, y, 380, 20);
    box.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:box];
    self.controls[key] = box;
    return y - 28;
}

- (NSArray<NSString *> *)categoryNames { return [self.pageNames copy]; }
- (BOOL)hasControlForKey:(NSString *)key { return self.controls[key] != nil; }

- (BOOL)visible { return self.panel.isVisible; }

- (void)toggle {
    if (self.panel.isVisible) { [self.panel orderOut:nil]; return; }
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)apply:(id)sender {
    NppPreferences *p = [NppPreferences shared];
    p.fontName = [self.controls[@"fontName"] stringValue];
    p.fontSize = [[self.controls[@"fontSize"] stringValue] integerValue];
    p.tabWidth = MAX(1, [[self.controls[@"tabWidth"] stringValue] integerValue]);
    p.useSpaces = [self.controls[@"useSpaces"] state] == NSControlStateValueOn;
    p.wordWrap = [self.controls[@"wordWrap"] state] == NSControlStateValueOn;
    p.showWhitespace = [self.controls[@"showWhitespace"] state] == NSControlStateValueOn;
    p.showIndentGuides = [self.controls[@"showIndentGuides"] state] == NSControlStateValueOn;
    p.restoreSession = [self.controls[@"restoreSession"] state] == NSControlStateValueOn;
    p.defaultEncoding = [self.controls[@"defaultEncoding"] stringValue];
    p.appearanceMode = [self.controls[@"appearanceMode"] indexOfSelectedItem];
    p.lightThemeName = [self.controls[@"lightThemeName"] titleOfSelectedItem];
    p.darkThemeName = [self.controls[@"darkThemeName"] titleOfSelectedItem];
    p.showToolbar = [self.controls[@"showToolbar"] state] == NSControlStateValueOn;
    p.toolbarDisplayMode = [self.controls[@"toolbarDisplayMode"] indexOfSelectedItem];
    p.toolbarIconSize = [self.controls[@"toolbarIconSize"] indexOfSelectedItem];
    p.backupMode = [self.controls[@"backupMode"] indexOfSelectedItem];
    p.backupDirectory = [self.controls[@"backupDirectory"] stringValue];
    p.autosaveEnabled = [self.controls[@"autosaveEnabled"] state] == NSControlStateValueOn;
    p.autosaveInterval = MAX(5, [[self.controls[@"autosaveInterval"] stringValue] integerValue]);
    p.printLineNumbers = [self.controls[@"printLineNumbers"] state] == NSControlStateValueOn;
    p.printColourMode = [self.controls[@"printColourMode"] indexOfSelectedItem];
    p.printHeaderLeft = [self.controls[@"printHeaderLeft"] stringValue];
    p.printHeaderRight = [self.controls[@"printHeaderRight"] stringValue];
    p.printFooterMiddle = [self.controls[@"printFooterMiddle"] stringValue];
    p.largeFileRestrictionEnabled = [self.controls[@"largeFileRestrictionEnabled"] state] == NSControlStateValueOn;
    p.largeFileThresholdMB = MAX(1, MIN(2046, [[self.controls[@"largeFileThresholdMB"] stringValue] integerValue]));
    p.largeFileAllowBraceMatch = [self.controls[@"largeFileAllowBraceMatch"] state] == NSControlStateValueOn;
    p.largeFileAllowClickableLinks = [self.controls[@"largeFileAllowClickableLinks"] state] == NSControlStateValueOn;
    p.linksEnabled = [self.controls[@"linksEnabled"] state] == NSControlStateValueOn;
    p.linksNoUnderline = [self.controls[@"linksNoUnderline"] state] == NSControlStateValueOn;
    p.linkCustomSchemes = [self.controls[@"linkCustomSchemes"] stringValue];
    p.braceMatchEnabled = [self.controls[@"braceMatchEnabled"] state] == NSControlStateValueOn;
    p.smartHighlightEnabled = [self.controls[@"smartHighlightEnabled"] state] == NSControlStateValueOn;
    p.customWordCharsEnabled = [self.controls[@"customWordCharsEnabled"] state] == NSControlStateValueOn;
    p.customWordChars = [self.controls[@"customWordChars"] stringValue];
    p.delimiterOpen = [self.controls[@"delimiterOpen"] stringValue];
    p.delimiterClose = [self.controls[@"delimiterClose"] stringValue];
    p.delimiterMultiline = [self.controls[@"delimiterMultiline"] state] == NSControlStateValueOn;
    p.multiInstanceMode = [self.controls[@"multiInstanceMode"] indexOfSelectedItem];
    p.reverseDateTimeOrder = [self.controls[@"reverseDateTimeOrder"] state] == NSControlStateValueOn;
    p.rememberPanelState = [self.controls[@"rememberPanelState"] state] == NSControlStateValueOn;
    p.settingsDirectory = [self.controls[@"settingsDirectory"] stringValue];

    // The settings the Windows version has that this one had no controls for.
    p.caretWidth = [self.controls[@"caretWidth"] indexOfSelectedItem];
    p.caretBlinkRate = MAX(0, [[self.controls[@"caretBlinkRate"] stringValue] integerValue]);
    p.currentLineHighlightMode = [self.controls[@"currentLineHighlightMode"] indexOfSelectedItem];
    p.currentLineFrameWidth = MIN(6, MAX(1, [[self.controls[@"currentLineFrameWidth"] stringValue] integerValue]));
    p.scrollBeyondLastLine = [self.controls[@"scrollBeyondLastLine"] state] == NSControlStateValueOn;
    p.virtualSpace = [self.controls[@"virtualSpace"] state] == NSControlStateValueOn;
    p.lineCopyCutWithoutSelection = [self.controls[@"lineCopyCutWithoutSelection"] state] == NSControlStateValueOn;
    p.selectedTextDragDrop = [self.controls[@"selectedTextDragDrop"] state] == NSControlStateValueOn;
    p.rightClickKeepsSelection = [self.controls[@"rightClickKeepsSelection"] state] == NSControlStateValueOn;
    p.lineWrapMethod = [self.controls[@"lineWrapMethod"] indexOfSelectedItem];
    p.bookmarkMarginShow = [self.controls[@"bookmarkMarginShow"] state] == NSControlStateValueOn;
    p.foldMarginShow = [self.controls[@"foldMarginShow"] state] == NSControlStateValueOn;
    p.paddingLeft = MIN(9, MAX(0, [[self.controls[@"paddingLeft"] stringValue] integerValue]));
    p.paddingRight = MIN(9, MAX(0, [[self.controls[@"paddingRight"] stringValue] integerValue]));
    p.edgeMode = [self.controls[@"edgeMode"] indexOfSelectedItem];
    p.edgeColumns = [self.controls[@"edgeColumns"] stringValue];
    p.autoIndentMode = [self.controls[@"autoIndentMode"] indexOfSelectedItem];
    p.smartHighlightMatchCase = [self.controls[@"smartHighlightMatchCase"] state] == NSControlStateValueOn;
    p.smartHighlightWholeWord = [self.controls[@"smartHighlightWholeWord"] state] == NSControlStateValueOn;
    p.markAllCaseSensitive = [self.controls[@"markAllCaseSensitive"] state] == NSControlStateValueOn;
    p.markAllWordOnly = [self.controls[@"markAllWordOnly"] state] == NSControlStateValueOn;
    p.autoCompleteOnInput = [self.controls[@"autoCompleteOnInput"] state] == NSControlStateValueOn;
    p.autoCompleteSource = [self.controls[@"autoCompleteSource"] indexOfSelectedItem];
    p.autoCompleteThreshold = MAX(1, [[self.controls[@"autoCompleteThreshold"] stringValue] integerValue]);
    p.autoCompleteBriefList = [self.controls[@"autoCompleteBriefList"] state] == NSControlStateValueOn;
    p.autoCompleteIgnoreNumbers = [self.controls[@"autoCompleteIgnoreNumbers"] state] == NSControlStateValueOn;
    p.autoCompleteUseTab = [self.controls[@"autoCompleteUseTab"] state] == NSControlStateValueOn;
    p.functionHintOnInput = [self.controls[@"functionHintOnInput"] state] == NSControlStateValueOn;
    p.autoInsertParenthesis = [self.controls[@"autoInsertParenthesis"] state] == NSControlStateValueOn;
    p.autoInsertBracket = [self.controls[@"autoInsertBracket"] state] == NSControlStateValueOn;
    p.autoInsertBrace = [self.controls[@"autoInsertBrace"] state] == NSControlStateValueOn;
    p.autoInsertSingleQuote = [self.controls[@"autoInsertSingleQuote"] state] == NSControlStateValueOn;
    p.autoInsertDoubleQuote = [self.controls[@"autoInsertDoubleQuote"] state] == NSControlStateValueOn;
    p.autoInsertCloseTag = [self.controls[@"autoInsertCloseTag"] state] == NSControlStateValueOn;
    [self.editor applyEditorPreferences];
    [self.editor setAutosaveEnabled:p.autosaveEnabled interval:p.autosaveInterval];
    [self.editor applyWordCharacters];
    [self.editor applyPerformanceRestrictions];
    [self.editor markClickableLinks];
    [p applyToEditor:self.editor];
    // The toolbar lives on the window, so the delegate applies those three.
    if ([NSApp.delegate respondsToSelector:@selector(applyToolbarPreferences)]) {
        [NSApp.delegate performSelector:@selector(applyToolbarPreferences)];
    }
}

- (void)resetAll:(id)sender {
    [[NppPreferences shared] reset];
    [[NppPreferences shared] applyToEditor:self.editor];
    [self.panel orderOut:nil];
}

@end

#pragma mark - Style Configurator

static NSColor *ColourFromHexString(NSString *hex) {
    unsigned int rgb = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return nil;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

@interface StyleConfiguratorWindow () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSPopUpButton *languagePicker;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSColorWell *foregroundWell;
@property (nonatomic, strong) NSColorWell *backgroundWell;
@property (nonatomic, strong) NSButton *boldBox;
@property (nonatomic, strong) NSButton *italicBox;
@property (nonatomic, strong) NSButton *underlineBox;
@property (nonatomic, strong) NSTextField *fontField;
@property (nonatomic, strong) NSTextField *sizeField;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSArray<NppStyle *> *styles;
@end

@implementation StyleConfiguratorWindow

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;

    NSRect frame = NSMakeRect(0, 0, 460, 420);
    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Style Configurator";
    _panel.releasedWhenClosed = NO;

    NSView *content = [[NSView alloc] initWithFrame:frame];

    _languagePicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, NSHeight(frame) - 44, 240, 26)];
    for (NppLanguage *lang in [[LanguageCatalog sharedCatalog].allLanguages
            sortedArrayUsingComparator:^NSComparisonResult(NppLanguage *a, NppLanguage *b) {
                return [a.name caseInsensitiveCompare:b.name]; }]) {
        [_languagePicker addItemWithTitle:lang.name];
    }
    _languagePicker.target = self;
    _languagePicker.action = @selector(languageChanged:);
    [content addSubview:_languagePicker];

    // Every attribute the upstream Style struct carries, not just the foreground.
    CGFloat row1 = NSHeight(frame) - 46;
    NSTextField *fgLabel = [NSTextField labelWithString:@"Text"];
    fgLabel.frame = NSMakeRect(276, row1 + 4, 34, 18);
    [content addSubview:fgLabel];
    _foregroundWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(312, row1, 48, 26)];
    _foregroundWell.target = self;
    _foregroundWell.action = @selector(attributesChanged:);
    [content addSubview:_foregroundWell];

    NSTextField *bgLabel = [NSTextField labelWithString:@"Back"];
    bgLabel.frame = NSMakeRect(366, row1 + 4, 36, 18);
    [content addSubview:bgLabel];
    _backgroundWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(404, row1, 40, 26)];
    _backgroundWell.target = self;
    _backgroundWell.action = @selector(attributesChanged:);
    [content addSubview:_backgroundWell];

    CGFloat row2 = row1 - 32;
    _boldBox = [NSButton checkboxWithTitle:@"Bold" target:self action:@selector(attributesChanged:)];
    _boldBox.frame = NSMakeRect(20, row2, 60, 20);
    [content addSubview:_boldBox];
    _italicBox = [NSButton checkboxWithTitle:@"Italic" target:self action:@selector(attributesChanged:)];
    _italicBox.frame = NSMakeRect(84, row2, 64, 20);
    [content addSubview:_italicBox];
    _underlineBox = [NSButton checkboxWithTitle:@"Underline" target:self action:@selector(attributesChanged:)];
    _underlineBox.frame = NSMakeRect(152, row2, 90, 20);
    [content addSubview:_underlineBox];

    _fontField = [[NSTextField alloc] initWithFrame:NSMakeRect(250, row2 - 2, 130, 22)];
    _fontField.placeholderString = @"Font";
    _fontField.target = self;
    _fontField.action = @selector(attributesChanged:);
    [content addSubview:_fontField];

    _sizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(388, row2 - 2, 56, 22)];
    _sizeField.placeholderString = @"Size";
    _sizeField.target = self;
    _sizeField.action = @selector(attributesChanged:);
    [content addSubview:_sizeField];

    NSRect tableRect = NSMakeRect(20, 20, NSWidth(frame) - 40, NSHeight(frame) - 116);
    _table = [[NSTableView alloc] initWithFrame:tableRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"style"];
    col.width = NSWidth(tableRect) - 4;
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.dataSource = self;
    _table.delegate = self;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:tableRect];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = _table;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:scroll];

    _panel.contentView = content;
    [self loadLanguage:editor.currentDocument.language.name ?: @"normal"];
    return self;
}

- (BOOL)visible { return self.panel.isVisible; }
- (NSInteger)styleCount { return (NSInteger)self.styles.count; }

- (void)loadLanguage:(NSString *)name {
    [self.languagePicker selectItemWithTitle:name];
    self.styles = [[StyleCatalog sharedCatalog] stylesForLexerName:name] ?: @[];
    [self.table reloadData];
}

- (void)toggle {
    if (self.panel.isVisible) { [self.panel orderOut:nil]; return; }
    [self loadLanguage:self.editor.currentDocument.language.name ?: @"normal"];
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)languageChanged:(id)sender { [self loadLanguage:self.languagePicker.titleOfSelectedItem]; }

static NSString *HexOfColour(NSColor *colour) {
    NSColor *c = [colour colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return [NSString stringWithFormat:@"%02X%02X%02X",
            (int)(c.redComponent * 255), (int)(c.greenComponent * 255), (int)(c.blueComponent * 255)];
}

- (void)attributesChanged:(id)sender {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.styles.count) return;

    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[@"fg"] = HexOfColour(self.foregroundWell.color);
    attrs[@"bg"] = HexOfColour(self.backgroundWell.color);
    attrs[@"bold"] = @(self.boldBox.state == NSControlStateValueOn);
    attrs[@"italic"] = @(self.italicBox.state == NSControlStateValueOn);
    attrs[@"underline"] = @(self.underlineBox.state == NSControlStateValueOn);
    if (self.fontField.stringValue.length) attrs[@"font"] = self.fontField.stringValue;
    if (self.sizeField.stringValue.integerValue > 0) attrs[@"size"] = @(self.sizeField.stringValue.integerValue);

    [[NppPreferences shared] setStyleOverride:attrs
                                  forLanguage:self.languagePicker.titleOfSelectedItem
                                      styleID:self.styles[(NSUInteger)row].styleID];
    [self.editor applyLanguage];
    [self.table reloadData];
}

/// Loads the selected row's current values into the controls.
- (void)tableViewSelectionDidChange:(NSNotification *)note {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.styles.count) return;
    NppStyle *style = self.styles[(NSUInteger)row];
    NSDictionary *attrs = [[NppPreferences shared]
        styleOverrideForLanguage:self.languagePicker.titleOfSelectedItem styleID:style.styleID];

    self.foregroundWell.color = style.foreground ?: [NSColor textColor];
    self.backgroundWell.color = style.background ?: [NSColor textBackgroundColor];
    self.boldBox.state = (style.fontStyle & 1) ? NSControlStateValueOn : NSControlStateValueOff;
    self.italicBox.state = (style.fontStyle & 2) ? NSControlStateValueOn : NSControlStateValueOff;
    self.underlineBox.state = (style.fontStyle & 4) ? NSControlStateValueOn : NSControlStateValueOff;
    self.fontField.stringValue = style.fontName ?: @"";
    self.sizeField.stringValue = style.fontSize > 0 ? [@(style.fontSize) stringValue] : @"";

    if (!attrs) return;                       // no override yet: the theme values stand
    if (attrs[@"fg"]) self.foregroundWell.color = ColourFromHexString(attrs[@"fg"]) ?: self.foregroundWell.color;
    if (attrs[@"bg"]) self.backgroundWell.color = ColourFromHexString(attrs[@"bg"]) ?: self.backgroundWell.color;
    if (attrs[@"bold"]) self.boldBox.state = [attrs[@"bold"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    if (attrs[@"italic"]) self.italicBox.state = [attrs[@"italic"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    if (attrs[@"underline"]) self.underlineBox.state = [attrs[@"underline"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    if (attrs[@"font"]) self.fontField.stringValue = attrs[@"font"];
    if (attrs[@"size"]) self.sizeField.stringValue = [attrs[@"size"] stringValue];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)self.styles.count; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.styles.count) return @"";
    NppStyle *s = self.styles[(NSUInteger)row];
    NSString *key = [NSString stringWithFormat:@"%@/%d",
                     self.languagePicker.titleOfSelectedItem, s.styleID];
    NSDictionary *override = [[NppPreferences shared]
        styleOverrideForLanguage:self.languagePicker.titleOfSelectedItem styleID:s.styleID];
    (void)key;
    return [NSString stringWithFormat:@"%@  (style %d)%@", s.name ?: @"style", s.styleID,
            override.count ? @"   customised" : @""];
}

@end

#pragma mark - Shortcut Mapper

@interface ShortcutMapperWindow () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSArray<NSMenuItem *> *items;
@end

@implementation ShortcutMapperWindow

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;

    NSRect frame = NSMakeRect(0, 0, 520, 460);
    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Shortcut Mapper";
    _panel.releasedWhenClosed = NO;

    _table = [[NSTableView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"sc"];
    col.width = NSWidth(frame) - 4;
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(rowActivated:);

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = _table;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _panel.contentView = scroll;

    [self reload];
    return self;
}

- (void)reload {
    NSMutableArray *found = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithArray:NSApp.mainMenu.itemArray];
    while (queue.count) {
        NSMenuItem *item = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (item.submenu) [queue addObjectsFromArray:item.submenu.itemArray];
        if (item.keyEquivalent.length && item.title.length) [found addObject:item];
    }
    self.items = found;
    [self.table reloadData];
}

- (BOOL)visible { return self.panel.isVisible; }

- (NSArray<NSString *> *)commandTitles {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSMenuItem *i in self.items) [titles addObject:i.title];
    return titles;
}

- (void)toggle {
    if (self.panel.isVisible) { [self.panel orderOut:nil]; return; }
    [self reload];
    [self.panel makeKeyAndOrderFront:nil];
}

static NSString *DescribeShortcut(NSMenuItem *item) {
    NSMutableString *out = [NSMutableString string];
    NSEventModifierFlags m = item.keyEquivalentModifierMask;
    if (m & NSEventModifierFlagControl) [out appendString:@"ctrl+"];
    if (m & NSEventModifierFlagOption)  [out appendString:@"opt+"];
    if (m & NSEventModifierFlagShift)   [out appendString:@"shift+"];
    if (m & NSEventModifierFlagCommand) [out appendString:@"cmd+"];
    [out appendString:item.keyEquivalent];
    return out;
}

- (void)rowActivated:(id)sender {
    NSInteger row = self.table.clickedRow;
    if (row < 0 || row >= (NSInteger)self.items.count) return;
    NSMenuItem *item = self.items[(NSUInteger)row];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Shortcut for \"%@\"", item.title];
    alert.informativeText = @"Use modifiers cmd, shift, opt, ctrl joined by '+', "
                            @"for example cmd+shift+k. Leave empty to remove.";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    field.stringValue = DescribeShortcut(item);
    alert.accessoryView = field;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [[NppPreferences shared] setShortcutOverride:field.stringValue forCommand:item.title];
    ApplyShortcutSpec(item, field.stringValue);
    [self.table reloadData];
}

/// Applies a "cmd+shift+k" style specification to a menu item.
void ApplyShortcutSpec(NSMenuItem *item, NSString *spec) {
    NSEventModifierFlags mask = 0;
    NSString *key = @"";
    for (NSString *part in [spec.lowercaseString componentsSeparatedByString:@"+"]) {
        if ([part isEqualToString:@"cmd"]) mask |= NSEventModifierFlagCommand;
        else if ([part isEqualToString:@"shift"]) mask |= NSEventModifierFlagShift;
        else if ([part isEqualToString:@"opt"] || [part isEqualToString:@"alt"]) mask |= NSEventModifierFlagOption;
        else if ([part isEqualToString:@"ctrl"]) mask |= NSEventModifierFlagControl;
        else key = part;
    }
    item.keyEquivalent = key;
    item.keyEquivalentModifierMask = mask;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)self.items.count; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.items.count) return @"";
    NSMenuItem *item = self.items[(NSUInteger)row];
    return [NSString stringWithFormat:@"%-44@ %@", item.title, DescribeShortcut(item)];
}

@end

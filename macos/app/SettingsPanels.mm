#import "SettingsPanels.h"
#import "SettingsCommands.h"
#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#import "Toolbar.h"
#import "BackupAndPrint.h"

#pragma mark - Preferences

@interface PreferencesWindow ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSMutableDictionary *controls;
@end

@implementation PreferencesWindow

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _controls = [NSMutableDictionary dictionary];

    NSRect frame = NSMakeRect(0, 0, 470, 800);
    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Preferences";
    _panel.releasedWhenClosed = NO;

    NSView *content = [[NSView alloc] initWithFrame:frame];
    CGFloat y = NSHeight(frame) - 40;

    y = [self addField:@"Font" key:@"fontName" value:[NppPreferences shared].fontName
                     to:content atY:y];
    y = [self addField:@"Font size" key:@"fontSize"
                  value:[@([NppPreferences shared].fontSize) stringValue] to:content atY:y];
    y = [self addField:@"Tab width" key:@"tabWidth"
                  value:[@([NppPreferences shared].tabWidth) stringValue] to:content atY:y];
    y = [self addCheckbox:@"Insert spaces instead of tabs" key:@"useSpaces"
                      on:[NppPreferences shared].useSpaces to:content atY:y];
    y = [self addCheckbox:@"Word wrap" key:@"wordWrap"
                      on:[NppPreferences shared].wordWrap to:content atY:y];
    y = [self addCheckbox:@"Show whitespace" key:@"showWhitespace"
                      on:[NppPreferences shared].showWhitespace to:content atY:y];
    y = [self addCheckbox:@"Show indent guides" key:@"showIndentGuides"
                      on:[NppPreferences shared].showIndentGuides to:content atY:y];
    y = [self addCheckbox:@"Restore the previous session on launch" key:@"restoreSession"
                      on:[NppPreferences shared].restoreSession to:content atY:y];
    y = [self addField:@"Default encoding" key:@"defaultEncoding"
                  value:[NppPreferences shared].defaultEncoding to:content atY:y];

    y -= 8;
    y = [self addPopup:@"Appearance" key:@"appearanceMode"
                 items:@[@"Follow the system", @"Light", @"Dark"]
              selected:[NppPreferences shared].appearanceMode to:content atY:y];
    NSArray *themes = [StyleCatalog availableThemeNames];
    y = [self addPopup:@"Light theme" key:@"lightThemeName" items:themes
              selected:[themes indexOfObject:[NppPreferences shared].lightThemeName ?: @"Default"]
                    to:content atY:y];
    y = [self addPopup:@"Dark theme" key:@"darkThemeName" items:themes
              selected:[themes indexOfObject:[NppPreferences shared].darkThemeName ?: @"DarkModeDefault"]
                    to:content atY:y];

    y -= 8;
    y = [self addCheckbox:@"Show the toolbar" key:@"showToolbar"
                      on:[NppPreferences shared].showToolbar to:content atY:y];
    y = [self addPopup:@"Toolbar buttons" key:@"toolbarDisplayMode"
                 items:@[@"Icons only", @"Icons and labels", @"Labels only"]
              selected:[NppPreferences shared].toolbarDisplayMode to:content atY:y];
    y = [self addPopup:@"Toolbar size" key:@"toolbarIconSize"
                 items:@[@"Regular", @"Small"]
              selected:[NppPreferences shared].toolbarIconSize to:content atY:y];

    y -= 8;
    y = [self addPopup:@"Backup on save" key:@"backupMode"
                 items:@[@"None", @"Simple", @"Verbose (timestamped)"]
              selected:[NppPreferences shared].backupMode to:content atY:y];
    y = [self addField:@"Backup folder" key:@"backupDirectory"
                  value:[NppPreferences shared].backupDirectory to:content atY:y];
    y = [self addCheckbox:@"Autosave modified documents" key:@"autosaveEnabled"
                      on:[NppPreferences shared].autosaveEnabled to:content atY:y];
    y = [self addField:@"Autosave every (seconds)" key:@"autosaveInterval"
                  value:[@([NppPreferences shared].autosaveInterval) stringValue] to:content atY:y];

    y -= 8;
    y = [self addCheckbox:@"Print line numbers" key:@"printLineNumbers"
                      on:[NppPreferences shared].printLineNumbers to:content atY:y];
    y = [self addPopup:@"Print colours" key:@"printColourMode"
                 items:@[@"As shown", @"Inverted", @"Black on white", @"No background"]
              selected:[NppPreferences shared].printColourMode to:content atY:y];
    y = [self addField:@"Header (left)" key:@"printHeaderLeft"
                  value:[NppPreferences shared].printHeaderLeft to:content atY:y];
    y = [self addField:@"Header (right)" key:@"printHeaderRight"
                  value:[NppPreferences shared].printHeaderRight to:content atY:y];
    y = [self addField:@"Footer (middle)" key:@"printFooterMiddle"
                  value:[NppPreferences shared].printFooterMiddle to:content atY:y];

    NSButton *apply = [[NSButton alloc] initWithFrame:NSMakeRect(300, 12, 100, 28)];
    apply.title = @"Apply";
    apply.bezelStyle = NSBezelStyleRounded;
    apply.target = self;
    apply.action = @selector(apply:);
    [content addSubview:apply];

    NSButton *reset = [[NSButton alloc] initWithFrame:NSMakeRect(190, 12, 100, 28)];
    reset.title = @"Reset";
    reset.bezelStyle = NSBezelStyleRounded;
    reset.target = self;
    reset.action = @selector(resetAll:);
    [content addSubview:reset];

    _panel.contentView = content;
    return self;
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
    [self.editor setAutosaveEnabled:p.autosaveEnabled interval:p.autosaveInterval];
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

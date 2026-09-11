#import "SettingsPanels.h"
#import "SettingsCommands.h"
#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"

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

    NSRect frame = NSMakeRect(0, 0, 420, 360);
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
    [p applyToEditor:self.editor];
}

- (void)resetAll:(id)sender {
    [[NppPreferences shared] reset];
    [[NppPreferences shared] applyToEditor:self.editor];
    [self.panel orderOut:nil];
}

@end

#pragma mark - Style Configurator

@interface StyleConfiguratorWindow () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSPopUpButton *languagePicker;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSColorWell *well;
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

    _well = [[NSColorWell alloc] initWithFrame:NSMakeRect(300, NSHeight(frame) - 46, 60, 28)];
    _well.target = self;
    _well.action = @selector(colourChanged:);
    [content addSubview:_well];

    NSRect tableRect = NSMakeRect(20, 20, NSWidth(frame) - 40, NSHeight(frame) - 80);
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

- (void)colourChanged:(id)sender {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.styles.count) return;
    NSColor *c = [self.well.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    NSString *hex = [NSString stringWithFormat:@"%02X%02X%02X",
                     (int)(c.redComponent * 255), (int)(c.greenComponent * 255),
                     (int)(c.blueComponent * 255)];
    [[NppPreferences shared] setStyleOverride:hex
                                  forLanguage:self.languagePicker.titleOfSelectedItem
                                      styleID:self.styles[(NSUInteger)row].styleID];
    [self.editor applyLanguage];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)self.styles.count; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.styles.count) return @"";
    NppStyle *s = self.styles[(NSUInteger)row];
    NSString *key = [NSString stringWithFormat:@"%@/%d",
                     self.languagePicker.titleOfSelectedItem, s.styleID];
    NSString *override = [NppPreferences shared].styleOverrides[key];
    return [NSString stringWithFormat:@"%@  (style %d)%@", s.name ?: @"style", s.styleID,
            override ? [@"  overridden #" stringByAppendingString:override] : @""];
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

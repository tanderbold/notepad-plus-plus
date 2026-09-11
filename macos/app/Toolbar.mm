#import "Toolbar.h"

/// One button: identifier, label, SF Symbol and the menu selector it drives.
typedef struct {
    __unsafe_unretained NSString *identifier;
    __unsafe_unretained NSString *label;
    __unsafe_unretained NSString *symbol;
    __unsafe_unretained NSString *selectorName;
} NppToolbarSpec;

static NppToolbarSpec gSpecs[] = {
    {@"npp.new",        @"New",        @"doc",                    @"newDocument:"},
    {@"npp.open",       @"Open",       @"folder",                 @"openDocument:"},
    {@"npp.save",       @"Save",       @"square.and.arrow.down",  @"saveDocument:"},
    {@"npp.saveAll",    @"Save All",   @"square.and.arrow.down.on.square", @"saveAll:"},
    {@"npp.close",      @"Close",      @"xmark.square",           @"closeTab:"},
    {@"npp.cut",        @"Cut",        @"scissors",               @"cutText:"},
    {@"npp.copy",       @"Copy",       @"doc.on.doc",             @"copyText:"},
    {@"npp.paste",      @"Paste",      @"doc.on.clipboard",       @"pasteText:"},
    {@"npp.undo",       @"Undo",       @"arrow.uturn.backward",   @"undo:"},
    {@"npp.redo",       @"Redo",       @"arrow.uturn.forward",    @"redo:"},
    {@"npp.find",       @"Find",       @"magnifyingglass",        @"showFind:"},
    {@"npp.replace",    @"Replace",    @"arrow.2.squarepath",     @"showReplace:"},
    {@"npp.zoomIn",     @"Zoom In",    @"plus.magnifyingglass",   @"zoomIn:"},
    {@"npp.zoomOut",    @"Zoom Out",   @"minus.magnifyingglass",  @"zoomOut:"},
    {@"npp.wrap",       @"Word Wrap",  @"text.append",            @"toggleWordWrap:"},
    {@"npp.whitespace", @"Whitespace", @"paragraphsign",          @"toggleWhitespace:"},
    {@"npp.macroRec",   @"Record",     @"record.circle",          @"macroStart:"},
    {@"npp.macroStop",  @"Stop",       @"stop.circle",            @"macroStop:"},
    {@"npp.macroPlay",  @"Play",       @"play.circle",            @"macroPlay:"},
};

static const NSUInteger kSpecCount = sizeof(gSpecs) / sizeof(gSpecs[0]);

@interface NppToolbar ()
@property (nonatomic, weak) NSWindow *window;
@property (nonatomic, weak) id actionTarget;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic) NSInteger requestedDisplayMode;
@property (nonatomic) NSInteger requestedIconSize;
@end

@implementation NppToolbar

- (instancetype)initWithWindow:(NSWindow *)window target:(id)target {
    if (!(self = [super init])) return nil;
    _window = window;
    _actionTarget = target;

    _toolbar = [[NSToolbar alloc] initWithIdentifier:@"NppMacToolbar"];
    _toolbar.delegate = self;
    _toolbar.allowsUserCustomization = YES;
    _toolbar.autosavesConfiguration = YES;
    _toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    window.toolbar = _toolbar;
    return self;
}

- (BOOL)visible { return self.window.toolbar != nil && self.toolbar.isVisible; }

- (void)setVisible:(BOOL)visible {
    // Keep the toolbar attached either way so its configuration survives.
    self.window.toolbar = self.toolbar;
    self.toolbar.visible = visible;
}

- (NSInteger)displayMode { return self.requestedDisplayMode; }
- (NSInteger)iconSize { return self.requestedIconSize; }
- (NSToolbarDisplayMode)effectiveDisplayMode { return self.toolbar.displayMode; }

- (void)setDisplayMode:(NSInteger)mode {
    self.requestedDisplayMode = mode;
    [self applyLayout];
}

- (void)setIconSize:(NSInteger)size {
    self.requestedIconSize = size;
    [self applyLayout];
}

/// The two settings are not independent on macOS: the compact toolbar style
/// draws icons only and ignores the display mode, so labels force the regular
/// style. Both are therefore applied together rather than one at a time.
- (void)applyLayout {
    BOOL wantsLabels = self.requestedDisplayMode != 0;
    self.window.toolbarStyle = (wantsLabels || self.requestedIconSize == 0)
        ? NSWindowToolbarStyleExpanded
        : NSWindowToolbarStyleUnifiedCompact;
    self.toolbar.displayMode = self.requestedDisplayMode == 0 ? NSToolbarDisplayModeIconOnly
                             : self.requestedDisplayMode == 2 ? NSToolbarDisplayModeLabelOnly
                                                              : NSToolbarDisplayModeIconAndLabel;
}

- (NSArray<NSString *> *)itemIdentifiers {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSToolbarItem *item in self.toolbar.items) [ids addObject:item.itemIdentifier];
    return ids;
}

- (SEL)actionForIdentifier:(NSString *)identifier {
    for (NSUInteger i = 0; i < kSpecCount; ++i) {
        if ([gSpecs[i].identifier isEqualToString:identifier]) {
            return NSSelectorFromString(gSpecs[i].selectorName);
        }
    }
    return NULL;
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSUInteger i = 0; i < kSpecCount; ++i) {
        [ids addObject:gSpecs[i].identifier];
        // Group the buttons the way the Windows toolbar groups them.
        if ([gSpecs[i].identifier isEqualToString:@"npp.close"] ||
            [gSpecs[i].identifier isEqualToString:@"npp.paste"] ||
            [gSpecs[i].identifier isEqualToString:@"npp.redo"] ||
            [gSpecs[i].identifier isEqualToString:@"npp.replace"] ||
            [gSpecs[i].identifier isEqualToString:@"npp.whitespace"]) {
            [ids addObject:NSToolbarSpaceItemIdentifier];
        }
    }
    return ids;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSUInteger i = 0; i < kSpecCount; ++i) [ids addObject:gSpecs[i].identifier];
    [ids addObjectsFromArray:@[NSToolbarSpaceItemIdentifier,
                               NSToolbarFlexibleSpaceItemIdentifier,
                               NSToolbarSeparatorItemIdentifier]];
    return ids;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    for (NSUInteger i = 0; i < kSpecCount; ++i) {
        if (![gSpecs[i].identifier isEqualToString:identifier]) continue;
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
        item.label = gSpecs[i].label;
        item.paletteLabel = gSpecs[i].label;
        item.toolTip = gSpecs[i].label;
        item.image = [NSImage imageWithSystemSymbolName:gSpecs[i].symbol
                               accessibilityDescription:gSpecs[i].label];
        item.target = self.actionTarget;
        item.action = NSSelectorFromString(gSpecs[i].selectorName);
        return item;
    }
    return nil;
}

@end

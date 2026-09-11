#import "AuxPanels.h"
#import "EditorController.h"
#import "ScintillaView.h"

#pragma mark - Character Panel

@interface CharacterPanel () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, weak) EditorController *editor;
@end

@implementation CharacterPanel

/// Notepad++'s ASCII panel covers 0-255; the printable range starts at 32.
static const NSInteger kFirstCode = 32;
static const NSInteger kLastCode = 255;

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;

    NSRect frame = NSMakeRect(0, 0, 260, 420);
    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Character Panel";
    _panel.floatingPanel = YES;
    _panel.releasedWhenClosed = NO;

    _table = [[NSTableView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"ch"];
    col.width = frame.size.width - 4;
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
    return self;
}

- (BOOL)visible { return self.panel.isVisible; }
- (NSInteger)rowCount { return kLastCode - kFirstCode + 1; }

- (void)toggle {
    if (self.panel.isVisible) { [self.panel orderOut:nil]; return; }
    [self.table reloadData];
    [self.panel makeKeyAndOrderFront:nil];
}

- (BOOL)insertRow:(NSInteger)row {
    if (row < 0 || row >= self.rowCount) return NO;
    unichar c = (unichar)(kFirstCode + row);
    NSString *text = [NSString stringWithCharacters:&c length:1];
    ScintillaView *sci = self.editor.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:text];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS
           wParam:(uptr_t)(pos + (long)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) lParam:0];
    [self.editor refreshChrome];
    return YES;
}

- (void)rowActivated:(id)sender { [self insertRow:self.table.clickedRow]; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return self.rowCount; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSInteger code = kFirstCode + row;
    unichar c = (unichar)code;
    return [NSString stringWithFormat:@"%3ld   0x%02lX   %@",
            (long)code, (long)code, [NSString stringWithCharacters:&c length:1]];
}

@end

#pragma mark - Clipboard History

@interface ClipboardHistoryPanel () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSMutableArray<NSString *> *items;
@property (nonatomic, strong) NSTimer *poller;
@property (nonatomic) NSInteger lastChangeCount;
@end

@implementation ClipboardHistoryPanel

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _items = [NSMutableArray array];
    _lastChangeCount = [NSPasteboard generalPasteboard].changeCount;

    NSRect frame = NSMakeRect(0, 0, 320, 360);
    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Clipboard History";
    _panel.floatingPanel = YES;
    _panel.releasedWhenClosed = NO;

    _table = [[NSTableView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"clip"];
    col.width = frame.size.width - 4;
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
    return self;
}

- (void)dealloc { [_poller invalidate]; }

- (BOOL)visible { return self.panel.isVisible; }
- (NSArray<NSString *> *)entries { return self.items; }

/// The pasteboard has no change notification, so it is polled while the panel
/// is open and captured explicitly after the editor's own copy commands.
- (void)capturePasteboard {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    self.lastChangeCount = pb.changeCount;
    NSString *text = [pb stringForType:NSPasteboardTypeString];
    if (!text.length) return;
    if (self.items.count && [self.items.firstObject isEqualToString:text]) return;
    [self.items removeObject:text];
    [self.items insertObject:text atIndex:0];
    while (self.items.count > 30) [self.items removeLastObject];
    [self.table reloadData];
}

- (void)toggle {
    if (self.panel.isVisible) {
        [self.poller invalidate];
        self.poller = nil;
        [self.panel orderOut:nil];
        return;
    }
    [self capturePasteboard];
    __weak ClipboardHistoryPanel *weakSelf = self;
    self.poller = [NSTimer scheduledTimerWithTimeInterval:0.75 repeats:YES block:^(NSTimer *t) {
        ClipboardHistoryPanel *me = weakSelf;
        if (!me) { [t invalidate]; return; }
        if ([NSPasteboard generalPasteboard].changeCount != me.lastChangeCount) [me capturePasteboard];
    }];
    [self.panel makeKeyAndOrderFront:nil];
}

- (BOOL)pasteRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.items.count) return NO;
    NSString *text = self.items[(NSUInteger)row];
    ScintillaView *sci = self.editor.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:text];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS
           wParam:(uptr_t)(pos + (long)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) lParam:0];
    [self.editor refreshChrome];
    return YES;
}

- (void)rowActivated:(id)sender { [self pasteRow:self.table.clickedRow]; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)self.items.count; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSString *text = self.items[(NSUInteger)row];
    NSString *oneLine = [[text componentsSeparatedByCharactersInSet:
                          [NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    return oneLine.length > 80 ? [[oneLine substringToIndex:77] stringByAppendingString:@"..."] : oneLine;
}

@end

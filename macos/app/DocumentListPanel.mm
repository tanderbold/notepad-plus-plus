#import "DocumentListPanel.h"
#import "EditorController.h"

@interface DocumentListPanel () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, weak) EditorController *editor;
@end

@implementation DocumentListPanel

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;

    NSRect frame = NSMakeRect(0, 0, 280, 360);
    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered
                                            defer:YES];
    _panel.title = @"Document List";
    _panel.floatingPanel = YES;
    _panel.releasedWhenClosed = NO;

    _table = [[NSTableView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"doc"];
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
- (NSInteger)rowCount { return self.table.numberOfRows; }

- (void)toggle {
    if (self.panel.isVisible) {
        [self.panel orderOut:nil];
    } else {
        [self.table reloadData];
        [self.panel makeKeyAndOrderFront:nil];
    }
}

- (void)rowActivated:(id)sender {
    NSInteger row = self.table.clickedRow;
    if (row >= 0) [self.editor selectDocumentAtIndex:row];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)self.editor.documents.count;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NppDocument *d = self.editor.documents[(NSUInteger)row];
    return d.path ?: d.displayName;
}

@end

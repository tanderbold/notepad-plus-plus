#import "WorkspacePanel.h"
#import "SettingsCommands.h"

@interface WSNode : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) BOOL isDirectory;
@property (nonatomic, strong, nullable) NSMutableArray<WSNode *> *children;
@end

@implementation WSNode
- (NSMutableArray<WSNode *> *)children {
    if (!_isDirectory) return nil;
    if (_children) return _children;                 // loaded lazily, as the tree expands
    _children = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [[fm contentsOfDirectoryAtPath:_path error:NULL]
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;         // hidden entries stay hidden
        NSString *full = [_path stringByAppendingPathComponent:name];
        // Symbolic links only when MISC. allows them, as upstream.
        NSString *type = [fm attributesOfItemAtPath:full error:NULL][NSFileType];
        if ([type isEqualToString:NSFileTypeSymbolicLink] && ![NppPreferences shared].workspaceSymlinks) continue;
        BOOL dir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&dir]) continue;
        WSNode *n = [[WSNode alloc] init];
        n.path = full;
        n.isDirectory = dir;
        [_children addObject:n];
    }
    return _children;
}
@end

@interface WorkspacePanel () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, strong) NSScrollView *scroll;
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong, nullable) WSNode *root;
@end

@implementation WorkspacePanel

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super init])) return nil;

    _outline = [[NSOutlineView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.title = @"Workspace";
    col.width = NSWidth(frame);
    [_outline addTableColumn:col];
    _outline.outlineTableColumn = col;
    _outline.headerView = nil;
    _outline.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    _outline.dataSource = self;
    _outline.delegate = self;
    _outline.target = self;
    _outline.doubleAction = @selector(rowDoubleClicked:);

    _scroll = [[NSScrollView alloc] initWithFrame:frame];
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.documentView = _outline;
    _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return self;
}

- (NSView *)view { return self.scroll; }
- (NSString *)rootPath { return self.root.path; }

- (void)setRootPath:(NSString *)path {
    if (!path.length) { self.root = nil; [self.outline reloadData]; return; }
    WSNode *n = [[WSNode alloc] init];
    n.path = path;
    n.isDirectory = YES;
    self.root = n;
    [self.outline reloadData];
    [self.outline expandItem:n];
}

- (NSArray<NSString *> *)topLevelNames {
    NSMutableArray *out = [NSMutableArray array];
    for (WSNode *n in self.root.children) [out addObject:n.path.lastPathComponent];
    return out;
}

- (void)rowDoubleClicked:(id)sender {
    WSNode *n = [self.outline itemAtRow:self.outline.clickedRow];
    if (!n) return;
    if (n.isDirectory) {
        if ([self.outline isItemExpanded:n]) [self.outline collapseItem:n];
        else [self.outline expandItem:n];
        return;
    }
    [self.delegate workspaceDidActivateFile:n.path];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    if (!self.root) return 0;
    if (!item) return 1;                              // the root folder itself
    return (NSInteger)[(WSNode *)item children].count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item {
    if (!item) return self.root;
    return [(WSNode *)item children][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return [(WSNode *)item isDirectory];
}

- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)col byItem:(id)item {
    return [(WSNode *)item path].lastPathComponent;
}

@end

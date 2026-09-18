#import "DockingManager.h"
#import "SettingsCommands.h"

NSNotificationName const NppDockPanelVisibilityDidChangeNotification = @"NppDockPanelVisibilityDidChange";

static const CGFloat kHeader = 22;

@interface NppDockPanelRecord : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSView *view;
@property (nonatomic) NppDockPlace place;
@property (nonatomic) NppDockPlace lastDockedPlace;
@property (nonatomic) BOOL visible;
@property (nonatomic) NSRect floatFrame;
@end
@implementation NppDockPanelRecord
@end

@class NppDockContainerView;

@interface NppDockingManager () <NSWindowDelegate, NSSplitViewDelegate>
@property (nonatomic, weak) NSSplitView *split;
@property (nonatomic, strong) NSSplitView *centerSplit;
@property (nonatomic, weak) NSView *center;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppDockPanelRecord *> *records;
@property (nonatomic, strong) NSMutableArray<NSString *> *order;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NppDockContainerView *> *containers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSPanel *> *floats;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *fronts;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *sizes;
@property (nonatomic) BOOL arranging;
- (void)containerClickedPanel:(NSString *)identifier;
- (void)dragOfPanel:(NSString *)identifier endedAtScreenPoint:(NSPoint)point;
- (NSMenu *)menuForPanel:(NSString *)identifier;
- (NSString *)titleOf:(NSString *)identifier;
@end

#pragma mark - Container

/// One container: the panels in it as tabs along the top, the one in front below.
@interface NppDockContainerView : NSView
@property (nonatomic) NppDockPlace place;
@property (nonatomic, weak) NppDockingManager *manager;
@property (nonatomic, copy) NSArray<NSString *> *panels;
@property (nonatomic, copy, nullable) NSString *front;
@property (nonatomic, copy, nullable) NSString *dragging;
@property (nonatomic) NSPoint dragStart;
@property (nonatomic) BOOL dragMoved;
@end

@implementation NppDockContainerView

- (BOOL)isFlipped { return YES; }

- (NSArray<NSValue *> *)tabRects {
    NSMutableArray *rects = [NSMutableArray array];
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:11]};
    // Each tab as wide as its title, all of them squeezed alike to leave
    // room for the close button when they do not fit.
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    CGFloat total = 0;
    for (NSString *p in self.panels) {
        CGFloat w = MIN(180, [[self.manager titleOf:p] sizeWithAttributes:attrs].width + 18);
        [widths addObject:@(w)];
        total += w + 2;
    }
    CGFloat room = NSWidth(self.bounds) - 4 - 26;
    CGFloat scale = (total > room && total > 0) ? room / total : 1;
    CGFloat x = 4;
    for (NSNumber *w in widths) {
        CGFloat width = floor(w.doubleValue * scale);
        [rects addObject:[NSValue valueWithRect:NSMakeRect(x, 2, width, kHeader - 4)]];
        x += width + 2;
    }
    return rects;
}

- (NSRect)closeRect { return NSMakeRect(NSWidth(self.bounds) - 20, 4, 14, 14); }

- (void)drawRect:(NSRect)dirty {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(0, kHeader - 1, NSWidth(self.bounds), 1));
    NSArray *rects = [self tabRects];
    for (NSUInteger i = 0; i < self.panels.count; ++i) {
        NSRect r = [rects[i] rectValue];
        BOOL front = [self.panels[i] isEqualToString:self.front];
        if (front) {
            [[NSColor controlBackgroundColor] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];
        }
        NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
        para.lineBreakMode = NSLineBreakByTruncatingTail;
        NSDictionary *attrs = @{NSFontAttributeName: front ? [NSFont boldSystemFontOfSize:11] : [NSFont systemFontOfSize:11],
                                NSForegroundColorAttributeName: front ? [NSColor labelColor] : [NSColor secondaryLabelColor],
                                NSParagraphStyleAttributeName: para};
        [[self.manager titleOf:self.panels[i]] drawInRect:NSInsetRect(r, 8, 2) withAttributes:attrs];
    }
    NSImage *x = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"];
    [x drawInRect:[self closeRect] fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.6];
}

- (nullable NSString *)panelAtPoint:(NSPoint)p {
    NSArray *rects = [self tabRects];
    for (NSUInteger i = 0; i < rects.count; ++i) if (NSPointInRect(p, [rects[i] rectValue])) return self.panels[i];
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, [self closeRect])) { if (self.front) [self.manager hidePanel:self.front]; return; }
    NSString *hit = [self panelAtPoint:p];
    if (!hit) return;
    if (event.clickCount == 2) {
        // A double click floats a docked panel and docks a floating one back.
        NppDockPlace now = [self.manager placeOfPanel:hit];
        [self.manager movePanel:hit to:now == NppDockFloating ? NppDockPlace(-1) : NppDockFloating];
        return;
    }
    [self.manager containerClickedPanel:hit];
    self.dragging = hit;
    self.dragStart = p;
    self.dragMoved = NO;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragging) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (hypot(p.x - self.dragStart.x, p.y - self.dragStart.y) > 12) {
        self.dragMoved = YES;
        [[NSCursor closedHandCursor] set];
    }
}

- (void)mouseUp:(NSEvent *)event {
    NSString *moved = self.dragMoved ? self.dragging : nil;
    self.dragging = nil;
    [[NSCursor arrowCursor] set];
    if (!moved) return;
    NSPoint screen = [self.window convertPointToScreen:event.locationInWindow];
    // Let go on its own tab strip: nothing to do.
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(local, NSMakeRect(0, 0, NSWidth(self.bounds), kHeader))) return;
    [self.manager dragOfPanel:moved endedAtScreenPoint:screen];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSString *hit = [self panelAtPoint:[self convertPoint:event.locationInWindow fromView:nil]] ?: self.front;
    return hit ? [self.manager menuForPanel:hit] : nil;
}

@end

#pragma mark - Manager

@implementation NppDockingManager

+ (instancetype)shared {
    static NppDockingManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[NppDockingManager alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _records = [NSMutableDictionary dictionary];
    _order = [NSMutableArray array];
    _containers = [NSMutableDictionary dictionary];
    _floats = [NSMutableDictionary dictionary];
    _fronts = [NSMutableDictionary dictionary];
    _sizes = [@{@(NppDockLeft): @240, @(NppDockRight): @240, @(NppDockTop): @160, @(NppDockBottom): @200} mutableCopy];
    NSDictionary *stored = [NppPreferences shared].dockLayout[@"sizes"];
    for (NSString *key in stored) {
        if ([stored[key] doubleValue] >= 60) self.sizes[@(key.integerValue)] = stored[key];
    }
    return self;
}

- (void)attachToSplit:(NSSplitView *)split center:(NSView *)center {
    self.split = split;
    self.center = center;
    self.centerSplit = [[NSSplitView alloc] initWithFrame:center.frame];
    self.centerSplit.vertical = NO;
    self.centerSplit.dividerStyle = NSSplitViewDividerStyleThin;
    self.centerSplit.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.centerSplit.delegate = self;
    split.delegate = self;
    NSMutableArray *subviews = [split.subviews mutableCopy];
    NSUInteger at = [subviews indexOfObjectIdenticalTo:center];
    if (at == NSNotFound) [subviews addObject:self.centerSplit];
    else subviews[at] = self.centerSplit;
    split.subviews = subviews;
    self.centerSplit.subviews = @[center];
    [self arrange];
}

- (NSString *)titleOf:(NSString *)identifier { return self.records[identifier].title ?: identifier; }

- (void)registerPanel:(NSString *)identifier title:(NSString *)title view:(NSView *)view
         defaultPlace:(NppDockPlace)place {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r) {
        r = [[NppDockPanelRecord alloc] init];
        r.identifier = identifier;
        NSDictionary *layout = [NppPreferences shared].dockLayout;
        NSNumber *remembered = layout[@"places"][identifier];
        r.place = remembered ? (NppDockPlace)remembered.integerValue : place;
        NSNumber *docked = layout[@"docked"][identifier];
        r.lastDockedPlace = docked ? (NppDockPlace)docked.integerValue : (place == NppDockFloating ? NppDockRight : place);
        NSString *frame = layout[@"floating"][identifier];
        r.floatFrame = frame ? NSRectFromString(frame) : NSMakeRect(200, 200, 300, 400);
        self.records[identifier] = r;
        [self.order addObject:identifier];
    }
    r.title = title;
    r.view = view;
}

- (BOOL)hasPanel:(NSString *)identifier { return self.records[identifier] != nil; }
- (BOOL)isPanelVisible:(NSString *)identifier { return self.records[identifier].visible; }
- (NppDockPlace)placeOfPanel:(NSString *)identifier { return self.records[identifier].place; }
- (CGFloat)sizeOfPlace:(NppDockPlace)place { return self.sizes[@(place)].doubleValue; }

- (NSArray<NSString *> *)panelsIn:(NppDockPlace)place {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *ident in self.order) {
        NppDockPanelRecord *r = self.records[ident];
        if (r.visible && r.place == place) [out addObject:ident];
    }
    return out;
}

- (NSString *)frontPanelIn:(NppDockPlace)place {
    NSArray *panels = [self panelsIn:place];
    NSString *front = self.fronts[@(place)];
    return [panels containsObject:front] ? front : panels.lastObject;
}

- (void)showPanel:(NSString *)identifier {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r) return;
    BOOL was = r.visible;
    r.visible = YES;
    if (r.place != NppDockFloating) self.fronts[@(r.place)] = identifier;
    [self arrange];
    if (!was) [[NSNotificationCenter defaultCenter] postNotificationName:NppDockPanelVisibilityDidChangeNotification object:identifier];
}

- (void)hidePanel:(NSString *)identifier {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r || !r.visible) return;
    r.visible = NO;
    [self arrange];
    [[NSNotificationCenter defaultCenter] postNotificationName:NppDockPanelVisibilityDidChangeNotification object:identifier];
}

- (void)togglePanel:(NSString *)identifier {
    if ([self isPanelVisible:identifier]) [self hidePanel:identifier];
    else [self showPanel:identifier];
}

- (void)movePanel:(NSString *)identifier to:(NppDockPlace)place {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r) return;
    // -1: back where it was last docked.
    if ((NSInteger)place < 0) place = r.lastDockedPlace;
    if (r.place == NppDockFloating) {
        NSPanel *window = self.floats[identifier];
        if (window) r.floatFrame = window.frame;
    }
    r.place = place;
    if (place != NppDockFloating) r.lastDockedPlace = place;
    r.visible = YES;
    if (place != NppDockFloating) self.fronts[@(place)] = identifier;
    [self arrange];
    [self saveLayout];
}

- (void)containerClickedPanel:(NSString *)identifier {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r || r.place == NppDockFloating) return;
    self.fronts[@(r.place)] = identifier;
    [self arrange];
}

- (NppDockPlace)placeForDropAtScreenPoint:(NSPoint)point {
    NSWindow *window = self.split.window;
    if (!window || !NSPointInRect(point, window.frame)) return NppDockFloating;
    NSRect f = window.frame;
    CGFloat fx = (point.x - NSMinX(f)) / MAX(1, NSWidth(f));
    CGFloat fy = (NSMaxY(f) - point.y) / MAX(1, NSHeight(f));   // from the top
    if (fx < 0.25) return NppDockLeft;
    if (fx > 0.75) return NppDockRight;
    if (fy < 0.25) return NppDockTop;
    if (fy > 0.75) return NppDockBottom;
    return NppDockFloating;
}

- (void)dragOfPanel:(NSString *)identifier endedAtScreenPoint:(NSPoint)point {
    NppDockPlace place = [self placeForDropAtScreenPoint:point];
    if (place == NppDockFloating) {
        NppDockPanelRecord *r = self.records[identifier];
        NSRect frame = r.floatFrame;
        frame.origin = NSMakePoint(point.x - 40, point.y - NSHeight(frame) + 10);
        r.floatFrame = frame;
        if (r.place == NppDockFloating) { [self.floats[identifier] setFrame:frame display:YES]; [self saveLayout]; return; }
    }
    [self movePanel:identifier to:place];
}

- (NSMenu *)menuForPanel:(NSString *)identifier {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:[self titleOf:identifier]];
    NSArray *choices = @[@[@"Dock Left", @(NppDockLeft)], @[@"Dock Right", @(NppDockRight)],
                         @[@"Dock Top", @(NppDockTop)], @[@"Dock Bottom", @(NppDockBottom)],
                         @[@"Float", @(NppDockFloating)]];
    NppDockPlace now = [self placeOfPanel:identifier];
    for (NSArray *c in choices) {
        NSMenuItem *item = [menu addItemWithTitle:c[0] action:@selector(menuMove:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = @[identifier, c[1]];
        item.state = [c[1] integerValue] == now ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *close = [menu addItemWithTitle:@"Close" action:@selector(menuClose:) keyEquivalent:@""];
    close.target = self;
    close.representedObject = identifier;
    return menu;
}

- (void)menuMove:(NSMenuItem *)item { [self movePanel:item.representedObject[0] to:(NppDockPlace)[item.representedObject[1] integerValue]]; }
- (void)menuClose:(NSMenuItem *)item { [self hidePanel:item.representedObject]; }

#pragma mark Arranging

- (NppDockContainerView *)containerFor:(NppDockPlace)place {
    NppDockContainerView *c = self.containers[@(place)];
    if (!c) {
        c = [[NppDockContainerView alloc] initWithFrame:NSMakeRect(0, 0, 240, 240)];
        c.place = place;
        c.manager = self;
        self.containers[@(place)] = c;
    }
    return c;
}

/// Puts every shown panel in its container or window, the containers around
/// the editor, and each container at its remembered size.
- (void)arrange {
    if (!self.split || self.arranging) return;
    self.arranging = YES;
    for (NSNumber *placeKey in @[@(NppDockLeft), @(NppDockRight), @(NppDockTop), @(NppDockBottom)]) {
        NppDockPlace place = (NppDockPlace)placeKey.integerValue;
        NppDockContainerView *c = [self containerFor:place];
        NSArray *panels = [self panelsIn:place];
        NSString *front = [self frontPanelIn:place];
        c.panels = panels;
        c.front = front;
        // Only the panel in front is in the view tree, as a tab control shows it.
        for (NSView *sub in [c.subviews copy]) [sub removeFromSuperview];
        if (front) {
            NSView *v = self.records[front].view;
            [v removeFromSuperview];
            v.frame = NSMakeRect(0, kHeader, NSWidth(c.bounds), MAX(0, NSHeight(c.bounds) - kHeader));
            v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [c addSubview:v];
        }
        [c setNeedsDisplay:YES];
    }
    // Floating windows.
    for (NSString *ident in self.order) {
        NppDockPanelRecord *r = self.records[ident];
        NSPanel *window = self.floats[ident];
        if (r.visible && r.place == NppDockFloating) {
            if (!window) {
                window = [[NSPanel alloc] initWithContentRect:r.floatFrame
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
                                                      backing:NSBackingStoreBuffered defer:YES];
                window.releasedWhenClosed = NO;
                window.floatingPanel = YES;
                window.delegate = self;
                window.title = r.title;
                self.floats[ident] = window;
                [window setFrame:r.floatFrame display:NO];
            }
            NppDockContainerView *holder = [[NppDockContainerView alloc] initWithFrame:[window contentRectForFrameRect:window.frame]];
            holder.place = NppDockFloating;
            holder.manager = self;
            holder.panels = @[ident];
            holder.front = ident;
            [r.view removeFromSuperview];
            r.view.frame = NSMakeRect(0, kHeader, NSWidth(holder.bounds), MAX(0, NSHeight(holder.bounds) - kHeader));
            r.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [holder addSubview:r.view];
            holder.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            window.contentView = holder;
            [window orderFront:nil];
        } else if (window) {
            r.floatFrame = window.frame;
            window.delegate = nil;
            [window orderOut:nil];
            [self.floats removeObjectForKey:ident];
        }
        if (!r.visible) [r.view removeFromSuperview];
    }
    // The containers that have something, around the editor.
    NSMutableArray *row = [NSMutableArray array];
    if ([self panelsIn:NppDockLeft].count) [row addObject:[self containerFor:NppDockLeft]];
    [row addObject:self.centerSplit];
    if ([self panelsIn:NppDockRight].count) [row addObject:[self containerFor:NppDockRight]];
    NSMutableArray *column = [NSMutableArray array];
    if ([self panelsIn:NppDockTop].count) [column addObject:[self containerFor:NppDockTop]];
    if (self.center) [column addObject:self.center];
    if ([self panelsIn:NppDockBottom].count) [column addObject:[self containerFor:NppDockBottom]];
    // The split may hold other views the editor put there; they are kept, in front of the row.
    NSMutableArray *others = [NSMutableArray array];
    for (NSView *v in self.split.subviews) {
        if (v != self.centerSplit && ![self.containers.allValues containsObject:(NppDockContainerView *)v]) [others addObject:v];
    }
    NSArray *wantedRow = [others arrayByAddingObjectsFromArray:row];
    if (![self.split.subviews isEqualToArray:wantedRow]) self.split.subviews = wantedRow;
    if (![self.centerSplit.subviews isEqualToArray:column]) self.centerSplit.subviews = column;
    [self.split adjustSubviews];
    [self.centerSplit adjustSubviews];
    // Sizes: the side containers by width, the others by height.
    CGFloat width = NSWidth(self.split.bounds), height = NSHeight(self.centerSplit.bounds);
    NSUInteger leftIndex = [self.split.subviews indexOfObject:[self containerFor:NppDockLeft]];
    NSUInteger rightIndex = [self.split.subviews indexOfObject:[self containerFor:NppDockRight]];
    if (leftIndex != NSNotFound) [self.split setPosition:NSMinX(self.split.subviews[leftIndex].frame) + [self sizeOfPlace:NppDockLeft] ofDividerAtIndex:(NSInteger)leftIndex];
    if (rightIndex != NSNotFound && rightIndex > 0) [self.split setPosition:width - [self sizeOfPlace:NppDockRight] ofDividerAtIndex:(NSInteger)rightIndex - 1];
    NSUInteger topIndex = [self.centerSplit.subviews indexOfObject:[self containerFor:NppDockTop]];
    NSUInteger bottomIndex = [self.centerSplit.subviews indexOfObject:[self containerFor:NppDockBottom]];
    if (topIndex != NSNotFound) [self.centerSplit setPosition:[self sizeOfPlace:NppDockTop] ofDividerAtIndex:(NSInteger)topIndex];
    if (bottomIndex != NSNotFound && bottomIndex > 0) [self.centerSplit setPosition:height - [self sizeOfPlace:NppDockBottom] ofDividerAtIndex:(NSInteger)bottomIndex - 1];
    self.arranging = NO;
}

#pragma mark Remembering

- (void)saveLayout {
    NSMutableDictionary *places = [NSMutableDictionary dictionary], *docked = [NSMutableDictionary dictionary];
    NSMutableDictionary *floating = [NSMutableDictionary dictionary], *sizes = [NSMutableDictionary dictionary];
    for (NSString *ident in self.order) {
        NppDockPanelRecord *r = self.records[ident];
        places[ident] = @(r.place);
        docked[ident] = @(r.lastDockedPlace);
        NSPanel *window = self.floats[ident];
        floating[ident] = NSStringFromRect(window ? window.frame : r.floatFrame);
    }
    for (NSNumber *place in self.sizes) sizes[place.stringValue] = self.sizes[place];
    [NppPreferences shared].dockLayout = @{@"places": places, @"docked": docked, @"floating": floating, @"sizes": sizes};
}

/// A divider dragged: the container's new size is kept.
- (void)splitViewDidResizeSubviews:(NSNotification *)note {
    if (self.arranging) return;
    for (NSNumber *placeKey in @[@(NppDockLeft), @(NppDockRight), @(NppDockTop), @(NppDockBottom)]) {
        NppDockContainerView *c = self.containers[placeKey];
        if (!c.superview || c.hidden) continue;
        BOOL side = placeKey.integerValue == NppDockLeft || placeKey.integerValue == NppDockRight;
        CGFloat size = side ? NSWidth(c.frame) : NSHeight(c.frame);
        if (size >= 60) self.sizes[placeKey] = @(size);
    }
    [self saveLayout];
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview { return NO; }

- (BOOL)windowShouldClose:(NSWindow *)window {
    for (NSString *ident in self.floats) {
        if (self.floats[ident] == window) { [self hidePanel:ident]; break; }
    }
    return NO;
}

- (void)windowDidMove:(NSNotification *)note { [self saveLayout]; }
- (void)windowDidResize:(NSNotification *)note { [self saveLayout]; }

@end

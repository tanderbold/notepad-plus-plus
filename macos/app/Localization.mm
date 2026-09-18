#import "Localization.h"
#import <objc/runtime.h>

@interface NppLocalization ()
@property (nonatomic, readwrite, copy, nullable) NSString *languageFile;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *commands;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *menuNames;      // menuId / subMenuId -> text
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *englishMenuIds;  // english name -> menuId / subMenuId
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *strings;        // normalised english -> text
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *titles;         // dialog and tab titles
@end

/// The English an object showed before it was translated, so a language can
/// be changed back and forth and the originals are never lost.
static NSMapTable *gOriginals;

static NSMapTable *Originals(void) {
    if (!gOriginals) gOriginals = [NSMapTable weakToStrongObjectsMapTable];
    return gOriginals;
}

static NSString *Original(id object, NSString *key, NSString *now) {
    NSMutableDictionary *d = [Originals() objectForKey:object];
    if (!d) { d = [NSMutableDictionary dictionary]; [Originals() setObject:d forKey:object]; }
    if (!d[key] && now) d[key] = now;
    return d[key] ?: now;
}

NSString *NppEnglishTitle(NSMenuItem *item) {
    NSDictionary *d = [Originals() objectForKey:item];
    return d[@"title"] ?: item.title ?: @"";
}

NSString *NppEnglishMenuTitle(NSMenu *menu) {
    NSDictionary *d = [Originals() objectForKey:menu];
    return d[@"title"] ?: menu.title ?: @"";
}

NSString *NppL(NSString *english) { return [[NppLocalization shared] translate:english]; }

/// Upstream's strings carry & before the access key; && is a literal &.
static NSString *WithoutAccessKeys(NSString *s) {
    if ([s rangeOfString:@"&"].location == NSNotFound) return s;
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; ++i) {
        unichar c = [s characterAtIndex:i];
        if (c == '&') {
            if (i + 1 < s.length && [s characterAtIndex:i + 1] == '&') { [out appendString:@"&"]; ++i; }
            continue;
        }
        [out appendFormat:@"%C", c];
    }
    return out;
}

/// The key an English string is looked up by: no access keys, no shortcut
/// after a tab, no trailing colon or ellipsis, case and spaces aside.
static NSString *Normalised(NSString *s) {
    NSString *t = WithoutAccessKeys(s ?: @"");
    NSRange tab = [t rangeOfString:@"\t"];
    if (tab.location != NSNotFound) t = [t substringToIndex:tab.location];
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([t hasSuffix:@":"] || [t hasSuffix:@"…"] || [t hasSuffix:@"."]) {
        t = [[t substringToIndex:t.length - 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return t.lowercaseString;
}

/// A push button keeps its English width, or grows to its translated title
/// when the room beside it is free; otherwise the title is cut on one line.
static void FitPushButton(NSButton *b) {
    NSString *w = Original(b, @"width", [NSString stringWithFormat:@"%g", b.frame.size.width]);
    NSRect frame = b.frame;
    frame.size.width = w.doubleValue;
    CGFloat wanted = ceil(b.cell.cellSize.width);
    b.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    b.cell.usesSingleLineMode = YES;
    if (wanted > frame.size.width) {
        NSRect grown = frame;
        grown.size.width = wanted;
        BOOL free = !b.superview || NSMaxX(grown) <= NSWidth(b.superview.bounds);
        for (NSView *other in b.superview.subviews) {
            if (other == b || other.hidden != b.hidden || !free) continue;   // views of one tab
            if (NSIntersectsRect(NSInsetRect(other.frame, 1, 1), grown) && !NSIntersectsRect(other.frame, frame)) free = NO;
        }
        if (free) frame = grown;
    }
    b.frame = frame;
}

@implementation NppLocalization

+ (instancetype)shared {
    static NppLocalization *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[NppLocalization alloc] init]; });
    return shared;
}

+ (NSString *)directory { return [[NSBundle mainBundle] pathForResource:@"nativeLang" ofType:nil]; }

+ (NSDictionary<NSString *, NSString *> *)availableLanguages {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self directory] error:NULL]) {
        if (![file.pathExtension isEqualToString:@"xml"]) continue;
        // Only the <Native-Langue ...> tag is decoded: a fixed-length head can
        // end inside a multi-byte character, and then nothing decodes.
        NSData *data = [[NSFileHandle fileHandleForReadingAtPath:
                            [[self directory] stringByAppendingPathComponent:file]] readDataOfLength:4096];
        NSRange tag = data ? [data rangeOfData:[@"<Native-Langue" dataUsingEncoding:NSUTF8StringEncoding]
                                       options:0 range:NSMakeRange(0, data.length)] : NSMakeRange(NSNotFound, 0);
        NSString *head = @"";
        if (tag.location != NSNotFound) {
            NSRange close = [data rangeOfData:[@">" dataUsingEncoding:NSUTF8StringEncoding] options:0
                                        range:NSMakeRange(tag.location, data.length - tag.location)];
            if (close.location != NSNotFound) {
                head = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(tag.location, NSMaxRange(close) - tag.location)]
                                             encoding:NSUTF8StringEncoding] ?: @"";
            }
        }
        NSRange r = [head rangeOfString:@"name=\""];
        NSString *name = file.stringByDeletingPathExtension;
        if (r.location != NSNotFound) {
            NSRange end = [head rangeOfString:@"\"" options:0 range:NSMakeRange(NSMaxRange(r), head.length - NSMaxRange(r))];
            if (end.location != NSNotFound) name = [head substringWithRange:NSMakeRange(NSMaxRange(r), end.location - NSMaxRange(r))];
        }
        out[file] = name;
    }
    return out;
}

- (BOOL)active { return self.strings.count > 0; }

/// Every translatable value of a file, by where it is: the element path with
/// the attribute that tells siblings apart, then the attribute's name.
static NSDictionary<NSString *, NSString *> *Flatten(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSXMLDocument *doc = data ? [[NSXMLDocument alloc] initWithData:data options:0 error:NULL] : nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (!doc) return out;
    NSArray *keys = @[@"id", @"menuId", @"subMenuId", @"CMID", @"CMDID", @"idName"];
    __block void (^walk)(NSXMLElement *, NSString *) = nil;
    void (^__block __weak weakWalk)(NSXMLElement *, NSString *);
    walk = ^(NSXMLElement *e, NSString *prefix) {
        NSString *ident = nil;
        for (NSString *k in keys) { NSString *v = [[e attributeForName:k] stringValue]; if (v) { ident = [NSString stringWithFormat:@"%@=%@", k, v]; break; } }
        NSString *here = [NSString stringWithFormat:@"%@/%@%@", prefix, e.name, ident ? [NSString stringWithFormat:@"[%@]", ident] : @""];
        for (NSXMLNode *a in e.attributes) {
            if ([keys containsObject:a.name] || [a.name isEqualToString:@"filename"] || [a.name isEqualToString:@"version"]) continue;
            out[[NSString stringWithFormat:@"%@@%@", here, a.name]] = a.stringValue ?: @"";
        }
        for (NSXMLNode *child in e.children) if ([child isKindOfClass:[NSXMLElement class]]) weakWalk((NSXMLElement *)child, here);
    };
    weakWalk = walk;
    NSXMLElement *root = [[doc rootElement] elementsForName:@"Native-Langue"].firstObject ?: doc.rootElement;
    walk(root, @"");
    return out;
}

- (BOOL)loadLanguageFile:(NSString *)fileName {
    self.commands = [NSMutableDictionary dictionary];
    self.menuNames = [NSMutableDictionary dictionary];
    self.englishMenuIds = [NSMutableDictionary dictionary];
    self.strings = [NSMutableDictionary dictionary];
    self.titles = [NSMutableDictionary dictionary];
    self.languageFile = nil;
    if (!fileName.length || [fileName isEqualToString:@"english.xml"]) return YES;
    NSString *dir = [NppLocalization directory];
    NSString *path = [dir stringByAppendingPathComponent:fileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    NSDictionary *english = Flatten([dir stringByAppendingPathComponent:@"english.xml"]);
    NSDictionary *native = Flatten(path);
    // Dialog texts first: "Replace" is the dialog's button before it is the
    // menu's "Replace..." command.
    NSArray *ordered = [native.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL da = [a hasPrefix:@"/Native-Langue/Dialog/"], db = [b hasPrefix:@"/Native-Langue/Dialog/"];
        if (da != db) return da ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];
    for (NSString *key in ordered) {
        NSString *text = native[key];
        NSString *en = english[key];
        // Menu commands by id, menus and submenus by their upstream ids.
        NSRange cmd = [key rangeOfString:@"/Commands/Item[id="];
        if (cmd.location == NSNotFound) cmd = [key rangeOfString:@"/TabBar/Item[CMDID="];
        if ([key hasPrefix:@"/Native-Langue/Menu/"] && cmd.location != NSNotFound && [key hasSuffix:@"@name"]) {
            NSString *idPart = [key substringFromIndex:NSMaxRange(cmd)];
            self.commands[@([idPart intValue])] = WithoutAccessKeys(text);
        }
        for (NSString *kind in @[@"menuId=", @"subMenuId="]) {
            NSRange r = [key rangeOfString:kind];
            if ([key hasPrefix:@"/Native-Langue/Menu/Main/"] && r.location != NSNotFound && [key hasSuffix:@"@name"]) {
                NSString *ident = [key substringWithRange:NSMakeRange(NSMaxRange(r), [key rangeOfString:@"]" options:0 range:NSMakeRange(NSMaxRange(r), key.length - NSMaxRange(r))].location - NSMaxRange(r))];
                self.menuNames[ident] = WithoutAccessKeys(text);
                if (en.length) self.englishMenuIds[Normalised(en)] = ident;
            }
        }
        // A window's or a tab's name: "Replace" is "Замена" there, "Заменить" on a button.
        NSRange at = [key rangeOfString:@"@" options:NSBackwardsSearch];
        if ([key hasPrefix:@"/Native-Langue/Dialog/"] && at.location != NSNotFound
            && [[key substringFromIndex:at.location + 1] hasPrefix:@"title"]
            && en.length && text.length && !self.titles[Normalised(en)]) {
            self.titles[Normalised(en)] = text;
        }
        if (en.length && text.length && ![en isEqualToString:text] && !self.strings[Normalised(en)]) {
            self.strings[Normalised(en)] = text;
        }
    }
    self.languageFile = fileName;
    return YES;
}

- (NSString *)commandName:(int)identifier { return self.commands[@(identifier)]; }

- (NSString *)translate:(NSString *)english {
    return [self translate:english hit:self.strings[Normalised(english ?: @"")]];
}

- (NSString *)translateTitle:(NSString *)english {
    NSString *key = Normalised(english ?: @"");
    return [self translate:english hit:self.titles[key] ?: self.strings[key]];
}

- (NSString *)translate:(NSString *)english hit:(NSString *)hit {
    if (!english.length || !self.strings.count) return english ?: @"";
    if (!hit) return english;
    NSString *text = WithoutAccessKeys(hit);
    // Upstream breaks long button texts over two lines; a Mac button has one.
    text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    NSRange tab = [text rangeOfString:@"\t"];
    if (tab.location != NSNotFound) text = [text substringToIndex:tab.location];
    // The English form's colon or ellipsis goes on the translation, and only then.
    NSString *trimmed = [english stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL englishColon = [trimmed hasSuffix:@":"];
    BOOL englishDots = [trimmed hasSuffix:@"…"] || [trimmed hasSuffix:@"..."];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    while (!englishDots && ([text hasSuffix:@"…"] || [text hasSuffix:@"..."])) {
        text = [[text substringToIndex:text.length - ([text hasSuffix:@"…"] ? 1 : 3)]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    while (!englishColon && [text hasSuffix:@":"]) {
        text = [[text substringToIndex:text.length - 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    if ([trimmed hasSuffix:@":"] && ![text hasSuffix:@":"]) text = [text stringByAppendingString:@":"];
    if (([trimmed hasSuffix:@"…"] || [trimmed hasSuffix:@"..."]) && ![text hasSuffix:@"…"] && ![text hasSuffix:@"..."]) {
        text = [text stringByAppendingString:@"…"];
    }
    return text;
}

#pragma mark Menus

- (void)localizeMenu:(NSMenu *)menu identifiers:(NSDictionary<NSNumber *, NSMenuItem *> *)ids {
    NSMapTable *byItem = [NSMapTable weakToStrongObjectsMapTable];
    for (NSNumber *identifier in ids) [byItem setObject:identifier forKey:ids[identifier]];
    [self localizeMenu:menu byItem:byItem top:YES];
}

- (void)localizeMenu:(NSMenu *)menu byItem:(NSMapTable *)byItem top:(BOOL)top {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) continue;
        NSString *english = Original(item, @"title", item.title);
        NSString *text = nil;
        if (item.submenu) {
            NSString *englishMenu = Original(item.submenu, @"title", item.submenu.title);
            NSString *ident = self.englishMenuIds[Normalised(english)] ?: self.englishMenuIds[Normalised(englishMenu)];
            // The application menu keeps its name.
            if (top && menu.itemArray.firstObject == item) ident = nil, text = english;
            text = text ?: (ident ? self.menuNames[ident] : nil) ?: [self translate:english];
            item.submenu.title = self.active ? text : englishMenu;
            [self localizeMenu:item.submenu byItem:byItem top:NO];
        } else {
            NSNumber *identifier = [byItem objectForKey:item];
            text = identifier ? [self commandName:identifier.intValue] : nil;
            text = text ?: [self translate:english];
        }
        item.title = self.active ? text : english;
    }
}

#pragma mark Windows

- (void)localizeWindow:(NSWindow *)window {
    if (!window) return;
    NSString *english = Original(window, @"title", window.title);
    window.title = [self translateTitle:english];
    if (window.contentView) [self localizeView:window.contentView];
}

- (void)localizeView:(NSView *)view {
    if ([view isKindOfClass:[NSButton class]] && ![view isKindOfClass:[NSPopUpButton class]]) {
        // (A pop-up's setTitle: selects or adds an item; its items are done below.)
        NSButton *b = (NSButton *)view;
        if (b.title.length) {
            b.title = [self translate:Original(b, @"title", b.title)];
            if (b.bezelStyle == NSBezelStyleRounded) FitPushButton(b);
        }
    }
    if ([view isKindOfClass:[NSPopUpButton class]]) {
        for (NSMenuItem *item in ((NSPopUpButton *)view).itemArray) {
            item.title = [self translate:Original(item, @"title", item.title)];
        }
    } else if ([view isKindOfClass:[NSSegmentedControl class]]) {
        NSSegmentedControl *s = (NSSegmentedControl *)view;
        for (NSInteger i = 0; i < s.segmentCount; ++i) {
            NSString *label = [s labelForSegment:i];
            if (label.length) [s setLabel:[self translateTitle:Original(s, [NSString stringWithFormat:@"seg%ld", (long)i], label)] forSegment:i];
        }
    } else if ([view isKindOfClass:[NSTextField class]] && ![view isKindOfClass:[NSComboBox class]]) {
        NSTextField *f = (NSTextField *)view;
        if (!f.editable && f.stringValue.length) f.stringValue = [self translate:Original(f, @"text", f.stringValue)];
        if (f.placeholderString.length) f.placeholderString = [self translate:Original(f, @"placeholder", f.placeholderString)];
    } else if ([view isKindOfClass:[NSMatrix class]]) {
        for (NSCell *cell in ((NSMatrix *)view).cells) {
            if (cell.title.length) cell.title = [self translate:Original(cell, @"title", cell.title)];
        }
    } else if ([view isKindOfClass:[NSTableView class]]) {
        [(NSTableView *)view reloadData];   // data sources translate what they return
    } else if ([view isKindOfClass:[NSBox class]]) {
        NSBox *b = (NSBox *)view;
        if (b.title.length) b.title = [self translate:Original(b, @"title", b.title)];
    } else if ([view isKindOfClass:[NSTableView class]]) {
        for (NSTableColumn *c in ((NSTableView *)view).tableColumns) {
            if (c.title.length) c.title = [self translate:Original(c, @"title", c.title)];
        }
    }
    for (NSView *sub in view.subviews) [self localizeView:sub];
}

@end

#pragma mark - Message boxes

/// Alerts are translated as they are run, by their English text.
@implementation NSAlert (NppLocalization)

+ (void)load {
    Method original = class_getInstanceMethod(self, @selector(runModal));
    Method replacement = class_getInstanceMethod(self, @selector(npp_runModal));
    method_exchangeImplementations(original, replacement);
}

- (NSModalResponse)npp_runModal {
    NppLocalization *l = [NppLocalization shared];
    if (l.active) {
        self.messageText = [l translate:self.messageText];
        self.informativeText = [l translate:self.informativeText];
        for (NSButton *b in self.buttons) b.title = [l translate:b.title];
    }
    return [self npp_runModal];
}

@end

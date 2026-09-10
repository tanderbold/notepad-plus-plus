#import "StyleCatalog.h"

@implementation NppStyle
@end

@interface StyleCatalog () <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NppStyle *> *> *byLexer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppStyle *> *globals;
@property (nonatomic, copy, nullable) NSString *currentLexer;
@property (nonatomic) BOOL inGlobals;
@end

@implementation StyleCatalog

+ (instancetype)sharedCatalog {
    static StyleCatalog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[StyleCatalog alloc] init]; });
    return shared;
}

/// "RRGGBB" -> NSColor. Notepad++ stores colours without a leading '#'.
static NSColor *ColorFromHex(NSString *hex) {
    if (hex.length != 6) return nil;
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&v]) return nil;
    return [NSColor colorWithSRGBRed:((v >> 16) & 0xFF) / 255.0
                               green:((v >> 8) & 0xFF) / 255.0
                                blue:(v & 0xFF) / 255.0
                               alpha:1.0];
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _byLexer = [NSMutableDictionary dictionary];
    _globals = [NSMutableDictionary dictionary];

    NSString *path = [[NSBundle mainBundle] pathForResource:@"stylers.model" ofType:@"xml"];
    if (path) {
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[NSData dataWithContentsOfFile:path]];
        parser.delegate = self;
        [parser parse];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {

    if ([element isEqualToString:@"LexerType"]) {
        self.currentLexer = attrs[@"name"];
        if (self.currentLexer && !self.byLexer[self.currentLexer]) {
            self.byLexer[self.currentLexer] = [NSMutableArray array];
        }
        return;
    }
    if ([element isEqualToString:@"GlobalStyles"]) { self.inGlobals = YES; return; }

    BOOL isStyle = [element isEqualToString:@"WordsStyle"] || [element isEqualToString:@"WidgetStyle"];
    if (!isStyle) return;

    NSString *idStr = attrs[@"styleID"];
    if (!idStr.length) return;

    NppStyle *s = [[NppStyle alloc] init];
    s.styleID = idStr.intValue;
    s.foreground = ColorFromHex(attrs[@"fgColor"] ?: @"");
    s.background = ColorFromHex(attrs[@"bgColor"] ?: @"");
    s.fontStyle = (attrs[@"fontStyle"] ?: @"0").intValue;
    s.fontName = attrs[@"fontName"].length ? attrs[@"fontName"] : nil;
    s.fontSize = (attrs[@"fontSize"] ?: @"0").intValue;
    s.keywordClass = attrs[@"keywordClass"].length ? attrs[@"keywordClass"] : nil;
    s.name = attrs[@"name"];

    if (self.inGlobals) {
        if (s.name.length) self.globals[s.name] = s;
    } else if (self.currentLexer) {
        [self.byLexer[self.currentLexer] addObject:s];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {
    if ([element isEqualToString:@"LexerType"]) self.currentLexer = nil;
    else if ([element isEqualToString:@"GlobalStyles"]) self.inGlobals = NO;
}

- (NSArray<NppStyle *> *)stylesForLexerName:(NSString *)lexerName {
    return self.byLexer[lexerName];
}

- (NSDictionary<NSString *, NppStyle *> *)globalStyles { return self.globals; }

@end

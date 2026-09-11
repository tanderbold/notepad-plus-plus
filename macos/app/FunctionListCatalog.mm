#import "FunctionListCatalog.h"

@implementation NppFunctionEntry
@end

/// One <parser> from a functionList file.
@interface NppFunctionParser : NSObject
@property (nonatomic, copy) NSString *parserID;
@property (nonatomic, copy, nullable) NSString *functionExpr;      // <function mainExpr>
@property (nonatomic, copy, nullable) NSString *functionNameExpr;  // <funcNameExpr expr>
@property (nonatomic, copy, nullable) NSString *classRangeExpr;    // <classRange mainExpr>
@property (nonatomic, copy, nullable) NSString *classNameExpr;     // <className><nameExpr expr>
@property (nonatomic, copy, nullable) NSString *classFunctionExpr;
@property (nonatomic, copy, nullable) NSString *classFunctionNameExpr;
@end

@implementation NppFunctionParser
@end

@interface FunctionListCatalog () <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppFunctionParser *> *parsers;
/// "language:python" or "ext:py" -> parser id
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *associations;
/// The file a parser came from: upstream's association map keys on file names
/// ("cpp.xml"), while each file's parser carries its own id ("cplusplus_syntax").
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *parserIDByFile;
@property (nonatomic, copy, nullable) NSString *currentFileBase;

// parse state
@property (nonatomic, strong, nullable) NppFunctionParser *current;
@property (nonatomic) BOOL inClassRange;
@property (nonatomic) BOOL inClassName;
@property (nonatomic) BOOL inFunctionName;
@end

@implementation FunctionListCatalog

+ (instancetype)sharedCatalog {
    static FunctionListCatalog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[FunctionListCatalog alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _parsers = [NSMutableDictionary dictionary];
    _associations = [NSMutableDictionary dictionary];
    _parserIDByFile = [NSMutableDictionary dictionary];

    NSString *dir = [[NSBundle mainBundle] pathForResource:@"functionList" ofType:nil];
    if (!dir) return self;
    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"xml"]) continue;
        NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:file]];
        if (!data) continue;
        self.currentFileBase = file.stringByDeletingPathExtension.lowercaseString;
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
        parser.delegate = self;
        [parser parse];
    }
    return self;
}

- (NSArray<NSString *> *)parserIDs {
    return [self.parsers.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Pattern translation

/// Upstream's patterns are PCRE. ICU, which NSRegularExpression uses, accepts
/// almost all of it; the exception that matters is \K, which resets the start of
/// the match. Everything after \K is what upstream reports, so the pattern is
/// rewritten to capture exactly that into group 1.
+ (NSString *)icuPatternFrom:(NSString *)pcre {
    if (!pcre.length) return nil;
    NSString *out = pcre;

    NSRange keep = [out rangeOfString:@"\\K" options:NSBackwardsSearch];
    if (keep.location != NSNotFound) {
        // A named group, because these patterns often already contain groups of
        // their own -- python's "(async )?" among them -- so group 1 would be
        // the wrong one to read back.
        out = [NSString stringWithFormat:@"%@(?<nppkeep>%@)",
               [out substringToIndex:keep.location],
               [out substringFromIndex:keep.location + keep.length]];
    }
    // ICU rejects a possessive quantifier on a group in some builds; PCRE's
    // atomic groups are equivalent to plain groups for extraction purposes.
    out = [out stringByReplacingOccurrencesOfString:@"(?>" withString:@"(?:"];
    return out;
}

+ (NSRegularExpression *)expressionFrom:(NSString *)pcre {
    NSString *icu = [self icuPatternFrom:pcre];
    if (!icu.length) return nil;
    // Upstream compiles these with '.' matching newlines, which its classRange
    // patterns depend on to span a class body, and with '^' anchoring per line.
    return [NSRegularExpression regularExpressionWithPattern:icu
                                                     options:(NSRegularExpressionAnchorsMatchLines |
                                                              NSRegularExpressionDotMatchesLineSeparators)
                                                       error:NULL];
}

/// What a pattern reports: the \K group when it had one, otherwise the match.
static NSRange ReportedRange(NSTextCheckingResult *m) {
    NSRange named = [m rangeWithName:@"nppkeep"];
    return named.location != NSNotFound ? named : m.range;
}

static NSString *ReportedText(NSTextCheckingResult *m, NSString *subject) {
    return [subject substringWithRange:ReportedRange(m)];
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {

    if ([element isEqualToString:@"parser"]) {
        NppFunctionParser *p = [[NppFunctionParser alloc] init];
        p.parserID = attrs[@"id"] ?: @"";
        self.current = p;
        self.inClassRange = self.inClassName = self.inFunctionName = NO;
        return;
    }
    if ([element isEqualToString:@"association"]) {
        NSString *target = attrs[@"id"] ?: @"";
        if (attrs[@"langID"]) {
            // langID is a numeric LangType; the language name is the useful key,
            // so the file's own name is used as a fallback association.
            self.associations[[@"lang:" stringByAppendingString:attrs[@"langID"]]] = target;
        }
        if (attrs[@"userDefinedLangName"]) {
            self.associations[[@"language:" stringByAppendingString:
                               attrs[@"userDefinedLangName"].lowercaseString]] = target;
        }
        if (attrs[@"ext"]) {
            NSString *ext = attrs[@"ext"];
            if ([ext hasPrefix:@"."]) ext = [ext substringFromIndex:1];
            self.associations[[@"ext:" stringByAppendingString:ext.lowercaseString]] = target;
        }
        return;
    }
    if (!self.current) return;

    if ([element isEqualToString:@"classRange"]) {
        self.inClassRange = YES;
        self.current.classRangeExpr = attrs[@"mainExpr"];
    } else if ([element isEqualToString:@"className"]) {
        self.inClassName = YES;
    } else if ([element isEqualToString:@"functionName"]) {
        self.inFunctionName = YES;
    } else if ([element isEqualToString:@"function"]) {
        if (self.inClassRange) self.current.classFunctionExpr = attrs[@"mainExpr"];
        else self.current.functionExpr = attrs[@"mainExpr"];
    } else if ([element isEqualToString:@"nameExpr"] && self.inClassName) {
        self.current.classNameExpr = attrs[@"expr"];
    } else if ([element isEqualToString:@"funcNameExpr"]) {
        if (self.inClassRange) self.current.classFunctionNameExpr = attrs[@"expr"];
        else self.current.functionNameExpr = attrs[@"expr"];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {
    if ([element isEqualToString:@"parser"]) {
        if (self.current.parserID.length) {
            self.parsers[self.current.parserID] = self.current;
            if (self.currentFileBase.length && !self.parserIDByFile[self.currentFileBase]) {
                self.parserIDByFile[self.currentFileBase] = self.current.parserID;
            }
        }
        self.current = nil;
    } else if ([element isEqualToString:@"classRange"]) {
        self.inClassRange = NO;
    } else if ([element isEqualToString:@"className"]) {
        self.inClassName = NO;
    } else if ([element isEqualToString:@"functionName"]) {
        self.inFunctionName = NO;
    }
}

#pragma mark - Lookup

- (NSString *)parserIDForLanguage:(NSString *)language extension:(NSString *)ext {
    if (ext.length) {
        NSString *byExt = self.associations[[@"ext:" stringByAppendingString:ext.lowercaseString]];
        if (byExt) return byExt;
    }
    NSString *byName = self.associations[[@"language:" stringByAppendingString:
                                          language.lowercaseString]];
    if (byName) return byName;

    // Upstream names each file after its language, so that is the reliable key.
    NSString *byFile = self.parserIDByFile[language.lowercaseString];
    if (byFile) return byFile;
    if (ext.length) {
        NSString *byExtFile = self.parserIDByFile[ext.lowercaseString];
        if (byExtFile) return byExtFile;
    }

    // Upstream names most parsers "<language>_syntax" or "<language>_function".
    for (NSString *suffix in @[@"_syntax", @"_function", @""]) {
        NSString *candidate = [language.lowercaseString stringByAppendingString:suffix];
        if (self.parsers[candidate]) return candidate;
    }
    return nil;
}

- (NSArray<NppFunctionEntry *> *)entriesInText:(NSString *)text
                                   forLanguage:(NSString *)language
                                     extension:(NSString *)ext {
    NSString *parserID = [self parserIDForLanguage:language extension:ext];
    NppFunctionParser *p = parserID ? self.parsers[parserID] : nil;
    if (!p || !text.length) return @[];

    NSMutableArray *entries = [NSMutableArray array];
    NSRange whole = NSMakeRange(0, text.length);

    NSUInteger (^lineOf)(NSUInteger) = ^NSUInteger(NSUInteger index) {
        return [[text substringToIndex:index] componentsSeparatedByString:@"\n"].count - 1;
    };

    void (^collect)(NSString *, NSString *, NSRange, NSString *) =
        ^(NSString *mainExpr, NSString *nameExpr, NSRange range, NSString *container) {
        NSRegularExpression *re = [FunctionListCatalog expressionFrom:mainExpr];
        if (!re) return;
        [re enumerateMatchesInString:text options:0 range:range
                          usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
            NSString *body = ReportedText(m, text);
            NSString *name = body;
            if (nameExpr.length) {
                NSRegularExpression *nameRe = [FunctionListCatalog expressionFrom:nameExpr];
                NSTextCheckingResult *nm = nameRe
                    ? [nameRe firstMatchInString:body options:0 range:NSMakeRange(0, body.length)]
                    : nil;
                if (nm) name = ReportedText(nm, body);
            }
            name = [name stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!name.length) return;

            NppFunctionEntry *entry = [[NppFunctionEntry alloc] init];
            entry.name = name;
            entry.container = container;
            entry.line = lineOf(ReportedRange(m).location);
            [entries addObject:entry];
        }];
    };

    // Classes first, so their methods are attributed to them.
    NSMutableArray<NSValue *> *classRanges = [NSMutableArray array];
    if (p.classRangeExpr.length) {
        NSRegularExpression *re = [FunctionListCatalog expressionFrom:p.classRangeExpr];
        if (re) {
            [re enumerateMatchesInString:text options:0 range:whole
                              usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                NSRange body = ReportedRange(m);
                NSString *className = [text substringWithRange:body];
                if (p.classNameExpr.length) {
                    NSRegularExpression *nameRe = [FunctionListCatalog expressionFrom:p.classNameExpr];
                    NSTextCheckingResult *nm = nameRe
                        ? [nameRe firstMatchInString:className options:0
                                               range:NSMakeRange(0, className.length)] : nil;
                    className = nm ? ReportedText(nm, className) : @"";
                }
                className = [className stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (className.length) {
                    NppFunctionEntry *entry = [[NppFunctionEntry alloc] init];
                    entry.name = className;
                    entry.line = lineOf(body.location);
                    [entries addObject:entry];
                    [classRanges addObject:[NSValue valueWithRange:body]];
                    if (p.classFunctionExpr.length) {
                        collect(p.classFunctionExpr, p.classFunctionNameExpr, body, className);
                    }
                }
            }];
        }
    }
    if (p.functionExpr.length) collect(p.functionExpr, p.functionNameExpr, whole, nil);

    [entries sortUsingComparator:^NSComparisonResult(NppFunctionEntry *a, NppFunctionEntry *b) {
        if (a.line == b.line) return NSOrderedSame;
        return a.line < b.line ? NSOrderedAscending : NSOrderedDescending;
    }];
    return entries;
}

@end

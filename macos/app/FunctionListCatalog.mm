#import "FunctionListCatalog.h"

@implementation NppFunctionEntry
@end

/// One <parser> from a functionList file.
@interface NppFunctionParser : NSObject
@property (nonatomic, copy) NSString *parserID;
@property (nonatomic, copy, nullable) NSString *commentExpr;       // <parser commentExpr>
@property (nonatomic, copy, nullable) NSString *functionExpr;      // <function mainExpr>
@property (nonatomic, copy, nullable) NSString *classRangeExpr;    // <classRange mainExpr>
@property (nonatomic, copy, nullable) NSString *classOpenSymbol;   // <classRange openSymbole>
@property (nonatomic, copy, nullable) NSString *classCloseSymbol;  // <classRange closeSymbole>
@property (nonatomic, copy, nullable) NSString *classFunctionExpr;
// Upstream lists several name patterns and uses the first that matches, so the
// order matters and all of them have to be kept.
@property (nonatomic, strong) NSMutableArray<NSString *> *functionNameExprs;
@property (nonatomic, strong) NSMutableArray<NSString *> *classNameExprs;
@property (nonatomic, strong) NSMutableArray<NSString *> *classFunctionNameExprs;
@end

@implementation NppFunctionParser
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _functionNameExprs = [NSMutableArray array];
    _classNameExprs = [NSMutableArray array];
    _classFunctionNameExprs = [NSMutableArray array];
    return self;
}
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
        data = [FunctionListCatalog dataPreservingAttributeNewlines:data];
        self.currentFileBase = file.stringByDeletingPathExtension.lowercaseString;
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
        parser.delegate = self;
        [parser parse];
    }
    return self;
}

/// XML says a newline inside an attribute value is the same as a space, and
/// NSXMLParser obeys that. Most of these patterns are written with (?x), where
/// a # comment runs to the end of the line -- so once the newlines are gone the
/// first comment swallows the whole pattern and it matches nothing. Notepad++
/// does not hit this because its own XML reader leaves the newlines alone.
///
/// Turning each newline into a character reference before parsing gets them
/// back: a parser must expand &#10; to a newline and must not then fold it into
/// a space, because only literal whitespace is normalised.
+ (NSData *)dataPreservingAttributeNewlines:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text.length) return data;

    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    BOOL inTag = NO;
    unichar quote = 0;
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        if (quote) {
            if (c == quote) quote = 0;
            else if (c == '\n') { [out appendString:@"&#10;"]; continue; }
            else if (c == '\r') { [out appendString:@"&#13;"]; continue; }
        } else if (inTag && (c == '"' || c == '\'')) {
            quote = c;
        } else if (c == '<') {
            inTag = YES;
        } else if (c == '>') {
            inTag = NO;
        }
        [out appendFormat:@"%C", c];
    }
    return [out dataUsingEncoding:NSUTF8StringEncoding] ?: data;
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
    // Upstream searches with SCFIND_REGEXP | SCFIND_POSIX | SCFIND_REGEXP_DOTMATCHESNL
    // (functionParser.cpp), so '.' matches newlines everywhere -- python's
    // classRange spans a whole class body that way -- and '^' anchors per line.
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
        p.commentExpr = attrs[@"commentExpr"];
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
        // Upstream spells these "openSymbole"/"closeSymbole".
        self.current.classOpenSymbol = attrs[@"openSymbole"];
        self.current.classCloseSymbol = attrs[@"closeSymbole"];
    } else if ([element isEqualToString:@"className"]) {
        self.inClassName = YES;
    } else if ([element isEqualToString:@"functionName"]) {
        self.inFunctionName = YES;
    } else if ([element isEqualToString:@"function"]) {
        if (self.inClassRange) self.current.classFunctionExpr = attrs[@"mainExpr"];
        else self.current.functionExpr = attrs[@"mainExpr"];
    } else if ([element isEqualToString:@"nameExpr"] ||
               [element isEqualToString:@"funcNameExpr"]) {
        // The two spellings mean the same thing; which list an entry belongs to
        // is decided by the element it sits inside, not by its own name. Most
        // of upstream's files use <nameExpr> inside <functionName>.
        NSString *expr = attrs[@"expr"];
        if (!expr.length) return;
        if (self.inClassName) [self.current.classNameExprs addObject:expr];
        else if (self.inFunctionName) {
            if (self.inClassRange) [self.current.classFunctionNameExprs addObject:expr];
            else [self.current.functionNameExprs addObject:expr];
        }
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

/// Narrows `body` down to a name. The patterns are applied one after another,
/// each searching inside what the one before it found -- not as alternatives.
/// That is how upstream reaches "Thing" from "class Thing" in three steps.
static NSString *NarrowToName(NSString *body, NSArray<NSString *> *exprs);

/// Blanks out whatever `commentExpr` matches, keeping the length the same so
/// every offset -- and therefore every line number -- still refers to the same
/// place in the original text.
static NSString *TextWithoutComments(NSString *text, NSString *commentExpr);

- (NSArray<NppFunctionEntry *> *)entriesInText:(NSString *)text
                                   forLanguage:(NSString *)language
                                     extension:(NSString *)ext {
    NSString *parserID = [self parserIDForLanguage:language extension:ext];
    NppFunctionParser *p = parserID ? self.parsers[parserID] : nil;
    if (!p || !text.length) return @[];

    // Matching happens against a copy with the comments blanked out, so a
    // function mentioned in a comment is not reported. Line numbers still come
    // from the same offsets because the blanking preserves length.
    NSString *subject = TextWithoutComments(text, p.commentExpr);

    NSMutableArray *entries = [NSMutableArray array];
    NSRange whole = NSMakeRange(0, subject.length);

    NSUInteger (^lineOf)(NSUInteger) = ^NSUInteger(NSUInteger index) {
        return [[subject substringToIndex:index] componentsSeparatedByString:@"\n"].count - 1;
    };

    void (^collect)(NSString *, NSArray<NSString *> *, NSRange, NSString *) =
        ^(NSString *mainExpr, NSArray<NSString *> *nameExprs, NSRange range, NSString *container) {
        NSRegularExpression *re = [FunctionListCatalog expressionFrom:mainExpr];
        if (!re) return;
        [re enumerateMatchesInString:subject options:0 range:range
                          usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
            NSString *body = ReportedText(m, subject);
            NSString *name = NarrowToName(body, nameExprs) ?: body;
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

    // Classes first, so their methods are attributed to them and are not then
    // reported a second time by the plain function pass.
    NSMutableArray<NSValue *> *classBodies = [NSMutableArray array];
    if (p.classRangeExpr.length) {
        NSRegularExpression *re = [FunctionListCatalog expressionFrom:p.classRangeExpr];
        if (re) {
            [re enumerateMatchesInString:subject options:0 range:whole
                              usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                NSRange header = ReportedRange(m);
                NSString *className = NarrowToName([subject substringWithRange:header],
                                                   p.classNameExprs)
                                      ?: [subject substringWithRange:header];
                className = [className stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (!className.length) return;

                // The pattern only matches as far as the opening brace. The body
                // runs to the brace that closes it, which has to be found by
                // counting -- that is what openSymbole/closeSymbole are for.
                NSRange body = [FunctionListCatalog bodyRangeFrom:header
                                                          inText:subject
                                                            open:p.classOpenSymbol
                                                           close:p.classCloseSymbol];

                NppFunctionEntry *entry = [[NppFunctionEntry alloc] init];
                entry.name = className;
                entry.line = lineOf(header.location);
                [entries addObject:entry];
                [classBodies addObject:[NSValue valueWithRange:body]];
                if (p.classFunctionExpr.length) {
                    collect(p.classFunctionExpr, p.classFunctionNameExprs, body, className);
                }
            }];
        }
    }

    if (p.functionExpr.length) {
        // Anything already covered by a class body has been reported under its
        // class, so the plain pass runs over the gaps between them.
        NSUInteger cursor = 0;
        NSMutableArray<NSValue *> *gaps = [NSMutableArray array];
        for (NSValue *v in classBodies) {
            NSRange b = v.rangeValue;
            if (b.location > cursor) {
                [gaps addObject:[NSValue valueWithRange:NSMakeRange(cursor, b.location - cursor)]];
            }
            cursor = MAX(cursor, NSMaxRange(b));
        }
        if (cursor < subject.length) {
            [gaps addObject:[NSValue valueWithRange:
                             NSMakeRange(cursor, subject.length - cursor)]];
        }
        for (NSValue *v in gaps) collect(p.functionExpr, p.functionNameExprs, v.rangeValue, nil);
    }

    [entries sortUsingComparator:^NSComparisonResult(NppFunctionEntry *a, NppFunctionEntry *b) {
        if (a.line == b.line) return NSOrderedSame;
        return a.line < b.line ? NSOrderedAscending : NSOrderedDescending;
    }];
    return entries;
}

/// Where a class body ends: from the opening symbol the pattern stopped at,
/// forward until the symbols balance.
+ (NSRange)bodyRangeFrom:(NSRange)header inText:(NSString *)text
                    open:(NSString *)openExpr close:(NSString *)closeExpr {
    NSRegularExpression *open = openExpr.length ? [self expressionFrom:openExpr] : nil;
    NSRegularExpression *close = closeExpr.length ? [self expressionFrom:closeExpr] : nil;
    if (!open || !close) return header;

    NSUInteger from = NSMaxRange(header);
    NSRange rest = NSMakeRange(from, text.length - from);
    NSMutableArray<NSValue *> *opens = [NSMutableArray array];
    NSMutableArray<NSValue *> *closes = [NSMutableArray array];
    [open enumerateMatchesInString:text options:0 range:rest
                        usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
        [opens addObject:[NSValue valueWithRange:m.range]];
    }];
    [close enumerateMatchesInString:text options:0 range:rest
                         usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
        [closes addObject:[NSValue valueWithRange:m.range]];
    }];

    // The header already consumed one opening symbol, so the count starts at 1.
    NSInteger depth = 1;
    NSUInteger oi = 0, ci = 0;
    while (ci < closes.count) {
        NSUInteger closeAt = closes[ci].rangeValue.location;
        while (oi < opens.count && opens[oi].rangeValue.location < closeAt) { depth++; oi++; }
        depth--;
        if (depth == 0) {
            NSUInteger end = NSMaxRange(closes[ci].rangeValue);
            return NSMakeRange(header.location, end - header.location);
        }
        ci++;
    }
    // Unbalanced, which a document being edited often is: take the rest.
    return NSMakeRange(header.location, text.length - header.location);
}

static NSString *NarrowToName(NSString *body, NSArray<NSString *> *exprs) {
    if (!exprs.count) return nil;
    NSString *current = body;
    for (NSString *expr in exprs) {
        NSRegularExpression *re = [FunctionListCatalog expressionFrom:expr];
        if (!re) continue;
        NSTextCheckingResult *m = [re firstMatchInString:current options:0
                                                   range:NSMakeRange(0, current.length)];
        // A step that matches nothing leaves the result where it was, rather
        // than throwing away what the earlier steps had already narrowed to.
        if (m) current = ReportedText(m, current);
    }
    return current;
}

static NSString *TextWithoutComments(NSString *text, NSString *commentExpr) {
    if (!commentExpr.length) return text;
    NSRegularExpression *re = [FunctionListCatalog expressionFrom:commentExpr];
    if (!re) return text;

    NSMutableString *out = [text mutableCopy];
    [re enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                     usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        NSRange r = m.range;
        if (!r.length) return;
        // Newlines are kept so line numbers do not shift; everything else in the
        // comment becomes a space.
        NSMutableString *blank = [NSMutableString stringWithCapacity:r.length];
        for (NSUInteger i = 0; i < r.length; ++i) {
            unichar c = [text characterAtIndex:r.location + i];
            [blank appendString:(c == '\n' || c == '\r') ? [NSString stringWithCharacters:&c length:1] : @" "];
        }
        [out replaceCharactersInRange:r withString:blank];
    }];
    return out;
}

@end

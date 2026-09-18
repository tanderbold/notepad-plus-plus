#import "LanguageCatalog.h"
#include "LangMap.h"

@implementation NppLanguage
@end

@interface LanguageCatalog () <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<NppLanguage *> *languages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppLanguage *> *byName;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppLanguage *> *byExtension;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NppLanguage *> *builtInByExtension;
@property (nonatomic, strong) NSArray<NppLanguage *> *userLanguages;
// parse state
@property (nonatomic, strong, nullable) NppLanguage *current;
@property (nonatomic, strong, nullable) NSMutableDictionary<NSNumber *, NSString *> *currentKeywords;
@property (nonatomic, strong, nullable) NSNumber *currentKeywordIndex;
@property (nonatomic, strong, nullable) NSMutableString *currentText;
@end

@implementation LanguageCatalog

+ (instancetype)sharedCatalog {
    static LanguageCatalog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[LanguageCatalog alloc] init]; });
    return shared;
}

/// Notepad++'s LANG_INDEX_* order (see MISC/Common/NppConstants.h).
static NSNumber *KeywordSetIndex(NSString *attrName) {
    static NSDictionary<NSString *, NSNumber *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{@"instre1": @0, @"instre2": @1,
                @"type1": @2, @"type2": @3, @"type3": @4, @"type4": @5,
                @"type5": @6, @"type6": @7, @"type7": @8};
    });
    return map[attrName];
}

static NSString *LexerIDForLanguage(NSString *langName) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:kNppLangLexerCount];
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            m[@(kNppLangLexers[i].langName)] = @(kNppLangLexers[i].lexerID);
        }
        map = m;
    });
    return map[langName] ?: @"null";
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _languages = [NSMutableArray array];
    _byName = [NSMutableDictionary dictionary];
    _byExtension = [NSMutableDictionary dictionary];

    NSString *path = [[NSBundle mainBundle] pathForResource:@"langs.model" ofType:@"xml"];
    _sourcePath = path ?: @"";
    if (path) {
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[NSData dataWithContentsOfFile:path]];
        parser.delegate = self;
        [parser parse];
    }
    return self;
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {

    if ([element isEqualToString:@"Language"]) {
        NppLanguage *lang = [[NppLanguage alloc] init];
        lang.name = attrs[@"name"] ?: @"";
        lang.lexerID = LexerIDForLanguage(lang.name);
        lang.commentLine = attrs[@"commentLine"];
        lang.commentStart = attrs[@"commentStart"];
        lang.commentEnd = attrs[@"commentEnd"];

        NSString *ext = attrs[@"ext"] ?: @"";
        NSMutableArray *exts = [NSMutableArray array];
        for (NSString *e in [ext componentsSeparatedByString:@" "]) {
            if (e.length) [exts addObject:e.lowercaseString];
        }
        lang.extensions = exts;

        self.current = lang;
        self.currentKeywords = [NSMutableDictionary dictionary];

    } else if ([element isEqualToString:@"Keywords"] && self.current) {
        self.currentKeywordIndex = KeywordSetIndex(attrs[@"name"] ?: @"");
        self.currentText = self.currentKeywordIndex ? [NSMutableString string] : nil;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.currentText appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {

    if ([element isEqualToString:@"Keywords"]) {
        if (self.currentKeywordIndex && self.currentText.length) {
            // Scintilla wants a single-space-separated list; the XML wraps lines.
            NSArray *words = [self.currentText componentsSeparatedByCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSMutableArray *clean = [NSMutableArray array];
            for (NSString *w in words) if (w.length) [clean addObject:w];
            if (clean.count) {
                self.currentKeywords[self.currentKeywordIndex] = [clean componentsJoinedByString:@" "];
            }
        }
        self.currentKeywordIndex = nil;
        self.currentText = nil;

    } else if ([element isEqualToString:@"Language"] && self.current) {
        self.current.keywordSets = self.currentKeywords ?: @{};
        [self.languages addObject:self.current];
        if (self.current.name.length) self.byName[self.current.name] = self.current;
        for (NSString *e in self.current.extensions) {
            // Where two languages claim the same extension, Notepad++ walks its
            // list from the end (Parameters.cpp, getLangFromExt), so the last
            // definition wins: .tex belongs to tex, not to latex.
            self.byExtension[e] = self.current;
        }
        self.current = nil;
        self.currentKeywords = nil;
    }
}

#pragma mark - Lookup

- (NSArray<NppLanguage *> *)allLanguages { return self.languages; }

- (void)registerUserLanguages:(NSArray<NppLanguage *> *)languages {
    if (!self.builtInByExtension) self.builtInByExtension = [self.byExtension copy];
    for (NppLanguage *old in self.userLanguages) {
        [self.languages removeObject:old];
        if (self.byName[old.name] == old) [self.byName removeObjectForKey:old.name];
    }
    self.byExtension = [self.builtInByExtension mutableCopy];
    self.userLanguages = [languages copy];
    for (NppLanguage *lang in languages) {
        [self.languages addObject:lang];
        self.byName[lang.name] = lang;
        for (NSString *ext in lang.extensions) self.byExtension[ext.lowercaseString] = lang;
    }
}

- (NppLanguage *)languageNamed:(NSString *)name { return self.byName[name]; }

- (NppLanguage *)languageForFileName:(NSString *)fileName {
    NSString *ext = fileName.pathExtension.lowercaseString;
    NppLanguage *lang = ext.length ? self.byExtension[ext] : nil;
    if (!lang) {
        // Extension-less files Notepad++ still recognises by full name (e.g. "makefile").
        lang = self.byExtension[fileName.lastPathComponent.lowercaseString];
    }
    return lang ?: self.byName[@"normal"];
}

@end

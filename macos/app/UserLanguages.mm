#import "UserLanguages.h"
#import "ScintillaView.h"
#import "SettingsCommands.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include <objc/runtime.h>

@implementation NppUserLanguage

/// The names a <Keywords> element may carry, in every version of the file
/// (UserDefineDialog.h's keywordNameMapper), to the SCE_USER_KWLIST index.
static NSDictionary<NSString *, NSNumber *> *KeywordListIndexes(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"Comments": @(SCE_USER_KWLIST_COMMENTS),
            @"Numbers, prefix1": @(SCE_USER_KWLIST_NUMBER_PREFIX1),
            @"Numbers, prefix2": @(SCE_USER_KWLIST_NUMBER_PREFIX2),
            @"Numbers, prefixes": @(SCE_USER_KWLIST_NUMBER_PREFIX2),
            @"Numbers, extras1": @(SCE_USER_KWLIST_NUMBER_EXTRAS1),
            @"Numbers, extras2": @(SCE_USER_KWLIST_NUMBER_EXTRAS2),
            @"Numbers, extras with prefixes": @(SCE_USER_KWLIST_NUMBER_EXTRAS2),
            @"Numbers, suffix1": @(SCE_USER_KWLIST_NUMBER_SUFFIX1),
            @"Numbers, suffix2": @(SCE_USER_KWLIST_NUMBER_SUFFIX2),
            @"Numbers, suffixes": @(SCE_USER_KWLIST_NUMBER_SUFFIX2),
            @"Numbers, range": @(SCE_USER_KWLIST_NUMBER_RANGE),
            @"Numbers, additional": @(SCE_USER_KWLIST_NUMBER_RANGE),
            @"Operators": @(SCE_USER_KWLIST_OPERATORS1),
            @"Operators1": @(SCE_USER_KWLIST_OPERATORS1),
            @"Operators2": @(SCE_USER_KWLIST_OPERATORS2),
            @"Folder+": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN),
            @"Folder-": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE),
            @"Folders in code1, open": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN),
            @"Folders in code1, middle": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_MIDDLE),
            @"Folders in code1, close": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE),
            @"Folders in code2, open": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_OPEN),
            @"Folders in code2, middle": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_MIDDLE),
            @"Folders in code2, close": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_CLOSE),
            @"Folders in comment, open": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_OPEN),
            @"Folders in comment, middle": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_MIDDLE),
            @"Folders in comment, close": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_CLOSE),
            @"Words1": @(SCE_USER_KWLIST_KEYWORDS1), @"Words2": @(SCE_USER_KWLIST_KEYWORDS2),
            @"Words3": @(SCE_USER_KWLIST_KEYWORDS3), @"Words4": @(SCE_USER_KWLIST_KEYWORDS4),
            @"Keywords1": @(SCE_USER_KWLIST_KEYWORDS1), @"Keywords2": @(SCE_USER_KWLIST_KEYWORDS2),
            @"Keywords3": @(SCE_USER_KWLIST_KEYWORDS3), @"Keywords4": @(SCE_USER_KWLIST_KEYWORDS4),
            @"Keywords5": @(SCE_USER_KWLIST_KEYWORDS5), @"Keywords6": @(SCE_USER_KWLIST_KEYWORDS6),
            @"Keywords7": @(SCE_USER_KWLIST_KEYWORDS7), @"Keywords8": @(SCE_USER_KWLIST_KEYWORDS8),
            @"Delimiters": @(SCE_USER_KWLIST_DELIMITERS),
        };
    });
    return map;
}

/// A <WordsStyle name="..."> to its SCE_USER_STYLE id (styleIdMapper).
static NSDictionary<NSString *, NSNumber *> *StyleIndexes(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"DEFAULT": @(SCE_USER_STYLE_DEFAULT), @"COMMENTS": @(SCE_USER_STYLE_COMMENT),
            @"LINE COMMENTS": @(SCE_USER_STYLE_COMMENTLINE), @"NUMBERS": @(SCE_USER_STYLE_NUMBER),
            @"KEYWORDS1": @(SCE_USER_STYLE_KEYWORD1), @"KEYWORDS2": @(SCE_USER_STYLE_KEYWORD2),
            @"KEYWORDS3": @(SCE_USER_STYLE_KEYWORD3), @"KEYWORDS4": @(SCE_USER_STYLE_KEYWORD4),
            @"KEYWORDS5": @(SCE_USER_STYLE_KEYWORD5), @"KEYWORDS6": @(SCE_USER_STYLE_KEYWORD6),
            @"KEYWORDS7": @(SCE_USER_STYLE_KEYWORD7), @"KEYWORDS8": @(SCE_USER_STYLE_KEYWORD8),
            @"OPERATORS": @(SCE_USER_STYLE_OPERATOR),
            @"FOLDER IN CODE1": @(SCE_USER_STYLE_FOLDER_IN_CODE1),
            @"FOLDER IN CODE2": @(SCE_USER_STYLE_FOLDER_IN_CODE2),
            @"FOLDER IN COMMENT": @(SCE_USER_STYLE_FOLDER_IN_COMMENT),
            @"DELIMITERS1": @(SCE_USER_STYLE_DELIMITER1), @"DELIMITERS2": @(SCE_USER_STYLE_DELIMITER2),
            @"DELIMITERS3": @(SCE_USER_STYLE_DELIMITER3), @"DELIMITERS4": @(SCE_USER_STYLE_DELIMITER4),
            @"DELIMITERS5": @(SCE_USER_STYLE_DELIMITER5), @"DELIMITERS6": @(SCE_USER_STYLE_DELIMITER6),
            @"DELIMITERS7": @(SCE_USER_STYLE_DELIMITER7), @"DELIMITERS8": @(SCE_USER_STYLE_DELIMITER8),
        };
    });
    return map;
}

static BOOL YesAttribute(NSXMLElement *element, NSString *name) {
    NSString *value = [element attributeForName:name].stringValue;
    return [value isEqualToString:@"yes"] || [value isEqualToString:@"1"] || [value isEqualToString:@"true"];
}

+ (NSArray<NppUserLanguage *> *)languagesInFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @[];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:NULL];
    NSMutableArray *languages = [NSMutableArray array];
    for (NSXMLElement *userLang in [doc.rootElement elementsForName:@"UserLang"]) {
        NSString *name = [userLang attributeForName:@"name"].stringValue;
        if (!name.length) continue;
        NppUserLanguage *udl = [[NppUserLanguage alloc] init];
        udl.name = name;
        NSMutableArray *exts = [NSMutableArray array];
        for (NSString *e in [[userLang attributeForName:@"ext"].stringValue ?: @"" componentsSeparatedByString:@" "]) {
            if (e.length) [exts addObject:e.lowercaseString];
        }
        udl.extensions = exts;

        NSMutableArray *prefixes = [NSMutableArray arrayWithCapacity:8];
        for (int i = 0; i < 8; ++i) [prefixes addObject:@NO];
        NSXMLElement *settings = [userLang elementsForName:@"Settings"].firstObject;
        NSXMLElement *global = [settings elementsForName:@"Global"].firstObject;
        if (global) {
            udl.caseIgnored = YesAttribute(global, @"caseIgnored");
            udl.allowFoldOfComments = YesAttribute(global, @"allowFoldOfComments");
            udl.foldCompact = YesAttribute(global, @"foldCompact");
            udl.forcePureLC = [global attributeForName:@"forcePureLC"].stringValue.intValue;
            udl.decimalSeparator = [global attributeForName:@"decimalSeparator"].stringValue.intValue;
        }
        NSXMLElement *prefix = [settings elementsForName:@"Prefix"].firstObject;
        if (prefix) {
            for (int i = 0; i < 8; ++i) {
                NSString *key = [NSString stringWithFormat:@"Keywords%d", i + 1];
                NSString *old = [NSString stringWithFormat:@"words%d", i + 1];
                prefixes[i] = @(YesAttribute(prefix, key) || YesAttribute(prefix, old));
            }
        }
        udl.prefixes = prefixes;

        NSMutableArray *lists = [NSMutableArray arrayWithCapacity:SCE_USER_KWLIST_TOTAL];
        for (int i = 0; i < SCE_USER_KWLIST_TOTAL; ++i) [lists addObject:@""];
        NSXMLElement *keywordLists = [userLang elementsForName:@"KeywordLists"].firstObject;
        for (NSXMLElement *keywords in [keywordLists elementsForName:@"Keywords"]) {
            NSNumber *index = KeywordListIndexes()[[keywords attributeForName:@"name"].stringValue ?: @""];
            if (index) lists[index.unsignedIntegerValue] = keywords.stringValue ?: @"";
        }
        udl.keywordLists = lists;

        NSMutableDictionary *styles = [NSMutableDictionary dictionary];
        NSXMLElement *styleRoot = [userLang elementsForName:@"Styles"].firstObject;
        for (NSXMLElement *style in [styleRoot elementsForName:@"WordsStyle"]) {
            NSNumber *styleID = StyleIndexes()[[style attributeForName:@"name"].stringValue ?: @""];
            if (!styleID) continue;
            NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
            for (NSString *key in @[@"fgColor", @"bgColor", @"fontName", @"fontStyle", @"fontSize", @"nesting"]) {
                NSString *value = [style attributeForName:key].stringValue;
                if (value.length) attrs[key] = value;
            }
            styles[styleID] = attrs;
        }
        udl.styles = styles;
        [languages addObject:udl];
    }
    return languages;
}

@end

#pragma mark - The catalog

static const char kUserDefinitionKey = 0;
static const char kUserLanguagesKey = 0;

@implementation LanguageCatalog (UserLanguages)

- (NSArray<NppUserLanguage *> *)reloadUserLanguagesFromDirectory:(NSString *)directory {
    NSMutableArray<NppUserLanguage *> *found = [NSMutableArray array];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    [files addObject:[directory stringByAppendingPathComponent:@"userDefineLang.xml"]];
    NSString *folder = [directory stringByAppendingPathComponent:@"userDefineLangs"];
    for (NSString *name in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL]
                            sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        if ([name.pathExtension caseInsensitiveCompare:@"xml"] == NSOrderedSame) {
            [files addObject:[folder stringByAppendingPathComponent:name]];
        }
    }
    for (NSString *path in files) [found addObjectsFromArray:[NppUserLanguage languagesInFile:path]];

    NSMutableArray<NppLanguage *> *entries = [NSMutableArray array];
    for (NppUserLanguage *udl in found) {
        NppLanguage *lang = [[NppLanguage alloc] init];
        lang.name = udl.name;
        lang.lexerID = @"user";
        lang.extensions = udl.extensions;
        lang.keywordSets = @{};
        // The comment tokens, for comment toggling: the first block pair and
        // the first line marker of the Comments list, when written in the
        // 2.x shape "00# 01 02 03/* 04*/".
        for (NSString *piece in [udl.keywordLists[SCE_USER_KWLIST_COMMENTS] componentsSeparatedByString:@" "]) {
            if (piece.length <= 2) continue;
            NSString *code = [piece substringToIndex:2], *token = [piece substringFromIndex:2];
            if ([code isEqualToString:@"00"] && !lang.commentLine) lang.commentLine = token;
            if ([code isEqualToString:@"03"] && !lang.commentStart) lang.commentStart = token;
            if ([code isEqualToString:@"04"] && !lang.commentEnd) lang.commentEnd = token;
        }
        objc_setAssociatedObject(lang, &kUserDefinitionKey, udl, OBJC_ASSOCIATION_RETAIN);
        [entries addObject:lang];
    }
    [self registerUserLanguages:entries];
    objc_setAssociatedObject(self, &kUserLanguagesKey, found, OBJC_ASSOCIATION_RETAIN);
    return found;
}

- (NppUserLanguage *)userLanguageNamed:(NSString *)name {
    NppLanguage *lang = [self languageNamed:name];
    return lang ? objc_getAssociatedObject(lang, &kUserDefinitionKey) : nil;
}

@end

#pragma mark - Driving the lexer

@implementation EditorController (UserLanguages)

/// A keyword list the way setUserLexer hands it to SCI_SETKEYWORDS: quoted
/// phrases become one word with \v (double quotes) or \b (single quotes)
/// standing for the spaces inside, and \" \' \\ are unescaped.
static NSString *KeywordListForScintilla(NSString *list) {
    const char *in = list.UTF8String ?: "";
    size_t len = strlen(in);
    std::string out;
    out.reserve(len);
    bool inDouble = false, inSingle = false, nonWSFound = false;
    for (size_t j = 0; j < len; ++j) {
        char c = in[j];
        if (!inSingle && c == '"') { inDouble = !inDouble; continue; }
        if (!inDouble && c == '\'') { inSingle = !inSingle; continue; }
        if (c == '\\' && (in[j + 1] == '"' || in[j + 1] == '\'' || in[j + 1] == '\\')) {
            ++j;
            out.push_back(in[j]);
            continue;
        }
        if (inDouble || inSingle) {
            if (c > ' ') {
                out.push_back(c);
                nonWSFound = true;
            } else if (nonWSFound && in[j - 1] != '"' && in[j + 1] != '"' && in[j + 1] > ' ') {
                out.push_back(inDouble ? '\v' : '\b');
            }
        } else {
            out.push_back(c);
        }
    }
    return @(out.c_str());
}

- (void)configureUserLexerFor:(NppUserLanguage *)udl {
    ScintillaView *sci = self.sci;
    [sci setLexerProperty:@"fold" value:@"1"];
    [sci setLexerProperty:@"userDefine.isCaseIgnored" value:udl.caseIgnored ? @"1" : @"0"];
    [sci setLexerProperty:@"userDefine.allowFoldOfComments" value:udl.allowFoldOfComments ? @"1" : @"0"];
    [sci setLexerProperty:@"userDefine.foldCompact" value:udl.foldCompact ? @"1" : @"0"];
    for (int i = 0; i < 8; ++i) {
        [sci setLexerProperty:[NSString stringWithFormat:@"userDefine.prefixKeywords%d", i + 1]
                        value:[udl.prefixes[i] boolValue] ? @"1" : @"0"];
    }

    // The lists that are properties (setLexerMapper) and the ones that are
    // keyword sets, numbered in the order they come.
    NSDictionary<NSNumber *, NSString *> *properties = @{
        @(SCE_USER_KWLIST_COMMENTS): @"userDefine.comments",
        @(SCE_USER_KWLIST_DELIMITERS): @"userDefine.delimiters",
        @(SCE_USER_KWLIST_OPERATORS1): @"userDefine.operators1",
        @(SCE_USER_KWLIST_NUMBER_PREFIX1): @"userDefine.numberPrefix1",
        @(SCE_USER_KWLIST_NUMBER_PREFIX2): @"userDefine.numberPrefix2",
        @(SCE_USER_KWLIST_NUMBER_EXTRAS1): @"userDefine.numberExtras1",
        @(SCE_USER_KWLIST_NUMBER_EXTRAS2): @"userDefine.numberExtras2",
        @(SCE_USER_KWLIST_NUMBER_SUFFIX1): @"userDefine.numberSuffix1",
        @(SCE_USER_KWLIST_NUMBER_SUFFIX2): @"userDefine.numberSuffix2",
        @(SCE_USER_KWLIST_NUMBER_RANGE): @"userDefine.numberRange",
        @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN): @"userDefine.foldersInCode1Open",
        @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_MIDDLE): @"userDefine.foldersInCode1Middle",
        @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE): @"userDefine.foldersInCode1Close",
    };
    int keywordSet = 0;
    for (int i = 0; i < SCE_USER_KWLIST_TOTAL; ++i) {
        NSString *list = i < (int)udl.keywordLists.count ? udl.keywordLists[i] : @"";
        NSString *property = properties[@(i)];
        if (property) {
            [sci setLexerProperty:property value:list];
        } else {
            [sci setStringProperty:SCI_SETKEYWORDS parameter:keywordSet++ value:KeywordListForScintilla(list)];
        }
    }
    [sci setLexerProperty:@"userDefine.forcePureLC" value:[@(udl.forcePureLC) stringValue]];
    [sci setLexerProperty:@"userDefine.decimalSeparator" value:[@(udl.decimalSeparator) stringValue]];
    [sci setLexerProperty:@"userDefine.udlName" value:[@((unsigned long)(uintptr_t)(__bridge void *)udl) stringValue]];
    [sci setLexerProperty:@"userDefine.currentBufferID"
                    value:[@((unsigned long)(uintptr_t)self.currentDocument.docPointer) stringValue]];
    for (NSNumber *styleID in udl.styles) {
        NSString *nesting = udl.styles[styleID][@"nesting"];
        if (nesting.length) {
            [sci setLexerProperty:[NSString stringWithFormat:@"userDefine.nesting.%02d", styleID.intValue]
                            value:nesting];
        }
    }
}

static NSColor *ColourFromHex(NSString *hex) {
    unsigned int rgb = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return nil;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

static long SciColourOf(NSColor *c) {
    NSColor *d = [c colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    return ((long)(d.blueComponent * 255) << 16) + ((long)(d.greenComponent * 255) << 8) + (long)(d.redComponent * 255);
}

- (void)applyUserLanguageStyles:(NppUserLanguage *)udl {
    ScintillaView *sci = self.sci;
    for (NSNumber *styleID in udl.styles) {
        NSDictionary *attrs = udl.styles[styleID];
        uptr_t id = (uptr_t)styleID.intValue;
        NSColor *fg = ColourFromHex(attrs[@"fgColor"]), *bg = ColourFromHex(attrs[@"bgColor"]);
        if (fg) [sci message:SCI_STYLESETFORE wParam:id lParam:SciColourOf(fg)];
        if (bg) [sci message:SCI_STYLESETBACK wParam:id lParam:SciColourOf(bg)];
        int fontStyle = [attrs[@"fontStyle"] intValue];
        if (fontStyle & 1) [sci message:SCI_STYLESETBOLD wParam:id lParam:1];
        if (fontStyle & 2) [sci message:SCI_STYLESETITALIC wParam:id lParam:1];
        if (fontStyle & 4) [sci message:SCI_STYLESETUNDERLINE wParam:id lParam:1];
        if ([attrs[@"fontName"] length]) [sci setStringProperty:SCI_STYLESETFONT parameter:(long)id value:attrs[@"fontName"]];
        if ([attrs[@"fontSize"] intValue] > 0) [sci message:SCI_STYLESETSIZE wParam:id lParam:[attrs[@"fontSize"] intValue]];
    }
}

@end

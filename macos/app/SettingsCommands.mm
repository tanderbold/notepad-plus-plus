#import "SettingsCommands.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"

static NSString *const kDefaultsPrefix = @"NppMac.";

static NSString *Key(NSString *name) { return [kDefaultsPrefix stringByAppendingString:name]; }

@implementation NppPreferences

+ (instancetype)shared {
    static NppPreferences *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[NppPreferences alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    // Defaults chosen to match what the editor already did before it had settings.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        Key(@"fontName"):        @"Menlo",
        Key(@"fontSize"):        @13,
        Key(@"tabWidth"):        @4,
        Key(@"useSpaces"):       @YES,
        Key(@"wordWrap"):        @NO,
        Key(@"showWhitespace"):  @NO,
        Key(@"showIndentGuides"):@YES,
        Key(@"restoreSession"):  @NO,
        Key(@"defaultEOL"):      @(SC_EOL_LF),
        Key(@"defaultEncoding"): @"UTF-8",
        Key(@"appearanceMode"):  @0,
        Key(@"showToolbar"):     @YES,
        Key(@"toolbarDisplayMode"): @0,
        Key(@"toolbarIconSize"): @1,
        Key(@"lightThemeName"):  @"Default",
        Key(@"darkThemeName"):   @"DarkModeDefault",
        Key(@"styleOverrides"):  @{},
        Key(@"shortcutOverrides"): @{},
        Key(@"contextMenuCommands"): @[@"Cut", @"Copy", @"Paste", @"Select All",
                                       @"Toggle Line Comment", @"Go to Matching Brace"],
    }];
    return self;
}

#define NPP_PREF_OBJ(getter, setter, type, key)                                   \
- (type *)getter { return [[NSUserDefaults standardUserDefaults] objectForKey:Key(key)]; } \
- (void)setter:(type *)value {                                                    \
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:Key(key)];       \
}

#define NPP_PREF_INT(getter, setter, key)                                         \
- (NSInteger)getter { return [[NSUserDefaults standardUserDefaults] integerForKey:Key(key)]; } \
- (void)setter:(NSInteger)value {                                                 \
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:Key(key)];      \
}

#define NPP_PREF_BOOL(getter, setter, key)                                        \
- (BOOL)getter { return [[NSUserDefaults standardUserDefaults] boolForKey:Key(key)]; }  \
- (void)setter:(BOOL)value {                                                      \
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:Key(key)];         \
}

NPP_PREF_OBJ(fontName, setFontName, NSString, @"fontName")
NPP_PREF_OBJ(defaultEncoding, setDefaultEncoding, NSString, @"defaultEncoding")
NPP_PREF_OBJ(lightThemeName, setLightThemeName, NSString, @"lightThemeName")
NPP_PREF_OBJ(darkThemeName, setDarkThemeName, NSString, @"darkThemeName")
NPP_PREF_OBJ(styleOverrides, setStyleOverrides, NSDictionary, @"styleOverrides")
NPP_PREF_OBJ(shortcutOverrides, setShortcutOverrides, NSDictionary, @"shortcutOverrides")
NPP_PREF_OBJ(contextMenuCommands, setContextMenuCommands, NSArray, @"contextMenuCommands")
NPP_PREF_INT(fontSize, setFontSize, @"fontSize")
NPP_PREF_INT(tabWidth, setTabWidth, @"tabWidth")
NPP_PREF_INT(defaultEOL, setDefaultEOL, @"defaultEOL")
NPP_PREF_INT(appearanceMode, setAppearanceMode, @"appearanceMode")
NPP_PREF_INT(toolbarDisplayMode, setToolbarDisplayMode, @"toolbarDisplayMode")
NPP_PREF_INT(toolbarIconSize, setToolbarIconSize, @"toolbarIconSize")
NPP_PREF_BOOL(useSpaces, setUseSpaces, @"useSpaces")
NPP_PREF_BOOL(wordWrap, setWordWrap, @"wordWrap")
NPP_PREF_BOOL(showWhitespace, setShowWhitespace, @"showWhitespace")
NPP_PREF_BOOL(showIndentGuides, setShowIndentGuides, @"showIndentGuides")
NPP_PREF_BOOL(restoreSession, setRestoreSession, @"restoreSession")
NPP_PREF_BOOL(showToolbar, setShowToolbar, @"showToolbar")

- (BOOL)systemIsDark {
    NSString *match = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSString *)effectiveThemeName {
    BOOL dark = self.appearanceMode == 2 || (self.appearanceMode == 0 && [self systemIsDark]);
    return dark ? (self.darkThemeName ?: @"DarkModeDefault") : (self.lightThemeName ?: @"Default");
}

- (void)setStyleOverride:(NSDictionary *)attributes
             forLanguage:(NSString *)language styleID:(int)styleID {
    NSMutableDictionary *all = [self.styleOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@/%d", language, styleID];
    if (attributes.count) all[key] = attributes; else [all removeObjectForKey:key];
    self.styleOverrides = all;
}

- (NSDictionary *)styleOverrideForLanguage:(NSString *)language styleID:(int)styleID {
    id stored = self.styleOverrides[[NSString stringWithFormat:@"%@/%d", language, styleID]];
    if ([stored isKindOfClass:[NSDictionary class]]) return stored;
    // Settings written by the foreground-only version were a bare hex string.
    if ([stored isKindOfClass:[NSString class]]) return @{@"fg": stored};
    return nil;
}

- (void)setShortcutOverride:(NSString *)spec forCommand:(NSString *)title {
    NSMutableDictionary *all = [self.shortcutOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
    if (spec.length) all[title] = spec; else [all removeObjectForKey:title];
    self.shortcutOverrides = all;
}

- (void)applyToEditor:(EditorController *)editor {
    // The theme decides the colours, so it is loaded before the styles are set.
    NSString *wanted = [self effectiveThemeName];
    if (![[StyleCatalog sharedCatalog].themeName isEqualToString:wanted]) {
        [StyleCatalog loadThemeNamed:wanted];
        [editor applyLanguage];
    }
    ScintillaView *sci = editor.sci;
    [sci setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:self.fontName];
    [sci message:SCI_STYLESETSIZE wParam:STYLE_DEFAULT lParam:self.fontSize];
    [sci message:SCI_SETTABWIDTH wParam:(uptr_t)self.tabWidth lParam:0];
    [sci message:SCI_SETINDENT wParam:(uptr_t)self.tabWidth lParam:0];
    [sci message:SCI_SETUSETABS wParam:(uptr_t)(self.useSpaces ? 0 : 1) lParam:0];
    [sci message:SCI_SETWRAPMODE wParam:(uptr_t)(self.wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE) lParam:0];
    [sci message:SCI_SETVIEWWS
           wParam:(uptr_t)(self.showWhitespace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE) lParam:0];
    [sci message:SCI_SETINDENTATIONGUIDES
           wParam:(uptr_t)(self.showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE) lParam:0];
    [editor refreshChrome];
}

- (void)reset {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in [[d dictionaryRepresentation] allKeys]) {
        if ([key hasPrefix:kDefaultsPrefix]) [d removeObjectForKey:key];
    }
}

@end

#pragma mark - Editor side

@implementation EditorController (SettingsCommands)

- (NSString *)supportDirectory {
    NSString *dir = self.defaultSessionPath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    return dir;
}

- (NSString *)userDefinedLanguagePath {
    return [[self supportDirectory] stringByAppendingPathComponent:@"userDefineLang.xml"];
}

- (NSUInteger)importFiles:(NSArray<NSString *> *)paths intoSubdirectory:(NSString *)subdir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dest = [[self supportDirectory] stringByAppendingPathComponent:subdir];
    [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:NULL];

    NSUInteger copied = 0;
    for (NSString *src in paths) {
        NSString *target = [dest stringByAppendingPathComponent:src.lastPathComponent];
        [fm removeItemAtPath:target error:NULL];      // importing again replaces
        if ([fm copyItemAtPath:src toPath:target error:NULL]) copied++;
    }
    return copied;
}

- (NSArray<NSString *> *)importedFilesIn:(NSString *)subdir {
    NSString *dir = [[self supportDirectory] stringByAppendingPathComponent:subdir];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    return [names sortedArrayUsingSelector:@selector(compare:)] ?: @[];
}

/// Writes the language in the same shape Notepad++ uses for userDefineLang.xml,
/// so the file is recognisable to anyone who has seen the Windows one.
- (BOOL)defineUserLanguageNamed:(NSString *)name
                     extensions:(NSString *)extensions
                       keywords:(NSString *)keywords
                    commentLine:(NSString *)commentLine {
    if (!name.length) return NO;
    NSString *xml = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n"
        @"<NotepadPlus>\n"
        @"    <UserLang name=\"%@\" ext=\"%@\" udlVersion=\"2.1\">\n"
        @"        <Settings>\n"
        @"            <Global caseIgnored=\"no\" />\n"
        @"        </Settings>\n"
        @"        <KeywordLists>\n"
        @"            <Keywords name=\"Comments\">%@</Keywords>\n"
        @"            <Keywords name=\"Keywords1\">%@</Keywords>\n"
        @"        </KeywordLists>\n"
        @"    </UserLang>\n"
        @"</NotepadPlus>\n",
        name, extensions ?: @"", commentLine ?: @"", keywords ?: @""];

    if (![xml writeToFile:[self userDefinedLanguagePath] atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL]) return NO;

    // Make it usable straight away: drive the document with the chosen tokens.
    NppLanguage *lang = [[NppLanguage alloc] init];
    lang.name = name;
    lang.lexerID = @"user";
    NSMutableArray *exts = [NSMutableArray array];
    for (NSString *e in [(extensions ?: @"") componentsSeparatedByString:@" "]) {
        if (e.length) [exts addObject:e.lowercaseString];
    }
    lang.extensions = exts;
    lang.commentLine = commentLine.length ? commentLine : nil;
    lang.keywordSets = keywords.length ? @{@0: keywords} : @{};
    self.currentDocument.language = lang;
    [self applyLanguage];
    [self refreshChrome];
    return YES;
}

- (NSDictionary *)userDefinedLanguage {
    NSString *xml = [NSString stringWithContentsOfFile:[self userDefinedLanguagePath]
                                              encoding:NSUTF8StringEncoding error:NULL];
    if (!xml.length) return nil;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"<UserLang name=\"([^\"]*)\" ext=\"([^\"]*)\""
                             options:0 error:&err];
    NSTextCheckingResult *m = [re firstMatchInString:xml options:0 range:NSMakeRange(0, xml.length)];
    if (!m) return nil;
    return @{@"name": [xml substringWithRange:[m rangeAtIndex:1]],
             @"ext":  [xml substringWithRange:[m rangeAtIndex:2]]};
}

@end

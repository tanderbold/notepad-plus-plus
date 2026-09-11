// Loads Notepad++'s own colour scheme (stylers.model.xml) so the macOS editor
// renders with the same default theme as Notepad++ on Windows.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// One <WordsStyle>/<WidgetStyle> entry.
@interface NppStyle : NSObject
@property (nonatomic) int styleID;
@property (nonatomic, strong, nullable) NSColor *foreground;
@property (nonatomic, strong, nullable) NSColor *background;
@property (nonatomic) int fontStyle;                       // bit 1 bold, 2 italic, 4 underline
@property (nonatomic, copy, nullable) NSString *fontName;
@property (nonatomic) int fontSize;                        // 0 = unset
@property (nonatomic, copy, nullable) NSString *keywordClass;  // "instre1", "type1", ...
@property (nonatomic, copy, nullable) NSString *name;          // <WidgetStyle name="..."> 
@end

@interface StyleCatalog : NSObject
+ (instancetype)sharedCatalog;

/// Themes are the same XML as stylers.model.xml. Notepad++ ships a folder of
/// them; imported ones live beside the app's other support files.
+ (NSArray<NSString *> *)availableThemeNames;      // "Default" plus every theme found
+ (nullable NSString *)pathForThemeNamed:(NSString *)name;
/// Reloads the shared catalogue from a theme. "Default" restores stylers.model.xml.
+ (void)loadThemeNamed:(NSString *)name;
+ (void)setImportedThemesDirectory:(nullable NSString *)dir;
@property (nonatomic, readonly, copy) NSString *themeName;
/// Styles for a Notepad++ lexer name (the <LexerType name="..."> key), or nil.
- (nullable NSArray<NppStyle *> *)stylesForLexerName:(NSString *)lexerName;
/// Entries from <GlobalStyles>, keyed by their name attribute.
/// Several share styleID="0", so the name is the only unique key.
@property (nonatomic, readonly) NSDictionary<NSString *, NppStyle *> *globalStyles;
@end

NS_ASSUME_NONNULL_END

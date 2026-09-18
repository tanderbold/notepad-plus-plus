// User Defined Languages, read from userDefineLang.xml and the userDefineLangs
// folder and driven into Lexilla's "user" lexer with the same properties,
// keyword lists and styles Notepad++ hands it (ScintillaEditView::setUserLexer).
// Before this the file was written and never read: no user language was
// ever highlighted.
#import <Foundation/Foundation.h>
#import "LanguageCatalog.h"
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// One <UserLang> as the file describes it.
@interface NppUserLanguage : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *extensions;
@property (nonatomic) BOOL caseIgnored, allowFoldOfComments, foldCompact;
@property (nonatomic) int forcePureLC, decimalSeparator;
/// Whether keyword group 1..8 matches by prefix.
@property (nonatomic, copy) NSArray<NSNumber *> *prefixes;
/// The 28 keyword lists, by SCE_USER_KWLIST_* index, as written in the file.
@property (nonatomic, copy) NSArray<NSString *> *keywordLists;
/// SCE_USER_STYLE_* id -> {fg, bg, fontName, fontStyle, fontSize, nesting}.
@property (nonatomic, copy) NSDictionary<NSNumber *, NSDictionary *> *styles;
/// A small number of its own, for the lexer's cache; a pointer would not
/// survive the lexer's int conversion.
@property (nonatomic) int identifier;

/// Every language in an XML file of Notepad++'s userDefineLang shape.
+ (NSArray<NppUserLanguage *> *)languagesInFile:(NSString *)path;
@end

@interface LanguageCatalog (UserLanguages)
/// Reads userDefineLang.xml and userDefineLangs/*.xml under the settings
/// folder and lists their languages in the catalog, replacing whatever user
/// languages were listed before. A user language's extensions win over the
/// built-in ones, as on Windows.
- (NSArray<NppUserLanguage *> *)reloadUserLanguagesFromDirectory:(NSString *)directory;
/// The definition behind a language listed from a file, or nil.
- (nullable NppUserLanguage *)userLanguageNamed:(NSString *)name;
@end

@interface EditorController (UserLanguages)
/// Sets the "user" lexer up for the language: the properties and keyword
/// lists as setUserLexer sends them. The lexer is already in place.
- (void)configureUserLexerFor:(NppUserLanguage *)udl;
/// The language's own styles, on top of the theme's default.
- (void)applyUserLanguageStyles:(NppUserLanguage *)udl;
@end

NS_ASSUME_NONNULL_END

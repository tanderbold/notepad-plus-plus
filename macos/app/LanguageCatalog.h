// Loads Notepad++'s own language definitions (langs.model.xml) at runtime and
// resolves a file name to the Lexilla lexer and keyword sets Notepad++ uses.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppLanguage : NSObject
@property (nonatomic, copy) NSString *name;              // e.g. "cpp"
@property (nonatomic, copy) NSString *lexerID;           // Lexilla lexer, e.g. "cpp"
@property (nonatomic, copy) NSArray<NSString *> *extensions;
/// Scintilla keyword-set index -> space-separated words.
/// Index follows Notepad++'s LANG_INDEX_*: instre1=0, instre2=1, type1=2 ... type7=8.
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *keywordSets;
@property (nonatomic, copy, nullable) NSString *commentLine;
@property (nonatomic, copy, nullable) NSString *commentStart;
@property (nonatomic, copy, nullable) NSString *commentEnd;
@end

@interface LanguageCatalog : NSObject
/// Parses langs.model.xml from the app bundle. Never nil; empty if the file is missing.
+ (instancetype)sharedCatalog;
@property (nonatomic, readonly) NSArray<NppLanguage *> *allLanguages;
@property (nonatomic, readonly) NSString *sourcePath;
- (nullable NppLanguage *)languageNamed:(NSString *)name;
/// Matches on file extension; falls back to the "normal" language.
- (nullable NppLanguage *)languageForFileName:(NSString *)fileName;
@end

NS_ASSUME_NONNULL_END

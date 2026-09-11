// Reads Notepad++'s own functionList definitions rather than a hand-written
// pattern table, so the Function List recognises what upstream recognises.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One entry found in a document.
@interface NppFunctionEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *container;   // enclosing class, if any
@property (nonatomic) NSUInteger line;                       // zero-based
@end

@interface FunctionListCatalog : NSObject
+ (instancetype)sharedCatalog;

/// Parser ids loaded from the bundled functionList folder.
@property (nonatomic, readonly) NSArray<NSString *> *parserIDs;
/// Languages and extensions that have a parser, from the association map.
- (nullable NSString *)parserIDForLanguage:(NSString *)language extension:(nullable NSString *)ext;
/// Entries found in `text` using the parser for that language.
- (NSArray<NppFunctionEntry *> *)entriesInText:(NSString *)text
                                   forLanguage:(NSString *)language
                                     extension:(nullable NSString *)ext;

/// Translates one of upstream's PCRE patterns into something ICU accepts.
/// Exposed so the translation itself can be tested.
+ (nullable NSString *)icuPatternFrom:(NSString *)pcre;
@end

NS_ASSUME_NONNULL_END

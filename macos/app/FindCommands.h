// Find and Replace as Notepad++ has them: three search modes, the options that
// go with them, and replacement that understands back-references. What was here
// before searched for a literal string and nothing else.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppSearchMode) {
    NppSearchNormal = 0,    ///< the text as typed
    NppSearchExtended,      ///< \n, \t, \xHH and the rest
    NppSearchRegex,         ///< a regular expression
};

typedef NS_OPTIONS(NSInteger, NppFindOptions) {
    NppFindNone        = 0,
    NppFindMatchCase   = 1 << 0,
    NppFindWholeWord   = 1 << 1,
    NppFindWrap        = 1 << 2,
    NppFindBackward    = 1 << 3,
    NppFindInSelection = 1 << 4,
};

/// What to look for, and what to put in its place.
@interface NppFindSpec : NSObject
@property (nonatomic, copy) NSString *what;
@property (nonatomic, copy, nullable) NSString *replacement;
@property (nonatomic) NppSearchMode mode;
@property (nonatomic) NppFindOptions options;
+ (instancetype)specFor:(NSString *)what mode:(NppSearchMode)mode options:(NppFindOptions)options;
@end

@interface EditorController (FindCommands)

/// The escapes Extended mode understands: \r \n \0 \t \\, and \b \o \d \x \u
/// with their fixed digit counts. Anything else keeps its backslash, exactly as
/// upstream leaves it.
+ (NSString *)convertExtendedToString:(NSString *)query;

/// Finds and selects the next match, returning whether there was one.
- (BOOL)findNext:(NppFindSpec *)spec;
/// How many matches the document holds.
- (NSUInteger)countMatches:(NppFindSpec *)spec;
/// Replaces every match, returning how many.
- (NSUInteger)replaceAll:(NppFindSpec *)spec;
/// Replaces the selection when it is already a match, then finds the next one.
- (BOOL)replaceCurrentThenFindNext:(NppFindSpec *)spec;
/// Marks every match with the Find mark style, returning how many.
- (NSUInteger)markAll:(NppFindSpec *)spec;
/// Byte ranges of every match; the others are built on this.
- (NSArray<NSValue *> *)rangesOfMatches:(NppFindSpec *)spec;

@end

NS_ASSUME_NONNULL_END

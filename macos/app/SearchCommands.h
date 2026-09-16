// Search-menu commands: token styling with five marker styles, bookmark line
// operations, brace matching, Find in Files and incremental search.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// Notepad++ offers five "style all occurrences" colours; these map onto
/// Scintilla indicators 8..12, which sit above the range lexers use.
#define NPPMAC_STYLE_COUNT 5
#define NPPMAC_STYLE_FIRST_INDICATOR 8
/// Indicator 13 backs "Find Mark Style", the one Find's Mark All writes.
#define NPPMAC_FIND_MARK_INDICATOR 13

@interface EditorController (SearchCommands)

// Token styling. style is 0..4, or NPPMAC_STYLE_COUNT for the Find Mark style.
- (NSUInteger)markAllOccurrencesOfSelection:(NSInteger)style;
/// The same, with the matching rules given rather than taken from the Mark All
/// settings; smart highlighting has settings of its own.
- (NSUInteger)markAllOccurrencesOfSelection:(NSInteger)style
                                  matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord;
- (void)markOneOccurrenceOfSelection:(NSInteger)style;
- (void)clearStyle:(NSInteger)style;
- (void)clearAllStyles;
- (BOOL)jumpToMarker:(NSInteger)style forward:(BOOL)forward;
- (NSString *)textOfStyle:(NSInteger)style;
- (NSString *)textOfAllStyles;

// Bookmark line operations
- (NSString *)bookmarkedLinesText;
- (void)cutBookmarkedLines;
- (void)copyBookmarkedLines;
- (void)pasteOverBookmarkedLines;
- (void)removeBookmarkedLines;
- (void)removeUnbookmarkedLines;
- (void)inverseBookmarks;

// Braces
- (BOOL)goToMatchingBrace;
- (BOOL)selectBetweenMatchingBraces;

// Find in Files
- (NSUInteger)findInFiles:(NSString *)term
                inFolder:(NSString *)folder
                  filter:(nullable NSString *)filter;
/// Puts a report into the "Search results" tab, which is where every kind of
/// find-all here leaves its output.
- (void)showSearchResults:(NSString *)report;
- (BOOL)focusSearchResults;
- (BOOL)goToSearchResult:(BOOL)forward;

// Incremental / volatile search helpers
- (BOOL)findNextOccurrenceOfSelection:(BOOL)forward extendSelection:(BOOL)extend;
- (NSUInteger)markCharactersInRangeFrom:(unichar)from to:(unichar)to;

// Change history
- (void)enableChangeHistory:(BOOL)on;
- (BOOL)goToNextChange:(BOOL)forward;
- (void)clearChangeHistory;

@end

NS_ASSUME_NONNULL_END

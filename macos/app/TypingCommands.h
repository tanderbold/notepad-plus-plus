// Preferences > Auto-Completion, New document, Tab bar, Recent files,
// Default directory, Searching and Highlighting: the behaviour behind them.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppCompletionSource) {
    NppCompletionFunctions = 0,
    NppCompletionWords,
    NppCompletionBoth,
};

@interface EditorController (TypingCommands)

/// Called for every character typed; drives completion and auto-insertion.
- (void)handleCharacterAdded:(int)character;
/// Carries the previous line's indentation onto a new one, and in the languages
/// that use braces opens a level after one. Called when a newline is typed.
- (void)maintainIndentationAfter:(int)character;

/// Candidates the current settings would offer for `prefix`.
- (NSArray<NSString *> *)completionCandidatesForPrefix:(NSString *)prefix;
/// The closing text that should follow `character`, or nil.
- (nullable NSString *)autoInsertionForCharacter:(int)character;
/// The close tag for the element just finished at the caret, or nil.
- (nullable NSString *)closeTagAtCaret;

// New documents
- (void)applyNewDocumentDefaults;
/// The name an untitled tab should take, which may come from its first line.
- (NSString *)untitledNameForDocument:(NppDocument *)doc;

// Recent files
- (void)noteRecentFile:(NSString *)path;
- (NSArray<NSString *> *)recentFiles;
- (NSString *)displayNameForRecentFile:(NSString *)path;
- (void)clearRecentFiles;

// Default directory
- (NSString *)defaultOpenDirectory;
- (void)rememberOpenDirectory:(NSString *)path;

// Searching and highlighting helpers
/// What the Find field should be pre-filled with, per the settings.
- (NSString *)initialFindTerm;

@end

NS_ASSUME_NONNULL_END

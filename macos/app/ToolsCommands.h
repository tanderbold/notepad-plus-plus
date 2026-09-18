// Tools, Macro, Window, Run and Help commands.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppDigest) {
    NppDigestMD5, NppDigestSHA1, NppDigestSHA256, NppDigestSHA512,
};

typedef NS_ENUM(NSInteger, NppTabSort) {
    NppTabSortName, NppTabSortPath, NppTabSortType,
    NppTabSortContentLength, NppTabSortModifiedTime,
};

@interface EditorController (ToolsCommands)

// Hashes
+ (NSString *)hashOfData:(NSData *)data digest:(NppDigest)digest;
+ (NSString *)nameOfDigest:(NppDigest)digest;
- (NSString *)hashOfSelection:(NppDigest)digest;
- (NSString *)hashOfFiles:(NSArray<NSString *> *)paths digest:(NppDigest)digest;

// Macros
- (void)startRecordingMacro;
- (void)stopRecordingMacro;
- (BOOL)recordingMacro;
- (NSUInteger)recordedStepCount;
- (BOOL)playbackMacro:(NSUInteger)times;
- (BOOL)saveRecordedMacroAs:(NSString *)name;
- (NSArray<NSString *> *)savedMacroNames;
/// Plays a saved macro, as the Macro menu entry does.
- (BOOL)playSavedMacroNamed:(NSString *)name;
- (BOOL)removeSavedMacroNamed:(NSString *)name;
/// The steps of a saved macro: {msg, w, l, text?} each; nil when there is none.
- (nullable NSArray<NSDictionary *> *)stepsOfSavedMacroNamed:(NSString *)name;
/// Keeps steps under a name, written to macros.json.
- (void)storeSavedMacro:(NSArray<NSDictionary *> *)steps named:(NSString *)name;

/// Reads the saved macros back from macros.json, replacing what is held.
- (void)reloadSavedMacros;
/// Called from the notification handler for each recorded Scintilla action.
- (void)recordMacroMessage:(int)message wParam:(unsigned long)wParam lParam:(long)lParam;
- (void)rememberPreviousTab:(NppDocument *)doc;

/// The tab Recent Window would step back to, or nil.
- (nullable NppDocument *)previousTab;

// Window
- (void)sortTabsBy:(NppTabSort)key ascending:(BOOL)ascending;
- (NSArray<NSString *> *)windowList;
- (BOOL)activateRecentWindow;

// Run
- (nullable NSString *)runShellCommand:(NSString *)command;
- (NSString *)validateShortcutsFile;

// Help / info
- (NSString *)debugInfo;
- (NSString *)commandLineArgumentsHelp;

@end

NS_ASSUME_NONNULL_END

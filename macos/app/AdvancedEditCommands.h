// The remaining Edit-menu commands: multi-selection, column editing, actions on
// the selection, paste special and auto-completion helpers.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSInteger, NppMatchFlags) {
    NppMatchNone      = 0,
    NppMatchCase      = 1 << 0,
    NppMatchWholeWord = 1 << 1,
};

@interface EditorController (AdvancedEditCommands)

// Multi-selection
- (NSUInteger)multiSelectAllOccurrences:(NppMatchFlags)flags;
- (BOOL)multiSelectNextOccurrence:(NppMatchFlags)flags;
- (BOOL)undoLastMultiSelection;
- (BOOL)skipCurrentMultiSelection;
- (NSUInteger)selectionCount;

// Begin/End select (sticky anchor)
- (BOOL)beginEndSelectColumnMode:(BOOL)columnMode;
- (BOOL)beginEndSelectActive;

// Column editor
- (BOOL)columnInsertText:(NSString *)text;
- (BOOL)columnInsertNumbersFrom:(long)initial increment:(long)increment
                    zeroPadded:(BOOL)padded base:(int)base;

// On selection
- (nullable NSString *)selectionAsPath;
- (BOOL)openSelectedFile;
- (BOOL)revealSelectedFile;
- (BOOL)redactSelectionWithBlock:(BOOL)solidBlock;
- (BOOL)searchSelectionOnInternet;
@property (nonatomic, copy) NSString *searchEngineTemplate;   // %@ is the query

// Paste special
- (BOOL)pasteAsHTML;
- (BOOL)pasteAsRTF;
- (BOOL)copySelectionAsBinary;
- (BOOL)cutSelectionAsBinary;
- (BOOL)pasteBinary;

// Auto-completion helpers
- (BOOL)showPathCompletion;
- (BOOL)showFunctionCallTip;
- (BOOL)cycleFunctionCallTip:(BOOL)forward;

// File attribute
- (BOOL)systemReadOnly;
- (BOOL)toggleSystemReadOnly;

@end

NS_ASSUME_NONNULL_END

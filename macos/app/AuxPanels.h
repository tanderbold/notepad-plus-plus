// Character Panel and Clipboard History: the two remaining Edit-menu panels.
#import <Cocoa/Cocoa.h>
@class EditorController;

NS_ASSUME_NONNULL_BEGIN

/// Lists characters by code point; double-click inserts one at the caret.
@interface CharacterPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic, readonly) NSInteger rowCount;
/// Inserts the character at `row`; exposed for tests.
- (BOOL)insertRow:(NSInteger)row;
@end

/// Keeps what has been on the pasteboard; double-click pastes an entry back.
@interface ClipboardHistoryPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
- (void)capturePasteboard;               // records the current pasteboard text
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic, readonly) NSArray<NSString *> *entries;
- (BOOL)pasteRow:(NSInteger)row;
@end

NS_ASSUME_NONNULL_END

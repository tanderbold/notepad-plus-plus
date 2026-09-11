// "Function List": the declarations found in the current document, in a panel.
// Notepad++ drives this from functionList.xml regexes; the same idea is used
// here with a per-language pattern table.
#import <Cocoa/Cocoa.h>
@class EditorController;

@interface FunctionListPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
- (void)reload;
@property (nonatomic, readonly) BOOL visible;
/// Names found in the current document; exposed for tests.
- (NSArray<NSString *> *)functionNames;
@end

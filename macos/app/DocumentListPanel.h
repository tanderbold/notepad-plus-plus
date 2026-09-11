// "Document List": a floating panel listing the open tabs, the macOS stand-in
// for Notepad++'s docked Document List.
#import <Cocoa/Cocoa.h>
@class EditorController;

@interface DocumentListPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic, readonly) NSInteger rowCount;
@end

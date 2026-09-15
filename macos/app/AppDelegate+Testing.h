// Surface used by the built-in test suite (NPPMAC_TEST=1). These are the very
// code paths the menu items drive; tests call them directly so no modal panel
// is involved.
#import "AppDelegate.h"

@class EditorController;

@interface AppDelegate (Testing)
@property (nonatomic, copy) NSString *lastSearchTerm;
- (EditorController *)editor;
- (BOOL)searchFrom:(long)start forward:(BOOL)forward wrap:(BOOL)wrap;

// Find panel: the controls the Find dialog carries, and what they add up to.
- (void)buildFindPanel;
- (id)currentFindSpec;

// File
- (void)newDocument:(id)sender;
- (void)closeTab:(id)sender;
// Edit
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (void)cutText:(id)sender;
- (void)copyText:(id)sender;
- (void)pasteText:(id)sender;
- (void)selectAllText:(id)sender;
- (void)duplicateLine:(id)sender;
// Window / view modes
@property (nonatomic, strong) NSWindow *window;
- (void)toggleDistractionFree:(id)sender;
- (void)togglePostIt:(id)sender;
- (void)toggleAlwaysOnTop:(id)sender;
- (void)toggleFileBrowser:(id)sender;
- (void)toggleDocumentList:(id)sender;
- (void)applyToolbarPreferences;
// View
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)zoomReset:(id)sender;
- (void)toggleWordWrap:(id)sender;
- (void)toggleWhitespace:(id)sender;
@end

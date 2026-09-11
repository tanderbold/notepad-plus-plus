// "Folder as Workspace": a file tree beside the editor, the macOS stand-in for
// Notepad++'s docked Folder as Workspace panel.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WorkspacePanelDelegate <NSObject>
- (void)workspaceDidActivateFile:(NSString *)path;
@end

@interface WorkspacePanel : NSObject
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<WorkspacePanelDelegate> delegate;
@property (nonatomic, readonly, nullable) NSString *rootPath;

- (instancetype)initWithFrame:(NSRect)frame;
- (void)setRootPath:(nullable NSString *)path;
/// Files currently listed at the top level; used by tests.
- (NSArray<NSString *> *)topLevelNames;
@end

NS_ASSUME_NONNULL_END

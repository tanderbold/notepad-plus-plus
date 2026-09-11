// Preferences, Style Configurator and Shortcut Mapper windows.
#import <Cocoa/Cocoa.h>
@class EditorController;

NS_ASSUME_NONNULL_BEGIN

/// Applies a "cmd+shift+k" style specification to a menu item.
void ApplyShortcutSpec(NSMenuItem *item, NSString *spec);

@interface PreferencesWindow : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
@end

@interface StyleConfiguratorWindow : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
/// Number of styles listed for the language currently shown; used by tests.
@property (nonatomic, readonly) NSInteger styleCount;
@end

@interface ShortcutMapperWindow : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
/// Menu commands that carry a keyboard shortcut.
@property (nonatomic, readonly) NSArray<NSString *> *commandTitles;
@end

NS_ASSUME_NONNULL_END

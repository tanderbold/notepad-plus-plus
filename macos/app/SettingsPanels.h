// Preferences, Style Configurator and Shortcut Mapper windows.
#import <Cocoa/Cocoa.h>
@class EditorController;

NS_ASSUME_NONNULL_BEGIN

/// Applies a "cmd+shift+k" style specification to a menu item.

@interface PreferencesWindow : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
/// The category names, in the order they are listed; exposed for tests.
- (NSArray<NSString *> *)categoryNames;
/// Whether a setting has a control on some page.
- (BOOL)hasControlForKey:(NSString *)key;
- (void)showPageAtIndex:(NSInteger)index;
@property (nonatomic, readonly) BOOL visible;
/// Writes every control into the preferences and applies them, as the
/// Apply button does; here so the suite can drive it.
- (void)apply:(id)sender;
@end

@interface StyleConfiguratorWindow : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
/// Number of styles listed for the language currently shown; used by tests.
@property (nonatomic, readonly) NSInteger styleCount;
@end


NS_ASSUME_NONNULL_END

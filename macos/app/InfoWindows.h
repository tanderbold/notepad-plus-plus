// Help > About and Help > Debug Info, laid out as Notepad++'s dialogs are.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Upstream's licence text, as the About box shows it.
extern NSString *const NppLicenceText;

@interface NppAboutWindow : NSObject
+ (instancetype)shared;
- (void)show;
@property (nonatomic, readonly) NSPanel *panel;
/// The version line: "Notepad++ v8.9.8   (ARM 64-bit)".
+ (NSString *)versionLine;
/// "(32-bit)", "(64-bit)" or "(ARM 64-bit)", as upstream names the build.
+ (NSString *)bitness;
@end

@interface NppDebugInfoWindow : NSObject
+ (instancetype)shared;
- (void)showText:(NSString *)text;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NSTextView *textView;
/// The dialog's "Copy debug info to clipboard".
- (void)copyToClipboard:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END

// Localisation from Notepad++'s own translations (installer/nativeLang/*.xml):
// menu commands by their command id, top menus and submenus by upstream's
// menuId / subMenuId, and every other string - dialog controls, window
// titles, message boxes - by the English text it has in english.xml.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppLocalization : NSObject
+ (instancetype)shared;
/// The translations there are: file name -> the language's own name.
+ (NSDictionary<NSString *, NSString *> *)availableLanguages;
/// Loads "russian.xml" (or none for English); YES when it was found.
- (BOOL)loadLanguageFile:(nullable NSString *)fileName;
@property (nonatomic, readonly, copy, nullable) NSString *languageFile;
@property (nonatomic, readonly) BOOL active;
/// A menu command's text, by upstream's command id.
- (nullable NSString *)commandName:(int)identifier;
/// The tab context menu's own wording for a command, when the file has one.
- (nullable NSString *)tabCommandName:(int)identifier;
/// The translation of an English string, or the string itself.
- (NSString *)translate:(nullable NSString *)english;
/// As translate:, preferring the names upstream gives windows and tabs.
- (NSString *)translateTitle:(nullable NSString *)english;
/// The main menu: commands by id (from `idsByItem`), menus and submenus by name.
- (void)localizeMenu:(NSMenu *)menu identifiers:(NSDictionary<NSNumber *, NSMenuItem *> *)idsByItem;
/// A window's controls and title.
- (void)localizeWindow:(NSWindow *)window;
- (void)localizeView:(NSView *)view;
@end

/// The translated form of an English interface string.
FOUNDATION_EXPORT NSString *NppL(NSString *english);
/// A menu item's or menu's English title, whatever it shows now: what the
/// Shortcut Mapper and shortcuts.xml go by.
FOUNDATION_EXPORT NSString *NppEnglishTitle(NSMenuItem *item);
FOUNDATION_EXPORT NSString *NppEnglishMenuTitle(NSMenu *menu);

NS_ASSUME_NONNULL_END

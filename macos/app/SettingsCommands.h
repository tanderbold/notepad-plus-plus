// Settings menu: preferences, style configurator, shortcut mapper, imports and
// the editor's context menu.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// The app's settings, stored in NSUserDefaults and applied to the editor.
@interface NppPreferences : NSObject
+ (instancetype)shared;

@property (nonatomic, copy) NSString *fontName;
@property (nonatomic) NSInteger fontSize;
@property (nonatomic) NSInteger tabWidth;
@property (nonatomic) BOOL useSpaces;
@property (nonatomic) BOOL wordWrap;
@property (nonatomic) BOOL showWhitespace;
@property (nonatomic) BOOL showIndentGuides;
@property (nonatomic) BOOL restoreSession;
@property (nonatomic) NSInteger defaultEOL;              // SC_EOL_*
@property (nonatomic, copy) NSString *defaultEncoding;   // "UTF-8", "UTF-8-BOM", ...

/// Foreground overrides, keyed "<language>/<styleID>" -> hex RGB.
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *styleOverrides;
- (void)setStyleOverride:(nullable NSString *)hexRGB
             forLanguage:(NSString *)language styleID:(int)styleID;

/// Shortcut overrides, keyed by menu title -> "cmd+shift+k" style string.
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *shortcutOverrides;
- (void)setShortcutOverride:(nullable NSString *)spec forCommand:(NSString *)title;

/// Commands listed in the editor's right-click menu, by menu title.
@property (nonatomic, copy) NSArray<NSString *> *contextMenuCommands;

- (void)applyToEditor:(EditorController *)editor;
- (void)reset;
@end

@interface EditorController (SettingsCommands)

/// Folder holding macros, plugins, themes and user-defined languages.
- (NSString *)supportDirectory;
- (NSString *)userDefinedLanguagePath;

- (NSUInteger)importFiles:(NSArray<NSString *> *)paths intoSubdirectory:(NSString *)subdir;
- (NSArray<NSString *> *)importedFilesIn:(NSString *)subdir;

/// Writes a user-defined language into userDefineLang.xml and loads it.
- (BOOL)defineUserLanguageNamed:(NSString *)name
                     extensions:(NSString *)extensions
                       keywords:(NSString *)keywords
                    commentLine:(NSString *)commentLine;
- (nullable NSDictionary *)userDefinedLanguage;

@end

NS_ASSUME_NONNULL_END

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

/// Appearance. 0 follows the system, 1 forces light, 2 forces dark.
@property (nonatomic) NSInteger appearanceMode;
@property (nonatomic, copy) NSString *lightThemeName;   // "Default" = stylers.model.xml
@property (nonatomic, copy) NSString *darkThemeName;    // "DarkModeDefault"
/// Toolbar. 0 = icon only, 1 = icon and label, 2 = label only; size 0 regular, 1 small.
@property (nonatomic) BOOL showToolbar;
@property (nonatomic) NSInteger toolbarDisplayMode;
@property (nonatomic) NSInteger toolbarIconSize;

/// Backup. 0 none, 1 simple (.bak beside the file), 2 verbose (timestamped).
@property (nonatomic) NSInteger backupMode;
@property (nonatomic, copy) NSString *backupDirectory;   // empty = the support folder
@property (nonatomic) BOOL autosaveEnabled;
@property (nonatomic) NSInteger autosaveInterval;        // seconds

/// Print. Colour mode 0 as shown, 1 inverted, 2 black on white, 3 no background.
@property (nonatomic) BOOL printLineNumbers;
@property (nonatomic) NSInteger printColourMode;
@property (nonatomic) double printMarginLeft;
@property (nonatomic) double printMarginRight;
@property (nonatomic) double printMarginTop;
@property (nonatomic) double printMarginBottom;
@property (nonatomic, copy) NSString *printHeaderLeft;
@property (nonatomic, copy) NSString *printHeaderMiddle;
@property (nonatomic, copy) NSString *printHeaderRight;
@property (nonatomic, copy) NSString *printFooterLeft;
@property (nonatomic, copy) NSString *printFooterMiddle;
@property (nonatomic, copy) NSString *printFooterRight;
@property (nonatomic, copy) NSString *printHeaderFontName;
@property (nonatomic) NSInteger printHeaderFontSize;
@property (nonatomic) BOOL printHeaderBold;
@property (nonatomic) BOOL printHeaderItalic;

/// Performance: large-file restriction and what stays allowed above it.
@property (nonatomic) BOOL largeFileRestrictionEnabled;
@property (nonatomic) NSInteger largeFileThresholdMB;      // 1 - 2046, as upstream
@property (nonatomic) BOOL largeFileDeactivateWordWrap;
@property (nonatomic) BOOL largeFileAllowAutoCompletion;
@property (nonatomic) BOOL largeFileAllowSmartHighlighting;
@property (nonatomic) BOOL largeFileAllowBraceMatch;
@property (nonatomic) BOOL largeFileAllowClickableLinks;
@property (nonatomic) BOOL suppressHugeFileWarning;

/// Clickable links.
@property (nonatomic) BOOL linksEnabled;
@property (nonatomic) BOOL linksNoUnderline;
@property (nonatomic) BOOL linksFullBox;
@property (nonatomic, copy) NSString *linkCustomSchemes;

/// Editing aids.
@property (nonatomic) BOOL braceMatchEnabled;
@property (nonatomic) BOOL smartHighlightEnabled;

/// Word characters and delimiter selection.
@property (nonatomic) BOOL customWordCharsEnabled;
@property (nonatomic, copy) NSString *customWordChars;
@property (nonatomic, copy) NSString *delimiterOpen;
@property (nonatomic, copy) NSString *delimiterClose;
@property (nonatomic) BOOL delimiterMultiline;

/// Multi-instance. 0 mono-instance, 1 always multi-instance, 2 session per instance.
@property (nonatomic) NSInteger multiInstanceMode;
@property (nonatomic) BOOL reverseDateTimeOrder;
@property (nonatomic) BOOL rememberPanelState;
@property (nonatomic, copy) NSDictionary *panelState;

/// Auto-completion.
@property (nonatomic) BOOL autoCompleteOnInput;
@property (nonatomic) NSInteger autoCompleteSource;      // 0 functions, 1 words, 2 both
@property (nonatomic) NSInteger autoCompleteThreshold;   // characters before it opens
@property (nonatomic) BOOL autoCompleteBriefList;
@property (nonatomic) BOOL autoCompleteIgnoreNumbers;
@property (nonatomic) BOOL autoCompleteUseTab;           // NO means Enter accepts
@property (nonatomic) BOOL functionHintOnInput;
@property (nonatomic) BOOL autoInsertParenthesis;
@property (nonatomic) BOOL autoInsertBracket;
@property (nonatomic) BOOL autoInsertBrace;
@property (nonatomic) BOOL autoInsertSingleQuote;
@property (nonatomic) BOOL autoInsertDoubleQuote;
@property (nonatomic) BOOL autoInsertCloseTag;

/// New documents.
@property (nonatomic, copy) NSString *defaultLanguage;
@property (nonatomic) BOOL openNewDocumentAtStartup;
@property (nonatomic) BOOL untitledFromFirstLine;

/// Tab bar.
@property (nonatomic) BOOL hideTabBar;
@property (nonatomic) BOOL tabDoubleClickCloses;
@property (nonatomic) BOOL exitOnClosingLastTab;
@property (nonatomic) BOOL tabShowCloseButton;
@property (nonatomic) BOOL tabPinFeatureEnabled;

/// Recent files.
@property (nonatomic, copy) NSArray<NSString *> *recentFiles;
@property (nonatomic) NSInteger recentFilesMax;
@property (nonatomic) BOOL recentFilesShowFullPath;
@property (nonatomic) NSInteger recentFilesMaxLength;

/// Default directory. 0 follow the document, 1 remember the last, 2 a fixed one.
@property (nonatomic) NSInteger defaultDirectoryMode;
@property (nonatomic, copy) NSString *lastUsedDirectory;
@property (nonatomic, copy) NSString *fixedDirectory;

/// Searching.
@property (nonatomic) BOOL findFillWithSelection;
@property (nonatomic) BOOL findSelectWordUnderCaret;
@property (nonatomic) BOOL replaceStaysOnOccurrence;
@property (nonatomic) BOOL confirmReplaceAll;

/// Smart highlighting refinements.
@property (nonatomic) BOOL smartHighlightMatchCase;
@property (nonatomic) BOOL smartHighlightWholeWord;

/// Settings folder ("cloud location"); empty means the default support folder.
@property (nonatomic, copy) NSString *settingsDirectory;

/// The theme that should be in effect right now.
- (NSString *)effectiveThemeName;
- (BOOL)systemIsDark;

/// Style overrides, keyed "<language>/<styleID>". Each value is a dictionary
/// carrying any of: fg, bg (hex RGB), bold, italic, underline (booleans),
/// font (name) and size. A bare string is read as a foreground colour, so
/// settings written by the earlier foreground-only version still load.
@property (nonatomic, copy) NSDictionary<NSString *, id> *styleOverrides;
- (nullable NSDictionary *)styleOverrideForLanguage:(NSString *)language styleID:(int)styleID;
- (void)setStyleOverride:(nullable NSDictionary *)attributes
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

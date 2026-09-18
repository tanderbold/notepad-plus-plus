#import "SettingsCommands.h"
#import "UserLanguages.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"

static NSString *const kDefaultsPrefix = @"NppMac.";

static NSString *Key(NSString *name) { return [kDefaultsPrefix stringByAppendingString:name]; }

@implementation NppPreferences

+ (instancetype)shared {
    static NppPreferences *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[NppPreferences alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    // Defaults chosen to match what the editor already did before it had settings.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        Key(@"fontName"):        @"Menlo",
        Key(@"fontSize"):        @13,
        Key(@"tabWidth"):        @4,
        Key(@"useSpaces"):       @NO,
        Key(@"wordWrap"):        @NO,
        Key(@"showWhitespace"):  @NO,
        Key(@"showIndentGuides"):@YES,
        Key(@"restoreSession"):  @NO,
        Key(@"detectLanguageFromContent"): @YES,
        Key(@"defaultEOL"):      @(SC_EOL_LF),
        Key(@"defaultEncoding"): @"UTF-8",
        Key(@"appearanceMode"):  @0,
        Key(@"showToolbar"):     @YES,
        Key(@"toolbarDisplayMode"): @0,
        Key(@"toolbarIconSize"): @1,
        Key(@"backupMode"):      @0,
        Key(@"backupDirectory"): @"",
        Key(@"autosaveEnabled"): @NO,
        Key(@"fileAutoDetection"): @YES,
        Key(@"autoDetectCharacterEncoding"): @YES,
        Key(@"fileAutoDetectionSilent"): @NO,
        Key(@"fileAutoDetectionScrollToEnd"): @NO,
        Key(@"autosaveInterval"): @60,
        Key(@"printLineNumbers"): @NO,
        Key(@"printColourMode"): @2,
        Key(@"printMarginLeft"): @36.0,
        Key(@"printMarginRight"): @36.0,
        Key(@"printMarginTop"): @36.0,
        Key(@"printMarginBottom"): @36.0,
        Key(@"printHeaderLeft"): @"$(FULL_CURRENT_PATH)",
        Key(@"printHeaderMiddle"): @"",
        Key(@"printHeaderRight"): @"$(CURRENT_DATE)",
        Key(@"printFooterLeft"): @"",
        Key(@"printFooterMiddle"): @"Page $(CURRENT_PRINTING_PAGE) of $(TOTAL_PRINTING_PAGE)",
        Key(@"printFooterRight"): @"",
        Key(@"printHeaderFontName"): @"Helvetica",
        Key(@"printHeaderFontSize"): @9,
        Key(@"printHeaderBold"): @NO,
        Key(@"printHeaderItalic"): @NO,
        Key(@"largeFileRestrictionEnabled"): @YES,
        Key(@"largeFileThresholdMB"): @200,
        Key(@"largeFileDeactivateWordWrap"): @YES,
        Key(@"largeFileAllowAutoCompletion"): @NO,
        Key(@"largeFileAllowSmartHighlighting"): @NO,
        Key(@"largeFileAllowBraceMatch"): @NO,
        Key(@"largeFileAllowClickableLinks"): @NO,
        Key(@"suppressHugeFileWarning"): @NO,
        Key(@"linksEnabled"): @YES,
        Key(@"linksNoUnderline"): @NO,
        Key(@"linksFullBox"): @NO,
        Key(@"linkCustomSchemes"): @"",
        Key(@"braceMatchEnabled"): @YES,
        Key(@"smartHighlightEnabled"): @YES,
        Key(@"customWordCharsEnabled"): @NO,
        Key(@"customWordChars"): @"",
        Key(@"delimiterOpen"): @"(",
        Key(@"delimiterClose"): @")",
        Key(@"delimiterMultiline"): @NO,
        Key(@"multiInstanceMode"): @0,
        Key(@"reverseDateTimeOrder"): @NO,
        Key(@"rememberPanelState"): @NO,
        Key(@"panelState"): @{},
        Key(@"settingsDirectory"): @"",
        Key(@"compareIgnoreCase"): @NO,
        Key(@"compareIgnoreSpaces"): @NO,
        Key(@"compareIgnoreEmptyLines"): @NO,
        Key(@"jsonIndent"): @4,
        Key(@"ftpProfiles"): @[],
        Key(@"savedRunCommands"): @[],
        Key(@"edgeMode"): @0,
        Key(@"edgeColumns"): @"80",
        Key(@"caretWidth"): @1,
        Key(@"caretBlinkRate"): @530,          // the Windows default
        Key(@"scrollBeyondLastLine"): @YES,
        Key(@"virtualSpace"): @NO,
        // These defaults are Notepad++'s own, from ScintillaViewParams.
        Key(@"autoIndentMode"): @2,            // Notepad++ defaults to advanced
        Key(@"markAllCaseSensitive"): @NO,
        Key(@"markAllWordOnly"): @YES,
        Key(@"lineCopyCutWithoutSelection"): @YES,
        Key(@"currentLineHighlightMode"): @1,
        Key(@"currentLineFrameWidth"): @1,
        Key(@"foldMarginShow"): @YES,
        Key(@"bookmarkMarginShow"): @YES,
        Key(@"lineWrapMethod"): @1,            // aligned
        Key(@"paddingLeft"): @0,
        Key(@"paddingRight"): @0,
        Key(@"rightClickKeepsSelection"): @NO,
        Key(@"selectedTextDragDrop"): @YES,
        Key(@"autoCompleteOnInput"): @YES,
        Key(@"autoCompleteSource"): @2,
        Key(@"autoCompleteThreshold"): @1,
        Key(@"autoCompleteBriefList"): @NO,
        Key(@"autoCompleteIgnoreNumbers"): @YES,
        Key(@"autoCompleteUseTab"): @YES,
        Key(@"functionHintOnInput"): @YES,
        Key(@"autoInsertParenthesis"): @NO,
        Key(@"autoInsertBracket"): @NO,
        Key(@"autoInsertBrace"): @NO,
        Key(@"autoInsertSingleQuote"): @NO,
        Key(@"autoInsertDoubleQuote"): @NO,
        Key(@"autoInsertCloseTag"): @NO,
        Key(@"defaultLanguage"): @"",
        Key(@"openNewDocumentAtStartup"): @YES,
        Key(@"untitledFromFirstLine"): @NO,
        Key(@"hideTabBar"): @NO,
        Key(@"tabDoubleClickCloses"): @NO,
        Key(@"exitOnClosingLastTab"): @NO,
        Key(@"tabShowCloseButton"): @NO,
        Key(@"tabPinFeatureEnabled"): @YES,
        Key(@"tabCloseButtonOnInactive"): @NO,
        Key(@"tabBarLocked"): @NO,
        Key(@"tabBarVertical"): @NO,
        Key(@"tabBarMultiLine"): @NO,
        Key(@"recentFiles"): @[],
        Key(@"recentFilesMax"): @10,
        Key(@"recentFilesShowFullPath"): @NO,
        Key(@"recentFilesMaxLength"): @60,
        Key(@"defaultDirectoryMode"): @0,
        Key(@"lastUsedDirectory"): @"",
        Key(@"fixedDirectory"): @"",
        Key(@"findFillWithSelection"): @YES,
        Key(@"findSelectWordUnderCaret"): @YES,
        Key(@"replaceStaysOnOccurrence"): @NO,
        Key(@"confirmReplaceAll"): @YES,
        Key(@"smartHighlightMatchCase"): @NO,
        Key(@"smartHighlightWholeWord"): @YES,
        Key(@"lightThemeName"):  @"Default",
        Key(@"darkThemeName"):   @"DarkModeDefault",
        Key(@"styleOverrides"):  @{},
        Key(@"globalOverride"):  @{},
        Key(@"userMatchedPairs"): @[],
        Key(@"findHistory"): @[], Key(@"replaceHistory"): @[],
        Key(@"filterHistory"): @[], Key(@"directoryHistory"): @[],
        Key(@"findTransparencyMode"): @1, Key(@"findTransparencyLevel"): @150,
        Key(@"searchResultsPurge"): @NO,
        Key(@"docListExtColumn"): @YES, Key(@"docListPathColumn"): @NO,
        Key(@"docPeekOnTab"): @NO, Key(@"docPeekOnMap"): @NO,
        Key(@"docSwitcherEnabled"): @YES, Key(@"docSwitcherMRU"): @YES,
        Key(@"titleBarFileNameOnly"): @NO, Key(@"confirmSaveAll"): @YES, Key(@"muteSounds"): @NO,
        Key(@"sessionFileExtension"): @"", Key(@"workspaceFileExtension"): @"",
        Key(@"workspaceSymlinks"): @NO, Key(@"searchEngine"): @1, Key(@"searchEngineCustom"): @"",
        Key(@"languageMenuHidden"): @[], Key(@"languageMenuCompact"): @YES, Key(@"sqlBackslashEscape"): @YES,
        Key(@"languageIndent"): @{}, Key(@"backspaceUnindents"): @NO, Key(@"statusBarHidden"): @NO,
        Key(@"shortcutOverrides"): @{},
        Key(@"contextMenuCommands"): @[@"Cut", @"Copy", @"Paste", @"Select All",
                                       @"Toggle Line Comment", @"Go to Matching Brace"],
    }];
    return self;
}

#define NPP_PREF_OBJ(getter, setter, type, key)                                   \
- (type *)getter { return [[NSUserDefaults standardUserDefaults] objectForKey:Key(key)]; } \
- (void)setter:(type *)value {                                                    \
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:Key(key)];       \
}

#define NPP_PREF_INT(getter, setter, key)                                         \
- (NSInteger)getter { return [[NSUserDefaults standardUserDefaults] integerForKey:Key(key)]; } \
- (void)setter:(NSInteger)value {                                                 \
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:Key(key)];      \
}

#define NPP_PREF_BOOL(getter, setter, key)                                        \
- (BOOL)getter { return [[NSUserDefaults standardUserDefaults] boolForKey:Key(key)]; }  \
- (void)setter:(BOOL)value {                                                      \
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:Key(key)];         \
}

NPP_PREF_OBJ(fontName, setFontName, NSString, @"fontName")
NPP_PREF_OBJ(defaultEncoding, setDefaultEncoding, NSString, @"defaultEncoding")
NPP_PREF_OBJ(lightThemeName, setLightThemeName, NSString, @"lightThemeName")
NPP_PREF_OBJ(darkThemeName, setDarkThemeName, NSString, @"darkThemeName")
NPP_PREF_OBJ(backupDirectory, setBackupDirectory, NSString, @"backupDirectory")
NPP_PREF_OBJ(printHeaderLeft, setPrintHeaderLeft, NSString, @"printHeaderLeft")
NPP_PREF_OBJ(printHeaderMiddle, setPrintHeaderMiddle, NSString, @"printHeaderMiddle")
NPP_PREF_OBJ(printHeaderRight, setPrintHeaderRight, NSString, @"printHeaderRight")
NPP_PREF_OBJ(printFooterLeft, setPrintFooterLeft, NSString, @"printFooterLeft")
NPP_PREF_OBJ(printFooterMiddle, setPrintFooterMiddle, NSString, @"printFooterMiddle")
NPP_PREF_OBJ(printFooterRight, setPrintFooterRight, NSString, @"printFooterRight")
NPP_PREF_OBJ(printHeaderFontName, setPrintHeaderFontName, NSString, @"printHeaderFontName")
NPP_PREF_OBJ(linkCustomSchemes, setLinkCustomSchemes, NSString, @"linkCustomSchemes")
NPP_PREF_OBJ(customWordChars, setCustomWordChars, NSString, @"customWordChars")
NPP_PREF_OBJ(delimiterOpen, setDelimiterOpen, NSString, @"delimiterOpen")
NPP_PREF_OBJ(delimiterClose, setDelimiterClose, NSString, @"delimiterClose")
NPP_PREF_OBJ(settingsDirectory, setSettingsDirectory, NSString, @"settingsDirectory")
NPP_PREF_OBJ(panelState, setPanelState, NSDictionary, @"panelState")
NPP_PREF_OBJ(defaultLanguage, setDefaultLanguage, NSString, @"defaultLanguage")
NPP_PREF_OBJ(recentFiles, setRecentFiles, NSArray, @"recentFiles")
NPP_PREF_OBJ(lastUsedDirectory, setLastUsedDirectory, NSString, @"lastUsedDirectory")
NPP_PREF_OBJ(fixedDirectory, setFixedDirectory, NSString, @"fixedDirectory")
NPP_PREF_OBJ(ftpProfiles, setFtpProfiles, NSArray, @"ftpProfiles")
NPP_PREF_OBJ(savedRunCommands, setSavedRunCommands, NSArray, @"savedRunCommands")
NPP_PREF_INT(edgeMode, setEdgeMode, @"edgeMode")
NPP_PREF_OBJ(edgeColumns, setEdgeColumns, NSString, @"edgeColumns")
NPP_PREF_INT(caretWidth, setCaretWidth, @"caretWidth")
NPP_PREF_INT(caretBlinkRate, setCaretBlinkRate, @"caretBlinkRate")
NPP_PREF_BOOL(scrollBeyondLastLine, setScrollBeyondLastLine, @"scrollBeyondLastLine")
NPP_PREF_BOOL(virtualSpace, setVirtualSpace, @"virtualSpace")
NPP_PREF_INT(autoIndentMode, setAutoIndentMode, @"autoIndentMode")
NPP_PREF_BOOL(markAllCaseSensitive, setMarkAllCaseSensitive, @"markAllCaseSensitive")
NPP_PREF_BOOL(markAllWordOnly, setMarkAllWordOnly, @"markAllWordOnly")
NPP_PREF_BOOL(lineCopyCutWithoutSelection, setLineCopyCutWithoutSelection, @"lineCopyCutWithoutSelection")
NPP_PREF_INT(currentLineHighlightMode, setCurrentLineHighlightMode, @"currentLineHighlightMode")
NPP_PREF_INT(currentLineFrameWidth, setCurrentLineFrameWidth, @"currentLineFrameWidth")
NPP_PREF_BOOL(foldMarginShow, setFoldMarginShow, @"foldMarginShow")
NPP_PREF_BOOL(bookmarkMarginShow, setBookmarkMarginShow, @"bookmarkMarginShow")
NPP_PREF_INT(lineWrapMethod, setLineWrapMethod, @"lineWrapMethod")
NPP_PREF_INT(paddingLeft, setPaddingLeft, @"paddingLeft")
NPP_PREF_INT(paddingRight, setPaddingRight, @"paddingRight")
NPP_PREF_BOOL(rightClickKeepsSelection, setRightClickKeepsSelection, @"rightClickKeepsSelection")
NPP_PREF_BOOL(selectedTextDragDrop, setSelectedTextDragDrop, @"selectedTextDragDrop")
NPP_PREF_OBJ(styleOverrides, setStyleOverrides, NSDictionary, @"styleOverrides")
NPP_PREF_OBJ(globalOverride, setGlobalOverride, NSDictionary, @"globalOverride")
NPP_PREF_OBJ(userMatchedPairs, setUserMatchedPairs, NSArray, @"userMatchedPairs")
NPP_PREF_OBJ(findHistory, setFindHistory, NSArray, @"findHistory")
NPP_PREF_OBJ(replaceHistory, setReplaceHistory, NSArray, @"replaceHistory")
NPP_PREF_OBJ(filterHistory, setFilterHistory, NSArray, @"filterHistory")
NPP_PREF_OBJ(directoryHistory, setDirectoryHistory, NSArray, @"directoryHistory")
NPP_PREF_INT(findTransparencyMode, setFindTransparencyMode, @"findTransparencyMode")
NPP_PREF_INT(findTransparencyLevel, setFindTransparencyLevel, @"findTransparencyLevel")
NPP_PREF_BOOL(searchResultsPurge, setSearchResultsPurge, @"searchResultsPurge")
NPP_PREF_BOOL(docListExtColumn, setDocListExtColumn, @"docListExtColumn")
NPP_PREF_BOOL(docListPathColumn, setDocListPathColumn, @"docListPathColumn")
NPP_PREF_BOOL(docPeekOnTab, setDocPeekOnTab, @"docPeekOnTab")
NPP_PREF_BOOL(docPeekOnMap, setDocPeekOnMap, @"docPeekOnMap")
NPP_PREF_BOOL(docSwitcherEnabled, setDocSwitcherEnabled, @"docSwitcherEnabled")
NPP_PREF_BOOL(docSwitcherMRU, setDocSwitcherMRU, @"docSwitcherMRU")
NPP_PREF_BOOL(titleBarFileNameOnly, setTitleBarFileNameOnly, @"titleBarFileNameOnly")
NPP_PREF_BOOL(confirmSaveAll, setConfirmSaveAll, @"confirmSaveAll")
NPP_PREF_BOOL(muteSounds, setMuteSounds, @"muteSounds")
NPP_PREF_OBJ(sessionFileExtension, setSessionFileExtension, NSString, @"sessionFileExtension")
NPP_PREF_OBJ(workspaceFileExtension, setWorkspaceFileExtension, NSString, @"workspaceFileExtension")
NPP_PREF_BOOL(workspaceSymlinks, setWorkspaceSymlinks, @"workspaceSymlinks")
NPP_PREF_INT(searchEngine, setSearchEngine, @"searchEngine")
NPP_PREF_OBJ(searchEngineCustom, setSearchEngineCustom, NSString, @"searchEngineCustom")
NPP_PREF_OBJ(languageMenuHidden, setLanguageMenuHidden, NSArray, @"languageMenuHidden")
NPP_PREF_BOOL(languageMenuCompact, setLanguageMenuCompact, @"languageMenuCompact")
NPP_PREF_BOOL(sqlBackslashEscape, setSqlBackslashEscape, @"sqlBackslashEscape")
NPP_PREF_OBJ(languageIndent, setLanguageIndent, NSDictionary, @"languageIndent")
NPP_PREF_BOOL(backspaceUnindents, setBackspaceUnindents, @"backspaceUnindents")
NPP_PREF_BOOL(statusBarHidden, setStatusBarHidden, @"statusBarHidden")
NPP_PREF_OBJ(shortcutOverrides, setShortcutOverrides, NSDictionary, @"shortcutOverrides")
NPP_PREF_OBJ(contextMenuCommands, setContextMenuCommands, NSArray, @"contextMenuCommands")
NPP_PREF_INT(fontSize, setFontSize, @"fontSize")
NPP_PREF_INT(tabWidth, setTabWidth, @"tabWidth")
NPP_PREF_INT(defaultEOL, setDefaultEOL, @"defaultEOL")
NPP_PREF_INT(appearanceMode, setAppearanceMode, @"appearanceMode")
NPP_PREF_INT(toolbarDisplayMode, setToolbarDisplayMode, @"toolbarDisplayMode")
NPP_PREF_INT(toolbarIconSize, setToolbarIconSize, @"toolbarIconSize")
NPP_PREF_INT(backupMode, setBackupMode, @"backupMode")
NPP_PREF_INT(autosaveInterval, setAutosaveInterval, @"autosaveInterval")
NPP_PREF_INT(printColourMode, setPrintColourMode, @"printColourMode")
NPP_PREF_INT(printHeaderFontSize, setPrintHeaderFontSize, @"printHeaderFontSize")
NPP_PREF_INT(largeFileThresholdMB, setLargeFileThresholdMB, @"largeFileThresholdMB")
NPP_PREF_INT(multiInstanceMode, setMultiInstanceMode, @"multiInstanceMode")
NPP_PREF_INT(autoCompleteSource, setAutoCompleteSource, @"autoCompleteSource")
NPP_PREF_INT(autoCompleteThreshold, setAutoCompleteThreshold, @"autoCompleteThreshold")
NPP_PREF_INT(recentFilesMax, setRecentFilesMax, @"recentFilesMax")
NPP_PREF_INT(recentFilesMaxLength, setRecentFilesMaxLength, @"recentFilesMaxLength")
NPP_PREF_INT(defaultDirectoryMode, setDefaultDirectoryMode, @"defaultDirectoryMode")
NPP_PREF_INT(jsonIndent, setJsonIndent, @"jsonIndent")
NPP_PREF_BOOL(useSpaces, setUseSpaces, @"useSpaces")
NPP_PREF_BOOL(wordWrap, setWordWrap, @"wordWrap")
NPP_PREF_BOOL(showWhitespace, setShowWhitespace, @"showWhitespace")
NPP_PREF_BOOL(showIndentGuides, setShowIndentGuides, @"showIndentGuides")
NPP_PREF_BOOL(restoreSession, setRestoreSession, @"restoreSession")
NPP_PREF_BOOL(detectLanguageFromContent, setDetectLanguageFromContent, @"detectLanguageFromContent")
NPP_PREF_BOOL(showToolbar, setShowToolbar, @"showToolbar")
NPP_PREF_BOOL(autosaveEnabled, setAutosaveEnabled, @"autosaveEnabled")
NPP_PREF_BOOL(fileAutoDetection, setFileAutoDetection, @"fileAutoDetection")
NPP_PREF_BOOL(autoDetectCharacterEncoding, setAutoDetectCharacterEncoding, @"autoDetectCharacterEncoding")
NPP_PREF_BOOL(fileAutoDetectionSilent, setFileAutoDetectionSilent, @"fileAutoDetectionSilent")
NPP_PREF_BOOL(fileAutoDetectionScrollToEnd, setFileAutoDetectionScrollToEnd, @"fileAutoDetectionScrollToEnd")
NPP_PREF_BOOL(printLineNumbers, setPrintLineNumbers, @"printLineNumbers")
NPP_PREF_BOOL(printHeaderBold, setPrintHeaderBold, @"printHeaderBold")
NPP_PREF_BOOL(printHeaderItalic, setPrintHeaderItalic, @"printHeaderItalic")
NPP_PREF_BOOL(largeFileRestrictionEnabled, setLargeFileRestrictionEnabled, @"largeFileRestrictionEnabled")
NPP_PREF_BOOL(largeFileDeactivateWordWrap, setLargeFileDeactivateWordWrap, @"largeFileDeactivateWordWrap")
NPP_PREF_BOOL(largeFileAllowAutoCompletion, setLargeFileAllowAutoCompletion, @"largeFileAllowAutoCompletion")
NPP_PREF_BOOL(largeFileAllowSmartHighlighting, setLargeFileAllowSmartHighlighting, @"largeFileAllowSmartHighlighting")
NPP_PREF_BOOL(largeFileAllowBraceMatch, setLargeFileAllowBraceMatch, @"largeFileAllowBraceMatch")
NPP_PREF_BOOL(largeFileAllowClickableLinks, setLargeFileAllowClickableLinks, @"largeFileAllowClickableLinks")
NPP_PREF_BOOL(suppressHugeFileWarning, setSuppressHugeFileWarning, @"suppressHugeFileWarning")
NPP_PREF_BOOL(linksEnabled, setLinksEnabled, @"linksEnabled")
NPP_PREF_BOOL(linksNoUnderline, setLinksNoUnderline, @"linksNoUnderline")
NPP_PREF_BOOL(linksFullBox, setLinksFullBox, @"linksFullBox")
NPP_PREF_BOOL(braceMatchEnabled, setBraceMatchEnabled, @"braceMatchEnabled")
NPP_PREF_BOOL(smartHighlightEnabled, setSmartHighlightEnabled, @"smartHighlightEnabled")
NPP_PREF_BOOL(customWordCharsEnabled, setCustomWordCharsEnabled, @"customWordCharsEnabled")
NPP_PREF_BOOL(delimiterMultiline, setDelimiterMultiline, @"delimiterMultiline")
NPP_PREF_BOOL(reverseDateTimeOrder, setReverseDateTimeOrder, @"reverseDateTimeOrder")
NPP_PREF_BOOL(rememberPanelState, setRememberPanelState, @"rememberPanelState")
NPP_PREF_BOOL(autoCompleteOnInput, setAutoCompleteOnInput, @"autoCompleteOnInput")
NPP_PREF_BOOL(autoCompleteBriefList, setAutoCompleteBriefList, @"autoCompleteBriefList")
NPP_PREF_BOOL(autoCompleteIgnoreNumbers, setAutoCompleteIgnoreNumbers, @"autoCompleteIgnoreNumbers")
NPP_PREF_BOOL(autoCompleteUseTab, setAutoCompleteUseTab, @"autoCompleteUseTab")
NPP_PREF_BOOL(functionHintOnInput, setFunctionHintOnInput, @"functionHintOnInput")
NPP_PREF_BOOL(autoInsertParenthesis, setAutoInsertParenthesis, @"autoInsertParenthesis")
NPP_PREF_BOOL(autoInsertBracket, setAutoInsertBracket, @"autoInsertBracket")
NPP_PREF_BOOL(autoInsertBrace, setAutoInsertBrace, @"autoInsertBrace")
NPP_PREF_BOOL(autoInsertSingleQuote, setAutoInsertSingleQuote, @"autoInsertSingleQuote")
NPP_PREF_BOOL(autoInsertDoubleQuote, setAutoInsertDoubleQuote, @"autoInsertDoubleQuote")
NPP_PREF_BOOL(autoInsertCloseTag, setAutoInsertCloseTag, @"autoInsertCloseTag")
NPP_PREF_BOOL(openNewDocumentAtStartup, setOpenNewDocumentAtStartup, @"openNewDocumentAtStartup")
NPP_PREF_BOOL(untitledFromFirstLine, setUntitledFromFirstLine, @"untitledFromFirstLine")
NPP_PREF_BOOL(hideTabBar, setHideTabBar, @"hideTabBar")
NPP_PREF_BOOL(tabDoubleClickCloses, setTabDoubleClickCloses, @"tabDoubleClickCloses")
NPP_PREF_BOOL(exitOnClosingLastTab, setExitOnClosingLastTab, @"exitOnClosingLastTab")
NPP_PREF_BOOL(tabShowCloseButton, setTabShowCloseButton, @"tabShowCloseButton")
NPP_PREF_BOOL(tabPinFeatureEnabled, setTabPinFeatureEnabled, @"tabPinFeatureEnabled")
NPP_PREF_BOOL(tabCloseButtonOnInactive, setTabCloseButtonOnInactive, @"tabCloseButtonOnInactive")
NPP_PREF_BOOL(tabBarLocked, setTabBarLocked, @"tabBarLocked")
NPP_PREF_BOOL(tabBarVertical, setTabBarVertical, @"tabBarVertical")
NPP_PREF_BOOL(tabBarMultiLine, setTabBarMultiLine, @"tabBarMultiLine")
NPP_PREF_BOOL(recentFilesShowFullPath, setRecentFilesShowFullPath, @"recentFilesShowFullPath")
NPP_PREF_BOOL(findFillWithSelection, setFindFillWithSelection, @"findFillWithSelection")
NPP_PREF_BOOL(findSelectWordUnderCaret, setFindSelectWordUnderCaret, @"findSelectWordUnderCaret")
NPP_PREF_BOOL(replaceStaysOnOccurrence, setReplaceStaysOnOccurrence, @"replaceStaysOnOccurrence")
NPP_PREF_BOOL(confirmReplaceAll, setConfirmReplaceAll, @"confirmReplaceAll")
NPP_PREF_BOOL(smartHighlightMatchCase, setSmartHighlightMatchCase, @"smartHighlightMatchCase")
NPP_PREF_BOOL(smartHighlightWholeWord, setSmartHighlightWholeWord, @"smartHighlightWholeWord")
NPP_PREF_BOOL(compareIgnoreCase, setCompareIgnoreCase, @"compareIgnoreCase")
NPP_PREF_BOOL(compareIgnoreSpaces, setCompareIgnoreSpaces, @"compareIgnoreSpaces")
NPP_PREF_BOOL(compareIgnoreEmptyLines, setCompareIgnoreEmptyLines, @"compareIgnoreEmptyLines")

#define NPP_PREF_DOUBLE(getter, setter, key)                                      \
- (double)getter { return [[NSUserDefaults standardUserDefaults] doubleForKey:Key(key)]; } \
- (void)setter:(double)value {                                                    \
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:Key(key)];       \
}

NPP_PREF_DOUBLE(printMarginLeft, setPrintMarginLeft, @"printMarginLeft")
NPP_PREF_DOUBLE(printMarginRight, setPrintMarginRight, @"printMarginRight")
NPP_PREF_DOUBLE(printMarginTop, setPrintMarginTop, @"printMarginTop")
NPP_PREF_DOUBLE(printMarginBottom, setPrintMarginBottom, @"printMarginBottom")

- (BOOL)systemIsDark {
    NSString *match = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSString *)effectiveThemeName {
    BOOL dark = self.appearanceMode == 2 || (self.appearanceMode == 0 && [self systemIsDark]);
    // A user language made for dark mode is chosen by extension in dark mode.
    [LanguageCatalog sharedCatalog].darkMode = dark;
    return dark ? (self.darkThemeName ?: @"DarkModeDefault") : (self.lightThemeName ?: @"Default");
}

- (void)setStyleOverride:(NSDictionary *)attributes
             forLanguage:(NSString *)language styleID:(int)styleID {
    NSMutableDictionary *all = [self.styleOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@/%d", language, styleID];
    if (attributes.count) all[key] = attributes; else [all removeObjectForKey:key];
    self.styleOverrides = all;
}

- (NSDictionary *)styleOverrideForLanguage:(NSString *)language styleID:(int)styleID {
    id stored = self.styleOverrides[[NSString stringWithFormat:@"%@/%d", language, styleID]];
    if ([stored isKindOfClass:[NSDictionary class]]) return stored;
    // Settings written by the foreground-only version were a bare hex string.
    if ([stored isKindOfClass:[NSString class]]) return @{@"fg": stored};
    return nil;
}

- (NSInteger)tabWidthForLanguage:(NSString *)language {
    NSDictionary *own = language ? self.languageIndent[language] : nil;
    return [own[@"size"] integerValue] > 0 ? [own[@"size"] integerValue] : MAX(1, self.tabWidth);
}

- (BOOL)useSpacesForLanguage:(NSString *)language {
    NSDictionary *own = language ? self.languageIndent[language] : nil;
    return own[@"spaces"] ? [own[@"spaces"] boolValue] : self.useSpaces;
}

- (NSString *)searchEngineTemplate {
    switch (self.searchEngine) {
        case 0: return @"https://duckduckgo.com/?q=%@";
        case 2: return @"https://www.bing.com/search?q=%@";
        case 3: return @"https://search.yahoo.com/search?q=%@";
        case 4: {
            // Upstream writes the words as $(CURRENT_WORD).
            NSString *custom = [self.searchEngineCustom stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
            custom = [custom stringByReplacingOccurrencesOfString:@"$(CURRENT_WORD)" withString:@"%@"];
            if ([custom rangeOfString:@"%@"].location != NSNotFound) return custom;
            break;
        }
        default: break;
    }
    return @"https://www.google.com/search?q=%@";
}

- (void)setShortcutOverride:(NSString *)spec forCommand:(NSString *)title {
    NSMutableDictionary *all = [self.shortcutOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
    if (spec.length) all[title] = spec; else [all removeObjectForKey:title];
    self.shortcutOverrides = all;
}

- (void)applyToEditor:(EditorController *)editor {
    // The theme decides the colours, so it is loaded before the styles are set.
    NSString *wanted = [self effectiveThemeName];
    if (![[StyleCatalog sharedCatalog].themeName isEqualToString:wanted]) {
        [StyleCatalog loadThemeNamed:wanted];
        [editor applyLanguage];
    }
    ScintillaView *sci = editor.sci;
    [sci setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:self.fontName];
    [sci message:SCI_STYLESETSIZE wParam:STYLE_DEFAULT lParam:self.fontSize];
    [editor applyDocumentSettings];
    [sci message:SCI_SETWRAPMODE wParam:(uptr_t)(self.wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE) lParam:0];
    [sci message:SCI_SETVIEWWS
           wParam:(uptr_t)(self.showWhitespace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE) lParam:0];
    [sci message:SCI_SETINDENTATIONGUIDES
           wParam:(uptr_t)(self.showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE) lParam:0];
    [editor refreshChrome];
}

- (void)reset {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in [[d dictionaryRepresentation] allKeys]) {
        if ([key hasPrefix:kDefaultsPrefix]) [d removeObjectForKey:key];
    }
}

@end

#pragma mark - Editor side

void NppBeep(void) {
    if (![NppPreferences shared].muteSounds) NSBeep();
}

@implementation EditorController (SettingsCommands)

static NSString *gSettingsDirectoryForThisLaunch;

+ (void)setSettingsDirectoryForThisLaunch:(NSString *)directory {
    gSettingsDirectoryForThisLaunch = [directory copy];
}

- (NSString *)supportDirectory {
    // -settingsDir= on the command line, for this launch only; then the
    // preference; then the default.
    NSString *override = gSettingsDirectoryForThisLaunch.length
        ? gSettingsDirectoryForThisLaunch : [NppPreferences shared].settingsDirectory;
    NSString *dir = override.length
        ? override
        : self.defaultSessionPath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    return dir;
}

- (NSString *)userDefinedLanguagePath {
    return [[self supportDirectory] stringByAppendingPathComponent:@"userDefineLang.xml"];
}

- (NSUInteger)importFiles:(NSArray<NSString *> *)paths intoSubdirectory:(NSString *)subdir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dest = [[self supportDirectory] stringByAppendingPathComponent:subdir];
    [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:NULL];

    NSUInteger copied = 0;
    for (NSString *src in paths) {
        NSString *target = [dest stringByAppendingPathComponent:src.lastPathComponent];
        [fm removeItemAtPath:target error:NULL];      // importing again replaces
        if ([fm copyItemAtPath:src toPath:target error:NULL]) copied++;
    }
    return copied;
}

- (NSArray<NSString *> *)importedFilesIn:(NSString *)subdir {
    NSString *dir = [[self supportDirectory] stringByAppendingPathComponent:subdir];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    return [names sortedArrayUsingSelector:@selector(compare:)] ?: @[];
}

/// Writes the language in the same shape Notepad++ uses for userDefineLang.xml,
/// so the file is recognisable to anyone who has seen the Windows one.
static NSString *XMLEscaped(NSString *text) {
    NSMutableString *out = [(text ?: @"") mutableCopy];
    [out replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, out.length)];
    return out;
}

- (BOOL)defineUserLanguageNamed:(NSString *)name
                     extensions:(NSString *)extensions
                       keywords:(NSString *)keywords
                    commentLine:(NSString *)commentLine {
    if (!name.length) return NO;
    NSString *xml = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n"
        @"<NotepadPlus>\n"
        @"    <UserLang name=\"%@\" ext=\"%@\" udlVersion=\"2.1\">\n"
        @"        <Settings>\n"
        @"            <Global caseIgnored=\"no\" />\n"
        @"        </Settings>\n"
        @"        <KeywordLists>\n"
        @"            <Keywords name=\"Comments\">%@</Keywords>\n"
        @"            <Keywords name=\"Keywords1\">%@</Keywords>\n"
        @"        </KeywordLists>\n"
        @"    </UserLang>\n"
        @"</NotepadPlus>\n",
        XMLEscaped(name), XMLEscaped(extensions), XMLEscaped(commentLine), XMLEscaped(keywords)];

    if (![xml writeToFile:[self userDefinedLanguagePath] atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL]) return NO;

    // Read back the way every user language is, and applied to the document.
    [[LanguageCatalog sharedCatalog] reloadUserLanguagesFromDirectory:[self supportDirectory]];
    // Shown on the document in front, as the Windows dialog previews it, but
    // not as a choice the user made: a rename still re-detects the language.
    [self setLanguageNamed:name];
    return YES;
}

- (NSDictionary *)userDefinedLanguage {
    NSString *xml = [NSString stringWithContentsOfFile:[self userDefinedLanguagePath]
                                              encoding:NSUTF8StringEncoding error:NULL];
    if (!xml.length) return nil;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"<UserLang name=\"([^\"]*)\" ext=\"([^\"]*)\""
                             options:0 error:&err];
    NSTextCheckingResult *m = [re firstMatchInString:xml options:0 range:NSMakeRange(0, xml.length)];
    if (!m) return nil;
    return @{@"name": [xml substringWithRange:[m rangeAtIndex:1]],
             @"ext":  [xml substringWithRange:[m rangeAtIndex:2]]};
}

@end

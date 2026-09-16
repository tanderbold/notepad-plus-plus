// Multi-document editor built on one ScintillaView, switching Scintilla
// documents per tab -- the same model Notepad++ uses on Windows.
#import <Cocoa/Cocoa.h>
#import "TabBarView.h"

@class ScintillaView;
@class NppLanguage;

NS_ASSUME_NONNULL_BEGIN

/// Posted whenever the set of open documents changes, so panels listing them
/// can reload instead of drawing from a stale row count.
extern NSString *const NppEditorDocumentsDidChangeNotification;

@interface NppDocument : NSObject
@property (nonatomic) void *docPointer;                 // Scintilla document
@property (nonatomic, copy, nullable) NSString *path;   // nil until saved
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong, nullable) NppLanguage *language;
@property (nonatomic) BOOL modified;
@property (nonatomic) NSStringEncoding encoding;   // encoding the file was read with / will be written with
@property (nonatomic) BOOL hasBOM;
/// Non-zero when the document is held in a Windows code page that has no
/// NSStringEncoding of its own (currently only 720); 0 means use `encoding`.
@property (nonatomic) unsigned int codepage;
@property (nonatomic) int eolMode;                 // SC_EOL_CRLF / SC_EOL_LF / SC_EOL_CR
@property (nonatomic) BOOL pinned;                 // survives Close All but Pinned
@property (nonatomic) NSInteger tabColour;         // 0 = none, 1..5 as in Notepad++
/// Set when the language was chosen from the menu rather than worked out from
/// the file name. Renaming then leaves it alone, as Notepad++ does.
@property (nonatomic) BOOL languageChosenByUser;
@end

@interface EditorController : NSObject <NppTabBarDelegate>
@property (nonatomic, readonly) ScintillaView *sci;
@property (nonatomic, readonly) NSView *view;           // tab bar + editor + status bar
@property (nonatomic, readonly) NSArray<NppDocument *> *documents;
@property (nonatomic, readonly) NppDocument *currentDocument;
@property (nonatomic, weak, nullable) NSWindow *window;

- (instancetype)initWithFrame:(NSRect)frame;

- (void)newDocument;
- (BOOL)openFileAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)saveCurrentDocument;          // prompts if unsaved
/// Writes the current document to `path` in its own encoding, making a backup
/// first when Preferences asks for one.
- (BOOL)writeCurrentToPath:(NSString *)path;
- (BOOL)saveCurrentDocumentAs;
- (void)closeCurrentDocument;
/// Non-interactive close used by the Close All family and by tests.
- (void)closeDocumentAtIndex:(NSInteger)index discardChanges:(BOOL)discard;

// File commands
- (BOOL)reloadCurrentDocument:(NSError **)error;
- (BOOL)saveCopyOfCurrentTo:(NSString *)path error:(NSError **)error;
- (NSUInteger)saveAllDocuments;
- (BOOL)renameCurrentTo:(NSString *)newPath error:(NSError **)error;
- (BOOL)moveCurrentToTrash:(NSError **)error;
- (void)closeAllDocuments;
- (void)closeAllButCurrent;
- (void)closeAllToLeft;
- (void)closeAllToRight;
- (void)closeAllUnchanged;
- (void)closeAllButPinned;
- (void)togglePinCurrent;
- (BOOL)printCurrentShowingPanel:(BOOL)showPanel;
/// The print job, built but not run -- lets tests check it without printing.
- (nullable NSPrintOperation *)printOperationForCurrentShowingPanel:(BOOL)showPanel;

// "Open Containing Folder" family. The target is resolved separately from the
// launch so tests can check it without opening Finder or Terminal.
- (nullable NSURL *)containingFolderURL;
- (BOOL)revealInFinder;
- (BOOL)openContainingFolderInTerminal;   // macOS stand-in for both cmd and PowerShell
- (BOOL)openInDefaultViewer;

// Folder as Workspace
- (void)openFolderAsWorkspace:(nullable NSString *)path;   // nil hides the panel
- (BOOL)workspaceVisible;
- (nullable NSString *)workspaceRootPath;
- (NSArray<NSString *> *)workspaceTopLevelNames;

// Sessions
- (BOOL)saveSessionTo:(NSString *)path error:(NSError **)error;
- (BOOL)loadSessionFrom:(NSString *)path error:(NSError **)error;
- (NSString *)defaultSessionPath;
- (void)selectDocumentAtIndex:(NSInteger)index;

- (void)setLanguageNamed:(NSString *)langName;   // manual override
/// The same, marking the choice as the user's so a rename will not undo it.
- (void)chooseLanguageNamed:(NSString *)langName;
- (void)setEncoding:(NSStringEncoding)enc withBOM:(BOOL)bom;   // re-saves in this encoding
- (void)convertEOLTo:(int)eolMode;
- (NSString *)encodingDisplayName;

// Editing commands
- (void)toggleLineComment;
- (void)toggleBlockComment;
- (void)toggleBookmark;
- (void)nextBookmark;
- (void)previousBookmark;
- (void)clearBookmarks;
- (void)foldAll:(BOOL)fold;
- (void)toggleFoldAtCursor;
- (void)foldCurrent:(BOOL)fold;   // IDM_VIEW_FOLD_CURRENT / IDM_VIEW_UNFOLD_CURRENT
- (void)showAutoCompletion;
- (void)applyTheme;                               // re-apply npp styles (e.g. on appearance change)
- (void)applyLanguage;                            // re-attach lexer, keywords and styles
- (void)rebuildContextMenu;                       // right-click menu from Preferences
- (void)applyTabBarPreferences;                   // layout and behaviour of the tab bar
/// Overtype: what the status bar shows as INS or OVR, and what the Insert key
/// switches between.
@property (nonatomic) BOOL overtype;
- (void)toggleOvertype;
/// Pushes the editor settings that are not per document into Scintilla.
- (void)applyEditorPreferences;

- (void)refreshChrome;                            // tab titles + status bar
- (void)setChromeVisible:(BOOL)visible;           // hides tab bar + status bar
- (BOOL)chromeVisible;

// Second editor pane. Notepad++ calls these "views"; here the primary pane
// owns the tab bar and the secondary one shows a moved or cloned document.
@property (nonatomic, readonly) ScintillaView *secondarySci;
- (BOOL)secondaryViewVisible;
- (void)setSecondaryViewVisible:(BOOL)visible;
- (void)focusOtherView;
- (BOOL)otherViewHasFocus;
- (BOOL)moveCurrentToOtherView;
- (BOOL)cloneCurrentToOtherView;
- (BOOL)syncVerticalScroll;
- (void)setSyncVerticalScroll:(BOOL)on;
- (BOOL)syncHorizontalScroll;
- (void)setSyncHorizontalScroll:(BOOL)on;
- (BOOL)syncZoom;
- (void)setSyncZoom:(BOOL)on;
- (void)mirrorScrollToSecondary;
- (void)mirrorScrollFromSecondary;
- (BOOL)openCurrentInNewInstanceMoving:(BOOL)closeHere;

// Document Map: a shrunken read-only view of the same buffer.
- (BOOL)documentMapVisible;
- (void)setDocumentMapVisible:(BOOL)visible;

// Project panels 1..3, each keeping its own folder root.
- (void)showProjectPanel:(NSInteger)index;        // 1..3; same index again hides it
- (NSInteger)activeProjectPanel;                  // 0 when none is shown
- (void)setProjectPanel:(NSInteger)index root:(nullable NSString *)path;
- (nullable NSString *)projectPanelRoot:(NSInteger)index;
- (NSArray<NSString *> *)projectPanelNames:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END

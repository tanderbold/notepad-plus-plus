// Multi-document editor built on one ScintillaView, switching Scintilla
// documents per tab -- the same model Notepad++ uses on Windows.
#import <Cocoa/Cocoa.h>

@class ScintillaView;
@class NppLanguage;

NS_ASSUME_NONNULL_BEGIN

@interface NppDocument : NSObject
@property (nonatomic) void *docPointer;                 // Scintilla document
@property (nonatomic, copy, nullable) NSString *path;   // nil until saved
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong, nullable) NppLanguage *language;
@property (nonatomic) BOOL modified;
@property (nonatomic) NSStringEncoding encoding;   // encoding the file was read with / will be written with
@property (nonatomic) BOOL hasBOM;
@property (nonatomic) int eolMode;                 // SC_EOL_CRLF / SC_EOL_LF / SC_EOL_CR
@property (nonatomic) BOOL pinned;                 // survives Close All but Pinned
@property (nonatomic) NSInteger tabColour;         // 0 = none, 1..5 as in Notepad++
@end

@interface EditorController : NSObject
@property (nonatomic, readonly) ScintillaView *sci;
@property (nonatomic, readonly) NSView *view;           // tab bar + editor + status bar
@property (nonatomic, readonly) NSArray<NppDocument *> *documents;
@property (nonatomic, readonly) NppDocument *currentDocument;
@property (nonatomic, weak, nullable) NSWindow *window;

- (instancetype)initWithFrame:(NSRect)frame;

- (void)newDocument;
- (BOOL)openFileAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)saveCurrentDocument;          // prompts if unsaved
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
- (void)refreshChrome;                            // tab titles + status bar
- (void)setChromeVisible:(BOOL)visible;           // hides tab bar + status bar
- (BOOL)chromeVisible;

@end

NS_ASSUME_NONNULL_END

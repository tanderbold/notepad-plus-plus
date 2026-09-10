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
- (void)selectDocumentAtIndex:(NSInteger)index;

- (void)setLanguageNamed:(NSString *)langName;   // manual override
- (void)applyTheme;                               // re-apply npp styles (e.g. on appearance change)
- (void)refreshChrome;                            // tab titles + status bar

@end

NS_ASSUME_NONNULL_END

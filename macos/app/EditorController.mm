#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#import "WorkspacePanel.h"
#import "EncodingCommands.h"
#include "ILexer.h"
#include "Lexilla.h"

/// Marker 1: bookmarks. Fold markers occupy 25-31, so this cannot collide.
#define NPPMAC_BOOKMARK_MARKER 1

@implementation NppDocument
@end

/// ScintillaNotificationProtocol gives no sender, so the secondary pane gets its
/// own delegate object that tags the callback.
@interface NppSecondaryPaneDelegate : NSObject <ScintillaNotificationProtocol>
@property (nonatomic, weak) EditorController *owner;
@end

@implementation NppSecondaryPaneDelegate
- (void)notification:(SCNotification *)n {
    if (n->nmhdr.code == SCN_UPDATEUI) [self.owner mirrorScrollFromSecondary];
}
@end

@interface EditorController () <ScintillaNotificationProtocol, WorkspacePanelDelegate>
@property (nonatomic, strong) WorkspacePanel *workspace;
@property (nonatomic, strong) NSSplitView *split;
@property (nonatomic, strong) NSView *editorArea;
@property (nonatomic, strong) ScintillaView *secondaryView;
@property (nonatomic, strong) NSSplitView *editorSplit;
@property (nonatomic, strong) id secondaryDelegate;
@property (nonatomic) BOOL syncV;
@property (nonatomic) BOOL syncH;
@property (nonatomic) BOOL syncZ;
@property (nonatomic, strong) ScintillaView *docMapView;
@property (nonatomic, strong) NSMutableArray<WorkspacePanel *> *projects;
@property (nonatomic) NSInteger activeProject;
@property (nonatomic, strong) ScintillaView *sciView;
@property (nonatomic, strong) NSView *container;
@property (nonatomic, strong) NSSegmentedControl *tabBar;
@property (nonatomic, strong) NSTextField *statusField;
@property (nonatomic, strong) NSMutableArray<NppDocument *> *docs;
@property (nonatomic) NSInteger currentIndex;
@end

@implementation EditorController

/// Scintilla wants 0xBBGGRR. Note setColorProperty: puts the colour in lParam,
/// which is wrong for messages like SCI_SETCARETLINEBACK that take it in wParam,
/// so every colour goes through message:wParam:lParam: explicitly.
/// Sniffs a BOM, then falls back to UTF-8 and finally Latin-1, which always
/// succeeds -- the same order of preference a plain-text editor should use.
static NSString *DecodeText(NSData *data, NSStringEncoding *outEnc, BOOL *outBOM) {
    const unsigned char *b = (const unsigned char *)data.bytes;
    NSUInteger n = data.length;

    if (n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
        *outEnc = NSUTF8StringEncoding; *outBOM = YES;
        return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(3, n - 3)]
                                     encoding:NSUTF8StringEncoding];
    }
    if (n >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
        *outEnc = NSUTF16LittleEndianStringEncoding; *outBOM = YES;
        return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, n - 2)]
                                     encoding:NSUTF16LittleEndianStringEncoding];
    }
    if (n >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
        *outEnc = NSUTF16BigEndianStringEncoding; *outBOM = YES;
        return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, n - 2)]
                                     encoding:NSUTF16BigEndianStringEncoding];
    }

    *outBOM = NO;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s) { *outEnc = NSUTF8StringEncoding; return s; }
    *outEnc = NSISOLatin1StringEncoding;
    return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

/// First line ending wins, matching how Notepad++ reports a file's EOL.
static int DetectEOL(NSString *text) {
    NSRange cr = [text rangeOfString:@"\r"];
    NSRange lf = [text rangeOfString:@"\n"];
    if (cr.location == NSNotFound) return SC_EOL_LF;   // no CR at all, incl. no line ending
    if (lf.location == NSNotFound) return SC_EOL_CR;
    return (lf.location == cr.location + 1) ? SC_EOL_CRLF : SC_EOL_CR;
}

static NSData *EncodeText(NSString *text, NSStringEncoding enc, BOOL bom) {
    NSMutableData *out = [NSMutableData data];
    if (bom) {
        if (enc == NSUTF8StringEncoding) {
            const unsigned char b[] = {0xEF, 0xBB, 0xBF}; [out appendBytes:b length:3];
        } else if (enc == NSUTF16LittleEndianStringEncoding) {
            const unsigned char b[] = {0xFF, 0xFE}; [out appendBytes:b length:2];
        } else if (enc == NSUTF16BigEndianStringEncoding) {
            const unsigned char b[] = {0xFE, 0xFF}; [out appendBytes:b length:2];
        }
    }
    NSData *body = [text dataUsingEncoding:enc allowLossyConversion:YES];
    if (!body) return nil;
    [out appendData:body];
    return out;
}

static long SciColor(NSColor *c) {
    NSColor *d = [c colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    long r = (long)(d.redComponent * 255);
    long g = (long)(d.greenComponent * 255);
    long b = (long)(d.blueComponent * 255);
    return (b << 16) + (g << 8) + r;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super init])) return nil;
    _docs = [NSMutableArray array];
    _currentIndex = -1;

    _container = [[NSView alloc] initWithFrame:frame];
    _container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CGFloat tabH = 28, statusH = 22;

    NSRect upper = NSMakeRect(0, statusH, NSWidth(frame), NSHeight(frame) - statusH);

    _editorArea = [[NSView alloc] initWithFrame:upper];
    _editorArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _tabBar = [[NSSegmentedControl alloc] initWithFrame:
               NSMakeRect(0, NSHeight(upper) - tabH, NSWidth(upper), tabH)];
    _tabBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _tabBar.segmentStyle = NSSegmentStyleTexturedSquare;
    _tabBar.segmentCount = 0;
    _tabBar.target = self;
    _tabBar.action = @selector(tabClicked:);
    [_editorArea addSubview:_tabBar];

    NSRect editorRect = NSMakeRect(0, 0, NSWidth(upper), NSHeight(upper) - tabH);
    _sciView = [[ScintillaView alloc] initWithFrame:editorRect];
    _sciView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _sciView.delegate = self;

    _secondaryView = [[ScintillaView alloc] initWithFrame:editorRect];
    _secondaryDelegate = [[NppSecondaryPaneDelegate alloc] init];
    ((NppSecondaryPaneDelegate *)_secondaryDelegate).owner = self;
    _secondaryView.delegate = (id<ScintillaNotificationProtocol>)_secondaryDelegate;

    _editorSplit = [[NSSplitView alloc] initWithFrame:editorRect];
    _editorSplit.vertical = NO;                    // panes stacked, as Notepad++ splits
    _editorSplit.dividerStyle = NSSplitViewDividerStyleThin;
    _editorSplit.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_editorSplit addSubview:_sciView];
    [_editorArea addSubview:_editorSplit];

    _workspace = [[WorkspacePanel alloc] initWithFrame:NSMakeRect(0, 0, 220, NSHeight(upper))];
    _workspace.delegate = self;

    _projects = [NSMutableArray array];
    for (int i = 0; i < 3; ++i) {
        WorkspacePanel *p = [[WorkspacePanel alloc] initWithFrame:NSMakeRect(0, 0, 220, NSHeight(upper))];
        p.delegate = self;
        [_projects addObject:p];
    }

    _split = [[NSSplitView alloc] initWithFrame:upper];
    _split.vertical = YES;
    _split.dividerStyle = NSSplitViewDividerStyleThin;
    _split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_split addSubview:_editorArea];              // workspace is inserted when opened
    [_container addSubview:_split];

    _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(6, 2, NSWidth(frame) - 12, statusH - 4)];
    _statusField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    _statusField.bezeled = NO;
    _statusField.editable = NO;
    _statusField.selectable = NO;
    _statusField.drawsBackground = NO;
    _statusField.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _statusField.textColor = [NSColor secondaryLabelColor];
    [_container addSubview:_statusField];

    [self configureEditorChrome];
    [self newDocument];
    return self;
}

- (ScintillaView *)sci { return self.sciView; }
- (NSView *)view { return self.container; }
- (NSArray<NppDocument *> *)documents { return self.docs; }

- (NppDocument *)currentDocument {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.docs.count) return nil;
    return self.docs[self.currentIndex];
}

#pragma mark - Editor chrome

- (void)configureEditorChrome {
    ScintillaView *sci = self.sciView;
    [sci message:SCI_SETMARGINTYPEN wParam:0 lParam:SC_MARGIN_NUMBER];
    [sci message:SCI_SETMARGINWIDTHN wParam:0 lParam:52];
    // Margin 1: bookmarks. Margin 2: folding.
    [sci message:SCI_SETMARGINTYPEN wParam:1 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINWIDTHN wParam:1 lParam:14];
    [sci message:SCI_SETMARGINMASKN wParam:1 lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:1 lParam:1];
    [sci message:SCI_MARKERDEFINE wParam:NPPMAC_BOOKMARK_MARKER lParam:SC_MARK_BOOKMARK];

    [sci message:SCI_SETMARGINTYPEN wParam:2 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN wParam:2 lParam:(long)SC_MASK_FOLDERS];
    [sci message:SCI_SETMARGINWIDTHN wParam:2 lParam:16];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:2 lParam:1];
    [sci message:SCI_SETAUTOMATICFOLD wParam:(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE) lParam:0];
    for (int mk = SC_MARKNUM_FOLDEREND; mk <= SC_MARKNUM_FOLDEROPEN; ++mk) {
        [sci message:SCI_MARKERDEFINE wParam:(uptr_t)mk lParam:SC_MARK_BOXPLUS];
    }
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN lParam:SC_MARK_BOXMINUS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER lParam:SC_MARK_BOXPLUS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB lParam:SC_MARK_VLINE];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL lParam:SC_MARK_LCORNER];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEREND lParam:SC_MARK_BOXPLUSCONNECTED];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPENMID lParam:SC_MARK_BOXMINUSCONNECTED];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:SC_MARK_TCORNER];
    [sci message:SCI_SETCARETLINEVISIBLE wParam:1 lParam:0];
    [self applyDocumentSettings];
    [sci message:SCI_SETSCROLLWIDTHTRACKING wParam:1 lParam:0];
    [sci message:SCI_SETMULTIPLESELECTION wParam:1 lParam:0];
    [sci message:SCI_SETADDITIONALSELECTIONTYPING wParam:1 lParam:0];
}

/// Scintilla resets these when the document pointer changes, so they are
/// re-applied on every switch rather than only at startup.
- (void)applyDocumentSettings {
    ScintillaView *sci = self.sciView;
    [sci message:SCI_SETTABWIDTH wParam:4 lParam:0];
    [sci message:SCI_SETINDENT wParam:4 lParam:0];
    [sci message:SCI_SETUSETABS wParam:0 lParam:0];
    [sci message:SCI_SETINDENTATIONGUIDES wParam:SC_IV_LOOKBOTH lParam:0];
    [sci message:SCI_SETBACKSPACEUNINDENTS wParam:1 lParam:0];
    [sci message:SCI_SETTABINDENTS wParam:1 lParam:0];
    // Change History powers Search > Change History; it is per document.
    // Change History must have a margin of its own. A marker that belongs to no
    // margin is drawn by Scintilla as a whole-line background instead, which
    // paints every saved line in the "saved" colour.
    long historyMask = (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) |
                       (1 << SC_MARKNUM_HISTORY_SAVED) |
                       (1 << SC_MARKNUM_HISTORY_MODIFIED) |
                       (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED);
    [sci message:SCI_SETMARGINS wParam:4 lParam:0];
    [sci message:SCI_SETMARGINTYPEN wParam:3 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN wParam:3 lParam:historyMask];
    [sci message:SCI_SETMARGINWIDTHN wParam:3 lParam:6];
    [sci message:SCI_SETCHANGEHISTORY
           wParam:(SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS) lParam:0];
}

#pragma mark - Documents

- (void)newDocument {
    NppDocument *doc = [[NppDocument alloc] init];
    doc.docPointer = (void *)[self.sciView message:SCI_CREATEDOCUMENT wParam:0 lParam:SC_DOCUMENTOPTION_DEFAULT];
    doc.displayName = @"new 1";
    doc.language = [[LanguageCatalog sharedCatalog] languageNamed:@"normal"];
    doc.encoding = NSUTF8StringEncoding;
    doc.hasBOM = NO;
    doc.eolMode = SC_EOL_LF;      // macOS default; Notepad++ uses CRLF on Windows

    NSInteger n = 1;
    for (NppDocument *d in self.docs) if (!d.path) n++;
    doc.displayName = [NSString stringWithFormat:@"new %ld", (long)n];

    [self.docs addObject:doc];
    [self selectDocumentAtIndex:(NSInteger)self.docs.count - 1];
}

- (BOOL)openFileAtPath:(NSString *)path error:(NSError **)error {
    // Already open? Just focus it.
    for (NSUInteger i = 0; i < self.docs.count; ++i) {
        if ([self.docs[i].path isEqualToString:path]) { [self selectDocumentAtIndex:(NSInteger)i]; return YES; }
    }

    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return NO;

    NSStringEncoding used = NSUTF8StringEncoding;
    BOOL bom = NO;
    NSString *text = DecodeText(data, &used, &bom);
    if (!text) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSFileReadUnknownStringEncodingError
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Cannot decode %@", path.lastPathComponent]}];
        return NO;
    }

    NppDocument *doc = [[NppDocument alloc] init];
    doc.docPointer = (void *)[self.sciView message:SCI_CREATEDOCUMENT wParam:0 lParam:SC_DOCUMENTOPTION_DEFAULT];
    doc.path = path;
    doc.displayName = path.lastPathComponent;
    doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:path];
    doc.encoding = used;
    doc.hasBOM = bom;
    doc.codepage = 0;
    doc.eolMode = DetectEOL(text);

    [self.docs addObject:doc];
    [self selectDocumentAtIndex:(NSInteger)self.docs.count - 1];

    [self.sciView setString:text];
    [self.sciView message:SCI_SETEOLMODE wParam:(uptr_t)doc.eolMode lParam:0];
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    [self.sciView message:SCI_GOTOPOS wParam:0 lParam:0];
    [self.sciView message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    doc.modified = NO;

    [self applyLanguage];
    [self refreshChrome];
    [[NSDocumentController sharedDocumentController]
        noteNewRecentDocumentURL:[NSURL fileURLWithPath:path]];
    return YES;
}

- (void)selectDocumentAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.docs.count) return;
    self.currentIndex = index;
    NppDocument *doc = self.docs[index];
    [self.sciView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
    [self applyDocumentSettings];
    [self applyLanguage];
    [self refreshChrome];
    [self.window makeFirstResponder:self.sciView];
}

- (void)tabClicked:(NSSegmentedControl *)sender {
    [self selectDocumentAtIndex:sender.selectedSegment];
}

- (BOOL)saveCurrentDocument {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    if (!doc.path) return [self saveCurrentDocumentAs];
    return [self writeCurrentToPath:doc.path];
}

- (BOOL)saveCurrentDocumentAs {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = doc.path.lastPathComponent ?: doc.displayName;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return NO;
    NSString *path = panel.URL.path;
    if (![self writeCurrentToPath:path]) return NO;
    doc.path = path;
    doc.displayName = path.lastPathComponent;
    doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:path];
    [self applyLanguage];
    [self refreshChrome];
    return YES;
}

- (BOOL)writeCurrentToPath:(NSString *)path {
    NSError *err = nil;
    NSString *text = [self.sciView string] ?: @"";
    NppDocument *doc = self.currentDocument;
    NSStringEncoding enc = doc.encoding ?: NSUTF8StringEncoding;
    NSData *data = doc.codepage
        ? [EditorController dataFromString:text codepage:doc.codepage]
        : EncodeText(text, enc, doc.hasBOM);
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&err]) {
        if (!err) err = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
                                        userInfo:@{NSLocalizedDescriptionKey:
                                            @"Cannot encode the document in the selected encoding."}];
        [[NSAlert alertWithError:err] runModal];
        return NO;
    }
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    self.currentDocument.modified = NO;
    [self refreshChrome];
    return YES;
}

- (void)closeCurrentDocument {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;

    if (doc.modified) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Save changes to %@?", doc.displayName];
        alert.informativeText = @"Your changes will be lost if you don't save them.";
        [alert addButtonWithTitle:@"Save"];
        [alert addButtonWithTitle:@"Don't Save"];
        [alert addButtonWithTitle:@"Cancel"];
        NSModalResponse r = [alert runModal];
        if (r == NSAlertThirdButtonReturn) return;
        if (r == NSAlertFirstButtonReturn && ![self saveCurrentDocument]) return;
    }

    [self closeDocumentAtIndex:self.currentIndex discardChanges:YES];
}

- (void)closeDocumentAtIndex:(NSInteger)index discardChanges:(BOOL)discard {
    if (index < 0 || index >= (NSInteger)self.docs.count) return;
    NppDocument *doc = self.docs[index];
    if (!discard && doc.modified) return;

    [self.docs removeObjectAtIndex:index];

    if (self.docs.count == 0) {
        self.currentIndex = -1;
        [self newDocument];                       // switches the view off the old doc
    } else {
        [self selectDocumentAtIndex:MIN(index, (NSInteger)self.docs.count - 1)];
    }
    // Safe only once the view no longer points at it.
    [self.sciView message:SCI_RELEASEDOCUMENT wParam:0 lParam:(sptr_t)doc.docPointer];
}

#pragma mark - File commands

- (BOOL)reloadCurrentDocument:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                                            userInfo:@{NSLocalizedDescriptionKey: @"This document has never been saved."}];
        return NO;
    }
    NSData *data = [NSData dataWithContentsOfFile:doc.path options:0 error:error];
    if (!data) return NO;

    NSStringEncoding enc = NSUTF8StringEncoding; BOOL bom = NO;
    NSString *text = DecodeText(data, &enc, &bom);
    if (!text) return NO;

    long caret = [self.sciView message:SCI_GETCURRENTPOS];
    [self.sciView setString:text];
    doc.encoding = enc;
    doc.hasBOM = bom;
    doc.eolMode = DetectEOL(text);
    [self.sciView message:SCI_SETEOLMODE wParam:(uptr_t)doc.eolMode lParam:0];
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    [self.sciView message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    [self.sciView message:SCI_GOTOPOS
                   wParam:(uptr_t)MIN(caret, [self.sciView message:SCI_GETLENGTH]) lParam:0];
    doc.modified = NO;
    [self refreshChrome];
    return YES;
}

- (BOOL)saveCopyOfCurrentTo:(NSString *)path error:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    NSData *data = EncodeText([self.sciView string] ?: @"", doc.encoding ?: NSUTF8StringEncoding, doc.hasBOM);
    if (!data) return NO;
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

- (NSUInteger)saveAllDocuments {
    NSInteger restore = self.currentIndex;
    NSUInteger saved = 0;
    for (NSInteger i = 0; i < (NSInteger)self.docs.count; ++i) {
        NppDocument *d = self.docs[i];
        if (!d.path || !d.modified) continue;      // Save As prompts; skip unsaved ones
        [self selectDocumentAtIndex:i];
        if ([self writeCurrentToPath:d.path]) saved++;
    }
    [self selectDocumentAtIndex:restore];
    return saved;
}

- (BOOL)renameCurrentTo:(NSString *)newPath error:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) return [self saveCopyOfCurrentTo:newPath error:error] &&
                           ({ doc.path = newPath; doc.displayName = newPath.lastPathComponent; YES; });
    if (![[NSFileManager defaultManager] moveItemAtPath:doc.path toPath:newPath error:error]) return NO;
    doc.path = newPath;
    doc.displayName = newPath.lastPathComponent;
    doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:newPath];
    [self applyLanguage];
    [self refreshChrome];
    return YES;
}

/// macOS equivalent of Notepad++'s "Move to Recycle Bin".
- (BOOL)moveCurrentToTrash:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                                            userInfo:@{NSLocalizedDescriptionKey: @"This document has never been saved."}];
        return NO;
    }
    if (![[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:doc.path]
                                       resultingItemURL:nil error:error]) return NO;
    [self closeDocumentAtIndex:self.currentIndex discardChanges:YES];
    return YES;
}

- (void)closeAllDocuments {
    while (self.docs.count > 1) [self closeDocumentAtIndex:0 discardChanges:YES];
    [self closeDocumentAtIndex:0 discardChanges:YES];   // last one is replaced by a fresh tab
}

- (void)closeAllButCurrent {
    NppDocument *keep = self.currentDocument;
    for (NSInteger i = (NSInteger)self.docs.count - 1; i >= 0; --i) {
        if (self.docs[i] != keep) [self closeDocumentAtIndex:i discardChanges:YES];
    }
    [self reselectDocument:keep];
}

- (void)closeAllToLeft {
    NppDocument *keep = self.currentDocument;
    for (NSInteger i = self.currentIndex - 1; i >= 0; --i) {
        [self closeDocumentAtIndex:i discardChanges:YES];
    }
    [self reselectDocument:keep];
}

- (void)closeAllToRight {
    NppDocument *keep = self.currentDocument;
    // closeDocumentAtIndex: moves currentIndex, so the bound is captured first.
    NSInteger from = self.currentIndex;
    for (NSInteger i = (NSInteger)self.docs.count - 1; i > from; --i) {
        [self closeDocumentAtIndex:i discardChanges:YES];
    }
    [self reselectDocument:keep];
}

/// closeDocumentAtIndex: re-selects a tab as a side effect, so the document the
/// caller meant to keep has to be put back in front afterwards.
- (void)reselectDocument:(NppDocument *)doc {
    NSUInteger idx = [self.docs indexOfObject:doc];
    if (idx != NSNotFound) [self selectDocumentAtIndex:(NSInteger)idx];
}

- (void)closeAllButPinned {
    for (NSInteger i = (NSInteger)self.docs.count - 1; i >= 0; --i) {
        if (!self.docs[i].pinned) [self closeDocumentAtIndex:i discardChanges:YES];
    }
}

- (void)togglePinCurrent {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    doc.pinned = !doc.pinned;
    [self refreshChrome];
}

- (void)closeAllUnchanged {
    for (NSInteger i = (NSInteger)self.docs.count - 1; i >= 0; --i) {
        if (!self.docs[i].modified) [self closeDocumentAtIndex:i discardChanges:NO];
    }
}

- (NSPrintOperation *)printOperationForCurrentShowingPanel:(BOOL)showPanel {
    NppDocument *doc = self.currentDocument;
    if (!doc) return nil;
    NSTextView *page = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 540, 720)];
    page.string = [self.sciView string] ?: @"";
    page.font = [NSFont fontWithName:@"Menlo" size:10] ?: [NSFont userFixedPitchFontOfSize:10];

    NSPrintInfo *info = [NSPrintInfo sharedPrintInfo];
    info.horizontalPagination = NSPrintingPaginationModeFit;
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:page printInfo:info];
    op.showsPrintPanel = showPanel;
    op.showsProgressPanel = showPanel;
    op.jobTitle = doc.displayName;
    return op;
}

- (BOOL)printCurrentShowingPanel:(BOOL)showPanel {
    NSPrintOperation *op = [self printOperationForCurrentShowingPanel:showPanel];
    return op ? [op runOperation] : NO;
}

#pragma mark - Folder as Workspace

- (void)openFolderAsWorkspace:(NSString *)path {
    if (!path.length) {
        if (self.workspace.view.superview) [self.workspace.view removeFromSuperview];
        [self.workspace setRootPath:nil];
        [self.split adjustSubviews];
        return;
    }
    [self.workspace setRootPath:path];
    if (!self.workspace.view.superview) {
        [self.split addSubview:self.workspace.view positioned:NSWindowBelow relativeTo:self.editorArea];
        [self.split setPosition:220 ofDividerAtIndex:0];
    }
    [self.split adjustSubviews];
}

- (BOOL)workspaceVisible { return self.workspace.view.superview != nil; }
- (NSString *)workspaceRootPath { return self.workspace.rootPath; }
- (NSArray<NSString *> *)workspaceTopLevelNames { return [self.workspace topLevelNames]; }

- (void)workspaceDidActivateFile:(NSString *)path {
    NSError *err = nil;
    if (![self openFileAtPath:path error:&err] && err) [[NSAlert alertWithError:err] runModal];
}

#pragma mark - Open Containing Folder

- (NSURL *)containingFolderURL {
    NSString *path = self.currentDocument.path;
    if (!path.length) return nil;
    return [NSURL fileURLWithPath:path.stringByDeletingLastPathComponent isDirectory:YES];
}

- (BOOL)revealInFinder {
    NSString *path = self.currentDocument.path;
    if (!path.length) return NO;
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
    return YES;
}

/// Notepad++ offers "cmd" and "PowerShell" here; on macOS both mean Terminal.
- (BOOL)openContainingFolderInTerminal {
    NSURL *folder = self.containingFolderURL;
    if (!folder) return NO;
    NSURL *terminal = [[NSWorkspace sharedWorkspace]
        URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
    if (!terminal) return NO;
    [[NSWorkspace sharedWorkspace] openURLs:@[folder]
                       withApplicationAtURL:terminal
                              configuration:[NSWorkspaceOpenConfiguration configuration]
                          completionHandler:nil];
    return YES;
}

- (BOOL)openInDefaultViewer {
    NSString *path = self.currentDocument.path;
    if (!path.length) return NO;
    return [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

#pragma mark - Sessions

- (NSString *)defaultSessionPath {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"NotepadMac"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:@"session.json"];
}

- (BOOL)saveSessionTo:(NSString *)path error:(NSError **)error {
    NSMutableArray *files = [NSMutableArray array];
    for (NppDocument *d in self.docs) {
        if (!d.path) continue;                      // unsaved tabs have nothing to restore
        [files addObject:@{@"path": d.path,
                           @"language": d.language.name ?: @"normal"}];
    }
    NSDictionary *session = @{@"version": @1,
                              @"current": @(MAX(0, self.currentIndex)),
                              @"files": files};
    NSData *json = [NSJSONSerialization dataWithJSONObject:session
                                                   options:NSJSONWritingPrettyPrinted error:error];
    if (!json) return NO;
    return [json writeToFile:path options:NSDataWritingAtomic error:error];
}

- (BOOL)loadSessionFrom:(NSString *)path error:(NSError **)error {
    NSData *json = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!json) return NO;
    NSDictionary *session = [NSJSONSerialization JSONObjectWithData:json options:0 error:error];
    if (![session isKindOfClass:[NSDictionary class]]) return NO;

    NSArray *files = session[@"files"];
    if (![files isKindOfClass:[NSArray class]]) return NO;

    NSUInteger opened = 0;
    for (NSDictionary *f in files) {
        NSString *p = f[@"path"];
        if (![p isKindOfClass:[NSString class]]) continue;
        if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;   // deleted since
        if ([self openFileAtPath:p error:NULL]) {
            opened++;
            NSString *lang = f[@"language"];
            if ([lang isKindOfClass:[NSString class]] && lang.length) [self setLanguageNamed:lang];
        }
    }
    NSNumber *cur = session[@"current"];
    if ([cur isKindOfClass:[NSNumber class]]) {
        [self selectDocumentAtIndex:MIN(cur.integerValue, (NSInteger)self.docs.count - 1)];
    }
    return opened > 0 || files.count == 0;
}

#pragma mark - Language + theme

- (void)setLanguageNamed:(NSString *)langName {
    NppLanguage *lang = [[LanguageCatalog sharedCatalog] languageNamed:langName];
    if (!lang) return;
    self.currentDocument.language = lang;
    [self applyLanguage];
    [self refreshChrome];
}

- (void)applyLanguage {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    NppLanguage *lang = doc.language ?: [[LanguageCatalog sharedCatalog] languageNamed:@"normal"];
    ScintillaView *sci = self.sciView;

    void *lexer = CreateLexer(lang.lexerID.UTF8String);
    [sci message:SCI_SETILEXER wParam:0 lParam:(sptr_t)lexer];
    [sci setLexerProperty:@"fold" value:@"1"];
    [sci setLexerProperty:@"fold.compact" value:@"0"];

    for (NSNumber *idx in lang.keywordSets) {
        [sci setStringProperty:SCI_SETKEYWORDS parameter:idx.integerValue value:lang.keywordSets[idx]];
    }

    [self applyTheme];
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
}

- (void)applyTheme {
    ScintillaView *sci = self.sciView;
    StyleCatalog *styles = [StyleCatalog sharedCatalog];
    NppDocument *doc = self.currentDocument;
    NSString *langName = doc.language.name ?: @"normal";

    NppStyle *def = styles.globalStyles[@"Default Style"];
    NSString *fontName = def.fontName.length ? def.fontName : @"Menlo";
    // Courier New at size 10 is a Windows default; on macOS it reads far too small.
    int fontSize = (def.fontSize > 0) ? MAX(def.fontSize, 12) : 13;
    if ([fontName isEqualToString:@"Courier New"]) fontName = @"Menlo";

    [sci setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:fontName];
    [sci message:SCI_STYLESETSIZE wParam:STYLE_DEFAULT lParam:fontSize];
    if (def.foreground) [sci message:SCI_STYLESETFORE wParam:STYLE_DEFAULT lParam:SciColor(def.foreground)];
    if (def.background) [sci message:SCI_STYLESETBACK wParam:STYLE_DEFAULT lParam:SciColor(def.background)];
    [sci message:SCI_STYLECLEARALL wParam:0 lParam:0];   // propagate default to all styles first

    void (^applyStyle)(NppStyle *, int) = ^(NppStyle *s, int styleID) {
        if (s.foreground) [sci message:SCI_STYLESETFORE wParam:styleID lParam:SciColor(s.foreground)];
        if (s.background) [sci message:SCI_STYLESETBACK wParam:styleID lParam:SciColor(s.background)];
        if (s.fontStyle & 1) [sci message:SCI_STYLESETBOLD wParam:styleID lParam:1];
        if (s.fontStyle & 2) [sci message:SCI_STYLESETITALIC wParam:styleID lParam:1];
        if (s.fontStyle & 4) [sci message:SCI_STYLESETUNDERLINE wParam:styleID lParam:1];
        if (s.fontName.length) [sci setStringProperty:SCI_STYLESETFONT parameter:styleID value:s.fontName];
    };

    for (NppStyle *s in [styles stylesForLexerName:langName]) applyStyle(s, s.styleID);

    NppStyle *lineNo = styles.globalStyles[@"Line number margin"];
    if (lineNo) applyStyle(lineNo, STYLE_LINENUMBER);
    NppStyle *indent = styles.globalStyles[@"Indent guideline style"];
    if (indent) applyStyle(indent, STYLE_INDENTGUIDE);
    NppStyle *brace = styles.globalStyles[@"Brace highlight style"];
    if (brace) applyStyle(brace, STYLE_BRACELIGHT);
    NppStyle *badBrace = styles.globalStyles[@"Bad brace colour"];
    if (badBrace) applyStyle(badBrace, STYLE_BRACEBAD);

    // These take the colour in wParam, so they cannot go through applyStyle.
    NppStyle *caretLine = styles.globalStyles[@"Current line background colour"];
    if (caretLine.background) [sci message:SCI_SETCARETLINEBACK wParam:SciColor(caretLine.background) lParam:0];
    NppStyle *caret = styles.globalStyles[@"Caret colour"];
    if (caret.foreground) [sci message:SCI_SETCARETFORE wParam:SciColor(caret.foreground) lParam:0];
    NppStyle *sel = styles.globalStyles[@"Selected text colour"];
    if (sel.background) [sci message:SCI_SETSELBACK wParam:1 lParam:SciColor(sel.background)];
    NppStyle *ws = styles.globalStyles[@"White space symbol"];
    if (ws.foreground) [sci message:SCI_SETWHITESPACEFORE wParam:1 lParam:SciColor(ws.foreground)];

    // Change History markers, in the margin configured by applyDocumentSettings.
    struct { NSString *name; int marker; } history[] = {
        {@"Change History modified",        SC_MARKNUM_HISTORY_MODIFIED},
        {@"Change History saved",           SC_MARKNUM_HISTORY_SAVED},
        {@"Change History revert origin",   SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN},
        {@"Change History revert modified", SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED},
    };
    for (size_t i = 0; i < sizeof(history)/sizeof(history[0]); ++i) {
        NppStyle *hs = styles.globalStyles[history[i].name];
        [sci message:SCI_MARKERDEFINE wParam:(uptr_t)history[i].marker lParam:SC_MARK_LEFTRECT];
        if (hs.background) {
            [sci message:SCI_MARKERSETBACK wParam:(uptr_t)history[i].marker lParam:SciColor(hs.background)];
            [sci message:SCI_MARKERSETFORE wParam:(uptr_t)history[i].marker lParam:SciColor(hs.background)];
        }
    }
}

#pragma mark - Encoding + EOL

- (void)setEncoding:(NSStringEncoding)enc withBOM:(BOOL)bom {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    doc.encoding = enc;
    doc.hasBOM = bom;
    // Changing the encoding changes the bytes on disk, so the document is dirty.
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    doc.modified = YES;
    [self refreshChrome];
}

- (void)convertEOLTo:(int)eolMode {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    [self.sciView message:SCI_SETEOLMODE wParam:(uptr_t)eolMode lParam:0];
    [self.sciView message:SCI_CONVERTEOLS wParam:(uptr_t)eolMode lParam:0];
    doc.eolMode = eolMode;
    [self refreshChrome];
}

- (NSString *)encodingDisplayName {
    NppDocument *doc = self.currentDocument;
    // These strings match the Encoding menu labels used by Notepad++.
    switch (doc.encoding) {
        case NSUTF16LittleEndianStringEncoding: return @"UTF-16 LE BOM";
        case NSUTF16BigEndianStringEncoding:    return @"UTF-16 BE BOM";
        case NSISOLatin1StringEncoding:         return @"ANSI";
        default: return doc.hasBOM ? @"UTF-8-BOM" : @"UTF-8";
    }
}

#pragma mark - Editing commands

/// Reads `len` bytes at `pos` as a string, for prefix tests.
- (NSString *)textAt:(long)pos length:(long)len {
    if (len <= 0) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:(NSUInteger)len];
    long docLen = [self.sciView message:SCI_GETLENGTH];
    for (long i = 0; i < len && pos + i < docLen; ++i) {
        [out appendFormat:@"%c", (char)[self.sciView message:SCI_GETCHARAT wParam:(uptr_t)(pos + i)]];
    }
    return out;
}

- (void)toggleLineComment {
    NppDocument *doc = self.currentDocument;
    NSString *token = doc.language.commentLine;
    if (!token.length) { NSBeep(); return; }

    ScintillaView *sci = self.sciView;
    long selStart = [sci message:SCI_GETSELECTIONSTART];
    long selEnd   = [sci message:SCI_GETSELECTIONEND];
    long firstLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    long lastLine  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    if (lastLine > firstLine && selEnd == [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lastLine]) {
        lastLine--;   // a trailing selection edge at column 0 does not include that line
    }

    // Comment unless every non-blank line is already commented -- Notepad++'s rule.
    BOOL allCommented = YES;
    for (long ln = firstLine; ln <= lastLine; ++ln) {
        long indent = [sci message:SCI_GETLINEINDENTPOSITION wParam:(uptr_t)ln];
        long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        if (indent >= end) continue;                       // blank line: ignore
        if (![[self textAt:indent length:(long)token.length] isEqualToString:token]) {
            allCommented = NO; break;
        }
    }

    [sci message:SCI_BEGINUNDOACTION];
    for (long ln = lastLine; ln >= firstLine; --ln) {      // bottom-up keeps positions valid
        long indent = [sci message:SCI_GETLINEINDENTPOSITION wParam:(uptr_t)ln];
        long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        if (indent >= end) continue;
        if (allCommented) {
            long extra = [[self textAt:indent + (long)token.length length:1] isEqualToString:@" "] ? 1 : 0;
            [sci message:SCI_DELETERANGE wParam:(uptr_t)indent lParam:(long)token.length + extra];
        } else {
            [sci setStringProperty:SCI_INSERTTEXT parameter:indent
                             value:[token stringByAppendingString:@" "]];
        }
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
}

- (void)toggleBlockComment {
    NppDocument *doc = self.currentDocument;
    NSString *open = doc.language.commentStart, *close = doc.language.commentEnd;
    if (!open.length || !close.length) { NSBeep(); return; }

    ScintillaView *sci = self.sciView;
    long selStart = [sci message:SCI_GETSELECTIONSTART];
    long selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selEnd == selStart) { NSBeep(); return; }

    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:selEnd value:close];
    [sci setStringProperty:SCI_INSERTTEXT parameter:selStart value:open];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_SETSEL wParam:(uptr_t)selStart
             lParam:selEnd + (long)open.length + (long)close.length];
    [self refreshChrome];
}

- (void)toggleBookmark {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long markers = [sci message:SCI_MARKERGET wParam:(uptr_t)line];
    if (markers & (1 << NPPMAC_BOOKMARK_MARKER)) {
        [sci message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
    } else {
        [sci message:SCI_MARKERADD wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
    }
}

- (void)nextBookmark {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long found = [sci message:SCI_MARKERNEXT wParam:(uptr_t)(line + 1) lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    if (found < 0) found = [sci message:SCI_MARKERNEXT wParam:0 lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    if (found < 0) { NSBeep(); return; }
    [sci message:SCI_GOTOLINE wParam:(uptr_t)found lParam:0];
    [self refreshChrome];
}

- (void)previousBookmark {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long found = [sci message:SCI_MARKERPREVIOUS wParam:(uptr_t)(line - 1) lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    if (found < 0) {
        found = [sci message:SCI_MARKERPREVIOUS
                       wParam:(uptr_t)[sci message:SCI_GETLINECOUNT] lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    }
    if (found < 0) { NSBeep(); return; }
    [sci message:SCI_GOTOLINE wParam:(uptr_t)found lParam:0];
    [self refreshChrome];
}

- (void)clearBookmarks {
    [self.sciView message:SCI_MARKERDELETEALL wParam:NPPMAC_BOOKMARK_MARKER lParam:0];
}

- (void)foldAll:(BOOL)fold {
    [self.sciView message:SCI_FOLDALL wParam:(uptr_t)(fold ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND) lParam:0];
}

- (void)toggleFoldAtCursor {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    [sci message:SCI_TOGGLEFOLD wParam:(uptr_t)line lParam:0];
}

- (void)foldCurrent:(BOOL)fold {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    // Act on the enclosing fold point, which is what "current level" means.
    long parent = [sci message:SCI_GETFOLDPARENT wParam:(uptr_t)line];
    if (parent < 0) parent = line;
    [sci message:SCI_FOLDLINE wParam:(uptr_t)parent
             lParam:(fold ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND)];
}

- (void)showAutoCompletion {
    ScintillaView *sci = self.sciView;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long start = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
    if (pos <= start) { NSBeep(); return; }
    NSString *prefix = [self textAt:start length:pos - start];

    // Candidates: distinct words already in the document, as Notepad++ does.
    NSMutableSet *words = [NSMutableSet set];
    NSString *all = [sci string] ?: @"";
    NSCharacterSet *sep = [[NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] invertedSet];
    for (NSString *w in [all componentsSeparatedByCharactersInSet:sep]) {
        if (w.length > prefix.length && [w hasPrefix:prefix]) [words addObject:w];
    }
    if (!words.count) { NSBeep(); return; }

    NSArray *sorted = [words.allObjects sortedArrayUsingSelector:@selector(compare:)];
    [sci message:SCI_AUTOCSETSEPARATOR wParam:(uptr_t)' ' lParam:0];
    [sci setStringProperty:SCI_AUTOCSHOW parameter:pos - start
                     value:[sorted componentsJoinedByString:@" "]];
}

#pragma mark - Chrome refresh

- (void)refreshChrome {
    self.tabBar.segmentCount = (NSInteger)self.docs.count;
    for (NSUInteger i = 0; i < self.docs.count; ++i) {
        NppDocument *d = self.docs[i];
        NSString *label = d.modified ? [d.displayName stringByAppendingString:@" •"] : d.displayName;
        if (d.pinned) label = [@"📌 " stringByAppendingString:label];
        if (d.tabColour > 0 && d.tabColour <= 5) {
            NSArray *dots = @[@"🔴", @"🟠", @"🟡", @"🟢", @"🔵"];
            label = [NSString stringWithFormat:@"%@ %@", dots[d.tabColour - 1], label];
        }
        [self.tabBar setLabel:label forSegment:(NSInteger)i];
        [self.tabBar setWidth:0 forSegment:(NSInteger)i];
    }
    if (self.currentIndex >= 0 && self.currentIndex < (NSInteger)self.docs.count) {
        self.tabBar.selectedSegment = self.currentIndex;
    }

    NppDocument *doc = self.currentDocument;
    ScintillaView *sci = self.sciView;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos] + 1;
    long col = [sci message:SCI_GETCOLUMN wParam:(uptr_t)pos] + 1;
    long len = [sci message:SCI_GETLENGTH];
    long lines = [sci message:SCI_GETLINECOUNT];

    NSString *eol = doc.eolMode == SC_EOL_CRLF ? @"CRLF" : doc.eolMode == SC_EOL_CR ? @"CR" : @"LF";
    self.statusField.stringValue = [NSString stringWithFormat:
        @"%@    Ln %ld, Col %ld    %ld lines, %ld bytes    %@    %@    %@",
        doc.path ?: @"(unsaved)", line, col, lines, len,
        doc.language.name ?: @"normal", [self encodingDisplayName], eol];

    self.window.title = doc.path ? [NSString stringWithFormat:@"%@ — %@", doc.displayName,
                                    doc.path.stringByDeletingLastPathComponent]
                                 : doc.displayName;
    self.window.representedFilename = doc.path ?: @"";
    self.window.documentEdited = doc.modified;
}

- (void)setChromeVisible:(BOOL)visible {
    self.tabBar.hidden = !visible;
    self.statusField.hidden = !visible;
    NSRect upper = self.split.frame;
    CGFloat tabH = visible ? 28 : 0, statusH = visible ? 22 : 0;
    self.split.frame = NSMakeRect(0, statusH, NSWidth(self.container.frame),
                                  NSHeight(self.container.frame) - statusH);
    self.sciView.frame = NSMakeRect(0, 0, NSWidth(self.editorArea.frame),
                                    NSHeight(self.editorArea.frame) - tabH);
    (void)upper;
    [self.container setNeedsDisplay:YES];
}

- (BOOL)chromeVisible { return !self.tabBar.hidden; }

#pragma mark - Second editor pane

- (ScintillaView *)secondarySci { return self.secondaryView; }

- (BOOL)secondaryViewVisible { return self.secondaryView.superview != nil; }

- (void)setSecondaryViewVisible:(BOOL)visible {
    if (visible == [self secondaryViewVisible]) return;
    if (visible) {
        [self.editorSplit addSubview:self.secondaryView];
        [self.editorSplit adjustSubviews];
        [self.editorSplit setPosition:NSHeight(self.editorSplit.frame) / 2 ofDividerAtIndex:0];
    } else {
        [self.secondaryView removeFromSuperview];
        [self.editorSplit adjustSubviews];
    }
}

- (void)focusOtherView {
    if (![self secondaryViewVisible]) { NSBeep(); return; }
    NSResponder *first = self.window.firstResponder;
    BOOL primaryFocused = !(first == self.secondaryView ||
                            [first isKindOfClass:[NSView class]] &&
                            [(NSView *)first isDescendantOf:self.secondaryView]);
    [self.window makeFirstResponder:primaryFocused ? self.secondaryView : self.sciView];
}

- (BOOL)otherViewHasFocus {
    NSResponder *first = self.window.firstResponder;
    if (![first isKindOfClass:[NSView class]]) return NO;
    return [(NSView *)first isDescendantOf:self.secondaryView];
}

- (BOOL)cloneCurrentToOtherView {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    [self setSecondaryViewVisible:YES];
    // Sharing the document pointer is what makes it a clone: both panes edit
    // the same buffer, exactly as Notepad++'s Clone to Other View does.
    [self.secondaryView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
    return YES;
}

- (BOOL)moveCurrentToOtherView {
    if (self.documents.count < 2) {
        // Moving the only tab away would leave the primary pane empty.
        if (![self cloneCurrentToOtherView]) return NO;
        return YES;
    }
    NppDocument *doc = self.currentDocument;
    if (![self cloneCurrentToOtherView]) return NO;
    NSInteger idx = [self.documents indexOfObject:doc];
    if (idx != NSNotFound) [self closeDocumentAtIndex:idx discardChanges:YES];
    return YES;
}

- (BOOL)syncVerticalScroll { return self.syncV; }
- (void)setSyncVerticalScroll:(BOOL)on { self.syncV = on; if (on) [self mirrorScrollToSecondary]; }
- (BOOL)syncHorizontalScroll { return self.syncH; }
- (void)setSyncHorizontalScroll:(BOOL)on { self.syncH = on; if (on) [self mirrorScrollToSecondary]; }
- (BOOL)syncZoom { return self.syncZ; }
- (void)setSyncZoom:(BOOL)on { self.syncZ = on; if (on) [self mirrorScrollToSecondary]; }

- (void)mirrorScrollToSecondary {
    if (![self secondaryViewVisible]) return;
    if (self.syncV) {
        [self.secondaryView message:SCI_SETFIRSTVISIBLELINE
                             wParam:(uptr_t)[self.sciView message:SCI_GETFIRSTVISIBLELINE] lParam:0];
    }
    if (self.syncH) {
        [self.secondaryView message:SCI_SETXOFFSET
                             wParam:(uptr_t)[self.sciView message:SCI_GETXOFFSET] lParam:0];
    }
    if (self.syncZ) {
        [self.secondaryView message:SCI_SETZOOM
                             wParam:(uptr_t)[self.sciView message:SCI_GETZOOM] lParam:0];
    }
}

- (void)mirrorScrollFromSecondary {
    if (![self secondaryViewVisible]) return;
    if (self.syncV) {
        [self.sciView message:SCI_SETFIRSTVISIBLELINE
                       wParam:(uptr_t)[self.secondaryView message:SCI_GETFIRSTVISIBLELINE] lParam:0];
    }
    if (self.syncH) {
        [self.sciView message:SCI_SETXOFFSET
                       wParam:(uptr_t)[self.secondaryView message:SCI_GETXOFFSET] lParam:0];
    }
    if (self.syncZ) {
        [self.sciView message:SCI_SETZOOM
                       wParam:(uptr_t)[self.secondaryView message:SCI_GETZOOM] lParam:0];
    }
}

#pragma mark - Document Map

- (BOOL)documentMapVisible { return self.docMapView.superview != nil; }

- (void)setDocumentMapVisible:(BOOL)visible {
    if (visible == [self documentMapVisible]) return;
    if (!visible) {
        [self.docMapView removeFromSuperview];
        [self.split adjustSubviews];
        return;
    }
    if (!self.docMapView) {
        self.docMapView = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 120, 400)];
        // A shrunken, read-only, chrome-less mirror of the buffer.
        [self.docMapView message:SCI_SETZOOM wParam:(uptr_t)-8 lParam:0];
        [self.docMapView message:SCI_SETREADONLY wParam:1 lParam:0];
        [self.docMapView message:SCI_SETMARGINWIDTHN wParam:0 lParam:0];
        [self.docMapView message:SCI_SETMARGINWIDTHN wParam:1 lParam:0];
        [self.docMapView message:SCI_SETMARGINWIDTHN wParam:2 lParam:0];
        [self.docMapView message:SCI_SETHSCROLLBAR wParam:0 lParam:0];
        [self.docMapView message:SCI_SETVSCROLLBAR wParam:0 lParam:0];
    }
    [self.docMapView message:SCI_SETDOCPOINTER wParam:0
                      lParam:(sptr_t)self.currentDocument.docPointer];
    [self.split addSubview:self.docMapView];
    [self.split adjustSubviews];
    [self.split setPosition:NSWidth(self.split.frame) - 120
           ofDividerAtIndex:self.split.subviews.count - 2];
}

#pragma mark - Project panels

- (NSInteger)activeProjectPanel { return self.activeProject; }

- (void)setProjectPanel:(NSInteger)index root:(NSString *)path {
    if (index < 1 || index > 3) return;
    [self.projects[(NSUInteger)(index - 1)] setRootPath:path];
}

- (NSString *)projectPanelRoot:(NSInteger)index {
    if (index < 1 || index > 3) return nil;
    return self.projects[(NSUInteger)(index - 1)].rootPath;
}

- (NSArray<NSString *> *)projectPanelNames:(NSInteger)index {
    if (index < 1 || index > 3) return @[];
    return [self.projects[(NSUInteger)(index - 1)] topLevelNames];
}

- (void)showProjectPanel:(NSInteger)index {
    if (index < 1 || index > 3) return;
    WorkspacePanel *panel = self.projects[(NSUInteger)(index - 1)];

    if (self.activeProject == index) {            // same panel again hides it
        [panel.view removeFromSuperview];
        self.activeProject = 0;
        [self.split adjustSubviews];
        return;
    }
    for (WorkspacePanel *p in self.projects) [p.view removeFromSuperview];
    if ([self workspaceVisible]) [self openFolderAsWorkspace:nil];

    [self.split addSubview:panel.view positioned:NSWindowBelow relativeTo:self.editorArea];
    [self.split setPosition:220 ofDividerAtIndex:0];
    self.activeProject = index;
    [self.split adjustSubviews];
}

/// Notepad++ opens a second process; `open -n` is the macOS equivalent.
- (BOOL)openCurrentInNewInstanceMoving:(BOOL)closeHere {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) { NSBeep(); return NO; }
    NSURL *bundle = [[NSBundle mainBundle] bundleURL];
    NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
    config.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:doc.path]]
                       withApplicationAtURL:bundle
                              configuration:config
                          completionHandler:nil];
    if (closeHere) [self closeDocumentAtIndex:self.currentIndex discardChanges:YES];
    return YES;
}

#pragma mark - ScintillaNotificationProtocol

- (void)notification:(SCNotification *)n {
    switch (n->nmhdr.code) {
        case SCN_SAVEPOINTREACHED: self.currentDocument.modified = NO; [self refreshChrome]; break;
        case SCN_SAVEPOINTLEFT:    self.currentDocument.modified = YES; [self refreshChrome]; break;
        case SCN_UPDATEUI:
            [self refreshChrome];
            [self mirrorScrollToSecondary];
            break;
        default: break;
    }
}

@end

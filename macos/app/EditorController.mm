#include <string>
#import "EditorController.h"
#import "ProjectPanel.h"
#import "CharsetDetection.h"
#import "UserLanguages.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "AdvancedEditCommands.h"
#import "ScintillaView.h"
#import "WorkspacePanel.h"
#import "EncodingCommands.h"
#import "ToolsCommands.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"
#import "TypingCommands.h"
#import <objc/runtime.h>
#import "TabBarView.h"
#import "SettingsCommands.h"
#import "SearchCommands.h"
#import "LanguageDetection.h"
#include "ILexer.h"
#include "Lexilla.h"

/// Marker 1: bookmarks. Fold markers occupy 25-31, so this cannot collide.
#define NPPMAC_BOOKMARK_MARKER 1

NSString *const NppEditorDocumentsDidChangeNotification = @"NppEditorDocumentsDidChange";

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

@interface EditorController () <ScintillaNotificationProtocol, WorkspacePanelDelegate, NppTabBarDelegate>
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
/// The document the other pane shows, so that closing it can move the pane off it.
@property (nonatomic, strong) NppDocument *secondaryDocument;
@property (nonatomic, strong) NSMutableArray<NppProjectPanel *> *projects;
@property (nonatomic) NSInteger activeProject;
@property (nonatomic, strong) ScintillaView *sciView;
@property (nonatomic, strong) NSView *container;
@property (nonatomic, strong) NppTabBarView *tabBar;
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
    // UTF-16 without a mark gives itself away before anything is decoded.
    NSStringEncoding wide = [NppCharsetDetection utf16EncodingWithoutMarkForData:data];
    if (wide) {
        NSString *s = [[NSString alloc] initWithData:data encoding:wide];
        if (s) { *outEnc = wide; return s; }
    }
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s) { *outEnc = NSUTF8StringEncoding; return s; }
    // Not UTF-8: asked of uchardet, as Windows asks, before falling back to
    // Latin-1, which reads anything and understands nothing.
    if ([NppPreferences shared].autoDetectCharacterEncoding) {
        NSStringEncoding guessed = [NppCharsetDetection encodingGuessedForData:data];
        if (guessed) {
            NSString *s = [[NSString alloc] initWithData:data encoding:guessed];
            if (s) { *outEnc = guessed; return s; }
        }
    }
    *outEnc = NSISOLatin1StringEncoding;
    return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

/// First line ending wins, matching how Notepad++ reports a file's EOL.
static int DetectEOL(NSString *text) {
    NSRange cr = [text rangeOfString:@"\r"];
    NSRange lf = [text rangeOfString:@"\n"];
    if (cr.location == NSNotFound) return SC_EOL_LF;   // no CR at all, incl. no line ending
    if (lf.location == NSNotFound) return SC_EOL_CR;
    if (lf.location < cr.location) return SC_EOL_LF;   // the first ending is a bare LF
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

    _tabBar = [[NppTabBarView alloc] initWithFrame:
               NSMakeRect(0, NSHeight(upper) - tabH, NSWidth(upper), tabH)];
    _tabBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _tabBar.tabDelegate = self;
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
        NppProjectPanel *p = [[NppProjectPanel alloc] initWithNumber:i + 1
                                                               frame:NSMakeRect(0, 0, 240, NSHeight(upper))];
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
    // From the preferences, not literals: these live in the Scintilla
    // document, so whatever was applied to the last one is gone on a switch.
    NppPreferences *prefs = [NppPreferences shared];
    [sci message:SCI_SETTABWIDTH wParam:(uptr_t)MAX(1, prefs.tabWidth) lParam:0];
    [sci message:SCI_SETINDENT wParam:(uptr_t)MAX(1, prefs.tabWidth) lParam:0];
    [sci message:SCI_SETUSETABS wParam:(uptr_t)(prefs.useSpaces ? 0 : 1) lParam:0];
    [sci message:SCI_SETINDENTATIONGUIDES
           wParam:(uptr_t)(prefs.showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE) lParam:0];
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

    [self applyEditorPreferences];
}

/// The editor settings Notepad++ keeps outside a document: the vertical edge,
/// the caret, and how far the view and the caret may go past the text.
- (void)applyEditorPreferences {
    ScintillaView *sci = self.sciView;
    NppPreferences *prefs = [NppPreferences shared];

    // A vertical edge can be a line or a change of background, and Notepad++
    // takes a list of columns rather than one.
    NSMutableArray<NSNumber *> *columns = [NSMutableArray array];
    for (NSString *piece in [(prefs.edgeColumns ?: @"") componentsSeparatedByCharactersInSet:
                             [NSCharacterSet characterSetWithCharactersInString:@" ,;\t"]]) {
        NSInteger column = piece.integerValue;
        if (column > 0) [columns addObject:@(column)];
    }

    [sci message:SCI_MULTIEDGECLEARALL wParam:0 lParam:0];
    if (prefs.edgeMode == 0 || !columns.count) {
        [sci message:SCI_SETEDGEMODE wParam:EDGE_NONE lParam:0];
    } else if (prefs.edgeMode == 2) {
        // Background mode marks everything past the column and takes one column.
        [sci message:SCI_SETEDGEMODE wParam:EDGE_BACKGROUND lParam:0];
        [sci message:SCI_SETEDGECOLUMN wParam:(uptr_t)columns.firstObject.integerValue lParam:0];
    } else if (columns.count == 1) {
        [sci message:SCI_SETEDGEMODE wParam:EDGE_LINE lParam:0];
        [sci message:SCI_SETEDGECOLUMN wParam:(uptr_t)columns.firstObject.integerValue lParam:0];
    } else {
        [sci message:SCI_SETEDGEMODE wParam:EDGE_MULTILINE lParam:0];
        long colour = [sci message:SCI_GETEDGECOLOUR];
        for (NSNumber *column in columns) {
            [sci message:SCI_MULTIEDGEADDLINE wParam:(uptr_t)column.integerValue lParam:colour];
        }
    }

    [sci message:SCI_SETCARETWIDTH wParam:(uptr_t)MAX((NSInteger)0, prefs.caretWidth) lParam:0];
    [sci message:SCI_SETCARETPERIOD wParam:(uptr_t)MAX((NSInteger)0, prefs.caretBlinkRate) lParam:0];

    // SCI_SETENDATLASTLINE is the other way round: setting it stops the view
    // scrolling past the end.
    [sci message:SCI_SETENDATLASTLINE wParam:prefs.scrollBeyondLastLine ? 0 : 1 lParam:0];
    [sci message:SCI_SETVIRTUALSPACEOPTIONS
           wParam:prefs.virtualSpace ? (SCVS_RECTANGULARSELECTION | SCVS_USERACCESSIBLE)
                                     : SCVS_RECTANGULARSELECTION
           lParam:0];

    // The current line can be left alone, given a background, or framed.
    switch (prefs.currentLineHighlightMode) {
        case 0:
            [sci message:SCI_SETCARETLINEVISIBLE wParam:0 lParam:0];
            break;
        case 2:
            [sci message:SCI_SETCARETLINEVISIBLE wParam:1 lParam:0];
            [sci message:SCI_SETCARETLINEFRAME
                   wParam:(uptr_t)MIN((NSInteger)6, MAX((NSInteger)1, prefs.currentLineFrameWidth))
                   lParam:0];
            break;
        default:
            [sci message:SCI_SETCARETLINEVISIBLE wParam:1 lParam:0];
            [sci message:SCI_SETCARETLINEFRAME wParam:0 lParam:0];
            break;
    }

    // Margins the user can turn off. The line number margin has its own
    // setting elsewhere; these two are the bookmark and fold margins.
    [sci message:SCI_SETMARGINWIDTHN wParam:1 lParam:prefs.bookmarkMarginShow ? 14 : 0];
    [sci message:SCI_SETMARGINWIDTHN wParam:2 lParam:prefs.foldMarginShow ? 16 : 0];

    // How a wrapped line continues: plain, aligned with the line above, or a
    // level further in.
    long wrapIndent = prefs.lineWrapMethod == 2 ? SC_WRAPINDENT_INDENT
                    : prefs.lineWrapMethod == 0 ? SC_WRAPINDENT_FIXED
                                                : SC_WRAPINDENT_SAME;
    [sci message:SCI_SETWRAPINDENTMODE wParam:(uptr_t)wrapIndent lParam:0];

    [sci message:SCI_SETMARGINLEFT wParam:0
           lParam:(sptr_t)MIN((NSInteger)9, MAX((NSInteger)0, prefs.paddingLeft))];
    [sci message:SCI_SETMARGINRIGHT wParam:0
           lParam:(sptr_t)MIN((NSInteger)9, MAX((NSInteger)0, prefs.paddingRight))];

    [sci message:SCI_SETMOUSESELECTIONRECTANGULARSWITCH wParam:1 lParam:0];
    [sci message:SCI_SETDRAGDROPENABLED wParam:prefs.selectedTextDragDrop ? 1 : 0 lParam:0];
}

#pragma mark - Typing mode

- (BOOL)overtype {
    return [self.sciView message:SCI_GETOVERTYPE] != 0;
}

- (void)setOvertype:(BOOL)on {
    [self.sciView message:SCI_SETOVERTYPE wParam:on ? 1 : 0 lParam:0];
    [self refreshChrome];
}

- (void)toggleOvertype {
    [self setOvertype:![self overtype]];
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
    [self applyNewDocumentDefaults];
}

#pragma mark - The text, by length

- (NSString *)documentText {
    long length = [self.sciView message:SCI_GETLENGTH wParam:0 lParam:0];
    if (length <= 0) return @"";
    std::string buffer((size_t)length + 1, '\0');
    [self.sciView message:SCI_GETTEXT wParam:(uptr_t)(length + 1) lParam:(sptr_t)&buffer[0]];
    NSString *text = [[NSString alloc] initWithBytes:buffer.data() length:(NSUInteger)length
                                            encoding:NSUTF8StringEncoding];
    return text ?: ([self.sciView string] ?: @"");
}

- (void)setDocumentText:(NSString *)text {
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    // A read-only document takes no text; the flag is lifted for the
    // replacement (a reload, a reread in another code page) and put back.
    BOOL readOnly = [self.sciView message:SCI_GETREADONLY wParam:0 lParam:0] != 0;
    if (readOnly) [self.sciView message:SCI_SETREADONLY wParam:0 lParam:0];
    [self.sciView message:SCI_CLEARALL wParam:0 lParam:0];
    [self.sciView message:SCI_ADDTEXT wParam:(uptr_t)utf8.length lParam:(sptr_t)utf8.bytes];
    if (readOnly) [self.sciView message:SCI_SETREADONLY wParam:1 lParam:0];
}

- (BOOL)openFileAtPath:(NSString *)path error:(NSError **)error {
    // Already open? Just focus it.
    for (NSUInteger i = 0; i < self.docs.count; ++i) {
        if ([self.docs[i].path isEqualToString:path]) { [self selectDocumentAtIndex:(NSInteger)i]; return YES; }
    }

    // Decided on the size on disk, before anything is read: a file too big to
    // hold is refused, and a large one is opened without styling from the
    // start rather than styled and then unstyled.
    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL]
                               fileSize];
    if (size >= 2ULL * 1024 * 1024 * 1024) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadTooLargeError
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"%@ is too big to open (2 GB or more).",
                                                 path.lastPathComponent]}];
        return NO;
    }
    NppPreferences *prefs = [NppPreferences shared];
    BOOL large = prefs.largeFileRestrictionEnabled &&
                 size > (unsigned long long)prefs.largeFileThresholdMB * 1024 * 1024;

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
    doc.docPointer = (void *)[self.sciView message:SCI_CREATEDOCUMENT wParam:0
        lParam:large ? (SC_DOCUMENTOPTION_STYLES_NONE | SC_DOCUMENTOPTION_TEXT_LARGE)
                     : SC_DOCUMENTOPTION_DEFAULT];
    doc.path = path;
    doc.displayName = path.lastPathComponent;
    doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:path];
    doc.encoding = used;
    doc.hasBOM = bom;
    doc.codepage = 0;
    doc.eolMode = DetectEOL(text);
    doc.fileModificationDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL]
                                fileModificationDate];

    [self.docs addObject:doc];
    [self selectDocumentAtIndex:(NSInteger)self.docs.count - 1];

    [self setDocumentText:text];
    [self.sciView message:SCI_SETEOLMODE wParam:(uptr_t)doc.eolMode lParam:0];
    [self applyPerformanceRestrictions];
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    [self.sciView message:SCI_GOTOPOS wParam:0 lParam:0];
    [self.sciView message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    doc.modified = NO;

    [self applyLanguage];
    // A file that cannot be written is not edited until the user says so.
    if (![[NSFileManager defaultManager] isWritableFileAtPath:path]) {
        [self.sciView message:SCI_SETREADONLY wParam:1 lParam:0];
    }
    [self refreshChrome];
    // The recent list holds what was closed, not what is open, as on Windows.
    [self forgetRecentFile:path];
    [self rememberOpenDirectory:path];

    // A name with no extension says nothing, so the contents are asked instead.
    [self detectLanguageOfCurrentDocumentOffering:self.languageChoiceHandler];
    return YES;
}

- (void)selectDocumentAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.docs.count) return;
    if (self.currentIndex >= 0 && self.currentIndex != index &&
        self.currentIndex < (NSInteger)self.docs.count) {
        [self rememberPreviousTab:self.docs[self.currentIndex]];   // backs Window > Recent Window
    }
    // Where the caret and the view are belongs to the document, as on
    // Windows: kept when it leaves the front, put back when it returns.
    if (self.currentIndex >= 0 && self.currentIndex != index &&
        self.currentIndex < (NSInteger)self.docs.count) {
        NppDocument *leaving = self.docs[self.currentIndex];
        leaving.caretPosition = [self.sciView message:SCI_GETCURRENTPOS];
        leaving.anchorPosition = [self.sciView message:SCI_GETANCHOR];
        leaving.firstVisibleLine = [self.sciView message:SCI_GETFIRSTVISIBLELINE];
        NSMutableArray *marks = [NSMutableArray array];
        long line = -1;
        while ((line = [self.sciView message:SCI_MARKERNEXT wParam:(uptr_t)(line + 1) lParam:(1 << 1)]) >= 0) {
            [marks addObject:@(line)];
        }
        leaving.bookmarkedLines = marks;
    }
    BOOL switching = self.currentIndex != index;
    self.currentIndex = index;
    NppDocument *doc = self.docs[index];
    [self.sciView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
    if (switching) {
        [self.sciView message:SCI_SETSEL wParam:(uptr_t)doc.anchorPosition lParam:doc.caretPosition];
        [self.sciView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)doc.firstVisibleLine lParam:0];
    }
    [self forgetAutoCloser];
    // The map mirrors whatever is in front, not whatever was when it opened.
    if (self.docMapView.superview) {
        [self.docMapView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
    }
    [self applyDocumentSettings];
    [self applyLanguage];
    [self refreshChrome];
    [self.window makeFirstResponder:self.sciView];
}

#pragma mark - NppTabBarDelegate

- (void)tabBar:(NppTabBarView *)bar didSelectIndex:(NSInteger)index {
    [self selectDocumentAtIndex:index];
}

- (void)tabBar:(NppTabBarView *)bar didRequestCloseIndex:(NSInteger)index {
    [self selectDocumentAtIndex:index];
    [self closeCurrentDocument];
}

- (void)tabBar:(NppTabBarView *)bar didMoveIndex:(NSInteger)from toIndex:(NSInteger)to {
    NSMutableArray *docs = (NSMutableArray *)self.documents;
    if (from < 0 || to < 0 || from >= (NSInteger)docs.count || to >= (NSInteger)docs.count) return;
    NppDocument *moving = docs[(NSUInteger)from];
    NppDocument *inFront = self.currentDocument;
    [docs removeObjectAtIndex:(NSUInteger)from];
    [docs insertObject:moving atIndex:(NSUInteger)to];
    // The indexes moved, the documents did not: the one in front keeps its
    // number updated, so that selecting the moved tab is a real switch from
    // it (or none at all when the moved tab is the one in front).
    self.currentIndex = inFront ? (NSInteger)[docs indexOfObject:inFront] : -1;
    [self selectDocumentAtIndex:to];
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
    for (NppDocument *other in self.docs) {
        if (other != doc && [other.path isEqualToString:path]) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"That file is open in another tab.";
            alert.informativeText = @"Close it first, or choose another name.";
            [alert runModal];
            return NO;
        }
    }
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
    // Preserve what is on disk before overwriting it, if Backup asks for that.
    [self writeBackupForPath:path];
    NSString *text = [self documentText];
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
    self.currentDocument.encodingChanged = NO;
    self.currentDocument.fileModificationDate =
        [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileModificationDate];
    [self dropBackupOfDocument:self.currentDocument];
    [self refreshChrome];
    return YES;
}

- (void)dropBackupOfDocument:(NppDocument *)doc {
    if (!doc.backupPath) return;
    [[NSFileManager defaultManager] removeItemAtPath:doc.backupPath error:NULL];
    doc.backupPath = nil;
}

#pragma mark - Files changed on disk

static BOOL gCheckingFilesOnDisk;

- (void)checkFilesOnDisk {
    NppPreferences *p = [NppPreferences shared];
    if (!p.fileAutoDetection) return;
    // Answering the question means leaving and returning to the
    // application, which asks again: not while a check is under way.
    if (gCheckingFilesOnDisk) return;
    gCheckingFilesOnDisk = YES;
    NSFileManager *fm = [NSFileManager defaultManager];
    NppDocument *was = self.currentDocument;
    NppDocument *previous = [self previousTab];

    for (NppDocument *doc in [self.docs copy]) {
        if (!doc.path || ![self.docs containsObject:doc]) continue;
        NSDate *onDisk = [[fm attributesOfItemAtPath:doc.path error:NULL] fileModificationDate];

        if (!onDisk) {
            if (!doc.fileModificationDate) continue;      // already known to be gone, and kept
            // Gone. Kept as a modified document, or closed, as the user says.
            [self selectDocumentAtIndex:(NSInteger)[self.docs indexOfObject:doc]];
            NSInteger answer = self.scriptedCloseAnswer;
            if (!answer && getenv("NPPMAC_TEST")) answer = NSAlertFirstButtonReturn;
            if (!answer) {
                NSAlert *ask = [[NSAlert alloc] init];
                ask.messageText = [NSString stringWithFormat:@"\"%@\" no longer exists.", doc.displayName];
                ask.informativeText = @"Keep it in the editor?";
                [ask addButtonWithTitle:@"Keep"];
                [ask addButtonWithTitle:@"Close"];
                answer = [ask runModal];
            }
            if (answer == NSAlertFirstButtonReturn) {
                doc.modified = YES;
                doc.fileModificationDate = nil;
                [self refreshChrome];
            } else {
                NSString *gone = doc.path;
                [self closeDocumentAtIndex:(NSInteger)[self.docs indexOfObject:doc] discardChanges:YES];
                [self forgetRecentFile:gone];             // there is nothing to reopen
            }
            continue;
        }
        if (!doc.fileModificationDate || [onDisk compare:doc.fileModificationDate] == NSOrderedSame) continue;

        // Changed by another program. Reloaded, unless the user has edits and
        // wants to keep them; asked first unless the setting says not to.
        [self selectDocumentAtIndex:(NSInteger)[self.docs indexOfObject:doc]];
        NSInteger answer = self.scriptedCloseAnswer;
        if (!answer && p.fileAutoDetectionSilent && !doc.modified) answer = NSAlertFirstButtonReturn;
        if (!answer && getenv("NPPMAC_TEST")) answer = NSAlertFirstButtonReturn;
        if (!answer) {
            NSAlert *ask = [[NSAlert alloc] init];
            ask.messageText = [NSString stringWithFormat:@"\"%@\" has been changed by another program.",
                               doc.displayName];
            ask.informativeText = doc.modified
                ? @"Reload it and lose the changes made here?" : @"Reload it?";
            [ask addButtonWithTitle:@"Reload"];
            [ask addButtonWithTitle:@"Keep"];
            answer = [ask runModal];
        }
        if (answer == NSAlertFirstButtonReturn) {
            [self reselectDocument:doc];                  // the alert may have moved the front
            if ([self reloadCurrentDocument:NULL] && p.fileAutoDetectionScrollToEnd) {
                [self.sciView message:SCI_DOCUMENTEND wParam:0 lParam:0];
            }
        }
        // Either way this version is the one known, so it is not asked about again.
        doc.fileModificationDate = onDisk;
    }
    [self reselectDocument:was];
    [self rememberPreviousTab:previous];
    gCheckingFilesOnDisk = NO;
}

- (BOOL)confirmClosingDocuments:(NSArray<NppDocument *> *)docs {
    NppDocument *was = self.currentDocument;
    // Selecting each document to ask about it must not become the tab that
    // Recent Window steps back to.
    NppDocument *previous = [self previousTab];
    for (NppDocument *doc in [docs copy]) {
        if (!doc.modified || ![self.docs containsObject:doc]) continue;
        [self selectDocumentAtIndex:(NSInteger)[self.docs indexOfObject:doc]];

        NSInteger answer = self.scriptedCloseAnswer;
        // The suite cannot answer a sheet; unless a test scripted the answer,
        // it does not save, which is what every test before this relied on.
        if (!answer && getenv("NPPMAC_TEST")) answer = NSAlertSecondButtonReturn;
        if (!answer) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [NSString stringWithFormat:@"Save changes to %@?", doc.displayName];
            alert.informativeText = @"Your changes will be lost if you don't save them.";
            [alert addButtonWithTitle:@"Save"];
            [alert addButtonWithTitle:@"Don't Save"];
            [alert addButtonWithTitle:@"Cancel"];
            answer = [alert runModal];
        }
        if (answer == NSAlertThirdButtonReturn) {
            [self reselectDocument:was];
            [self rememberPreviousTab:previous];
            return NO;
        }
        if (answer == NSAlertFirstButtonReturn && ![self saveCurrentDocument]) {
            [self reselectDocument:was];
            [self rememberPreviousTab:previous];
            return NO;
        }
    }
    [self reselectDocument:was];
    [self rememberPreviousTab:previous];
    return YES;
}

- (void)closeCurrentDocument {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    if (![self confirmClosingDocuments:@[doc]]) return;
    [self closeDocumentAtIndex:self.currentIndex discardChanges:YES];
}

- (void)closeDocumentAtIndex:(NSInteger)index discardChanges:(BOOL)discard {
    if (index < 0 || index >= (NSInteger)self.docs.count) return;
    NppDocument *doc = self.docs[index];
    if (!discard && doc.modified) return;
    NppDocument *inFront = self.currentDocument;

    [self.docs removeObjectAtIndex:index];

    if (self.docs.count == 0) {
        if ([NppPreferences shared].exitOnClosingLastTab) {
            [NSApp terminate:nil];
            return;
        }
        self.currentIndex = -1;
        [self newDocument];                       // switches the view off the old doc
    } else if (inFront && inFront != doc && [self.docs containsObject:inFront]) {
        // Closing another tab leaves the one in front where it is; only its
        // number changed.
        self.currentIndex = (NSInteger)[self.docs indexOfObject:inFront];
        [self refreshChrome];
    } else {
        // The closed document was the one in front: nothing of it is worth
        // keeping, and the index no longer names it, so the neighbour is
        // entered as a fresh switch and gets its own caret back.
        self.currentIndex = -1;
        [self selectDocumentAtIndex:MIN(index, (NSInteger)self.docs.count - 1)];
    }
    if (doc.path) [self noteRecentFile:doc.path];
    [self dropBackupOfDocument:doc];
    // The other pane must not be left on a document about to go.
    if (self.secondaryDocument == doc) {
        NppDocument *front = self.currentDocument;
        if (front && [self secondaryViewVisible]) {
            [self.secondaryView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)front.docPointer];
            self.secondaryDocument = front;
        } else {
            [self.secondaryView message:SCI_SETDOCPOINTER wParam:0 lParam:0];
            self.secondaryDocument = nil;
        }
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
    // Read back the way it is being read: a code page the user chose stays.
    NSString *text = doc.codepage ? [EditorController stringFromData:data codepage:doc.codepage]
                                  : DecodeText(data, &enc, &bom);
    if (!text) return NO;

    long caret = [self.sciView message:SCI_GETCURRENTPOS];
    long firstLine = [self.sciView message:SCI_GETFIRSTVISIBLELINE];
    [self setDocumentText:text];
    if (!doc.codepage) {
        doc.encoding = enc;
        doc.hasBOM = bom;
    }
    doc.encodingChanged = NO;
    doc.eolMode = DetectEOL(text);
    [self.sciView message:SCI_SETEOLMODE wParam:(uptr_t)doc.eolMode lParam:0];
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    [self.sciView message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    [self.sciView message:SCI_GOTOPOS
                   wParam:(uptr_t)MIN(caret, [self.sciView message:SCI_GETLENGTH]) lParam:0];
    [self.sciView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)firstLine lParam:0];
    doc.fileModificationDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:doc.path error:NULL]
                                fileModificationDate];
    [self dropBackupOfDocument:doc];
    doc.modified = NO;
    [self refreshChrome];
    return YES;
}

- (BOOL)saveCopyOfCurrentTo:(NSString *)path error:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    NSString *text = [self documentText];
    NSData *data = doc.codepage
        ? [EditorController dataFromString:text codepage:doc.codepage]
        : EncodeText(text, doc.encoding ?: NSUTF8StringEncoding, doc.hasBOM);
    if (!data) return NO;
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

- (NSUInteger)saveAllDocuments {
    NSInteger restore = self.currentIndex;
    NSUInteger saved = 0;
    for (NSInteger i = 0; i < (NSInteger)self.docs.count; ++i) {
        NppDocument *d = self.docs[i];
        if (!d.modified) continue;
        if (!d.path && getenv("NPPMAC_TEST")) continue;  // the suite cannot answer a save panel
        [self selectDocumentAtIndex:i];
        // An untitled document is asked where to go, as Windows asks.
        if (d.path ? [self writeCurrentToPath:d.path] : [self saveCurrentDocumentAs]) saved++;
    }
    [self selectDocumentAtIndex:restore];
    return saved;
}

- (BOOL)renameCurrentTo:(NSString *)newPath error:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) {
        // Nothing on disk to move: only the tab is renamed, as on Windows.
        doc.displayName = newPath.lastPathComponent;
        [self refreshChrome];
        return YES;
    }
    if (![[NSFileManager defaultManager] moveItemAtPath:doc.path toPath:newPath error:error]) return NO;
    doc.path = newPath;
    doc.displayName = newPath.lastPathComponent;
    // A language the user picked survives the rename; one worked out from the
    // old name is worked out again from the new one.
    if (!doc.languageChosenByUser) {
        doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:newPath];
    }
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
    NSString *gone = doc.path;
    [self closeDocumentAtIndex:self.currentIndex discardChanges:YES];
    [self forgetRecentFile:gone];             // as Windows takes a deleted file off the list
    return YES;
}

- (void)closeAllDocuments {
    if (![self confirmClosingDocuments:self.docs]) return;
    while (self.docs.count > 1) [self closeDocumentAtIndex:0 discardChanges:YES];
    [self closeDocumentAtIndex:0 discardChanges:YES];   // last one is replaced by a fresh tab
}

- (void)closeAllButCurrent {
    if (![self confirmClosingDocuments:[self.docs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NppDocument *d, NSDictionary *b) { return d != self.currentDocument; }]]]) return;
    NppDocument *keep = self.currentDocument;
    for (NSInteger i = (NSInteger)self.docs.count - 1; i >= 0; --i) {
        if (self.docs[i] != keep) [self closeDocumentAtIndex:i discardChanges:YES];
    }
    [self reselectDocument:keep];
}

- (void)closeAllToLeft {
    if (![self confirmClosingDocuments:[self.docs subarrayWithRange:NSMakeRange(0, (NSUInteger)MAX(0, self.currentIndex))]]) return;
    NppDocument *keep = self.currentDocument;
    for (NSInteger i = self.currentIndex - 1; i >= 0; --i) {
        [self closeDocumentAtIndex:i discardChanges:YES];
    }
    [self reselectDocument:keep];
}

- (void)closeAllToRight {
    if (![self confirmClosingDocuments:(self.currentIndex + 1 < (NSInteger)self.docs.count ? [self.docs subarrayWithRange:NSMakeRange((NSUInteger)self.currentIndex + 1, self.docs.count - (NSUInteger)self.currentIndex - 1)] : @[])]) return;
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
    if (![self confirmClosingDocuments:[self.docs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NppDocument *d, NSDictionary *b) { return !d.pinned; }]]]) return;
    for (NSInteger i = (NSInteger)self.docs.count - 1; i >= 0; --i) {
        if (!self.docs[i].pinned) [self closeDocumentAtIndex:i discardChanges:YES];
    }
}

- (void)togglePinCurrent {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    doc.pinned = !doc.pinned;
    // Pinned tabs sit at the left, as on Windows: pinning moves the tab to the
    // end of that run, unpinning to just after it.
    [self.docs removeObject:doc];
    NSUInteger pinnedRun = 0;
    while (pinnedRun < self.docs.count && self.docs[pinnedRun].pinned) pinnedRun++;
    [self.docs insertObject:doc atIndex:pinnedRun];
    self.currentIndex = (NSInteger)pinnedRun;
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
    page.string = [self documentText];
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

/// What the session keeps of a document beyond its path: where the caret and
/// the view were, its bookmarks, and the settings that are the user's rather
/// than the file's. The document in front is read live; the others were
/// recorded when they left the front.
- (NSMutableDictionary *)sessionEntryForDocument:(NppDocument *)d {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"language"] = d.language.name ?: @"normal";
    BOOL front = d == self.currentDocument;
    entry[@"caret"] = @(front ? [self.sciView message:SCI_GETCURRENTPOS] : d.caretPosition);
    entry[@"anchor"] = @(front ? [self.sciView message:SCI_GETANCHOR] : d.anchorPosition);
    entry[@"firstLine"] = @(front ? [self.sciView message:SCI_GETFIRSTVISIBLELINE] : d.firstVisibleLine);
    entry[@"pinned"] = @(d.pinned);
    entry[@"tabColour"] = @(d.tabColour);
    entry[@"encoding"] = @(d.encoding);
    entry[@"bom"] = @(d.hasBOM);
    entry[@"codepage"] = @(d.codepage);
    entry[@"eol"] = @(d.eolMode);
    if (d.backupPath && [[NSFileManager defaultManager] fileExistsAtPath:d.backupPath]) {
        entry[@"backup"] = d.backupPath;
    }
    // Bookmarks are marker 1, wherever it sits; the document can be asked
    // without being shown by pointing a query at its pointer... but Scintilla
    // answers for the view's document only, so the others were recorded on
    // leaving the front.
    if (front) {
        NSMutableArray *marks = [NSMutableArray array];
        long line = -1;
        while ((line = [self.sciView message:SCI_MARKERNEXT wParam:(uptr_t)(line + 1) lParam:(1 << 1)]) >= 0) {
            [marks addObject:@(line)];
        }
        entry[@"bookmarks"] = marks;
        d.bookmarkedLines = marks;
    } else if (d.bookmarkedLines) {
        entry[@"bookmarks"] = d.bookmarkedLines;
    }
    return entry;
}

- (BOOL)saveSessionTo:(NSString *)path error:(NSError **)error {
    NSMutableArray *files = [NSMutableArray array];
    NSMutableArray *unsaved = [NSMutableArray array];
    for (NppDocument *d in self.docs) {
        NSMutableDictionary *entry = [self sessionEntryForDocument:d];
        if (d.path) {
            entry[@"path"] = d.path;
            [files addObject:entry];
        } else if (entry[@"backup"]) {
            // An untitled document survives only through its backup.
            entry[@"name"] = d.displayName ?: @"";
            [unsaved addObject:entry];
        }
    }
    // The active tab is named by path: an index would count the unsaved
    // tabs that are not in the list, and the tabs open before the load.
    NSDictionary *session = @{@"version": @2,
                              @"current": @(MAX(0, self.currentIndex)),
                              @"currentPath": self.currentDocument.path ?: @"",
                              @"files": files,
                              @"unsaved": unsaved};
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
            [self applySessionEntry:f];
        }
    }
    // Untitled documents come back from their backups, still modified.
    NSArray *unsaved = session[@"unsaved"];
    if ([unsaved isKindOfClass:[NSArray class]]) {
        for (NSDictionary *u in unsaved) {
            NSString *backup = [u isKindOfClass:[NSDictionary class]] ? u[@"backup"] : nil;
            NSData *data = [backup isKindOfClass:[NSString class]] ? [NSData dataWithContentsOfFile:backup] : nil;
            if (!data) continue;
            [self newDocument];
            NSString *name = u[@"name"];
            if ([name isKindOfClass:[NSString class]] && name.length) self.currentDocument.displayName = name;
            [self applySessionEntry:u];
            [self restoreBackupData:data forDocument:self.currentDocument atPath:backup];
        }
    }
    NSString *currentPath = session[@"currentPath"];
    NSUInteger byPath = [currentPath isKindOfClass:[NSString class]] && currentPath.length
        ? [self.docs indexOfObjectPassingTest:^BOOL(NppDocument *d, NSUInteger i, BOOL *stop) {
              return [d.path isEqualToString:currentPath];
          }]
        : NSNotFound;
    NSNumber *cur = session[@"current"];
    if (byPath != NSNotFound) {
        [self selectDocumentAtIndex:(NSInteger)byPath];
    } else if (![currentPath isKindOfClass:[NSString class]] && [cur isKindOfClass:[NSNumber class]]) {
        // A session written before the path was kept: the index is all there is.
        [self selectDocumentAtIndex:MIN(cur.integerValue, (NSInteger)self.docs.count - 1)];
    }
    // An untitled tab was active: it is not in the list, and an index over
    // the tabs of that time would land on the wrong file; the last one opened stays.
    return opened > 0 || files.count == 0;
}

/// Puts back what the session kept of a document, once it is in front.
- (void)applySessionEntry:(NSDictionary *)f {
    NppDocument *doc = self.currentDocument;
    NSString *lang = f[@"language"];
    if ([lang isKindOfClass:[NSString class]] && lang.length) [self setLanguageNamed:lang];
    if ([f[@"codepage"] isKindOfClass:[NSNumber class]] && [f[@"codepage"] unsignedIntValue] && doc.path) {
        [self reinterpretAsCodepage:[f[@"codepage"] unsignedIntValue]];
        doc.modified = NO;
        doc.encodingChanged = NO;
        [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    }
    if ([f[@"pinned"] isKindOfClass:[NSNumber class]]) doc.pinned = [f[@"pinned"] boolValue];
    if ([f[@"tabColour"] isKindOfClass:[NSNumber class]]) doc.tabColour = [f[@"tabColour"] integerValue];
    // A backup newer than the file is the unsaved text of the last session.
    NSString *backup = f[@"backup"];
    if ([backup isKindOfClass:[NSString class]] && doc.path) {
        NSDate *backupDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:backup error:NULL] fileModificationDate];
        NSData *data = backupDate && doc.fileModificationDate &&
                       [backupDate compare:doc.fileModificationDate] != NSOrderedAscending
            ? [NSData dataWithContentsOfFile:backup] : nil;
        if (data) [self restoreBackupData:data forDocument:doc atPath:backup];
        else [[NSFileManager defaultManager] removeItemAtPath:backup error:NULL];
    }
    // The bookmarks go on once the text is final: replacing the text would
    // have swept them all onto the first line.
    NSArray *marks = f[@"bookmarks"];
    if ([marks isKindOfClass:[NSArray class]]) {
        for (NSNumber *line in marks) {
            if ([line isKindOfClass:[NSNumber class]]) {
                [self.sciView message:SCI_MARKERADD wParam:(uptr_t)line.longValue lParam:1];
            }
        }
    }
    long caret = [f[@"caret"] isKindOfClass:[NSNumber class]] ? [f[@"caret"] longValue] : 0;
    long anchor = [f[@"anchor"] isKindOfClass:[NSNumber class]] ? [f[@"anchor"] longValue] : caret;
    long length = [self.sciView message:SCI_GETLENGTH];
    [self.sciView message:SCI_SETSEL wParam:(uptr_t)MIN(anchor, length) lParam:MIN(caret, length)];
    if ([f[@"firstLine"] isKindOfClass:[NSNumber class]]) {
        [self.sciView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)[f[@"firstLine"] longValue] lParam:0];
    }
    [self refreshChrome];
}

/// The text of a backup goes into the document in front, which is then
/// modified, and the backup stays where it is until the document is saved.
- (void)restoreBackupData:(NSData *)data forDocument:(NppDocument *)doc atPath:(NSString *)backup {
    NSString *text = doc.codepage ? [EditorController stringFromData:data codepage:doc.codepage] : nil;
    if (!text) {
        NSStringEncoding enc = NSUTF8StringEncoding; BOOL bom = NO;
        text = DecodeText(data, &enc, &bom);
    }
    if (!text) return;
    [self setDocumentText:text];
    [self.sciView message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    doc.modified = YES;
    doc.backupPath = backup;
    [self refreshChrome];
}

#pragma mark - Language + theme

- (void)chooseLanguageNamed:(NSString *)langName {
    [self setLanguageNamed:langName];
    self.currentDocument.languageChosenByUser = YES;
}

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

    NppUserLanguage *udl = [[LanguageCatalog sharedCatalog] userLanguageNamed:lang.name];
    if (udl) {
        [self configureUserLexerFor:udl];
    } else {
        // The words the user added in the Style Configurator join the
        // language's own, set by set, as Notepad++ appends them.
        NSMutableDictionary<NSNumber *, NSString *> *sets = [lang.keywordSets mutableCopy] ?: [NSMutableDictionary dictionary];
        for (NppStyle *s in [[StyleCatalog sharedCatalog] stylesForLexerName:lang.name]) {
            NSNumber *idx = s.keywordClass ? NppKeywordSetIndex(s.keywordClass) : nil;
            if (!idx || !s.userKeywords.length) continue;
            sets[idx] = sets[idx].length ? [NSString stringWithFormat:@"%@ %@", sets[idx], s.userKeywords] : s.userKeywords;
        }
        for (NSNumber *idx in sets) {
            [sci setStringProperty:SCI_SETKEYWORDS parameter:idx.integerValue value:sets[idx]];
        }
    }

    [self applyTheme];
    if (udl) [self applyUserLanguageStyles:udl];
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    [self applyWordCharacters];
    [self markClickableLinks];
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

    // Global override: each attribute ticked in the Style Configurator comes
    // from the "Global override" style and beats every other style's own.
    NSDictionary *goFlags = [NppPreferences shared].globalOverride;
    NppStyle *go = styles.globalStyles[@"Global override"];
    void (^applyOverride)(int) = ^(int styleID) {
        if (!go) return;
        if ([goFlags[@"fg"] boolValue] && go.foreground)
            [sci message:SCI_STYLESETFORE wParam:(uptr_t)styleID lParam:SciColor(go.foreground)];
        if ([goFlags[@"bg"] boolValue] && go.background)
            [sci message:SCI_STYLESETBACK wParam:(uptr_t)styleID lParam:SciColor(go.background)];
        if ([goFlags[@"font"] boolValue] && go.fontName.length) {
            NSString *face = [go.fontName isEqualToString:@"Courier New"] ? @"Menlo" : go.fontName;
            [sci setStringProperty:SCI_STYLESETFONT parameter:styleID value:face];
        }
        if ([goFlags[@"fontSize"] boolValue] && go.fontSize > 0)
            [sci message:SCI_STYLESETSIZE wParam:(uptr_t)styleID lParam:go.fontSize];
        if ([goFlags[@"bold"] boolValue])
            [sci message:SCI_STYLESETBOLD wParam:(uptr_t)styleID lParam:(go.fontStyle & 1) ? 1 : 0];
        if ([goFlags[@"italic"] boolValue])
            [sci message:SCI_STYLESETITALIC wParam:(uptr_t)styleID lParam:(go.fontStyle & 2) ? 1 : 0];
        if ([goFlags[@"underline"] boolValue])
            [sci message:SCI_STYLESETUNDERLINE wParam:(uptr_t)styleID lParam:(go.fontStyle & 4) ? 1 : 0];
    };
    applyOverride(STYLE_DEFAULT);
    [sci message:SCI_STYLECLEARALL wParam:0 lParam:0];   // propagate default to all styles first

    void (^applyStyle)(NppStyle *, int) = ^(NppStyle *s, int styleID) {
        if (s.foreground) [sci message:SCI_STYLESETFORE wParam:styleID lParam:SciColor(s.foreground)];
        if (s.background) [sci message:SCI_STYLESETBACK wParam:styleID lParam:SciColor(s.background)];
        if (s.fontStyle & 1) [sci message:SCI_STYLESETBOLD wParam:styleID lParam:1];
        if (s.fontStyle & 2) [sci message:SCI_STYLESETITALIC wParam:styleID lParam:1];
        if (s.fontStyle & 4) [sci message:SCI_STYLESETUNDERLINE wParam:styleID lParam:1];
        if (s.fontName.length) [sci setStringProperty:SCI_STYLESETFONT parameter:styleID value:s.fontName];
        if (s.fontSize > 0) [sci message:SCI_STYLESETSIZE wParam:(uptr_t)styleID lParam:s.fontSize];
    };

    for (NppStyle *s in [styles stylesForLexerName:langName]) applyStyle(s, s.styleID);

    // Anything chosen in the Style Configurator wins over the shipped theme.
    // Every attribute the upstream Style struct carries is honoured here.
    NSDictionary *overrides = [NppPreferences shared].styleOverrides;
    for (NSString *key in overrides) {
        NSArray *parts = [key componentsSeparatedByString:@"/"];
        if (parts.count != 2 || ![parts[0] isEqualToString:langName]) continue;
        int styleID = [parts[1] intValue];
        NSDictionary *attrs = [[NppPreferences shared] styleOverrideForLanguage:langName
                                                                        styleID:styleID];
        if (!attrs.count) continue;

        NSColor *(^colourFrom)(NSString *) = ^NSColor *(NSString *hex) {
            unsigned int rgb = 0;
            if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return nil;
            return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                                       green:((rgb >> 8) & 0xFF) / 255.0
                                        blue:(rgb & 0xFF) / 255.0 alpha:1.0];
        };
        NSColor *fg = colourFrom(attrs[@"fg"]);
        NSColor *bg = colourFrom(attrs[@"bg"]);
        if (fg) [sci message:SCI_STYLESETFORE wParam:(uptr_t)styleID lParam:SciColor(fg)];
        if (bg) [sci message:SCI_STYLESETBACK wParam:(uptr_t)styleID lParam:SciColor(bg)];
        if (attrs[@"bold"])      [sci message:SCI_STYLESETBOLD wParam:(uptr_t)styleID
                                        lParam:[attrs[@"bold"] boolValue] ? 1 : 0];
        if (attrs[@"italic"])    [sci message:SCI_STYLESETITALIC wParam:(uptr_t)styleID
                                        lParam:[attrs[@"italic"] boolValue] ? 1 : 0];
        if (attrs[@"underline"]) [sci message:SCI_STYLESETUNDERLINE wParam:(uptr_t)styleID
                                        lParam:[attrs[@"underline"] boolValue] ? 1 : 0];
        if ([attrs[@"font"] length]) {
            [sci setStringProperty:SCI_STYLESETFONT parameter:styleID value:attrs[@"font"]];
        }
        if ([attrs[@"size"] intValue] > 0) {
            [sci message:SCI_STYLESETSIZE wParam:(uptr_t)styleID lParam:[attrs[@"size"] intValue]];
        }
    }

    for (NppStyle *s in [styles stylesForLexerName:langName]) applyOverride(s.styleID);

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
    // Changing the encoding changes the bytes on disk, so the document is
    // dirty - and stays dirty however far the text is undone, which is why
    // the savepoint is left where it was.
    doc.encodingChanged = YES;
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
    // Word Completion: the document's words, a lone one typed straight in.
    [self showCompletion:NppCompletionKindWords autoInsert:YES];
}

static const char kEditorMenuItemsKey = 0;

/// Right-click menu, built from the commands listed in Preferences.
- (void)rebuildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Context"];
    for (NSString *title in [NppPreferences shared].contextMenuCommands) {
        NSMenuItem *found = nil;
        NSMutableArray *queue = [NSMutableArray arrayWithArray:NSApp.mainMenu.itemArray];
        while (queue.count && !found) {
            NSMenuItem *item = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if (item.submenu) [queue addObjectsFromArray:item.submenu.itemArray];
            if ([item.title isEqualToString:title] && item.action) found = item;
        }
        if (!found) continue;
        NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:found.title
                                                      action:found.action keyEquivalent:@""];
        copy.target = found.target;
        copy.tag = found.tag;
        copy.representedObject = found.representedObject;
        [menu addItem:copy];
    }
    menu.delegate = (id<NSMenuDelegate>)self;
    objc_setAssociatedObject(self, &kEditorMenuItemsKey, [menu.itemArray copy], OBJC_ASSOCIATION_COPY);
    self.sciView.menu = menu;
    self.secondaryView.menu = menu;
}

/// The results tab has the Search results panel's menu instead of the editor's.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != self.sciView.menu && menu != self.secondaryView.menu) return;
    [menu removeAllItems];
    if ([self showingSearchResults]) {
        struct { NSString *title; SEL action; } items[] = {
            {@"Fold all", @selector(resultsFoldAll:)}, {@"Unfold all", @selector(resultsUnfoldAll:)},
            {nil, NULL},
            {@"Copy Selected Line(s)", @selector(resultsCopyLines:)},
            {@"Copy Selected Pathname(s)", @selector(resultsCopyPaths:)},
            {@"Select all", @selector(resultsSelectAll:)},
            {@"Clear all", @selector(resultsClearAll:)},
            {@"Delete This Search", @selector(resultsDeleteSearch:)},
            {nil, NULL},
            {@"Open Selected Pathname(s)", @selector(resultsOpenPaths:)},
            {nil, NULL},
            {@"Purge for every search", @selector(resultsTogglePurge:)},
        };
        for (auto &it : items) {
            if (!it.title) { [menu addItem:[NSMenuItem separatorItem]]; continue; }
            NSMenuItem *item = [menu addItemWithTitle:it.title action:it.action keyEquivalent:@""];
            item.target = self;
            if (it.action == @selector(resultsTogglePurge:)) {
                item.state = [NppPreferences shared].searchResultsPurge ? NSControlStateValueOn : NSControlStateValueOff;
            }
        }
        return;
    }
    for (NSMenuItem *item in objc_getAssociatedObject(self, &kEditorMenuItemsKey)) [menu addItem:[item copy]];
}

- (void)resultsFoldAll:(id)sender   { [self foldAllSearchResults:YES]; }
- (void)resultsUnfoldAll:(id)sender { [self foldAllSearchResults:NO]; }
- (void)resultsCopyLines:(id)sender { [self copySearchResultLines]; }
- (void)resultsCopyPaths:(id)sender { [self copySearchResultPaths]; }
- (void)resultsSelectAll:(id)sender { [self.sci message:SCI_SELECTALL]; }
- (void)resultsClearAll:(id)sender  { [self clearSearchResults]; }
- (void)resultsDeleteSearch:(id)sender { [self deleteSearchResultAtCaret]; }
- (void)resultsOpenPaths:(id)sender { [self openSearchResultPaths]; }
- (void)resultsTogglePurge:(id)sender {
    [NppPreferences shared].searchResultsPurge = ![NppPreferences shared].searchResultsPurge;
}

#pragma mark - Chrome refresh

- (void)refreshChrome {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NppEditorDocumentsDidChangeNotification object:self];
    NSMutableArray *tabItems = [NSMutableArray arrayWithCapacity:self.docs.count];
    for (NppDocument *d in self.docs) {
        NppTabItem *item = [[NppTabItem alloc] init];
        item.title = (d == self.currentDocument) ? [self untitledNameForDocument:d] : d.displayName;
        item.modified = d.modified;
        item.pinned = d.pinned;
        item.colour = d.tabColour;
        [tabItems addObject:item];
    }
    self.tabBar.items = tabItems;
    if (self.currentIndex >= 0 && self.currentIndex < (NSInteger)self.docs.count) {
        self.tabBar.selectedIndex = self.currentIndex;
    }
    [self applyTabBarPreferences];

    NppDocument *doc = self.currentDocument;
    ScintillaView *sci = self.sciView;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos] + 1;
    long col = [sci message:SCI_GETCOLUMN wParam:(uptr_t)pos] + 1;
    long len = [sci message:SCI_GETLENGTH];
    long lines = [sci message:SCI_GETLINECOUNT];

    NSString *eol = doc.eolMode == SC_EOL_CRLF ? @"CRLF" : doc.eolMode == SC_EOL_CR ? @"CR" : @"LF";
    // Notepad++ shows the typing mode in the status bar, and this is the only
    // place it is visible.
    NSString *typing = [self overtype] ? @"OVR" : @"INS";
    self.statusField.stringValue = [NSString stringWithFormat:
        @"%@    Ln %ld, Col %ld    %ld lines, %ld bytes    %@    %@    %@    %@",
        doc.path ?: @"(unsaved)", line, col, lines, len,
        doc.language.name ?: @"normal", [self encodingDisplayName], eol, typing];

    NSString *title = doc.path ? [NSString stringWithFormat:@"%@ — %@", doc.displayName,
                                  doc.path.stringByDeletingLastPathComponent]
                               : doc.displayName;
    if (self.titleSuffix.length) title = [title stringByAppendingFormat:@" - %@", self.titleSuffix];
    self.window.title = title;
    self.window.representedFilename = doc.path ?: @"";
    self.window.documentEdited = doc.modified;
}

/// The Tab bar page of Preferences drives the bar's layout and behaviour.
- (void)applyTabBarPreferences {
    NppPreferences *p = [NppPreferences shared];
    self.tabBar.showCloseButtons = p.tabShowCloseButton;
    self.tabBar.closeButtonsOnInactiveTabs = p.tabCloseButtonOnInactive;
    self.tabBar.doubleClickCloses = p.tabDoubleClickCloses;
    self.tabBar.locked = p.tabBarLocked;
    self.tabBar.vertical = p.tabBarVertical;
    self.tabBar.multiLine = p.tabBarMultiLine;
    self.tabBar.hidden = p.hideTabBar;
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
    self.secondaryDocument = doc;
    return YES;
}

- (BOOL)restoreLastClosedFile {
    NSString *last = [self recentFiles].firstObject;
    if (!last.length) { NSBeep(); return NO; }
    return [self openFileAtPath:last error:NULL];
}

- (NSUInteger)openAllRecentFiles {
    NSUInteger opened = 0;
    for (NSString *path in [[self recentFiles] copy]) {
        if ([self openFileAtPath:path error:NULL]) opened++;
    }
    return opened;
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

- (NppProjectPanel *)projectPanel:(NSInteger)index {
    if (index < 1 || index > 3) return nil;
    return self.projects[(NSUInteger)(index - 1)];
}

- (BOOL)confirmDiscardingProjectChanges {
    for (NppProjectPanel *p in self.projects) {
        if (![p confirmDiscardingChanges]) return NO;
    }
    return YES;
}

- (void)showProjectPanel:(NSInteger)index {
    if (index < 1 || index > 3) return;
    NppProjectPanel *panel = self.projects[(NSUInteger)(index - 1)];
    // The workspace the panel had last time comes back the first time it opens.
    if (!panel.workspacePath && !panel.root.children.count) {
        NSString *last = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppMac.projectWorkspaces"]
                         [[@(index) stringValue]];
        if (last.length && [[NSFileManager defaultManager] fileExistsAtPath:last]) [panel openWorkspace:last];
    }

    if (self.activeProject == index) {            // same panel again hides it
        [panel.view removeFromSuperview];
        self.activeProject = 0;
        [self.split adjustSubviews];
        return;
    }
    for (NppProjectPanel *p in self.projects) [p.view removeFromSuperview];
    if ([self workspaceVisible]) [self openFolderAsWorkspace:nil];

    [self.split addSubview:panel.view positioned:NSWindowBelow relativeTo:self.editorArea];
    [self.split setPosition:240 ofDividerAtIndex:0];
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
        case SCN_SAVEPOINTREACHED:
            self.currentDocument.modified = self.currentDocument.encodingChanged;
            [self refreshChrome];
            break;
        case SCN_SAVEPOINTLEFT:    self.currentDocument.modified = YES; [self refreshChrome]; break;
        case SCN_UPDATEUI:
            [self refreshChrome];
            [self mirrorScrollToSecondary];
            [self updateBraceMatch];
            if (n->updated & SC_UPDATE_SELECTION) [self updateSmartHighlight];
            break;
        case SCN_CHARADDED:
            [self handleCharacterAdded:n->ch];
            break;
        case SCN_CALLTIPCLICK:
            [self callTipClicked:(long)n->position];
            break;
        case SCN_INDICATORRELEASE:
            [self openLinkAtPosition:(long)n->position];
            break;
        case SCN_DOUBLECLICK:
            // In the results tab a double click means "take me there", the way
            // it does in Notepad++'s Search results panel. It waits for the
            // turn of the run loop after this one: Scintilla is in the middle
            // of the click, and switching the document under it leaves it
            // finishing the click on the file just opened, which puts the caret
            // back wherever the pointer happened to be.
            {
                dispatch_async(dispatch_get_main_queue(), ^{ [self openSearchResultAtCaret]; });
            }
            break;
        case SCN_MACRORECORD:
            [self recordMacroMessage:(int)n->message
                              wParam:(unsigned long)n->wParam
                              lParam:(long)n->lParam];
            break;
        default: break;
    }
}

@end

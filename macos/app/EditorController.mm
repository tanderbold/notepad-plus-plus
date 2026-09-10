#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#include "ILexer.h"
#include "Lexilla.h"

@implementation NppDocument
@end

@interface EditorController () <ScintillaNotificationProtocol>
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

    _tabBar = [[NSSegmentedControl alloc] initWithFrame:
               NSMakeRect(0, NSHeight(frame) - tabH, NSWidth(frame), tabH)];
    _tabBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _tabBar.segmentStyle = NSSegmentStyleTexturedSquare;
    _tabBar.segmentCount = 0;
    _tabBar.target = self;
    _tabBar.action = @selector(tabClicked:);
    [_container addSubview:_tabBar];

    _sciView = [[ScintillaView alloc] initWithFrame:
                NSMakeRect(0, statusH, NSWidth(frame), NSHeight(frame) - tabH - statusH)];
    _sciView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _sciView.delegate = self;
    [_container addSubview:_sciView];

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
    [sci message:SCI_SETMARGINTYPEN wParam:1 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINWIDTHN wParam:1 lParam:14];
    [sci message:SCI_SETCARETLINEVISIBLE wParam:1 lParam:0];
    [sci message:SCI_SETTABWIDTH wParam:4 lParam:0];
    [sci message:SCI_SETUSETABS wParam:0 lParam:0];
    [sci message:SCI_SETINDENTATIONGUIDES wParam:SC_IV_LOOKBOTH lParam:0];
    [sci message:SCI_SETSCROLLWIDTHTRACKING wParam:1 lParam:0];
    [sci message:SCI_SETMULTIPLESELECTION wParam:1 lParam:0];
    [sci message:SCI_SETADDITIONALSELECTIONTYPING wParam:1 lParam:0];
}

#pragma mark - Documents

- (void)newDocument {
    NppDocument *doc = [[NppDocument alloc] init];
    doc.docPointer = (void *)[self.sciView message:SCI_CREATEDOCUMENT wParam:0 lParam:SC_DOCUMENTOPTION_DEFAULT];
    doc.displayName = @"new 1";
    doc.language = [[LanguageCatalog sharedCatalog] languageNamed:@"normal"];

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

    NSStringEncoding used = 0;
    NSString *text = [NSString stringWithContentsOfFile:path usedEncoding:&used error:NULL];
    if (!text) {  // not UTF-8/UTF-16: fall back the way a plain-text editor should
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
        if (!data) return NO;
        text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
            ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!text) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                    code:NSFileReadUnknownStringEncodingError
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Cannot decode %@", path.lastPathComponent]}];
            return NO;
        }
    }

    NppDocument *doc = [[NppDocument alloc] init];
    doc.docPointer = (void *)[self.sciView message:SCI_CREATEDOCUMENT wParam:0 lParam:SC_DOCUMENTOPTION_DEFAULT];
    doc.path = path;
    doc.displayName = path.lastPathComponent;
    doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:path];

    [self.docs addObject:doc];
    [self selectDocumentAtIndex:(NSInteger)self.docs.count - 1];

    [self.sciView setString:text];
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
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
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

    NSInteger idx = self.currentIndex;
    [self.docs removeObjectAtIndex:idx];

    if (self.docs.count == 0) {
        self.currentIndex = -1;
        [self newDocument];                       // switches the view off the old doc
    } else {
        [self selectDocumentAtIndex:MIN(idx, (NSInteger)self.docs.count - 1)];
    }
    // Safe only once the view no longer points at it.
    [self.sciView message:SCI_RELEASEDOCUMENT wParam:0 lParam:(sptr_t)doc.docPointer];
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
}

#pragma mark - Chrome refresh

- (void)refreshChrome {
    self.tabBar.segmentCount = (NSInteger)self.docs.count;
    for (NSUInteger i = 0; i < self.docs.count; ++i) {
        NppDocument *d = self.docs[i];
        NSString *label = d.modified ? [d.displayName stringByAppendingString:@" •"] : d.displayName;
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

    self.statusField.stringValue = [NSString stringWithFormat:
        @"%@    Ln %ld, Col %ld    %ld lines, %ld bytes    %@",
        doc.path ?: @"(unsaved)", line, col, lines, len,
        doc.language.name ?: @"normal"];

    self.window.title = doc.path ? [NSString stringWithFormat:@"%@ — %@", doc.displayName,
                                    doc.path.stringByDeletingLastPathComponent]
                                 : doc.displayName;
    self.window.representedFilename = doc.path ?: @"";
    self.window.documentEdited = doc.modified;
}

#pragma mark - ScintillaNotificationProtocol

- (void)notification:(SCNotification *)n {
    switch (n->nmhdr.code) {
        case SCN_SAVEPOINTREACHED: self.currentDocument.modified = NO; [self refreshChrome]; break;
        case SCN_SAVEPOINTLEFT:    self.currentDocument.modified = YES; [self refreshChrome]; break;
        case SCN_UPDATEUI:         [self refreshChrome]; break;
        default: break;
    }
}

@end

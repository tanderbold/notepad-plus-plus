#import "ViewCommands.h"
#import "SettingsCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

@implementation EditorController (ViewCommands)

#pragma mark - Tabs

- (BOOL)selectTabNumber:(NSInteger)oneBased {
    NSInteger idx = oneBased - 1;
    if (idx < 0 || idx >= (NSInteger)self.documents.count) { NSBeep(); return NO; }
    [self selectDocumentAtIndex:idx];
    return YES;
}

- (void)goToFirstTab { [self selectDocumentAtIndex:0]; }
- (void)goToLastTab  { [self selectDocumentAtIndex:(NSInteger)self.documents.count - 1]; }

- (void)goToNextTab {
    NSInteger n = (NSInteger)self.documents.count;
    if (n < 2) return;
    NSInteger cur = [self.documents indexOfObject:self.currentDocument];
    [self selectDocumentAtIndex:(cur + 1) % n];
}

- (void)goToPreviousTab {
    NSInteger n = (NSInteger)self.documents.count;
    if (n < 2) return;
    NSInteger cur = [self.documents indexOfObject:self.currentDocument];
    [self selectDocumentAtIndex:(cur - 1 + n) % n];
}

- (BOOL)moveCurrentTab:(BOOL)forward {
    NSMutableArray *docs = (NSMutableArray *)self.documents;
    NSInteger from = [docs indexOfObject:self.currentDocument];
    NSInteger to = from + (forward ? 1 : -1);
    if (from == NSNotFound || to < 0 || to >= (NSInteger)docs.count) { NSBeep(); return NO; }
    [docs exchangeObjectAtIndex:(NSUInteger)from withObjectAtIndex:(NSUInteger)to];
    [self selectDocumentAtIndex:to];
    return YES;
}

- (void)moveCurrentTabToEnd:(BOOL)end {
    NSMutableArray *docs = (NSMutableArray *)self.documents;
    NppDocument *doc = self.currentDocument;
    NSInteger from = [docs indexOfObject:doc];
    if (from == NSNotFound) return;
    [docs removeObjectAtIndex:(NSUInteger)from];
    NSInteger to = end ? (NSInteger)docs.count : 0;
    [docs insertObject:doc atIndex:(NSUInteger)to];
    [self selectDocumentAtIndex:to];
}

- (void)setTabColour:(NSInteger)colour {
    self.currentDocument.tabColour = colour;
    [self refreshChrome];
}

#pragma mark - Fold levels

/// Contracts or expands every fold header whose level equals `level`.
- (void)applyFoldLevel:(NSInteger)level expanded:(BOOL)expanded {
    ScintillaView *sci = self.sci;
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    long total = [sci message:SCI_GETLINECOUNT];
    for (long line = 0; line < total; ++line) {
        long fold = [sci message:SCI_GETFOLDLEVEL wParam:(uptr_t)line];
        if (!(fold & SC_FOLDLEVELHEADERFLAG)) continue;
        long depth = (fold & SC_FOLDLEVELNUMBERMASK) - SC_FOLDLEVELBASE;
        if (depth != level - 1) continue;
        BOOL isExpanded = [sci message:SCI_GETFOLDEXPANDED wParam:(uptr_t)line] != 0;
        if (isExpanded != expanded) [sci message:SCI_TOGGLEFOLD wParam:(uptr_t)line lParam:0];
    }
    [self refreshChrome];
}

- (void)foldToLevel:(NSInteger)level   { [self applyFoldLevel:level expanded:NO]; }
- (void)unfoldToLevel:(NSInteger)level { [self applyFoldLevel:level expanded:YES]; }

#pragma mark - Symbols

- (BOOL)symbolVisible:(NppSymbol)symbol {
    ScintillaView *sci = self.sci;
    switch (symbol) {
        case NppSymbolWhitespace:  return [sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE;
        case NppSymbolEOL:         return [sci message:SCI_GETVIEWEOL] != 0;
        case NppSymbolNonPrinting: return [sci message:SCI_GETCONTROLCHARSYMBOL] != 0;
        case NppSymbolControlAndUnicodeEOL:
            return [sci message:SCI_GETVIEWEOL] != 0 && [sci message:SCI_GETCONTROLCHARSYMBOL] != 0;
        case NppSymbolIndentGuide: return [sci message:SCI_GETINDENTATIONGUIDES] != SC_IV_NONE;
        case NppSymbolWrap:        return [sci message:SCI_GETWRAPVISUALFLAGS] != SC_WRAPVISUALFLAG_NONE;
    }
    return NO;
}

- (void)toggleSymbol:(NppSymbol)symbol {
    ScintillaView *sci = self.sci;
    BOOL on = [self symbolVisible:symbol];
    switch (symbol) {
        case NppSymbolWhitespace:
            // The preference, so that nothing applied later puts it back.
            [NppPreferences shared].showWhitespace = !on;
            [sci message:SCI_SETVIEWWS wParam:(uptr_t)(on ? SCWS_INVISIBLE : SCWS_VISIBLEALWAYS) lParam:0];
            if (self.secondarySci) {
                [self.secondarySci message:SCI_SETVIEWWS
                                    wParam:(uptr_t)(on ? SCWS_INVISIBLE : SCWS_VISIBLEALWAYS) lParam:0];
            }
            break;
        case NppSymbolEOL:
            [sci message:SCI_SETVIEWEOL wParam:(uptr_t)(on ? 0 : 1) lParam:0];
            break;
        case NppSymbolNonPrinting:
            // 0 restores Scintilla's default boxed mnemonics.
            [sci message:SCI_SETCONTROLCHARSYMBOL wParam:(uptr_t)(on ? 0 : (long)'.') lParam:0];
            break;
        case NppSymbolControlAndUnicodeEOL:
            [sci message:SCI_SETVIEWEOL wParam:(uptr_t)(on ? 0 : 1) lParam:0];
            [sci message:SCI_SETCONTROLCHARSYMBOL wParam:(uptr_t)(on ? 0 : (long)'.') lParam:0];
            break;
        case NppSymbolIndentGuide:
            [sci message:SCI_SETINDENTATIONGUIDES wParam:(uptr_t)(on ? SC_IV_NONE : SC_IV_LOOKBOTH) lParam:0];
            break;
        case NppSymbolWrap:
            [sci message:SCI_SETWRAPVISUALFLAGS
                   wParam:(uptr_t)(on ? SC_WRAPVISUALFLAG_NONE : SC_WRAPVISUALFLAG_END) lParam:0];
            break;
    }
    [self refreshChrome];
}

#pragma mark - Hide lines

- (BOOL)hideSelectedLines {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    long first = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)a];
    long last  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)b];
    if (last < first) return NO;
    [sci message:SCI_HIDELINES wParam:(uptr_t)first lParam:last];
    [self refreshChrome];
    return YES;
}

- (void)showAllHiddenLines {
    ScintillaView *sci = self.sci;
    [sci message:SCI_SHOWLINES wParam:0 lParam:[sci message:SCI_GETLINECOUNT]];
    [self refreshChrome];
}

#pragma mark - Text direction

- (void)setTextDirectionRTL:(BOOL)rtl {
    [self.sci message:SCI_SETBIDIRECTIONAL
               wParam:(uptr_t)(rtl ? SC_BIDIRECTIONAL_R2L : SC_BIDIRECTIONAL_L2R) lParam:0];
    [self refreshChrome];
}

- (BOOL)textDirectionIsRTL {
    return [self.sci message:SCI_GETBIDIRECTIONAL] == SC_BIDIRECTIONAL_R2L;
}

#pragma mark - Summary

- (NSDictionary<NSString *, NSNumber *> *)documentSummary {
    ScintillaView *sci = self.sci;
    NSString *text = [sci string] ?: @"";
    // A word is a run of anything that is not one of these, which is the set
    // Notepad_plus::wordCount searches with. Splitting on every non-alphanumeric
    // instead, as this did, counts foo_bar as two words and a_b#c as three.
    NSUInteger words = 0;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:
                           @" \t\\.,;:!?()+\r\n-*/=][{}&~\"'`|@$%<>^"];
    while (!scanner.isAtEnd) {
        if ([scanner scanUpToCharactersFromSet:sep intoString:NULL]) words++;
        [scanner scanCharactersFromSet:sep intoString:NULL];
    }
    return @{@"characters": @(text.length),
             @"bytes":      @([sci message:SCI_GETLENGTH]),
             @"lines":      @([sci message:SCI_GETLINECOUNT]),
             @"words":      @(words),
             @"selected":   @([sci message:SCI_GETSELECTIONEND] - [sci message:SCI_GETSELECTIONSTART])};
}

#pragma mark - External viewers

- (BOOL)openCurrentInBrowserBundleID:(NSString *)bundleID {
    NSString *path = self.currentDocument.path;
    if (!path.length) return NO;
    NSURL *app = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleID];
    if (!app) return NO;
    [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:path]]
                       withApplicationAtURL:app
                              configuration:[NSWorkspaceOpenConfiguration configuration]
                          completionHandler:nil];
    return YES;
}

#pragma mark - Monitoring (tail -f)

static const char kMonitorSourceKey = 0;

- (BOOL)monitoringEnabled {
    return objc_getAssociatedObject(self, &kMonitorSourceKey) != nil;
}

- (void)setMonitoring:(BOOL)on {
    dispatch_source_t existing = objc_getAssociatedObject(self, &kMonitorSourceKey);
    if (existing) {
        dispatch_source_cancel(existing);
        objc_setAssociatedObject(self, &kMonitorSourceKey, nil, OBJC_ASSOCIATION_RETAIN);
    }
    if (!on) { [self refreshChrome]; return; }

    NSString *path = self.currentDocument.path;
    if (!path.length) { NSBeep(); return; }
    int fd = open(path.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) { NSBeep(); return; }

    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE,
        dispatch_get_main_queue());
    __weak EditorController *weakSelf = self;
    dispatch_source_set_event_handler(src, ^{
        EditorController *me = weakSelf;
        if (!me) return;
        // Reload and stay pinned to the end, which is what tail -f looks like.
        [me reloadCurrentDocument:NULL];
        [me.sci message:SCI_DOCUMENTEND];
    });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
    objc_setAssociatedObject(self, &kMonitorSourceKey, src, OBJC_ASSOCIATION_RETAIN);
    [self refreshChrome];
}

@end

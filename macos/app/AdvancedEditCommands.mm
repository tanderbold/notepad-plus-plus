#import "AdvancedEditCommands.h"
#import "ApiCatalog.h"
#import "EditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

static long Utf8Len(NSString *s) {
    return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

static NSString *SliceBytes(NSData *data, long start, long end) {
    if (start < 0) start = 0;
    if (end > (long)data.length) end = (long)data.length;
    if (end <= start) return @"";
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)start,
                                                                            (NSUInteger)(end - start))]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

@implementation EditorController (AdvancedEditCommands)

#pragma mark - Shared

- (NSString *)currentSelectionOrWord {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (a == b) {
        long pos = [sci message:SCI_GETCURRENTPOS];
        a = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        b = [sci message:SCI_WORDENDPOSITION wParam:(uptr_t)pos lParam:1];
    }
    if (b <= a) return @"";
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return SliceBytes(data, a, b);
}

/// Byte offsets of every match of `term` under the given flags.
- (NSArray<NSNumber *> *)matchesOf:(NSString *)term flags:(NppMatchFlags)flags {
    ScintillaView *sci = self.sci;
    NSMutableArray *out = [NSMutableArray array];
    if (!term.length) return out;

    long sciFlags = 0;
    if (flags & NppMatchCase) sciFlags |= SCFIND_MATCHCASE;
    if (flags & NppMatchWholeWord) sciFlags |= SCFIND_WHOLEWORD;

    const char *needle = term.UTF8String;
    long len = Utf8Len(term);
    long docLen = [sci message:SCI_GETLENGTH];
    long from = 0;
    while (from < docLen) {
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from lParam:0];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)docLen lParam:0];
        [sci message:SCI_SETSEARCHFLAGS wParam:(uptr_t)sciFlags lParam:0];
        long hit = [sci message:SCI_SEARCHINTARGET wParam:(uptr_t)len lParam:(sptr_t)needle];
        if (hit < 0) break;
        [out addObject:@(hit)];
        from = hit + MAX(1, len);
    }
    return out;
}

#pragma mark - Multi-selection

- (NSUInteger)selectionCount { return (NSUInteger)[self.sci message:SCI_GETSELECTIONS]; }

- (NSUInteger)multiSelectAllOccurrences:(NppMatchFlags)flags {
    ScintillaView *sci = self.sci;
    NSString *term = [self currentSelectionOrWord];
    NSArray *hits = [self matchesOf:term flags:flags];
    if (!hits.count) { NSBeep(); return 0; }

    long len = Utf8Len(term);
    [sci message:SCI_SETSELECTION wParam:(uptr_t)[hits.firstObject longValue]
             lParam:[hits.firstObject longValue] + len];
    for (NSUInteger i = 1; i < hits.count; ++i) {
        long at = [hits[i] longValue];
        [sci message:SCI_ADDSELECTION wParam:(uptr_t)(at + len) lParam:at];
    }
    [self refreshChrome];
    return hits.count;
}

- (BOOL)multiSelectNextOccurrence:(NppMatchFlags)flags {
    ScintillaView *sci = self.sci;
    NSString *term = [self currentSelectionOrWord];
    NSArray *hits = [self matchesOf:term flags:flags];
    if (hits.count < 2) { NSBeep(); return NO; }

    long len = Utf8Len(term);
    long last = [sci message:SCI_GETSELECTIONNCARET
                      wParam:(uptr_t)([sci message:SCI_GETSELECTIONS] - 1)];
    long target = -1;
    for (NSNumber *h in hits) {
        if (h.longValue + len > last) { target = h.longValue; break; }
    }
    if (target < 0) target = [hits.firstObject longValue];    // wrap around
    [sci message:SCI_ADDSELECTION wParam:(uptr_t)(target + len) lParam:target];
    [sci message:SCI_SCROLLCARET];
    [self refreshChrome];
    return YES;
}

- (BOOL)undoLastMultiSelection {
    ScintillaView *sci = self.sci;
    long n = [sci message:SCI_GETSELECTIONS];
    if (n < 2) { NSBeep(); return NO; }
    [sci message:SCI_DROPSELECTIONN wParam:(uptr_t)(n - 1) lParam:0];
    [self refreshChrome];
    return YES;
}

- (BOOL)skipCurrentMultiSelection {
    ScintillaView *sci = self.sci;
    long n = [sci message:SCI_GETSELECTIONS];
    if (n < 1) { NSBeep(); return NO; }
    // Drop the selection the caret is on, then take the one after it.
    long main = [sci message:SCI_GETMAINSELECTION];
    if (n > 1) [sci message:SCI_DROPSELECTIONN wParam:(uptr_t)main lParam:0];
    return [self multiSelectNextOccurrence:NppMatchNone];
}

#pragma mark - Begin/End select

static const char kBeginEndAnchorKey = 0;

- (BOOL)beginEndSelectActive {
    return objc_getAssociatedObject(self, &kBeginEndAnchorKey) != nil;
}

/// First call drops an anchor, second extends the selection to the caret --
/// Notepad++'s Begin/End Select, in normal or column mode.
- (BOOL)beginEndSelectColumnMode:(BOOL)columnMode {
    ScintillaView *sci = self.sci;
    NSNumber *anchor = objc_getAssociatedObject(self, &kBeginEndAnchorKey);
    long caret = [sci message:SCI_GETCURRENTPOS];

    if (!anchor) {
        objc_setAssociatedObject(self, &kBeginEndAnchorKey, @(caret), OBJC_ASSOCIATION_RETAIN);
        return NO;                       // anchor dropped, selection not made yet
    }
    objc_setAssociatedObject(self, &kBeginEndAnchorKey, nil, OBJC_ASSOCIATION_RETAIN);

    if (columnMode) {
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:(uptr_t)anchor.longValue lParam:0];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:(uptr_t)caret lParam:0];
    } else {
        [sci message:SCI_SETSEL wParam:(uptr_t)anchor.longValue lParam:caret];
    }
    [self refreshChrome];
    return YES;
}

#pragma mark - Column editor

/// Inserts into each row of a rectangular selection, as the Column Editor does.
- (BOOL)columnApply:(NSString *(^)(NSUInteger row))textForRow {
    ScintillaView *sci = self.sci;
    long selections = [sci message:SCI_GETSELECTIONS];
    if (selections < 1) return NO;

    // Each row: what it covers, and how far past the end of a short line the
    // rectangle reaches (virtual space), which becomes real spaces.
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (long i = 0; i < selections; ++i) {
        long start = [sci message:SCI_GETSELECTIONNSTART wParam:(uptr_t)i];
        long end = [sci message:SCI_GETSELECTIONNEND wParam:(uptr_t)i];
        long anchorSpace = [sci message:SCI_GETSELECTIONNANCHORVIRTUALSPACE wParam:(uptr_t)i];
        long caretSpace = [sci message:SCI_GETSELECTIONNCARETVIRTUALSPACE wParam:(uptr_t)i];
        long pad = start == end ? MIN(anchorSpace, caretSpace) : 0;
        [rows addObject:@{@"start": @(start), @"end": @(end), @"pad": @(pad)}];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"start"] compare:b[@"start"]];
    }];

    [sci message:SCI_BEGINUNDOACTION];
    // Bottom-up so earlier offsets stay valid. The selected column is
    // replaced, as the Column Editor does, not pushed along.
    for (NSUInteger i = rows.count; i > 0; --i) {
        NSString *text = textForRow(i - 1);
        if (!text.length) continue;
        NSDictionary *row = rows[i - 1];
        NSString *padded = [[@"" stringByPaddingToLength:[row[@"pad"] unsignedIntegerValue]
                                              withString:@" " startingAtIndex:0]
                            stringByAppendingString:text];
        [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)[row[@"start"] longValue]
                                        lParam:[row[@"end"] longValue]];
        [sci setStringProperty:SCI_REPLACETARGET parameter:Utf8Len(padded) value:padded];
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    return YES;
}

- (BOOL)columnInsertText:(NSString *)text {
    if (!text.length) return NO;
    return [self columnApply:^NSString *(NSUInteger row) { return text; }];
}

- (BOOL)columnInsertNumbersFrom:(long)initial increment:(long)increment
                     zeroPadded:(BOOL)padded base:(int)base {
    ScintillaView *sci = self.sci;
    long rows = [sci message:SCI_GETSELECTIONS];
    if (rows < 1) return NO;

    NSMutableArray *rendered = [NSMutableArray array];
    NSUInteger widest = 0;
    for (long i = 0; i < rows; ++i) {
        long value = initial + increment * i;
        NSString *s;
        switch (base) {
            case 16: s = [NSString stringWithFormat:@"%lX", value]; break;
            case 8:  s = [NSString stringWithFormat:@"%lo", value]; break;
            case 2: {
                NSMutableString *bits = [NSMutableString string];
                for (long v = value; v > 0; v >>= 1) [bits insertString:(v & 1) ? @"1" : @"0" atIndex:0];
                s = bits.length ? bits : @"0";
                break;
            }
            default: s = [NSString stringWithFormat:@"%ld", value]; break;
        }
        widest = MAX(widest, s.length);
        [rendered addObject:s];
    }
    if (padded) {
        for (NSUInteger i = 0; i < rendered.count; ++i) {
            NSString *s = rendered[i];
            if (s.length < widest) {
                rendered[i] = [[@"" stringByPaddingToLength:widest - s.length
                                                 withString:@"0" startingAtIndex:0]
                               stringByAppendingString:s];
            }
        }
    }
    return [self columnApply:^NSString *(NSUInteger row) {
        return row < rendered.count ? rendered[row] : @"";
    }];
}

#pragma mark - On selection

- (NSString *)selectionAsPath {
    NSString *raw = [[self currentSelectionOrWord]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!raw.length) return nil;
    if ([raw hasPrefix:@"\""] && [raw hasSuffix:@"\""] && raw.length > 1) {
        raw = [raw substringWithRange:NSMakeRange(1, raw.length - 2)];
    }
    if ([raw hasPrefix:@"~"]) raw = raw.stringByExpandingTildeInPath;
    if (![raw hasPrefix:@"/"]) {
        NSString *base = self.currentDocument.path.stringByDeletingLastPathComponent;
        if (base.length) raw = [base stringByAppendingPathComponent:raw];
    }
    return [[NSFileManager defaultManager] fileExistsAtPath:raw] ? raw : nil;
}

- (BOOL)openSelectedFile {
    NSString *path = [self selectionAsPath];
    if (!path) { NSBeep(); return NO; }
    return [self openFileAtPath:path error:NULL];
}

- (BOOL)revealSelectedFile {
    NSString *path = [self selectionAsPath];
    if (!path) { NSBeep(); return NO; }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
    return YES;
}

- (BOOL)redactSelectionWithBlock:(BOOL)solidBlock {
    ScintillaView *sci = self.sci;
    long selections = [sci message:SCI_GETSELECTIONS];
    if (selections < 1) return NO;
    // Notepad++ offers a full block or a bullet; █ and ●.
    NSString *mark = solidBlock ? @"█" : @"●";
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];

    BOOL any = NO;
    [sci message:SCI_BEGINUNDOACTION];
    for (long i = selections - 1; i >= 0; --i) {
        long a = [sci message:SCI_GETSELECTIONNSTART wParam:(uptr_t)i];
        long b = [sci message:SCI_GETSELECTIONNEND wParam:(uptr_t)i];
        if (b <= a) continue;
        NSUInteger chars = SliceBytes(doc, a, b).length;
        NSMutableString *replacement = [NSMutableString string];
        for (NSUInteger c = 0; c < chars; ++c) [replacement appendString:mark];
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)a lParam:0];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)b lParam:0];
        [sci setStringProperty:SCI_REPLACETARGET parameter:Utf8Len(replacement) value:replacement];
        any = YES;
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    if (!any) NSBeep();
    return any;
}

static const char kSearchEngineKey = 0;

- (NSString *)searchEngineTemplate {
    NSString *stored = objc_getAssociatedObject(self, &kSearchEngineKey);
    return stored ?: @"https://duckduckgo.com/?q=%@";
}

- (void)setSearchEngineTemplate:(NSString *)engineTemplate {
    objc_setAssociatedObject(self, &kSearchEngineKey, [engineTemplate copy], OBJC_ASSOCIATION_COPY);
}

- (BOOL)searchSelectionOnInternet {
    NSString *term = [self currentSelectionOrWord];
    if (!term.length) { NSBeep(); return NO; }
    NSString *escaped = [term stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:self.searchEngineTemplate, escaped]];
    if (!url) { NSBeep(); return NO; }
    return [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Paste special

- (void)insertStringAtCaret:(NSString *)text {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:text];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS wParam:(uptr_t)(pos + Utf8Len(text)) lParam:0];
    [self refreshChrome];
}

- (BOOL)pasteAsHTML {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *html = [pb stringForType:NSPasteboardTypeHTML];
    if (!html.length) {
        NSData *data = [pb dataForType:NSPasteboardTypeHTML];
        html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    }
    if (!html.length) { NSBeep(); return NO; }
    [self insertStringAtCaret:html];
    return YES;
}

- (BOOL)pasteAsRTF {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSData *rtf = [pb dataForType:NSPasteboardTypeRTF];
    if (!rtf) { NSBeep(); return NO; }
    NSString *text = [[NSString alloc] initWithData:rtf encoding:NSASCIIStringEncoding];
    if (!text.length) { NSBeep(); return NO; }
    [self insertStringAtCaret:text];
    return YES;
}

/// Notepad++'s binary clipboard keeps the raw bytes; here they travel as hex
/// pairs, which survives the text-only pasteboard without losing anything.
- (NSString *)hexOfSelection {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (b <= a) return nil;
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if ((NSUInteger)b > doc.length) return nil;
    NSData *slice = [doc subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a))];
    const unsigned char *bytes = (const unsigned char *)slice.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:slice.length * 3];
    for (NSUInteger i = 0; i < slice.length; ++i) {
        if (i) [hex appendString:@" "];
        [hex appendFormat:@"%02X", bytes[i]];
    }
    return hex;
}

- (BOOL)copySelectionAsBinary {
    NSString *hex = [self hexOfSelection];
    if (!hex) { NSBeep(); return NO; }
    [self copyToClipboard:hex];
    return YES;
}

- (BOOL)cutSelectionAsBinary {
    if (![self copySelectionAsBinary]) return NO;
    [self.sci message:SCI_CLEAR];
    [self refreshChrome];
    return YES;
}

- (BOOL)pasteBinary {
    NSString *hex = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (!hex.length) { NSBeep(); return NO; }
    NSMutableData *bytes = [NSMutableData data];
    for (NSString *pair in [hex componentsSeparatedByCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (pair.length != 2) continue;
        unsigned int value = 0;
        if (![[NSScanner scannerWithString:pair] scanHexInt:&value]) continue;
        unsigned char b = (unsigned char)value;
        [bytes appendBytes:&b length:1];
    }
    if (!bytes.length) { NSBeep(); return NO; }
    NSString *text = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding]
                  ?: [[NSString alloc] initWithData:bytes encoding:NSISOLatin1StringEncoding];
    if (!text) { NSBeep(); return NO; }
    [self insertStringAtCaret:text];
    return YES;
}

#pragma mark - Auto-completion helpers

- (BOOL)showPathCompletion {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long lineStart = [sci message:SCI_POSITIONFROMLINE
                             wParam:(uptr_t)[sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos]];
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSString *before = SliceBytes(doc, lineStart, pos);

    NSRange sep = [before rangeOfString:@"/" options:NSBackwardsSearch];
    if (sep.location == NSNotFound) { NSBeep(); return NO; }
    NSUInteger start = [before rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]
                                               options:NSBackwardsSearch
                                                 range:NSMakeRange(0, sep.location)].location;
    NSString *fragment = [before substringFromIndex:(start == NSNotFound ? 0 : start + 1)];
    NSString *dir = fragment.stringByDeletingLastPathComponent.stringByExpandingTildeInPath;
    NSString *prefix = fragment.lastPathComponent;

    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    if (!names.count) { NSBeep(); return NO; }
    NSMutableArray *matches = [NSMutableArray array];
    for (NSString *n in names) if (!prefix.length || [n hasPrefix:prefix]) [matches addObject:n];
    if (!matches.count) { NSBeep(); return NO; }

    [matches sortUsingSelector:@selector(compare:)];
    [sci message:SCI_AUTOCSETSEPARATOR wParam:(uptr_t)'\n' lParam:0];
    [sci setStringProperty:SCI_AUTOCSHOW parameter:(long)prefix.length
                     value:[matches componentsJoinedByString:@"\n"]];
    return YES;
}

/// What to show for the word under the caret: the signatures Notepad++ ships for
/// this language, and failing that the lines in this file that look like a
/// declaration of it.
- (NSArray<NSString *> *)callTipCandidates {
    NSString *word = [self currentSelectionOrWord];
    if (!word.length) return @[];

    NSArray<NSString *> *fromApi =
        [[ApiCatalog sharedCatalog] callTipsForLanguage:self.currentDocument.language.name ?: @""
                                               function:word];
    if (fromApi.count) return fromApi;

    NSMutableArray *tips = [NSMutableArray array];
    for (NSString *line in [([self.sci string] ?: @"") componentsSeparatedByString:@"\n"]) {
        if ([line rangeOfString:word].location == NSNotFound) continue;
        if ([line rangeOfString:@"("].location == NSNotFound) continue;
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length && ![tips containsObject:trimmed]) [tips addObject:trimmed];
    }
    return tips;
}

static const char kCallTipIndexKey = 0;

- (BOOL)showFunctionCallTip {
    NSArray *tips = [self callTipCandidates];
    if (!tips.count) { NSBeep(); return NO; }
    objc_setAssociatedObject(self, &kCallTipIndexKey, @0, OBJC_ASSOCIATION_RETAIN);
    NSString *body = tips.count > 1
        ? [NSString stringWithFormat:@"%@   (1 of %lu)", tips[0], (unsigned long)tips.count]
        : tips[0];
    [self.sci setStringProperty:SCI_CALLTIPSHOW
                      parameter:[self.sci message:SCI_GETCURRENTPOS] value:body];
    return YES;
}

- (BOOL)cycleFunctionCallTip:(BOOL)forward {
    NSArray *tips = [self callTipCandidates];
    if (tips.count < 2) { NSBeep(); return NO; }
    NSNumber *stored = objc_getAssociatedObject(self, &kCallTipIndexKey);
    NSInteger idx = (stored.integerValue + (forward ? 1 : -1) + (NSInteger)tips.count)
                    % (NSInteger)tips.count;
    objc_setAssociatedObject(self, &kCallTipIndexKey, @(idx), OBJC_ASSOCIATION_RETAIN);
    NSString *body = [NSString stringWithFormat:@"%@   (%ld of %lu)",
                      tips[(NSUInteger)idx], (long)idx + 1, (unsigned long)tips.count];
    [self.sci setStringProperty:SCI_CALLTIPSHOW
                      parameter:[self.sci message:SCI_GETCURRENTPOS] value:body];
    return YES;
}

#pragma mark - File attribute

/// Notepad++ toggles the Windows read-only attribute; the macOS counterpart is
/// the file's write permission.
- (BOOL)systemReadOnly {
    NSString *path = self.currentDocument.path;
    if (!path.length) return NO;
    return ![[NSFileManager defaultManager] isWritableFileAtPath:path];
}

- (BOOL)toggleSystemReadOnly {
    NSString *path = self.currentDocument.path;
    if (!path.length) { NSBeep(); return NO; }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
    if (!attrs) { NSBeep(); return NO; }

    NSUInteger perms = [attrs[NSFilePosixPermissions] unsignedIntegerValue];
    NSUInteger updated = [self systemReadOnly] ? (perms | 0200) : (perms & ~(NSUInteger)0222);
    if (![fm setAttributes:@{NSFilePosixPermissions: @(updated)} ofItemAtPath:path error:NULL]) {
        NSBeep();
        return NO;
    }
    [self refreshChrome];
    return YES;
}

@end

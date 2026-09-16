#import "SearchCommands.h"
#import "SettingsCommands.h"
#import "EditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"

#define NPPMAC_BOOKMARK_MARKER 1

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

@implementation EditorController (SearchCommands)

#pragma mark - Indicator plumbing

/// style 0..4 -> indicators 8..12; NPPMAC_STYLE_COUNT -> the Find Mark indicator.
static int IndicatorFor(NSInteger style) {
    if (style >= NPPMAC_STYLE_COUNT) return NPPMAC_FIND_MARK_INDICATOR;
    if (style < 0) style = 0;
    return NPPMAC_STYLE_FIRST_INDICATOR + (int)style;
}

- (void)ensureIndicatorConfigured:(int)indicator {
    ScintillaView *sci = self.sci;
    static const long colours[] = {
        0x00FFFF,   // yellow-ish (BGR)
        0x7FFF00,   // green
        0xFF7F7F,   // blue
        0xFF7FFF,   // magenta
        0x7FFFFF,   // orange
        0x00A5FF,   // find mark
    };
    int slot = indicator - NPPMAC_STYLE_FIRST_INDICATOR;
    if (slot < 0 || slot > NPPMAC_STYLE_COUNT) slot = NPPMAC_STYLE_COUNT;
    [sci message:SCI_INDICSETSTYLE wParam:(uptr_t)indicator lParam:INDIC_ROUNDBOX];
    [sci message:SCI_INDICSETALPHA wParam:(uptr_t)indicator lParam:80];
    [sci message:SCI_INDICSETUNDER wParam:(uptr_t)indicator lParam:1];
    [sci message:SCI_INDICSETFORE wParam:(uptr_t)indicator lParam:colours[slot]];
}

- (NSString *)selectedText {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (a == b) {   // fall back to the word under the caret, as Notepad++ does
        long pos = [sci message:SCI_GETCURRENTPOS];
        a = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        b = [sci message:SCI_WORDENDPOSITION wParam:(uptr_t)pos lParam:1];
    }
    if (b <= a) return @"";
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return SliceBytes(data, a, b);
}

/// Byte offsets of every occurrence of `term`.
- (NSArray<NSNumber *> *)occurrencesOf:(NSString *)term {
    // Plain matching, which is what the callers that do not offer the choice
    // have always used.
    return [self occurrencesOf:term matchCase:NO wholeWord:NO];
}

- (NSArray<NSNumber *> *)occurrencesOf:(NSString *)term
                             matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord {
    ScintillaView *sci = self.sci;
    NSMutableArray *out = [NSMutableArray array];
    if (!term.length) return out;
    const char *needle = term.UTF8String;
    long len = Utf8Len(term);
    long docLen = [sci message:SCI_GETLENGTH];
    long from = 0;
    while (from < docLen) {
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from lParam:0];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)docLen lParam:0];
        long flags = (matchCase ? SCFIND_MATCHCASE : 0) | (wholeWord ? SCFIND_WHOLEWORD : 0);
        [sci message:SCI_SETSEARCHFLAGS wParam:(uptr_t)flags lParam:0];
        long hit = [sci message:SCI_SEARCHINTARGET wParam:(uptr_t)len lParam:(sptr_t)needle];
        if (hit < 0) break;
        [out addObject:@(hit)];
        from = hit + MAX(1, len);
    }
    return out;
}

#pragma mark - Token styling

- (NSUInteger)markAllOccurrencesOfSelection:(NSInteger)style {
    // Mark All has its own case and whole-word settings, as it does in
    // Notepad++; smart highlighting has separate ones and asks explicitly.
    NppPreferences *prefs = [NppPreferences shared];
    return [self markAllOccurrencesOfSelection:style
                                     matchCase:prefs.markAllCaseSensitive
                                     wholeWord:prefs.markAllWordOnly];
}

- (NSUInteger)markAllOccurrencesOfSelection:(NSInteger)style
                                  matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord {
    ScintillaView *sci = self.sci;
    NSString *term = [self selectedText];
    if (!term.length) { NSBeep(); return 0; }
    int ind = IndicatorFor(style);
    [self ensureIndicatorConfigured:ind];
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];

    NSArray *hits = [self occurrencesOf:term matchCase:matchCase wholeWord:wholeWord];
    long len = Utf8Len(term);
    for (NSNumber *hit in hits) {
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)hit.longValue lParam:len];
    }
    return hits.count;
}

- (void)markOneOccurrenceOfSelection:(NSInteger)style {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (b <= a) { NSBeep(); return; }
    int ind = IndicatorFor(style);
    [self ensureIndicatorConfigured:ind];
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
    [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)a lParam:b - a];
}

- (void)clearStyle:(NSInteger)style {
    ScintillaView *sci = self.sci;
    int ind = IndicatorFor(style);
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];
}

- (void)clearAllStyles {
    for (NSInteger i = 0; i <= NPPMAC_STYLE_COUNT; ++i) [self clearStyle:i];
}

/// Ranges carrying the indicator, as {start, length} pairs.
- (NSArray<NSValue *> *)rangesOfStyle:(NSInteger)style {
    ScintillaView *sci = self.sci;
    int ind = IndicatorFor(style);
    long docLen = [sci message:SCI_GETLENGTH];
    NSMutableArray *out = [NSMutableArray array];
    long pos = 0;
    while (pos < docLen) {
        if ([sci message:SCI_INDICATORVALUEAT wParam:(uptr_t)ind lParam:pos]) {
            long end = [sci message:SCI_INDICATOREND wParam:(uptr_t)ind lParam:pos];
            if (end <= pos) break;
            [out addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)pos, (NSUInteger)(end - pos))]];
            pos = end;
        } else {
            long next = [sci message:SCI_INDICATOREND wParam:(uptr_t)ind lParam:pos];
            pos = (next > pos) ? next : pos + 1;
        }
    }
    return out;
}

- (BOOL)jumpToMarker:(NSInteger)style forward:(BOOL)forward {
    ScintillaView *sci = self.sci;
    NSArray *ranges = [self rangesOfStyle:style];
    if (!ranges.count) { NSBeep(); return NO; }
    // Measure from the far edge of the current selection, otherwise jumping back
    // from a selected marker lands on that same marker.
    long caret = forward ? [sci message:SCI_GETSELECTIONEND]
                         : [sci message:SCI_GETSELECTIONSTART];

    NSRange chosen = forward ? [ranges.firstObject rangeValue] : [ranges.lastObject rangeValue];
    if (forward) {
        for (NSValue *v in ranges) {
            if ((long)v.rangeValue.location > caret) { chosen = v.rangeValue; break; }
        }
    } else {
        for (NSValue *v in ranges.reverseObjectEnumerator) {
            if ((long)v.rangeValue.location < caret) { chosen = v.rangeValue; break; }
        }
    }
    [sci message:SCI_SETSEL wParam:(uptr_t)chosen.location
             lParam:(sptr_t)(chosen.location + chosen.length)];
    [sci message:SCI_SCROLLCARET];
    [self refreshChrome];
    return YES;
}

- (NSString *)textOfStyle:(NSInteger)style {
    NSData *data = [([self.sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray *out = [NSMutableArray array];
    for (NSValue *v in [self rangesOfStyle:style]) {
        NSRange r = v.rangeValue;
        [out addObject:SliceBytes(data, (long)r.location, (long)(r.location + r.length))];
    }
    return [out componentsJoinedByString:@"\n"];
}

- (NSString *)textOfAllStyles {
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger i = 0; i < NPPMAC_STYLE_COUNT; ++i) {
        NSString *t = [self textOfStyle:i];
        if (t.length) [out addObject:t];
    }
    return [out componentsJoinedByString:@"\n"];
}

#pragma mark - Bookmarked lines

- (NSArray<NSNumber *> *)bookmarkedLines {
    ScintillaView *sci = self.sci;
    NSMutableArray *out = [NSMutableArray array];
    long total = [sci message:SCI_GETLINECOUNT];
    for (long line = 0; line < total; ++line) {
        if ([sci message:SCI_MARKERGET wParam:(uptr_t)line] & (1 << NPPMAC_BOOKMARK_MARKER)) {
            [out addObject:@(line)];
        }
    }
    return out;
}

- (NSString *)lineText:(long)line {
    ScintillaView *sci = self.sci;
    long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
    long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return SliceBytes(data, start, end);
}

- (NSString *)bookmarkedLinesText {
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *line in [self bookmarkedLines]) [out addObject:[self lineText:line.longValue]];
    return [out componentsJoinedByString:@"\n"];
}

- (void)copyBookmarkedLines {
    [self copyToClipboard:[self bookmarkedLinesText]];
}

- (void)cutBookmarkedLines {
    [self copyBookmarkedLines];
    [self removeBookmarkedLines];
}

- (void)deleteLines:(NSArray<NSNumber *> *)lines {
    ScintillaView *sci = self.sci;
    [sci message:SCI_BEGINUNDOACTION];
    // Bottom-up so earlier line numbers stay valid.
    for (NSNumber *n in lines.reverseObjectEnumerator) {
        long line = n.longValue;
        long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
        long next = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(line + 1)];
        if (next <= start) next = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
        [sci message:SCI_DELETERANGE wParam:(uptr_t)start lParam:next - start];
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
}

- (void)removeBookmarkedLines { [self deleteLines:[self bookmarkedLines]]; }

- (void)removeUnbookmarkedLines {
    NSSet *marked = [NSSet setWithArray:[self bookmarkedLines]];
    NSMutableArray *others = [NSMutableArray array];
    long total = [self.sci message:SCI_GETLINECOUNT];
    for (long line = 0; line < total; ++line) {
        if (![marked containsObject:@(line)]) [others addObject:@(line)];
    }
    [self deleteLines:others];
}

- (void)pasteOverBookmarkedLines {
    NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"";
    NSArray *replacement = [clip componentsSeparatedByString:@"\n"];
    NSArray *lines = [self bookmarkedLines];
    if (!lines.count) { NSBeep(); return; }

    ScintillaView *sci = self.sci;
    [sci message:SCI_BEGINUNDOACTION];
    NSUInteger i = lines.count;
    for (NSNumber *n in lines.reverseObjectEnumerator) {
        i--;
        long line = n.longValue;
        long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
        long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
        NSString *text = i < replacement.count ? replacement[i] : @"";
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)start lParam:0];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)end lParam:0];
        [sci setStringProperty:SCI_REPLACETARGET parameter:Utf8Len(text) value:text];
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
}

- (void)inverseBookmarks {
    ScintillaView *sci = self.sci;
    NSSet *marked = [NSSet setWithArray:[self bookmarkedLines]];
    long total = [sci message:SCI_GETLINECOUNT];
    for (long line = 0; line < total; ++line) {
        if ([marked containsObject:@(line)]) {
            [sci message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
        } else {
            [sci message:SCI_MARKERADD wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
        }
    }
}

#pragma mark - Braces

- (BOOL)goToMatchingBrace {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    if (match < 0 && pos > 0) {
        pos -= 1;
        match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    }
    if (match < 0) { NSBeep(); return NO; }
    [sci message:SCI_GOTOPOS wParam:(uptr_t)match lParam:0];
    [self refreshChrome];
    return YES;
}

- (BOOL)selectBetweenMatchingBraces {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    if (match < 0 && pos > 0) {
        pos -= 1;
        match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    }
    if (match < 0) { NSBeep(); return NO; }
    long from = MIN(pos, match) + 1, to = MAX(pos, match);
    [sci message:SCI_SETSEL wParam:(uptr_t)from lParam:to];
    [self refreshChrome];
    return YES;
}

#pragma mark - Find in Files

- (NSUInteger)findInFiles:(NSString *)term inFolder:(NSString *)folder filter:(NSString *)filter {
    if (!term.length || !folder.length) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *walker = [fm enumeratorAtPath:folder];
    NSMutableString *report = [NSMutableString stringWithFormat:
        @"Search \"%@\" in %@\n\n", term, folder];
    NSUInteger hits = 0, files = 0;

    for (NSString *rel in walker) {
        NSString *full = [folder stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) continue;
        if (filter.length && ![rel.pathExtension.lowercaseString
                               isEqualToString:filter.lowercaseString]) continue;

        NSString *content = [NSString stringWithContentsOfFile:full encoding:NSUTF8StringEncoding error:NULL];
        if (!content) continue;                       // binary or another encoding

        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        NSMutableString *fileBlock = [NSMutableString string];
        NSUInteger fileHits = 0;
        for (NSUInteger i = 0; i < lines.count; ++i) {
            if ([lines[i] rangeOfString:term].location == NSNotFound) continue;
            fileHits++;
            [fileBlock appendFormat:@"\tLine %lu: %@\n", (unsigned long)(i + 1), lines[i]];
        }
        if (fileHits) {
            files++;
            hits += fileHits;
            [report appendFormat:@"%@ (%lu hit%@)\n%@\n", full, (unsigned long)fileHits,
                                 fileHits == 1 ? @"" : @"s", fileBlock];
        }
    }
    [report appendFormat:@"\n%lu hit%@ in %lu file%@\n", (unsigned long)hits, hits == 1 ? @"" : @"s",
                         (unsigned long)files, files == 1 ? @"" : @"s"];

    [self showSearchResults:report];
    return hits;
}

- (void)showSearchResults:(NSString *)report {
    // Notepad++ docks a results panel; here the results are a tab of their own.
    [self newDocument];
    self.currentDocument.displayName = @"Search results";
    [self.sci setString:report ?: @""];
    [self.sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    self.currentDocument.modified = NO;
    [self refreshChrome];
}

- (NSInteger)searchResultsTabIndex {
    for (NSUInteger i = 0; i < self.documents.count; ++i) {
        if ([self.documents[i].displayName isEqualToString:@"Search results"]) return (NSInteger)i;
    }
    return -1;
}

- (BOOL)focusSearchResults {
    NSInteger idx = [self searchResultsTabIndex];
    if (idx < 0) { NSBeep(); return NO; }
    [self selectDocumentAtIndex:idx];
    return YES;
}

- (BOOL)goToSearchResult:(BOOL)forward {
    if (![self focusSearchResults]) return NO;
    ScintillaView *sci = self.sci;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long total = [sci message:SCI_GETLINECOUNT];

    for (long probe = line + (forward ? 1 : -1); probe >= 0 && probe < total;
         probe += (forward ? 1 : -1)) {
        if ([[self lineText:probe] hasPrefix:@"\tLine "]) {
            [sci message:SCI_GOTOLINE wParam:(uptr_t)probe lParam:0];
            [self refreshChrome];
            return YES;
        }
    }
    NSBeep();
    return NO;
}

#pragma mark - Select and find / volatile find

- (BOOL)findNextOccurrenceOfSelection:(BOOL)forward extendSelection:(BOOL)extend {
    ScintillaView *sci = self.sci;
    NSString *term = [self selectedText];
    if (!term.length) { NSBeep(); return NO; }

    NSArray *hits = [self occurrencesOf:term];
    if (!hits.count) { NSBeep(); return NO; }
    long caret = [sci message:SCI_GETSELECTIONSTART];
    long len = Utf8Len(term);

    long target = forward ? [hits.firstObject longValue] : [hits.lastObject longValue];
    if (forward) {
        for (NSNumber *h in hits) if (h.longValue > caret) { target = h.longValue; break; }
    } else {
        for (NSNumber *h in hits.reverseObjectEnumerator) if (h.longValue < caret) { target = h.longValue; break; }
    }

    if (extend) {
        [sci message:SCI_ADDSELECTION wParam:(uptr_t)target lParam:target + len];
    } else {
        [sci message:SCI_SETSEL wParam:(uptr_t)target lParam:target + len];
    }
    [sci message:SCI_SCROLLCARET];
    [self refreshChrome];
    return YES;
}

- (NSUInteger)markCharactersInRangeFrom:(unichar)from to:(unichar)to {
    ScintillaView *sci = self.sci;
    int ind = IndicatorFor(NPPMAC_STYLE_COUNT);
    [self ensureIndicatorConfigured:ind];
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];

    NSString *text = [sci string] ?: @"";
    NSUInteger marked = 0;
    long bytePos = 0;
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        long charBytes = Utf8Len([text substringWithRange:NSMakeRange(i, 1)]);
        if (c >= from && c <= to) {
            [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)bytePos lParam:charBytes];
            marked++;
        }
        bytePos += charBytes;
    }
    return marked;
}

#pragma mark - Change history

- (void)enableChangeHistory:(BOOL)on {
    [self.sci message:SCI_SETCHANGEHISTORY
               wParam:(uptr_t)(on ? (SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS) : SC_CHANGE_HISTORY_DISABLED)
               lParam:0];
}

- (BOOL)goToNextChange:(BOOL)forward {
    ScintillaView *sci = self.sci;
    long mask = (1 << SC_MARKNUM_HISTORY_MODIFIED) |
                (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) |
                (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED);
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long total = [sci message:SCI_GETLINECOUNT];

    // Change-history markers are derived per line rather than stored in the
    // marker list, so SCI_MARKERNEXT does not see them -- scan with MARKERGET.
    for (long probe = line + (forward ? 1 : -1); probe >= 0 && probe < total;
         probe += (forward ? 1 : -1)) {
        if ([sci message:SCI_MARKERGET wParam:(uptr_t)probe] & mask) {
            [sci message:SCI_GOTOLINE wParam:(uptr_t)probe lParam:0];
            [self refreshChrome];
            return YES;
        }
    }
    NSBeep();
    return NO;
}

- (void)clearChangeHistory {
    // Toggling the feature off and on is how Scintilla discards the recorded history.
    [self enableChangeHistory:NO];
    [self enableChangeHistory:YES];
    [self refreshChrome];
}

@end

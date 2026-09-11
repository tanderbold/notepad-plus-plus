#import "EditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"

#pragma mark - Byte/character bridging

// Scintilla positions are UTF-8 byte offsets; NSString indices are UTF-16.
// Everything below converts through NSData so the two never get mixed up.

static long Utf8Length(NSString *s) {
    return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

static NSString *StringFromBytes(NSData *data, long start, long end) {
    if (start < 0) start = 0;
    if (end > (long)data.length) end = (long)data.length;
    if (end <= start) return @"";
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)start,
                                                                            (NSUInteger)(end - start))]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

/// Splits text into lines, each keeping its own line ending, so rebuilding the
/// document preserves mixed endings exactly.
static NSArray<NSString *> *SplitKeepingEndings(NSString *text) {
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger i = 0, n = text.length, lineStart = 0;
    while (i < n) {
        unichar c = [text characterAtIndex:i];
        if (c == '\r' || c == '\n') {
            NSUInteger end = i + 1;
            if (c == '\r' && end < n && [text characterAtIndex:end] == '\n') end++;
            [out addObject:[text substringWithRange:NSMakeRange(lineStart, end - lineStart)]];
            lineStart = end;
            i = end;
        } else {
            i++;
        }
    }
    if (lineStart < n) [out addObject:[text substringFromIndex:lineStart]];
    return out;
}

static NSString *LineBody(NSString *line) {
    NSUInteger n = line.length;
    while (n > 0) {
        unichar c = [line characterAtIndex:n - 1];
        if (c != '\r' && c != '\n') break;
        n--;
    }
    return [line substringToIndex:n];
}

static NSString *LineEnding(NSString *line) {
    return [line substringFromIndex:LineBody(line).length];
}

@implementation EditorController (EditCommands)

#pragma mark - Shared plumbing

- (NSString *)documentText { return [self.sci string] ?: @""; }

/// Replaces the whole document in one undo step, restoring the caret line.
- (void)replaceDocumentText:(NSString *)text keepingLine:(long)line {
    ScintillaView *sci = self.sci;
    [sci message:SCI_BEGINUNDOACTION];
    [sci setString:text];
    [sci message:SCI_ENDUNDOACTION];
    long last = [sci message:SCI_GETLINECOUNT] - 1;
    [sci message:SCI_GOTOLINE wParam:(uptr_t)MAX(0, MIN(line, last)) lParam:0];
    [self refreshChrome];
}

/// Inclusive line range covered by the selection, or the caret's line.
- (void)selectedFirstLine:(long *)first lastLine:(long *)last {
    ScintillaView *sci = self.sci;
    long selStart = [sci message:SCI_GETSELECTIONSTART];
    long selEnd   = [sci message:SCI_GETSELECTIONEND];
    *first = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    *last  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    if (*last > *first && selEnd == [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)*last]) (*last)--;
}

/// Rewrites the selected lines (or every line when nothing is selected).
- (void)transformSelectedLines:(NSArray<NSString *> *(^)(NSArray<NSString *> *bodies))transform {
    ScintillaView *sci = self.sci;
    BOOL hasSelection = [sci message:SCI_GETSELECTIONSTART] != [sci message:SCI_GETSELECTIONEND];
    NSArray *lines = SplitKeepingEndings(self.documentText);
    if (!lines.count) return;

    long first = 0, last = (long)lines.count - 1;
    if (hasSelection) [self selectedFirstLine:&first lastLine:&last];
    first = MAX(0, MIN(first, (long)lines.count - 1));
    last  = MAX(first, MIN(last, (long)lines.count - 1));

    NSMutableArray *bodies = [NSMutableArray array];
    NSMutableArray *endings = [NSMutableArray array];
    for (long i = first; i <= last; ++i) {
        [bodies addObject:LineBody(lines[(NSUInteger)i])];
        [endings addObject:LineEnding(lines[(NSUInteger)i])];
    }

    NSArray *newBodies = transform(bodies);

    NSMutableArray *rebuilt = [NSMutableArray arrayWithArray:[lines subarrayWithRange:NSMakeRange(0, (NSUInteger)first)]];
    // Reuse the original endings positionally; the final line keeps whatever it had.
    NSString *fallback = endings.count ? endings.lastObject : @"";
    if (!fallback.length) {
        fallback = [self.currentDocument.eolMode == SC_EOL_CRLF ? @"\r\n"
                  : self.currentDocument.eolMode == SC_EOL_CR   ? @"\r" : @"\n" copy];
    }
    for (NSUInteger i = 0; i < newBodies.count; ++i) {
        NSString *ending = i < endings.count ? endings[i] : fallback;
        BOOL isDocumentTail = (first + (long)i == (long)lines.count - 1) && i == newBodies.count - 1;
        if (isDocumentTail && i < endings.count) ending = endings[i];
        else if (!ending.length && !(isDocumentTail)) ending = fallback;
        [rebuilt addObject:[newBodies[i] stringByAppendingString:ending]];
    }
    if (last + 1 < (long)lines.count) {
        [rebuilt addObjectsFromArray:[lines subarrayWithRange:
            NSMakeRange((NSUInteger)(last + 1), lines.count - (NSUInteger)(last + 1))]];
    }

    [self replaceDocumentText:[rebuilt componentsJoinedByString:@""] keepingLine:first];
}

/// Rewrites the selected characters, or the whole document when nothing is selected.
- (void)transformSelectedText:(NSString *(^)(NSString *selected))transform {
    ScintillaView *sci = self.sci;
    long selStart = [sci message:SCI_GETSELECTIONSTART];
    long selEnd   = [sci message:SCI_GETSELECTIONEND];
    NSString *whole = self.documentText;

    if (selStart == selEnd) {
        long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        [self replaceDocumentText:transform(whole) keepingLine:line];
        return;
    }

    NSData *data = [whole dataUsingEncoding:NSUTF8StringEncoding];
    NSString *prefix = StringFromBytes(data, 0, selStart);
    NSString *middle = StringFromBytes(data, selStart, selEnd);
    NSString *suffix = StringFromBytes(data, selEnd, (long)data.length);
    NSString *replaced = transform(middle);

    [sci message:SCI_BEGINUNDOACTION];
    [sci setString:[NSString stringWithFormat:@"%@%@%@", prefix, replaced, suffix]];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_SETSEL wParam:(uptr_t)selStart lParam:selStart + Utf8Length(replaced)];
    [self refreshChrome];
}

#pragma mark - Convert Case

static NSString *ApplyCase(NSString *s, NppCaseMode mode) {
    switch (mode) {
        case NppCaseUpper: return s.uppercaseString;
        case NppCaseLower: return s.lowercaseString;

        case NppCaseProperForce:
            return s.lowercaseString.capitalizedString;
        case NppCaseProperBlend: {
            // Capitalise word starts, leave the rest of each word as the user typed it.
            NSMutableString *out = [s mutableCopy];
            BOOL atStart = YES;
            for (NSUInteger i = 0; i < out.length; ++i) {
                unichar c = [out characterAtIndex:i];
                BOOL isWord = [[NSCharacterSet letterCharacterSet] characterIsMember:c];
                if (isWord && atStart) {
                    [out replaceCharactersInRange:NSMakeRange(i, 1)
                                       withString:[[NSString stringWithCharacters:&c length:1] uppercaseString]];
                }
                atStart = !isWord;
            }
            return out;
        }

        case NppCaseSentenceForce:
        case NppCaseSentenceBlend: {
            BOOL force = (mode == NppCaseSentenceForce);
            NSMutableString *out = [(force ? s.lowercaseString : s) mutableCopy];
            BOOL newSentence = YES;
            for (NSUInteger i = 0; i < out.length; ++i) {
                unichar c = [out characterAtIndex:i];
                if (newSentence && [[NSCharacterSet letterCharacterSet] characterIsMember:c]) {
                    [out replaceCharactersInRange:NSMakeRange(i, 1)
                                       withString:[[NSString stringWithCharacters:&c length:1] uppercaseString]];
                    newSentence = NO;
                } else if (c == '.' || c == '!' || c == '?' || c == '\n' || c == '\r') {
                    newSentence = YES;
                }
            }
            return out;
        }

        case NppCaseInvert: {
            NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
            for (NSUInteger i = 0; i < s.length; ++i) {
                NSString *ch = [s substringWithRange:NSMakeRange(i, 1)];
                NSString *up = ch.uppercaseString;
                [out appendString:[ch isEqualToString:up] ? ch.lowercaseString : up];
            }
            return out;
        }

        case NppCaseRandom: {
            NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
            for (NSUInteger i = 0; i < s.length; ++i) {
                NSString *ch = [s substringWithRange:NSMakeRange(i, 1)];
                [out appendString:(arc4random_uniform(2) ? ch.uppercaseString : ch.lowercaseString)];
            }
            return out;
        }
    }
    return s;
}

- (void)convertCase:(NppCaseMode)mode {
    [self transformSelectedText:^NSString *(NSString *sel) { return ApplyCase(sel, mode); }];
}

#pragma mark - Sorting

static NSComparisonResult CompareNumeric(NSString *a, NSString *b, NSString *decimalSeparator) {
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    if (decimalSeparator) { f.decimalSeparator = decimalSeparator; f.usesGroupingSeparator = NO; }
    NSNumber *na = [f numberFromString:[a stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]]];
    NSNumber *nb = [f numberFromString:[b stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]]];
    // Lines that are not numbers sort before the ones that are, as in Notepad++.
    if (!na && !nb) return NSOrderedSame;
    if (!na) return NSOrderedAscending;
    if (!nb) return NSOrderedDescending;
    return [na compare:nb];
}

- (void)sortLines:(NppSortKey)key descending:(BOOL)descending {
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        if (key == NppSortReverseOrder) {
            return bodies.reverseObjectEnumerator.allObjects;
        }
        if (key == NppSortRandom) {
            NSMutableArray *shuffled = [bodies mutableCopy];
            for (NSUInteger i = shuffled.count; i > 1; --i) {
                [shuffled exchangeObjectAtIndex:i - 1
                              withObjectAtIndex:arc4random_uniform((uint32_t)i)];
            }
            return shuffled;
        }

        NSArray *sorted = [bodies sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            switch (key) {
                case NppSortLexicographic:                return [a compare:b];
                case NppSortLexicographicCaseInsensitive: return [a caseInsensitiveCompare:b];
                case NppSortLocale:                       return [a localizedStandardCompare:b];
                case NppSortInteger:                      return CompareNumeric(a, b, nil);
                case NppSortDecimalComma:                 return CompareNumeric(a, b, @",");
                case NppSortDecimalDot:                   return CompareNumeric(a, b, @".");
                case NppSortLength:
                    if (a.length != b.length) return a.length < b.length ? NSOrderedAscending : NSOrderedDescending;
                    return NSOrderedSame;
                default: return NSOrderedSame;
            }
        }];
        return descending ? sorted.reverseObjectEnumerator.allObjects : sorted;
    }];
}

#pragma mark - Line operations

- (void)removeDuplicateLines:(BOOL)consecutiveOnly {
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSString *line in bodies) {
            if (consecutiveOnly) {
                if (out.count && [out.lastObject isEqualToString:line]) continue;
            } else {
                if ([seen containsObject:line]) continue;
                [seen addObject:line];
            }
            [out addObject:line];
        }
        return out;
    }];
}

- (void)splitLines {
    // Notepad++ splits at the wrap width; without wrapping we split on spaces
    // so a long line becomes one word-run per line at the current edge column.
    long edge = [self.sci message:SCI_GETEDGECOLUMN];
    if (edge <= 0) edge = 80;
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *line in bodies) {
            if ((long)line.length <= edge) { [out addObject:line]; continue; }
            NSMutableString *current = [NSMutableString string];
            for (NSString *word in [line componentsSeparatedByString:@" "]) {
                if (current.length && (long)(current.length + 1 + word.length) > edge) {
                    [out addObject:[current copy]];
                    [current setString:word];
                } else {
                    if (current.length) [current appendString:@" "];
                    [current appendString:word];
                }
            }
            if (current.length) [out addObject:[current copy]];
        }
        return out;
    }];
}

- (void)joinLines {
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        return @[[bodies componentsJoinedByString:@" "]];
    }];
}

- (void)moveLine:(BOOL)up {
    [self.sci message:(up ? SCI_MOVESELECTEDLINESUP : SCI_MOVESELECTEDLINESDOWN)];
    [self refreshChrome];
}

- (void)removeEmptyLines:(BOOL)alsoBlankOnly {
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *line in bodies) {
            NSString *probe = alsoBlankOnly
                ? [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                : line;
            if (!probe.length) continue;
            [out addObject:line];
        }
        return out;
    }];
}

- (void)insertBlankLine:(BOOL)above {
    ScintillaView *sci = self.sci;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long pos = above ? [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line]
                     : [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
    NSString *eol = self.currentDocument.eolMode == SC_EOL_CRLF ? @"\r\n"
                  : self.currentDocument.eolMode == SC_EOL_CR   ? @"\r" : @"\n";
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:eol];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOLINE wParam:(uptr_t)(above ? line : line + 1) lParam:0];
    [self refreshChrome];
}

#pragma mark - Blank operations

- (void)applyTrim:(NppTrimMode)mode {
    long tabWidth = [self.sci message:SCI_GETTABWIDTH];
    if (tabWidth <= 0) tabWidth = 4;

    if (mode == NppTrimEOLToSpace || mode == NppTrimAll) {
        [self transformSelectedLines:^NSArray *(NSArray *bodies) {
            NSMutableArray *trimmed = [NSMutableArray array];
            for (NSString *line in bodies) {
                [trimmed addObject:(mode == NppTrimAll
                    ? [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                    : line)];
            }
            return @[[trimmed componentsJoinedByString:@" "]];
        }];
        return;
    }

    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
        NSString *spaces = [@"" stringByPaddingToLength:(NSUInteger)tabWidth withString:@" " startingAtIndex:0];
        for (NSString *line in bodies) {
            NSString *r = line;
            switch (mode) {
                case NppTrimTrailing: {
                    NSUInteger n = r.length;
                    while (n > 0 && [ws characterIsMember:[r characterAtIndex:n - 1]]) n--;
                    r = [r substringToIndex:n];
                    break;
                }
                case NppTrimLeading: {
                    NSUInteger i = 0;
                    while (i < r.length && [ws characterIsMember:[r characterAtIndex:i]]) i++;
                    r = [r substringFromIndex:i];
                    break;
                }
                case NppTrimBoth:
                    r = [r stringByTrimmingCharactersInSet:ws];
                    break;
                case NppTabToSpace:
                    r = [r stringByReplacingOccurrencesOfString:@"\t" withString:spaces];
                    break;
                case NppSpaceToTabAll:
                    r = [r stringByReplacingOccurrencesOfString:spaces withString:@"\t"];
                    break;
                case NppSpaceToTabLeading: {
                    NSUInteger i = 0;
                    while (i < r.length && [ws characterIsMember:[r characterAtIndex:i]]) i++;
                    NSString *indent = [[r substringToIndex:i]
                        stringByReplacingOccurrencesOfString:spaces withString:@"\t"];
                    r = [indent stringByAppendingString:[r substringFromIndex:i]];
                    break;
                }
                default: break;
            }
            [out addObject:r];
        }
        return out;
    }];
}

#pragma mark - Indent, delete

/// Notepad++'s Increase/Decrease Line Indent shifts whole lines. SCI_TAB would
/// instead replace a within-line selection with a tab character.
- (void)changeIndent:(BOOL)increase {
    ScintillaView *sci = self.sci;
    long first = 0, last = 0;
    [self selectedFirstLine:&first lastLine:&last];
    long width = [sci message:SCI_GETINDENT];
    if (width <= 0) width = [sci message:SCI_GETTABWIDTH];
    if (width <= 0) width = 4;

    [sci message:SCI_BEGINUNDOACTION];
    for (long line = first; line <= last; ++line) {
        long indent = [sci message:SCI_GETLINEINDENTATION wParam:(uptr_t)line];
        long target = increase ? indent + width : MAX(0, indent - width);
        [sci message:SCI_SETLINEINDENTATION wParam:(uptr_t)line lParam:target];
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
}

- (void)deleteSelection {
    [self.sci message:SCI_CLEAR];
    [self refreshChrome];
}

#pragma mark - Clipboard

- (void)copyToClipboard:(NSString *)string {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:string ?: @"" forType:NSPasteboardTypeString];
}

- (NSString *)allDocumentNames {
    NSMutableArray *out = [NSMutableArray array];
    for (NppDocument *d in self.documents) [out addObject:d.displayName ?: @""];
    return [out componentsJoinedByString:@"\n"];
}

- (NSString *)allDocumentPaths {
    NSMutableArray *out = [NSMutableArray array];
    for (NppDocument *d in self.documents) if (d.path) [out addObject:d.path];
    return [out componentsJoinedByString:@"\n"];
}

#pragma mark - Insert

- (void)insertDateTimeShort:(BOOL)shortForm {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterShortStyle;
    f.timeStyle = shortForm ? NSDateFormatterShortStyle : NSDateFormatterLongStyle;
    if (!shortForm) f.dateStyle = NSDateFormatterLongStyle;
    [self insertAtCaret:[f stringFromDate:[NSDate date]]];
}

- (void)insertCustomDateTime:(NSString *)format {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = format.length ? format : @"yyyy-MM-dd HH:mm:ss";
    [self insertAtCaret:[f stringFromDate:[NSDate date]]];
}

- (void)insertAtCaret:(NSString *)text {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:text];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS wParam:(uptr_t)(pos + Utf8Length(text)) lParam:0];
    [self refreshChrome];
}

#pragma mark - Comments

- (void)uncommentLines {
    NSString *token = self.currentDocument.language.commentLine;
    if (!token.length) { NSBeep(); return; }
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *line in bodies) {
            NSUInteger i = 0;
            while (i < line.length &&
                   [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:i]]) i++;
            NSString *indent = [line substringToIndex:i];
            NSString *rest = [line substringFromIndex:i];
            if ([rest hasPrefix:token]) {
                rest = [rest substringFromIndex:token.length];
                if ([rest hasPrefix:@" "]) rest = [rest substringFromIndex:1];
            }
            [out addObject:[indent stringByAppendingString:rest]];
        }
        return out;
    }];
}

- (void)streamComment:(BOOL)comment {
    NSString *open = self.currentDocument.language.commentStart;
    NSString *close = self.currentDocument.language.commentEnd;
    if (!open.length || !close.length) { NSBeep(); return; }

    if (comment) { [self toggleBlockComment]; return; }

    [self transformSelectedText:^NSString *(NSString *sel) {
        NSString *r = sel;
        if ([r hasPrefix:open]) r = [r substringFromIndex:open.length];
        if ([r hasSuffix:close]) r = [r substringToIndex:r.length - close.length];
        return r;
    }];
}

#pragma mark - Read-only

- (void)setReadOnly:(BOOL)readOnly {
    [self.sci message:SCI_SETREADONLY wParam:(uptr_t)(readOnly ? 1 : 0) lParam:0];
    [self refreshChrome];
}

- (BOOL)isReadOnly { return [self.sci message:SCI_GETREADONLY] != 0; }

- (void)setReadOnlyForAllDocuments:(BOOL)readOnly {
    NSInteger restore = [self.documents indexOfObject:self.currentDocument];
    for (NSInteger i = 0; i < (NSInteger)self.documents.count; ++i) {
        [self selectDocumentAtIndex:i];
        [self setReadOnly:readOnly];
    }
    if (restore != NSNotFound) [self selectDocumentAtIndex:restore];
}

@end

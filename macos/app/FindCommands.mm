#import "FindCommands.h"
#import "SearchCommands.h"
#import "NppRegex.h"
#import "ScintillaView.h"

@implementation NppFindSpec

+ (instancetype)specFor:(NSString *)what mode:(NppSearchMode)mode options:(NppFindOptions)options {
    NppFindSpec *spec = [[NppFindSpec alloc] init];
    spec.what = what;
    spec.mode = mode;
    spec.options = options;
    return spec;
}


@end

@implementation EditorController (FindCommands)

#pragma mark - Extended escapes

+ (NSString *)convertExtendedToString:(NSString *)query {
    if (!query.length) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:query.length];

    NSUInteger i = 0, length = query.length;
    while (i < length) {
        unichar c = [query characterAtIndex:i];
        if (c != '\\' || i + 1 >= length) {
            [out appendFormat:@"%C", c];
            ++i;
            continue;
        }

        unichar escape = [query characterAtIndex:i + 1];
        unichar simple = 0;
        switch (escape) {
            case 'r':  simple = '\r'; break;
            case 'n':  simple = '\n'; break;
            case 't':  simple = '\t'; break;
            case '0':  simple = 0;    break;
            case '\\': simple = '\\'; break;
            default:   simple = 0xFFFF; break;
        }
        if (simple != 0xFFFF) {
            [out appendFormat:@"%C", simple];
            i += 2;
            continue;
        }

        // The numeric forms, each with the digit count upstream fixes for it.
        NSInteger digits = 0, base = 0;
        switch (escape) {
            case 'b': digits = 8; base = 2;  break;
            case 'o': digits = 3; base = 8;  break;
            case 'd': digits = 3; base = 10; break;
            case 'x': digits = 2; base = 16; break;
            case 'u': digits = 4; base = 16; break;
            default: break;
        }
        BOOL converted = NO;
        if (digits && i + 2 + digits <= length) {
            NSString *text = [query substringWithRange:NSMakeRange(i + 2, digits)];
            NSInteger value = 0;
            BOOL valid = YES;
            for (NSUInteger d = 0; d < text.length; ++d) {
                unichar ch = [text characterAtIndex:d];
                NSInteger digit = -1;
                if (ch >= '0' && ch <= '9') digit = ch - '0';
                else if (ch >= 'a' && ch <= 'f') digit = ch - 'a' + 10;
                else if (ch >= 'A' && ch <= 'F') digit = ch - 'A' + 10;
                if (digit < 0 || digit >= base) { valid = NO; break; }
                value = value * base + digit;
            }
            if (valid) {
                [out appendFormat:@"%C", (unichar)value];
                i += 2 + digits;
                converted = YES;
            }
        }
        if (converted) continue;

        // Not a sequence after all: upstream keeps the backslash and the letter.
        [out appendFormat:@"\\%C", escape];
        i += 2;
    }
    return out;
}

#pragma mark - Pattern

/// Turns the spec into one PCRE pattern, so normal, extended and regular
/// expression searching all go down the same path.
- (nullable NppRegex *)regexFor:(NppFindSpec *)spec {
    if (!spec.what.length) return nil;

    NSString *body;
    if (spec.mode == NppSearchRegex) {
        body = spec.what;
    } else {
        NSString *literal = spec.mode == NppSearchExtended
            ? [EditorController convertExtendedToString:spec.what]
            : spec.what;
        // \Q...\E would be simpler but cannot carry a \E in the text, so every
        // character that means something to the engine is escaped instead.
        NSMutableString *quoted = [NSMutableString stringWithCapacity:literal.length * 2];
        NSCharacterSet *meta = [NSCharacterSet characterSetWithCharactersInString:
                                @"\\^$.|?*+()[]{}"];
        for (NSUInteger i = 0; i < literal.length; ++i) {
            unichar c = [literal characterAtIndex:i];
            if ([meta characterIsMember:c]) [quoted appendString:@"\\"];
            [quoted appendFormat:@"%C", c];
        }
        body = quoted;
    }

    if (spec.options & NppFindWholeWord) {
        body = [NSString stringWithFormat:@"\\b(?:%@)\\b", body];
    }
    if (!(spec.options & NppFindMatchCase)) {
        body = [@"(?i)" stringByAppendingString:body];
    }
    return [NppRegex regexWithPattern:body];
}

/// The part of the document a search may look at.
- (NSRange)searchRangeFor:(NppFindSpec *)spec inData:(NSData *)data {
    if (!(spec.options & NppFindInSelection)) return NSMakeRange(0, data.length);
    long from = [self.sci message:SCI_GETSELECTIONSTART];
    long to = [self.sci message:SCI_GETSELECTIONEND];
    if (to <= from) return NSMakeRange(0, data.length);
    return NSMakeRange((NSUInteger)from, (NSUInteger)(to - from));
}

- (NSData *)documentBytes {
    return [([self.sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
}

#pragma mark - Matches

- (NSArray<NSValue *> *)rangesOfMatches:(NppFindSpec *)spec {
    NppRegex *regex = [self regexFor:spec];
    if (!regex) return @[];
    NSData *data = [self documentBytes];
    NSMutableArray *out = [NSMutableArray array];
    [regex enumerateMatchesInData:data range:[self searchRangeFor:spec inData:data]
                       usingBlock:^(NSRange m, BOOL *stop) {
        [out addObject:[NSValue valueWithRange:m]];
    }];
    return out;
}

- (NSUInteger)countMatches:(NppFindSpec *)spec {
    return [self rangesOfMatches:spec].count;
}

- (BOOL)findNext:(NppFindSpec *)spec {
    NSArray<NSValue *> *matches = [self rangesOfMatches:spec];
    if (!matches.count) return NO;

    ScintillaView *sci = self.sci;
    BOOL backward = (spec.options & NppFindBackward) != 0;
    NSUInteger caret = backward
        ? (NSUInteger)[sci message:SCI_GETSELECTIONSTART]
        : (NSUInteger)[sci message:SCI_GETCURRENTPOS];

    NSValue *chosen = nil;
    if (backward) {
        for (NSValue *v in matches) {
            if (NSMaxRange(v.rangeValue) <= caret) chosen = v;
        }
        if (!chosen && (spec.options & NppFindWrap)) chosen = matches.lastObject;
    } else {
        for (NSValue *v in matches) {
            if (v.rangeValue.location >= caret) { chosen = v; break; }
        }
        if (!chosen && (spec.options & NppFindWrap)) chosen = matches.firstObject;
    }
    if (!chosen) return NO;

    NSRange found = chosen.rangeValue;
    [sci message:SCI_SETSEL wParam:(uptr_t)found.location lParam:(sptr_t)NSMaxRange(found)];
    return YES;
}

- (NSUInteger)markAll:(NppFindSpec *)spec {
    NSArray<NSValue *> *matches = [self rangesOfMatches:spec];
    ScintillaView *sci = self.sci;
    [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_FIND_MARK_INDICATOR];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0
           lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
    for (NSValue *v in matches) {
        NSRange r = v.rangeValue;
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)r.location lParam:(sptr_t)r.length];
    }
    return matches.count;
}

#pragma mark - Replacing

/// Builds the replacement for one match: \1..\9 and $1..$9 name the groups when
/// the search was a regular expression; otherwise the text is taken as it is,
/// after Extended mode has had its say.
- (NSString *)replacementFor:(NppFindSpec *)spec
                      groups:(NSArray<NSValue *> *)groups
                        data:(NSData *)data {
    NSString *template_ = spec.replacement ?: @"";
    if (spec.mode == NppSearchExtended) {
        template_ = [EditorController convertExtendedToString:template_];
    }
    if (spec.mode != NppSearchRegex) return template_;

    // \U and \L change the case of everything up to \E; \u and \l change one
    // character. They are what makes a replacement able to normalise what it
    // captured, and Notepad++ has them because Boost does.
    typedef NS_ENUM(NSInteger, NppCaseRun) { NppCaseAsIs, NppCaseUpperRun, NppCaseLowerRun };
    __block NppCaseRun run = NppCaseAsIs;
    __block NSInteger single = 0;      // +1 next character upper, -1 next lower

    NSMutableString *out = [NSMutableString stringWithCapacity:template_.length];
    void (^append)(NSString *) = ^(NSString *piece) {
        if (!piece.length) return;
        NSMutableString *text = [piece mutableCopy];
        if (single != 0) {
            NSString *first = [text substringToIndex:1];
            [text replaceCharactersInRange:NSMakeRange(0, 1)
                                withString:single > 0 ? first.uppercaseString : first.lowercaseString];
            single = 0;
            if (run == NppCaseUpperRun) {
                NSString *rest = [text substringFromIndex:1].uppercaseString;
                text = [[[text substringToIndex:1] stringByAppendingString:rest] mutableCopy];
            } else if (run == NppCaseLowerRun) {
                NSString *rest = [text substringFromIndex:1].lowercaseString;
                text = [[[text substringToIndex:1] stringByAppendingString:rest] mutableCopy];
            }
        } else if (run == NppCaseUpperRun) {
            text = [text.uppercaseString mutableCopy];
        } else if (run == NppCaseLowerRun) {
            text = [text.lowercaseString mutableCopy];
        }
        [out appendString:text];
    };

    for (NSUInteger i = 0; i < template_.length; ++i) {
        unichar c = [template_ characterAtIndex:i];
        BOOL hasNext = i + 1 < template_.length;
        unichar next = hasNext ? [template_ characterAtIndex:i + 1] : 0;

        if ((c == '\\' || c == '$') && next >= '0' && next <= '9') {
            NSUInteger index = next - '0';
            if (index < groups.count) {
                NSRange r = groups[index].rangeValue;
                if (r.location != NSNotFound) {
                    append([[NSString alloc] initWithData:[data subdataWithRange:r]
                                                 encoding:NSUTF8StringEncoding] ?: @"");
                }
            }
            i++;
            continue;
        }
        if (c == '\\' && hasNext) {
            switch (next) {
                case 'U': run = NppCaseUpperRun; i++; continue;
                case 'L': run = NppCaseLowerRun; i++; continue;
                case 'E': run = NppCaseAsIs;     i++; continue;
                case 'u': single = 1;            i++; continue;
                case 'l': single = -1;           i++; continue;
                case 'n': append(@"\n");         i++; continue;
                case 'r': append(@"\r");         i++; continue;
                case 't': append(@"\t");         i++; continue;
                case '\\': append(@"\\");        i++; continue;
                default: break;
            }
        }
        append([NSString stringWithCharacters:&c length:1]);
    }
    return out;
}

- (NSUInteger)replaceAll:(NppFindSpec *)spec {
    NppRegex *regex = [self regexFor:spec];
    if (!regex) return 0;

    NSData *data = [self documentBytes];
    NSRange scope = [self searchRangeFor:spec inData:data];

    // Collected first and applied from the end, so replacing does not move the
    // matches still to be replaced.
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    [regex enumerateMatchesWithGroupsInData:data range:scope
                                 usingBlock:^(NSArray<NSValue *> *groups, BOOL *stop) {
        [ranges addObject:groups.firstObject];
        [texts addObject:[self replacementFor:spec groups:groups data:data]];
    }];
    if (!ranges.count) return 0;

    ScintillaView *sci = self.sci;
    [sci message:SCI_BEGINUNDOACTION];
    for (NSInteger i = (NSInteger)ranges.count - 1; i >= 0; --i) {
        NSRange r = ranges[(NSUInteger)i].rangeValue;
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)r.location];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)NSMaxRange(r)];
        [sci setStringProperty:SCI_REPLACETARGET parameter:-1 value:texts[(NSUInteger)i]];
    }
    [sci message:SCI_ENDUNDOACTION];
    return ranges.count;
}

- (BOOL)replaceCurrentThenFindNext:(NppFindSpec *)spec {
    ScintillaView *sci = self.sci;
    long from = [sci message:SCI_GETSELECTIONSTART];
    long to = [sci message:SCI_GETSELECTIONEND];

    if (to > from) {
        // Replace only if what is selected is itself a match, so pressing
        // Replace on an arbitrary selection cannot damage it.
        NppRegex *regex = [self regexFor:spec];
        NSData *data = [self documentBytes];
        __block BOOL exact = NO;
        __block NSArray<NSValue *> *matched = nil;
        [regex enumerateMatchesWithGroupsInData:data
                                          range:NSMakeRange((NSUInteger)from, (NSUInteger)(to - from))
                                     usingBlock:^(NSArray<NSValue *> *groups, BOOL *stop) {
            NSRange r = groups.firstObject.rangeValue;
            if (r.location == (NSUInteger)from && NSMaxRange(r) == (NSUInteger)to) {
                exact = YES;
                matched = groups;
                *stop = YES;
            }
        }];
        if (exact) {
            NSString *text = [self replacementFor:spec groups:matched data:data];
            [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from];
            [sci message:SCI_SETTARGETEND wParam:(uptr_t)to];
            [sci setStringProperty:SCI_REPLACETARGET parameter:-1 value:text];
            [sci message:SCI_GOTOPOS wParam:(uptr_t)(from + (long)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding])];
        }
    }
    return [self findNext:spec];
}



#pragma mark - Across files

+ (BOOL)name:(NSString *)name matchesFilters:(NSString *)filters {
    NSString *trimmed = [(filters ?: @"") stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return YES;                 // no filter means every file

    for (NSString *pattern in [trimmed componentsSeparatedByCharactersInSet:
                               [NSCharacterSet characterSetWithCharactersInString:@" ,;"]]) {
        if (!pattern.length) continue;
        // Notepad++ takes shell patterns here, and so does this.
        NSPredicate *glob = [NSPredicate predicateWithFormat:@"SELF LIKE[c] %@", pattern];
        if ([glob evaluateWithObject:name]) return YES;
    }
    return NO;
}

/// Walks the folder, handing each file that passes the filter to `visit`.
- (void)walkFolder:(NSString *)folder
           filters:(NSString *)filters
         recursive:(BOOL)recursive
     includeHidden:(BOOL)includeHidden
             visit:(void (^)(NSString *path, NSString *contents))visit {
    NSFileManager *files = [NSFileManager defaultManager];
    NSDirectoryEnumerator *walker = [files enumeratorAtPath:folder];
    for (NSString *relative in walker) {
        if (!recursive && relative.pathComponents.count > 1) continue;

        BOOL hidden = NO;
        for (NSString *component in relative.pathComponents) {
            if ([component hasPrefix:@"."]) { hidden = YES; break; }
        }
        if (hidden && !includeHidden) continue;

        NSString *full = [folder stringByAppendingPathComponent:relative];
        BOOL isDirectory = NO;
        if (![files fileExistsAtPath:full isDirectory:&isDirectory] || isDirectory) continue;
        if (![EditorController name:relative.lastPathComponent matchesFilters:filters]) continue;

        NSString *contents = [NSString stringWithContentsOfFile:full
                                                       encoding:NSUTF8StringEncoding error:NULL];
        if (!contents) continue;                     // binary, or another encoding
        visit(full, contents);
    }
}

- (NSUInteger)findInFiles:(NppFindSpec *)spec
                   folder:(NSString *)folder
                  filters:(NSString *)filters
                recursive:(BOOL)recursive
            includeHidden:(BOOL)includeHidden
                   report:(NSString **)report {
    if (!spec.what.length || !folder.length) return 0;
    NppRegex *regex = [self regexFor:spec];
    if (!regex) return 0;

    NSMutableString *text = [NSMutableString stringWithFormat:@"Search \"%@\" in %@\n\n",
                             spec.what, folder];
    __block NSUInteger hits = 0, matchedFiles = 0;

    [self walkFolder:folder filters:filters recursive:recursive includeHidden:includeHidden
               visit:^(NSString *path, NSString *contents) {
        NSArray *lines = [contents componentsSeparatedByString:@"\n"];
        NSMutableString *block = [NSMutableString string];
        NSUInteger inFile = 0;
        for (NSUInteger i = 0; i < lines.count; ++i) {
            NSData *line = [lines[i] dataUsingEncoding:NSUTF8StringEncoding];
            if (!line.length) continue;
            if ([regex firstMatchInData:line range:NSMakeRange(0, line.length)].location == NSNotFound) {
                continue;
            }
            inFile++;
            [block appendFormat:@"\tLine %lu: %@\n", (unsigned long)(i + 1), lines[i]];
        }
        if (!inFile) return;
        matchedFiles++;
        hits += inFile;
        [text appendFormat:@"%@ (%lu hit%@)\n%@\n", path, (unsigned long)inFile,
                           inFile == 1 ? @"" : @"s", block];
    }];

    [text appendFormat:@"\n%lu hit%@ in %lu file%@\n", (unsigned long)hits,
                       hits == 1 ? @"" : @"s", (unsigned long)matchedFiles,
                       matchedFiles == 1 ? @"" : @"s"];
    if (report) *report = text;
    return hits;
}

- (NSUInteger)replaceInFiles:(NppFindSpec *)spec
                      folder:(NSString *)folder
                     filters:(NSString *)filters
                   recursive:(BOOL)recursive
               includeHidden:(BOOL)includeHidden
                changedFiles:(NSUInteger *)changedFiles {
    if (!spec.what.length || !folder.length) return 0;
    NppRegex *regex = [self regexFor:spec];
    if (!regex) return 0;

    __block NSUInteger replaced = 0, touched = 0;
    [self walkFolder:folder filters:filters recursive:recursive includeHidden:includeHidden
               visit:^(NSString *path, NSString *contents) {
        NSData *data = [contents dataUsingEncoding:NSUTF8StringEncoding];
        if (!data.length) return;

        NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        [regex enumerateMatchesWithGroupsInData:data range:NSMakeRange(0, data.length)
                                     usingBlock:^(NSArray<NSValue *> *groups, BOOL *stop) {
            [ranges addObject:groups.firstObject];
            [texts addObject:[self replacementFor:spec groups:groups data:data]];
        }];
        if (!ranges.count) return;

        // Applied from the end, so a replacement cannot move the ones still to
        // be made.
        NSMutableData *updated = [data mutableCopy];
        for (NSInteger i = (NSInteger)ranges.count - 1; i >= 0; --i) {
            NSRange range = ranges[(NSUInteger)i].rangeValue;
            NSData *piece = [texts[(NSUInteger)i] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
            [updated replaceBytesInRange:range withBytes:piece.bytes length:piece.length];
        }
        if ([updated writeToFile:path atomically:YES]) {
            replaced += ranges.count;
            touched++;
        }
    }];

    if (changedFiles) *changedFiles = touched;
    return replaced;
}

@end

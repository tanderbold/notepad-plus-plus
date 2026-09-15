#import "TypingCommands.h"
#import "ApiCatalog.h"
#import "SettingsCommands.h"
#import "AdvancedEditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"

static long Utf8Len(NSString *s) {
    return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

@implementation EditorController (TypingCommands)

#pragma mark - Typing

/// The word being typed immediately before the caret.
- (NSString *)prefixBeforeCaret {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long start = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
    if (pos <= start) return @"";
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if ((NSUInteger)pos > data.length) return @"";
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)start,
                                                                            (NSUInteger)(pos - start))]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

- (NSArray<NSString *> *)completionCandidatesForPrefix:(NSString *)prefix {
    NppPreferences *p = [NppPreferences shared];
    if (!prefix.length) return @[];
    if (p.autoCompleteIgnoreNumbers &&
        [prefix rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location == NSNotFound) {
        return @[];                              // a bare number is not worth completing
    }

    NSMutableSet *found = [NSMutableSet set];

    if (p.autoCompleteSource == NppCompletionWords || p.autoCompleteSource == NppCompletionBoth) {
        NSCharacterSet *sep = [[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] invertedSet];
        for (NSString *w in [([self.sci string] ?: @"") componentsSeparatedByCharactersInSet:sep]) {
            if (w.length > prefix.length && [w hasPrefix:prefix]) [found addObject:w];
        }
    }
    if (p.autoCompleteSource == NppCompletionFunctions || p.autoCompleteSource == NppCompletionBoth) {
        // Notepad++'s own list for this language, which is what "function
        // completion" means: the functions the language has, not the words that
        // happen to be in this file.
        NSString *language = self.currentDocument.language.name ?: @"";
        NSArray *fromApi = [[ApiCatalog sharedCatalog] completionsForLanguage:language
                                                                       prefix:prefix];
        [found addObjectsFromArray:fromApi];

        // A language Notepad++ ships no list for still gets its lexer keywords,
        // which is better than nothing.
        if (!fromApi.count) {
            for (NSString *set in self.currentDocument.language.keywordSets.allValues) {
                for (NSString *w in [set componentsSeparatedByString:@" "]) {
                    if (w.length > prefix.length && [w hasPrefix:prefix]) [found addObject:w];
                }
            }
        }
    }

    NSArray *sorted = [found.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (p.autoCompleteBriefList && sorted.count > 12) {
        sorted = [sorted subarrayWithRange:NSMakeRange(0, 12)];
    }
    return sorted;
}

- (NSString *)autoInsertionForCharacter:(int)character {
    NppPreferences *p = [NppPreferences shared];
    switch (character) {
        case '(':  return p.autoInsertParenthesis ? @")" : nil;
        case '[':  return p.autoInsertBracket ? @"]" : nil;
        case '{':  return p.autoInsertBrace ? @"}" : nil;
        case '\'': return p.autoInsertSingleQuote ? @"'" : nil;
        case '"':  return p.autoInsertDoubleQuote ? @"\"" : nil;
        default:   return nil;
    }
}

/// After ">" is typed, the element that was just opened, if any.
- (NSString *)closeTagAtCaret {
    if (![NppPreferences shared].autoInsertCloseTag) return nil;
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    NSString *text = [sci string] ?: @"";
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (pos <= 0 || (NSUInteger)pos > data.length) return nil;

    NSString *before = [[NSString alloc] initWithData:
        [data subdataWithRange:NSMakeRange(0, (NSUInteger)pos)] encoding:NSUTF8StringEncoding];
    if (![before hasSuffix:@">"]) return nil;

    NSRange open = [before rangeOfString:@"<" options:NSBackwardsSearch];
    if (open.location == NSNotFound) return nil;
    NSString *tag = [before substringWithRange:
        NSMakeRange(open.location + 1, before.length - open.location - 2)];
    if (![tag length] || [tag hasPrefix:@"/"] || [tag hasSuffix:@"/"]) return nil;

    // Only the element name, dropping any attributes.
    NSRange space = [tag rangeOfString:@" "];
    if (space.location != NSNotFound) tag = [tag substringToIndex:space.location];
    if (!tag.length) return nil;
    for (NSUInteger i = 0; i < tag.length; ++i) {
        unichar c = [tag characterAtIndex:i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '-' || c == '_' || c == ':';
        if (!ok) return nil;
    }
    return [NSString stringWithFormat:@"</%@>", tag];
}

- (void)handleCharacterAdded:(int)character {
    NppPreferences *p = [NppPreferences shared];
    ScintillaView *sci = self.sci;

    // Auto-insertion first: it does not depend on completion being on.
    NSString *closing = [self autoInsertionForCharacter:character];
    if (!closing && character == '>') closing = [self closeTagAtCaret];
    if (closing.length) {
        long pos = [sci message:SCI_GETCURRENTPOS];
        [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:closing];
        [sci message:SCI_GOTOPOS wParam:(uptr_t)pos lParam:0];   // caret stays inside
    }

    if (character == '(' && p.functionHintOnInput) {
        [self showFunctionCallTip];
        return;
    }
    if (!p.autoCompleteOnInput) return;

    NSString *prefix = [self prefixBeforeCaret];
    if ((NSInteger)prefix.length < MAX(1, p.autoCompleteThreshold)) {
        [sci message:SCI_AUTOCCANCEL];
        return;
    }
    NSArray *candidates = [self completionCandidatesForPrefix:prefix];
    if (!candidates.count) { [sci message:SCI_AUTOCCANCEL]; return; }

    [sci message:SCI_AUTOCSETSEPARATOR wParam:(uptr_t)'\n' lParam:0];
    // Whether Tab or Enter accepts the choice.
    [sci setStringProperty:SCI_AUTOCSETFILLUPS parameter:0
                     value:p.autoCompleteUseTab ? @"\t" : @""];
    [sci setStringProperty:SCI_AUTOCSHOW parameter:(long)prefix.length
                     value:[candidates componentsJoinedByString:@"\n"]];
}

#pragma mark - New documents

- (void)applyNewDocumentDefaults {
    NppPreferences *p = [NppPreferences shared];
    NppDocument *doc = self.currentDocument;
    if (!doc || doc.path) return;               // only untitled documents

    doc.eolMode = (int)p.defaultEOL;
    [self.sci message:SCI_SETEOLMODE wParam:(uptr_t)doc.eolMode lParam:0];

    NSDictionary *encodings = @{@"ANSI": @(NSISOLatin1StringEncoding),
                                @"UTF-8": @(NSUTF8StringEncoding),
                                @"UTF-8-BOM": @(NSUTF8StringEncoding),
                                @"UTF-16 BE BOM": @(NSUTF16BigEndianStringEncoding),
                                @"UTF-16 LE BOM": @(NSUTF16LittleEndianStringEncoding)};
    NSNumber *enc = encodings[p.defaultEncoding ?: @"UTF-8"];
    doc.encoding = enc ? (NSStringEncoding)enc.unsignedIntegerValue : NSUTF8StringEncoding;
    doc.hasBOM = [p.defaultEncoding hasSuffix:@"BOM"];

    if (p.defaultLanguage.length) [self setLanguageNamed:p.defaultLanguage];
}

- (NSString *)untitledNameForDocument:(NppDocument *)doc {
    NppPreferences *p = [NppPreferences shared];
    if (!p.untitledFromFirstLine || doc.path) return doc.displayName;

    NSString *text = [self.sci string] ?: @"";
    NSString *firstLine = [[text componentsSeparatedByCharactersInSet:
        [NSCharacterSet newlineCharacterSet]] firstObject] ?: @"";
    firstLine = [firstLine stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];
    if (!firstLine.length) return doc.displayName;
    return firstLine.length > 32 ? [firstLine substringToIndex:32] : firstLine;
}

#pragma mark - Recent files

- (void)noteRecentFile:(NSString *)path {
    if (!path.length) return;
    NppPreferences *p = [NppPreferences shared];
    NSMutableArray *list = [p.recentFiles mutableCopy] ?: [NSMutableArray array];
    [list removeObject:path];
    [list insertObject:path atIndex:0];
    while ((NSInteger)list.count > MAX(1, p.recentFilesMax)) [list removeLastObject];
    p.recentFiles = list;
}

- (NSArray<NSString *> *)recentFiles { return [NppPreferences shared].recentFiles ?: @[]; }

- (void)clearRecentFiles { [NppPreferences shared].recentFiles = @[]; }

/// 0 shows the file name, 1 the full path, both clipped to the configured length.
- (NSString *)displayNameForRecentFile:(NSString *)path {
    NppPreferences *p = [NppPreferences shared];
    NSString *shown = p.recentFilesShowFullPath ? path : path.lastPathComponent;
    NSInteger limit = p.recentFilesMaxLength;
    if (limit > 3 && (NSInteger)shown.length > limit) {
        // Keep the tail, which is the part that identifies the file.
        shown = [@"…" stringByAppendingString:
                 [shown substringFromIndex:shown.length - (NSUInteger)limit + 1]];
    }
    return shown;
}

#pragma mark - Default directory

- (NSString *)defaultOpenDirectory {
    NppPreferences *p = [NppPreferences shared];
    switch (p.defaultDirectoryMode) {
        case 0: {                                // follow the current document
            NSString *path = self.currentDocument.path;
            if (path.length) return path.stringByDeletingLastPathComponent;
            break;
        }
        case 1:                                  // remember the last used one
            if (p.lastUsedDirectory.length) return p.lastUsedDirectory;
            break;
        default:                                 // a fixed folder
            if (p.fixedDirectory.length) return p.fixedDirectory;
            break;
    }
    return NSHomeDirectory();
}

- (void)rememberOpenDirectory:(NSString *)path {
    if ([NppPreferences shared].defaultDirectoryMode != 1 || !path.length) return;
    [NppPreferences shared].lastUsedDirectory = path.stringByDeletingLastPathComponent;
}

#pragma mark - Searching

- (NSString *)initialFindTerm {
    NppPreferences *p = [NppPreferences shared];
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];

    if (b > a && p.findFillWithSelection) {
        NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
        if ((NSUInteger)b <= data.length) {
            return [[NSString alloc] initWithData:
                [data subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a))]
                                         encoding:NSUTF8StringEncoding] ?: @"";
        }
    }
    if (b == a && p.findSelectWordUnderCaret) {
        long pos = [sci message:SCI_GETCURRENTPOS];
        long start = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        long end = [sci message:SCI_WORDENDPOSITION wParam:(uptr_t)pos lParam:1];
        if (end > start) {
            NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
            if ((NSUInteger)end <= data.length) {
                return [[NSString alloc] initWithData:
                    [data subdataWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]
                                             encoding:NSUTF8StringEncoding] ?: @"";
            }
        }
    }
    return @"";
}

@end

#import "TypingCommands.h"
#import <objc/runtime.h>
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

/// Whether a closer may be put in after `character` was typed at caret-1,
/// as Notepad++ decides it: a bracket only before a blank, the end, or a
/// closer; a quote only between blanks or inside a fresh pair of brackets.
- (BOOL)autoCloseAllowedFor:(int)character {
    ScintillaView *sci = self.sci;
    long caret = [sci message:SCI_GETCURRENTPOS];
    int next = caret < [sci message:SCI_GETLENGTH] ? (int)[sci message:SCI_GETCHARAT wParam:(uptr_t)caret lParam:0] : 0;
    int prev = caret >= 2 ? (int)[sci message:SCI_GETCHARAT wParam:(uptr_t)(caret - 2) lParam:0] : 0;
    BOOL nextBlank = next == 0 || next == ' ' || next == '\t' || next == '\n' || next == '\r';
    BOOL prevBlank = prev == 0 || prev == ' ' || prev == '\t' || prev == '\n' || prev == '\r';
    BOOL nextCloser = next == ')' || next == ']' || next == '}';
    BOOL sandwiched = (prev == '(' && next == ')') || (prev == '[' && next == ']') || (prev == '{' && next == '}');
    if (character == '(' || character == '[' || character == '{') return nextBlank || nextCloser;
    return (prevBlank && nextBlank) || sandwiched;         // a quote
}

static const char kAutoCloseKey = 0;

- (void)forgetAutoCloser {
    objc_setAssociatedObject(self, &kAutoCloseKey, nil, OBJC_ASSOCIATION_RETAIN);
}

/// Typing the closer that was put in for you steps over it rather than
/// doubling it. Only the closer put in last is remembered, and only while
/// it is still where it was left.
- (BOOL)steppedOverAutoCloserFor:(int)character {
    ScintillaView *sci = self.sci;
    NSDictionary *tracked = objc_getAssociatedObject(self, &kAutoCloseKey);
    if (!tracked) return NO;
    long caret = [sci message:SCI_GETCURRENTPOS];
    long typedStart = [sci message:SCI_POSITIONBEFORE wParam:(uptr_t)caret lParam:0];
    long closerAt = [tracked[@"at"] longValue];
    int closer = [tracked[@"closer"] intValue];
    if (typedStart <= closerAt) closerAt += caret - typedStart;     // it moved along with the typing
    if (closerAt < caret || [sci message:SCI_GETCHARAT wParam:(uptr_t)closerAt lParam:0] != closer) {
        objc_setAssociatedObject(self, &kAutoCloseKey, nil, OBJC_ASSOCIATION_RETAIN);
        return NO;
    }
    if (closerAt == caret && character == closer) {
        [sci message:SCI_DELETERANGE wParam:(uptr_t)caret lParam:1];
        objc_setAssociatedObject(self, &kAutoCloseKey, nil, OBJC_ASSOCIATION_RETAIN);
        return YES;
    }
    objc_setAssociatedObject(self, &kAutoCloseKey, @{@"at": @(closerAt), @"closer": @(closer)},
                             OBJC_ASSOCIATION_RETAIN);
    return NO;
}

/// After ">" is typed, the element that was just opened, if any. Only in
/// HTML and XML, as on Windows, and never for an element that has no end.
- (NSString *)closeTagAtCaret {
    if (![NppPreferences shared].autoInsertCloseTag) return nil;
    NSString *language = self.currentDocument.language.name ?: @"";
    if (![language isEqualToString:@"html"] && ![language isEqualToString:@"xml"]) return nil;
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
    static NSSet *voidElements;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        voidElements = [NSSet setWithArray:@[@"area", @"base", @"br", @"col", @"embed", @"hr", @"img",
                                             @"input", @"link", @"meta", @"param", @"source",
                                             @"track", @"wbr"]];
    });
    if ([language isEqualToString:@"html"] && [voidElements containsObject:tag.lowercaseString]) return nil;
    return [NSString stringWithFormat:@"</%@>", tag];
}

/// The languages Notepad++ treats as brace-structured for auto-indent.
static BOOL LanguageUsesBraces(NSString *name) {
    static NSSet *braced;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        braced = [NSSet setWithArray:@[@"c", @"cpp", @"java", @"cs", @"objc", @"php",
                                       @"javascript", @"javascript.js", @"jsp", @"css",
                                       @"perl", @"rust", @"powershell", @"json", @"json5",
                                       @"typescript", @"go", @"golang", @"swift"]];
    });
    return [braced containsObject:(name ?: @"").lowercaseString];
}

- (void)maintainIndentationAfter:(int)character {
    NppPreferences *prefs = [NppPreferences shared];
    if (prefs.autoIndentMode == 0) return;

    ScintillaView *sci = self.sci;
    long eolMode = [sci message:SCI_GETEOLMODE];
    BOOL isNewline = (eolMode == SC_EOL_CR) ? (character == '\r') : (character == '\n');
    if (!isNewline) return;

    long current = [sci message:SCI_LINEFROMPOSITION
                          wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long previous = current - 1;
    if (previous < 0) return;

    // Pressing Enter on an empty line leaves the indentation alone.
    if ([sci message:SCI_LINELENGTH wParam:(uptr_t)previous] == 0) return;

    // The indent to carry over comes from the last line that had any text.
    while (previous >= 0 && [sci message:SCI_LINELENGTH wParam:(uptr_t)previous] == 0) previous--;
    if (previous < 0) return;
    long indent = [sci message:SCI_GETLINEINDENTATION wParam:(uptr_t)previous];

    if (prefs.autoIndentMode == 1 || !LanguageUsesBraces(self.currentDocument.language.name)) {
        if (indent > 0) [sci message:SCI_SETLINEINDENTATION wParam:(uptr_t)current lParam:indent];
        return;
    }

    // A brace opens a level, and a closing brace waiting on the same line is
    // pushed onto one of its own so the block is left open.
    long tabWidth = [sci message:SCI_GETTABWIDTH];
    long caret = [sci message:SCI_GETCURRENTPOS];
    long beforeNewline = caret - (eolMode == SC_EOL_CRLF ? 3 : 2);
    unsigned char previousChar = beforeNewline >= 0
        ? (unsigned char)[sci message:SCI_GETCHARAT wParam:(uptr_t)beforeNewline] : 0;
    unsigned char nextChar = (unsigned char)[sci message:SCI_GETCHARAT wParam:(uptr_t)caret];

    if (previousChar == '{') {
        if (nextChar == '}') {
            NSString *eol = eolMode == SC_EOL_CRLF ? @"\r\n" : eolMode == SC_EOL_CR ? @"\r" : @"\n";
            [sci setStringProperty:SCI_INSERTTEXT parameter:caret value:eol];
            [sci message:SCI_SETLINEINDENTATION wParam:(uptr_t)(current + 1) lParam:indent];
        }
        [sci message:SCI_SETLINEINDENTATION wParam:(uptr_t)current lParam:indent + tabWidth];
    } else {
        if (indent > 0) [sci message:SCI_SETLINEINDENTATION wParam:(uptr_t)current lParam:indent];
    }
}

- (void)handleCharacterAdded:(int)character {
    NppPreferences *p = [NppPreferences shared];
    ScintillaView *sci = self.sci;

    // Indentation is carried over before anything else, so the line is already
    // in place when completion looks at it.
    [self maintainIndentationAfter:character];

    if ([self steppedOverAutoCloserFor:character]) return;

    // Auto-insertion first: it does not depend on completion being on.
    NSString *closing = [self autoInsertionForCharacter:character];
    if (closing && ![self autoCloseAllowedFor:character]) closing = nil;
    if (!closing && character == '>') closing = [self closeTagAtCaret];
    if (closing.length) {
        long pos = [sci message:SCI_GETCURRENTPOS];
        [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:closing];
        [sci message:SCI_GOTOPOS wParam:(uptr_t)pos lParam:0];   // caret stays inside
        if (closing.length == 1) {
            objc_setAssociatedObject(self, &kAutoCloseKey,
                                     @{@"at": @(pos), @"closer": @([closing characterAtIndex:0])},
                                     OBJC_ASSOCIATION_RETAIN);
        }
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

- (void)forgetRecentFile:(NSString *)path {
    NppPreferences *p = [NppPreferences shared];
    if (![p.recentFiles containsObject:path]) return;
    NSMutableArray *list = [p.recentFiles mutableCopy];
    [list removeObject:path];
    p.recentFiles = list;
}

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

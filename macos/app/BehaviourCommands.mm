#import "BehaviourCommands.h"
#import "SettingsCommands.h"
#import "SearchCommands.h"
#import "AdvancedEditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

static long Utf8Len(NSString *s) {
    return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

@implementation EditorController (BehaviourCommands)

#pragma mark - Large file restriction

- (BOOL)largeFileRestrictionActive {
    NppPreferences *p = [NppPreferences shared];
    if (!p.largeFileRestrictionEnabled) return NO;
    long bytes = [self.sci message:SCI_GETLENGTH];
    return bytes > (long)p.largeFileThresholdMB * 1024 * 1024;
}

/// Notepad++ turns features off above a size threshold so large files stay
/// usable. The same switches are flipped here, and turned back on below it.
- (void)applyPerformanceRestrictions {
    NppPreferences *p = [NppPreferences shared];
    ScintillaView *sci = self.sci;
    BOOL restricted = [self largeFileRestrictionActive];

    if (restricted) {
        [sci message:SCI_SETILEXER wParam:0 lParam:0];          // no syntax highlighting
        if (p.largeFileDeactivateWordWrap) {
            [sci message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE lParam:0];
        }
        [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_LINK_INDICATOR lParam:0];
        [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];
        [sci message:SCI_BRACEBADLIGHT wParam:(uptr_t)-1 lParam:0];
    } else {
        [self applyLanguage];
    }
    [self refreshChrome];
}

/// Each feature asks whether it is allowed before doing work.
- (BOOL)featureAllowed:(NSString *)name {
    NppPreferences *p = [NppPreferences shared];
    if (![self largeFileRestrictionActive]) return YES;
    if ([name isEqualToString:@"autocompletion"]) return p.largeFileAllowAutoCompletion;
    if ([name isEqualToString:@"smartHighlight"]) return p.largeFileAllowSmartHighlighting;
    if ([name isEqualToString:@"braceMatch"])     return p.largeFileAllowBraceMatch;
    if ([name isEqualToString:@"links"])          return p.largeFileAllowClickableLinks;
    return YES;
}

#pragma mark - Clickable links

- (void)configureLinkIndicator {
    ScintillaView *sci = self.sci;
    NppPreferences *p = [NppPreferences shared];
    [sci message:SCI_INDICSETSTYLE wParam:NPPMAC_LINK_INDICATOR
           lParam:p.linksFullBox ? INDIC_ROUNDBOX : (p.linksNoUnderline ? INDIC_HIDDEN : INDIC_PLAIN)];
    [sci message:SCI_INDICSETFORE wParam:NPPMAC_LINK_INDICATOR lParam:0xFF0000];   // BGR blue
    [sci message:SCI_INDICSETALPHA wParam:NPPMAC_LINK_INDICATOR lParam:60];
    [sci message:SCI_INDICSETUNDER wParam:NPPMAC_LINK_INDICATOR lParam:1];
}

/// Schemes to recognise: the standard ones plus whatever the user added.
- (NSArray<NSString *> *)linkSchemes {
    NSMutableArray *schemes = [NSMutableArray arrayWithArray:@[@"https", @"http", @"ftp", @"mailto", @"file"]];
    for (NSString *extra in [[NppPreferences shared].linkCustomSchemes
                             componentsSeparatedByCharactersInSet:
                             [NSCharacterSet characterSetWithCharactersInString:@" ,;"]]) {
        NSString *t = [extra stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length && ![schemes containsObject:t]) [schemes addObject:t];
    }
    return schemes;
}

- (NSRegularExpression *)linkExpression {
    NSString *alternatives = [[self linkSchemes] componentsJoinedByString:@"|"];
    NSString *pattern = [NSString stringWithFormat:@"(?:%@)://[^\\s\"'<>()]+|mailto:[^\\s\"'<>()]+",
                         alternatives];
    return [NSRegularExpression regularExpressionWithPattern:pattern
                                                     options:NSRegularExpressionCaseInsensitive
                                                       error:NULL];
}

- (NSUInteger)markClickableLinks {
    ScintillaView *sci = self.sci;
    [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_LINK_INDICATOR lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];

    if (![NppPreferences shared].linksEnabled || ![self featureAllowed:@"links"]) return 0;
    [self configureLinkIndicator];

    NSString *text = [sci string] ?: @"";
    NSRegularExpression *re = [self linkExpression];
    if (!re) return 0;

    __block NSUInteger count = 0;
    [re enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        // Scintilla works in bytes, so the character range is converted.
        long start = Utf8Len([text substringToIndex:m.range.location]);
        long length = Utf8Len([text substringWithRange:m.range]);
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)start lParam:length];
        count++;
    }];
    return count;
}

- (NSString *)linkAtPosition:(long)position {
    ScintillaView *sci = self.sci;
    if (![sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_LINK_INDICATOR lParam:position]) return nil;
    long start = [sci message:SCI_INDICATORSTART wParam:NPPMAC_LINK_INDICATOR lParam:position];
    long end = [sci message:SCI_INDICATOREND wParam:NPPMAC_LINK_INDICATOR lParam:position];
    if (end <= start) return nil;

    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if ((NSUInteger)end > data.length) return nil;
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)start,
                                                                            (NSUInteger)(end - start))]
                                 encoding:NSUTF8StringEncoding];
}

- (BOOL)openLinkAtPosition:(long)position {
    NSString *link = [self linkAtPosition:position];
    if (!link.length) return NO;
    NSURL *url = [NSURL URLWithString:link];
    if (!url.scheme) return NO;
    return [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Brace match

- (void)updateBraceMatch {
    ScintillaView *sci = self.sci;
    if (![NppPreferences shared].braceMatchEnabled || ![self featureAllowed:@"braceMatch"]) {
        [sci message:SCI_BRACEBADLIGHT wParam:(uptr_t)-1 lParam:0];
        return;
    }
    long pos = [sci message:SCI_GETCURRENTPOS];
    long candidate = pos;
    long match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)candidate lParam:0];
    if (match < 0 && pos > 0) {
        candidate = pos - 1;
        match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)candidate lParam:0];
    }
    if (match < 0) {
        [sci message:SCI_BRACEBADLIGHT wParam:(uptr_t)-1 lParam:0];
        return;
    }
    [sci message:SCI_BRACEHIGHLIGHT wParam:(uptr_t)candidate lParam:match];
}

#pragma mark - Smart highlighting

- (NSUInteger)updateSmartHighlight {
    ScintillaView *sci = self.sci;
    // Style 4 is reserved for this, as Notepad++ reserves a Smart Highlighting style.
    NSInteger style = 4;
    [self clearStyle:style];
    if (![NppPreferences shared].smartHighlightEnabled ||
        ![self featureAllowed:@"smartHighlight"]) return 0;

    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (b <= a) return 0;                       // only a real selection highlights
    if (b - a > 100) return 0;                  // a whole-paragraph selection is not a token

    NppMatchFlags flags = NppMatchNone;
    if ([NppPreferences shared].smartHighlightMatchCase) flags |= NppMatchCase;
    if ([NppPreferences shared].smartHighlightWholeWord) flags |= NppMatchWholeWord;
    if (flags == NppMatchNone) return [self markAllOccurrencesOfSelection:style];

    // With either refinement on, the match rules come from AdvancedEditCommands.
    ScintillaView *view = self.sci;
    NSUInteger before = (NSUInteger)[view message:SCI_GETSELECTIONS];
    NSUInteger n = [self multiSelectAllOccurrences:flags];
    [view message:SCI_SETSELECTION wParam:(uptr_t)a lParam:b];
    (void)before;
    return n;
}

#pragma mark - Word characters and delimiters

- (void)applyWordCharacters {
    NppPreferences *p = [NppPreferences shared];
    if (!p.customWordCharsEnabled || !p.customWordChars.length) return;
    static const char *base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
    NSString *chars = [@(base) stringByAppendingString:p.customWordChars];
    [self.sci setStringProperty:SCI_SETWORDCHARS parameter:0 value:chars];
}

- (BOOL)selectBetweenDelimitersAt:(long)position {
    NppPreferences *p = [NppPreferences shared];
    NSString *open = p.delimiterOpen.length ? p.delimiterOpen : @"(";
    NSString *close = p.delimiterClose.length ? p.delimiterClose : @")";
    ScintillaView *sci = self.sci;

    NSString *text = [sci string] ?: @"";
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (position < 0 || (NSUInteger)position > data.length) return NO;

    unichar openChar = [open characterAtIndex:0];
    unichar closeChar = [close characterAtIndex:0];

    // Search outwards from the caret, in characters, then convert back to bytes.
    NSUInteger caretChar = [[[NSString alloc] initWithData:
        [data subdataWithRange:NSMakeRange(0, (NSUInteger)position)]
        encoding:NSUTF8StringEncoding] length];

    NSInteger from = -1, to = -1;
    for (NSInteger i = (NSInteger)caretChar - 1; i >= 0; --i) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c == closeChar && i != (NSInteger)caretChar - 1) break;
        if (c == openChar) { from = i; break; }
        if (!p.delimiterMultiline && (c == '\n' || c == '\r')) break;
    }
    for (NSUInteger i = caretChar; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        if (c == closeChar) { to = (NSInteger)i; break; }
        if (!p.delimiterMultiline && (c == '\n' || c == '\r')) break;
    }
    if (from < 0 || to < 0 || to <= from) { NSBeep(); return NO; }

    long byteFrom = Utf8Len([text substringToIndex:(NSUInteger)from + 1]);
    long byteTo = Utf8Len([text substringToIndex:(NSUInteger)to]);
    [sci message:SCI_SETSEL wParam:(uptr_t)byteFrom lParam:byteTo];
    [self refreshChrome];
    return YES;
}

#pragma mark - Multi-instance

- (BOOL)shouldOpenFilesInNewInstance {
    return [NppPreferences shared].multiInstanceMode == 1;
}

/// Notepad++ remembers which panels were open; the same set is stored here.
- (void)rememberPanelState {
    NppPreferences *p = [NppPreferences shared];
    if (!p.rememberPanelState) return;
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"workspace"] = @([self workspaceVisible]);
    state[@"documentMap"] = @([self documentMapVisible]);
    state[@"projectPanel"] = @([self activeProjectPanel]);
    state[@"secondaryView"] = @([self secondaryViewVisible]);
    p.panelState = state;
}

- (void)restorePanelState {
    NppPreferences *p = [NppPreferences shared];
    if (!p.rememberPanelState) return;
    NSDictionary *state = p.panelState;
    if (!state.count) return;

    if ([state[@"workspace"] boolValue]) {
        NSURL *folder = [self containingFolderURL];
        if (folder) [self openFolderAsWorkspace:folder.path];
    }
    if ([state[@"documentMap"] boolValue]) [self setDocumentMapVisible:YES];
    NSInteger project = [state[@"projectPanel"] integerValue];
    if (project >= 1 && project <= 3) [self showProjectPanel:project];
    if ([state[@"secondaryView"] boolValue]) [self setSecondaryViewVisible:YES];
}

@end

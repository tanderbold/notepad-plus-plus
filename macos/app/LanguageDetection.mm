#import "LanguageDetection.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

/// The C character tests may only be given a byte; handing them a UTF-16 unit
/// reads past the end of their table, which is how a file with a Cyrillic or
/// CJK character in it brought the whole run down.
static inline BOOL NppIsWordCharacter(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

static inline BOOL NppIsDigit(unichar c) { return c >= '0' && c <= '9'; }

/// Below this much text there is nothing to judge by, and a guess made on two
/// or three words would be wrong as often as not. A file this short is left
/// alone unless it says outright what it is.
const NSUInteger NppMostLanguagesToOffer = 10;

static const NSUInteger kLeastWords = 12;
static const NSUInteger kLeastCharacters = 40;

/// Only the beginning of a file is read: it is enough to tell what it is, and
/// a whole large file is not worth walking for the answer.
static const NSUInteger kSampleLimit = 64 * 1024;

/// What an interpreter on a shebang line is called here. The name of the
/// program is matched, not the path, so /usr/bin/env python3 works too.
static NSDictionary<NSString *, NSString *> *InterpreterNames(void) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"sh": @"bash", @"bash": @"bash", @"zsh": @"bash", @"ksh": @"bash",
            @"dash": @"bash", @"ash": @"bash", @"fish": @"bash",
            @"python": @"python", @"python2": @"python", @"python3": @"python",
            @"perl": @"perl", @"ruby": @"ruby", @"php": @"php",
            @"node": @"javascript", @"nodejs": @"javascript", @"deno": @"javascript",
            @"lua": @"lua", @"tclsh": @"tcl", @"wish": @"tcl", @"expect": @"tcl",
            @"awk": @"nsis", @"gawk": @"nsis",     // awk has no lexer of its own
            @"r": @"r", @"rscript": @"r",
            @"pwsh": @"powershell", @"powershell": @"powershell",
            @"make": @"makefile", @"cmake": @"cmake",
            @"swift": @"swift", @"go": @"go", @"julia": @"julia",
        };
    });
    return names;
}

/// Names an editor modeline may use for a language that is called something
/// else in Notepad++'s own list.
static NSDictionary<NSString *, NSString *> *ModelineNames(void) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"sh": @"bash", @"shell-script": @"bash", @"shell": @"bash",
            @"c++": @"cpp", @"csharp": @"cs", @"c#": @"cs",
            @"js": @"javascript", @"jsx": @"javascript", @"ts": @"typescript",
            @"make": @"makefile", @"conf": @"ini", @"cfg": @"ini",
            @"yml": @"yaml", @"md": @"markdown", @"text": @"normal",
        };
    });
    return names;
}

@implementation LanguageCatalog (Detection)

#pragma mark - The sample

- (NSString *)sampleOfContents:(NSString *)text {
    if (text.length <= kSampleLimit) return text;
    // Cut on a character boundary, which substringToIndex: already respects.
    return [text substringToIndex:kSampleLimit];
}

#pragma mark - What the text says outright

- (NppLanguage *)languageNamedForDetection:(NSString *)name {
    if (!name.length) return nil;
    NSString *lower = name.lowercaseString;
    NSString *mapped = ModelineNames()[lower] ?: lower;
    NppLanguage *language = [self languageNamed:mapped];
    return [language.name isEqualToString:@"normal"] ? nil : language;
}

- (NppLanguage *)languageFromShebang:(NSString *)line {
    if (![line hasPrefix:@"#!"]) return nil;
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *word in [[line substringFromIndex:2]
                            componentsSeparatedByCharactersInSet:
                                [NSCharacterSet whitespaceCharacterSet]]) {
        if (word.length) [words addObject:word];
    }
    if (!words.count) return nil;

    NSString *program = words.firstObject.lastPathComponent.lowercaseString;
    if ([program isEqualToString:@"env"] && words.count > 1) {
        // "env -S", "env VAR=value python" and the like: the interpreter is the
        // first word that is neither a switch nor an assignment.
        for (NSUInteger i = 1; i < words.count; ++i) {
            NSString *word = words[i];
            if ([word hasPrefix:@"-"] || [word containsString:@"="]) continue;
            program = word.lastPathComponent.lowercaseString;
            break;
        }
    }

    // python3.11 and the like: the version is not part of the name.
    NSString *trimmed = program;
    while (trimmed.length && (NppIsDigit([trimmed characterAtIndex:trimmed.length - 1]) ||
                              [trimmed hasSuffix:@"."])) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    NSString *name = InterpreterNames()[program] ?: InterpreterNames()[trimmed];
    return name ? [self languageNamed:name] : nil;
}

- (NppLanguage *)languageFromModeline:(NSArray<NSString *> *)lines {
    // Emacs writes "-*- mode: python -*-" (or just "-*- python -*-") in the
    // first line; vim writes "vim: set ft=python:" in the first or last few.
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN((NSUInteger)2, lines.count); ++i) {
        [candidates addObject:lines[i]];
    }
    for (NSUInteger i = lines.count > 5 ? lines.count - 5 : 0; i < lines.count; ++i) {
        [candidates addObject:lines[i]];
    }

    for (NSString *line in candidates) {
        NSRange open = [line rangeOfString:@"-*-"];
        if (open.location != NSNotFound) {
            NSRange after = NSMakeRange(NSMaxRange(open), line.length - NSMaxRange(open));
            NSRange close = [line rangeOfString:@"-*-" options:0 range:after];
            if (close.location != NSNotFound) {
                NSString *body = [line substringWithRange:
                    NSMakeRange(after.location, close.location - after.location)];
                NSString *mode = body;
                NSRange marker = [body rangeOfString:@"mode:" options:NSCaseInsensitiveSearch];
                if (marker.location != NSNotFound) {
                    mode = [body substringFromIndex:NSMaxRange(marker)];
                }
                mode = [mode componentsSeparatedByString:@";"].firstObject;
                mode = [mode stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
                NppLanguage *found = [self languageNamedForDetection:mode];
                if (found) return found;
            }
        }

        for (NSString *key in @[@"filetype=", @"ft=", @"syntax="]) {
            NSRange marker = [line rangeOfString:key options:NSCaseInsensitiveSearch];
            if (marker.location == NSNotFound) continue;
            NSString *rest = [line substringFromIndex:NSMaxRange(marker)];
            NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString:@" \t:;\"'"];
            NSRange end = [rest rangeOfCharacterFromSet:stop];
            NSString *mode = end.location == NSNotFound ? rest
                                                        : [rest substringToIndex:end.location];
            NppLanguage *found = [self languageNamedForDetection:mode];
            if (found) return found;
        }
    }
    return nil;
}

- (NppLanguage *)declaredLanguageInContents:(NSString *)text {
    NSString *sample = [self sampleOfContents:text];
    if (!sample.length) return nil;
    NSArray<NSString *> *lines = [sample componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet newlineCharacterSet]];

    NppLanguage *shebang = [self languageFromShebang:lines.firstObject ?: @""];
    if (shebang) return shebang;

    NSString *head = [sample substringToIndex:MIN((NSUInteger)512, sample.length)];
    NSString *lead = [head stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([lead hasPrefix:@"<?php"]) return [self languageNamed:@"php"];
    if ([lead hasPrefix:@"<?xml"]) return [self languageNamed:@"xml"];
    if ([head rangeOfString:@"<!DOCTYPE html" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [head rangeOfString:@"<html" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return [self languageNamed:@"html"];
    }

    NppLanguage *modeline = [self languageFromModeline:lines];
    if (modeline) return modeline;

    // JSON is worth parsing for: nothing else both starts this way and holds
    // together as JSON, and the keyword scoring has nothing to go on in it.
    if ([lead hasPrefix:@"{"] || [lead hasPrefix:@"["]) {
        NSData *data = [sample dataUsingEncoding:NSUTF8StringEncoding];
        if (data && [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]) {
            return [self languageNamed:@"json"];
        }
    }
    return nil;
}

#pragma mark - What its words suggest

/// keyword -> how many languages list it. Built once from the catalog itself.
- (NSDictionary<NSString *, NSNumber *> *)keywordOwnerCounts {
    static const char kCountsKey = 0;
    NSDictionary *cached = objc_getAssociatedObject(self, &kCountsKey);
    if (cached) return cached;

    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (NppLanguage *language in self.allLanguages) {
        for (NSString *word in [self keywordsOfLanguage:language]) {
            counts[word] = @(counts[word].integerValue + 1);
        }
    }
    objc_setAssociatedObject(self, &kCountsKey, counts, OBJC_ASSOCIATION_RETAIN);
    return counts;
}

/// The distinct words a language claims, lowercased.
- (NSSet<NSString *> *)keywordsOfLanguage:(NppLanguage *)language {
    static const char kWordsKey = 0;
    NSMutableDictionary *cache = objc_getAssociatedObject(self, &kWordsKey);
    if (!cache) {
        cache = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &kWordsKey, cache, OBJC_ASSOCIATION_RETAIN);
    }
    NSSet *cached = cache[language.name ?: @""];
    if (cached) return cached;

    NSMutableSet<NSString *> *words = [NSMutableSet set];
    for (NSString *list in language.keywordSets.allValues) {
        for (NSString *word in [list componentsSeparatedByString:@" "]) {
            // Only words a text can be scanned for: the keyword lists also hold
            // operators and fragments, which no word boundary would find.
            if (word.length < 2) continue;
            NSString *lower = word.lowercaseString;
            BOOL plain = YES;
            for (NSUInteger i = 0; i < lower.length; ++i) {
                unichar c = [lower characterAtIndex:i];
                if (!(NppIsWordCharacter(c) || c == '_' || c == '-' || c == '.')) { plain = NO; break; }
            }
            if (plain) [words addObject:lower];
        }
    }
    cache[language.name ?: @""] = words;
    return words;
}

- (NSDictionary<NSString *, NSNumber *> *)languageScoresForContents:(NSString *)text {
    NSString *sample = [self sampleOfContents:text];
    if (sample.length < kLeastCharacters) return @{};

    // The words of the text, and how often each occurs.
    NSMutableDictionary<NSString *, NSNumber *> *seen = [NSMutableDictionary dictionary];
    NSMutableString *word = [NSMutableString string];
    NSUInteger total = 0;
    for (NSUInteger i = 0; i <= sample.length; ++i) {
        unichar c = i < sample.length ? [sample characterAtIndex:i] : ' ';
        if (NppIsWordCharacter(c) || c == '_' || c == '-' || c == '.' || c == '#' || c == '@') {
            [word appendFormat:@"%C", c];
            continue;
        }
        if (word.length >= 2) {
            NSString *lower = word.lowercaseString;
            seen[lower] = @(seen[lower].integerValue + 1);
            total++;
        }
        [word setString:@""];
    }
    if (total < kLeastWords) return @{};

    NSDictionary<NSString *, NSNumber *> *owners = [self keywordOwnerCounts];
    NSMutableDictionary<NSString *, NSNumber *> *scores = [NSMutableDictionary dictionary];
    for (NppLanguage *language in self.allLanguages) {
        if ([language.name isEqualToString:@"normal"]) continue;
        NSSet<NSString *> *keywords = [self keywordsOfLanguage:language];
        if (keywords.count < 4) continue;      // too little to judge by

        double score = 0;
        NSUInteger distinct = 0;
        for (NSString *found in seen) {
            if (![keywords containsObject:found]) continue;
            distinct++;

            // A word every language claims says nothing; one claimed by a
            // single language says more. A long word says more than a short
            // one, which is as often as not an ordinary English word. And
            // repeating a word adds less each time, so one word cannot carry
            // a whole file.
            NSInteger claimants = MAX((NSInteger)1, owners[found].integerValue);
            double weight = log(1.0 + (double)found.length) / (double)claimants;
            score += weight * (1.0 + log((double)seen[found].integerValue));
        }

        // Three different words at the least: one or two are coincidence.
        if (distinct < 3) continue;

        // Divided by the size of the language's own list as well as by the size
        // of the text. Without this a language that claims two thousand words,
        // as SQL and PowerShell do, matches something in every file and wins
        // them all.
        if (score > 0) {
            scores[language.name] = @(score / (sqrt((double)total) * sqrt((double)keywords.count)));
        }
    }
    return scores;
}

#pragma mark - The answer

- (NSArray<NppLanguage *> *)languagesMatchingContents:(NSString *)text {
    NppLanguage *declared = [self declaredLanguageInContents:text];
    if (declared) return @[declared];

    NSDictionary<NSString *, NSNumber *> *scores = [self languageScoresForContents:text];
    if (!scores.count) return @[];

    NSArray<NSString *> *ranked = [scores keysSortedByValueUsingComparator:
                                   ^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [b compare:a];
    }];
    double top = scores[ranked.firstObject].doubleValue;
    if (top <= 0) return @[];

    // A language is worth offering when it is at least in the same class as the
    // best one. Anything far below is noise from a word or two in a comment.
    NSMutableArray<NppLanguage *> *fitting = [NSMutableArray array];
    for (NSString *name in ranked) {
        if (scores[name].doubleValue < top * 0.5) break;
        NppLanguage *language = [self languageNamed:name];
        if (language) [fitting addObject:language];
        if (fitting.count > NppMostLanguagesToOffer) return @[];
    }
    return fitting;
}

- (NppLanguage *)languageForContents:(NSString *)text {
    NSArray<NppLanguage *> *fitting = [self languagesMatchingContents:text];
    if (fitting.count != 1) return nil;
    return fitting.firstObject;
}

@end

@implementation EditorController (LanguageDetection)

- (void (^)(NSArray<NppLanguage *> *))languageChoiceHandler {
    static const char kHandlerKey = 0;
    return objc_getAssociatedObject(self, &kHandlerKey);
}

- (void)setLanguageChoiceHandler:(void (^)(NSArray<NppLanguage *> *))handler {
    static const char kHandlerKey = 0;
    objc_setAssociatedObject(self, &kHandlerKey, handler, OBJC_ASSOCIATION_COPY);
}

- (NSArray<NppLanguage *> *)languagesSuggestedForCurrentDocument {
    if (![NppPreferences shared].detectLanguageFromContent) return @[];

    NppDocument *doc = self.currentDocument;
    if (!doc || doc.languageChosenByUser) return @[];

    // Only where the name has nothing to say. A file called script.py is that
    // language whatever its contents look like.
    if (doc.path.pathExtension.length) return @[];
    if (doc.language && ![doc.language.name isEqualToString:@"normal"]) return @[];

    return [[LanguageCatalog sharedCatalog] languagesMatchingContents:[self.sci string] ?: @""];
}

- (NppLanguage *)detectLanguageOfCurrentDocumentOffering:
    (void (^)(NSArray<NppLanguage *> *))chooser {

    NSArray<NppLanguage *> *fitting = [self languagesSuggestedForCurrentDocument];
    if (!fitting.count) return nil;

    // One answer is an answer: it is applied without asking.
    if (fitting.count == 1) {
        [self setLanguageNamed:fitting.firstObject.name];
        return fitting.firstObject;
    }
    if (chooser) chooser(fitting);
    return nil;
}

@end

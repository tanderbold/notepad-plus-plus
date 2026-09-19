#import "LanguageDetection.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import "LanguageModel.h"
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
            @"dmd": @"d", @"rdmd": @"d", @"ldc2": @"d",
            @"raku": @"raku", @"perl6": @"raku", @"groovy": @"java", @"scala": @"java",
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

/// Shapes that belong to one language and are not words any keyword list holds:
/// a TeX environment, an include line, a section header. Keyword counting alone
/// leaves several languages with nothing to go on, and these are what it misses.
static NSDictionary<NSString *, NSArray<NSString *> *> *StructuralMarks(void) {
    static NSDictionary *marks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Each of these has to belong to its language and to almost nothing
        // else: two of them in a text are taken as that language's presence
        // whatever the rest of it looks like. A mark as ordinary as "def " or
        // "->" would drag its language into every list.
        marks = @{
            @"latex":      @[@"\\begin{", @"\\end{", @"\\documentclass", @"\\usepackage",
                             @"\\section{"],
            @"tex":        @[@"\\def\\", @"\\hbox", @"\\vbox", @"\\catcode", @"\\newif",
                             @"\\expandafter", @"\\csname"],
            @"makefile":   @[@".PHONY", @"$(CC)", @"$(MAKE)", @"$(shell", @"$(wildcard"],
            @"vb":         @[@"End Sub", @"End Function", @"End If", @"Private Sub", @"Public Sub",
                             @"End Class", @"End Module", @" As Integer", @" As String"],
            @"typescript": @[@"export type", @": Promise<", @"as const", @"export interface",
                             @": string[]", @"implements "],
            @"batch":      @[@"@echo off", @"%~dp0", @"goto :", @"set /p", @"%errorlevel%"],
            @"powershell": @[@"$PSScriptRoot", @"Write-Host", @"-ErrorAction", @"[CmdletBinding",
                             @"Write-Output", @"$args[", @"$($", @"-like ", @"-match ",
                             @"-eq ", @"-ne ", @"-not ", @"]::", @"param(", @"Get-"],
            @"cs":         @[@"using System", @"string[] args", @"Console.WriteLine",
                             @"async Task", @"nameof(", @"IEnumerable<", @"#region"],
            @"java":       @[@"public static void main", @"import java.", @"@Override",
                             @"System.out."],
            @"rust":       @[@"let mut ", @"impl ", @"#[derive", @"::new(", @"fn main()"],
            @"go":         @[@"package main", @"import (", @"func main()", @"fmt."],
            @"php":        @[@"$this->", @"<?=", @"::class"],
            @"perl":       @[@"use strict", @"my $", @"=~", @"@_"],
            @"ruby":       @[@"attr_accessor", @"do |", @"puts ", @"require '"],
        };
    });
    return marks;
}

/// Files that are nothing but sections and assignments: [name] on its own line,
/// then key=value. No keyword list has anything to say about them, and the
/// shape is the whole of what they are.
static double IniLikeness(NSString *sample) {
    NSArray<NSString *> *lines = [sample componentsSeparatedByString:@"\n"];
    NSUInteger sections = 0, assignments = 0, other = 0;
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        if (!line.length || [line hasPrefix:@";"] || [line hasPrefix:@"#"]) continue;
        if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) { sections++; continue; }
        NSRange equals = [line rangeOfString:@"="];
        if (equals.location != NSNotFound && equals.location > 0 &&
            [line rangeOfString:@";"].location == NSNotFound &&
            ![line hasSuffix:@"{"] && ![line hasSuffix:@","]) {
            assignments++;
            continue;
        }
        other++;
    }
    NSUInteger counted = sections + assignments + other;
    if (counted < 4 || !sections || !assignments) return 0;
    return (double)(sections + assignments) / (double)counted;
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

    // What a language looks like, over and above the words it uses. Several
    // languages have keyword lists too thin or too ordinary to be told apart by
    // words alone, and their shapes are what give them away.
    NSDictionary<NSString *, NSArray<NSString *> *> *marks = StructuralMarks();
    for (NSString *name in marks) {
        NSUInteger hits = 0;
        for (NSString *mark in marks[name]) {
            // Case matters: Visual Basic writes "End If", Fortran writes
            // "END IF", and ignoring the difference hands one the other's files.
            if ([sample rangeOfString:mark].location != NSNotFound) hits++;
        }
        if (hits < 2) continue;                      // one shape is a coincidence
        double bonus = 0.03 * (double)hits;
        scores[name] = @(scores[name].doubleValue + bonus);
    }

    double iniLike = IniLikeness(sample);
    if (iniLike > 0.8) scores[@"ini"] = @(scores[@"ini"].doubleValue + 0.06 * iniLike);
    return scores;
}

#pragma mark - The answer

- (NSArray<NppLanguage *> *)languagesMatchingContents:(NSString *)text {
    // What a file says about itself outright is taken as given. A shebang line
    // is not a guess, and no amount of training beats reading it.
    NppLanguage *declared = [self declaredLanguageInContents:text];
    if (declared) return @[declared];

    // The model answers with a set: one language, a short list, or nothing
    // when more than ten would fit. Only when it cannot judge the text at all
    // - there is no model, or too little text - do the rules get a turn.
    NSArray<NppLanguage *> *fromModel = [self languagesFromModelForContents:text];
    if (!fromModel) return [self languagesFromRulesForContents:text];
    if (fromModel.count) return fromModel;

    // The model found no language it was sure enough of. It was never shown
    // an example of a fifth of the list, and for those the rules are the
    // only judge there is: whatever they offer among the languages the model
    // does not know is offered, and nothing else.
    NSSet<NSString *> *known = [NSSet setWithArray:[NppLanguageModel sharedModel].languageNames];
    NSMutableArray<NppLanguage *> *unknown = [NSMutableArray array];
    for (NppLanguage *language in [self languagesFromRulesForContents:text]) {
        if (![known containsObject:language.name]) [unknown addObject:language];
    }
    return unknown;
}

/// What the trained model makes of the text, as the set it was fitted to
/// offer: the fewest languages whose likelihoods reach the coverage chosen on
/// held-back fragments. nil when the model has nothing to say.
/// A type declared behind an access modifier - "public enum Status", "internal
/// sealed class X", "public final class Y" - is written that way in C#, Java
/// and (classes and interfaces) ActionScript, and nowhere else Notepad++
/// knows. A short fragment gives the model little else to go by, so the
/// declaration decides which of them are offered, and what else it says
/// decides between them: nil when there is no such declaration.
- (nullable NSArray<NSString *> *)languagesDeclaringTypesIn:(NSString *)sample {
    static NSRegularExpression *declaration;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        declaration = [NSRegularExpression regularExpressionWithPattern:
            @"^[ \\t]*(?:public|private|protected|internal)[ \\t]+((?:(?:static|sealed|abstract|final|partial|readonly|strictfp|dynamic)[ \\t]+)*)"
            @"(enum|class|interface|struct|record|@interface)[ \\t]+[A-Za-z_][A-Za-z0-9_]*([^\\n{]*)"
                                                               options:NSRegularExpressionAnchorsMatchLines error:NULL];
    });
    NSArray<NSTextCheckingResult *> *found = [declaration matchesInString:sample options:0 range:NSMakeRange(0, sample.length)];
    if (!found.count) return nil;
    BOOL onlyCSharp = NO, notCSharp = NO, enumOnly = YES;
    for (NSTextCheckingResult *m in found) {
        NSString *modifiers = [sample substringWithRange:[m rangeAtIndex:1]];
        NSString *kind = [sample substringWithRange:[m rangeAtIndex:2]];
        NSString *rest = [sample substringWithRange:[m rangeAtIndex:3]];
        NSString *whole = [sample substringWithRange:m.range];
        if (![kind isEqualToString:@"enum"]) enumOnly = NO;
        if ([whole hasPrefix:@"internal"] || [whole containsString:@" internal "] || [kind isEqualToString:@"struct"] ||
            [modifiers containsString:@"sealed"] || [modifiers containsString:@"partial"] || [modifiers containsString:@"readonly"] ||
            [rest rangeOfString:@":"].location != NSNotFound) onlyCSharp = YES;
        if ([modifiers containsString:@"final"] || [modifiers containsString:@"strictfp"] || [kind isEqualToString:@"@interface"] ||
            [rest containsString:@" extends "] || [rest containsString:@" implements "]) notCSharp = YES;
    }
    // What the body says: members given numbers and properties are C#'s, not Java's.
    NSRegularExpression *numbered = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*[A-Za-z_][A-Za-z0-9_]*[ \\t]*=[ \\t]*-?(?:0x)?[0-9A-Fa-f]+[ \\t]*,?[ \\t]*$"
                                                                              options:NSRegularExpressionAnchorsMatchLines error:NULL];
    BOOL leansCSharp = [numbered firstMatchInString:sample options:0 range:NSMakeRange(0, sample.length)] != nil ||
                       [sample containsString:@"{ get;"] || [sample containsString:@"using System"] || [sample containsString:@"namespace "];
    BOOL leansJava = [sample containsString:@"import java"] || [sample containsString:@"package "] || [sample containsString:@"@Override"] ||
                     [sample containsString:@"System.out."];
    if (onlyCSharp && !notCSharp) return @[@"cs"];
    if (notCSharp && !onlyCSharp) return enumOnly ? @[@"java"] : @[@"java", @"actionscript"];
    NSMutableArray *names = [NSMutableArray arrayWithArray:leansJava && !leansCSharp ? @[@"java", @"cs"] : @[@"cs", @"java"]];
    if (!enumOnly && !leansCSharp && !leansJava) [names addObject:@"actionscript"];
    return names;
}

- (NSArray<NppLanguage *> *)languagesFromModelForContents:(NSString *)text {
    NppLanguageModel *model = [NppLanguageModel sharedModel];
    if (!model) return nil;

    NSArray<NSString *> *offered = [model languagesOfferedForText:text];
    // (A declaration speaks even where the text is too short for the model to.)
    if (!offered && [self languagesDeclaringTypesIn:[self sampleOfContents:text]].count) offered = @[];
    if (!offered) return nil;

    // The marks are read alongside the model rather than instead of it. The
    // model judges the text as a whole and can be talked round by a file that
    // is mostly one language quoting another - a PowerShell script whose body
    // is shell commands and a unit file reads as shell and ini - while a mark
    // such as "[environment]::" or "$($args[0])" belongs to one language and
    // to nothing else. Two of them put the language on the list.
    NSMutableArray<NSString *> *names = [offered mutableCopy];
    NSString *sample = [self sampleOfContents:text];
    // A declaration only a few languages can make settles which are offered;
    // what the model had besides (PowerShell for a bare enum, say) is not.
    NSArray<NSString *> *declared = [self languagesDeclaringTypesIn:sample];
    // (Unless the model is already sure of one of them: a whole Java file needs no question.)
    BOOL modelIsSure = offered.count == 1 && [declared containsObject:offered.firstObject];
    if (declared.count && !modelIsSure) names = [declared mutableCopy];
    NSDictionary<NSString *, NSArray<NSString *> *> *marks = StructuralMarks();
    for (NSString *name in [marks.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if ([names containsObject:name]) continue;
        NSUInteger hits = 0;
        for (NSString *mark in marks[name]) {
            if ([sample rangeOfString:mark].location != NSNotFound) hits++;
        }
        if (hits >= 2) [names addObject:name];
    }
    if (names.count > NppMostLanguagesToOffer) return @[];

    NSMutableArray<NppLanguage *> *fitting = [NSMutableArray array];
    for (NSString *name in names) {
        NppLanguage *language = [self languageNamed:name];
        if (language && ![language.name isEqualToString:@"normal"]) [fitting addObject:language];
    }
    return fitting;
}

/// The marks and the keyword counting, as they were before the model.
- (NSArray<NppLanguage *> *)languagesFromRulesForContents:(NSString *)text {
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

// One key for both accessors. A static declared inside each of them is two
// variables at two addresses, and what the setter stored the getter could
// never find: the handler read back as nil, and no choice was ever shown.
static const char kLanguageChoiceHandlerKey = 0;

- (void (^)(NSArray<NppLanguage *> *))languageChoiceHandler {
    return objc_getAssociatedObject(self, &kLanguageChoiceHandlerKey);
}

- (void)setLanguageChoiceHandler:(void (^)(NSArray<NppLanguage *> *))handler {
    objc_setAssociatedObject(self, &kLanguageChoiceHandlerKey, handler, OBJC_ASSOCIATION_COPY);
}

/// Why nothing was suggested, or nil when something could be. One line in
/// the system log per decision: "nothing happened" is otherwise impossible
/// to tell apart from "nothing was asked".
- (NSString *)reasonNotToSuggestForDocument:(NppDocument *)doc {
    if (![NppPreferences shared].detectLanguageFromContent) return @"the setting is off";
    if (!doc) return @"no document";
    if (doc.languageChosenByUser) return @"the language was chosen by hand";
    // Only where the name has nothing to say. A file called script.py is that
    // language whatever its contents look like.
    if (doc.path.pathExtension.length) return @"the name has an extension";
    if (doc.language && ![doc.language.name isEqualToString:@"normal"]) {
        return [NSString stringWithFormat:@"the language is already %@", doc.language.name];
    }
    return nil;
}

- (NSArray<NppLanguage *> *)languagesSuggestedForCurrentDocument {
    NppDocument *doc = self.currentDocument;
    NSString *reason = [self reasonNotToSuggestForDocument:doc];
    if (reason) {
        NSLog(@"language detection: not asked, %@", reason);
        return @[];
    }
    NSArray<NppLanguage *> *fitting =
        [[LanguageCatalog sharedCatalog] languagesMatchingContents:[self.sci string] ?: @""];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NppLanguage *one in fitting) [names addObject:one.name];
    NSLog(@"language detection: %lu characters, offered [%@]",
          (unsigned long)[self.sci string].length, [names componentsJoinedByString:@", "]);
    return fitting;
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

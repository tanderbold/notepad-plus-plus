#import "ToolsCommands.h"
#import "EditCommands.h"
#import "ScintillaView.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

@implementation EditorController (ToolsCommands)

#pragma mark - Hashes

+ (NSString *)nameOfDigest:(NppDigest)digest {
    switch (digest) {
        case NppDigestMD5:    return @"MD5";
        case NppDigestSHA1:   return @"SHA-1";
        case NppDigestSHA256: return @"SHA-256";
        case NppDigestSHA512: return @"SHA-512";
    }
    return @"";
}

+ (NSString *)hashOfData:(NSData *)data digest:(NppDigest)digest {
    if (!data) return nil;
    // MD5 is offered because the Tools menu offers it. It is a checksum here,
    // not a security primitive, so the deprecation is silenced deliberately.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    unsigned char out[CC_SHA512_DIGEST_LENGTH];
    CC_LONG len = (CC_LONG)data.length;
    NSUInteger size = 0;
    switch (digest) {
        case NppDigestMD5:    CC_MD5(data.bytes, len, out);    size = CC_MD5_DIGEST_LENGTH;    break;
        case NppDigestSHA1:   CC_SHA1(data.bytes, len, out);   size = CC_SHA1_DIGEST_LENGTH;   break;
        case NppDigestSHA256: CC_SHA256(data.bytes, len, out); size = CC_SHA256_DIGEST_LENGTH; break;
        case NppDigestSHA512: CC_SHA512(data.bytes, len, out); size = CC_SHA512_DIGEST_LENGTH; break;
    }
#pragma clang diagnostic pop
    NSMutableString *hex = [NSMutableString stringWithCapacity:size * 2];
    for (NSUInteger i = 0; i < size; ++i) [hex appendFormat:@"%02x", out[i]];
    return hex;
}

- (NSString *)hashOfSelection:(NppDigest)digest {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSData *slice = (b > a && (NSUInteger)b <= doc.length)
        ? [doc subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a))]
        : doc;                                   // no selection: hash the document
    return [EditorController hashOfData:slice digest:digest];
}

- (NSString *)hashOfFiles:(NSArray<NSString *> *)paths digest:(NppDigest)digest {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        [lines addObject:[NSString stringWithFormat:@"%@  %@",
                          [EditorController hashOfData:data digest:digest], path]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - Macros

// Scintilla reports each recordable action through SCN_MACRORECORD; the steps
// are kept here and replayed verbatim.
static const char kMacroStepsKey = 0;
static const char kMacroRecordingKey = 0;
static const char kSavedMacrosKey = 0;

- (NSMutableArray *)macroSteps {
    NSMutableArray *steps = objc_getAssociatedObject(self, &kMacroStepsKey);
    if (!steps) {
        steps = [NSMutableArray array];
        objc_setAssociatedObject(self, &kMacroStepsKey, steps, OBJC_ASSOCIATION_RETAIN);
    }
    return steps;
}

- (BOOL)recordingMacro {
    return [objc_getAssociatedObject(self, &kMacroRecordingKey) boolValue];
}

- (NSUInteger)recordedStepCount { return [self macroSteps].count; }

- (void)startRecordingMacro {
    [[self macroSteps] removeAllObjects];
    objc_setAssociatedObject(self, &kMacroRecordingKey, @YES, OBJC_ASSOCIATION_RETAIN);
    [self.sci message:SCI_STARTRECORD];
    [self refreshChrome];
}

- (void)stopRecordingMacro {
    [self.sci message:SCI_STOPRECORD];
    objc_setAssociatedObject(self, &kMacroRecordingKey, @NO, OBJC_ASSOCIATION_RETAIN);
    [self refreshChrome];
}

/// Called from the notification handler for each recorded action.
- (void)recordMacroMessage:(int)message wParam:(unsigned long)wParam lParam:(long)lParam {
    if (![self recordingMacro]) return;
    // Messages whose lParam is a string must have the text copied now; the
    // pointer Scintilla passes does not outlive the callback.
    NSString *text = nil;
    switch (message) {
        case SCI_REPLACESEL:
        case SCI_ADDTEXT:
        case SCI_INSERTTEXT:
        case SCI_APPENDTEXT:
            if (lParam) text = @((const char *)lParam);
            break;
        default: break;
    }
    [[self macroSteps] addObject:@{@"msg": @(message),
                                   @"w": @(wParam),
                                   @"l": @(lParam),
                                   @"text": text ?: @""}];
}

- (BOOL)playbackMacro:(NSUInteger)times {
    return [self playSteps:[[self macroSteps] copy] times:times];
}

- (BOOL)playSteps:(NSArray *)steps times:(NSUInteger)times {
    if (!steps.count || times == 0) { NSBeep(); return NO; }
    ScintillaView *sci = self.sci;
    [sci message:SCI_BEGINUNDOACTION];
    for (NSUInteger t = 0; t < times; ++t) {
        for (NSDictionary *step in steps) {
            // Steps read from a file are checked before they reach Scintilla.
            if (![step isKindOfClass:[NSDictionary class]] || ![step[@"msg"] isKindOfClass:[NSNumber class]]) continue;
            int msg = [step[@"msg"] intValue];
            NSString *text = step[@"text"];
            if (text.length) {
                [sci setStringProperty:msg parameter:[step[@"w"] longValue] value:text];
            } else {
                [sci message:msg wParam:(uptr_t)[step[@"w"] unsignedLongValue]
                      lParam:(sptr_t)[step[@"l"] longValue]];
            }
        }
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    return YES;
}

- (NSString *)savedMacrosPath {
    return [self.defaultSessionPath.stringByDeletingLastPathComponent
            stringByAppendingPathComponent:@"macros.json"];
}

- (NSMutableDictionary *)savedMacros {
    NSMutableDictionary *saved = objc_getAssociatedObject(self, &kSavedMacrosKey);
    if (!saved) {
        // What was saved before this launch, read back: written and never
        // read, a saved macro lasted exactly one session.
        [self reloadSavedMacros];
        saved = objc_getAssociatedObject(self, &kSavedMacrosKey);
    }
    return saved;
}

- (void)reloadSavedMacros {
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    NSData *json = [NSData dataWithContentsOfFile:[self savedMacrosPath]];
    id parsed = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL] : nil;
    if ([parsed isKindOfClass:[NSDictionary class]]) {
        for (NSString *name in parsed) {
            if ([name isKindOfClass:[NSString class]] && [parsed[name] isKindOfClass:[NSArray class]]) {
                saved[name] = parsed[name];
            }
        }
    }
    objc_setAssociatedObject(self, &kSavedMacrosKey, saved, OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)saveRecordedMacroAs:(NSString *)name {
    if (!name.length || ![self macroSteps].count) { NSBeep(); return NO; }
    [self savedMacros][name] = [[self macroSteps] copy];

    // Persist alongside the session so macros survive a restart.
    NSString *path = [self savedMacrosPath];
    NSData *json = [NSJSONSerialization dataWithJSONObject:[self savedMacros]
                                                   options:NSJSONWritingPrettyPrinted error:NULL];
    [json writeToFile:path options:NSDataWritingAtomic error:NULL];
    return YES;
}

- (NSArray<NSDictionary *> *)stepsOfSavedMacroNamed:(NSString *)name {
    id steps = [self savedMacros][name];
    return [steps isKindOfClass:[NSArray class]] ? steps : nil;
}

- (BOOL)playSavedMacroNamed:(NSString *)name {
    NSArray *steps = [self stepsOfSavedMacroNamed:name];
    if (!steps.count) { NSBeep(); return NO; }
    return [self playSteps:steps times:1];
}

- (void)writeSavedMacros {
    NSData *json = [NSJSONSerialization dataWithJSONObject:[self savedMacros]
                                                   options:NSJSONWritingPrettyPrinted error:NULL];
    [json writeToFile:[self savedMacrosPath] options:NSDataWritingAtomic error:NULL];
}

- (BOOL)removeSavedMacroNamed:(NSString *)name {
    if (![self savedMacros][name]) return NO;
    [[self savedMacros] removeObjectForKey:name];
    [self writeSavedMacros];
    return YES;
}

- (void)storeSavedMacro:(NSArray<NSDictionary *> *)steps named:(NSString *)name {
    if (!name.length || !steps) return;
    [self savedMacros][name] = [steps copy];
    [self writeSavedMacros];
}

- (NSArray<NSString *> *)savedMacroNames {
    return [[self savedMacros].allKeys sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Window

- (void)sortTabsBy:(NppTabSort)key ascending:(BOOL)ascending {
    NSMutableArray *docs = (NSMutableArray *)self.documents;
    NppDocument *keep = self.currentDocument;
    NSFileManager *fm = [NSFileManager defaultManager];

    [docs sortUsingComparator:^NSComparisonResult(NppDocument *a, NppDocument *b) {
        NSComparisonResult r = NSOrderedSame;
        switch (key) {
            case NppTabSortName:
                r = [a.displayName localizedStandardCompare:b.displayName];
                break;
            case NppTabSortPath:
                r = [(a.path ?: @"") localizedStandardCompare:(b.path ?: @"")];
                break;
            case NppTabSortType:
                r = [a.displayName.pathExtension localizedStandardCompare:b.displayName.pathExtension];
                if (r == NSOrderedSame) r = [a.displayName localizedStandardCompare:b.displayName];
                break;
            case NppTabSortContentLength: {
                unsigned long long sa = [[fm attributesOfItemAtPath:(a.path ?: @"") error:NULL] fileSize];
                unsigned long long sb = [[fm attributesOfItemAtPath:(b.path ?: @"") error:NULL] fileSize];
                r = sa == sb ? NSOrderedSame : (sa < sb ? NSOrderedAscending : NSOrderedDescending);
                break;
            }
            case NppTabSortModifiedTime: {
                NSDate *da = [[fm attributesOfItemAtPath:(a.path ?: @"") error:NULL] fileModificationDate];
                NSDate *db = [[fm attributesOfItemAtPath:(b.path ?: @"") error:NULL] fileModificationDate];
                if (!da && !db) r = NSOrderedSame;
                else if (!da) r = NSOrderedAscending;
                else if (!db) r = NSOrderedDescending;
                else r = [da compare:db];
                break;
            }
        }
        return ascending ? r : (NSComparisonResult)(-(NSInteger)r);
    }];

    NSUInteger idx = [docs indexOfObject:keep];
    [self selectDocumentAtIndex:(idx == NSNotFound ? 0 : (NSInteger)idx)];
}

- (NSArray<NSString *> *)windowList {
    NSMutableArray *out = [NSMutableArray array];
    for (NppDocument *d in self.documents) [out addObject:d.path ?: d.displayName];
    return out;
}

/// Notepad++'s Recent Window steps back to the previously active tab.
static const char kPreviousTabKey = 0;

- (BOOL)activateRecentWindow {
    // A document rather than an index: tabs closed since it was remembered
    // would have shifted an index onto the wrong tab.
    NppDocument *prev = objc_getAssociatedObject(self, &kPreviousTabKey);
    NppDocument *current = self.currentDocument;
    NSUInteger where = prev ? [self.documents indexOfObject:prev] : NSNotFound;
    if (where == NSNotFound || prev == current) {
        NSBeep();
        return NO;
    }
    [self selectDocumentAtIndex:(NSInteger)where];
    objc_setAssociatedObject(self, &kPreviousTabKey, current, OBJC_ASSOCIATION_RETAIN);
    return YES;
}

- (NppDocument *)previousTab {
    return objc_getAssociatedObject(self, &kPreviousTabKey);
}

- (void)rememberPreviousTab:(NppDocument *)doc {
    objc_setAssociatedObject(self, &kPreviousTabKey, doc, OBJC_ASSOCIATION_RETAIN);
}

#pragma mark - Run

- (NSString *)runShellCommand:(NSString *)command {
    if (!command.length) return nil;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[@"-c", command];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    // -waitUntilExit spins the run loop. On the main thread that re-enters
    // AppKit mid-command, which can raise inside a CATransaction observer and
    // abort the process, so completion is awaited on a semaphore instead.
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *t) { dispatch_semaphore_signal(finished); };

    NSError *err = nil;
    if (![task launchAndReturnError:&err]) return nil;

    // readDataToEndOfFile blocks on the pipe, not on the run loop.
    NSData *out = [pipe.fileHandleForReading readDataToEndOfFile];
    dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    return [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] ?: @"";
}

/// Notepad++ validates shortcuts.xml; here the equivalent is the app's own
/// keyboard shortcuts, checked for duplicates.
- (NSString *)validateShortcutsFile {
    NSMutableDictionary *seen = [NSMutableDictionary dictionary];
    NSMutableArray *clashes = [NSMutableArray array];
    NSUInteger counted = 0;

    NSMutableArray *queue = [NSMutableArray arrayWithArray:NSApp.mainMenu.itemArray];
    while (queue.count) {
        NSMenuItem *item = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (item.submenu) [queue addObjectsFromArray:item.submenu.itemArray];
        if (!item.keyEquivalent.length) continue;
        counted++;
        NSString *key = [NSString stringWithFormat:@"%lu-%@",
                         (unsigned long)item.keyEquivalentModifierMask, item.keyEquivalent];
        NSString *existing = seen[key];
        if (existing) [clashes addObject:[NSString stringWithFormat:@"%@ clashes with %@ (%@)",
                                          item.title, existing, item.keyEquivalent]];
        else seen[key] = item.title;
    }
    if (!clashes.count) {
        return [NSString stringWithFormat:@"%lu shortcuts, no duplicates.", (unsigned long)counted];
    }
    return [NSString stringWithFormat:@"%lu shortcuts, %lu duplicate(s):\n%@",
            (unsigned long)counted, (unsigned long)clashes.count,
            [clashes componentsJoinedByString:@"\n"]];
}

#pragma mark - Help / info

- (NSString *)debugInfo {
    NSProcessInfo *pi = [NSProcessInfo processInfo];
#if defined(__arm64__)
    NSString *arch = @"arm64";
#elif defined(__x86_64__)
    NSString *arch = @"x86_64";
#else
    NSString *arch = @"unknown";
#endif
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    return [NSString stringWithFormat:
        @"NotepadMac %@ (build %@)\n"
        @"Architecture: %@\n"
        @"macOS: %@\n"
        @"Scintilla document count: %lu\n"
        @"Language definitions: loaded from langs.model.xml\n",
        info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?",
        arch, pi.operatingSystemVersionString, (unsigned long)self.documents.count];
}

- (NSString *)commandLineArgumentsHelp {
    return @"NotepadMac accepts file paths as arguments:\n\n"
           @"    open -a NotepadMac file1.txt file2.txt\n"
           @"    open -a NotepadMac --args -n12 -c3 file.txt\n\n"
           @"The switches Notepad++ takes are taken here too:\n"
           @"    -n<line> -c<column> -p<position>   go there in the file opened last\n"
           @"    -l<language>       set the language of the files opened\n"
           @"    -ro                open the files read-only\n"
           @"    -nosession         do not restore the last session\n"
           @"    -openSession       the files are session files to load\n"
           @"    -r                 open every file under the folders given\n"
           @"    -openFoldersAsWorkspace   open the folders as the workspace\n"
           @"    -monitor           follow the file opened last as it grows\n"
           @"    -alwaysOnTop       keep the window above the others\n"
           @"    -notabbar          hide the tab bar\n"
           @"    -titleAdd=<text>   add text to the window title\n"
           @"    -settingsDir=<dir> read and write settings there for this launch\n"
           @"    -qt=<text> -qf=<file>   open a new document holding the text\n"
           @"    -notepadStyleCmdline    the rest of the line is one file name\n"
           @"    -z                 ignore the next argument\n"
           @"    -multiInst -noPlugin -systemtray -loadingTime -quickPrint   accepted and ignored\n\n"
           @"Environment variables used by the build:\n"
           @"    NPPMAC_TEST=1        run the built-in test suite and exit\n"
           @"    NPPMAC_SELFTEST=1    print a short self-test and exit\n"
           @"    NPPMAC_SNAPSHOT=path render the window to a PNG and exit\n";
}

@end

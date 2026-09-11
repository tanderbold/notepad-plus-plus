#import "AppDelegate.h"
#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#import "Tests.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) EditorController *editor;
@property (nonatomic, copy) NSString *lastSearchTerm;
@end

@implementation AppDelegate

#pragma mark - Launch

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSRect frame = NSMakeRect(0, 0, 1000, 700);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [self.window center];
    self.window.minSize = NSMakeSize(520, 320);

    self.editor = [[EditorController alloc] initWithFrame:frame];
    self.editor.window = self.window;
    self.window.contentView = self.editor.view;

    [self buildMenus];
    [self.editor refreshChrome];

    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.editor.sci];
    [NSApp activateIgnoringOtherApps:YES];

    if (getenv("NPPMAC_TEST")) {
        [self performSelector:@selector(runTestSuite) withObject:nil afterDelay:0.5];
    }
    if (getenv("NPPMAC_SELFTEST")) {
        [self performSelector:@selector(runSelfTest) withObject:nil afterDelay:0.8];
    }
    if (getenv("NPPMAC_SNAPSHOT")) {
        [self performSelector:@selector(writeSnapshot) withObject:nil afterDelay:1.2];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename {
    NSError *err = nil;
    if ([self.editor openFileAtPath:filename error:&err]) return YES;
    if (err) [[NSAlert alertWithError:err] runModal];
    return NO;
}

#pragma mark - Menus

- (NSMenuItem *)item:(NSString *)title action:(SEL)sel key:(NSString *)key
               flags:(NSEventModifierFlags)flags menu:(NSMenu *)menu {
    NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:key];
    if (flags) mi.keyEquivalentModifierMask = flags;
    mi.target = self;
    [menu addItem:mi];
    return mi;
}

- (void)buildMenus {
    NSMenu *bar = [[NSMenu alloc] init];
    NSString *appName = @"NotepadMac";

    // ---- Application menu
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [bar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:[@"About " stringByAppendingString:appName]
                       action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *hide = [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:appName]
                                          action:@selector(hide:) keyEquivalent:@"h"];
    hide.target = NSApp;
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    hideOthers.target = NSApp;
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:appName]
                                          action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    appItem.submenu = appMenu;

    // ---- File
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [bar addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [self item:@"New"      action:@selector(newDocument:) key:@"n" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Open…"    action:@selector(openDocument:) key:@"o" flags:NSEventModifierFlagCommand menu:fileMenu];

    NSMenuItem *recentItem = [fileMenu addItemWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
    NSMenu *recentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    [recentMenu addItemWithTitle:@"Clear Menu" action:@selector(clearRecentDocuments:) keyEquivalent:@""];
    recentItem.submenu = recentMenu;

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Save"     action:@selector(saveDocument:) key:@"s" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Save As…" action:@selector(saveDocumentAs:) key:@"s"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:fileMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Close Tab" action:@selector(closeTab:) key:@"w" flags:NSEventModifierFlagCommand menu:fileMenu];
    fileItem.submenu = fileMenu;

    // ---- Edit
    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [bar addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [self item:@"Undo" action:@selector(undo:) key:@"z" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Redo" action:@selector(redo:) key:@"z"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Cut"   action:@selector(cutText:) key:@"x" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Copy"  action:@selector(copyText:) key:@"c" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Paste" action:@selector(pasteText:) key:@"v" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Select All" action:@selector(selectAllText:) key:@"a" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Duplicate Line" action:@selector(duplicateLine:) key:@"d" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Line Comment" action:@selector(toggleLineComment:) key:@"/" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Block Comment" action:@selector(toggleBlockComment:) key:@"/"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Complete Word" action:@selector(showAutoComplete:) key:@" "
         flags:NSEventModifierFlagControl menu:editMenu];
    editItem.submenu = editMenu;

    // ---- Search
    NSMenuItem *searchItem = [[NSMenuItem alloc] init];
    [bar addItem:searchItem];
    NSMenu *searchMenu = [[NSMenu alloc] initWithTitle:@"Search"];
    [self item:@"Find…"      action:@selector(showFind:) key:@"f" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Find Next"  action:@selector(findNext:) key:@"g" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Find Previous" action:@selector(findPrevious:) key:@"g"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Replace…"   action:@selector(showReplace:) key:@"f"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Go to Line…" action:@selector(goToLine:) key:@"l" flags:NSEventModifierFlagCommand menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Bookmark" action:@selector(toggleBookmark:) key:@"b" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Next Bookmark" action:@selector(nextBookmark:) key:@"b"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Previous Bookmark" action:@selector(previousBookmark:) key:@"b"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:searchMenu];
    [self item:@"Clear All Bookmarks" action:@selector(clearBookmarks:) key:@"" flags:0 menu:searchMenu];
    searchItem.submenu = searchMenu;

    // ---- View
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    [bar addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [self item:@"Zoom In"    action:@selector(zoomIn:) key:@"+" flags:NSEventModifierFlagCommand menu:viewMenu];
    [self item:@"Zoom Out"   action:@selector(zoomOut:) key:@"-" flags:NSEventModifierFlagCommand menu:viewMenu];
    [self item:@"Actual Size" action:@selector(zoomReset:) key:@"0" flags:NSEventModifierFlagCommand menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Word Wrap" action:@selector(toggleWordWrap:) key:@"w"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:viewMenu];
    [self item:@"Show Whitespace" action:@selector(toggleWhitespace:) key:@"i"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Fold" action:@selector(toggleFold:) key:@"." flags:NSEventModifierFlagCommand menu:viewMenu];
    [self item:@"Fold All" action:@selector(foldAll:) key:@"." 
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:viewMenu];
    [self item:@"Unfold All" action:@selector(unfoldAll:) key:@"."
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:viewMenu];
    [self item:@"Fold Current Level" action:@selector(foldCurrent:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Unfold Current Level" action:@selector(unfoldCurrent:) key:@"" flags:0 menu:viewMenu];
    viewItem.submenu = viewMenu;

    // ---- Encoding
    NSMenuItem *encItem = [[NSMenuItem alloc] init];
    [bar addItem:encItem];
    NSMenu *encMenu = [[NSMenu alloc] initWithTitle:@"Encoding"];
    struct { NSString *title; NSStringEncoding enc; BOOL bom; } encodings[] = {
        {@"UTF-8",           NSUTF8StringEncoding,               NO},
        {@"UTF-8-BOM",       NSUTF8StringEncoding,               YES},
        {@"UTF-16 LE BOM",   NSUTF16LittleEndianStringEncoding,  YES},
        {@"UTF-16 BE BOM",   NSUTF16BigEndianStringEncoding,     YES},
        {@"ANSI",            NSISOLatin1StringEncoding,          NO},
    };
    for (size_t i = 0; i < sizeof(encodings)/sizeof(encodings[0]); ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:encodings[i].title
                                                    action:@selector(pickEncoding:) keyEquivalent:@""];
        mi.target = self;
        mi.tag = (NSInteger)i;
        [encMenu addItem:mi];
    }
    [encMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *eolHeader = [encMenu addItemWithTitle:@"EOL Conversion" action:nil keyEquivalent:@""];
    eolHeader.enabled = NO;
    [self item:@"Windows (CR LF)" action:@selector(eolCRLF:) key:@"" flags:0 menu:encMenu];
    [self item:@"Unix (LF)"       action:@selector(eolLF:) key:@"" flags:0 menu:encMenu];
    [self item:@"Classic Mac (CR)" action:@selector(eolCR:) key:@"" flags:0 menu:encMenu];
    encItem.submenu = encMenu;

    // ---- Language (populated from Notepad++'s langs.model.xml)
    NSMenuItem *langItem = [[NSMenuItem alloc] init];
    [bar addItem:langItem];
    NSMenu *langMenu = [[NSMenu alloc] initWithTitle:@"Language"];
    NSArray *langs = [[LanguageCatalog sharedCatalog].allLanguages
        sortedArrayUsingComparator:^NSComparisonResult(NppLanguage *a, NppLanguage *b) {
            return [a.name caseInsensitiveCompare:b.name];
        }];
    for (NppLanguage *lang in langs) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:lang.name
                                                    action:@selector(pickLanguage:) keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = lang.name;
        [langMenu addItem:mi];
    }
    langItem.submenu = langMenu;

    // ---- Window
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [bar addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [self item:@"Next Tab" action:@selector(nextTab:) key:@"]"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:windowMenu];
    [self item:@"Previous Tab" action:@selector(previousTab:) key:@"["
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:windowMenu];
    windowItem.submenu = windowMenu;
    NSApp.windowsMenu = windowMenu;

    NSApp.mainMenu = bar;
}

#pragma mark - Menu validation

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL a = item.action;
    if (a == @selector(pickLanguage:)) {
        item.state = [item.representedObject isEqualToString:self.editor.currentDocument.language.name]
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(toggleWordWrap:)) {
        item.state = [self.editor.sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(toggleWhitespace:)) {
        item.state = [self.editor.sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(undo:)) {
        return [self.editor.sci message:SCI_CANUNDO] != 0;
    } else if (a == @selector(redo:)) {
        return [self.editor.sci message:SCI_CANREDO] != 0;
    } else if (a == @selector(pasteText:)) {
        return [self.editor.sci message:SCI_CANPASTE] != 0;
    } else if (a == @selector(pickEncoding:)) {
        item.state = [item.title isEqualToString:[self.editor encodingDisplayName]]
                     ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

#pragma mark - File actions

- (void)newDocument:(id)sender { [self.editor newDocument]; }

- (void)openDocument:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = NO;
    if ([panel runModal] != NSModalResponseOK) return;
    for (NSURL *url in panel.URLs) {
        NSError *err = nil;
        if (![self.editor openFileAtPath:url.path error:&err] && err) {
            [[NSAlert alertWithError:err] runModal];
        }
    }
}

- (void)saveDocument:(id)sender   { [self.editor saveCurrentDocument]; }
- (void)saveDocumentAs:(id)sender { [self.editor saveCurrentDocumentAs]; }
- (void)closeTab:(id)sender       { [self.editor closeCurrentDocument]; }

- (void)clearRecentDocuments:(id)sender {
    [[NSDocumentController sharedDocumentController] clearRecentDocuments:sender];
}

#pragma mark - Edit actions (routed straight to Scintilla)

- (void)undo:(id)sender        { [self.editor.sci message:SCI_UNDO]; }
- (void)redo:(id)sender        { [self.editor.sci message:SCI_REDO]; }
- (void)cutText:(id)sender     { [self.editor.sci message:SCI_CUT]; }
- (void)copyText:(id)sender    { [self.editor.sci message:SCI_COPY]; }
- (void)pasteText:(id)sender   { [self.editor.sci message:SCI_PASTE]; }
- (void)selectAllText:(id)sender { [self.editor.sci message:SCI_SELECTALL]; }

- (void)duplicateLine:(id)sender { [self.editor.sci message:SCI_LINEDUPLICATE]; }

#pragma mark - View actions

- (void)zoomIn:(id)sender    { [self.editor.sci message:SCI_ZOOMIN]; }
- (void)zoomOut:(id)sender   { [self.editor.sci message:SCI_ZOOMOUT]; }
- (void)zoomReset:(id)sender { [self.editor.sci message:SCI_SETZOOM wParam:0 lParam:0]; }

- (void)toggleWordWrap:(id)sender {
    ScintillaView *sci = self.editor.sci;
    BOOL on = [sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE;
    [sci message:SCI_SETWRAPMODE wParam:(on ? SC_WRAP_NONE : SC_WRAP_WORD) lParam:0];
}

- (void)toggleWhitespace:(id)sender {
    ScintillaView *sci = self.editor.sci;
    BOOL on = [sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE;
    [sci message:SCI_SETVIEWWS wParam:(on ? SCWS_INVISIBLE : SCWS_VISIBLEALWAYS) lParam:0];
}

- (void)pickLanguage:(NSMenuItem *)sender {
    [self.editor setLanguageNamed:sender.representedObject];
}

#pragma mark - Comment / completion

- (void)toggleLineComment:(id)sender  { [self.editor toggleLineComment]; }
- (void)toggleBlockComment:(id)sender { [self.editor toggleBlockComment]; }
- (void)showAutoComplete:(id)sender   { [self.editor showAutoCompletion]; }

#pragma mark - Bookmarks

- (void)toggleBookmark:(id)sender   { [self.editor toggleBookmark]; }
- (void)nextBookmark:(id)sender     { [self.editor nextBookmark]; }
- (void)previousBookmark:(id)sender { [self.editor previousBookmark]; }
- (void)clearBookmarks:(id)sender   { [self.editor clearBookmarks]; }

#pragma mark - Folding

- (void)toggleFold:(id)sender { [self.editor toggleFoldAtCursor]; }
- (void)foldAll:(id)sender    { [self.editor foldAll:YES]; }
- (void)unfoldAll:(id)sender  { [self.editor foldAll:NO]; }
- (void)foldCurrent:(id)sender   { [self.editor foldCurrent:YES]; }
- (void)unfoldCurrent:(id)sender { [self.editor foldCurrent:NO]; }

#pragma mark - Encoding + EOL

- (void)pickEncoding:(NSMenuItem *)sender {
    struct { NSStringEncoding enc; BOOL bom; } table[] = {
        {NSUTF8StringEncoding,              NO},
        {NSUTF8StringEncoding,              YES},
        {NSUTF16LittleEndianStringEncoding, YES},
        {NSUTF16BigEndianStringEncoding,    YES},
        {NSISOLatin1StringEncoding,         NO},
    };
    NSInteger i = sender.tag;
    if (i < 0 || i >= (NSInteger)(sizeof(table)/sizeof(table[0]))) return;
    [self.editor setEncoding:table[i].enc withBOM:table[i].bom];
}

- (void)eolCRLF:(id)sender { [self.editor convertEOLTo:SC_EOL_CRLF]; }
- (void)eolLF:(id)sender   { [self.editor convertEOLTo:SC_EOL_LF]; }
- (void)eolCR:(id)sender   { [self.editor convertEOLTo:SC_EOL_CR]; }

#pragma mark - Tabs

- (void)nextTab:(id)sender {
    NSInteger n = (NSInteger)self.editor.documents.count;
    if (n < 2) return;
    NSInteger cur = [self.editor.documents indexOfObject:self.editor.currentDocument];
    [self.editor selectDocumentAtIndex:(cur + 1) % n];
}

- (void)previousTab:(id)sender {
    NSInteger n = (NSInteger)self.editor.documents.count;
    if (n < 2) return;
    NSInteger cur = [self.editor.documents indexOfObject:self.editor.currentDocument];
    [self.editor selectDocumentAtIndex:(cur - 1 + n) % n];
}

#pragma mark - Search

- (NSString *)promptForString:(NSString *)title default:(NSString *)def {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.stringValue = def ?: @"";
    alert.accessoryView = field;
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    return field.stringValue;
}

- (void)showFind:(id)sender {
    NSString *term = [self promptForString:@"Find" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    [self searchFrom:[self.editor.sci message:SCI_GETCURRENTPOS] forward:YES wrap:YES];
}

- (void)findNext:(id)sender {
    if (!self.lastSearchTerm.length) { [self showFind:sender]; return; }
    [self searchFrom:[self.editor.sci message:SCI_GETCURRENTPOS] forward:YES wrap:YES];
}

- (void)findPrevious:(id)sender {
    if (!self.lastSearchTerm.length) { [self showFind:sender]; return; }
    [self searchFrom:[self.editor.sci message:SCI_GETSELECTIONSTART] forward:NO wrap:YES];
}

/// Returns YES when a match was found and selected.
///
/// SCI_SEARCHINTARGET returns -1 when there is no match and leaves the target
/// range untouched, so the result must be read from the return value. Reading
/// SCI_GETTARGETSTART/END instead reports the range we just set as a hit.
- (BOOL)searchFrom:(long)start forward:(BOOL)forward wrap:(BOOL)wrap {
    ScintillaView *sci = self.editor.sci;
    NSString *term = self.lastSearchTerm;
    if (!term.length) return NO;

    const char *needle = term.UTF8String;
    long needleLen = (long)strlen(needle);
    long docLen = [sci message:SCI_GETLENGTH];

    long found = [self searchTarget:forward ? start : 0
                                 to:forward ? docLen : start
                             needle:needle length:needleLen];

    if (found < 0 && wrap) {
        found = [self searchTarget:forward ? 0 : docLen
                                to:forward ? docLen : 0
                            needle:needle length:needleLen];
    }
    if (found < 0) { NSBeep(); return NO; }

    // Backwards: SCI_SEARCHINTARGET reports the first hit in the range, so take
    // the last one before the caret instead.
    if (!forward) {
        long best = found, probe = found;
        while (probe >= 0) {
            long nextStart = probe + 1;
            if (nextStart >= (forward ? docLen : start)) break;
            probe = [self searchTarget:nextStart to:start needle:needle length:needleLen];
            if (probe >= 0) best = probe;
        }
        found = best;
    }

    [sci message:SCI_SETSEL wParam:(uptr_t)found lParam:found + needleLen];
    [sci message:SCI_SCROLLCARET];
    return YES;
}

/// One SCI_SEARCHINTARGET pass; returns the match position or -1.
- (long)searchTarget:(long)from to:(long)to needle:(const char *)needle length:(long)len {
    ScintillaView *sci = self.editor.sci;
    [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from lParam:0];
    [sci message:SCI_SETTARGETEND wParam:(uptr_t)to lParam:0];
    [sci message:SCI_SETSEARCHFLAGS wParam:0 lParam:0];
    return [sci message:SCI_SEARCHINTARGET wParam:(uptr_t)len lParam:(sptr_t)needle];
}

- (void)showReplace:(id)sender {
    NSString *term = [self promptForString:@"Replace — find what?" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    NSString *with = [self promptForString:@"Replace with" default:@""];
    if (!with) return;

    ScintillaView *sci = self.editor.sci;
    long count = 0;
    [sci message:SCI_SETSEL wParam:0 lParam:0];
    [sci message:SCI_BEGINUNDOACTION];
    while ([self searchFrom:[sci message:SCI_GETSELECTIONEND] forward:YES wrap:NO]) {
        // searchFrom left the target on the match, so replace it directly.
        [sci setStringProperty:SCI_REPLACETARGET parameter:(long)strlen(with.UTF8String) value:with];
        long end = [sci message:SCI_GETTARGETEND];
        [sci message:SCI_SETSEL wParam:(uptr_t)end lParam:end];
        count++;
        if (count > 100000) break;   // pathological guard
    }
    [sci message:SCI_ENDUNDOACTION];
    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = [NSString stringWithFormat:@"%ld replacement%@ made", count, count == 1 ? @"" : @"s"];
    [done runModal];
    [self.editor refreshChrome];
}

- (void)goToLine:(id)sender {
    NSString *s = [self promptForString:@"Go to line" default:@""];
    if (!s.length) return;
    long line = s.integerValue - 1;
    if (line < 0) return;
    [self.editor.sci message:SCI_GOTOLINE wParam:(uptr_t)line lParam:0];
    [self.editor refreshChrome];
}

#pragma mark - Test suite

- (void)runTestSuite {
    int failures = NppMacRunTests(self);
    fflush(stdout);
    exit(failures == 0 ? 0 : 1);   // exit code carries the result to CI
}

#pragma mark - Snapshot

/// Renders the window's content view straight to a PNG. This deliberately does
/// not go through screencapture(1), which needs Screen Recording permission and
/// silently returns a desktop with no windows when it is not granted.
///
/// Caveat: cacheDisplayInRect: captures Scintilla (which draws itself) but not
/// the text of AppKit controls, so the tab bar and status bar come out blank.
/// Their contents are covered by the self-test instead.
- (void)writeSnapshot {
    const char *dest = getenv("NPPMAC_SNAPSHOT");
    if (!dest) { [NSApp terminate:nil]; return; }

    // Give the caller something worth looking at rather than an empty buffer.
    NSString *sample = getenv("NPPMAC_SNAPSHOT_FILE")
        ? @(getenv("NPPMAC_SNAPSHOT_FILE")) : nil;
    if (sample.length) {
        NSError *err = nil;
        if (![self.editor openFileAtPath:sample error:&err]) {
            fprintf(stderr, "snapshot: cannot open %s\n", sample.UTF8String);
        }
    }
    [self.editor refreshChrome];
    [self.editor.view displayIfNeeded];

    NSView *view = self.window.contentView;

    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

    if ([png writeToFile:@(dest) atomically:YES]) {
        printf("SNAPSHOT wrote %s (%.0fx%.0f)\n", dest, view.bounds.size.width, view.bounds.size.height);
    } else {
        fprintf(stderr, "SNAPSHOT failed to write %s\n", dest);
    }
    [NSApp terminate:nil];
}

#pragma mark - Self-test

- (void)runSelfTest {
    LanguageCatalog *langs = [LanguageCatalog sharedCatalog];
    StyleCatalog *styles = [StyleCatalog sharedCatalog];

    printf("SELFTEST languages_loaded=%lu\n", (unsigned long)langs.allLanguages.count);
    printf("SELFTEST cpp_styles_loaded=%lu\n",
           (unsigned long)[styles stylesForLexerName:@"cpp"].count);
    printf("SELFTEST global_styles_loaded=%lu\n", (unsigned long)styles.globalStyles.count);

    // Extension -> language -> lexer, straight from Notepad++'s own data.
    NSArray *probes = @[@"a.cpp", @"b.py", @"c.rs", @"d.json", @"e.sh", @"f.unknownext"];
    for (NSString *p in probes) {
        NppLanguage *l = [langs languageForFileName:p];
        printf("SELFTEST detect %-14s -> lang=%-10s lexer=%s\n",
               p.UTF8String, l.name.UTF8String, l.lexerID.UTF8String);
    }

    // Open a real file through the normal path and confirm it lexes.
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"nppmac_selftest.py"];
    [@"# comment\ndef f(x):\n    return x + 1\n" writeToFile:tmp atomically:YES
                                                  encoding:NSUTF8StringEncoding error:NULL];
    NSError *err = nil;
    BOOL opened = [self.editor openFileAtPath:tmp error:&err];
    printf("SELFTEST open_file=%s tabs=%lu lang=%s\n",
           opened ? "OK" : "FAIL",
           (unsigned long)self.editor.documents.count,
           self.editor.currentDocument.language.name.UTF8String);

    ScintillaView *sci = self.editor.sci;
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    long style0 = [sci message:SCI_GETSTYLEAT wParam:0];
    printf("SELFTEST python_comment_style=%ld (SCE_P_COMMENTLINE=%d) match=%s\n",
           style0, SCE_P_COMMENTLINE, style0 == SCE_P_COMMENTLINE ? "YES" : "NO");

    // Search must find a known token.
    self.lastSearchTerm = @"return";
    BOOL found = [self searchFrom:0 forward:YES wrap:YES];
    printf("SELFTEST search_found=%s\n", found ? "YES" : "NO");

    // The snapshot cannot capture AppKit control text, so assert the chrome here.
    for (NSUInteger i = 0; i < self.editor.documents.count; ++i) {
        printf("SELFTEST tab[%lu]=\"%s\"\n", (unsigned long)i,
               self.editor.documents[i].displayName.UTF8String);
    }
    NSString *status = [self.editor valueForKey:@"statusField"]
        ? [(NSTextField *)[self.editor valueForKey:@"statusField"] stringValue] : @"";
    printf("SELFTEST status_nonempty=%s fields=%s\n",
           status.length ? "YES" : "NO",
           ([status containsString:@"Ln "] && [status containsString:@"lines"]) ? "OK" : "MISSING");

    printf("SELFTEST menus=%ld\n", (long)NSApp.mainMenu.numberOfItems);
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
    [NSApp terminate:nil];
}

@end

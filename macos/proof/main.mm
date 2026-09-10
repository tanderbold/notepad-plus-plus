// Minimal proof: Notepad++'s editing engine (Scintilla + Cocoa + Lexilla) running natively on macOS.
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#include "ILexer.h"
#include "Lexilla.h"
#include "SciLexer.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) ScintillaView *sci;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSRect frame = NSMakeRect(0, 0, 900, 640);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [self.window setTitle:@"Notepad++ engine on macOS — Scintilla/Cocoa + Lexilla"];
    [self.window center];

    self.sci = [[ScintillaView alloc] initWithFrame:frame];
    [self.window setContentView:self.sci];

    // Attach the C++ lexer from Lexilla, exactly as Notepad++ does on Windows.
    void *lexer = CreateLexer("cpp");
    [self.sci setReferenceProperty:SCI_SETILEXER parameter:NULL value:lexer];
    [self.sci setStringProperty:SCI_SETKEYWORDS parameter:0 value:@"int char void if else for while return struct class const static"];

    // Styling: line numbers + a few token colours.
    [self.sci setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:@"Menlo"];
    [self.sci setColorProperty:SCI_STYLESETFORE parameter:SCE_C_COMMENTLINE value:[NSColor systemGreenColor]];
    [self.sci setColorProperty:SCI_STYLESETFORE parameter:SCE_C_WORD        value:[NSColor systemBlueColor]];
    [self.sci setColorProperty:SCI_STYLESETFORE parameter:SCE_C_STRING      value:[NSColor systemBrownColor]];
    [self.sci setColorProperty:SCI_STYLESETFORE parameter:SCE_C_NUMBER      value:[NSColor systemPurpleColor]];
    [self.sci setGeneralProperty:SCI_SETMARGINTYPEN parameter:0 value:SC_MARGIN_NUMBER];
    [self.sci setGeneralProperty:SCI_SETMARGINWIDTHN parameter:0 value:44];

    [self.sci setString:
        @"// Scintilla + Lexilla running natively on macOS (arm64).\n"
        @"// Same editing engine Notepad++ uses on Windows.\n"
        @"#include <stdio.h>\n\n"
        @"int main(void) {\n"
        @"    const char *msg = \"syntax highlighting works\";\n"
        @"    for (int i = 0; i < 42; ++i)\n"
        @"        printf(\"%s\\n\", msg);\n"
        @"    return 0;\n"
        @"}\n"];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    // Headless verification mode: report engine state, then exit.
    if (getenv("NPPMAC_SELFTEST")) {
        [self performSelector:@selector(selfTest) withObject:nil afterDelay:1.0];
    }
}

- (void)selfTest {
    long len   = [self.sci getGeneralProperty:SCI_GETLENGTH];
    long lines = [self.sci getGeneralProperty:SCI_GETLINECOUNT];
    // Force the lexer to style the whole buffer, then read back a styled byte.
    [self.sci setGeneralProperty:SCI_COLOURISE parameter:0 value:-1];
    long styleAtComment = [self.sci getGeneralProperty:SCI_GETSTYLEAT parameter:2];
    printf("SELFTEST doc_bytes=%ld lines=%ld style_at_offset2=%ld (SCE_C_COMMENTLINE=%d)\n",
           len, lines, styleAtComment, SCE_C_COMMENTLINE);
    printf("SELFTEST lexer_attached=%s\n", styleAtComment == SCE_C_COMMENTLINE ? "YES" : "NO");
    [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *d = [[AppDelegate alloc] init];
        [app setDelegate:d];
        [app run];
    }
    return 0;
}

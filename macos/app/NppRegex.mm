#import "NppRegex.h"
#include <dlfcn.h>

// libpcre2 is on every macOS that matters, but there is no pcre2.h in the SDK,
// so the handful of entry points that are needed are declared here. They are
// the 8-bit variants, which is what the _8 suffix means.
typedef void *(*npp_pcre2_compile)(const uint8_t *pattern, size_t length, uint32_t options,
                                   int *errorcode, size_t *erroroffset, void *context);
typedef void *(*npp_pcre2_match_data_create_from_pattern)(const void *code, void *context);
typedef int (*npp_pcre2_match)(const void *code, const uint8_t *subject, size_t length,
                               size_t startoffset, uint32_t options,
                               void *matchData, void *context);
typedef size_t *(*npp_pcre2_get_ovector_pointer)(void *matchData);
typedef void (*npp_pcre2_match_data_free)(void *matchData);
typedef void (*npp_pcre2_code_free)(void *code);
typedef int (*npp_pcre2_get_error_message)(int errorcode, uint8_t *buffer, size_t length);

// The option values are those of PCRE2 10.x. They are checked against the
// library's own behaviour by a test, rather than being trusted from memory.
static const uint32_t kDotAll = 0x00000020u;
static const uint32_t kMultiline = 0x00000400u;
static const uint32_t kUTF = 0x00080000u;

static npp_pcre2_compile gCompile;
static npp_pcre2_match_data_create_from_pattern gMatchDataCreate;
static npp_pcre2_match gMatch;
static npp_pcre2_get_ovector_pointer gOvector;
static npp_pcre2_match_data_free gMatchDataFree;
static npp_pcre2_code_free gCodeFree;
static npp_pcre2_get_error_message gErrorMessage;
static BOOL gLoaded;

static void LoadPCRE2(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/usr/lib/libpcre2-8.dylib", RTLD_LAZY);
        if (!handle) return;
        gCompile = (npp_pcre2_compile)dlsym(handle, "pcre2_compile_8");
        gMatchDataCreate = (npp_pcre2_match_data_create_from_pattern)
            dlsym(handle, "pcre2_match_data_create_from_pattern_8");
        gMatch = (npp_pcre2_match)dlsym(handle, "pcre2_match_8");
        gOvector = (npp_pcre2_get_ovector_pointer)dlsym(handle, "pcre2_get_ovector_pointer_8");
        gMatchDataFree = (npp_pcre2_match_data_free)dlsym(handle, "pcre2_match_data_free_8");
        gCodeFree = (npp_pcre2_code_free)dlsym(handle, "pcre2_code_free_8");
        gErrorMessage = (npp_pcre2_get_error_message)dlsym(handle, "pcre2_get_error_message_8");
        gLoaded = gCompile && gMatchDataCreate && gMatch && gOvector &&
                  gMatchDataFree && gCodeFree;
    });
}

@interface NppRegex ()
@property (nonatomic) void *code;
@end

@implementation NppRegex

+ (BOOL)available { LoadPCRE2(); return gLoaded; }

/// Compiles, returning either the code or the reason it would not compile.
static void *CompilePattern(NSString *pattern, NSString **errorOut) {
    LoadPCRE2();
    if (!gLoaded) {
        if (errorOut) *errorOut = @"libpcre2 is not available";
        return NULL;
    }
    NSData *bytes = [pattern dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes) {
        if (errorOut) *errorOut = @"the pattern is not valid UTF-8";
        return NULL;
    }

    int errorCode = 0;
    size_t errorOffset = 0;
    // The same options upstream searches with: SCFIND_REGEXP_DOTMATCHESNL, and
    // '^' anchored per line. See functionParser.cpp.
    void *code = gCompile((const uint8_t *)bytes.bytes, bytes.length,
                          kMultiline | kDotAll | kUTF, &errorCode, &errorOffset, NULL);
    if (!code && errorOut) {
        uint8_t message[256] = {0};
        if (gErrorMessage) gErrorMessage(errorCode, message, sizeof message);
        *errorOut = [NSString stringWithFormat:@"%s (at offset %zu)", message, errorOffset];
    }
    return code;
}

+ (NSString *)compileErrorForPattern:(NSString *)pattern {
    NSString *error = nil;
    void *code = CompilePattern(pattern, &error);
    if (code) { gCodeFree(code); return nil; }
    return error ?: @"the pattern would not compile";
}

+ (instancetype)regexWithPattern:(NSString *)pattern {
    if (!pattern.length) return nil;

    // The catalogue runs the same few patterns against every document, and a
    // name pattern runs once per match, so compiling is worth doing once.
    static NSMutableDictionary<NSString *, id> *cache;
    static dispatch_once_t once;
    static NSLock *lock;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; lock = [NSLock new]; });

    [lock lock];
    id cached = cache[pattern];
    [lock unlock];
    if (cached) return cached == [NSNull null] ? nil : cached;

    void *code = CompilePattern(pattern, NULL);
    NppRegex *regex = nil;
    if (code) {
        regex = [[NppRegex alloc] init];
        regex.code = code;
    }
    [lock lock];
    cache[pattern] = regex ?: (id)[NSNull null];
    [lock unlock];
    return regex;
}

- (void)dealloc {
    // Instances live in the cache for the life of the process, so this runs only
    // if one is discarded; freeing is still the right thing to do.
    if (_code && gCodeFree) gCodeFree(_code);
}

/// Steps past one UTF-8 character, so an empty match cannot stall the loop and
/// cannot leave the offset inside a character.
static size_t NextCharacter(const uint8_t *bytes, size_t length, size_t from) {
    size_t i = from + 1;
    while (i < length && (bytes[i] & 0xC0) == 0x80) ++i;
    return i;
}

- (void)enumerateMatchesInData:(NSData *)data range:(NSRange)range
                    usingBlock:(void (^)(NSRange, BOOL *))block {
    if (!self.code || !data.length || !block) return;
    if (NSMaxRange(range) > data.length) return;

    void *matchData = gMatchDataCreate(self.code, NULL);
    if (!matchData) return;

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    size_t end = NSMaxRange(range);
    size_t at = range.location;
    BOOL stop = NO;

    while (at <= end && !stop) {
        // The subject is cut at `end` so a match cannot run past the range it
        // was asked for -- which is how a class body is kept to itself.
        int rc = gMatch(self.code, bytes, end, at, 0, matchData, NULL);
        if (rc < 0) break;

        size_t *ovector = gOvector(matchData);
        size_t start = ovector[0], finish = ovector[1];
        if (start > end) break;

        block(NSMakeRange(start, finish - start), &stop);
        at = (finish > start) ? finish : NextCharacter(bytes, end, start);
    }

    gMatchDataFree(matchData);
}

- (NSRange)firstNonEmptyMatchInData:(NSData *)data range:(NSRange)range {
    __block NSRange found = NSMakeRange(NSNotFound, 0);
    [self enumerateMatchesInData:data range:range usingBlock:^(NSRange m, BOOL *stop) {
        if (!m.length) return;
        found = m;
        *stop = YES;
    }];
    return found;
}

- (NSRange)firstMatchInData:(NSData *)data range:(NSRange)range {
    __block NSRange found = NSMakeRange(NSNotFound, 0);
    [self enumerateMatchesInData:data range:range usingBlock:^(NSRange m, BOOL *stop) {
        found = m;
        *stop = YES;
    }];
    return found;
}

@end

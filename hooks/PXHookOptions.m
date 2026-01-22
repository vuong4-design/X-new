#import "PXHookOptions.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import "PXHookKeys.h"

#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

CFStringRef const kPXHookPrefsChangedNotification = CFSTR("com.projectx.hookprefs.changed");

static NSDictionary *gPXPrefs = nil;

// Dedicated lock for prefs access.
// Do NOT synchronize on a class name (e.g. [PXHookOptions class]) because this
// file is C-function based and may not declare such an Objective-C class.
static NSObject *PXPrefsLock(void) {
    static NSObject *lockObj = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lockObj = [NSObject new];
    });
    return lockObj;
}

static NSString * const kPXHookPrefsDomain = @"com.projectx.hookprefs";
// Keep in sync with PXHookPrefsStore (common/PXHookPrefsStore.m)
static NSString * const kPXHookPrefsGlobalKey = @"GlobalOptions";
static NSString * const kPXHookPrefsPerAppKey = @"PerAppOptions";
// Canonical path written by ProjectX UI app
static NSString * const kPXHookPrefsPlistPath = @"/var/mobile/Library/Preferences/com.projectx.hookprefs.plist";

static NSDictionary *PXCopyPrefsSnapshot(void) {
    // IMPORTANT:
    // - ProjectX UI writes /var/mobile/Library/Preferences/com.projectx.hookprefs.plist
    // - Using NSUserDefaults initWithSuiteName:@"com.projectx.hookprefs" will often NOT
    //   read that file inside sandboxed app processes, leading to fallback defaults (all ON).
    // So we read the plist file directly first, then fall back to suite if needed.
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:jbroot(kPXHookPrefsPlistPath)];

    NSDictionary *global = nil;
    NSDictionary *perApp = nil;
    if ([root isKindOfClass:[NSDictionary class]]) {
        global = root[kPXHookPrefsGlobalKey];
        perApp = root[kPXHookPrefsPerAppKey];
    }

    if (![global isKindOfClass:[NSDictionary class]] || ![perApp isKindOfClass:[NSDictionary class]]) {
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:kPXHookPrefsDomain];
        if (![global isKindOfClass:[NSDictionary class]]) global = [ud dictionaryForKey:kPXHookPrefsGlobalKey];
        if (![perApp isKindOfClass:[NSDictionary class]]) perApp = [ud dictionaryForKey:kPXHookPrefsPerAppKey];
    }

    if (![global isKindOfClass:[NSDictionary class]]) global = @{};
    if (![perApp isKindOfClass:[NSDictionary class]]) perApp = @{};

    // Merge with defaults so missing keys always have a value
    NSDictionary *defaultGlobal = PXDefaultHookOptions();
    NSMutableDictionary *mergedGlobal = [defaultGlobal mutableCopy];
    [mergedGlobal addEntriesFromDictionary:global];

    return @{
        kPXHookPrefsGlobalKey: mergedGlobal ?: defaultGlobal ?: @{},
        kPXHookPrefsPerAppKey: perApp ?: @{}
    };
}


static void PXLoadPrefsLocked(void) {
    gPXPrefs = PXCopyPrefsSnapshot();
}

void PXReloadHookPrefs(void) {
    @synchronized(PXPrefsLock()) {
        PXLoadPrefsLocked();
    }
}

static NSDictionary *PXPrefs(void) {
    if (gPXPrefs == nil) {
        PXReloadHookPrefs();
    }
    return gPXPrefs ?: @{};
}

BOOL PXHookEnabled(NSString *key) {
    if (key.length == 0) return YES;

    // IMPORTANT: do NOT use -[NSBundle bundleIdentifier] here.
    // Many tweaks (including ours) can hook NSBundle methods. If we call the
    // Objective-C selector, the returned bundle id can be spoofed (causing
    // per-app matching to fail), or we can even trigger recursion/stack overflows
    // when our own Identifier hooks are enabled.
    // Use CoreFoundation APIs instead.
    NSString *bundleID = @"";
    CFBundleRef mainBundle = CFBundleGetMainBundle();
    if (mainBundle) {
        CFStringRef cfBid = CFBundleGetIdentifier(mainBundle);
        if (cfBid) {
            bundleID = [NSString stringWithString:(__bridge NSString *)cfBid];
        }
    }
    NSDictionary *prefs = PXPrefs();

    NSDictionary *global = prefs[kPXHookPrefsGlobalKey];
    NSDictionary *perAppAll = prefs[kPXHookPrefsPerAppKey];
    NSDictionary *perApp = (bundleID.length && [perAppAll isKindOfClass:[NSDictionary class]]) ? perAppAll[bundleID] : nil;

    id v = nil;
    if ([perApp isKindOfClass:[NSDictionary class]]) {
        v = perApp[key];
    }
    if (!v && [global isKindOfClass:[NSDictionary class]]) {
        v = global[key];
    }

    if ([v isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)v boolValue];
    }
    return YES;
}

static void PXPrefsChanged(CFNotificationCenterRef center,
                           void *observer,
                           CFStringRef name,
                           const void *object,
                           CFDictionaryRef userInfo) {
    PXReloadHookPrefs();
}

__attribute__((constructor))
static void PXHookOptionsInit(void) {
    PXReloadHookPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    PXPrefsChanged,
                                    kPXHookPrefsChangedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
}

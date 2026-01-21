#import "PXHookOptions.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>

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

static NSString *PXPrefsPath(void) {
    return jbroot(@"/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist");
}

// Resolve the current process bundle identifier as early and reliably as possible.
// When a dylib is injected very early, `-[NSBundle mainBundle] bundleIdentifier`
// can sometimes be empty temporarily. CFBundleGetIdentifier is typically available
// earlier.
NSString *PXCurrentBundleIdentifier(void) {
    // Backwards-compatible wrapper used by older code paths.
    // Use the shared helper so callers always get a non-nil value.
    return PXSafeBundleIdentifier();
}

static void PXLoadPrefsLocked(void) {
    NSString *path = PXPrefsPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if ([dict isKindOfClass:[NSDictionary class]]) {
        gPXPrefs = dict;
    } else {
        gPXPrefs = @{};
    }
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

	NSString *bundleID = PXCurrentBundleIdentifier() ?: @"";
    NSDictionary *prefs = PXPrefs();

    NSDictionary *global = prefs[@"HookOptions"];
    NSDictionary *perAppAll = prefs[@"PerAppHookOptions"];
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

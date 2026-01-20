#import "PXHookOptions.h"
#import <CoreFoundation/CoreFoundation.h>

#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

CFStringRef const kPXHookPrefsChangedNotification = CFSTR("com.projectx.hookprefs.changed");

static NSDictionary *gPXPrefs = nil;

static NSString *PXPrefsPath(void) {
    return jbroot(@"/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist");
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
    @synchronized([PXHookOptions class]) {
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

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
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

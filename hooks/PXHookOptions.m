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
static NSString * const kPXHookPrefsGlobalKey = @"global";
static NSString * const kPXHookPrefsPerAppKey = @"perApp";

static NSDictionary *PXCopyPrefsSnapshot(void) {
    // Values are stored as individual keys in CFPreferences domain.
    CFPropertyListRef gVal = CFPreferencesCopyAppValue((CFStringRef)kPXHookPrefsGlobalKey, (CFStringRef)kPXHookPrefsDomain);
    CFPropertyListRef pVal = CFPreferencesCopyAppValue((CFStringRef)kPXHookPrefsPerAppKey, (CFStringRef)kPXHookPrefsDomain);

    NSDictionary *global = nil;
    NSDictionary *perAppAll = nil;

    if (gVal) {
        if (CFGetTypeID(gVal) == CFDictionaryGetTypeID()) {
            global = [(__bridge NSDictionary *)gVal copy];
        }
        CFRelease(gVal);
    }
    if (pVal) {
        if (CFGetTypeID(pVal) == CFDictionaryGetTypeID()) {
            perAppAll = [(__bridge NSDictionary *)pVal copy];
        }
        CFRelease(pVal);
    }

    if (![global isKindOfClass:[NSDictionary class]]) global = @{};
    if (![perAppAll isKindOfClass:[NSDictionary class]]) perAppAll = @{};

    // Merge defaults so missing keys are treated as YES.
    NSDictionary *defaults = PXDefaultHookOptions();
    NSMutableDictionary *mergedGlobal = [defaults mutableCopy];
    [mergedGlobal addEntriesFromDictionary:global];

    return @{
        kPXHookPrefsGlobalKey: mergedGlobal,
        kPXHookPrefsPerAppKey: perAppAll
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

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
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

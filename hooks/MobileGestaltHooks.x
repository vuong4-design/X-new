#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <substrate.h>

#import "ProjectXLogging.h"
#import "DataManager.h"
#import "PXHookOptions.h"

#pragma mark - MobileGestalt typedefs

typedef CFTypeRef (*MGCopyAnswerFn)(CFStringRef property);
typedef CFDictionaryRef (*MGCopyMultipleAnswersFn)(CFArrayRef properties, int options);

static MGCopyAnswerFn orig_MGCopyAnswer = NULL;
static MGCopyMultipleAnswersFn orig_MGCopyMultipleAnswers = NULL;

// recursion guard
static __thread BOOL px_mg_in_hook = NO;

#pragma mark - Helpers

static CFStringRef PXCreateCFStringOrNULL(NSString *s) {
    if (!s || s.length == 0) return NULL;
    return (__bridge_retained CFStringRef)[s copy];
}

static CFDataRef PXCreateCFDataFromUUIDStringOrNULL(NSString *uuidString) {
    if (!uuidString || uuidString.length == 0) return NULL;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    if (!uuid) return NULL;

    uuid_t bytes;
    [uuid getUUIDBytes:bytes];
    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)bytes, sizeof(uuid_t));
}

static CFTypeRef PXCreateOverrideForMGKey(NSString *key) {
    PhoneInfo *info = CurrentPhoneInfo();
    if (!info) return NULL;

    DeviceModel *dm = info.deviceModel;
    IosVersion *iv = info.iosVersion;

    // ---- Device model ----
    if ([key isEqualToString:@"ProductType"])
        return PXCreateCFStringOrNULL(dm.modelName);

    if ([key isEqualToString:@"MarketingName"])
        return PXCreateCFStringOrNULL(dm.name);

    if ([key isEqualToString:@"HWModelStr"] ||
        [key isEqualToString:@"HardwareModel"])
        return PXCreateCFStringOrNULL(dm.hwModel);

    // ---- iOS version ----
    if ([key isEqualToString:@"ProductVersion"])
        return PXCreateCFStringOrNULL(iv.version);

    if ([key isEqualToString:@"BuildVersion"])
        return PXCreateCFStringOrNULL(iv.build);

    // ---- Identifiers ----
    if ([key isEqualToString:@"SerialNumber"])
        return PXCreateCFStringOrNULL(info.serialNumber);

    if ([key isEqualToString:@"InternationalMobileEquipmentIdentity"])
        return PXCreateCFStringOrNULL(info.IMEI);

    if ([key isEqualToString:@"MobileEquipmentIdentifier"])
        return PXCreateCFStringOrNULL(info.MEID);

    if ([key isEqualToString:@"UniqueDeviceID"])
        return PXCreateCFStringOrNULL(info.systemBootUUID);

    if ([key isEqualToString:@"UniqueDeviceIDData"])
        return PXCreateCFDataFromUUIDStringOrNULL(info.systemBootUUID);

    if ([key isEqualToString:@"UserAssignedDeviceName"])
        return PXCreateCFStringOrNULL(info.deviceName);

    return NULL;
}

#pragma mark - Hooks

static CFTypeRef hook_MGCopyAnswer(CFStringRef property) {
    if (!orig_MGCopyAnswer || !property)
        return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;

    if (px_mg_in_hook) {
        PXLog(@"[MobileGestalt] ⚠️ Re-entrant MGCopyAnswer, skipping");
        return orig_MGCopyAnswer(property);
    }

    if (!PXHookEnabled(@"devicemodel"))
        return orig_MGCopyAnswer(property);

    px_mg_in_hook = YES;

    @autoreleasepool {
        NSString *key = (__bridge NSString *)property;
        PXLog(@"[MobileGestalt] 🔍 MGCopyAnswer called: %@", key);

        CFTypeRef override = PXCreateOverrideForMGKey(key);
        if (override) {
            PXLog(@"[MobileGestalt] 🎭 Spoofed %@ = %@", key, (__bridge id)override);
            px_mg_in_hook = NO;
            return override; // retained
        }

        PXLog(@"[MobileGestalt] ➡️ Pass-through %@", key);
        CFTypeRef orig = orig_MGCopyAnswer(property);
        px_mg_in_hook = NO;
        return orig;
    }
}

static CFDictionaryRef hook_MGCopyMultipleAnswers(CFArrayRef properties, int options) {
    if (!orig_MGCopyMultipleAnswers || !properties)
        return orig_MGCopyMultipleAnswers ? orig_MGCopyMultipleAnswers(properties, options) : NULL;

    if (px_mg_in_hook)
        return orig_MGCopyMultipleAnswers(properties, options);

    if (!PXHookEnabled(@"devicemodel"))
        return orig_MGCopyMultipleAnswers(properties, options);

    px_mg_in_hook = YES;

    @autoreleasepool {
        CFIndex count = CFArrayGetCount(properties);
        PXLog(@"[MobileGestalt] 📦 MGCopyMultipleAnswers count=%ld", count);

        CFDictionaryRef origDict = orig_MGCopyMultipleAnswers(properties, options);
        CFMutableDictionaryRef out =
            origDict ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, origDict)
                     : CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                        &kCFTypeDictionaryKeyCallBacks,
                        &kCFTypeDictionaryValueCallBacks);

        for (CFIndex i = 0; i < count; i++) {
            CFStringRef keyRef = (CFStringRef)CFArrayGetValueAtIndex(properties, i);
            if (!keyRef) continue;

            NSString *key = (__bridge NSString *)keyRef;
            CFTypeRef override = PXCreateOverrideForMGKey(key);

            if (override) {
                PXLog(@"[MobileGestalt] 🎭 [Multi] %@ = %@", key, (__bridge id)override);
                CFDictionarySetValue(out, keyRef, override);
                CFRelease(override);
            }
        }

        px_mg_in_hook = NO;
        return out; // retained
    }
}

#pragma mark - Init

%group PX_mobilegestalt

%ctor {
    @autoreleasepool {
        void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (!handle) {
            PXLog(@"[MobileGestalt] ❌ Failed to open libMobileGestalt.dylib");
            return;
        }

        void *a = dlsym(handle, "MGCopyAnswer");
        void *m = dlsym(handle, "MGCopyMultipleAnswers");

        if (a) {
            MSHookFunction(a, (void *)hook_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
            PXLog(@"[MobileGestalt] ✅ Hooked MGCopyAnswer");
        }

        if (m) {
            MSHookFunction(m, (void *)hook_MGCopyMultipleAnswers, (void **)&orig_MGCopyMultipleAnswers);
            PXLog(@"[MobileGestalt] ✅ Hooked MGCopyMultipleAnswers");
        }
    }
}

%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init(PX_mobilegestalt);
    }
}

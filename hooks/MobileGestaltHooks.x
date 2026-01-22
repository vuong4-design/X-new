#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <substrate.h>

#import "ProjectXLogging.h"
#import "DataManager.h"
#import "PXHookOptions.h"

#pragma mark - Typedefs

typedef CFTypeRef (*MGCopyAnswerFn)(CFStringRef property);

// iOS 12/13 (phổ biến): options là CFDictionaryRef
typedef CFDictionaryRef (*MGCopyMultipleAnswersDictFn)(CFArrayRef properties, CFDictionaryRef options);

// iOS 14 (phổ biến): options là int flags
typedef CFDictionaryRef (*MGCopyMultipleAnswersIntFn)(CFArrayRef properties, int options);

static MGCopyAnswerFn orig_MGCopyAnswer = NULL;
static MGCopyMultipleAnswersDictFn orig_MGCopyMultipleAnswers_dict = NULL;
static MGCopyMultipleAnswersIntFn  orig_MGCopyMultipleAnswers_int  = NULL;

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

static BOOL PXMGIsWhitelistedKey(NSString *key) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"ProductType",
            @"MarketingName",
            @"HWModelStr",
            @"HardwareModel",
            @"ProductVersion",
            @"BuildVersion",
            @"SerialNumber",
            @"InternationalMobileEquipmentIdentity",
            @"MobileEquipmentIdentifier",
            @"UniqueDeviceID",
            @"UniqueDeviceIDData",
            @"UserAssignedDeviceName",
        ]];
    });
    return [keys containsObject:key];
}

// Trả object retained (Copy rule)
static CFTypeRef PXCreateOverrideForMGKey(NSString *key) {
    if (!PXMGIsWhitelistedKey(key)) return NULL;

    PhoneInfo *info = CurrentPhoneInfo();
    if (!info) return NULL;

    DeviceModel *dm = info.deviceModel;
    IosVersion *iv = info.iosVersion;

    if ([key isEqualToString:@"ProductType"])          return PXCreateCFStringOrNULL(dm.modelName);
    if ([key isEqualToString:@"MarketingName"])        return PXCreateCFStringOrNULL(dm.name);
    if ([key isEqualToString:@"HWModelStr"] ||
        [key isEqualToString:@"HardwareModel"])        return PXCreateCFStringOrNULL(dm.hwModel);

    if ([key isEqualToString:@"ProductVersion"])       return PXCreateCFStringOrNULL(iv.version);
    if ([key isEqualToString:@"BuildVersion"])         return PXCreateCFStringOrNULL(iv.build);

    if ([key isEqualToString:@"SerialNumber"])         return PXCreateCFStringOrNULL(info.serialNumber);
    if ([key isEqualToString:@"InternationalMobileEquipmentIdentity"])
                                                      return PXCreateCFStringOrNULL(info.IMEI);
    if ([key isEqualToString:@"MobileEquipmentIdentifier"])
                                                      return PXCreateCFStringOrNULL(info.MEID);

    if ([key isEqualToString:@"UserAssignedDeviceName"])return PXCreateCFStringOrNULL(info.deviceName);

    if ([key isEqualToString:@"UniqueDeviceID"])       return PXCreateCFStringOrNULL(info.systemBootUUID);
    if ([key isEqualToString:@"UniqueDeviceIDData"])   return PXCreateCFDataFromUUIDStringOrNULL(info.systemBootUUID);

    return NULL;
}

static NSString *PXDescribeCFType(CFTypeRef obj) {
    if (!obj) return @"<null>";
    CFTypeID t = CFGetTypeID(obj);
    if (t == CFStringGetTypeID()) return (__bridge NSString *)obj;
    if (t == CFNumberGetTypeID()) return [(__bridge NSNumber *)obj stringValue];
    if (t == CFDataGetTypeID())   return [NSString stringWithFormat:@"<CFData %ld bytes>", (long)CFDataGetLength((CFDataRef)obj)];
    if (t == CFBooleanGetTypeID())return CFBooleanGetValue((CFBooleanRef)obj) ? @"true" : @"false";
    return [NSString stringWithFormat:@"<CFType %lu>", (unsigned long)t];
}

#pragma mark - MGCopyAnswer Hook

static CFTypeRef hook_MGCopyAnswer(CFStringRef property) {
    if (!orig_MGCopyAnswer || !property) return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;

    if (px_mg_in_hook) {
        PXLog(@"[MobileGestalt] ⚠️ Re-entrant MGCopyAnswer, skipping");
        return orig_MGCopyAnswer(property);
    }
    if (!PXHookEnabled(@"devicemodel")) return orig_MGCopyAnswer(property);

    px_mg_in_hook = YES;
    @autoreleasepool {
        NSString *key = (__bridge NSString *)property;

        // Log gọi (nhẹ) - có thể comment nếu spam
        PXLog(@"[MobileGestalt] 🔍 MGCopyAnswer called: %@", key);

        CFTypeRef override = PXCreateOverrideForMGKey(key);
        if (override) {
            PXLog(@"[MobileGestalt] 🎭 Spoofed %@ = %@", key, PXDescribeCFType(override));
            px_mg_in_hook = NO;
            return override; // retained
        }

        CFTypeRef orig = orig_MGCopyAnswer(property);
        px_mg_in_hook = NO;
        return orig;
    }
}

#pragma mark - MGCopyMultipleAnswers Hooks (2 variants)

static CFDictionaryRef hook_MGCopyMultipleAnswers_dict(CFArrayRef properties, CFDictionaryRef options) {
    if (!orig_MGCopyMultipleAnswers_dict || !properties)
        return orig_MGCopyMultipleAnswers_dict ? orig_MGCopyMultipleAnswers_dict(properties, options) : NULL;

    if (px_mg_in_hook) return orig_MGCopyMultipleAnswers_dict(properties, options);
    if (!PXHookEnabled(@"devicemodel")) return orig_MGCopyMultipleAnswers_dict(properties, options);

    px_mg_in_hook = YES;
    @autoreleasepool {
        CFIndex count = CFArrayGetCount(properties);
        PXLog(@"[MobileGestalt] 📦 MGCopyMultipleAnswers(dict) count=%ld", (long)count);

        CFDictionaryRef origDict = orig_MGCopyMultipleAnswers_dict(properties, options);
        CFMutableDictionaryRef out =
            origDict ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, origDict)
                     : CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                        &kCFTypeDictionaryKeyCallBacks,
                        &kCFTypeDictionaryValueCallBacks);

        for (CFIndex i = 0; i < count; i++) {
            CFTypeRef keyRef = CFArrayGetValueAtIndex(properties, i);
            if (!keyRef || CFGetTypeID(keyRef) != CFStringGetTypeID()) continue;

            NSString *key = (__bridge NSString *)((CFStringRef)keyRef);
            CFTypeRef override = PXCreateOverrideForMGKey(key);
            if (override) {
                PXLog(@"[MobileGestalt] 🎭 [Multi dict] %@ = %@", key, PXDescribeCFType(override));
                CFDictionarySetValue(out, keyRef, override);
                CFRelease(override);
            }
        }

        px_mg_in_hook = NO;
        return out; // retained
    }
}

static CFDictionaryRef hook_MGCopyMultipleAnswers_int(CFArrayRef properties, int options) {
    if (!orig_MGCopyMultipleAnswers_int || !properties)
        return orig_MGCopyMultipleAnswers_int ? orig_MGCopyMultipleAnswers_int(properties, options) : NULL;

    if (px_mg_in_hook) return orig_MGCopyMultipleAnswers_int(properties, options);
    if (!PXHookEnabled(@"devicemodel")) return orig_MGCopyMultipleAnswers_int(properties, options);

    px_mg_in_hook = YES;
    @autoreleasepool {
        CFIndex count = CFArrayGetCount(properties);
        PXLog(@"[MobileGestalt] 📦 MGCopyMultipleAnswers(int) count=%ld options=%d", (long)count, options);

        CFDictionaryRef origDict = orig_MGCopyMultipleAnswers_int(properties, options);
        CFMutableDictionaryRef out =
            origDict ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, origDict)
                     : CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                        &kCFTypeDictionaryKeyCallBacks,
                        &kCFTypeDictionaryValueCallBacks);

        for (CFIndex i = 0; i < count; i++) {
            CFTypeRef keyRef = CFArrayGetValueAtIndex(properties, i);
            if (!keyRef || CFGetTypeID(keyRef) != CFStringGetTypeID()) continue;

            NSString *key = (__bridge NSString *)((CFStringRef)keyRef);
            CFTypeRef override = PXCreateOverrideForMGKey(key);
            if (override) {
                PXLog(@"[MobileGestalt] 🎭 [Multi int] %@ = %@", key, PXDescribeCFType(override));
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

        void *symA = dlsym(handle, "MGCopyAnswer");
        void *symM = dlsym(handle, "MGCopyMultipleAnswers");

        if (symA) {
            MSHookFunction(symA, (void *)hook_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
            PXLog(@"[MobileGestalt] ✅ Hooked MGCopyAnswer");
        } else {
            PXLog(@"[MobileGestalt] ❌ Could not find MGCopyAnswer");
        }

        if (symM) {
            NSInteger major = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;

            // iOS 12/13: dict; iOS 14+: int (thực tế hay gặp)
            if (major >= 14) {
                MSHookFunction(symM, (void *)hook_MGCopyMultipleAnswers_int, (void **)&orig_MGCopyMultipleAnswers_int);
                PXLog(@"[MobileGestalt] ✅ Hooked MGCopyMultipleAnswers (int) for iOS %ld", (long)major);
            } else {
                MSHookFunction(symM, (void *)hook_MGCopyMultipleAnswers_dict, (void **)&orig_MGCopyMultipleAnswers_dict);
                PXLog(@"[MobileGestalt] ✅ Hooked MGCopyMultipleAnswers (dict) for iOS %ld", (long)major);
            }
        } else {
            PXLog(@"[MobileGestalt] ⚠️ MGCopyMultipleAnswers not found (OK)");
        }
    }
}

%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init(PX_mobilegestalt);
    }
}

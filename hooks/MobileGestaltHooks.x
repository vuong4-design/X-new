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

// Thread safety
static pthread_mutex_t px_mg_mutex = PTHREAD_MUTEX_INITIALIZER;

#pragma mark - Helpers

static NSSet<NSString *> *getSpoofableKeys() {
    static NSSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"ProductType", @"MarketingName", @"HWModelStr", @"HardwareModel",
            @"ProductVersion", @"BuildVersion", @"SerialNumber", 
            @"InternationalMobileEquipmentIdentity", @"MobileEquipmentIdentifier",
            @"UniqueDeviceID", @"UniqueDeviceIDData", @"UserAssignedDeviceName"
        ]];
    });
    return keys;
}

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
    
    if ([key isEqualToString:@"ProductType"]) return PXCreateCFStringOrNULL(dm.modelName);
    if ([key isEqualToString:@"MarketingName"]) return PXCreateCFStringOrNULL(dm.name);
    if ([key isEqualToString:@"HWModelStr"] || [key isEqualToString:@"HardwareModel"]) 
        return PXCreateCFStringOrNULL(dm.hwModel);
    if ([key isEqualToString:@"ProductVersion"]) return PXCreateCFStringOrNULL(iv.version);
    if ([key isEqualToString:@"BuildVersion"]) return PXCreateCFStringOrNULL(iv.build);
    if ([key isEqualToString:@"SerialNumber"]) return PXCreateCFStringOrNULL(info.serialNumber);
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
    // Early exits - không cần lock
    if (!orig_MGCopyAnswer) return NULL;
    if (!property) return orig_MGCopyAnswer(property);
    
    // Check enabled WITHOUT autorelease pool
    BOOL hookEnabled = PXHookEnabled(@"devicemodel");
    if (!hookEnabled) {
        return orig_MGCopyAnswer(property);
    }

    NSString *key = (__bridge NSString *)property;
    
    // Quick check nếu không phải key cần fake
    if (![getSpoofableKeys() containsObject:key]) {
        return orig_MGCopyAnswer(property);
    }

    // Bây giờ mới lock và xử lý
    pthread_mutex_lock(&px_mg_mutex);
    
    CFTypeRef result = NULL;
    
    @autoreleasepool {
        CFTypeRef override = PXCreateOverrideForMGKey(key);
        if (override) {
            PXLog(@"[MobileGestalt] 🎭 Spoofed %@ = %@", key, (__bridge id)override);
            result = override; // Already retained
        } else {
            // Gọi original và PHẢI retain
            result = orig_MGCopyAnswer(property);
            if (result) {
                CFRetain(result);
            }
        }
    }
    
    pthread_mutex_unlock(&px_mg_mutex);
    
    return result; // Caller's responsibility to release
}

static CFDictionaryRef hook_MGCopyMultipleAnswers(CFArrayRef properties, int options) {
    // Early exits
    if (!orig_MGCopyMultipleAnswers) return NULL;
    if (!properties) return orig_MGCopyMultipleAnswers(properties, options);
    
    BOOL hookEnabled = PXHookEnabled(@"devicemodel");
    if (!hookEnabled) {
        return orig_MGCopyMultipleAnswers(properties, options);
    }

    pthread_mutex_lock(&px_mg_mutex);
    
    CFDictionaryRef result = NULL;
    
    @autoreleasepool {
        // Gọi original function
        CFDictionaryRef origDict = orig_MGCopyMultipleAnswers(properties, options);
        
        // Tạo mutable copy hoặc dict mới
        CFMutableDictionaryRef out = NULL;
        if (origDict) {
            out = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, origDict);
            CFRelease(origDict); // Release ngay sau khi copy
        } else {
            out = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks);
        }
        
        // Apply overrides
        NSSet *spoofableKeys = getSpoofableKeys();
        CFIndex count = CFArrayGetCount(properties);
        
        for (CFIndex i = 0; i < count; i++) {
            CFStringRef keyRef = (CFStringRef)CFArrayGetValueAtIndex(properties, i);
            if (!keyRef) continue;
            
            NSString *key = (__bridge NSString *)keyRef;
            
            if ([spoofableKeys containsObject:key]) {
                CFTypeRef override = PXCreateOverrideForMGKey(key);
                if (override) {
                    PXLog(@"[MobileGestalt] 🎭 [Multi] %@ = %@", key, (__bridge id)override);
                    CFDictionarySetValue(out, keyRef, override);
                    CFRelease(override); // Dict đã retain
                }
            }
        }
        
        result = out; // Transfer ownership
    }
    
    pthread_mutex_unlock(&px_mg_mutex);
    
    return result;
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
        
        // KHÔNG close handle - libMobileGestalt cần được load suốt
        // dlclose(handle);
    }
}
%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init(PX_mobilegestalt);
    }
}

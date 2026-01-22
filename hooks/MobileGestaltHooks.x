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

static id PXGetOverrideForMGKey(NSString *key) {
    PhoneInfo *info = CurrentPhoneInfo();
    if (!info) return nil;
    
    DeviceModel *dm = info.deviceModel;
    IosVersion *iv = info.iosVersion;
    
    if ([key isEqualToString:@"ProductType"]) return dm.modelName;
    if ([key isEqualToString:@"MarketingName"]) return dm.name;
    if ([key isEqualToString:@"HWModelStr"] || [key isEqualToString:@"HardwareModel"]) 
        return dm.hwModel;
    if ([key isEqualToString:@"ProductVersion"]) return iv.version;
    if ([key isEqualToString:@"BuildVersion"]) return iv.build;
    if ([key isEqualToString:@"SerialNumber"]) return info.serialNumber;
    if ([key isEqualToString:@"InternationalMobileEquipmentIdentity"]) 
        return info.IMEI;
    if ([key isEqualToString:@"MobileEquipmentIdentifier"]) 
        return info.MEID;
    if ([key isEqualToString:@"UniqueDeviceID"]) 
        return info.systemBootUUID;
    if ([key isEqualToString:@"UserAssignedDeviceName"]) 
        return info.deviceName;
    
    if ([key isEqualToString:@"UniqueDeviceIDData"]) {
        if (!info.systemBootUUID || info.systemBootUUID.length == 0) return nil;
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:info.systemBootUUID];
        if (!uuid) return nil;
        uuid_t bytes;
        [uuid getUUIDBytes:bytes];
        return [NSData dataWithBytes:bytes length:sizeof(uuid_t)];
    }
    
    return nil;
}

#pragma mark - Hooks

static CFTypeRef hook_MGCopyAnswer(CFStringRef property) {
    // Safety checks
    if (!orig_MGCopyAnswer || !property) {
        return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
    }
    
    if (!PXHookEnabled(@"devicemodel")) {
        return orig_MGCopyAnswer(property);
    }

    @autoreleasepool {
        NSString *key = (__bridge NSString *)property;
        
        // Chỉ xử lý các key trong whitelist
        if (![getSpoofableKeys() containsObject:key]) {
            return orig_MGCopyAnswer(property);
        }
        
        id override = PXGetOverrideForMGKey(key);
        
        // Nếu không có override, gọi original
        if (!override) {
            return orig_MGCopyAnswer(property);
        }
        
        // Có override - return nó thay vì original
        PXLog(@"[MobileGestalt] 🎭 Spoofed %@ = %@", key, override);
        
        // QUAN TRỌNG: __bridge_retained tạo +1 retain count
        // Caller sẽ release (follow Copy rule)
        return (__bridge_retained CFTypeRef)override;
    }
}

static CFDictionaryRef hook_MGCopyMultipleAnswers(CFArrayRef properties, int options) {
    if (!orig_MGCopyMultipleAnswers || !properties) {
        return orig_MGCopyMultipleAnswers ? orig_MGCopyMultipleAnswers(properties, options) : NULL;
    }
    
    if (!PXHookEnabled(@"devicemodel")) {
        return orig_MGCopyMultipleAnswers(properties, options);
    }

    @autoreleasepool {
        // Gọi original để lấy base dictionary
        CFDictionaryRef originalDict = orig_MGCopyMultipleAnswers(properties, options);
        
        // Tạo mutable dictionary từ original HOẶC tạo mới
        NSMutableDictionary *result;
        if (originalDict) {
            result = [(__bridge NSDictionary *)originalDict mutableCopy];
            // QUAN TRỌNG: Release original vì chúng ta đã copy
            CFRelease(originalDict);
        } else {
            result = [NSMutableDictionary dictionary];
        }
        
        // Apply overrides
        NSSet *spoofableKeys = getSpoofableKeys();
        NSArray *props = (__bridge NSArray *)properties;
        
        for (id keyObj in props) {
            if (![keyObj isKindOfClass:[NSString class]]) continue;
            NSString *key = (NSString *)keyObj;
            
            if ([spoofableKeys containsObject:key]) {
                id override = PXGetOverrideForMGKey(key);
                if (override) {
                    PXLog(@"[MobileGestalt] 🎭 [Multi] %@ = %@", key, override);
                    result[key] = override;
                }
            }
        }
        
        // Return với +1 retain count
        return (__bridge_retained CFDictionaryRef)result;
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

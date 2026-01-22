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

// Trả về NSString thay vì CFStringRef để tránh memory issue
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
    
    // Special case: UniqueDeviceIDData cần CFData
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
    // Luôn gọi original trước
    CFTypeRef originalResult = orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
    
    // Nếu không enable hoặc không có property, return original
    if (!property || !PXHookEnabled(@"devicemodel")) {
        return originalResult;
    }

    @autoreleasepool {
        NSString *key = (__bridge NSString *)property;
        
        // Chỉ xử lý các key trong whitelist
        if (![getSpoofableKeys() containsObject:key]) {
            return originalResult;
        }
        
        id override = PXGetOverrideForMGKey(key);
        if (!override) {
            return originalResult;
        }
        
        PXLog(@"[MobileGestalt] 🎭 Spoofed %@ = %@", key, override);
        
        // Release original nếu có
        if (originalResult) {
            CFRelease(originalResult);
        }
        
        // Return với bridge_retained để match ownership semantics
        return (__bridge_retained CFTypeRef)override;
    }
}

static CFDictionaryRef hook_MGCopyMultipleAnswers(CFArrayRef properties, int options) {
    // Luôn gọi original trước
    CFDictionaryRef originalResult = orig_MGCopyMultipleAnswers 
        ? orig_MGCopyMultipleAnswers(properties, options) 
        : NULL;
    
    if (!properties || !PXHookEnabled(@"devicemodel")) {
        return originalResult;
    }

    @autoreleasepool {
        // Convert sang NSDictionary để dễ xử lý
        NSMutableDictionary *dict = originalResult 
            ? [(__bridge NSDictionary *)originalResult mutableCopy]
            : [NSMutableDictionary dictionary];
        
        NSSet *spoofableKeys = getSpoofableKeys();
        NSArray *props = (__bridge NSArray *)properties;
        
        for (id keyObj in props) {
            if (![keyObj isKindOfClass:[NSString class]]) continue;
            NSString *key = (NSString *)keyObj;
            
            if ([spoofableKeys containsObject:key]) {
                id override = PXGetOverrideForMGKey(key);
                if (override) {
                    PXLog(@"[MobileGestalt] 🎭 [Multi] %@ = %@", key, override);
                    dict[key] = override;
                }
            }
        }
        
        // Release original
        if (originalResult) {
            CFRelease(originalResult);
        }
        
        // Return với bridge_retained
        return (__bridge_retained CFDictionaryRef)dict;
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

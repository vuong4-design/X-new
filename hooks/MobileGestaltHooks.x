#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <substrate.h>
#import "ProjectXLogging.h"
#import "DataManager.h"
#import "PXHookOptions.h"

#pragma mark - Private MobileGestalt Interface

@interface MobileGestalt : NSObject
+ (id)copyAnswer:(NSString *)key;
+ (NSDictionary *)copyMultipleAnswers:(NSArray *)keys options:(int)options;
@end

#pragma mark - C Function Typedefs

typedef CFTypeRef (*MGCopyAnswerFn)(CFStringRef property);
typedef CFDictionaryRef (*MGCopyMultipleAnswersFn)(CFArrayRef properties, int options);

static MGCopyAnswerFn orig_MGCopyAnswer = NULL;
static MGCopyMultipleAnswersFn orig_MGCopyMultipleAnswers = NULL;

#pragma mark - Shared Override Logic

static NSSet<NSString *> *getSpoofableKeys() {
    static NSSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"ProductType", @"MarketingName", @"HWModelStr", @"HardwareModel",
            @"ProductVersion", @"BuildVersion", @"SerialNumber", 
            @"InternationalMobileEquipmentIdentity", @"MobileEquipmentIdentifier",
            @"UniqueDeviceID", @"UniqueDeviceIDData", @"UserAssignedDeviceName",
            // Thêm các key bổ sung mà app có thể query
            @"DeviceClass", @"RegionInfo", @"ModelNumber", @"RegionCode"
        ]];
    });
    return keys;
}

static id PXGetOverrideForMGKey(NSString *key) {
    if (!PXHookEnabled(@"devicemodel")) return nil;
    
    PhoneInfo *info = CurrentPhoneInfo();
    if (!info) return nil;
    
    DeviceModel *dm = info.deviceModel;
    IosVersion *iv = info.iosVersion;
    
    // Device Model
    if ([key isEqualToString:@"ProductType"]) return dm.modelName;
    if ([key isEqualToString:@"MarketingName"]) return dm.name;
    if ([key isEqualToString:@"HWModelStr"] || [key isEqualToString:@"HardwareModel"]) 
        return dm.hwModel;
    
    // iOS Version
    if ([key isEqualToString:@"ProductVersion"]) return iv.version;
    if ([key isEqualToString:@"BuildVersion"]) return iv.build;
    
    // Identifiers
    if ([key isEqualToString:@"SerialNumber"]) return info.serialNumber;
    if ([key isEqualToString:@"InternationalMobileEquipmentIdentity"]) return info.IMEI;
    if ([key isEqualToString:@"MobileEquipmentIdentifier"]) return info.MEID;
    if ([key isEqualToString:@"UniqueDeviceID"]) return info.systemBootUUID;
    if ([key isEqualToString:@"UserAssignedDeviceName"]) return info.deviceName;
    
    // Special: UUID as Data
    if ([key isEqualToString:@"UniqueDeviceIDData"]) {
        if (!info.systemBootUUID) return nil;
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:info.systemBootUUID];
        if (!uuid) return nil;
        uuid_t bytes;
        [uuid getUUIDBytes:bytes];
        return [NSData dataWithBytes:bytes length:sizeof(uuid_t)];
    }
    
    return nil;
}

#pragma mark - Objective-C Method Hooks

%hook MobileGestalt

+ (id)copyAnswer:(NSString *)key {
    id override = PXGetOverrideForMGKey(key);
    if (override) {
        PXLog(@"[MobileGestalt][ObjC] 🎭 Spoofed %@ = %@", key, override);
        return override;
    }
    return %orig;
}

+ (NSDictionary *)copyMultipleAnswers:(NSArray *)keys options:(int)options {
    NSMutableDictionary *result = [%orig mutableCopy];
    if (!result) result = [NSMutableDictionary dictionary];
    
    for (NSString *key in keys) {
        id override = PXGetOverrideForMGKey(key);
        if (override) {
            PXLog(@"[MobileGestalt][ObjC] 🎭 [Multi] %@ = %@", key, override);
            result[key] = override;
        }
    }
    
    return result;
}

%end

#pragma mark - C Function Hooks

static CFTypeRef hooked_MGCopyAnswer(CFStringRef property) {
    if (!orig_MGCopyAnswer || !property) {
        return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
    }
    
    @autoreleasepool {
        NSString *key = (__bridge NSString *)property;
        
        // Chỉ xử lý các key trong whitelist
        if ([getSpoofableKeys() containsObject:key]) {
            id override = PXGetOverrideForMGKey(key);
            if (override) {
                PXLog(@"[MobileGestalt][C] 🎭 Spoofed %@ = %@", key, override);
                return (__bridge_retained CFTypeRef)override;
            }
        }
    }
    
    return orig_MGCopyAnswer(property);
}

static CFDictionaryRef hooked_MGCopyMultipleAnswers(CFArrayRef properties, int options) {
    if (!orig_MGCopyMultipleAnswers || !properties) {
        return orig_MGCopyMultipleAnswers ? orig_MGCopyMultipleAnswers(properties, options) : NULL;
    }
    
    @autoreleasepool {
        CFDictionaryRef originalDict = orig_MGCopyMultipleAnswers(properties, options);
        
        NSMutableDictionary *result;
        if (originalDict) {
            result = [(__bridge NSDictionary *)originalDict mutableCopy];
            CFRelease(originalDict);
        } else {
            result = [NSMutableDictionary dictionary];
        }
        
        NSSet *spoofableKeys = getSpoofableKeys();
        NSArray *props = (__bridge NSArray *)properties;
        
        for (NSString *key in props) {
            if ([spoofableKeys containsObject:key]) {
                id override = PXGetOverrideForMGKey(key);
                if (override) {
                    PXLog(@"[MobileGestalt][C] 🎭 [Multi] %@ = %@", key, override);
                    result[key] = override;
                }
            }
        }
        
        return (__bridge_retained CFDictionaryRef)result;
    }
}

#pragma mark - C Function Hook Installation

%group PX_mobilegestalt_cfunctions

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
            MSHookFunction(a, (void *)hooked_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
            PXLog(@"[MobileGestalt] ✅ Hooked C function MGCopyAnswer");
        } else {
            PXLog(@"[MobileGestalt] ⚠️ Could not find MGCopyAnswer");
        }
        
        if (m) {
            MSHookFunction(m, (void *)hooked_MGCopyMultipleAnswers, (void **)&orig_MGCopyMultipleAnswers);
            PXLog(@"[MobileGestalt] ✅ Hooked C function MGCopyMultipleAnswers");
        } else {
            PXLog(@"[MobileGestalt] ⚠️ Could not find MGCopyMultipleAnswers");
        }
    }
}

%end

#pragma mark - Initialization

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init; // Hook ObjC methods
        %init(PX_mobilegestalt_cfunctions); // Hook C functions
        PXLog(@"[MobileGestalt] ✅ All hooks initialized");
    }
}

#import <Foundation/Foundation.h>
#import "ProjectXLogging.h"
#import "DataManager.h"
#import "PXHookOptions.h"

#pragma mark - Private MobileGestalt Interface

@interface MobileGestalt : NSObject
+ (id)copyAnswer:(NSString *)key;
+ (NSDictionary *)copyMultipleAnswers:(NSArray *)keys options:(int)options;
@end

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
            // Thêm nhiều key hơn
            @"DeviceClass", @"RegionInfo", @"ModelNumber", @"RegionCode",
            @"DeviceName", @"UniqueChipID", @"CPUArchitecture"
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
    if ([key isEqualToString:@"DeviceName"]) return info.deviceName;
    
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
        PXLog(@"[MobileGestalt] 🎭 Spoofed %@ = %@", key, override);
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
            PXLog(@"[MobileGestalt] 🎭 [Multi] %@ = %@", key, override);
            result[key] = override;
        }
    }
    
    return result;
}

%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init;
        PXLog(@"[MobileGestalt] ✅ ObjC hooks initialized");
    }
}

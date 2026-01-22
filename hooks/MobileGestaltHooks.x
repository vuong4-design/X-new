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
    // Test version - chỉ fake 1 key để debug
    if (!orig_MGCopyAnswer || !property) {
        return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
    }
    
    NSString *key = (__bridge NSString *)property;
    
    // CHỈ fake ProductType để test
    if ([key isEqualToString:@"ProductType"]) {
        PXLog(@"[MobileGestalt] 🎭 Test fake ProductType");
        NSString *fake = @"iPhone12,1";
        return (__bridge_retained CFStringRef)fake;
    }
    
    return orig_MGCopyAnswer(property);
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

        if (a) {
            MSHookFunction(a, (void *)hook_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
            PXLog(@"[MobileGestalt] ✅ Hooked MGCopyAnswer");
        }
     
    }
}
%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init(PX_mobilegestalt);
    }
}

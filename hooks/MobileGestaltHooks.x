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

// Giữ lại hàm getSpoofableKeys để quản lý các key cần fake một cách tập trung
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

// Giữ nguyên hàm tạo giá trị fake
static CFTypeRef PXCreateOverrideForMGKey(NSString *key) {
    PhoneInfo *info = CurrentPhoneInfo();
    if (!info) return NULL;
    DeviceModel *dm = info.deviceModel;
    IosVersion *iv = info.iosVersion;
    if ([key isEqualToString:@"ProductType"]) return PXCreateCFStringOrNULL(dm.modelName);
    if ([key isEqualToString:@"MarketingName"]) return PXCreateCFStringOrNULL(dm.name);
    if ([key isEqualToString:@"HWModelStr"] || [key isEqualToString:@"HardwareModel"]) return PXCreateCFStringOrNULL(dm.hwModel);
    if ([key isEqualToString:@"ProductVersion"]) return PXCreateCFStringOrNULL(iv.version);
    if ([key isEqualToString:@"BuildVersion"]) return PXCreateCFStringOrNULL(iv.build);
    if ([key isEqualToString:@"SerialNumber"]) return PXCreateCFStringOrNULL(info.serialNumber);
    if ([key isEqualToString:@"InternationalMobileEquipmentIdentity"]) return PXCreateCFStringOrNULL(info.IMEI);
    if ([key isEqualToString:@"MobileEquipmentIdentifier"]) return PXCreateCFStringOrNULL(info.MEID);
    if ([key isEqualToString:@"UniqueDeviceID"]) return PXCreateCFStringOrNULL(info.systemBootUUID);
    if ([key isEqualToString:@"UniqueDeviceIDData"]) return PXCreateCFDataFromUUIDStringOrNULL(info.systemBootUUID);
    if ([key isEqualToString:@"UserAssignedDeviceName"]) return PXCreateCFStringOrNULL(info.deviceName);
    return NULL;
}

#pragma mark - Hooks (THE GOLDEN VERSION)

static CFTypeRef hook_MGCopyAnswer(CFStringRef property) {
    if (!orig_MGCopyAnswer) return NULL;
    if (!property || !PXHookEnabled(@"devicemodel")) {
        return orig_MGCopyAnswer(property);
    }

    NSString *key = (__bridge NSString *)property;

    // Chỉ khi key nằm trong danh sách cần fake, chúng ta mới xử lý
    if ([getSpoofableKeys() containsObject:key]) {
        // Bên trong khối này mới là logic của bạn
        @autoreleasepool {
            CFTypeRef override = PXCreateOverrideForMGKey(key);
            if (override) {
                PXLog(@"[MobileGestalt] 🎭 Spoofed %@ = %@", key, (__bridge id)override);
                return override; // Retained
            }
        }
    }

    // Với TẤT CẢ các key khác, gọi hàm gốc ngay lập tức
    return orig_MGCopyAnswer(property);
}

static CFDictionaryRef hook_MGCopyMultipleAnswers(CFArrayRef properties, int options) {
    if (!orig_MGCopyMultipleAnswers || !properties || !PXHookEnabled(@"devicemodel")) {
        return orig_MGCopyMultipleAnswers ? orig_MGCopyMultipleAnswers(properties, options) : NULL;
    }

    // Luôn gọi hàm gốc trước để lấy kết quả ban đầu
    CFDictionaryRef origDict = orig_MGCopyMultipleAnswers(properties, options);

    // Tạo một bản sao có thể thay đổi
    CFMutableDictionaryRef out =
        origDict ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, origDict)
                 : CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                    &kCFTypeDictionaryKeyCallBacks,
                    &kCFTypeDictionaryValueCallBacks);
    
    // Chỉ duyệt qua các key chúng ta quan tâm
    @autoreleasepool {
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
                    CFRelease(override);
                }
            }
        }
    }

    if (origDict) CFRelease(origDict);
    return out; // Retained
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
        
        dlclose(handle);
    }
}
%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init(PX_mobilegestalt);
    }
}

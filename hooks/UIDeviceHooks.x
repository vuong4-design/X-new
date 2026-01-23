#import <UIKit/UIKit.h>
#import "ProjectXLogging.h"
#import "DataManager.h"
#import "PXHookOptions.h"

%hook UIDevice

- (NSString *)model {
    if (PXHookEnabled(@"devicemodel")) {
        PhoneInfo *info = CurrentPhoneInfo();
        if (info && info.deviceModel.name) {
            // Extract tên ngắn từ "iPhone XS Max" -> "iPhone"
            NSString *modelName = info.deviceModel.name;
            if ([modelName containsString:@"iPhone"]) {
                return @"iPhone";
            } else if ([modelName containsString:@"iPad"]) {
                return @"iPad";
            }
            return modelName;
        }
    }
    return %orig;
}

- (NSString *)localizedModel {
    if (PXHookEnabled(@"devicemodel")) {
        PhoneInfo *info = CurrentPhoneInfo();
        if (info && info.deviceModel.name) {
            NSString *modelName = info.deviceModel.name;
            if ([modelName containsString:@"iPhone"]) {
                return @"iPhone";
            } else if ([modelName containsString:@"iPad"]) {
                return @"iPad";
            }
            return modelName;
        }
    }
    return %orig;
}

- (NSString *)systemVersion {
    if (PXHookEnabled(@"devicemodel")) {
        PhoneInfo *info = CurrentPhoneInfo();
        if (info && info.iosVersion.version) {
            PXLog(@"[UIDevice] 🎭 systemVersion = %@", info.iosVersion.version);
            return info.iosVersion.version;
        }
    }
    return %orig;
}

- (NSString *)systemName {
    return %orig; // Luôn là "iOS"
}

- (NSString *)name {
    if (PXHookEnabled(@"devicemodel")) {
        PhoneInfo *info = CurrentPhoneInfo();
        if (info && info.deviceName) {
            PXLog(@"[UIDevice] 🎭 name = %@", info.deviceName);
            return info.deviceName;
        }
    }
    return %orig;
}

- (NSUUID *)identifierForVendor {
    if (PXHookEnabled(@"devicemodel")) {
        PhoneInfo *info = CurrentPhoneInfo();
        if (info && info.systemBootUUID) {
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:info.systemBootUUID];
            if (uuid) {
                PXLog(@"[UIDevice] 🎭 identifierForVendor = %@", uuid);
                return uuid;
            }
        }
    }
    return %orig;
}

%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init;
        PXLog(@"[UIDevice] ✅ Hooks initialized");
    }
}

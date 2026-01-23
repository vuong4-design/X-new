#import <Foundation/Foundation.h>
#import "ProjectXLogging.h"
#import "DataManager.h"
#import "PXHookOptions.h"
#import <substrate.h>  // ← THÊM DÒNG NÀY

// Private function declaration
extern NSString *MGCopyAnswer(NSString *key);

// Hook private C function bằng cách thay thế implementation
NSString *(*orig_MGCopyAnswer_str)(NSString *) = NULL;

NSString *hooked_MGCopyAnswer_str(NSString *key) {
    if (!PXHookEnabled(@"devicemodel")) {
        return orig_MGCopyAnswer_str ? orig_MGCopyAnswer_str(key) : nil;
    }
    
    PhoneInfo *info = CurrentPhoneInfo();
    if (!info) {
        return orig_MGCopyAnswer_str ? orig_MGCopyAnswer_str(key) : nil;
    }
    
    DeviceModel *dm = info.deviceModel;
    IosVersion *iv = info.iosVersion;
    
    if ([key isEqualToString:@"ProductType"] && dm.modelName) {
        PXLog(@"[PrivateAPI] 🎭 ProductType = %@", dm.modelName);
        return dm.modelName;
    }
    if ([key isEqualToString:@"MarketingName"] && dm.name) {
        return dm.name;
    }
    if ([key isEqualToString:@"ProductVersion"] && iv.version) {
        return iv.version;
    }
    
    return orig_MGCopyAnswer_str ? orig_MGCopyAnswer_str(key) : nil;
}

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        MSHookFunction((void *)MGCopyAnswer, 
                      (void *)hooked_MGCopyAnswer_str, 
                      (void **)&orig_MGCopyAnswer_str);
        PXLog(@"[PrivateAPI] ✅ MGCopyAnswer hooked");
    }
}

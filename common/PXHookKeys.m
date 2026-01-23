#import "PXHookKeys.h"

NSString * const PXHookKeyBattery      = @"battery";
NSString * const PXHookKeyBootTime     = @"boottime";
NSString * const PXHookKeyCanvas       = @"canvas";
NSString * const PXHookKeyDeviceModel  = @"devicemodel";
NSString * const PXHookKeyMGProbe     = @"mgprobe";
NSString * const PXHookKeyDeviceSpec   = @"devicespec";
NSString * const PXHookKeyIOSVersion   = @"iosversion";
NSString * const PXHookKeyNetwork      = @"network";
NSString * const PXHookKeyPasteboard   = @"pasteboard";
NSString * const PXHookKeyStorage      = @"storage";
NSString * const PXHookKeyCore         = @"core";
NSString * const PXHookKeyUUID         = @"uuid";
NSString * const PXHookKeyUserDefaults = @"userdefaults";
NSString * const PXHookKeyWiFi         = @"wifi";

NSArray<NSString *> *PXAllHookKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            PXHookKeyBattery,
            PXHookKeyBootTime,
            PXHookKeyCanvas,
            PXHookKeyDeviceModel,
            PXHookKeyDeviceSpec,
            PXHookKeyIOSVersion,
            PXHookKeyNetwork,
            PXHookKeyPasteboard,
            PXHookKeyStorage,
            PXHookKeyCore,
            PXHookKeyUUID,
            PXHookKeyUserDefaults,
            PXHookKeyWiFi,
        ];
    });
    return keys;
}

NSDictionary<NSString *, NSNumber *> *PXDefaultHookOptions(void) {
    static NSDictionary<NSString *, NSNumber *> *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        for (NSString *key in PXAllHookKeys()) {
            dict[key] = @YES; // default: enabled
        }
        defaults = [dict copy];
    });
    return defaults;
}

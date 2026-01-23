#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Canonical hook keys used across tweak + app UI.
/// Keep this list in sync with all calls to PXHookEnabled(@"<key>").

extern NSString * const PXHookKeyBattery;
extern NSString * const PXHookKeyBootTime;
extern NSString * const PXHookKeyCanvas;
extern NSString * const PXHookKeyDeviceModel;
extern NSString * const PXHookKeyMGProbe;
extern NSString * const PXHookKeyDeviceSpec;
extern NSString * const PXHookKeyIOSVersion;
extern NSString * const PXHookKeyNetwork;
extern NSString * const PXHookKeyPasteboard;
extern NSString * const PXHookKeyStorage;
extern NSString * const PXHookKeyCore;
extern NSString * const PXHookKeyUUID;
extern NSString * const PXHookKeyUserDefaults;
extern NSString * const PXHookKeyWiFi;

FOUNDATION_EXPORT NSArray<NSString *> *PXAllHookKeys(void);
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> *PXDefaultHookOptions(void);

NS_ASSUME_NONNULL_END

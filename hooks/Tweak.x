#import <AdSupport/ASIdentifierManager.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "ProjectXLogging.h"
#import <mach-o/dyld.h>
#import <ifaddrs.h>
#import <string.h>
#import <net/if.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>  // For sysctlbyname hooks
#import <dirent.h>     // For DIR type
#import <sys/mount.h>  // For statfs
#import "ProfileManager.h" // For accessing current profile
#import <substrate.h>
#import <sys/utsname.h>
#import <Security/Security.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import "PXBundleIdentifier.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMotion/CoreMotion.h> // Import CoreMotion framework for sensor spoofing
#import "DataManager.h"

// Forward declarations for classes we need to hook
#import "PXHookOptions.h"
@interface SBScreenshotManager : NSObject
- (void)saveScreenshotsWithCompletion:(id)completion;
- (void)saveScreenshots;
@end

@interface UIImage (WeaponXScreenshot)
- (UIImage *)weaponx_addProfileIndicator;
- (UIImage *)weaponx_removeNavigationBar;
@end


// Define hook group for main identifier spoofing

// // MGCopyAnswer hook for various system identifiers
// %hookf(NSString *, MGCopyAnswer, CFStringRef property) {
//     PhoneInfo * phoneInfo = CurrentPhoneInfo();
//     NSString *propertyString = (__bridge NSString *)property;
//     NSString *currentBundleID = PXSafeBundleIdentifier();
    
//     PXLog(@"MGCopyAnswer requested for property: %@ by app: %@", propertyString, currentBundleID);
    
    
//     // Handle various identifier types
//     if ([propertyString isEqualToString:@"UniqueDeviceID"] || 
//         [propertyString isEqualToString:@"UniqueDeviceIDData"]) {
        
//         NSString *spoofedUDID = phoneInfo.UDID;
//         if (spoofedUDID) {
//             PXLog(@"Spoofing UDID with: %@", spoofedUDID);
//             return spoofedUDID;
//         }
        
//     } 
//     else if ([propertyString isEqualToString:@"SerialNumber"]) {
//         // Special case for Filza and ADManager
//         if ([currentBundleID isEqualToString:@"com.tigisoftware.Filza"] || 
//             [currentBundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
//             NSString *hardcodedSerial = @"FCCC15Q4HG04";
//             PXLog(@"[WeaponX] 📱 Returning hardcoded serial number for %@: %@", currentBundleID, hardcodedSerial);
//             return hardcodedSerial;
//         }
        
//         if ([manager isIdentifierEnabled:@"SerialNumber"]) {
//             NSString *spoofedSerial = [manager getValueForType:@"SerialNumber"];
//             if (spoofedSerial) {
//                 PXLog(@"Spoofing Serial Number with: %@", spoofedSerial);
//                 return spoofedSerial;
//             }
//         }
//     }
//     else if ([propertyString isEqualToString:@"InternationalMobileEquipmentIdentity"] ||
//              [propertyString isEqualToString:@"MobileEquipmentIdentifier"]) {
        
//         if ([manager isIdentifierEnabled:@"IMEI"]) {
//             NSString *spoofedIMEI = [manager getValueForType:@"IMEI"];
//             if (spoofedIMEI) {
//                 PXLog(@"Spoofing IMEI with: %@", spoofedIMEI);
//                 return spoofedIMEI;
//             }
//         }
//     }
    
//     // Default: return original value
//     PXLog(@"No spoofing applied, returning original value");
//     return %orig;
// }

// IDFA hook
%group PX_core

%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    NSString *idfaString = CurrentPhoneInfo().idfa;
    if (idfaString) {
        PXLog(@"Spoofing IDFA with: %@", idfaString);
        return [[NSUUID alloc] initWithUUIDString:idfaString];
    }
    
    
    PXLog(@"No IDFA spoofing applied, returning original value");
    return %orig;
}

%end

// IDFV and device name hooks
%hook UIDevice

// Hook for identifierForVendor (IDFV)
- (NSUUID *)identifierForVendor {
    NSUUID *originalIdentifier = %orig;
    
    @try {
        NSString *idfvString = CurrentPhoneInfo().idfv;
        if (idfvString) {
            return [[NSUUID alloc] initWithUUIDString:idfvString];
        }
    
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in identifierForVendor: %@", exception);
    }
    
    return originalIdentifier;
}

// Hook for device name with improved iOS 15-16 compatibility
- (NSString *)name {
    NSString *originalName = %orig;
    
    @try {
        NSString *deviceName = CurrentPhoneInfo().deviceName;
        if (deviceName && deviceName.length > 0) {
            // Cache the name for this process to ensure consistency
            static NSString *cachedHostName = nil;
            if (!cachedHostName) {
                cachedHostName = [deviceName copy];
            }
            PXLog(@"[WeaponX] Spoofing NSHost name with: %@", cachedHostName);
            return cachedHostName;
        }
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in NSHost name: %@", exception);
    }
    
    return originalName;
}

%end

// IDFV fallback through ubiquityIdentityToken
%hook NSFileManager

- (id)ubiquityIdentityToken {
    return nil;
}

%end

// NSHost hook for device name
%hook NSHost

- (NSString *)name {
    NSString *originalName = %orig;
    
    @try {
        NSString *deviceName = CurrentPhoneInfo().deviceName;
        if (deviceName && deviceName.length > 0) {
            // Cache the name for this process to ensure consistency
            static NSString *cachedHostName = nil;
            if (!cachedHostName) {
                cachedHostName = [deviceName copy];
            }
            PXLog(@"[WeaponX] Spoofing NSHost name with: %@", cachedHostName);
            return cachedHostName;
        }
    
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in NSHost name: %@", exception);
    }
    
    return originalName;
}

%end






// Hook IOKit's IORegistryEntryCreateCFProperty for serial number
static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);

CFTypeRef hook_IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    // Null checks to prevent crashes
    if (!entry || !key) {
        return NULL;
    }
    
    // Get manager and check if identifier spoofing is enabled
    @try {
 
        
        NSString *currentBundleID = PXSafeBundleIdentifier();
        
        
        // Convert CoreFoundation key to NSString for easier handling
        NSString *keyString = (__bridge NSString *)key;
        
        // Serial Number
        if ([keyString isEqualToString:@"IOPlatformSerialNumber"]) {
            // Special case for Filza and ADManager
            if ([currentBundleID isEqualToString:@"com.tigisoftware.Filza"] || 
                [currentBundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
                NSString *hardcodedSerial = @"FCCC15Q4HG04";
                PXLog(@"[WeaponX] 📱 Spoofing IOPlatformSerialNumber with hardcoded value for %@: %@", 
                     currentBundleID, hardcodedSerial);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)hardcodedSerial);
            }
            
            NSString *spoofedSerial = CurrentPhoneInfo().serialNumber;
            if (spoofedSerial) {
                PXLog(@"Spoofing IOPlatformSerialNumber with: %@", spoofedSerial);
                // Ensure proper memory management with CoreFoundation objects
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedSerial);
            }
            
        }
        
        
        // IMEI for cellular devices
        if ([keyString isEqualToString:@"kIMEIKey"]) {
            NSString *spoofedIMEI = CurrentPhoneInfo().IMEI;
            if (spoofedIMEI) {
                PXLog(@"Spoofing IMEI with: %@", spoofedIMEI);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedIMEI);
            }
        }
        

    } @catch (NSException *exception) {
        PXLog(@"Exception in IORegistryEntryCreateCFProperty hook: %@", exception);
    }
    
    // For all other cases, pass through to the original function
    if (!orig_IORegistryEntryCreateCFProperty) {
        PXLog(@"[WeaponX] ⚠️ IORegistryEntryCreateCFProperty original is NULL; returning NULL to avoid crash");
        return NULL;
    }
    return orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
}

// Hook private API GSSystemGetSerialNo
static char* (*orig_GSSystemGetSerialNo)(void);

static char* hook_GSSystemGetSerialNo(void) {
    NSString *currentBundleID = PXSafeBundleIdentifier();
    
    PXLog(@"GSSystemGetSerialNo requested by app: %@", currentBundleID);
    
    // Special case for Filza and ADManager
    if ([currentBundleID isEqualToString:@"com.tigisoftware.Filza"] || 
        [currentBundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
        NSString *hardcodedSerial = @"FCCC15Q4HG04";
        PXLog(@"[WeaponX] 📱 Spoofing GSSystemGetSerialNo with hardcoded value for %@: %@", 
             currentBundleID, hardcodedSerial);
        
        // Convert NSString to char* that will persist
        char *serialStr = strdup([hardcodedSerial UTF8String]);
        return serialStr;
    }
    
    
    NSString *spoofedSerial = CurrentPhoneInfo().serialNumber;
    if (spoofedSerial) {
        PXLog(@"Spoofing GSSystemGetSerialNo with: %@", spoofedSerial);
        
        // Convert NSString to char* that will persist
        // Note: This will leak a small amount of memory but it's necessary
        // since we can't free the memory after returning it
        char *serialStr = strdup([spoofedSerial UTF8String]);
        return serialStr;
    }
    
    
    if (!orig_GSSystemGetSerialNo) {
        PXLog(@"[WeaponX] ⚠️ GSSystemGetSerialNo original is NULL; returning NULL to avoid crash");
        return NULL;
    }
    return orig_GSSystemGetSerialNo();
}

// Constructor
%ctor {    
    PXLog(@"ProjectX tweak initializing...");

    
    // Load saved settings and ensure synchronization
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Load security settings
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    [securitySettings synchronize]; // Force synchronization to get the latest settings
    
    
    
    // Hook IOKit for serial number spoofing
    void *IOKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (IOKitHandle) {
        void *IORegEntryCreateCFPropertyPtr = dlsym(IOKitHandle, "IORegistryEntryCreateCFProperty");
        if (IORegEntryCreateCFPropertyPtr) {
            PXLog(@"Hooking IORegistryEntryCreateCFProperty for serial number spoofing");
            MSHookFunction(IORegEntryCreateCFPropertyPtr, (void *)hook_IORegistryEntryCreateCFProperty, 
                            (void **)&orig_IORegistryEntryCreateCFProperty);
        }
        dlclose(IOKitHandle);
    }
    
    // Hook GSSystemGetSerialNo for serial number access through GS framework
    void *GSHandle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW);
    if (GSHandle) {
        void *GSSystemGetSerialNoPtr = dlsym(GSHandle, "GSSystemGetSerialNo");
        if (GSSystemGetSerialNoPtr) {
            PXLog(@"Hooking GSSystemGetSerialNo for serial number spoofing");
            MSHookFunction(GSSystemGetSerialNoPtr, (void *)hook_GSSystemGetSerialNo, 
                            (void **)&orig_GSSystemGetSerialNo);
            
        }
        dlclose(GSHandle);
    }
    

    
    PXLog(@"[WeaponX] Location and sensor spoofing hooks initialized");
}

%end

%ctor {
    if (PXHookEnabled(@"core")) {
        %init(PX_core);
    }
}

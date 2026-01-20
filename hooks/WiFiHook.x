#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "ProjectXLogging.h"
#import <Network/Network.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <substrate.h>
#import "DataManager.h"

// Forward declarations for private API methods
#import "PXHookOptions.h"
@interface NWPath (WeaponXPrivate)
- (NSString *)_getSSID;
- (id)_getBSSID;
- (NSInteger)quality;
- (double)latency;
- (id)gatherDiagnostics;
- (BOOL)isExpensive;
- (BOOL)isConstrained;
@end

@interface URLSessionTaskTransactionMetrics : NSObject
@property (nonatomic, readonly) NSURLRequest *request;
@property (nonatomic, readonly) NSURLResponse *response;
@property (nonatomic, readonly) NSDate *fetchStartDate;
@property (nonatomic, readonly) NSDate *domainLookupStartDate;
@property (nonatomic, readonly) NSDate *domainLookupEndDate;
@property (nonatomic, readonly) NSDate *connectStartDate;
@property (nonatomic, readonly) NSDate *connectEndDate;
@property (nonatomic, readonly) NSDate *secureConnectionStartDate;
@property (nonatomic, readonly) NSDate *secureConnectionEndDate;
@property (nonatomic, readonly) NSDate *requestStartDate;
@property (nonatomic, readonly) NSDate *requestEndDate;
@property (nonatomic, readonly) NSDate *responseStartDate;
@property (nonatomic, readonly) NSDate *responseEndDate;
@end

@interface URLSessionTaskMetrics : NSObject
@property (nonatomic, readonly) NSArray<URLSessionTaskTransactionMetrics *> *transactionMetrics;
@property (nonatomic, readonly) NSDate *taskInterval;
@property (nonatomic, readonly) int64_t countOfBytesReceived;
@property (nonatomic, readonly) int64_t countOfBytesSent;
@end

// MobileWiFi framework typedefs and functions (private API)
typedef struct __WiFiDeviceClient *WiFiDeviceClientRef;
typedef struct __WiFiNetwork *WiFiNetworkRef;
typedef struct __WiFiManager *WiFiManagerRef;

// Function pointers for the original functions we'll hook
static CFDictionaryRef (*orig_CNCopyCurrentNetworkInfo)(CFStringRef interfaceName);
static id (*orig_dictionaryWithScanResult)(id self, SEL _cmd, id arg1);

// MobileWiFi.framework function pointers
static WiFiManagerRef (*orig_WiFiManagerClientCreate)(CFAllocatorRef allocator, int flags);
static WiFiNetworkRef (*orig_WiFiDeviceClientCopyCurrentNetwork)(WiFiDeviceClientRef client);
static CFStringRef (*orig_WiFiNetworkGetSSID)(WiFiNetworkRef network);
static CFStringRef (*orig_WiFiNetworkGetBSSID)(WiFiNetworkRef network);




#pragma mark - Core Hook Functions

// Implementation of CNCopyCurrentNetworkInfo hook
static CFDictionaryRef replaced_CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    // Get the original result first
    CFDictionaryRef originalDict = orig_CNCopyCurrentNetworkInfo ? orig_CNCopyCurrentNetworkInfo(interfaceName) : NULL;
    
    @try {
        
        // Try to use cached info first
        if (CurrentPhoneInfo().wifiInfo.ssid && CurrentPhoneInfo().wifiInfo.bssid) {
            NSMutableDictionary *spoofedInfo = [NSMutableDictionary dictionary];
            spoofedInfo[@"SSID"] = CurrentPhoneInfo().wifiInfo.ssid;
            spoofedInfo[@"BSSID"] = CurrentPhoneInfo().wifiInfo.bssid;
            spoofedInfo[@"NetworkType"] = CurrentPhoneInfo().wifiInfo.networkType ?: @"Infrastructure";
            
            return CFBridgingRetain(spoofedInfo);
        }
        
    } @catch (NSException *exception) {
        // Silent exception handling
    }
    
    // Return original if spoofing failed
    return originalDict;
}

// Implementation of NEHotspotHelper dictionaryWithScanResult: hook
static id replaced_dictionaryWithScanResult(id self, SEL _cmd, id arg1) {
    // Call original first
    id originalResult = nil;
    if (orig_dictionaryWithScanResult) {
        originalResult = orig_dictionaryWithScanResult(self, _cmd, arg1);
    }
    
    @try {
        // Get bundle ID for scope checking        
        // Check if we should spoof
        // Ensure we have a valid dictionary to work with
        if (!originalResult || ![originalResult isKindOfClass:[NSDictionary class]]) {
            return originalResult;
        }
        
        // Create mutable copy for modification
        NSMutableDictionary *modifiedResult = [NSMutableDictionary dictionaryWithDictionary:originalResult];
        
        // Try to use cached info first
        if (CurrentPhoneInfo().wifiInfo.ssid && CurrentPhoneInfo().wifiInfo.bssid) {
            modifiedResult[@"SSID"] = CurrentPhoneInfo().wifiInfo.ssid;
            modifiedResult[@"BSSID"] = CurrentPhoneInfo().wifiInfo.bssid;
            
            // Add WiFi standard information if available from cached info
            if (CurrentPhoneInfo().wifiInfo.wifiStandard) {
                NSString *standard = CurrentPhoneInfo().wifiInfo.wifiStandard;
                if ([standard containsString:@"ax"]) {
                    modifiedResult[@"WifiStandard"] = @6; // 802.11ax
                } else if ([standard containsString:@"ac"]) {
                    modifiedResult[@"WifiStandard"] = @5; // 802.11ac
                } else if ([standard containsString:@"n"]) {
                    modifiedResult[@"WifiStandard"] = @4; // 802.11n
                }
            }
            
            return modifiedResult;
        }
        
    } @catch (NSException *exception) {
        // Silent exception handling
    }
    
    // Return original if spoofing failed
    return originalResult;
}



#pragma mark - MobileWiFi Framework Hooks

// Hook implementation for WiFiManagerClientCreate
static WiFiManagerRef replaced_WiFiManagerClientCreate(CFAllocatorRef allocator, int flags) {
    // Call original implementation
    if (!orig_WiFiManagerClientCreate) {
        return NULL;
    }
    return orig_WiFiManagerClientCreate(allocator, flags);
}

// Hook implementation for WiFiDeviceClientCopyCurrentNetwork
static WiFiNetworkRef replaced_WiFiDeviceClientCopyCurrentNetwork(WiFiDeviceClientRef client) {
    // Call original implementation
    if (!orig_WiFiDeviceClientCopyCurrentNetwork) {
        return NULL;
    }
    return orig_WiFiDeviceClientCopyCurrentNetwork(client);
}

// Hook implementation for WiFiNetworkGetSSID
static CFStringRef replaced_WiFiNetworkGetSSID(WiFiNetworkRef network) {


    if (CurrentPhoneInfo().wifiInfo.ssid) {
        
        return (__bridge CFStringRef)CurrentPhoneInfo().wifiInfo.ssid;
    }
    
    // Call original as fallback
    if (!orig_WiFiNetworkGetSSID) {
        return NULL;
    }
    return orig_WiFiNetworkGetSSID(network);
}

// Hook implementation for WiFiNetworkGetBSSID
static CFStringRef replaced_WiFiNetworkGetBSSID(WiFiNetworkRef network) {
    
    if (CurrentPhoneInfo().wifiInfo.bssid) {     
        return (__bridge CFStringRef)CurrentPhoneInfo().wifiInfo.bssid;
    }
    
    // Call original as fallback
    if (!orig_WiFiNetworkGetBSSID) {
        return NULL;
    }
    return orig_WiFiNetworkGetBSSID(network);
}

#pragma mark - Hook Installation

static void initializeHooks(void) {
    // Install CNCopyCurrentNetworkInfo hook using ellekit
    void *symbol = dlsym(RTLD_DEFAULT, "CNCopyCurrentNetworkInfo");
    if (symbol) {
        MSHookFunction(symbol, 
                           (void *)replaced_CNCopyCurrentNetworkInfo, 
                           (void **)&orig_CNCopyCurrentNetworkInfo);
        
    }
    
    // Install NEHotspotHelper hook using method swizzling
    Class neHotspotHelperClass = NSClassFromString(@"NEHotspotHelper");
    if (neHotspotHelperClass) {
        Method dictionaryMethod = class_getClassMethod(neHotspotHelperClass, @selector(dictionaryWithScanResult:));
        if (dictionaryMethod) {
            orig_dictionaryWithScanResult = (id (*)(id, SEL, id))method_getImplementation(dictionaryMethod);
            method_setImplementation(dictionaryMethod, (IMP)replaced_dictionaryWithScanResult);
        }
    }
    

    // Install MobileWiFi framework hooks
    void *mobileWiFiLib = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_NOW);
    if (mobileWiFiLib) {
        // Hook WiFiManagerClientCreate
        symbol = dlsym(mobileWiFiLib, "WiFiManagerClientCreate");
        if (symbol) {
            MSHookFunction(symbol, 
                  (void *)replaced_WiFiManagerClientCreate, 
                  (void **)&orig_WiFiManagerClientCreate);
        }
        
        // Hook WiFiDeviceClientCopyCurrentNetwork
        symbol = dlsym(mobileWiFiLib, "WiFiDeviceClientCopyCurrentNetwork");
        if (symbol) {
            MSHookFunction(symbol, 
                  (void *)replaced_WiFiDeviceClientCopyCurrentNetwork, 
                  (void **)&orig_WiFiDeviceClientCopyCurrentNetwork);
        }
        
        // Hook WiFiNetworkGetSSID
        symbol = dlsym(mobileWiFiLib, "WiFiNetworkGetSSID");
        if (symbol) {
            MSHookFunction(symbol, 
                  (void *)replaced_WiFiNetworkGetSSID, 
                  (void **)&orig_WiFiNetworkGetSSID);
        }
        
        // Hook WiFiNetworkGetBSSID
        symbol = dlsym(mobileWiFiLib, "WiFiNetworkGetBSSID");
        if (symbol) {
            MSHookFunction(symbol, 
                  (void *)replaced_WiFiNetworkGetBSSID, 
                  (void **)&orig_WiFiNetworkGetBSSID);
        }
        
        dlclose(mobileWiFiLib);
    }
}

#pragma mark - Notification Handlers


#pragma mark - NWPathMonitor Hooks (Network Framework)

// Hook for NWPath methods
%group PX_wifi

%hook NWPath

- (BOOL)usesInterfaceType:(NSInteger)type {
    // We don't modify this as it would break connectivity detection
    return %orig;
}

- (NSString *)_getSSID {
    // Return spoofed SSID if available
    if (CurrentPhoneInfo().wifiInfo.ssid) {
        return CurrentPhoneInfo().wifiInfo.ssid;
    }
    
    // Fallback to original if no spoofed data
    return %orig;
}

- (id)_getBSSID {
    
    // Return spoofed BSSID if available
    // NSDictionary *wifiInfo = getProfileWiFiInfo();
    if (CurrentPhoneInfo().wifiInfo.bssid) {
        return CurrentPhoneInfo().wifiInfo.bssid;
    }
    
    // Fallback to original if no spoofed data
    return %orig;
}

- (NSInteger)quality {
    return %orig;
}

- (double)latency {
    return %orig;
}

- (BOOL)isExpensive {
    return %orig;
}

- (BOOL)isConstrained {
    return %orig;
}

- (id)gatherDiagnostics {
    return %orig;
}

%end

// Hook NWPathMonitor class
%hook NWPathMonitor

- (void)setPathUpdateHandler:(void (^)(id path))handler {
    if (handler) {
        // Create a wrapper that can modify the path if needed
        void (^newHandler)(id path) = ^(id path) {
            // Original handler still needs to be called with the path
            // We're not modifying it here as the path itself is hooked separately
            handler(path);
        };
        %orig(newHandler);
    } else {
        %orig;
    }
}

- (id)currentPath {
    // The path object itself is hooked via the NWPath hook above
    return %orig;
}

%end
%hook NEHotspotNetwork

- (id)SSID{

    if (CurrentPhoneInfo().wifiInfo.ssid) {
        return CurrentPhoneInfo().wifiInfo.ssid;
    }
    return %orig;
}
- (id)BSSID{

    if (CurrentPhoneInfo().wifiInfo.bssid) { 
        return CurrentPhoneInfo().wifiInfo.bssid;
    }
    return %orig;
}
- (double)signalStrength{
    double strength = 0.7 + ((double)arc4random_uniform(20) / 100.0);
    return strength;
}
- (bool)isSecure{
    return YES;
}
    
%end
#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        @try {
            PXLog(@"[WiFiHook] Initializing WiFi hooks");
                    
            
            // Initialize hooks
            initializeHooks();
            
            // Initialize Objective-C hooks for scoped apps only
            %init;
            
            PXLog(@"[WiFiHook] WiFi hooks successfully initialized for scoped app");
            
        } @catch (NSException *e) {
            PXLog(@"[WiFiHook] ❌ Exception in constructor: %@", e);
        }
    }
}

%end

%ctor {
    if (PXHookEnabled(@"wifi")) {
        %init(PX_wifi);
    }
}

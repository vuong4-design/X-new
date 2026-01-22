#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ProjectXLogging.h"
#import <WebKit/WebKit.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <substrate.h>
#import "DataManager.h"

// Add a macro for logging with a recognizable prefix
// Set DEBUG_LOG to 0 to reduce logging in production
#import "PXHookOptions.h"
#define DEBUG_LOG 0

#if DEBUG_LOG
#define IOSVERSION_LOG(fmt, ...) NSLog((@"[iosversion] " fmt), ##__VA_ARGS__)
#else
// Only log important messages when DEBUG_LOG is off
#define IOSVERSION_LOG(fmt, ...) if ([fmt hasPrefix:@"❌"] || [fmt hasPrefix:@"⚠️"]) NSLog((@"[iosversion] " fmt), ##__VA_ARGS__)
#endif
// SystemVersion.plist path constants
#define SYSTEM_VERSION_PATH @"/System/Library/CoreServices/SystemVersion.plist"
#define ROOTLESS_SYSTEM_VERSION_PATH @"/var/jb/System/Library/CoreServices/SystemVersion.plist"

// Forward declarations
static void modifyUserAgentString(NSString **userAgentString, NSString *originalVersion, NSString *spoofedVersion);
static BOOL isSystemVersionFile(NSString *path);
static NSDictionary *spoofSystemVersionPlist(NSDictionary *originalPlist);

// Function declarations for file access hooks
NSData* replaced_NSData_dataWithContentsOfFile(Class self, SEL _cmd, NSString *path);
NSDictionary* replaced_NSDictionary_dictionaryWithContentsOfFile(Class self, SEL _cmd, NSString *path);
id replaced_NSString_stringWithContentsOfFile(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error);

// Original sysctlbyname function pointer for hooking
static int (*original_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

// Original function pointers for direct file access hooks
static NSData* (*original_NSData_dataWithContentsOfFile)(Class self, SEL _cmd, NSString *path);
static NSDictionary* (*original_NSDictionary_dictionaryWithContentsOfFile)(Class self, SEL _cmd, NSString *path);
static id (*original_NSString_stringWithContentsOfFile)(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error);

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *processName = [[NSProcessInfo processInfo] processName];
        PXLog(@"[IOSVersionHooks] ✅ loaded in process=%@ bundle=%@", processName, bundleID);
    }
}


// Throttling variables to prevent excessive function calls
static uint64_t lastSystemVersionCallTime = 0;
static NSString *cachedSystemVersionResult = nil;
static uint64_t lastDictCallTime = 0;
static CFDictionaryRef cachedDictResult = NULL;

// Define constants
#define VERSION_CACHE_VALID_PERIOD 1800.0 // 30 minutes
#define THROTTLE_INTERVAL_NSEC 100000000  // 100ms in nanoseconds


// Convert version string to NSOperatingSystemVersion struct
static NSOperatingSystemVersion getOperatingSystemVersion(NSString *versionString) {
    NSArray *components = [versionString componentsSeparatedByString:@"."];
    
    NSInteger majorVersion = components.count > 0 ? [components[0] integerValue] : 0;
    NSInteger minorVersion = components.count > 1 ? [components[1] integerValue] : 0;
    NSInteger patchVersion = components.count > 2 ? [components[2] integerValue] : 0;
    
    return (NSOperatingSystemVersion){majorVersion, minorVersion, patchVersion};
}

// Helper function to modify a user agent string with the spoofed iOS version
static void modifyUserAgentString(NSString **userAgentString, NSString *originalVersion, NSString *spoofedVersion) {
    if (!userAgentString || !*userAgentString || !spoofedVersion || !originalVersion) {
        return;
    }
    
    NSString *originalUA = *userAgentString;
    
    // Common patterns to handle:
    // 1. Mobile/15E148 (for older formats)
    // 2. OS 15_4 like Mac (for newer formats)
    // 3. Version/15.4 (for Safari)
    // 4. CPU OS 15_4 (for iPad)
    // 5. Mozilla/5.0 (iPhone; CPU iPhone OS 15_4 like Mac OS X)
    // 6. AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15
    
    // Pattern 1: Mobile/15E148
    NSRegularExpression *mobileRegex = [NSRegularExpression regularExpressionWithPattern:@"(Mobile)/\\d+[A-Z]\\d+" options:0 error:nil];
    NSString *spoofedBuild = CurrentPhoneInfo().iosVersion.build;
    NSString *updatedUA = originalUA;
    
    if (spoofedBuild) {
        updatedUA = [mobileRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1/%@", spoofedBuild]];
    }
    
    // Pattern 2: OS 15_4 like Mac
    NSString *underscoreVersion = [spoofedVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSRegularExpression *osRegex = [NSRegularExpression regularExpressionWithPattern:@"(OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like\\s+Mac)" options:0 error:nil];
    updatedUA = [osRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 3: Version/15.4
    NSRegularExpression *versionRegex = [NSRegularExpression regularExpressionWithPattern:@"(Version/)\\d+\\.\\d+(?:\\.\\d+)?" options:0 error:nil];
    updatedUA = [versionRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@", spoofedVersion]];
    
    // Pattern 4: CPU OS 15_4
    NSRegularExpression *cpuOSRegex = [NSRegularExpression regularExpressionWithPattern:@"(CPU\\s+OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [cpuOSRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 5: CPU iPhone OS 15_4
    NSRegularExpression *iPhoneOSRegex = [NSRegularExpression regularExpressionWithPattern:@"(CPU iPhone OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [iPhoneOSRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 6: Mozilla/5.0 (iPhone; ... OS X)
    NSRegularExpression *mozillaRegex = [NSRegularExpression regularExpressionWithPattern:@"(Mozilla/5\\.0 \\([^;]+; [^;]+; [^\\s]+\\s+OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [mozillaRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    if (![updatedUA isEqualToString:originalUA]) {
        *userAgentString = updatedUA;
        IOSVERSION_LOG(@"Modified UA: %@ → %@", originalUA, updatedUA);
    } else {
        IOSVERSION_LOG(@"Failed to modify UA: %@", originalUA);
    }
}

#pragma mark - UIDevice Hooks
%group PX_iosversion


%hook UIDevice

// Hook the systemVersion method to return our spoofed version
- (NSString *)systemVersion {
    @try {
        // Rate limiting - don't call this function too frequently
        uint64_t currentTime = mach_absolute_time();
        if (cachedSystemVersionResult != nil && 
            (currentTime - lastSystemVersionCallTime) < THROTTLE_INTERVAL_NSEC) {
            return cachedSystemVersionResult;
        }
        
        NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
        if (spoofedVersion) {
            NSString *originalVersion = %orig;
            
            // Only log occasionally to reduce overhead
            if (lastSystemVersionCallTime == 0 || (currentTime - lastSystemVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                IOSVERSION_LOG(@"UIDevice.systemVersion: %@ → %@", originalVersion, spoofedVersion);
            }
            
            // Update cache and timestamp
            lastSystemVersionCallTime = currentTime;
            cachedSystemVersionResult = spoofedVersion;
            
            return spoofedVersion;
        }
    
        
        // Cache the original result too
        NSString *originalResult = %orig;
        lastSystemVersionCallTime = currentTime;
        cachedSystemVersionResult = originalResult;
        return originalResult;
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in systemVersion hook: %@", e);
    }
    
    return %orig;
}

%end

#pragma mark - NSProcessInfo Hooks

%hook NSProcessInfo

// Hook operatingSystemVersion to return our spoofed version
- (NSOperatingSystemVersion)operatingSystemVersion {
    @try {
        NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
        if (spoofedVersion) {
            NSOperatingSystemVersion originalVersion = %orig;
            NSOperatingSystemVersion spoofedStructVersion = getOperatingSystemVersion(spoofedVersion);
            
            NSLog(@"[iosversion] NSProcessInfo.operatingSystemVersion: %ld.%ld.%ld → %ld.%ld.%ld", 
                    (long)originalVersion.majorVersion, 
                    (long)originalVersion.minorVersion, 
                    (long)originalVersion.patchVersion,
                    (long)spoofedStructVersion.majorVersion, 
                    (long)spoofedStructVersion.minorVersion, 
                    (long)spoofedStructVersion.patchVersion);
            
            return spoofedStructVersion;
        }
    } @catch (NSException *e) {
        NSLog(@"[iosversion] Error in operatingSystemVersion hook: %@", e);
    }
    return %orig;
}

// Hook isOperatingSystemAtLeastVersion to handle our spoofed version
- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version {
    @try {
        NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
        if (spoofedVersion) {
            NSOperatingSystemVersion spoofedStructVersion = getOperatingSystemVersion(spoofedVersion);
            
            // Implement the comparison logic ourselves instead of calling orig
            BOOL result = (spoofedStructVersion.majorVersion > version.majorVersion) ||
                            ((spoofedStructVersion.majorVersion == version.majorVersion) && 
                            (spoofedStructVersion.minorVersion > version.minorVersion)) ||
                            ((spoofedStructVersion.majorVersion == version.majorVersion) && 
                            (spoofedStructVersion.minorVersion == version.minorVersion) && 
                            (spoofedStructVersion.patchVersion >= version.patchVersion));
            
            BOOL originalResult = %orig;
            NSLog(@"[iosversion] NSProcessInfo.isOperatingSystemAtLeastVersion: %ld.%ld.%ld, original: %d → spoofed: %d", 
                    (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion,
                    originalResult, result);
            
            return result;
        }
    } @catch (NSException *e) {
        NSLog(@"[iosversion] Error in isOperatingSystemAtLeastVersion hook: %@", e);
    }
    return %orig;
}

// Additional method to hook for getting raw operating system version string
- (NSString *)operatingSystemVersionString {
    @try {
        IosVersion *versionInfo = CurrentPhoneInfo().iosVersion;
        if (versionInfo && versionInfo.version) {
            NSString *originalVersion = %orig;
            NSString *spoofedVersion = [NSString stringWithFormat:@"Version %@ (Build %@)", 
                                        versionInfo.version, 
                                        versionInfo.build];
            
            IOSVERSION_LOG(@"NSProcessInfo.operatingSystemVersionString: %@ → %@", 
                    originalVersion, spoofedVersion);
                    
            return spoofedVersion;
        } 
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in operatingSystemVersionString hook: %@", e);
    }
    
    return %orig;
}

%end

#pragma mark - WKWebView User Agent Hooks

// Hook WKWebView to modify the user agent
%hook WKWebView

+ (WKWebView *)_allowedTopLevelWebView:(WKWebView *)webView {
    WKWebView *resultWebView = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Special case for Safari and WebKit processes to force spoofing
        BOOL forceSpoofForWebKit = [bundleID isEqualToString:@"com.apple.mobilesafari"] || 
                                  [bundleID hasPrefix:@"com.apple.WebKit"];
        
        if ((forceSpoofForWebKit) && resultWebView) {
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                // Get the current user agent
                if ([resultWebView respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
                    [resultWebView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(NSString *userAgent, NSError *error) {
                        if (userAgent && [userAgent isKindOfClass:[NSString class]]) {
                            // Modify the user agent string
                            NSMutableString *modifiedUA = [userAgent mutableCopy];
                            modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                            
                            // Set the new user agent if it changed
                            if (![modifiedUA isEqualToString:userAgent]) {
                                if ([resultWebView respondsToSelector:@selector(setCustomUserAgent:)]) {
                                    [resultWebView setCustomUserAgent:modifiedUA];
                                    IOSVERSION_LOG(@"Set modified user agent for WebView in %@", bundleID);
                                }
                            }
                        }
                    }];
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in _allowedTopLevelWebView: %@", e);
    }
    
    return resultWebView;
}

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    WKWebView *webView = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Special case for Safari and WebKit processes to force spoofing
        BOOL forceSpoofForWebKit = [bundleID isEqualToString:@"com.apple.mobilesafari"] || 
                                  [bundleID hasPrefix:@"com.apple.WebKit"];
        
        if ((forceSpoofForWebKit) && webView) {
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                // First, if configuration has applicationNameForUserAgent, try to modify it
                if (configuration && [configuration respondsToSelector:@selector(applicationNameForUserAgent)]) {
                    NSString *appName = [configuration applicationNameForUserAgent];
                    if (appName) {
                        NSMutableString *modifiedName = [appName mutableCopy];
                        modifyUserAgentString(&modifiedName, originalVersion, spoofedVersion);
                        
                        if (![modifiedName isEqualToString:appName]) {
                            [configuration setApplicationNameForUserAgent:modifiedName];
                            IOSVERSION_LOG(@"Modified applicationNameForUserAgent: %@ → %@", appName, modifiedName);
                        }
                    }
                }
                
                // Now try to set customUserAgent directly if possible
                if ([webView respondsToSelector:@selector(customUserAgent)] && 
                    [webView respondsToSelector:@selector(setCustomUserAgent:)]) {
                    
                    // Try to get existing customUserAgent first
                NSString *currentUserAgent = [webView customUserAgent];
                if (currentUserAgent) {
                    NSMutableString *modifiedUA = [currentUserAgent mutableCopy];
                    modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                    
                    if (![modifiedUA isEqualToString:currentUserAgent]) {
                        [webView setCustomUserAgent:modifiedUA];
                            IOSVERSION_LOG(@"Set custom user agent on init: %@ → %@", currentUserAgent, modifiedUA);
                        }
                    } else {
                        // If no custom user agent yet, we need to get the default one and modify it
                        [webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(NSString *userAgent, NSError *error) {
                            if (userAgent && [userAgent isKindOfClass:[NSString class]]) {
                                NSMutableString *modifiedUA = [userAgent mutableCopy];
                                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                                
                                if (![modifiedUA isEqualToString:userAgent]) {
                                    [webView setCustomUserAgent:modifiedUA];
                                    IOSVERSION_LOG(@"Set custom user agent from default: %@ → %@", userAgent, modifiedUA);
                                }
                            }
                        }];
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in initWithFrame: %@", e);
    }
    
    return webView;
}

- (void)setCustomUserAgent:(NSString *)customUserAgent {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Special case for Safari and WebKit processes to force spoofing
        BOOL forceSpoofForWebKit = [bundleID isEqualToString:@"com.apple.mobilesafari"] || 
                                  [bundleID hasPrefix:@"com.apple.WebKit"];
        
        if ((forceSpoofForWebKit) && customUserAgent) {
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                NSMutableString *modifiedUA = [customUserAgent mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:customUserAgent]) {
                    IOSVERSION_LOG(@"Setting modified custom UA: %@ → %@", customUserAgent, modifiedUA);
                    %orig(modifiedUA);
                    return;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in setCustomUserAgent: %@", e);
    }
    
    %orig;
}

// Add hooks for common JavaScript evaluation methods to modify user agent when detected
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(id)completionHandler {
    // Check if this is a user agent detection script
    BOOL isUserAgentScript = [javaScriptString containsString:@"navigator.userAgent"];
    
    // Let the original method run first
    %orig;
    
    // If it's a user agent script, try to update the user agent
    if (isUserAgentScript) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Special case for Safari and WebKit processes to force spoofing
        BOOL forceSpoofForWebKit = [bundleID isEqualToString:@"com.apple.mobilesafari"] || 
                                  [bundleID hasPrefix:@"com.apple.WebKit"];
        
        if (forceSpoofForWebKit) {
            // Wait a short time to let the script execute
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
                NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
                
                if (spoofedVersion && [self respondsToSelector:@selector(customUserAgent)]) {
                    NSString *currentUA = [self customUserAgent];
                    if (currentUA) {
                        NSMutableString *modifiedUA = [currentUA mutableCopy];
                        modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                        
                        if (![modifiedUA isEqualToString:currentUA]) {
                            [self setCustomUserAgent:modifiedUA];
                            IOSVERSION_LOG(@"Updated UA after JS evaluation: %@ → %@", currentUA, modifiedUA);
                        }
                    }
                }
            });
        }
    }
}

%end

#pragma mark - WKWebViewConfiguration Hooks

%hook WKWebViewConfiguration

- (void)setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent {
    @try {
        if (applicationNameForUserAgent) {
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                NSMutableString *modifiedName = [applicationNameForUserAgent mutableCopy];
                modifyUserAgentString(&modifiedName, originalVersion, spoofedVersion);
                
                if (![modifiedName isEqualToString:applicationNameForUserAgent]) {
                    %orig(modifiedName);
                    return;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    %orig;
}

%end

#pragma mark - NSURLRequest User-Agent Hooks

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    @try {
        if ([field isEqualToString:@"User-Agent"] && value) {
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                NSMutableString *modifiedValue = [value mutableCopy];
                modifyUserAgentString(&modifiedValue, originalVersion, spoofedVersion);
                
                if (![modifiedValue isEqualToString:value]) {
                    %orig(modifiedValue, field);
                    return;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    %orig;
}

%end

#pragma mark - Safari Specific Hooks

// Hook Safari's SFUserAgentController to modify the user agent string
%hook SFUserAgentController

+ (NSString *)userAgentWithDomain:(NSString *)domain {
    NSString *originalUA = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion && originalUA) {
                NSMutableString *modifiedUA = [originalUA mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:originalUA]) {
                    IOSVERSION_LOG(@"Safari: Modified user agent for domain %@", domain);
                    return modifiedUA;
                }
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"Error modifying Safari user agent: %@", e);
    }
    
    return originalUA;
}

+ (NSString *)defaultUserAgentString {
    NSString *originalUA = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion && originalUA) {
                NSMutableString *modifiedUA = [originalUA mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:originalUA]) {
                    IOSVERSION_LOG(@"Safari: Modified default user agent");
                    return modifiedUA;
                }
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"Error modifying Safari default user agent: %@", e);
    }
    
    return originalUA;
}

%end

#pragma mark - CoreFoundation Version Dictionary Hook

static CFStringRef PXCreateCFStringFromNSString(NSString *value) {
    if (!value) {
        return NULL;
    }
    const char *cString = [value UTF8String];
    if (!cString) {
        return NULL;
    }
    return CFStringCreateWithCString(NULL, cString, kCFStringEncodingUTF8);
}

// Hook CFCopySystemVersionDictionary to spoof iOS version information at the CoreFoundation level
static CFDictionaryRef (*original_CFCopySystemVersionDictionary)(void);
CFDictionaryRef replaced_CFCopySystemVersionDictionary(void) {
    @try {
        NSLog(@"[debug] version replace hook");
        // Rate limiting to prevent excessive calls
        uint64_t currentTime = mach_absolute_time();
        if (cachedDictResult != NULL && 
            (currentTime - lastDictCallTime) < THROTTLE_INTERVAL_NSEC) {
            // Return cached result to reduce CPU usage
            return CFRetain(cachedDictResult);
        }
        

            // Create a fallback dictionary if original function is NULL
            CFDictionaryRef originalDict = NULL;
            BOOL usingFallback = NO;
            
            if (original_CFCopySystemVersionDictionary) {
                originalDict = original_CFCopySystemVersionDictionary();
                NSLog(@"has original_CFCopySystemVersionDictionary");
            } else {
                // Create a basic dictionary with current system version
                NSString *actualVersion = [[UIDevice currentDevice] systemVersion];
                CFStringRef versionKey = CFSTR("ProductVersion");
                CFStringRef buildKey = CFSTR("ProductBuildVersion");
                
                // Use a default build number based on version
                NSString *actualBuild = [NSString stringWithFormat:@"%@000", [actualVersion stringByReplacingOccurrencesOfString:@"." withString:@""]];
                
                CFStringRef versionValue = PXCreateCFStringFromNSString(actualVersion);
                CFStringRef buildValue = PXCreateCFStringFromNSString(actualBuild);
                
                CFMutableDictionaryRef fallbackDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                
                if (fallbackDict && versionValue && buildValue) {
                    CFDictionarySetValue(fallbackDict, versionKey, versionValue);
                    CFDictionarySetValue(fallbackDict, buildKey, buildValue);
                    
                    CFRelease(versionValue);
                    CFRelease(buildValue);
                    
                    originalDict = fallbackDict;
                    usingFallback = YES;
                    
                    NSLog(@"Created fallback dictionary for CFCopySystemVersionDictionary");
                }
            }
            
            if (!originalDict) {
                NSLog(@"Failed to get system version dictionary");
                return NULL;
            }
            
            // Get spoofed version info
            IosVersion *versionInfo = CurrentPhoneInfo().iosVersion;
            if (!versionInfo || !versionInfo.version || !versionInfo.build) {
                NSLog(@"Missing version info for CFCopySystemVersionDictionary");
                if (cachedDictResult != NULL) {
                    CFRelease(cachedDictResult);
                }
                cachedDictResult = CFRetain(originalDict);
                lastDictCallTime = currentTime;
                return originalDict;
            }
            
            NSString *spoofedVersion = versionInfo.version;
            NSString *spoofedBuild = versionInfo.build;
            
            // Log original values only occasionally to reduce overhead
            if (lastDictCallTime == 0 || (currentTime - lastDictCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                CFStringRef origVersionKey = CFSTR("ProductVersion");
                CFStringRef origBuildKey = CFSTR("ProductBuildVersion");
                CFStringRef origVersionValue = CFDictionaryGetValue(originalDict, origVersionKey);
                CFStringRef origBuildValue = CFDictionaryGetValue(originalDict, origBuildKey);
                if (origVersionValue && origBuildValue) {
                    NSLog(@"CFCopySystemVersionDictionary original: version=%@ build=%@", 
                          (__bridge NSString *)origVersionValue,
                          (__bridge NSString *)origBuildValue);
                }
            }
            
            // Create mutable copy to modify
            CFMutableDictionaryRef mutableDict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, originalDict);
            if (!mutableDict) {
                NSLog(@"Failed to create mutable copy of system version dictionary");
                if (cachedDictResult != NULL) {
                    CFRelease(cachedDictResult);
                }
                cachedDictResult = CFRetain(originalDict);
                lastDictCallTime = currentTime;
                return originalDict;
            }
            
            // Update version and build number
            CFStringRef versionKey = CFSTR("ProductVersion");
            CFStringRef buildKey = CFSTR("ProductBuildVersion");
            
            CFStringRef versionValue = PXCreateCFStringFromNSString(spoofedVersion);
            CFStringRef buildValue = PXCreateCFStringFromNSString(spoofedBuild);
            
            if (versionValue) {
                CFDictionarySetValue(mutableDict, versionKey, versionValue);
                CFRelease(versionValue);
            }
            
            if (buildValue) {
                CFDictionarySetValue(mutableDict, buildKey, buildValue);
                CFRelease(buildValue);
            }
            
            // Log the newly set values only occasionally
            if (lastDictCallTime == 0 || (currentTime - lastDictCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                NSLog(@"CFCopySystemVersionDictionary spoofed: version=%@ build=%@", 
                      spoofedVersion, spoofedBuild);
            }
            
            // Release the original dictionary since we're returning a new one
            if (!usingFallback) {
                CFRelease(originalDict);
            }
            
            // Cache the result and update timestamp
            if (cachedDictResult != NULL) {
                CFRelease(cachedDictResult);
            }
            cachedDictResult = CFRetain(mutableDict);
            lastDictCallTime = currentTime;
            
            return mutableDict;
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in CFCopySystemVersionDictionary hook: %@", e);
    }
    
    // Call original function or return NULL if it's not available
    CFDictionaryRef result = original_CFCopySystemVersionDictionary ? original_CFCopySystemVersionDictionary() : NULL;
    
    // Update cache
    if (result) {
        if (cachedDictResult != NULL) {
            CFRelease(cachedDictResult);
        }
        cachedDictResult = CFRetain(result);
        lastDictCallTime = mach_absolute_time();
    }
    
    return result;
}

#pragma mark - sysctlbyname Hook

// Hook sysctlbyname to spoof iOS kernel version information
int hooked_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    
    @try {
        // Pre-cache version info only once
        IosVersion *cachedVersionInfo = CurrentPhoneInfo().iosVersion;
        if (!cachedVersionInfo) {
            return original_sysctlbyname(name, oldp, oldlenp, newp, newlen);
        }
        NSString *buildString = cachedVersionInfo.build;
        NSString *kernelVersionString = cachedVersionInfo.kernelVersion;
        if (!buildString.length || !kernelVersionString.length) {
            return original_sysctlbyname(name, oldp, oldlenp, newp, newlen);
        }

        static char cachedBuildStr[32] = {0}; // Cache the build string
        static size_t cachedBuildStrLen = 0;
        strlcpy(cachedBuildStr, [buildString UTF8String], sizeof(cachedBuildStr));
        cachedBuildStrLen = strlen(cachedBuildStr) + 1; // +1 for null terminator

        static char cachedKernelVersionStr[256] = {0}; // Cache the kernel version string
        strlcpy(cachedKernelVersionStr, [kernelVersionString UTF8String], sizeof(cachedKernelVersionStr));
        static size_t cachedKernelVersionStrLen = 0;
        cachedKernelVersionStrLen = strlen(cachedKernelVersionStr) + 1; // +1 for null terminator

        // Check if this is a request for full kernel version string
        if (name && strcmp(name, "kern.version") == 0) {
            // If we have a valid cached kernel version string
            if (cachedKernelVersionStrLen > 0) {
                // Check if this is just a length query (oldp is NULL but oldlenp is not)
                if (!oldp && oldlenp) {
                    *oldlenp = cachedKernelVersionStrLen;
                    return 0;
                }
                
                // Make sure we have enough space in the buffer and that both oldp and oldlenp are valid
                if (oldp && oldlenp && *oldlenp >= cachedKernelVersionStrLen) {
                    memcpy(oldp, cachedKernelVersionStr, cachedKernelVersionStrLen);
                    *oldlenp = cachedKernelVersionStrLen;
                    return 0; // Success
                } else if (oldlenp) {
                    // Not enough space, just set the required length
                    *oldlenp = cachedKernelVersionStrLen;
                    return 0; // Success (caller will need to provide a bigger buffer)
                }
            } else {
                IOSVERSION_LOG(@"❌ Missing cached kernel version string");
            }
        }
        // Check if this is a request for Darwin version number (kern.osrelease)
        else if (name && strcmp(name, "kern.osrelease") == 0 && cachedVersionInfo && cachedVersionInfo.darwin) {
            // Get Darwin version (format: "21.6.0")
            NSString *darwinVersion = cachedVersionInfo.darwin;
            if (darwinVersion) {
                const char *darwinVersionStr = [darwinVersion UTF8String];
                size_t darwinVersionLen = strlen(darwinVersionStr) + 1; // +1 for null terminator
                
                // Check if this is just a length query
                if (!oldp && oldlenp) {
                    *oldlenp = darwinVersionLen;
                    return 0;
                }
                
                // Copy the version if buffer is big enough
                if (oldp && oldlenp && *oldlenp >= darwinVersionLen) {
                    memcpy(oldp, darwinVersionStr, darwinVersionLen);
                    *oldlenp = darwinVersionLen;
                    
                    return 0; // Success
                } else if (oldlenp) {
                    // Not enough space, just set the required length
                    *oldlenp = darwinVersionLen;
                    return 0;
                }
            }
        }
        // Check if this is a request for iOS version information
        else if (name && (strcmp(name, "kern.osversion") == 0)) {
            
            // Skip processing if we have a valid cached build and not enough time has passed
            if (cachedBuildStrLen > 0) {
                // Check if this is just a length query (oldp is NULL but oldlenp is not)
                if (!oldp && oldlenp) {
                    *oldlenp = cachedBuildStrLen;
                    return 0;
                }
                
                // Make sure we have enough space in the buffer and that both oldp and oldlenp are valid
                if (oldp && oldlenp && *oldlenp >= cachedBuildStrLen) {
                    memcpy(oldp, cachedBuildStr, cachedBuildStrLen);
                    *oldlenp = cachedBuildStrLen;
                    
                    return 0; // Success
                } else if (oldlenp) {
                    // Not enough space, just set the required length
                    *oldlenp = cachedBuildStrLen;
                    return 0; // Success (caller will need to provide a bigger buffer)
                }
            } else {
                IOSVERSION_LOG(@"❌ Missing cached build number");
            }
        }
        
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in sysctlbyname hook: %@", e);
    }
    
    // Call the original function for all other cases
    return original_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

#pragma mark - Bundle Version Hooks

%hook NSBundle

- (id)objectForInfoDictionaryKey:(NSString *)key {
    @try {
        // Handle system version info in Info.plist queries
        if ([key isEqualToString:@"MinimumOSVersion"] || 
            [key isEqualToString:@"DTPlatformVersion"] ||
            [key isEqualToString:@"DTSDKName"]) {
            
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            if (spoofedVersion) {
                // For SDK and platform keys, add iOS prefix if needed
                if ([key isEqualToString:@"DTPlatformVersion"] || 
                    [key isEqualToString:@"DTSDKName"]) {
                    if (![spoofedVersion hasPrefix:@"iOS"]) {
                        return [NSString stringWithFormat:@"iOS%@", spoofedVersion];
                    }
                    return spoofedVersion;
                }
                return spoofedVersion;
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    return %orig;
}

%end

// Original function pointer for CFBundleGetValueForInfoDictionaryKey
static CFTypeRef (*original_CFBundleGetValueForInfoDictionaryKey)(CFBundleRef bundle, CFStringRef key);

// Replacement function for CFBundleGetValueForInfoDictionaryKey
CFTypeRef replaced_CFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key) {
    @try {
        if (!bundle || !key) return NULL;
        
        // Get the bundle ID for CFBundle
        CFStringRef bundleID = CFBundleGetIdentifier(bundle);
        NSString *nsBundleID = bundleID ? (__bridge NSString*)bundleID : nil;
        // Check for system version keys
        if (CFEqual(key, CFSTR("MinimumOSVersion")) || 
            CFEqual(key, CFSTR("DTPlatformVersion")) ||
            CFEqual(key, CFSTR("DTSDKName"))) {
            
            NSString *spoofedVersion = CurrentPhoneInfo().iosVersion.version;
            if (spoofedVersion) {
                // Log what we're spoofing
                NSLog(@"[iosversion] 💉 Spoofing %@ for bundle %@ to %@", 
                        (__bridge NSString*)key, nsBundleID, spoofedVersion);
                
                // Create a CFString from our spoofed version
                if (CFEqual(key, CFSTR("DTPlatformVersion")) || 
                    CFEqual(key, CFSTR("DTSDKName"))) {
                    
                    if (![spoofedVersion hasPrefix:@"iOS"]) {
                        NSString *prefixedVersion = [NSString stringWithFormat:@"iOS%@", spoofedVersion];
                        return PXCreateCFStringFromNSString(prefixedVersion);
                    }
                }
                
                return PXCreateCFStringFromNSString(spoofedVersion);
            }
        }
        
    } @catch (NSException *e) {
        NSLog(@"[iosversion] ❌ Error in CFBundleGetValueForInfoDictionaryKey hook: %@", e);
    }
    
    // Call original function if available, otherwise return NULL
    if (original_CFBundleGetValueForInfoDictionaryKey) {
        return original_CFBundleGetValueForInfoDictionaryKey(bundle, key);
    } else {
        // For some keys, provide default values
        if (key && (CFEqual(key, CFSTR("MinimumOSVersion")))) {
            // Return the current device's actual iOS version for MinimumOSVersion
            NSString *actualVersion = [[UIDevice currentDevice] systemVersion];
            return PXCreateCFStringFromNSString(actualVersion);
        }
        
        NSLog(@"[iosversion] ℹ️ No original function for CFBundleGetValueForInfoDictionaryKey, returning NULL");
        return NULL;
    }
}



#pragma mark - Constructor



%ctor {
    @autoreleasepool {   
        if (!PXHookEnabled(@"iosversion")) {
            return;
        }
        
        NSLog(@"App is scoped, installing iOS version hooks");
        
        // Force ElleKit hooks to be applied regardless of environment detection
        // This is needed for rootless jailbreaks where EKIsElleKitEnv() might fail
        IOSVERSION_LOG(@"Setting up ElleKit hooks for build number spoofing");
        
        // Hook CoreFoundation version dictionary function
        void *cfFramework = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
        if (cfFramework) {
            // Try several possible symbol names for CFCopySystemVersionDictionary
            const char *symbolNames[] = {
                "CFCopySystemVersionDictionary",
                "_CFCopySystemVersionDictionary",
                "__CFCopySystemVersionDictionary"
            };
            
            void *cfCopySystemVersionDictionaryPtr = NULL;
            for (int i = 0; i < 3; i++) {
                cfCopySystemVersionDictionaryPtr = dlsym(cfFramework, symbolNames[i]);
                if (cfCopySystemVersionDictionaryPtr) {
                    IOSVERSION_LOG(@"Found CoreFoundation symbol: %s", symbolNames[i]);
                    break;
                }
            }
            
            if (cfCopySystemVersionDictionaryPtr) {
                MSHookFunction(cfCopySystemVersionDictionaryPtr, (void *)replaced_CFCopySystemVersionDictionary, (void **)&original_CFCopySystemVersionDictionary);
                IOSVERSION_LOG(@"Successfully hooked CFCopySystemVersionDictionary");
            } else {
                // If we can't find the symbol, create a stub implementation
                IOSVERSION_LOG(@"⚠️ Failed to find CFCopySystemVersionDictionary symbols, using fallback");
                
                // Set original function to NULL and handle it in the replacement function
                original_CFCopySystemVersionDictionary = NULL;
                IOSVERSION_LOG(@"Set original_CFCopySystemVersionDictionary to NULL, will use fallback in replacement function");
            }
            
            // Hook CFBundle info dictionary key function - try different symbol names
            const char *bundleSymbolNames[] = {
                "CFBundleGetValueForInfoDictionaryKey",
                "_CFBundleGetValueForInfoDictionaryKey",
                "__CFBundleGetValueForInfoDictionaryKey"
            };
            
            void *cfBundleGetValueForInfoDictionaryKeyPtr = NULL;
            for (int i = 0; i < 3; i++) {
                cfBundleGetValueForInfoDictionaryKeyPtr = dlsym(cfFramework, bundleSymbolNames[i]);
                if (cfBundleGetValueForInfoDictionaryKeyPtr) {
                    IOSVERSION_LOG(@"Found CFBundle symbol: %s", bundleSymbolNames[i]);
                    break;
                }
            }
            
            if (cfBundleGetValueForInfoDictionaryKeyPtr) {
                MSHookFunction(cfBundleGetValueForInfoDictionaryKeyPtr, (void *)replaced_CFBundleGetValueForInfoDictionaryKey, (void **)&original_CFBundleGetValueForInfoDictionaryKey);
                IOSVERSION_LOG(@"Successfully hooked CFBundleGetValueForInfoDictionaryKey");
            } else {
                // If we can't find the symbol, create a stub implementation
                IOSVERSION_LOG(@"⚠️ Failed to find CFBundleGetValueForInfoDictionaryKey symbols, using fallback");
                
                // Set original function to NULL and handle it in the replacement function
                original_CFBundleGetValueForInfoDictionaryKey = NULL;
                IOSVERSION_LOG(@"Set original_CFBundleGetValueForInfoDictionaryKey to NULL, will use fallback in replacement function");
            }
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to open CoreFoundation framework");
        }
        
        // Hook sysctlbyname for kernel version checks
        void *libSystemHandle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW);
        if (libSystemHandle) {
            void *sysctlbynamePtr = dlsym(libSystemHandle, "sysctlbyname");
            if (sysctlbynamePtr) {
                MSHookFunction(sysctlbynamePtr, (void *)hooked_sysctlbyname, (void **)&original_sysctlbyname);
                IOSVERSION_LOG(@"Hooked sysctlbyname");
            } else {
                IOSVERSION_LOG(@"⚠️ Failed to find sysctlbyname symbol");
            }
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to open libSystem.B.dylib");
        }
        
        // Set up hooks for direct file access methods to catch SystemVersion.plist reads
        IOSVERSION_LOG(@"Setting up hooks for direct file access methods");
        
        // Hook NSData dataWithContentsOfFile:
        Class NSDataClass = objc_getClass("NSData");
        SEL dataWithContentsOfFileSelector = @selector(dataWithContentsOfFile:);
        Method dataWithContentsOfFileMethod = class_getClassMethod(NSDataClass, dataWithContentsOfFileSelector);
        if (dataWithContentsOfFileMethod) {
            original_NSData_dataWithContentsOfFile = (NSData* (*)(Class, SEL, NSString *))method_getImplementation(dataWithContentsOfFileMethod);
            method_setImplementation(dataWithContentsOfFileMethod, (IMP)replaced_NSData_dataWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSData dataWithContentsOfFile:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSData dataWithContentsOfFile:");
        }
        
        // Hook NSDictionary dictionaryWithContentsOfFile:
        Class NSDictionaryClass = objc_getClass("NSDictionary");
        SEL dictWithContentsOfFileSelector = @selector(dictionaryWithContentsOfFile:);
        Method dictWithContentsOfFileMethod = class_getClassMethod(NSDictionaryClass, dictWithContentsOfFileSelector);
        if (dictWithContentsOfFileMethod) {
            original_NSDictionary_dictionaryWithContentsOfFile = (NSDictionary* (*)(Class, SEL, NSString *))method_getImplementation(dictWithContentsOfFileMethod);
            method_setImplementation(dictWithContentsOfFileMethod, (IMP)replaced_NSDictionary_dictionaryWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSDictionary dictionaryWithContentsOfFile:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSDictionary dictionaryWithContentsOfFile:");
        }
        
        // Hook NSString stringWithContentsOfFile:encoding:error:
        Class NSStringClass = objc_getClass("NSString");
        SEL stringWithContentsOfFileSelector = @selector(stringWithContentsOfFile:encoding:error:);
        Method stringWithContentsOfFileMethod = class_getClassMethod(NSStringClass, stringWithContentsOfFileSelector);
        if (stringWithContentsOfFileMethod) {
            original_NSString_stringWithContentsOfFile = (id (*)(Class, SEL, NSString *, NSStringEncoding, NSError **))method_getImplementation(stringWithContentsOfFileMethod);
            method_setImplementation(stringWithContentsOfFileMethod, (IMP)replaced_NSString_stringWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSString stringWithContentsOfFile:encoding:error:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSString stringWithContentsOfFile:encoding:error:");
        }
        
        // Initialize Objective-C hooks for scoped apps only
        %init;
        
        IOSVERSION_LOG(@"iOS Version Hooks successfully initialized for scoped app");
    }
}

#pragma mark - File Access Hooks for SystemVersion.plist

// Function to check if a path is a system version file
static BOOL isSystemVersionFile(NSString *path) {
    if (!path) return NO;
    
    // Normalize path before comparing
    path = [path stringByStandardizingPath];
    return [path isEqualToString:SYSTEM_VERSION_PATH] || 
           [path isEqualToString:ROOTLESS_SYSTEM_VERSION_PATH] ||
           [path hasSuffix:@"SystemVersion.plist"];
}

// Function to spoof a system version plist
static NSDictionary *spoofSystemVersionPlist(NSDictionary *originalPlist) {
    if (!originalPlist) return nil;
        
    // Get our spoofed values
    IosVersion *versionInfo = CurrentPhoneInfo().iosVersion;
    if (!versionInfo || !versionInfo.version || !versionInfo.build) {
        return originalPlist;
    }
    
    // Make a copy with our spoofed values
    NSMutableDictionary *modifiedPlist = [originalPlist mutableCopy];
    
    // Modify the values we want to spoof
    [modifiedPlist setValue:versionInfo.version forKey:@"ProductVersion"];
    [modifiedPlist setValue:versionInfo.build forKey:@"ProductBuildVersion"];
    
    // Only log occasionally to reduce overhead
    static uint64_t lastPlistLogTime = 0;
    uint64_t currentTime = mach_absolute_time();
    if (lastPlistLogTime == 0 || (currentTime - lastPlistLogTime) > THROTTLE_INTERVAL_NSEC * 10) {
        IOSVERSION_LOG(@"📄 Spoofed SystemVersion.plist access: %@ → %@, %@ → %@",
              originalPlist[@"ProductVersion"], versionInfo.version,
              originalPlist[@"ProductBuildVersion"], versionInfo.build);
        lastPlistLogTime = currentTime;
    }
    
    return modifiedPlist;
}

// Hook NSData dataWithContentsOfFile: to intercept SystemVersion.plist reads
NSData* replaced_NSData_dataWithContentsOfFile(Class self, SEL _cmd, NSString *path) {
    NSData *originalData = original_NSData_dataWithContentsOfFile(self, _cmd, path);
    
    if (isSystemVersionFile(path)) {
        // Get the plist as a dictionary from the data
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:originalData 
                                                                        options:0 
                                                                            format:NULL 
                                                                            error:NULL];
        if (plist) {
            // Spoof the values
            NSDictionary *spoofedPlist = spoofSystemVersionPlist(plist);
            
            // Convert back to data
            NSData *spoofedData = [NSPropertyListSerialization dataWithPropertyList:spoofedPlist
                                                                                format:NSPropertyListXMLFormat_v1_0
                                                                            options:0
                                                                                error:NULL];
            if (spoofedData) {
                return spoofedData;
            }
        }
        
    }
    
    return originalData;
}

// Hook NSDictionary dictionaryWithContentsOfFile: to intercept SystemVersion.plist reads
NSDictionary* replaced_NSDictionary_dictionaryWithContentsOfFile(Class self, SEL _cmd, NSString *path) {
    NSDictionary *originalDict = original_NSDictionary_dictionaryWithContentsOfFile(self, _cmd, path);
    
    if (isSystemVersionFile(path) && originalDict) {
        return spoofSystemVersionPlist(originalDict);
        
    }
    
    return originalDict;
}

// Hook NSString stringWithContentsOfFile:encoding:error: to intercept text file reads
id replaced_NSString_stringWithContentsOfFile(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error) {
    id originalString = original_NSString_stringWithContentsOfFile(self, _cmd, path, enc, error);
    
    if (isSystemVersionFile(path) && originalString) {
        // For handling XML/plist files as raw strings
        IosVersion *versionInfo = CurrentPhoneInfo().iosVersion;
        if (versionInfo && versionInfo.version && versionInfo.build) {
            NSString *modifiedString = [originalString mutableCopy];
            modifiedString = [modifiedString stringByReplacingOccurrencesOfString:
                                    [NSString stringWithFormat:@"<key>ProductVersion</key>\\s*<string>[^<]+</string>"]
                                    withString:[NSString stringWithFormat:@"<key>ProductVersion</key><string>%@</string>", versionInfo.version]
                                    options:NSRegularExpressionSearch
                                    range:NSMakeRange(0, [modifiedString length])];
                                    
            modifiedString = [modifiedString stringByReplacingOccurrencesOfString:
                                    [NSString stringWithFormat:@"<key>ProductBuildVersion</key>\\s*<string>[^<]+</string>"]
                                    withString:[NSString stringWithFormat:@"<key>ProductBuildVersion</key><string>%@</string>", versionInfo.build]
                                    options:NSRegularExpressionSearch
                                    range:NSMakeRange(0, [modifiedString length])];
                                    
            return modifiedString;
        }
    
    }
    
    return originalString;
} 

%end

%ctor {
    if (PXHookEnabled(@"iosversion")) {
        %init(PX_iosversion);
    }
}

#import "DataManager.h"
#import "ProjectXLogging.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <errno.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// Define the swap usage structure if it's not available
#import "PXHookOptions.h"
#ifndef HAVE_XSW_USAGE
typedef struct xsw_usage xsw_usage;
#endif

// Original function pointers
static int (*orig_uname)(struct utsname *);
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static __thread BOOL px_sysctlbyname_in_hook = NO;

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *processName = [[NSProcessInfo processInfo] processName];
        PXLog(@"[DeviceModelHooks] ✅ loaded in process=%@ bundle=%@", processName, bundleID);
    }
}

#pragma mark - Hook Implementations

// Hook for uname() system call - used by many apps to detect device model
static int hook_uname(struct utsname *buf) {
    if (!buf) {
        PXLog(@"[model] ⚠️ uname received NULL buffer; returning -1 to avoid crash");
        return -1;
    }
    // Call the original first
    if (!orig_uname) {
        PXLog(@"[model] ⚠️ uname original is NULL; returning -1 to avoid crash");
        return -1;
    }
    int ret = orig_uname(buf);
    
    if (ret != 0) {
        // If original call failed, just return the error
        return ret;
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        return ret; // Can't determine bundle ID, return original result
    }
    
    // Store original value for logging
    char originalMachine[256] = {0};
    if (buf) {
        strlcpy(originalMachine, buf->machine, sizeof(originalMachine));
    }
    
    // Check if we need to spoof
    NSString *spoofedModel = CurrentPhoneInfo().deviceModel.modelName;
    
    if (spoofedModel.length > 0) {
        // Convert spoofed model to a C string and copy it to the utsname struct
        const char *model = [spoofedModel UTF8String];
        if (model) {
            size_t modelLen = strlen(model);
            size_t bufferLen = sizeof(buf->machine);
            
            // Ensure we don't overflow the buffer
            if (modelLen < bufferLen) {
                memset(buf->machine, 0, bufferLen);
                strcpy(buf->machine, model);
                PXLog(@"[model] Spoofed uname machine from %s to: %s for app: %@", 
                        originalMachine, buf->machine, bundleID);
            } else {
                PXLog(@"[model] WARNING: Spoofed model too long for uname buffer");
            }
        }
    } else {
        PXLog(@"[model] WARNING: getSpoofedDeviceModel returned empty string for app: %@", bundleID);
    }

    return ret;
}

// Hook for sysctlbyname - another common way to get device model
// NOTE: Many callers use a 2-step pattern:
//   1) sysctlbyname(name, NULL, &len, NULL, 0)  -> query required length
//   2) allocate buffer(len) then call again to fetch value
// If we don't spoof the *length* in step (1), caller may allocate a buffer that's too small,
// causing our spoof to fail and the caller to fall back to the original value.
static int PXWriteSysctlCString(const char *sysctlNameForLog,
                               const char *valueToUse,
                               void *oldp,
                               size_t *oldlenp) {
    if (!valueToUse || !oldlenp) {
        errno = EINVAL;
        return -1;
    }

    size_t need = strlen(valueToUse) + 1; // include null terminator

    // Size query
    if (oldp == NULL) {
        *oldlenp = need;
        return 0;
    }

    // Buffer too small: sysctl/sysctlbyname convention is ENOMEM and required size in *oldlenp
    if (*oldlenp < need) {
        *oldlenp = need;
        errno = ENOMEM;
        return -1;
    }

    // Write
    memset(oldp, 0, *oldlenp);
    memcpy(oldp, valueToUse, need);
    *oldlenp = need;
    return 0;
}

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctlbyname) {
        errno = ENOSYS;
        return -1;
    }
    if (px_sysctlbyname_in_hook) {
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }
    if (!name) {
        errno = EINVAL;
        return -1;
    }

    // If caller doesn't provide oldlenp we can't safely spoof; pass through.
    if (!oldlenp) {
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }

    px_sysctlbyname_in_hook = YES;

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];

    // Capture original (best-effort) for logging only when caller provided a buffer.
    char originalValue[256] = "<not available>";
    size_t originalLen = sizeof(originalValue);
    int origResult = -1;
    if (oldp != NULL && oldlenp != NULL && *oldlenp > 0) {
        origResult = orig_sysctlbyname(name, originalValue, &originalLen, NULL, 0);
    }

    // Get device specs
    PhoneInfo *pi = CurrentPhoneInfo();
    DeviceModel *model = pi.deviceModel;
    if (!model) {
        px_sysctlbyname_in_hook = NO;
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }

    // CPU architecture for processor-related sysctls
    NSString *cpuArchitecture = model.cpuArchitecture;
    NSInteger cpuCoreCount = [model.cpuCoreCount integerValue];
    NSString *spoofedValue = nil;

    // String sysctls we spoof
    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0) {
        spoofedValue = model.modelName;
    } else if (strcmp(name, "hw.model") == 0) {
        spoofedValue = model.hwModel;
    } else if (strcmp(name, "kern.osproductversion") == 0) {
        spoofedValue = pi.iosVersion.version;
    }

    // Integer sysctls
    if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0) {
        if (cpuCoreCount > 0 && oldp != NULL) {
            if (*oldlenp == sizeof(uint32_t)) {
                *(uint32_t *)oldp = (uint32_t)cpuCoreCount;
                px_sysctlbyname_in_hook = NO;
                return 0;
            } else if (*oldlenp == sizeof(int)) {
                *(int *)oldp = (int)cpuCoreCount;
                px_sysctlbyname_in_hook = NO;
                return 0;
            } else if (*oldlenp == sizeof(unsigned long)) {
                *(unsigned long *)oldp = (unsigned long)cpuCoreCount;
                px_sysctlbyname_in_hook = NO;
                return 0;
            }
        }
        // fall through to original if sizes don't match or oldp NULL
    }

    // CPU brand/model strings
    if (strcmp(name, "hw.cpu.brand_string") == 0 || strcmp(name, "hw.cpubrand") == 0) {
        if (cpuArchitecture && cpuArchitecture.length > 0) {
            const char *cpuBrand = [cpuArchitecture UTF8String];
            int w = PXWriteSysctlCString(name, cpuBrand, oldp, oldlenp);
            if (w == 0) {
                px_sysctlbyname_in_hook = NO;
                return 0;
            }
            // If ENOMEM, propagate so caller reallocates correctly
            px_sysctlbyname_in_hook = NO;
            return w;
        }
    }

    // If we have a spoofed string value, write it with proper length semantics.
    if (spoofedValue.length > 0) {
        const char *valueToUse = [spoofedValue UTF8String];
        int w = PXWriteSysctlCString(name, valueToUse, oldp, oldlenp);

        if (w == 0 && oldp != NULL) {
            if (origResult == 0) {
                PXLog(@"[model] Spoofed sysctlbyname %s from: %s to: %s for app: %@",
                      name, originalValue, valueToUse, bundleID);
            } else {
                PXLog(@"[model] Spoofed sysctlbyname %s to: %s for app: %@",
                      name, valueToUse, bundleID);
            }
        }
        px_sysctlbyname_in_hook = NO;
        return w;
    }

    // For all other cases, pass through to the original function
    int result = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    px_sysctlbyname_in_hook = NO;
    return result;
}



// Hook for UIDevice methods - many apps use combinations of these
%group PX_devicemodel

%hook UIDevice

- (NSString *)model {
    NSString *originalModel = %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (!bundleID) {
        return originalModel;
    }
    
    // Always log access to help with debugging
    PXLog(@"[model] App %@ checked UIDevice model: %@", bundleID, originalModel);
    
    // Only spoof if enabled for this app
    NSString *spoofedModel = CurrentPhoneInfo().deviceModel.modelName;
    if (spoofedModel.length > 0) {
        PXLog(@"[model] Spoofing UIDevice model from %@ to %@ for app: %@", 
                originalModel, spoofedModel, bundleID);
        return spoofedModel;
    }
    
    
    return originalModel;
}

- (NSString *)name {
    // Just log access but don't spoof - this is device name, not model
    NSString *originalName = %orig;
    PXLog(@"[model] App checked UIDevice name: %@",  originalName);
    
    
    return originalName;
}

- (NSString *)systemName {
    // Just log access but don't spoof - this is iOS, not device model
    NSString *originalName = %orig;    
    PXLog(@"[model] App checked UIDevice systemName: %@", originalName);
    
    
    return originalName;
}

- (NSString *)localizedModel {
    NSString *originalModel = %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (!bundleID) {
        return originalModel;
    }
    
    // Always log access to help with debugging
    PXLog(@"[model] App %@ checked UIDevice localizedModel: %@", bundleID, originalModel);
     
    NSString *spoofedModel = CurrentPhoneInfo().deviceModel.modelName;
    if (spoofedModel.length > 0) {
        PXLog(@"[model] Spoofing UIDevice localizedModel from %@ to %@ for app: %@", 
                originalModel, spoofedModel, bundleID);
        return spoofedModel;
    }

    
    return originalModel;
}

%end

// Add NSDictionary+machineName hook - a common extension in iOS apps to map device model codes
%hook NSDictionary

+ (NSDictionary *)dictionaryWithContentsOfURL:(NSURL *)url {
    NSDictionary *result = %orig;
    
    if (url) {
        NSString *urlStr = [url absoluteString];
        if ([urlStr containsString:@"device"] || [urlStr containsString:@"model"]) {
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            PXLog(@"[model] App %@ loaded dictionary with URL: %@", bundleID, urlStr);
        }
    }
    
    return result;
}

%end

// This declaration was already added at the top of the file, so remove this duplicate declaration
// static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);

static __thread BOOL px_sysctl_in_hook = NO;

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctl) {
        PXLog(@"[model] ⚠️ sysctl original is NULL; returning -1 to avoid crash");
        errno = ENOSYS;
        return -1;
    }
    if (!name) {
        PXLog(@"[model] ⚠️ sysctl received NULL name; returning -1 to avoid crash");
        errno = EINVAL;
        return -1;
    }
    if (px_sysctl_in_hook) {
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    }

    // If caller doesn't provide oldlenp we can't spoof safely.
    if (!oldlenp) {
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    }

    px_sysctl_in_hook = YES;

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        int r = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
        px_sysctl_in_hook = NO;
        return r;
    }

    BOOL isHWMachine = (namelen >= 2 && name[0] == 6 /*CTL_HW*/ && name[1] == 1 /*HW_MACHINE*/);
    BOOL isHWModel   = (namelen >= 2 && name[0] == 6 /*CTL_HW*/ && name[1] == 2 /*HW_MODEL*/);
    BOOL isModelQuery = isHWMachine || isHWModel;

    if (isModelQuery) {
        NSString *spoofed = isHWMachine ? CurrentPhoneInfo().deviceModel.modelName
                                        : CurrentPhoneInfo().deviceModel.hwModel;
        if (spoofed.length > 0) {
            const char *valueToUse = [spoofed UTF8String];
            // Respect sysctl length semantics
            int w = PXWriteSysctlCString(isHWMachine ? "hw.machine" : "hw.model", valueToUse, oldp, oldlenp);

            // Log only on successful write with a buffer
            if (w == 0 && oldp != NULL) {
                PXLog(@"[model] Spoofed sysctl CTL_HW %@ to: %s for app: %@",
                      isHWMachine ? @"hw.machine" : @"hw.model", valueToUse, bundleID);
            }

            px_sysctl_in_hook = NO;
            return w;
        }
    }

    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    px_sysctl_in_hook = NO;
    return ret;
}



%ctor {
    @autoreleasepool {
        PXLog(@"[model] Initializing device model spoofing hooks");
        
        // Initialize the hooks with error handling
        @try {
            MSHookFunction(uname, hook_uname, (void **)&orig_uname);
            PXLog(@"[model] Hooked uname() successfully");
        } @catch (NSException *e) {
            PXLog(@"[model] ERROR hooking uname(): %@", e);
        }
        
        @try {
            MSHookFunction(sysctlbyname, hook_sysctlbyname, (void **)&orig_sysctlbyname);
            PXLog(@"[model] Hooked sysctlbyname() successfully");
        } @catch (NSException *e) {
            PXLog(@"[model] ERROR hooking sysctlbyname(): %@", e);
        }
        
        @try {
            void *sysctlPtr = dlsym(RTLD_DEFAULT, "sysctl");
            if (sysctlPtr) {
                MSHookFunction(sysctlPtr, (void *)hook_sysctl, (void **)&orig_sysctl);
                PXLog(@"[model] Hooked sysctl() successfully");
            } else {
                PXLog(@"[model] Could not find sysctl symbol");
            }
        } @catch (NSException *e) {
            PXLog(@"[model] ERROR hooking sysctl(): %@", e);
        }
    }
}

%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init(PX_devicemodel);
    }
}

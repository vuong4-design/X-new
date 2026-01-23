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

// Log throttling: log each sysctl key once per process (to avoid spam)
static CFMutableSetRef gPXLoggedSysctlKeys = NULL;

static void PXEnsureLoggedSysctlKeySet(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gPXLoggedSysctlKeys = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
    });
}

static BOOL PXShouldLogSysctlKeyOnce(const char *name) {
    if (!name) return NO;
    PXEnsureLoggedSysctlKeySet();
    CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
    if (!key) return NO;
    BOOL should = !CFSetContainsValue(gPXLoggedSysctlKeys, key);
    if (should) CFSetAddValue(gPXLoggedSysctlKeys, key);
    CFRelease(key);
    return should;
}

static int PXWriteSysctlCString(const char *name, const char *value, void *oldp, size_t *oldlenp) {
    if (!oldlenp || !value) { errno = EINVAL; return -1; }
    size_t required = strlen(value) + 1; // include NUL
    if (!oldp) {
        *oldlenp = required;
        return 0;
    }
    if (*oldlenp < required) {
        *oldlenp = required;
        errno = ENOMEM;
        return -1;
    }
    memset(oldp, 0, *oldlenp);
    memcpy(oldp, value, required);
    *oldlenp = required;
    return 0;
}

static int PXWriteSysctlInt64(const char *name, int64_t v, void *oldp, size_t *oldlenp) {
    if (!oldlenp) { errno = EINVAL; return -1; }
    // Keep caller's expected size when possible
    if (!oldp) {
        // Ask original for size if available; otherwise default to 8
        *oldlenp = (*oldlenp ? *oldlenp : sizeof(int64_t));
        return 0;
    }
    if (*oldlenp == sizeof(int)) {
        *(int *)oldp = (int)v;
        return 0;
    }
    if (*oldlenp == sizeof(uint32_t)) {
        *(uint32_t *)oldp = (uint32_t)v;
        return 0;
    }
    if (*oldlenp == sizeof(unsigned long)) {
        *(unsigned long *)oldp = (unsigned long)v;
        return 0;
    }
    if (*oldlenp >= sizeof(int64_t)) {
        *(int64_t *)oldp = (int64_t)v;
        return 0;
    }
    errno = ENOMEM;
    return -1;
}

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
static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctlbyname) return -1;
    if (px_sysctlbyname_in_hook) return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    if (!name) { errno = EINVAL; return -1; }

    px_sysctlbyname_in_hook = YES;

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"<unknown>";
    PhoneInfo *info = CurrentPhoneInfo();
    DeviceModel *model = info.deviceModel;
    IosVersion *iv = info.iosVersion;

    // If we don't have data, fall back immediately
    if (!model || !iv) {
        px_sysctlbyname_in_hook = NO;
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }

    // Capture original value for nicer logs (best effort, not for size queries)
    char originalValue[256] = "<not available>";
    size_t originalLen = sizeof(originalValue);
    (void)orig_sysctlbyname(name, originalValue, &originalLen, NULL, 0);

    // ---- New additions requested ----
    // kern.ostype => "Darwin"
    if (strcmp(name, "kern.ostype") == 0) {
        const char *v = "Darwin";
        int r = PXWriteSysctlCString(name, v, oldp, oldlenp);
        if (r == 0 && PXShouldLogSysctlKeyOnce(name)) {
            PXLog(@"[model] Spoofed sysctlbyname %s from: %s to: %s for app: %@", name, originalValue, v, bundleID);
        }
        px_sysctlbyname_in_hook = NO;
        return r;
    }

    // kern.osrelease => iv.darwin (e.g. "20.2.0")
    if (strcmp(name, "kern.osrelease") == 0) {
        const char *v = iv.darwin ? [iv.darwin UTF8String] : NULL;
        if (v) {
            int r = PXWriteSysctlCString(name, v, oldp, oldlenp);
            if (r == 0 && PXShouldLogSysctlKeyOnce(name)) {
                PXLog(@"[model] Spoofed sysctlbyname %s from: %s to: %s for app: %@", name, originalValue, v, bundleID);
            }
            px_sysctlbyname_in_hook = NO;
            return r;
        }
    }

    // kern.version => iv.kernelVersion (long string)
    if (strcmp(name, "kern.version") == 0) {
        const char *v = iv.kernelVersion ? [iv.kernelVersion UTF8String] : NULL;
        if (v) {
            int r = PXWriteSysctlCString(name, v, oldp, oldlenp);
            if (r == 0 && PXShouldLogSysctlKeyOnce(name)) {
                PXLog(@"[model] Spoofed sysctlbyname %s for app: %@", name, bundleID);
            }
            px_sysctlbyname_in_hook = NO;
            return r;
        }
    }

    // kern.hostname => info.deviceName
    if (strcmp(name, "kern.hostname") == 0) {
        const char *v = info.deviceName ? [info.deviceName UTF8String] : NULL;
        if (v) {
            int r = PXWriteSysctlCString(name, v, oldp, oldlenp);
            if (r == 0 && PXShouldLogSysctlKeyOnce(name)) {
                PXLog(@"[model] Spoofed sysctlbyname %s from: %s to: %s for app: %@", name, originalValue, v, bundleID);
            }
            px_sysctlbyname_in_hook = NO;
            return r;
        }
    }

    // hw.physicalcpu / hw.physicalcpu_max / hw.logicalcpu / hw.logicalcpu_max
    if (strcmp(name, "hw.physicalcpu") == 0 ||
        strcmp(name, "hw.physicalcpu_max") == 0 ||
        strcmp(name, "hw.logicalcpu") == 0 ||
        strcmp(name, "hw.logicalcpu_max") == 0) {

        int64_t cores = (int64_t)[model.cpuCoreCount integerValue];
        if (cores > 0) {
            // Preserve original expected size on size-only query
            if (!oldp && oldlenp) {
                // Ask original for size so caller allocates the same amount
                size_t tmp = 0;
                (void)orig_sysctlbyname(name, NULL, &tmp, NULL, 0);
                if (tmp > 0) *oldlenp = tmp;
                px_sysctlbyname_in_hook = NO;
                return 0;
            }

            int r = PXWriteSysctlInt64(name, cores, oldp, oldlenp);
            if (r == 0 && PXShouldLogSysctlKeyOnce(name)) {
                PXLog(@"[model] Spoofed sysctlbyname %s from: %s to: %lld for app: %@", name, originalValue, (long long)cores, bundleID);
            }
            px_sysctlbyname_in_hook = NO;
            return r;
        }
    }

    // ---- Existing behavior (but fixed for proper size-query semantics) ----
    // NOTE: We must handle (oldp==NULL, oldlenp!=NULL) correctly, or callers will allocate
    // too-small buffers and we will later log "value too long".
    NSString *spoofedStr = nil;

    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0) {
        spoofedStr = model.modelName;
    } else if (strcmp(name, "hw.model") == 0) {
        spoofedStr = model.hwModel;
    } else if (strcmp(name, "kern.osproductversion") == 0) {
        spoofedStr = iv.version;
    }

    if (spoofedStr) {
        const char *v = [spoofedStr UTF8String];
        int r = PXWriteSysctlCString(name, v, oldp, oldlenp);
        if (r == 0 && PXShouldLogSysctlKeyOnce(name)) {
            PXLog(@"[model] Spoofed sysctlbyname %s from: %s to: %s for app: %@", name, originalValue, v, bundleID);
        }
        px_sysctlbyname_in_hook = NO;
        return r;
    }

    // CPU-related sysctls you already handled
    if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0) {
        int64_t cores = (int64_t)[model.cpuCoreCount integerValue];
        if (cores > 0) {
            if (!oldp && oldlenp) {
                size_t tmp = 0;
                (void)orig_sysctlbyname(name, NULL, &tmp, NULL, 0);
                if (tmp > 0) *oldlenp = tmp;
                px_sysctlbyname_in_hook = NO;
                return 0;
            }
            int r = PXWriteSysctlInt64(name, cores, oldp, oldlenp);
            if (r == 0 && PXShouldLogSysctlKeyOnce(name)) {
                PXLog(@"[model] Spoofed sysctlbyname %s to: %lld for app: %@", name, (long long)cores, bundleID);
            }
            px_sysctlbyname_in_hook = NO;
            return r;
        }
    }

    // Fall back to original for everything else
    px_sysctlbyname_in_hook = NO;
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}


static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctl) {
        PXLog(@"[model] ⚠️ sysctl original is NULL; returning -1 to avoid crash");
        return -1;
    }
    if (!name) {
        PXLog(@"[model] ⚠️ sysctl received NULL name; returning -1 to avoid crash");
        return -1;
    }
    // Get the bundle ID first to determine if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    }

    // Safety: if caller passes NULL out pointers (common anti-tamper probe), do not spoof or touch them
    if (!oldp || !oldlenp) {
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    }
    
    // Check if this is a hardware model (CTL_HW + HW_MACHINE) or hw.model (CTL_HW + HW_MODEL) query
    BOOL isHWMachine = (namelen >= 2 && name[0] == 6 /*CTL_HW*/ && name[1] == 1 /*HW_MACHINE*/);
    BOOL isHWModel = (namelen >= 2 && name[0] == 6 /*CTL_HW*/ && name[1] == 2 /*HW_MODEL*/);
    BOOL isModelQuery = isHWMachine || isHWModel;
    
    // Store original value for logging if this is a hardware query
    char originalValue[256] = "<not available>";
    
    if (isModelQuery && oldp && oldlenp && *oldlenp > 0) {
        // Make a copy of oldp and oldlenp to get original value
        void *origBuf = malloc(*oldlenp);
        size_t origLen = *oldlenp;
        
        if (origBuf) {
            int origResult = orig_sysctl(name, namelen, origBuf, &origLen, NULL, 0);
            if (origResult == 0) {
                strlcpy(originalValue, origBuf, sizeof(originalValue));
            }
            free(origBuf);
        }
    }
    
    // Call original function to get the original value
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    
    // Check if this is a hardware model query and if we need to spoof it
    if (ret == 0 && isModelQuery) {
        if (oldp && oldlenp && *oldlenp > 0) {
            NSString *spoofedValue = nil;
            
            // Get the appropriate spoofed value based on the query type
            if (isHWMachine) {
                spoofedValue = CurrentPhoneInfo().deviceModel.modelName;
            } else if (isHWModel) {
                spoofedValue = CurrentPhoneInfo().deviceModel.hwModel;
            }
            
            if (spoofedValue.length > 0) {
                const char *valueToUse = [spoofedValue UTF8String];
                if (valueToUse) {
                    size_t valueLen = strlen(valueToUse);
                    
                    // Ensure we don't overflow the buffer
                    if (valueLen < *oldlenp) {
                        memset(oldp, 0, *oldlenp);
                        strcpy(oldp, valueToUse);
                        PXLog(@"[model] Spoofed sysctl CTL_HW %@ from %s to: %s for app: %@", 
                             isHWMachine ? @"hw.machine" : @"hw.model", originalValue, valueToUse, bundleID);
                    } else {
                        PXLog(@"[model] WARNING: Spoofed value too long for sysctl buffer");
                    }
                }
            } else {
                PXLog(@"[model] WARNING: Failed to get spoofed value for %@", 
                     isHWMachine ? @"hw.machine" : @"hw.model");
            }
        } else {
            // Just log the access without spoofing
            PXLog(@"[model] App %@ checked sysctl CTL_HW %@: %s", 
                 bundleID, isHWMachine ? @"hw.machine" : @"hw.model", originalValue);
        }
    }
    
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

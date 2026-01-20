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
static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctlbyname) {
        return -1;
    }
    if (px_sysctlbyname_in_hook) {
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }
    if (!name) {
        errno = EINVAL;
        return -1;
    }
    // Safety: if caller passes NULL out pointers, do not spoof or touch them
    if (!oldp || !oldlenp) {
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }
    px_sysctlbyname_in_hook = YES;

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    // if (isHWMachine || isHWModel || isOSVersion) {
        // Make a copy of the original value for logging purposes
    char originalValue[256] = "<not available>";
    size_t originalLen = sizeof(originalValue);

    // Get the original value first to show before/after in logs
    int origResult = orig_sysctlbyname(name, originalValue, &originalLen, NULL, 0);


    // Get device specs
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        px_sysctlbyname_in_hook = NO;
        return origResult;
    }

    // Get CPU architecture for processor-related sysctls
    NSString *cpuArchitecture = model.cpuArchitecture;
    NSInteger cpuCoreCount = [model.cpuCoreCount integerValue];
    NSString *spoofedValue = nil;

    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0){
        spoofedValue = model.modelName;
    }else if (strcmp(name, "hw.model") == 0){
        spoofedValue = model.hwModel;
    }else if(strcmp(name, "kern.osproductversion") == 0){
        spoofedValue = CurrentPhoneInfo().iosVersion.version;
    }
    // Handle CPU-related sysctls
    else if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0) {
        // Number of CPUs / Active CPUs
        if (cpuCoreCount > 0 && oldp && oldlenp) {
            if (*oldlenp == sizeof(uint32_t)) {
                *(uint32_t *)oldp = (uint32_t)cpuCoreCount;
            } else if (*oldlenp == sizeof(int)) {
                *(int *)oldp = (int)cpuCoreCount;
            } else if (*oldlenp == sizeof(unsigned long)) {
                *(unsigned long *)oldp = (unsigned long)cpuCoreCount;
            }
            px_sysctlbyname_in_hook = NO;
            return 0;
        }
    }
    else if (strcmp(name, "hw.cpu.brand_string") == 0 || strcmp(name, "hw.cpubrand") == 0 || strcmp(name, "hw.model") == 0) {
        // CPU Brand/Model Name - return the processor name like "Apple A11 Bionic"
        if (cpuArchitecture && cpuArchitecture.length > 0) {
            const char *cpuBrand = [cpuArchitecture UTF8String];
            if (cpuBrand && oldp && oldlenp && *oldlenp > 0) {
                size_t brandLen = strlen(cpuBrand);
                if (brandLen < *oldlenp) {
                    *oldlenp = brandLen + 1;
                    memset(oldp, 0, *oldlenp);
                    strcpy(oldp, cpuBrand);
                    px_sysctlbyname_in_hook = NO;
                    return 0;
                } else {
                    PXLog(@"[DeviceSpec] WARNING: CPU brand string too long for buffer");
                }
            }
        }
    }
    else if (strcmp(name, "hw.cputype") == 0) {
        // CPU Type - ARM64 is already defined as CPU_TYPE_ARM64 in system headers
        if (oldp && oldlenp && *oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = CPU_TYPE_ARM64;
            px_sysctlbyname_in_hook = NO;
            return 0;
        }
    }
    else if (strcmp(name, "hw.cpusubtype") == 0) {
        // CPU Subtype - varies by processor
        uint32_t cpuSubtype = 0;
        
        if (cpuArchitecture) {
            if ([cpuArchitecture containsString:@"A9"]) {
                cpuSubtype = 2; // A9 subtype
            } else if ([cpuArchitecture containsString:@"A10"]) {
                cpuSubtype = 3; // A10 subtype  
            } else if ([cpuArchitecture containsString:@"A11"]) {
                cpuSubtype = 4; // A11 subtype
            } else if ([cpuArchitecture containsString:@"A12"]) {
                cpuSubtype = 5; // A12 subtype
            } else if ([cpuArchitecture containsString:@"A13"]) {
                cpuSubtype = 6; // A13 subtype
            } else if ([cpuArchitecture containsString:@"A14"]) {
                cpuSubtype = 7; // A14 subtype
            } else if ([cpuArchitecture containsString:@"A15"]) {
                cpuSubtype = 8; // A15 subtype
            } else if ([cpuArchitecture containsString:@"A16"]) {
                cpuSubtype = 9; // A16 subtype
            } else if ([cpuArchitecture containsString:@"A17"]) {
                cpuSubtype = 10; // A17 subtype
            } else if ([cpuArchitecture containsString:@"A18"]) {
                cpuSubtype = 11; // A18 subtype
            } else if ([cpuArchitecture containsString:@"M1"]) {
                cpuSubtype = 12; // M1 subtype
            } else if ([cpuArchitecture containsString:@"M2"]) {
                cpuSubtype = 13; // M2 subtype
            } else {
                cpuSubtype = 1; // Default ARM64 subtype
            }
        }
        
        if (oldp && oldlenp && *oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = cpuSubtype;
        }
    }
    else if (strcmp(name, "hw.cpufamily") == 0) {
        // CPU Family - unique identifier for each processor family
        uint32_t cpuFamily = 0;
        
        if (cpuArchitecture) {
            if ([cpuArchitecture containsString:@"A9"]) {
                cpuFamily = 0x67CEEE93; // Apple A9 family
            } else if ([cpuArchitecture containsString:@"A10"]) {
                cpuFamily = 0x92FB37C8; // Apple A10 family
            } else if ([cpuArchitecture containsString:@"A11"]) {
                cpuFamily = 0xDA33D83D; // Apple A11 family
            } else if ([cpuArchitecture containsString:@"A12"]) {
                cpuFamily = 0x8765EDEA; // Apple A12 family
            } else if ([cpuArchitecture containsString:@"A13"]) {
                cpuFamily = 0xAF4F32CB; // Apple A13 family
            } else if ([cpuArchitecture containsString:@"A14"]) {
                cpuFamily = 0x1B588BB3; // Apple A14 family
            } else if ([cpuArchitecture containsString:@"A15"]) {
                cpuFamily = 0xDA33D83D; // Apple A15 family
            } else if ([cpuArchitecture containsString:@"A16"]) {
                cpuFamily = 0x8765EDEA; // Apple A16 family
            } else if ([cpuArchitecture containsString:@"A17"]) {
                cpuFamily = 0xAF4F32CB; // Apple A17 family
            } else if ([cpuArchitecture containsString:@"A18"]) {
                cpuFamily = 0x1B588BB3; // Apple A18 family
            } else if ([cpuArchitecture containsString:@"M1"]) {
                cpuFamily = 0x458F4D97; // Apple M1 family
            } else if ([cpuArchitecture containsString:@"M2"]) {
                cpuFamily = 0x458F4D97; // Apple M2 family (same as M1)
            } else {
                cpuFamily = 0x67CEEE93; // Default ARM64 family
            }
        }
        
        if (oldp && oldlenp && *oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = cpuFamily;
        }
    }
    else if (strcmp(name, "hw.cpufrequency") == 0 || strcmp(name, "hw.cpufrequency_max") == 0 || strcmp(name, "hw.cpufrequency_min") == 0) {
        // CPU Frequency - approximate values based on processor
        uint64_t cpuFrequency = 0;
        
        if (cpuArchitecture) {
            if ([cpuArchitecture containsString:@"A9"]) {
                cpuFrequency = 1800000000; // 1.8 GHz
            } else if ([cpuArchitecture containsString:@"A10"]) {
                cpuFrequency = 2340000000; // 2.34 GHz
            } else if ([cpuArchitecture containsString:@"A11"]) {
                cpuFrequency = 2390000000; // 2.39 GHz
            } else if ([cpuArchitecture containsString:@"A12"]) {
                cpuFrequency = 2490000000; // 2.49 GHz
            } else if ([cpuArchitecture containsString:@"A13"]) {
                cpuFrequency = 2650000000; // 2.65 GHz
            } else if ([cpuArchitecture containsString:@"A14"]) {
                cpuFrequency = 2990000000; // 2.99 GHz
            } else if ([cpuArchitecture containsString:@"A15"]) {
                cpuFrequency = 3230000000; // 3.23 GHz
            } else if ([cpuArchitecture containsString:@"A16"]) {
                cpuFrequency = 3460000000; // 3.46 GHz
            } else if ([cpuArchitecture containsString:@"A17"]) {
                cpuFrequency = 3780000000; // 3.78 GHz
            } else if ([cpuArchitecture containsString:@"A18"]) {
                cpuFrequency = 4050000000; // 4.05 GHz
            } else if ([cpuArchitecture containsString:@"M1"]) {
                cpuFrequency = 3200000000; // 3.2 GHz
            } else if ([cpuArchitecture containsString:@"M2"]) {
                cpuFrequency = 3490000000; // 3.49 GHz
            } else {
                cpuFrequency = 2000000000; // Default 2.0 GHz
            }
            
            // Adjust for min/max variants
            if (strcmp(name, "hw.cpufrequency_min") == 0) {
                cpuFrequency = cpuFrequency * 0.4; // Min is typically 40% of max
            }
        }
        
        if (oldp && oldlenp && *oldlenp >= sizeof(uint64_t)) {
            *(uint64_t *)oldp = cpuFrequency;
        } else if (*oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = (uint32_t)cpuFrequency;
        }
    }
    else if (strcmp(name, "hw.cachelinesize") == 0) {
        // Cache line size - typically 64 bytes for ARM64
        uint32_t cacheLineSize = 64;
        
        if (oldp && oldlenp && *oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = cacheLineSize;
        }
    }
    else if (strcmp(name, "hw.l1icachesize") == 0 || strcmp(name, "hw.l1dcachesize") == 0 || 
             strcmp(name, "hw.l2cachesize") == 0) {
        // Cache sizes vary by processor
        uint32_t cacheSize = 0;
        
        if (cpuArchitecture) {
            BOOL isL1 = (strcmp(name, "hw.l1icachesize") == 0 || strcmp(name, "hw.l1dcachesize") == 0);
            BOOL isL2 = (strcmp(name, "hw.l2cachesize") == 0);
            
            if ([cpuArchitecture containsString:@"A9"]) {
                cacheSize = isL1 ? 32768 : (isL2 ? 3145728 : 0); // 32KB L1, 3MB L2
            } else if ([cpuArchitecture containsString:@"A10"]) {
                cacheSize = isL1 ? 32768 : (isL2 ? 3145728 : 0); // 32KB L1, 3MB L2  
            } else if ([cpuArchitecture containsString:@"A11"]) {
                cacheSize = isL1 ? 32768 : (isL2 ? 8388608 : 0); // 32KB L1, 8MB L2
            } else if ([cpuArchitecture containsString:@"A12"]) {
                cacheSize = isL1 ? 32768 : (isL2 ? 8388608 : 0); // 32KB L1, 8MB L2
            } else if ([cpuArchitecture containsString:@"A13"]) {
                cacheSize = isL1 ? 65536 : (isL2 ? 8388608 : 0); // 64KB L1, 8MB L2
            } else if ([cpuArchitecture containsString:@"A14"] || [cpuArchitecture containsString:@"A15"]) {
                cacheSize = isL1 ? 65536 : (isL2 ? 12582912 : 0); // 64KB L1, 12MB L2
            } else if ([cpuArchitecture containsString:@"A16"] || [cpuArchitecture containsString:@"A17"]) {
                cacheSize = isL1 ? 65536 : (isL2 ? 16777216 : 0); // 64KB L1, 16MB L2
            } else if ([cpuArchitecture containsString:@"A18"]) {
                cacheSize = isL1 ? 131072 : (isL2 ? 20971520 : 0); // 128KB L1, 20MB L2
            } else if ([cpuArchitecture containsString:@"M1"]) {
                cacheSize = isL1 ? 131072 : (isL2 ? 12582912 : 0); // 128KB L1, 12MB L2
            } else if ([cpuArchitecture containsString:@"M2"]) {
                cacheSize = isL1 ? 131072 : (isL2 ? 16777216 : 0); // 128KB L1, 16MB L2
            } else {
                cacheSize = isL1 ? 32768 : (isL2 ? 3145728 : 0); // Default
            }
        }
        
        if (*oldlenp >= sizeof(uint32_t) && cacheSize > 0) {
            *(uint32_t *)oldp = cacheSize;
        }
    }
    // Handle memory-related sysctls
    else if (strcmp(name, "hw.memsize") == 0 || strcmp(name, "hw.physmem") == 0) {
        // Get the device memory from specs (in GB)
        NSInteger deviceMemoryGB = [CurrentPhoneInfo().deviceModel.deviceMemory integerValue];
        if (deviceMemoryGB <= 0) {
            return origResult;
        }
        
        // Calculate total memory in bytes
        unsigned long long totalMemory = deviceMemoryGB * 1024 * 1024 * 1024;
        
        // Different sysctls might return different size types
        if (oldp && oldlenp && *oldlenp == sizeof(uint64_t)) {
            *(uint64_t *)oldp = totalMemory;
        } else if (*oldlenp == sizeof(uint32_t)) {
            *(uint32_t *)oldp = (uint32_t)totalMemory;
        } else if (*oldlenp == sizeof(unsigned long)) {
            *(unsigned long *)oldp = (unsigned long)totalMemory;
        }
        
    } else if (strcmp(name, "vm.swapusage") == 0 && *oldlenp >= sizeof(xsw_usage)) {
        // Swap usage information
        xsw_usage *swap = (xsw_usage *)oldp;
        
        // Get the device memory from specs (in GB)
        NSInteger deviceMemoryGB = [model.deviceMemory integerValue];
        if (deviceMemoryGB <= 0) {
            return origResult;
        }
        
        // Calculate realistic swap values based on device memory
        // iOS typically uses swap space proportional to RAM
        uint64_t totalMemory = deviceMemoryGB * 1024 * 1024 * 1024;
        
        // Typical iOS swap is ~50-100% of RAM depending on device
        float swapRatio = (deviceMemoryGB >= 4) ? 0.5 : 1.0;  // Less swap on high-RAM devices
        
        swap->xsu_total = totalMemory * swapRatio;
        swap->xsu_avail = totalMemory * swapRatio * 0.7;  // 70% available
        swap->xsu_used = totalMemory * swapRatio * 0.3;   // 30% used
        
    }
    // Add additional CPU feature and identification sysctls
    else if (strncmp(name, "hw.optional.", 12) == 0) {
        // Handle CPU feature flags - these indicate specific CPU capabilities
        // Most ARM64 devices support these features consistently
        BOOL featureSupported = YES;
        
        // Some features that might not be supported on older processors
        if (cpuArchitecture) {
            if (strstr(name, "arm64e") && [cpuArchitecture containsString:@"A9"]) {
                featureSupported = NO; // A9 doesn't support arm64e
            } else if (strstr(name, "armv8_3") && ([cpuArchitecture containsString:@"A9"] || [cpuArchitecture containsString:@"A10"])) {
                featureSupported = NO; // A9/A10 don't support ARMv8.3
            }
        }
        
        if (oldp && oldlenp && *oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = featureSupported ? 1 : 0;
        }
    }
    else if (strcmp(name, "hw.cpu.features") == 0) {
        // CPU features string - return a realistic feature set
        NSString *cpuFeatures = @"SSE SSE2 SSE3 SSSE3 SSE4.1 SSE4.2 AES AVX AVX2 BMI1 BMI2 FMA";
        
        // For ARM64, use ARM-specific features
        if (cpuArchitecture) {
            if ([cpuArchitecture containsString:@"A17"] || [cpuArchitecture containsString:@"A18"] || [cpuArchitecture containsString:@"M"]) {
                cpuFeatures = @"NEON AES SHA1 SHA2 CRC32 ATOMICS FP16 JSCVT FCMA LRCPC";
            } else if ([cpuArchitecture containsString:@"A15"] || [cpuArchitecture containsString:@"A16"]) {
                cpuFeatures = @"NEON AES SHA1 SHA2 CRC32 ATOMICS FP16 JSCVT";
            } else {
                cpuFeatures = @"NEON AES SHA1 SHA2 CRC32 ATOMICS";
            }
        }
        
        const char *featuresStr = [cpuFeatures UTF8String];
        if (featuresStr && oldp && oldlenp && *oldlenp > 0) {
            size_t featuresLen = strlen(featuresStr);
            if (featuresLen < *oldlenp) {
                *oldlenp = featuresLen + 1;
                memset(oldp, 0, *oldlenp);
                strcpy(oldp, featuresStr);
            }
        }
    }else if (name && strcmp(name, "kern.boottime") == 0) {
        NSDate * bootTime = CurrentPhoneInfo().upTimeInfo.bootTime;
        if (bootTime && oldp && oldlenp && *oldlenp >= sizeof(struct timeval)) {
            struct timeval boottime;
            boottime.tv_sec = (time_t)[bootTime timeIntervalSince1970];
            boottime.tv_usec = 0;
            memcpy(oldp, &boottime, sizeof(boottime));
            *oldlenp = sizeof(boottime);
            px_sysctlbyname_in_hook = NO;
            return 0; // Success
        }
    }
    else{
        PXLog(@"[DeviceSpec] ***not hooked name:%s",name);
    }
    
    if (spoofedValue.length > 0 && oldp && oldlenp && *oldlenp > 0) {
        const char *valueToUse = [spoofedValue UTF8String];
        if (valueToUse) {
            size_t valueLen = strlen(valueToUse);
            
            // Ensure we don't overflow the buffer
            if (valueLen < *oldlenp) {
                *oldlenp = valueLen + 1; // +1 for null terminator
                memset(oldp, 0, *oldlenp);
                strcpy(oldp, valueToUse);
                
                if (origResult == 0) {
                    PXLog(@"[model] Spoofed sysctlbyname %s from: %s to: %s for app: %@", 
                            name, originalValue, valueToUse, bundleID);
                } else {
                    PXLog(@"[model] Spoofed sysctlbyname %s to: %s for app: %@", 
                            name, valueToUse, bundleID);
                }
                px_sysctlbyname_in_hook = NO;
                return 0;
            } else {
                PXLog(@"[model] WARNING: Spoofed value too long for sysctlbyname buffer");
            }
        }
    } else {
        PXLog(@"[model] WARNING: Cannot spoof sysctlbyname, missing required params or spoofed value");
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

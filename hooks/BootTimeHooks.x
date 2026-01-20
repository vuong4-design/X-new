#import "ProjectXLogging.h"
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/mach_host.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "DataManager.h"

// Define the boot time structure for sysctl calls
#import "PXHookOptions.h"
struct timeval_boot {
    time_t tv_sec;
    suseconds_t tv_usec;
};

// Original function pointers - ONLY for system calls
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);


// Global flag to track if hooks are installed
static BOOL hooksInstalled = NO;

// Forward declarations
static void installSystemCallHooks(void);

#pragma mark - System Call Hooks

// Hook sysctl() for KERN_BOOTTIME queries - ONLY method that App Store apps commonly use
int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    @try {
        NSDate * bootTime = CurrentPhoneInfo().upTimeInfo.bootTime;
        // Check if this is a KERN_BOOTTIME query
        if (namelen >= 2 && name && name[0] == CTL_KERN && name[1] == KERN_BOOTTIME) {
            if (bootTime && oldp && oldlenp && *oldlenp >= sizeof(struct timeval)) {
                struct timeval boottime;
                boottime.tv_sec = (time_t)[bootTime timeIntervalSince1970];
                boottime.tv_usec = 0;
                memcpy(oldp, &boottime, sizeof(boottime));
                *oldlenp = sizeof(boottime);
                return 0; // Success
            }
        }
    } @catch (NSException *e) {
        // Silent failure, pass through to original
    }
    // Call original function for all other cases
    if (orig_sysctl) {
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    }
    return -1;
}


// Hook for -[NSProcessInfo systemUptime]
static NSTimeInterval (*orig_systemUptime)(NSProcessInfo *, SEL);
static NSTimeInterval hook_systemUptime(NSProcessInfo *self, SEL _cmd) {
    NSTimeInterval upTime = CurrentPhoneInfo().upTimeInfo.upTime;
    if (upTime > 0) {
        return upTime;
    }
    
    if (!orig_systemUptime) {
        return 0;
    }
    return orig_systemUptime(self, _cmd);
}

// Install system call hooks ONLY for scoped apps
static void installSystemCallHooks(void) {
    @try {
        if (hooksInstalled) {
            return; // Already installed
        }
        
        BOOL hookingSuccess = NO;
        
        // Try ElleKit first (preferred for rootless jailbreaks)

        // Fallback to Substrate
        void *sysctlPtr = dlsym(RTLD_DEFAULT, "sysctl");
        if (sysctlPtr) {
            MSHookFunction(sysctlPtr, (void *)hook_sysctl, (void **)&orig_sysctl);
            hookingSuccess = YES;
        }
        
        
        if (hookingSuccess) {
            hooksInstalled = YES;
            // Add systemUptime hook for NSProcessInfo
            Class procInfoClass = objc_getClass("NSProcessInfo");
            if (procInfoClass) {
                MSHookMessageEx(procInfoClass, @selector(systemUptime), (IMP)hook_systemUptime, (IMP *)&orig_systemUptime);
            }
        }
        
    } @catch (NSException *e) {
        PXLog(@"[BootTimeHooks] ❌ Exception installing hooks: %@", e);
    }
}

#pragma mark - Initialization

// COMPLETELY REMOVED ALL %hook DIRECTIVES - NO MORE OBJECTIVE-C METHOD HOOKS
// This eliminates crashes in non-scoped apps

%ctor {
    @autoreleasepool {
        if (!PXHookEnabled(@"boottime")) { return; }
        @try {
            
            PXLog(@"[BootTimeHooks]  Installing minimal system call hooks for scoped app");
            
            // Install the minimal system call hooks that App Store apps actually use immediately
            installSystemCallHooks();
            
        } @catch (NSException *e) {
            // Silent failure to prevent crashes
        }
    }
} 

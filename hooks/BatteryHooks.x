#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "DataManager.h"


// Hook for -[UIDevice batteryLevel]
#import "PXHookOptions.h"
static float (*orig_batteryLevel)(UIDevice *, SEL);
static float hook_batteryLevel(UIDevice *self, SEL _cmd) {
    NSString *spoofed = CurrentPhoneInfo().batteryInfo.batteryLevel;
    if (spoofed) {
        float spoofedValue = [spoofed floatValue];
        if (spoofedValue >= 0.01 && spoofedValue <= 1.0) {
            return spoofedValue;
        }
    }
    return orig_batteryLevel(self,_cmd);
}

// Optionally, hook batteryState (returns UIDeviceBatteryState)
static NSInteger (*orig_batteryState)(UIDevice *, SEL);
static NSInteger hook_batteryState(UIDevice *self, SEL _cmd) {
    return 1; // UIDeviceBatteryStateUnplugged
}

%ctor {
    @autoreleasepool {
        if (!PXHookEnabled(@"battery")) { return; }
        Class deviceClass = objc_getClass("UIDevice");
        if (deviceClass) {
            MSHookMessageEx(deviceClass, @selector(batteryLevel), (IMP)hook_batteryLevel, (IMP *)&orig_batteryLevel);
            MSHookMessageEx(deviceClass, @selector(batteryState), (IMP)hook_batteryState, (IMP *)&orig_batteryState);
        }
    }
} 

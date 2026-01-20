#import "SettingManager.h"

@implementation SettingManager
+ (instancetype)sharedManager {
    static SettingManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (BOOL)saveToPrefs {
    NSDictionary *dict = @{
        @"carrierCountryCode": self.carrierCountryCode ?: @"US",
        @"minVersion": self.minVersion ?: @"14.0",
        @"maxVersion": self.maxVersion ?: @"18.6"
    };

    CFPreferencesSetValue(
        CFSTR("setting"),
        (__bridge CFPropertyListRef)dict,
        CFSTR("com.projectx.setting"),
        CFSTR("mobile"),
        kCFPreferencesAnyHost
    );


    CFPreferencesSynchronize(
        CFSTR("com.projectx.setting"),
        CFSTR("mobile"),
        kCFPreferencesAnyHost
    );

    return YES;
}

- (void)loadFromPrefs {
    CFPropertyListRef value =
        CFPreferencesCopyValue(
            CFSTR("setting"),
            CFSTR("com.projectx.setting"),
            CFSTR("mobile"),          // ⚠️ 不用 CurrentUser
            kCFPreferencesAnyHost
        );


    if (!value || CFGetTypeID(value) != CFDictionaryGetTypeID()) {
        if (value) CFRelease(value);
        self.carrierCountryCode = @"US";
        self.minVersion = @"14.0";
        self.maxVersion = @"18.6";
        return;
    }

    NSDictionary *dict = CFBridgingRelease(value);
    self.carrierCountryCode = dict[@"carrierCountryCode"] ?: @"US";
    self.minVersion = dict[@"minVersion"] ?: @"14.0";
    self.maxVersion = dict[@"maxVersion"] ?: @"18.6";
}

@end
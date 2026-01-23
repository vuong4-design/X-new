#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CFNetwork/CFNetwork.h>

#import "ProjectXLogging.h"
#import "DataManager.h"
#import "PXHookOptions.h"

// ============================================================================
// Web/User-Agent coverage hooks (3 paths) — PLIST SOURCE OF TRUTH (Option A)
//  1) UIWebView legacy UA via NSUserDefaults "UserAgent"
//  2) CFNetwork: CFHTTPMessageSetHeaderFieldValue(User-Agent)
//  3) NSURLSessionConfiguration: HTTPAdditionalHeaders (User-Agent)
// Gating: PXHookEnabled(@"devicemodel")
// Logging: 1 time / path to avoid spam
//
// NOTE: Provide UA in com.projectx.phoneinfo.plist at:
//   deviceModel.userAgent (NSString)
// ============================================================================

static inline BOOL PXWebUASpoofEnabled(void) {
    return PXHookEnabled(@"devicemodel");
}

static NSString *PXUserAgentFromPlist(void) {
    PhoneInfo *info = CurrentPhoneInfo();
    if (!info) return nil;
    DeviceModel *dm = info.deviceModel;
    if (!dm) return nil;

    // Expect a full UA string stored in plist.
    // If your DeviceModel class doesn't expose "userAgent", this uses KVC safely.
    @try {
        id ua = [dm valueForKey:@"userAgent"];
        if ([ua isKindOfClass:[NSString class]] && [ua length] > 0) {
            return (NSString *)ua;
        }
    } @catch (__unused NSException *e) {
        // ignore
    }

    return nil;
}

static NSString *PXBuildFallbackUA(void) {
    // Fallback only if plist UA missing; keeps behavior stable but logs warning once.
    PhoneInfo *info = CurrentPhoneInfo();
    IosVersion *iv = info.iosVersion;

    NSString *version = iv.version ?: [[UIDevice currentDevice] systemVersion] ?: @"14.0";
    NSString *build   = iv.build   ?: @"15E148";

    NSString *osUnderscore = [version stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *webkit = @"605.1.15";

    return [NSString stringWithFormat:
            @"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) "
            @"AppleWebKit/%@ (KHTML, like Gecko) "
            @"Version/%@ Mobile/%@ Safari/604.1",
            osUnderscore, webkit, version, build];
}

static NSString *PXGetSpoofedUserAgent(void) {
    NSString *ua = PXUserAgentFromPlist();
    if (ua.length) return ua;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PXLog(@"[WebUA] ⚠️ deviceModel.userAgent missing in plist; using fallback UA generator");
    });
    return PXBuildFallbackUA();
}

// ----------------------------------------------------------------------------
// 1) UIWebView legacy UA (NSUserDefaults "UserAgent")
// ----------------------------------------------------------------------------
%hook UIWebView

- (instancetype)initWithFrame:(CGRect)frame {
    UIWebView *v = %orig;

    if (PXWebUASpoofEnabled()) {
        NSString *ua = PXGetSpoofedUserAgent();
        if (ua.length) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": ua}];
                PXLog(@"[WebUA] Spoofed UIWebView UserAgent via NSUserDefaults to: %@", ua);
            });
        }
    }
    return v;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    UIWebView *v = %orig;

    if (PXWebUASpoofEnabled()) {
        NSString *ua = PXGetSpoofedUserAgent();
        if (ua.length) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": ua}];
                PXLog(@"[WebUA] Spoofed UIWebView UserAgent via NSUserDefaults to: %@", ua);
            });
        }
    }
    return v;
}

%end

// ----------------------------------------------------------------------------
// 2) CFNetwork UA: CFHTTPMessageSetHeaderFieldValue
// ----------------------------------------------------------------------------
%hookf(void, CFHTTPMessageSetHeaderFieldValue, CFHTTPMessageRef message, CFStringRef headerField, CFStringRef value) {

    if (PXWebUASpoofEnabled() &&
        headerField &&
        CFStringCompare(headerField, CFSTR("User-Agent"), kCFCompareCaseInsensitive) == kCFCompareEqualTo) {

        NSString *ua = PXGetSpoofedUserAgent();
        if (ua.length) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                PXLog(@"[WebUA] Spoofed CFHTTPMessageSetHeaderFieldValue(User-Agent) to: %@", ua);
            });
            %orig(message, headerField, (__bridge CFStringRef)ua);
            return;
        }
    }

    %orig(message, headerField, value);
}

// ----------------------------------------------------------------------------
// 3) NSURLSessionConfiguration: HTTPAdditionalHeaders
// ----------------------------------------------------------------------------
%hook NSURLSessionConfiguration

- (void)setHTTPAdditionalHeaders:(NSDictionary<NSString *, NSString *> *)HTTPAdditionalHeaders {
    if (PXWebUASpoofEnabled() && [HTTPAdditionalHeaders isKindOfClass:[NSDictionary class]]) {
        NSString *ua = PXGetSpoofedUserAgent();
        if (ua.length) {
            if (HTTPAdditionalHeaders[@"User-Agent"]) {
                NSMutableDictionary *m = [HTTPAdditionalHeaders mutableCopy];
                m[@"User-Agent"] = ua;

                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    PXLog(@"[WebUA] Spoofed NSURLSessionConfiguration.HTTPAdditionalHeaders User-Agent to: %@", ua);
                });

                %orig([m copy]);
                return;
            }
        }
    }
    %orig(HTTPAdditionalHeaders);
}

%end

%ctor {
    @autoreleasepool {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSString *ua = PXUserAgentFromPlist();
            if (ua.length) {
                PXLog(@"[WebUA] ✅ Using UA from plist (deviceModel.userAgent)");
            } else {
                PXLog(@"[WebUA] ✅ Web UA coverage hooks loaded (UIWebView + CFNetwork + NSURLSessionConfiguration)");
            }
        });
    }
}

#import "PXBundleIdentifier.h"

NSString *PXSafeBundleIdentifier(void) {
    // Re-entrancy guard: in some setups a hook may indirectly call back into
    // this helper while we're still resolving the bundle id. Prevent infinite recursion.
    static __thread int _px_bid_inProgress = 0;
    if (_px_bid_inProgress > 0) {
        // Best-effort: avoid any further calls that might recurse.
        return @"";
    }
    _px_bid_inProgress++;
    @try {
        // Cache the first non-nil value we can obtain. If it's nil at the very
        // beginning of the process, we return @"" but we do NOT cache that,
        // so later calls can still pick up a valid bundle id.
        static NSString *cached = nil;
        if (cached.length > 0) {
            return cached;
        }

        NSString *bid = nil;
        @try {
            // Use CoreFoundation first to avoid any potential Objective-C hooks on
            // -[NSBundle bundleIdentifier] that could cause recursion.
            CFBundleRef b = CFBundleGetMainBundle();
            if (b) {
                CFStringRef cfbid = CFBundleGetIdentifier(b);
                if (cfbid) {
                    bid = (__bridge NSString *)cfbid;
                }

                if (bid.length == 0) {
                    CFDictionaryRef info = CFBundleGetInfoDictionary(b);
                    if (info) {
                        const void *val = CFDictionaryGetValue(info, CFSTR("CFBundleIdentifier"));
                        if (val && CFGetTypeID(val) == CFStringGetTypeID()) {
                            bid = (__bridge NSString *)((CFStringRef)val);
                        }
                    }
                }
            }
        } @catch (__unused NSException *e) {
            bid = nil;
        }

        if (bid.length > 0) {
            cached = [bid copy];
            return cached;
        }

        return @"";
    } @finally {
        _px_bid_inProgress--;
    }
}

#import "PXBundleIdentifier.h"

NSString *PXSafeBundleIdentifier(void) {
    // Cache the first non-nil value we can obtain. If it's nil at the very
    // beginning of the process, we return @"" but we do NOT cache that,
    // so later calls can still pick up a valid bundle id.
    static NSString *cached = nil;
    if (cached.length > 0) {
        return cached;
    }

    NSString *bid = nil;
    @try {
        bid = PXSafeBundleIdentifier();
    } @catch (__unused NSException *e) {
        bid = nil;
    }

    if (bid.length > 0) {
        cached = [bid copy];
        return cached;
    }

    return @"";
}

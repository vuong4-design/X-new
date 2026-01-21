#import <Foundation/Foundation.h>

/// Safe helper for retrieving the current process bundle identifier.
///
/// In injected contexts (Substrate / ElleKit), `-[NSBundle mainBundle] bundleIdentifier`
/// can temporarily be `nil` very early during process startup.
///
/// This helper always returns a non-nil string (empty string if unavailable).
FOUNDATION_EXPORT NSString *PXSafeBundleIdentifier(void);

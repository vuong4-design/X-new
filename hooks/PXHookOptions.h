#import <Foundation/Foundation.h>

#import "PXBundleIdentifier.h"

NS_ASSUME_NONNULL_BEGIN

/// Darwin notify name to reload tweak prefs at runtime.
FOUNDATION_EXPORT CFStringRef const kPXHookPrefsChangedNotification;

/// Returns YES if the given hook key is enabled for the current process bundle ID.
/// Resolution order: Per-app override -> Global default -> YES.
BOOL PXHookEnabled(NSString *key);

/// Force reload prefs from disk (used by notification observer).
void PXReloadHookPrefs(void);

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ProjectXLogging.h"
#import "ProfileManager.h"
#import "DataManager.h"


#import "PXHookOptions.h"
static NSMutableDictionary *customChangeCountMap = nil; // Store custom change counts per app
static NSMutableDictionary *lastKnownPasteboardData = nil; // Cache pasteboard content hash

// Helper for safe change count management
static NSInteger getCustomChangeCount(NSString *bundleID, NSInteger originalCount) {
    if (!customChangeCountMap) {
        customChangeCountMap = [NSMutableDictionary dictionary];
    }
    
    NSNumber *currentValue = customChangeCountMap[bundleID];
    if (!currentValue) {
        // First time seeing this app, initialize with original count
        NSInteger initialValue = originalCount;
        customChangeCountMap[bundleID] = @(initialValue);
        return initialValue;
    }
    
    return [currentValue integerValue];
}

// Helper to safely increment change count
static void incrementCustomChangeCount(NSString *bundleID) {
    if (!customChangeCountMap) {
        customChangeCountMap = [NSMutableDictionary dictionary];
    }
    
    NSNumber *currentValue = customChangeCountMap[bundleID];
    NSInteger newValue = currentValue ? [currentValue integerValue] + 1 : 1;
    customChangeCountMap[bundleID] = @(newValue);
}

// Helper to compute a hash of pasteboard content for change detection
static NSString *getPasteboardContentHash(UIPasteboard *pasteboard) {
    @try {
        NSMutableString *hashInput = [NSMutableString string];
        
        // Add string items
        NSArray *types = @[@"public.text", @"public.plain-text", @"public.utf8-plain-text"];
        for (NSString *type in types) {
            if ([pasteboard containsPasteboardTypes:@[type]]) {
                NSString *string = [pasteboard valueForPasteboardType:type];
                if (string) {
                    [hashInput appendString:string];
                }
            }
        }
        
        // Add image data hash if possible
        if (pasteboard.image) {
            NSData *imageData = UIImagePNGRepresentation(pasteboard.image);
            if (imageData) {
                [hashInput appendFormat:@"IMG:%lu", (unsigned long)imageData.hash];
            }
        }
        
        // Add URL strings
        if (pasteboard.URL) {
            [hashInput appendString:[pasteboard.URL absoluteString]];
        }
        
        // Compute hash of the combined content
        return [NSString stringWithFormat:@"%lu", (unsigned long)[hashInput hash]];
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception computing pasteboard hash: %@", exception);
        return @"ERROR";
    }
}

// Helper to check if pasteboard content has changed
static BOOL hasPasteboardContentChanged(NSString *bundleID, UIPasteboard *pasteboard) {
    @try {
        if (!lastKnownPasteboardData) {
            lastKnownPasteboardData = [NSMutableDictionary dictionary];
        }
        
        NSString *newHash = getPasteboardContentHash(pasteboard);
        NSString *oldHash = lastKnownPasteboardData[bundleID];
        
        // Update stored hash
        lastKnownPasteboardData[bundleID] = newHash;
        
        // If no previous hash or different hash, it changed
        return !oldHash || ![oldHash isEqualToString:newHash];
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception checking pasteboard changes: %@", exception);
        return NO;
    }
}

#pragma mark - UIPasteboard Hooks
%group PX_pasteboard


%hook UIPasteboard

// Hook the main pasteboard UUID method
- (NSUUID *)uniquePasteboardUUID {
    @try {    
        // Get spoofed Pasteboard UUID
        NSString *uuidString = CurrentPhoneInfo().pasteboardUUID;
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
        PXLog(@"[WeaponX] 🔄 Spoofing Pasteboard UUID with: %@", uuidString);
        return uuid;
    
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in uniquePasteboardUUID hook: %@", exception);
    }
    
    // Call original if we're not spoofing
    return %orig;
}

// Hook name property which can contain identifying information
- (NSString *)name {
    NSString *originalName = %orig;
    
    @try {        
        // Only spoof on custom-named pasteboards, not the general one
        if (originalName && ![originalName isEqualToString:@"com.apple.UIKit.pboard.general"]) {
            // Get current pasteboard UUID
            NSString *uuidString = CurrentPhoneInfo().pasteboardUUID;
            
            // Create a stable, deterministic name based on the spoofed UUID
            // We only replace the last component to maintain compatibility
            NSArray *components = [originalName componentsSeparatedByString:@"."];
            if (components.count > 0) {
                NSMutableArray *newComponents = [NSMutableArray arrayWithArray:components];
                
                // Replace last component with the first part of our UUID
                NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
                newComponents[newComponents.count - 1] = shortUUID;
                
                NSString *spoofedName = [newComponents componentsJoinedByString:@"."];
                PXLog(@"[WeaponX] 🔄 Spoofing Pasteboard name from '%@' to '%@'", originalName, spoofedName);
                return spoofedName;
            }
            
            // Fallback if components array doesn't have elements (shouldn't happen with valid names)
            // Just append the short UUID to maintain a unique but stable name
            NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
            NSString *spoofedName = [NSString stringWithFormat:@"%@.%@", originalName, shortUUID];
            PXLog(@"[WeaponX] 🔄 Spoofing Pasteboard name (fallback) from '%@' to '%@'", originalName, spoofedName);
            return spoofedName;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in name hook: %@", exception);
    }
    
    return originalName;
}

// Hook the general pasteboard accessor to ensure consistent UUID behavior
+ (UIPasteboard *)generalPasteboard {
    UIPasteboard *original = %orig;
    
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        // We don't need to do anything here, as uniquePasteboardUUID is hooked above
        // This override just ensures we're tracking all possible entry points
        PXLog(@"[WeaponX] 📋 Accessed general pasteboard from %@", bundleID);
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in generalPasteboard hook: %@", exception);
    }
    
    return original;
}

// Hook the named pasteboard creation method
+ (UIPasteboard *)pasteboardWithName:(NSString *)pasteboardName create:(BOOL)create {
    @try {        
        if (pasteboardName) {
            // Get current pasteboard UUID
            NSString *uuidString = CurrentPhoneInfo().pasteboardUUID;
            
            // Create a stable, deterministic name based on the spoofed UUID
            // We only replace the last component to maintain compatibility
            NSArray *components = [pasteboardName componentsSeparatedByString:@"."];
            if (components.count > 0) {
                NSMutableArray *newComponents = [NSMutableArray arrayWithArray:components];
                
                // Replace last component with the first part of our UUID
                NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
                newComponents[newComponents.count - 1] = shortUUID;
                
                NSString *spoofedName = [newComponents componentsJoinedByString:@"."];
                PXLog(@"[WeaponX] 🔄 Creating pasteboard with spoofed name: %@ (original: %@)", spoofedName, pasteboardName);
                return %orig(spoofedName, create);
            }
            
            // Fallback if components array doesn't have elements
            NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
            NSString *spoofedName = [NSString stringWithFormat:@"%@.%@", pasteboardName, shortUUID];
            PXLog(@"[WeaponX] 🔄 Creating pasteboard with spoofed name (fallback): %@ (original: %@)", spoofedName, pasteboardName);
            return %orig(spoofedName, create);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in pasteboardWithName:create: hook: %@", exception);
    }
    
    return %orig;
}

// Hook the pasteboard URL initialization method
+ (UIPasteboard *)pasteboardWithUniqueName {
    UIPasteboard *original = %orig;
    
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        
        if (original) {
            // We intercept the uniquePasteboardUUID method above
            // So this automatically gets our spoofed value 
            PXLog(@"[WeaponX] 📋 Created pasteboard with unique name from %@", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in pasteboardWithUniqueName hook: %@", exception);
    }
    
    return original;
}

// Hook URL-based pasteboard creation (iOS 10+)
+ (UIPasteboard *)pasteboardWithURL:(NSURL *)url create:(BOOL)create {
    @try {        
        if (url) {
            // Create a modified URL with our UUID to ensure stable but unique URLs
            NSString *uuidString = CurrentPhoneInfo().pasteboardUUID;
            NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
            
            // Create a new URL with our UUID injected to ensure stability
            NSURL *spoofedURL;
            NSString *originalURLString = [url absoluteString];
            
            if ([originalURLString containsString:@"?"]) {
                // URL already has query parameters, add ours
                spoofedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@&uuid=%@", 
                                                   originalURLString, shortUUID]];
            } else {
                // URL has no query parameters, add our own
                spoofedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?uuid=%@", 
                                                   originalURLString, shortUUID]];
            }
            
            if (!spoofedURL) {
                // If URL manipulation failed, fall back to original URL
                spoofedURL = url;
            }
            
            PXLog(@"[WeaponX] 🔄 Creating pasteboard with spoofed URL: %@ (original: %@)", 
                 spoofedURL, url);
            return %orig(spoofedURL, create);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in pasteboardWithURL:create: hook: %@", exception);
    }
    
    return %orig;
}

// Hook change count property used for pasteboard change detection
- (NSInteger)changeCount {
    NSInteger originalCount = %orig;
    
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        // Get our custom change count
        NSInteger spoofedCount = getCustomChangeCount(bundleID, originalCount);
        
        // Check if content actually changed, and if so, increment our count
        if (hasPasteboardContentChanged(bundleID, self)) {
            incrementCustomChangeCount(bundleID);
            spoofedCount = getCustomChangeCount(bundleID, originalCount);
        }
        
        PXLog(@"[WeaponX] 🔄 Spoofing pasteboard changeCount: %ld (original: %ld)", 
                (long)spoofedCount, (long)originalCount);
        return spoofedCount;
} @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in changeCount hook: %@", exception);
    }
    
    return originalCount;
}

// Hook persistent property to prevent fingerprinting
- (void)setPersistent:(BOOL)persistent {
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        // Always allow pasteboard to be persistent to avoid crashes
        // but log the attempt to track fingerprinting
        PXLog(@"[WeaponX] 📋 App %@ trying to set pasteboard persistence: %@", 
                bundleID, persistent ? @"YES" : @"NO");
        %orig(YES);
        return;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setPersistent: hook: %@", exception);
    }
    
    %orig;
}

// Hook persistent property getter
- (BOOL)isPersistent {
    BOOL originalValue = %orig;
    
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        // Always report persistent to avoid issues
        PXLog(@"[WeaponX] 📋 App %@ checking pasteboard persistence", bundleID);
        return YES;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in isPersistent hook: %@", exception);
    }
    
    return originalValue;
}

// Hook itemProviders for controlling access to pasteboard data types
- (NSArray *)itemProviders {
    NSArray *originalProviders = %orig;
    
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        
        if (originalProviders) {
            PXLog(@"[WeaponX] 📋 App %@ accessing pasteboard item providers (%lu items)", 
                 bundleID, (unsigned long)originalProviders.count);
            
            // We don't need to modify the providers as we're already spoofing the UUID
            // But we do want to track access for fingerprinting detection
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in itemProviders hook: %@", exception);
    }
    
    return originalProviders;
}

// Hook itemSet method for controlling access to pasteboard data types
- (NSArray *)itemSetWithPreferredPasteboardTypes:(NSArray *)types {
    NSArray *originalItemSet = %orig;
    
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        
        if (originalItemSet) {
            PXLog(@"[WeaponX] 📋 App %@ accessing pasteboard items with preferred types: %@", 
                 bundleID, types);
            
            // We don't modify the items, just track access for fingerprinting detection
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in itemSetWithPreferredPasteboardTypes: hook: %@", exception);
    }
    
    return originalItemSet;
}

// Hook containsPasteboardTypes method which might be used for fingerprinting
- (BOOL)containsPasteboardTypes:(NSArray *)pasteboardTypes {
    BOOL originalResult = %orig;
    
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        
        if (pasteboardTypes) {
            // Log suspicious fingerprinting types
            if ([pasteboardTypes containsObject:@"com.apple.uikit.pboard-uuid"] ||
                [pasteboardTypes containsObject:@"com.apple.uikit.pboard-devices"]) {
                PXLog(@"[WeaponX] ⚠️ Possible fingerprinting: App %@ checking for special types: %@", 
                      bundleID, pasteboardTypes);
            }
            
            // We don't modify the return value as that could break app functionality
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in containsPasteboardTypes: hook: %@", exception);
    }
    
    return originalResult;
}

// Hook valueForPasteboardType to monitor and potentially modify access to types
- (id)valueForPasteboardType:(NSString *)pasteboardType {
    id originalValue = %orig;
    
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        
        if (pasteboardType) {
            // Check for device-specific or identity types
            if ([pasteboardType isEqualToString:@"com.apple.uikit.pboard-uuid"] ||
                [pasteboardType isEqualToString:@"com.apple.uikit.pboard-devices"] ||
                [pasteboardType containsString:@"uuid"] ||
                [pasteboardType containsString:@"device"]) {
                
                PXLog(@"[WeaponX] ⚠️ App %@ accessing potentially identifying pasteboard type: %@",
                      bundleID, pasteboardType);
                
                // Return nil for sensitive types to prevent fingerprinting
                if ([pasteboardType isEqualToString:@"com.apple.uikit.pboard-uuid"]) {
                    NSString *spoofedUUID = CurrentPhoneInfo().pasteboardUUID;
                    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:spoofedUUID];
                    
                    // Use modern API with error handling instead of deprecated method
                    NSError *archiveError = nil;
                    NSData *uuidData = nil;
                    
                    if (@available(iOS 12.0, *)) {
                        uuidData = [NSKeyedArchiver archivedDataWithRootObject:uuid requiringSecureCoding:NO error:&archiveError];
                        if (archiveError) {
                            PXLog(@"[WeaponX] ⚠️ Error archiving UUID data: %@", archiveError);
                        }
                    } else {
                        // Fallback for older iOS versions
                        @try {
                            #pragma clang diagnostic push
                            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                            uuidData = [NSKeyedArchiver archivedDataWithRootObject:uuid];
                            #pragma clang diagnostic pop
                        } @catch (NSException *exception) {
                            PXLog(@"[WeaponX] ⚠️ Exception archiving UUID data: %@", exception);
                        }
                    }
                    
                    if (uuidData) {
                        return uuidData;
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in valueForPasteboardType: hook: %@", exception);
    }
    
    return originalValue;
}

// Hook data setter to monitor content changes and maintain our change count
- (void)setData:(NSData *)data forPasteboardType:(NSString *)pasteboardType {
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        // Increment our custom change count whenever content changes
        incrementCustomChangeCount(bundleID);
        PXLog(@"[WeaponX] 📋 App %@ setting pasteboard data for type: %@", bundleID, pasteboardType);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setData:forPasteboardType: hook: %@", exception);
    }
    
    %orig;
}

// Hook items setter to monitor content changes
- (void)setItems:(NSArray *)items {
    @try {
        NSString *bundleID = PXSafeBundleIdentifier();
        // Increment our custom change count whenever content changes
        incrementCustomChangeCount(bundleID);
        PXLog(@"[WeaponX] 📋 App %@ setting pasteboard items (%lu items)", 
                bundleID, (unsigned long)items.count);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setItems: hook: %@", exception);
    }
    
    %orig;
}

%end

#pragma mark - NSNotification Hooks for Pasteboard

// Hook notification posting to intercept pasteboard change notifications
%hook NSNotificationCenter

- (void)postNotification:(NSNotification *)notification {
    @try {
        NSString *name = notification.name;
        
        // Check for UIPasteboard change notifications
        if ([name isEqualToString:UIPasteboardChangedNotification] ||
            [name hasPrefix:@"UIPasteboard"] ||
            [name containsString:@"Pasteboard"]) {
            
            NSString *bundleID = PXSafeBundleIdentifier();
            // Let these through but log them for tracking fingerprinting
            PXLog(@"[WeaponX] 📋 Pasteboard notification: %@ in app %@", name, bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in postNotification: hook for notifications: %@", exception);
    }
    
    %orig;
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        // Skip for system processes
        NSString *bundleID = PXSafeBundleIdentifier();
        
        PXLog(@"[WeaponX] 📋 Initialized PasteboardHooks for %@", bundleID);
    }
} 

%end

%ctor {
    if (PXHookEnabled(@"pasteboard")) {
        %init(PX_pasteboard);
    }
}

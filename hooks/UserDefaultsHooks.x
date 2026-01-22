#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ProjectXLogging.h"
#import "ProfileManager.h"
#import "DataManager.h"

// Function declarations
#import "PXHookOptions.h"
static BOOL isUUIDKey(NSString *key);
static id processDictionaryValues(id object);



// Function to recursively process dictionary values and replace UUIDs
static id processDictionaryValues(id object) {
    // Base case: not a dictionary or array
    if (!object || (![object isKindOfClass:[NSDictionary class]] && ![object isKindOfClass:[NSArray class]])) {
        return object;
    }
    
    // For dictionaries, check each key and recursively process values
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dict.count];
        
        NSString *spoofedUUID = CurrentPhoneInfo().userDefaultsUUID;
        
        for (id key in dict) {
            // Check if this key is UUID-related
            if ([key isKindOfClass:[NSString class]] && isUUIDKey(key)) {
                id value = dict[key];
                // If value is a string and looks like a UUID, replace it
                if ([value isKindOfClass:[NSString class]]) {
                    NSString *strValue = (NSString *)value;
                    // If the value matches a UUID pattern or is more than 8 chars and contains only hex
                    if ([strValue rangeOfString:@"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" 
                                         options:NSRegularExpressionSearch].location != NSNotFound ||
                        (strValue.length > 8 && [strValue rangeOfString:@"^[0-9a-f]+$" 
                                                               options:NSRegularExpressionSearch].location != NSNotFound)) {
                        result[key] = spoofedUUID;
                        continue;
                    }
                }
            }
            
            // Recursively process the value
            result[key] = processDictionaryValues(dict[key]);
        }
        
        return result;
    }
    
    // For arrays, recursively process each element
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)object;
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
        
        for (id item in array) {
            [result addObject:processDictionaryValues(item)];
        }
        
        return result;
    }
    
    // Shouldn't reach here, but just in case
    return object;
}

// Enhanced isUUIDKey to detect more UUID patterns
static BOOL isUUIDKey(NSString *key) {
    if (!key) return NO;
    
    NSString *lowercaseKey = [key lowercaseString];
    
    // Common UUID-related key patterns
    // Keep this list *narrow*. Keys like "token" or "device" are too generic and
    // can match app-specific preferences that are not UUIDs (e.g. Facebook), which
    // can corrupt their stored data and crash later.
    NSArray *uuidPatterns = @[
        @"uuid", @"udid", @"deviceid", @"device-id", @"device_id",
        @"uniqueid", @"unique-id", @"unique_id", @"identifier",
        @"vendorid", @"vendor-id", @"vendor_id",
        @"idfa", @"idfv", @"adid", @"advertisingid"
    ];
    
    // Check for exact matches or suffixes
    for (NSString *pattern in uuidPatterns) {
        if ([lowercaseKey isEqualToString:pattern] || 
            [lowercaseKey hasSuffix:[@"." stringByAppendingString:pattern]] ||
            [lowercaseKey hasSuffix:[@"-" stringByAppendingString:pattern]] ||
            [lowercaseKey hasSuffix:[@"_" stringByAppendingString:pattern]]) {
            return YES;
        }
    }
    
    // Match UUID pattern (8-4-4-4-12 format)
    return [lowercaseKey rangeOfString:@"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" 
                              options:NSRegularExpressionSearch].location != NSNotFound;
}

static BOOL PXLooksLikeUUIDString(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return NO;
    if (s.length == 36) {
        return [[NSUUID alloc] initWithUUIDString:s] != nil;
    }
    if (s.length == 32) {
        // 32 hex chars (no dashes)
        NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
        return [[s stringByTrimmingCharactersInSet:hexSet] length] == 0;
    }
    return NO;
}

#pragma mark - NSUserDefaults Hooks
%group PX_userdefaults


%hook NSUserDefaults
// TODO 这里貌似会让应用闪退
// Base method for getting objects
- (id)objectForKey:(NSString *)defaultName {
    @try {
        id originalValue = %orig;
        if (!isUUIDKey(defaultName) || !originalValue) {
            // Not a UUID-like key, or no value -> do not interfere
            return originalValue;
        }

        NSString *spoofedUUID = CurrentPhoneInfo().userDefaultsUUID;

        // Only spoof when the original value is UUID-ish. Returning a string
        // unconditionally can corrupt app state (e.g. if an app stores binary blobs).
        if ([originalValue isKindOfClass:[NSString class]]) {
            NSString *s = (NSString *)originalValue;
            if (PXLooksLikeUUIDString(s)) {
                PXLog(@"[WeaponX] 🔍 Spoofing UserDefaults UUID for key '%@' with: %@", defaultName, spoofedUUID);
                return spoofedUUID;
            }
            return originalValue;
        }

        if ([originalValue isKindOfClass:[NSData class]]) {
            NSData *d = (NSData *)originalValue;
            if (d.length == 16) {
                NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:spoofedUUID];
                if (uuid) {
                    uuid_t bytes;
                    [uuid getUUIDBytes:bytes];
                    return [NSData dataWithBytes:bytes length:16];
                }
            }
            return originalValue;
        }

        if ([originalValue isKindOfClass:[NSUUID class]]) {
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:spoofedUUID];
            return uuid ?: originalValue;
        }

        // Only deep-process containers for UUID keys.
        if ([originalValue isKindOfClass:[NSDictionary class]] || [originalValue isKindOfClass:[NSArray class]]) {
            return processDictionaryValues(originalValue);
        }
        
        return originalValue;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in objectForKey hook: %@", exception);
        return %orig;
    }
}

// String-specific method
- (NSString *)stringForKey:(NSString *)defaultName {
    NSString *origValue = %orig;
    @try {
        if (!origValue) return nil;
        if (!isUUIDKey(defaultName)) return origValue;

        // Only spoof if the stored value actually looks like a UUID
        if (PXLooksLikeUUIDString(origValue)) {
            NSString *spoofedUUID = CurrentPhoneInfo().userDefaultsUUID;
            PXLog(@"[WeaponX] 🔍 Spoofing UserDefaults string UUID for key '%@' with: %@", defaultName, spoofedUUID);
            return spoofedUUID;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in stringForKey hook: %@", exception);
    }

    return origValue;
}

// Dictionary method - use our recursive processor for nested values
- (NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)defaultName {
    NSDictionary *originalDict = %orig;
    
    @try {        
        // Don't modify if not spoofing or if the dictionary is empty
        if (!originalDict || originalDict.count == 0) {
            return originalDict;
        }

        // Only touch UUID-related keys to avoid corrupting app-managed preferences.
        if (!isUUIDKey(defaultName)) {
            return originalDict;
        }
        
        // Use our recursive processor to handle nested dictionaries
        return processDictionaryValues(originalDict);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in dictionaryForKey hook: %@", exception);
        return originalDict;
    }
}

// Add additional accessor methods

- (NSArray *)arrayForKey:(NSString *)defaultName {
    NSArray *originalArray = %orig;
    
    @try {        
        // Don't modify if not spoofing or if the array is empty
        if (!originalArray || originalArray.count == 0) {
            return originalArray;
        }
        
        // Only touch UUID-related keys to avoid corrupting app-managed preferences.
        if (!isUUIDKey(defaultName)) {
            return originalArray;
        }

        // Use our recursive processor to handle arrays containing dictionaries with UUIDs
        return processDictionaryValues(originalArray);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in arrayForKey hook: %@", exception);
        return originalArray;
    }
}

- (NSData *)dataForKey:(NSString *)defaultName {
    @try {        
        NSData *originalData = %orig;
        if (!originalData) return nil;

        // Only spoof binary UUIDs when the *key* is UUID-related.
        if (!isUUIDKey(defaultName)) {
            return originalData;
        }

        // Spoof 16-byte UUID binary representation
        if (originalData.length == 16) {
            NSString *spoofedUUID = CurrentPhoneInfo().userDefaultsUUID;
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:spoofedUUID];
            if (uuid) {
                uuid_t bytes;
                [uuid getUUIDBytes:bytes];
                NSData *spoofedData = [NSData dataWithBytes:bytes length:16];
                PXLog(@"[WeaponX] 🔍 Spoofing binary UUID data for key '%@'", defaultName);
                return spoofedData;
            }
        }

        // Otherwise, keep original data. Some apps store non-UUID payloads here.
        return originalData;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in dataForKey hook: %@", exception);
    }
    
    return %orig;
}

- (NSURL *)URLForKey:(NSString *)defaultName {
    // URL values are rarely UUIDs, so use original
    return %orig;
}

// KVC accessor - important for accessing dictionaries
- (id)valueForKey:(NSString *)key {
    @try {
        // Only override for specific UUID keys to avoid breaking KVC for other properties
        if (isUUIDKey(key)) {
            id result = [self objectForKey:key];
            if (result) {
                return result;
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in valueForKey hook: %@", exception);
    }
    
    return %orig;
}

// Subscript accessor - important for dictionary-style access
- (id)objectForKeyedSubscript:(NSString *)key {
    @try {
        // This is used when accessing NSUserDefaults with subscript notation: userDefaults[key]
        if (isUUIDKey(key)) {
            return [self objectForKey:key];
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in objectForKeyedSubscript hook: %@", exception);
    }
    
    return %orig;
}

// SETTER METHODS

// Base setter method
- (void)setObject:(id)value forKey:(NSString *)defaultName {
    @try {        
        // If setting a UUID value, replace with our spoofed UUID
        if (isUUIDKey(defaultName) && [value isKindOfClass:[NSString class]]) {
            NSString *spoofedUUID = CurrentPhoneInfo().userDefaultsUUID;
            PXLog(@"[WeaponX] 🔍 Intercepting and spoofing UUID being saved to UserDefaults for key '%@'", defaultName);
            return %orig(spoofedUUID, defaultName);
        }
        
        // If setting a dictionary or array, process it to replace UUIDs
        if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
            id processedValue = processDictionaryValues(value);
            return %orig(processedValue, defaultName);
        }
    
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setObject:forKey: hook: %@", exception);
    }
    
    return %orig;
}

// String-specific setter
- (void)setString:(NSString *)value forKey:(NSString *)defaultName {
    @try {        
        if (isUUIDKey(defaultName)) {
            NSString *spoofedUUID = CurrentPhoneInfo().userDefaultsUUID;
            PXLog(@"[WeaponX] 🔍 Intercepting and spoofing UUID string being saved to UserDefaults for key '%@'", defaultName);
            return %orig(spoofedUUID, defaultName);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setString:forKey: hook: %@", exception);
    }
    
    return %orig;
}

// Dictionary-specific setter
- (void)setDictionary:(NSDictionary<NSString *,id> *)value forKey:(NSString *)defaultName {
    @try {        
        if (value) {
            // Process the dictionary to replace any UUIDs
            NSDictionary *processedDict = processDictionaryValues(value);
            return %orig(processedDict, defaultName);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setDictionary:forKey: hook: %@", exception);
    }
    
    return %orig;
}

// Data-specific setter
- (void)setData:(NSData *)value forKey:(NSString *)defaultName {
    @try {
        // Only spoof for UUID-related keys. Do not tamper with arbitrary blobs.
        if (isUUIDKey(defaultName) && value) {
            NSString *spoofedUUID = CurrentPhoneInfo().userDefaultsUUID;
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:spoofedUUID];
            if (uuid && value.length == 16) {
                uuid_t bytes;
                [uuid getUUIDBytes:bytes];
                NSData *spoofedData = [NSData dataWithBytes:bytes length:16];
                PXLog(@"[WeaponX] 🔍 Spoofing 16-byte UUID data being saved to UserDefaults for key '%@'", defaultName);
                return %orig(spoofedData, defaultName);
            }

            // Fallback: if the app stores UUID as UTF-8 string data
            if (PXLooksLikeUUIDString(spoofedUUID)) {
                NSData *spoofedData = [spoofedUUID dataUsingEncoding:NSUTF8StringEncoding];
                PXLog(@"[WeaponX] 🔍 Spoofing string UUID data being saved to UserDefaults for key '%@'", defaultName);
                return %orig(spoofedData, defaultName);
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setData:forKey: hook: %@", exception);
    }
    
    return %orig;
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        if (PXHookEnabled(@"userdefaults")) {
            PXLog(@"[WeaponX] 🔍 UserDefaults hooks initialized");
            %init(PX_userdefaults);
        }
    }
}

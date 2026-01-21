#import "AppScopeManager.h"
#import "PXBundleIdentifier.h"
#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif
@interface AppScopeManager()
@property (nonatomic, strong) NSMutableSet *scopedApps;
@end

@implementation AppScopeManager

+ (instancetype)sharedManager {
    static AppScopeManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    NSMutableSet *apps = [self loadPreferences];
    if(apps){
        _scopedApps = apps;
    } else {
        // 初始化scopedApps为空集合
        _scopedApps = [NSMutableSet set];
    }
    return self;
}

- (NSString *)preferencesFilePath {
    return jbroot(@"/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist");
}

- (BOOL)isScope {
    NSString *bundleID = PXSafeBundleIdentifier();
    if (!bundleID) return NO;
    
    
    // Check each scoped app's extension pattern
    if ([_scopedApps containsObject:bundleID]) {
        return YES;
    }
    return NO;
}

- (NSMutableSet *)loadPreferences {
    NSString *filePath = [self preferencesFilePath];
    
    // 检查plist文件是否存在
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"file exists");
        
        // 从plist文件读取数据（现在是一个字典）
        NSDictionary *preferencesDict = [NSDictionary dictionaryWithContentsOfFile:filePath];
        NSLog(@"preferencesDict: %@", preferencesDict);
        
        if (preferencesDict && [preferencesDict isKindOfClass:[NSDictionary class]]) {
            // 从嵌套结构中获取Bundles数组
            NSDictionary *filterDict = preferencesDict[@"Filter"];
            if (filterDict && [filterDict isKindOfClass:[NSDictionary class]]) {
                NSArray *bundlesArray = filterDict[@"Bundles"];
                if (bundlesArray && [bundlesArray isKindOfClass:[NSArray class]]) {
                    // 将NSArray转换为NSMutableSet
                    NSMutableSet *resultSet = [NSMutableSet setWithArray:bundlesArray];
                    NSLog(@"loaded bundles: %@", resultSet);
                    return resultSet;
                }
            }
        }
    }
    
    NSLog(@"[return] nil");
    return nil;
}

- (void)savePreferences:(NSMutableSet *)scopedApps {
    NSString *filePath = [self preferencesFilePath];
    _scopedApps = scopedApps;
    
    // 构建嵌套的字典结构
    NSDictionary *preferencesDict = @{
        @"Filter": @{
            @"Bundles": [_scopedApps allObjects] ?: @[]
        }
    };
    
    BOOL success = [preferencesDict writeToFile:filePath atomically:YES];
    
    if (!success) {
        NSLog(@"Failed to save preferences to plist file: %@", filePath);
    } else {
        NSLog(@"Preferences saved successfully: %@", preferencesDict);
    }
}

// 为了兼容性，可以添加一个转换旧格式的方法
- (void)migrateOldFormatIfNeeded {
    NSString *filePath = [self preferencesFilePath];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        // 尝试读取为数组（旧格式）
        NSArray *oldArray = [NSArray arrayWithContentsOfFile:filePath];
        
        if (oldArray && [oldArray isKindOfClass:[NSArray class]]) {
            NSLog(@"Migrating old format to new format");
            // 转换为新格式并保存
            _scopedApps = [NSMutableSet setWithArray:oldArray];
            [self savePreferences:_scopedApps];
            NSLog(@"Migration completed");
        }
    }
}

// 在初始化后调用迁移方法
- (void)initializeWithMigration {
    [self migrateOldFormatIfNeeded];
}

- (NSDictionary *)loadHookOptions {
    NSString *path = jbroot(@"/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist");
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![prefs isKindOfClass:[NSDictionary class]]) return @{};

    NSDictionary *global = prefs[@"HookOptions"];
    NSDictionary *perApp = prefs[@"PerAppHookOptions"];

    return @{
        @"HookOptions": [global isKindOfClass:[NSDictionary class]] ? global : @{},
        @"PerAppHookOptions": [perApp isKindOfClass:[NSDictionary class]] ? perApp : @{}
    };
}

- (void)saveHookOptions:(NSDictionary *)hookOptions {
    if (![hookOptions isKindOfClass:[NSDictionary class]]) return;

    NSString *path = jbroot(@"/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist");
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (![prefs isKindOfClass:[NSMutableDictionary class]]) {
        prefs = [NSMutableDictionary dictionary];
    }

    NSDictionary *global = hookOptions[@"HookOptions"];
    NSDictionary *perApp = hookOptions[@"PerAppHookOptions"];

    if ([global isKindOfClass:[NSDictionary class]]) {
        prefs[@"HookOptions"] = global;
    }
    if ([perApp isKindOfClass:[NSDictionary class]]) {
        prefs[@"PerAppHookOptions"] = perApp;
    }

    [prefs writeToFile:path atomically:YES];
}

@end

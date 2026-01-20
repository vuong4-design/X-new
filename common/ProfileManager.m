#import "ProfileManager.h"
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>

#define profileDataPath @"/private/var/mobile/Media/ProjectX/profiles.json"

// Forward declaration for app termination
@interface BottomButtons : NSObject
+ (instancetype)sharedInstance;
- (void)terminateApplicationWithBundleID:(NSString *)bundleID;
- (void)killAppViaExecutableName:(NSString *)bundleID;
@end

@interface SBSRelaunchAction : NSObject
+ (id)actionWithReason:(NSString *)reason options:(unsigned int)options targetURL:(NSURL *)targetURL;
@end

@interface FBSSystemService : NSObject
+ (id)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end



@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(id)identifier;
@property(readonly) NSString *bundleExecutable;
@end

@interface NetworkManager : NSObject
+ (void)saveLocalIPAddress:(NSString *)localIP;
@end

@implementation Profile

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _id = [coder decodeObjectOfClass:[NSString class] forKey:@"id"];
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _createdDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdDate"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_id forKey:@"id"];
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeObject:_createdDate forKey:@"createdDate"];
}
- (NSDictionary *)toDictionary {
    NSNumber *timestamp = @0;
    if (self.createdDate) {
        timestamp = @([self.createdDate timeIntervalSince1970]);
    }
    
    return @{
        @"id": self.id ?: @"",
        @"name": self.name ?: @"",
        @"createdDate": timestamp
    };
}

+ (Profile *)fromDictionary:(NSDictionary *)dict {
    Profile *profile = [[Profile alloc] init];
    
    // 设置 id 和 name
    profile.id = dict[@"id"];
    profile.name = dict[@"name"];
    
    // 处理 createdDate
    id dateValue = dict[@"createdDate"];
    if (dateValue) {
        // 如果是 NSNumber（时间戳格式）
        NSTimeInterval timestamp = [dateValue doubleValue];
        if (timestamp > 0) {
            profile.createdDate = [NSDate dateWithTimeIntervalSince1970:timestamp];
        } else {
            profile.createdDate = nil;
        }
        
    } else {
        profile.createdDate = nil;
    }
    
    return profile;
}

@end

@interface ProfileManager ()

@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSString *profilesDirectory;

@end


@implementation ProfileManager

+ (instancetype)sharedManager {
    static ProfileManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[ProfileManager alloc] init];
    });
    return sharedManager;
}
#pragma mark - 保存数据（使用字典，避免归档问题）

- (BOOL)saveData {
    @synchronized (self) {
        @try {
            
            NSMutableDictionary *dataDict = [NSMutableDictionary dictionary];
            
            // 1. 保存 currentId
            if (self.currentId) {
                dataDict[@"currentId"] = self.currentId;
            } else {
                dataDict[@"currentId"] = @"";
            }
            
            // 2. 保存 mutableProfiles 转为字典数组
            NSMutableArray *profilesArray = [NSMutableArray array];
            for (Profile *profile in self.mutableProfiles) {
                // 方法1: 使用自定义的toDictionary方法
                NSDictionary *profileDict = [profile toDictionary];
                [profilesArray addObject:profileDict];
            }
            
            if (profilesArray.count > 0) {
                dataDict[@"mutableProfiles"] = profilesArray;
            } else {
                dataDict[@"mutableProfiles"] = @[];
            }
            NSError *error = nil;
            // 4. 将字典写入文件
            // 使用writeToURL:atomically:方法，它自动处理序列化
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataDict 
                                                    options:NSJSONWritingPrettyPrinted 
                                                        error:&error];
            BOOL success = [jsonData writeToFile:profileDataPath
                                 options:NSDataWritingAtomic 
                                   error:&error];
            if (success) {
                NSLog(@"save success %lu profile", (unsigned long)self.mutableProfiles.count);
            } else {
                NSLog(@"error");
            }
            
            return success;
            
        } @catch (NSException *exception) {
            NSLog(@"exception: %@", exception.reason);
            return NO;
        } 
    }
}

#pragma mark - 加载数据

- (BOOL)loadData {
    @try {
        if(![[NSFileManager defaultManager] fileExistsAtPath:profileDataPath]){
            return NO;
        }
        NSError *readError = nil;
        // 1. 从plist文件读取字典
        NSData *jsonData = [NSData dataWithContentsOfFile:profileDataPath  options:NSDataReadingMappedIfSafe 
                                                error:&readError];
        NSError *jsonError = nil;
        NSDictionary *dataDict = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:jsonData 
                                                options:kNilOptions 
                                                    error:&jsonError];    

        if (!dataDict) {
            return NO;
        }
            
        // 3. 恢复 mutableProfiles
        NSArray *profilesArray = dataDict[@"mutableProfiles"];        
        if (profilesArray && [profilesArray isKindOfClass:[NSArray class]]) {
            [self.mutableProfiles removeAllObjects];
            
            for (id profileItem in profilesArray) {
                if ([profileItem isKindOfClass:[NSDictionary class]]) {
                    // 方法1: 从字典创建Profile对象
                    Profile *profile = [Profile fromDictionary:(NSDictionary *)profileItem];
                    [self.mutableProfiles addObject:profile];
                    
                }
            }
                        
        } else {
            self.mutableProfiles = [NSMutableArray array];
        }

        // 2. 恢复 currentId
        NSString *savedCurrentId = dataDict[@"currentId"];
        if (savedCurrentId && ![savedCurrentId isEqualToString:@""]) {
            self.currentId = savedCurrentId;
        } else if(_mutableProfiles.count > 0){
            self.currentId = _mutableProfiles[0].id;
        }
        
        
        return YES;
        
    } @catch (NSException *exception) {
        NSLog(@"error: %@", exception.reason);
        NSLog(@"异常调用栈: %@", exception.callStackSymbols);
        return NO;
    }
    
}
#pragma mark - 清空数据

- (BOOL)clearData {
    @try {
        self.currentId = nil;
        [self.mutableProfiles removeAllObjects];
        
        // 删除文件
        NSError *error = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:profileDataPath]) {
            [[NSFileManager defaultManager] removeItemAtURL:profileDataPath error:&error];
        }
        
        if (error) {
            NSLog(@"删除数据文件失败: %@", error.localizedDescription);
            return NO;
        }
        
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"清空数据异常: %@", exception.reason);
        return NO;
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableProfiles = [NSMutableArray array];
        _fileManager = [NSFileManager defaultManager];
        
        // Create main WeaponX directory if it doesn't exist
        NSString *projectXDirectory = @"/private/var/mobile/Media/ProjectX";
        [self createDirectoryIfNeeded:projectXDirectory];
        
        // 可选：启动时自动加载数据
        [self loadData];
    }
    return self;
}

- (BOOL)createDirectoryIfNeeded:(NSString *)directory {
    if (![_fileManager fileExistsAtPath:directory]) {
        NSError *error = nil;
        NSDictionary *attributes = @{
            NSFilePosixPermissions: @0755,
            NSFileOwnerAccountName: @"mobile",
            NSFileGroupOwnerAccountName: @"mobile"
        };
        
        [_fileManager createDirectoryAtPath:directory
               withIntermediateDirectories:YES
                                attributes:attributes
                                     error:&error];
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to create directory %@: %@", directory, error);
        } else {
            // Set permissions using NSFileManager
            [_fileManager setAttributes:@{NSFilePosixPermissions: @0755}
                         ofItemAtPath:directory
                              error:&error];
            if (error) {
                NSLog(@"[WeaponX] ⚠️ Failed to set directory permissions: %@", error);
                return NO;
            }
            NSLog(@"[WeaponX] ✅ Created directory: %@", directory);
            return YES;
        }
    }
    return NO;
}


#pragma mark - Public Methods
- (NSString *)genBackupDirectory{
    
    // 目标父目录路径
    NSString *basePath = @"/private/var/mobile/Media/ProjectX";
    
    // 创建目录名
    NSString *directoryName = [self generateProfileID];
    NSString *fullPath = [basePath stringByAppendingPathComponent:directoryName];
    
    // 创建时间戳目录
    BOOL success = [self createDirectoryIfNeeded:fullPath];
    
    if (success) {
        NSLog(@"目录创建成功: %@", fullPath);
        Profile * profile = [[Profile alloc] init];
        profile.id = directoryName;
        profile.name = directoryName;
        profile.createdDate = [NSDate date];
        [_mutableProfiles addObject:profile];
        _currentId = profile.id;
        [self saveData];
        return fullPath;
    } else {
        return nil;
    }
}

- (void)switchToProfile:(Profile *)profile {
    NSLog(@"[WeaponX] 🔄 Switching to profile: %@", profile.name);
    
    // Set as current profile
    self.currentId = profile.id;
    
    // Save to disk
    BOOL success = [self saveData];
}


- (BOOL)isCurrent:(Profile *)profile{
    return self.currentId && [self.currentId isEqualToString:profile.id];
}
- (BOOL)remove:(Profile *)profile{
    if (profile && ![self isCurrent:profile]) {
        return [self removeProfileById:profile.id];
    }
    return NO;
}

#pragma mark - Private Methods

- (NSString *)generateProfileID {
    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSince1970];
    // 毫秒级时间戳（13位）
    long long milliseconds = (long long)(timeInterval * 1000);
    return [NSString stringWithFormat:@"%lld", milliseconds];
}


#pragma mark - Current Profile Central Management



- (NSString *)getActiveProfileId {
    return _currentId;
}

- (NSString *)getActiveDataPath {
    NSString *profileId = [self getActiveProfileId];
    if(!profileId){
        return nil;
    }
    // Build the path to this profile's identity directory
    return [NSString stringWithFormat:@"/private/var/mobile/Media/ProjectX/%@", profileId];
}

- (NSString *)profileIdentityPath {
    // Get current profile ID without directly using ProfileManager
    NSString *profileId = [self getActiveProfileId];
    if (!profileId) {
        NSLog(@"[WeaponX] Error: No active profile when getting identity path");
        return nil;
    }
    
    // Build the path to this profile's identity directory
    NSString *profileDir = [NSString stringWithFormat:@"/private/var/mobile/Media/ProjectX/%@", profileId];
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    
    // Create the directory if it doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:identityDir]) {
        NSDictionary *attributes = @{NSFilePosixPermissions: @0755,
                                    NSFileOwnerAccountName: @"mobile"};
        
        NSError *dirError = nil;
        if (![fileManager createDirectoryAtPath:identityDir 
                    withIntermediateDirectories:YES 
                                     attributes:attributes
                                          error:&dirError]) {
            NSLog(@"[WeaponX] Error creating identity directory: %@", dirError);
            return nil;
        }
    }
    
    return identityDir;
}
- (Profile *) getProfileById:(NSString *) id{
    for(Profile * profile in _mutableProfiles){
        if([profile.id isEqualToString:id]){
            return profile;
        }
    }
    return nil;
}
- (BOOL) removeProfileById:(NSString *) id{
    for(Profile * profile in _mutableProfiles){
        if([profile.id isEqualToString:id]){
            if([self isCurrent:profile]) return NO;
            [_mutableProfiles removeObject: profile];
            [self saveData];
            return YES;
        }
    }
    return NO;
}

- (void)renameProfile:(NSString *)id to:(NSString *)newName {
    Profile * profile = [self getProfileById:id];
    profile.name = newName;
    [self saveData];
}
@end 
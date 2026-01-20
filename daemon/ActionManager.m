#import "ActionManager.h"
#import "AppScopeManager.h"
#import "PhoneInfo.h"
#import "ProfileManager.h"
#import "DataGenManager.h"
#import "SysExecutor.h"
#import "ProjectXLogging.h"
#import <sqlite3.h>

@interface ActionManager()
    @property(nonatomic, strong) ProfileManager *profileManager;
@end
@implementation ActionManager

+ (instancetype)sharedManager {
    static ActionManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}
- (instancetype) init{
    self = [super init];
    _profileManager = [ProfileManager sharedManager];
    return self;
}
- (void) newPhone{
    PXLog(@"[newPhone] cwd=%@", [[NSFileManager defaultManager] currentDirectoryPath]);
    PXLog(@"[newPhone] Starting newPhone flow");
    // // 加载所有被选中应用
    NSMutableSet * loadApps = [[AppScopeManager sharedManager] loadPreferences];
    PXLog(@"[newPhone] Scoped apps: %@", loadApps);
    if (!loadApps || loadApps.count == 0) {
        PXLog(@"[newPhone] No scoped apps; skipping data operations to avoid unintended deletes");
        return;
    }
    // 获取当前生效备份
    NSString * activeBackupPath = [_profileManager getActiveDataPath];
    if(!activeBackupPath){
        // 首次新机
        activeBackupPath = [_profileManager genBackupDirectory];
        
    }
    PXLog(@"[newPhone] Active backup path: %@", activeBackupPath);
    // 创建备份存放目录
    NSString * backupPath = [_profileManager genBackupDirectory];
    if(!backupPath){
        NSLog(@"create Backup directory error");
        PXLog(@"[newPhone] Failed to create backup directory");
        return;
    }
    PXLog(@"[newPhone] New backup path: %@", backupPath);
    for (NSString * bundleId in loadApps){
        PXLog(@"[newPhone] Processing bundle: %@", bundleId);
        // 强制关停应用
        [self killApp:bundleId];
         // 判断应用中是否存在 safari 额外清理 /var/mobile/Library/Safari 
        if([bundleId isEqualToString:@"com.apple.mobilesafari"]){
            PXLog(@"[newPhone] Clearing Safari data");
            [self delFile:@"/var/mobile/Library/Safari"];
        }
        // 清理 prefernce /private/var/mobile/Library/Preferences   
        PXLog(@"[newPhone] Clearing prefs for %@", bundleId);
        [self delFile:[NSString stringWithFormat:@"/private/var/mobile/Library/Preferences/%@.plist",bundleId]];
       
        // 清理or备份沙盒数据到activeBackUp中
        PXLog(@"[newPhone] Backup data to active path for %@", bundleId);
        [self backupFileToPath:bundleId toPath:activeBackupPath];
    }
    // 清理keychain内容
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ProjectXDisableKeychainWipe"]) {
        PXLog(@"[newPhone] Keychain wipe disabled by ProjectXDisableKeychainWipe");
    } else {
        PXLog(@"[newPhone] Clearing keychain");
        [self clearKeyChain];
    }
    // 保存旧参数
    PhoneInfo *phoneInfo = [PhoneInfo loadFromPrefs];
    if (phoneInfo) {
        PXLog(@"[newPhone] Backing up existing PhoneInfo");
        [PhoneInfo saveDictionaryToFile:[phoneInfo toDictionary] toFile:[activeBackupPath stringByAppendingPathComponent:@"phoneInfo.json"]];
    } else {
        PXLog(@"[ProjectXDaemon] No existing PhoneInfo to backup.");
    }
    // 生成新参数
    PhoneInfo * newPhoneInfo = [[DataGenManager sharedManager] generatePhoneInfo];
    PXLog(@"[newPhone] Generated new PhoneInfo");
    [PhoneInfo saveDictionaryToFile:[newPhoneInfo toDictionary] toFile:[backupPath stringByAppendingPathComponent:@"phoneInfo.json"]];
    [newPhoneInfo saveToPrefs];
    // 通知页面刷新显示
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, CFSTR("projectx.newPhoneFinish"), NULL, NULL, YES);
    PXLog(@"[newPhone] Finished newPhone flow");

}

-(void) switchBackup:(NSString *) id{
    PXLog(@"[switchBackup] cwd=%@", [[NSFileManager defaultManager] currentDirectoryPath]);
    PXLog(@"[switchBackup] Requested profile: %@", id);
    Profile *profile = [_profileManager getProfileById:id];
    // 不存在该备份直接返回
    if(!profile || [[ProfileManager sharedManager]isCurrent:profile]) return;
    // 加载所有被选中应用
    NSMutableSet * loadApps = [[AppScopeManager sharedManager] loadPreferences];
    PXLog(@"[switchBackup] Scoped apps: %@", loadApps);
    // 获取当前生效备份
    NSString * activeBackupPath = [_profileManager getActiveDataPath];
    [_profileManager switchToProfile:profile];
    NSString * waitActiveBackupPath = [_profileManager getActiveDataPath];
    PXLog(@"[switchBackup] Active backup path: %@", activeBackupPath);
    PXLog(@"[switchBackup] Target backup path: %@", waitActiveBackupPath);

    for (NSString * bundleId in loadApps){
        PXLog(@"[switchBackup] Processing bundle: %@", bundleId);
        // 强制关停应用
        [self killApp:bundleId];
       
        // 清理or备份沙盒数据到activeBackUp中
        PXLog(@"[switchBackup] Backup current data for %@", bundleId);
        [self backupFileToPath:bundleId toPath:activeBackupPath];

        PXLog(@"[switchBackup] Restoring data for %@", bundleId);
        [self restoreBackupFromPath:waitActiveBackupPath toBundle:bundleId];
    }
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ProjectXDisableKeychainWipe"]) {
        PXLog(@"[switchBackup] Keychain wipe disabled by ProjectXDisableKeychainWipe");
    } else {
        PXLog(@"[switchBackup] Clearing keychain");
        [self clearKeyChain];
    }

    // 加载备份下PhoneInfo
    NSDictionary * phoneInfo = [PhoneInfo loadDictionaryFromFile:[waitActiveBackupPath stringByAppendingPathComponent:@"phoneInfo.json"]];
    [PhoneInfo saveDictionaryToPrefs:phoneInfo];
    // Also post a Darwin notification for the floating indicator
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, 
                                            CFSTR("com.hydra.projectx.profileChanged"), 
                                            NULL, 
                                            NULL, 
                                            YES);
    PXLog(@"[switchBackup] Finished switchBackup");
                
}

- (void) clearKeyChain{
	sqlite3 *database;
	int openResult = sqlite3_open("/private/var/Keychains/keychain-2.db", &database);
	if (openResult == SQLITE_OK)
	{
		sqlite3_exec(database, "DELETE FROM genp WHERE agrp <> 'apple';", NULL, NULL, NULL);

		sqlite3_exec(database, "DELETE FROM cert WHERE agrp <> 'lockdown-identities';", NULL, NULL, NULL);

		sqlite3_exec(database, "DELETE FROM keys WHERE agrp <> 'lockdown-identities';", NULL, NULL, NULL);

		sqlite3_exec(database, "DELETE FROM inet;", NULL, NULL, NULL);

		sqlite3_exec(database, "DELETE FROM sqlite_sequence;", NULL, NULL, NULL);
		
        sqlite3_exec(database, "VACUUM;", NULL, NULL, NULL);
		
        sqlite3_close(database);
	}
}
- (void) killApp:(NSString *) bundleId{
    LSApplicationProxy* appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    
    runCommand([NSString stringWithFormat:@"killall -9 %@",appProxy.bundleExecutable]);
}
-(NSString *) getAppDataPath:(NSString *) bundleId{
    LSApplicationProxy* appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    return [appProxy valueForKeyPath:@"dataContainerURL.path"] ?: @"";
}
- (void)backupFileToPath:(NSString *)bundleId toPath:(NSString *)path {
    NSString *appDataPath = [self getAppDataPath:bundleId];
    NSString *savePath = [path stringByAppendingPathComponent:bundleId];
    PXLog(@"[backupFile] bundle=%@ appData=%@ savePath=%@", bundleId, appDataPath, savePath);
    if (appDataPath.length == 0) {
        PXLog(@"[backupFile] Missing appDataPath for %@; skipping backup to avoid relative deletes", bundleId);
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if(![fm fileExistsAtPath:savePath]){
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        attributes[NSFilePosixPermissions] = @0755;
        if (NSFileOwnerAccountName) {
            attributes[NSFileOwnerAccountName] = @"mobile";
        }
        if (NSFileGroupOwnerAccountName) {
            attributes[NSFileGroupOwnerAccountName] = @"mobile";
        }
        
        [fm createDirectoryAtPath:savePath
               withIntermediateDirectories:YES
                                attributes:attributes
                                     error:nil];
    }
    NSArray *folders = @[@"Documents", @"tmp", @"Library", @"SystemData"];

    //
    // 1️⃣ 先把整个目录直接移动到备份目录
    //
    for (NSString *folder in folders) {
        NSString *src = [appDataPath stringByAppendingPathComponent:folder];
        NSString *dst = [savePath stringByAppendingPathComponent:folder];

        if (![fm fileExistsAtPath:src]) continue;
        PXLog(@"[backupFile] Moving %@ -> %@", src, dst);
        [self delFile:dst];

        NSError *moveErr = nil;
        if (![fm moveItemAtPath:src toPath:dst error:&moveErr]) {
            NSLog(@"[ERROR] move %@ -> %@ failed: %@", src, dst, moveErr);
            PXLog(@"[backupFile] Move failed %@ -> %@ (%@)", src, dst, moveErr);
        }
    }

    //
    // 2️⃣ 重新创建必须存在的目录
    //
    NSArray *recreate = @[
        @"Documents",
        @"tmp",
        @"Library",
        @"SystemData",
        @"Library/Caches",
        @"Library/Preferences"
    ];

    for (NSString *folder in recreate) {
        NSString *dst = [appDataPath stringByAppendingPathComponent:folder];

        PXLog(@"[backupFile] Ensuring directory %@", dst);
        [fm createDirectoryAtPath:dst
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

        // 设置权限 + 属主
        [self applyMobile755Recursive:dst];
    }
}
- (void)restoreBackupFromPath:(NSString *)backupPath toBundle:(NSString *)bundleId {
    NSString *appDataPath = [self getAppDataPath:bundleId];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *savePath = [backupPath stringByAppendingPathComponent:bundleId];
    PXLog(@"[restoreBackup] bundle=%@ appData=%@ savePath=%@", bundleId, appDataPath, savePath);
    if (appDataPath.length == 0) {
        PXLog(@"[restoreBackup] Missing appDataPath for %@; skipping restore to avoid relative deletes", bundleId);
        return;
    }

    NSArray *folders = @[@"Documents", @"tmp", @"Library", @"SystemData"];

    //
    // 1️⃣ 逐个把备份目录拷贝回去（整个目录）
    //
    for (NSString *folder in folders) {
        NSString *src = [savePath stringByAppendingPathComponent:folder];
        NSString *dst = [appDataPath stringByAppendingPathComponent:folder];

        BOOL isDir = NO;
        if (![fm fileExistsAtPath:src isDirectory:&isDir] || !isDir) {
            continue;   // 备份中没有该目录就跳过
        }

        // 目标存在，先删除
        PXLog(@"[restoreBackup] Removing existing %@", dst);
        [self delFile:dst];

        NSError *copyErr = nil;
        if (![fm copyItemAtPath:src toPath:dst error:&copyErr]) {
            NSLog(@"[ERROR] copy %@ -> %@ failed: %@", src, dst, copyErr);
            PXLog(@"[restoreBackup] Copy failed %@ -> %@ (%@)", src, dst, copyErr);
        } else {
            NSLog(@"[DEBUG] Restored %@ -> %@", src, dst);
            PXLog(@"[restoreBackup] Restored %@ -> %@", src, dst);
        }

        // 统一权限（递归）
        [self applyMobile755Recursive:dst];
    }

    //
    // 2️⃣ 确保关键目录存在（有些应用启动必须要有）
    //
    NSArray *mustExist = @[
        @"Documents",
        @"tmp",
        @"Library",
        @"SystemData",
        @"Library/Caches",
        @"Library/Preferences"
    ];

    for (NSString *folder in mustExist) {
        NSString *dst = [appDataPath stringByAppendingPathComponent:folder];

        if (![fm fileExistsAtPath:dst]) {
            PXLog(@"[restoreBackup] Creating missing directory %@", dst);
            [fm createDirectoryAtPath:dst
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        }

        [self applyMobile755Recursive:dst];
    }
}

- (void)applyMobile755Recursive:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[NSFilePosixPermissions] = @(0755);
    if (NSFileOwnerAccountName) {
        attrs[NSFileOwnerAccountName] = @"mobile";
    }
    if (NSFileGroupOwnerAccountName) {
        attrs[NSFileGroupOwnerAccountName] = @"mobile";
    }

    [fm setAttributes:attrs ofItemAtPath:path error:nil];

    NSArray *contents = [fm subpathsAtPath:path];
    for (NSString *sub in contents) {
        NSString *full = [path stringByAppendingPathComponent:sub];
        [fm setAttributes:attrs ofItemAtPath:full error:nil];
    }
}


-(void) delFile:(NSString *) path{
    NSFileManager *fm = [NSFileManager defaultManager];
    // 判断文件是否存在 存在就删除
    if (!path.length) {
        return;
    }
    PXLog(@"Requested delete path: %@", path);
    PXLog(@"delFile stack trace: %@", [NSThread callStackSymbols]);
    NSArray<NSString *> *allowedPrefixes = @[
        @"/private/var/mobile/Containers/Data/Application/",
        @"/var/mobile/Containers/Data/Application/",
        @"/private/var/mobile/Media/ProjectX/",
        @"/var/mobile/Library/Safari",
        @"/private/var/mobile/Library/Preferences/"
    ];
    BOOL allowed = NO;
    for (NSString *prefix in allowedPrefixes) {
        if ([path hasPrefix:prefix]) {
            allowed = YES;
            break;
        }
    }
    if (!allowed) {
        PXLog(@"[ProjectXDaemon] Refusing to delete non-whitelisted path: %@", path);
        return;
    }
    if ([path isEqualToString:@"/var/lib/dpkg"] ||
        [path isEqualToString:@"/private/var/lib/dpkg"] ||
        [path hasPrefix:@"/var/lib/"] ||
        [path hasPrefix:@"/private/var/lib/"]) {
        PXLog(@"[ProjectXDaemon] Refusing to delete protected path: %@", path);
        return;
    }
    if([fm fileExistsAtPath:path]){
        NSString *res = runCommand([NSString stringWithFormat:@"rm -rf %@",path]);
        PXLog(@"delFile res:%@",res);
    }
}

-(void) removeBackup:(NSString *)id{
    if([_profileManager removeProfileById:id]){
        NSString * removePath = [NSString stringWithFormat:@"/private/var/mobile/Media/ProjectX/%@", id];
        [self delFile:removePath];
    }
}

@end

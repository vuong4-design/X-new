#import "PhoneInfo.h"
#import "ProjectXLogging.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>

static CFPropertyListRef PXCopyPhoneInfoPrefs(CFStringRef user, CFStringRef host) {
    return CFPreferencesCopyValue(
        CFSTR("PhoneInfo"),
        CFSTR("com.projectx.phoneinfo"),
        user,
        host
    );
}

static NSDictionary *PXLoadPhoneInfoFromPlistPath(NSString *path) {
    if (path.length == 0) {
        return nil;
    }
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (dict.count == 0) {
        return nil;
    }
    return dict;
}

static NSString *PXSysctlString(const char *name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) {
        return nil;
    }
    char *value = malloc(size);
    if (!value) {
        return nil;
    }
    if (sysctlbyname(name, value, &size, NULL, 0) != 0) {
        free(value);
        return nil;
    }
    NSString *result = [NSString stringWithUTF8String:value];
    free(value);
    return result;
}

static PhoneInfo *PXFallbackPhoneInfo(void) {
    PhoneInfo *info = [[PhoneInfo alloc] init];
    NSString *hwMachine = PXSysctlString("hw.machine");
    NSString *osVersion = [[UIDevice currentDevice] systemVersion];
    NSString *build = PXSysctlString("kern.osversion");

    DeviceModel *model = [[DeviceModel alloc] init];
    model.modelName = hwMachine ?: @"";
    model.hwModel = hwMachine ?: @"";
    info.deviceModel = model;

    IosVersion *iosVersion = [[IosVersion alloc] init];
    iosVersion.version = osVersion ?: @"";
    iosVersion.build = build ?: @"";
    info.iosVersion = iosVersion;

    PXLog(@"[PhoneInfo] ⚠️ Using fallback PhoneInfo hw.machine=%@ build=%@", hwMachine ?: @"<nil>", build ?: @"<nil>");
    return info;
}

@implementation PhoneInfo
#pragma mark - JSON 序列化

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    // 设备标识信息
    dict[@"idfa"] = self.idfa ?: @"";
    dict[@"idfv"] = self.idfv ?: @"";
    dict[@"deviceName"] = self.deviceName ?: @"";
    dict[@"serialNumber"] = self.serialNumber ?: @"";
    dict[@"IMEI"] = self.IMEI ?: @"";
    dict[@"MEID"] = self.MEID ?: @"";
    dict[@"iosVersion"] = [self.iosVersion toDictionary] ?: @{};
    
    // UUID 信息
    dict[@"systemBootUUID"] = self.systemBootUUID ?: @"";
    dict[@"dyldCacheUUID"] = self.dyldCacheUUID ?: @"";
    dict[@"pasteboardUUID"] = self.pasteboardUUID ?: @"";
    dict[@"keychainUUID"] = self.keychainUUID ?: @"";
    dict[@"userDefaultsUUID"] = self.userDefaultsUUID ?: @"";
    dict[@"appGroupUUID"] = self.appGroupUUID ?: @"";
    dict[@"coreDataUUID"] = self.coreDataUUID ?: @"";
    dict[@"appInstallUUID"] = self.appInstallUUID ?: @"";
    dict[@"appContainerUUID"] = self.appContainerUUID ?: @"";
    
    // 其他对象信息
    dict[@"storageInfo"] = [self.storageInfo toDictionary] ?: @{};
    dict[@"batteryInfo"] = [self.batteryInfo toDictionary] ?: @{};
    dict[@"wifiInfo"] = [self.wifiInfo toDictionary] ?: @{};
    dict[@"deviceModel"] = [self.deviceModel toDictionary] ?: @{};
    dict[@"upTimeInfo"] = [self.upTimeInfo toDictionary] ?: @{};
    dict[@"networkInfo"] = [self.networkInfo toDictionary] ?: @{};
    
    return [dict copy];
}

#pragma mark - JSON 反序列化

+ (instancetype)fromDictionary:(NSDictionary *)dict {

    if (![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    PhoneInfo *phoneInfo = [[PhoneInfo alloc] init];
    
    // 设备标识信息
    phoneInfo.idfa = dict[@"idfa"] ?: @"";
    phoneInfo.idfv = dict[@"idfv"] ?: @"";
    phoneInfo.deviceName = dict[@"deviceName"] ?: @"";
    phoneInfo.serialNumber = dict[@"serialNumber"] ?: @"";
    phoneInfo.IMEI = dict[@"IMEI"] ?: @"";
    phoneInfo.MEID = dict[@"MEID"] ?: @"";
    
    // 反序列化嵌套对象
    NSDictionary *iosVersionDict = dict[@"iosVersion"];
    if ([iosVersionDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.iosVersion = [IosVersion fromDictionary:iosVersionDict];
    }
    
    // UUID 信息
    phoneInfo.systemBootUUID = dict[@"systemBootUUID"] ?: @"";
    phoneInfo.dyldCacheUUID = dict[@"dyldCacheUUID"] ?: @"";
    phoneInfo.pasteboardUUID = dict[@"pasteboardUUID"] ?: @"";
    phoneInfo.keychainUUID = dict[@"keychainUUID"] ?: @"";
    phoneInfo.userDefaultsUUID = dict[@"userDefaultsUUID"] ?: @"";
    phoneInfo.appGroupUUID = dict[@"appGroupUUID"] ?: @"";
    phoneInfo.coreDataUUID = dict[@"coreDataUUID"] ?: @"";
    phoneInfo.appInstallUUID = dict[@"appInstallUUID"] ?: @"";
    phoneInfo.appContainerUUID = dict[@"appContainerUUID"] ?: @"";
    
    // 反序列化其他嵌套对象
    NSDictionary *storageInfoDict = dict[@"storageInfo"];
    if ([storageInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.storageInfo = [StorageInfo fromDictionary:storageInfoDict];
    }
    
    NSDictionary *batteryInfoDict = dict[@"batteryInfo"];
    if ([batteryInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.batteryInfo = [BatteryInfo fromDictionary:batteryInfoDict];
    }
    
    NSDictionary *wifiInfoDict = dict[@"wifiInfo"];
    if ([wifiInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.wifiInfo = [WifiInfo fromDictionary:wifiInfoDict];
    }
    
    NSDictionary *deviceModelDict = dict[@"deviceModel"];
    if ([deviceModelDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.deviceModel = [DeviceModel fromDictionary:deviceModelDict];
    }
    
    NSDictionary *upTimeInfoDict = dict[@"upTimeInfo"];
    if ([upTimeInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.upTimeInfo = [UpTimeInfo fromDictionary:upTimeInfoDict];
    }
    NSDictionary *networkInfoDict = dict[@"networkInfo"];
    if ([networkInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.networkInfo = [NetworkInfo fromDictionary:networkInfoDict];
    }
    
    return phoneInfo;
}

#pragma mark - 文件存储

- (BOOL)saveToPrefs{
    NSDictionary *dict = [self toDictionary];
    
    // 使用新的静态方法保存
    return [PhoneInfo saveDictionaryToPrefs:dict ];
}

+ (instancetype)loadFromPrefs{
    NSArray<NSDictionary *> *domains = @[
        @{@"user": (__bridge id)kCFPreferencesAnyUser, @"host": (__bridge id)kCFPreferencesCurrentHost, @"label": @"AnyUser/CurrentHost"},
        @{@"user": (__bridge id)kCFPreferencesCurrentUser, @"host": (__bridge id)kCFPreferencesAnyHost, @"label": @"CurrentUser/AnyHost"},
        @{@"user": (__bridge id)kCFPreferencesCurrentUser, @"host": (__bridge id)kCFPreferencesCurrentHost, @"label": @"CurrentUser/CurrentHost"},
        @{@"user": (__bridge id)kCFPreferencesAnyUser, @"host": (__bridge id)kCFPreferencesAnyHost, @"label": @"AnyUser/AnyHost"}
    ];

    for (NSDictionary *entry in domains) {
        CFStringRef user = (__bridge CFStringRef)entry[@"user"];
        CFStringRef host = (__bridge CFStringRef)entry[@"host"];
        NSString *label = entry[@"label"];
        CFPropertyListRef value = PXCopyPhoneInfoPrefs(user, host);
        if (!value) {
            PXLog(@"[PhoneInfo] ⚠️ CFPreferencesCopyValue (%@) returned nil.", label);
            continue;
        }
        if (CFGetTypeID(value) != CFDictionaryGetTypeID()) {
            PXLog(@"[PhoneInfo] ⚠️ CFPreferencesCopyValue (%@) returned non-dictionary.", label);
            CFRelease(value);
            continue;
        }

        NSDictionary *dict = (__bridge_transfer NSDictionary *)value;
        PhoneInfo *info = [PhoneInfo fromDictionary:dict];
        if (!info) {
            PXLog(@"[PhoneInfo] ⚠️ Failed to decode PhoneInfo dictionary (%@).", label);
            continue;
        }
        NSString *modelName = info.deviceModel.modelName;
        NSString *build = info.iosVersion.build;
        if (modelName.length == 0 || build.length == 0) {
            PXLog(@"[PhoneInfo] ⚠️ Loaded with missing values model=%@ build=%@ (%@).", modelName ?: @"<nil>", build ?: @"<nil>", label);
        }
        return info;
    }

    NSArray<NSString *> *plistPaths = @[
        @"/var/mobile/Library/Preferences/com.projectx.phoneinfo.plist",
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.projectx.phoneinfo.plist"],
        @"/var/jb/var/mobile/Library/Preferences/com.projectx.phoneinfo.plist",
        @"/var/jb/private/var/mobile/Library/Preferences/com.projectx.phoneinfo.plist"
    ];
    for (NSString *path in plistPaths) {
        NSDictionary *dict = PXLoadPhoneInfoFromPlistPath(path);
        if (!dict) {
            PXLog(@"[PhoneInfo] ⚠️ No plist data at %@", path);
            continue;
        }
        PhoneInfo *info = [PhoneInfo fromDictionary:dict];
        if (!info) {
            PXLog(@"[PhoneInfo] ⚠️ Failed to decode PhoneInfo plist at %@", path);
            continue;
        }
        NSString *modelName = info.deviceModel.modelName;
        NSString *build = info.iosVersion.build;
        if (modelName.length == 0 || build.length == 0) {
            PXLog(@"[PhoneInfo] ⚠️ Loaded plist with missing values model=%@ build=%@ path=%@", modelName ?: @"<nil>", build ?: @"<nil>", path);
        }
        return info;
    }

    PXLog(@"[PhoneInfo] ⚠️ All prefs/plist attempts failed; using fallback values.");
    return PXFallbackPhoneInfo();
}

#pragma mark - 直接字典存储和读取

/**
 * 静态方法：将 NSDictionary 直接保存为 JSON 文件
 * @param dict 要保存的字典
 * @param filePath 文件路径
 * @return 保存是否成功
 */
+ (BOOL)saveDictionaryToPrefs:(NSDictionary *)dict {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
        NSLog(@"无效的字典参数");
        return NO;
    }
    
    
    CFPreferencesSetValue(
        CFSTR("PhoneInfo"),
        (__bridge CFPropertyListRef)dict,
        CFSTR("com.projectx.phoneinfo"),
        kCFPreferencesAnyUser,
        kCFPreferencesCurrentHost
    );

    CFPreferencesSynchronize(
        CFSTR("com.projectx.phoneinfo"),
        kCFPreferencesAnyUser,
        kCFPreferencesCurrentHost
    );
    CFPreferencesSetValue(
        CFSTR("PhoneInfo"),
        (__bridge CFPropertyListRef)dict,
        CFSTR("com.projectx.phoneinfo"),
        kCFPreferencesAnyUser,
        kCFPreferencesAnyHost
    );
    CFPreferencesSynchronize(
        CFSTR("com.projectx.phoneinfo"),
        kCFPreferencesAnyUser,
        kCFPreferencesAnyHost
    );
    CFPreferencesSetValue(
        CFSTR("PhoneInfo"),
        (__bridge CFPropertyListRef)dict,
        CFSTR("com.projectx.phoneinfo"),
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    CFPreferencesSynchronize(
        CFSTR("com.projectx.phoneinfo"),
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    NSString *primaryPath = @"/var/mobile/Library/Preferences/com.projectx.phoneinfo.plist";
    if (![PhoneInfo saveDictionaryToFile:dict toFile:primaryPath]) {
        PXLog(@"[PhoneInfo] ⚠️ Failed to write plist to %@", primaryPath);
    } else {
        PXLog(@"[PhoneInfo] ✅ Wrote plist to %@", primaryPath);
    }
    NSString *jbPath = @"/var/jb/var/mobile/Library/Preferences/com.projectx.phoneinfo.plist";
    if (![PhoneInfo saveDictionaryToFile:dict toFile:jbPath]) {
        PXLog(@"[PhoneInfo] ⚠️ Failed to write plist to %@", jbPath);
    } else {
        PXLog(@"[PhoneInfo] ✅ Wrote plist to %@", jbPath);
    }
    NSString *sandboxPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.projectx.phoneinfo.plist"];
    if (![PhoneInfo saveDictionaryToFile:dict toFile:sandboxPath]) {
        PXLog(@"[PhoneInfo] ⚠️ Failed to write plist to %@", sandboxPath);
    } else {
        PXLog(@"[PhoneInfo] ✅ Wrote plist to %@", sandboxPath);
    }
    return YES;
}
/**
 * 静态方法：将 NSDictionary 直接保存为 JSON 文件
 * @param dict 要保存的字典
 * @param filePath 文件路径
 * @return 保存是否成功
 */
+ (BOOL)saveDictionaryToFile:(NSDictionary *)dict toFile:(NSString *)filePath {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
        NSLog(@"无效的字典参数");
        return NO;
    }
    
    if (!filePath || filePath.length == 0) {
        NSLog(@"无效的文件路径");
        return NO;
    }
    
    // 创建目录（如果不存在）
    NSString *directory = [filePath stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:directory]) {
        NSError *error = nil;
        BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                                  withIntermediateDirectories:YES
                                                                   attributes:nil
                                                                        error:&error];
        if (!success) {
            NSLog(@"创建目录失败: %@, error: %@", directory, error);
            return NO;
        }
    }
    
    NSError *error = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:dict
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:&error];
    if (error || !plistData) {
        NSLog(@"Plist 序列化失败: %@", error);
        return NO;
    }
    
    BOOL success = [plistData writeToFile:filePath
                                  options:NSDataWritingAtomic
                                    error:&error];
    
    if (!success) {
        NSLog(@"写入文件失败: %@, error: %@", filePath, error);
        return NO;
    }
    
    NSLog(@"字典已成功保存到: %@", filePath);
    return YES;
}

/**
 * 静态方法：从 JSON 文件读取并返回 NSDictionary
 * @param filePath 文件路径
 * @return 读取的字典，失败返回 nil
 */
+ (NSDictionary *)loadDictionaryFromFile:(NSString *)filePath {
    if (!filePath || filePath.length == 0) {
        NSLog(@"无效的文件路径");
        return nil;
    }
    
    // 检查文件是否存在
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:filePath];
    if (!fileExists) {
        NSLog(@"文件不存在: %@", filePath);
        return nil;
    }
    
    // 检查文件大小
    NSError *fileError = nil;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&fileError];
    if (fileError) {
        NSLog(@"获取文件属性失败: %@", fileError);
        return nil;
    }
    
    NSNumber *fileSize = fileAttributes[NSFileSize];
    if (fileSize.unsignedLongLongValue == 0) {
        NSLog(@"文件为空: %@", filePath);
        return nil;
    }
    
    // 读取文件内容
    NSError *readError = nil;
    NSData *jsonData = [NSData dataWithContentsOfFile:filePath 
                                              options:NSDataReadingMappedIfSafe 
                                                error:&readError];
    
    if (readError) {
        NSLog(@"读取文件失败: %@, error: %@", filePath, readError);
        return nil;
    }
    
    if (!jsonData || jsonData.length == 0) {
        NSLog(@"文件内容为空: %@", filePath);
        return nil;
    }
    
    // 解析 JSON
    NSError *jsonError = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData 
                                                    options:kNilOptions 
                                                      error:&jsonError];
    
    if (jsonError) {
        NSLog(@"JSON 解析失败: %@, error: %@", filePath, jsonError);
        return nil;
    }
    
    if (![jsonObject isKindOfClass:[NSDictionary class]]) {
        NSLog(@"JSON 格式错误，期望字典类型，实际类型: %@", [jsonObject class]);
        return nil;
    }
    
    NSDictionary *dict = (NSDictionary *)jsonObject;
    NSLog(@"成功从文件读取字典，键数量: %lu", (unsigned long)dict.count);
    
    return dict;
}
@end


@implementation IosVersion
-(NSString *) versionAndBuild{
    return [NSString stringWithFormat:@"%@ (%@)", _version, _build];
}
- (NSDictionary *)toDictionary {
    return @{
        @"version": self.version ?: @"",
        @"build": self.build ?: @"",
        @"kernelVersion": self.kernelVersion ?: @"",
        @"darwin": self.darwin ?: @""
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    IosVersion *iosVersion = [[IosVersion alloc] init];
    iosVersion.version = dict[@"version"] ?: @"";
    iosVersion.build = dict[@"build"] ?: @"";
    iosVersion.kernelVersion = dict[@"kernelVersion"] ?: @"";
    iosVersion.darwin = dict[@"darwin"] ?: @"";
    return iosVersion;
}

@end

@implementation StorageInfo
-(NSString *) showInfo{
    return [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                    _totalStorage, 
                                    _freeStorage];
}
- (NSDictionary *)toDictionary {
    return @{
        @"totalStorage": self.totalStorage ?: @"",
        @"freeStorage": self.freeStorage ?: @"",
        @"filesystemType": self.filesystemType ?: @""
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    StorageInfo *storageInfo = [[StorageInfo alloc] init];
    storageInfo.totalStorage = dict[@"totalStorage"] ?: @"";
    storageInfo.freeStorage = dict[@"freeStorage"] ?: @"";
    storageInfo.filesystemType = dict[@"filesystemType"] ?: @"";
    return storageInfo;
}
@end

@implementation BatteryInfo
- (NSDictionary *)toDictionary {
    return @{
        @"batteryLevel": self.batteryLevel ?: @"",
        @"batteryPercentage": self.batteryPercentage ?: @0
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    BatteryInfo *batteryInfo = [[BatteryInfo alloc] init];
    batteryInfo.batteryLevel = dict[@"batteryLevel"] ?: @"";
    batteryInfo.batteryPercentage = dict[@"batteryPercentage"] ?: @0;
    return batteryInfo;
}
@end

@implementation WifiInfo
-(NSString *) showInfo{
    return [NSString stringWithFormat:@"%@ (%@)", _ssid, _bssid];
}
- (NSDictionary *)toDictionary {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *lastConnectionTimeStr = @"";
    if (self.lastConnectionTime) {
        lastConnectionTimeStr = [formatter stringFromDate:self.lastConnectionTime];
    }
    
    return @{
        @"ssid": self.ssid ?: @"",
        @"bssid": self.bssid ?: @"",
        @"networkType": self.networkType ?: @"",
        @"wifiStandard": self.wifiStandard ?: @"",
        @"autoJoin": @(self.autoJoin),
        @"lastConnectionTime": lastConnectionTimeStr
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    WifiInfo *wifiInfo = [[WifiInfo alloc] init];
    wifiInfo.ssid = dict[@"ssid"] ?: @"";
    wifiInfo.bssid = dict[@"bssid"] ?: @"";
    wifiInfo.networkType = dict[@"networkType"] ?: @"";
    wifiInfo.wifiStandard = dict[@"wifiStandard"] ?: @"";
    wifiInfo.autoJoin = [dict[@"autoJoin"] boolValue];
    
    NSString *timeStr = dict[@"lastConnectionTime"];
    if (timeStr && [timeStr isKindOfClass:[NSString class]] && timeStr.length > 0) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        wifiInfo.lastConnectionTime = [formatter dateFromString:timeStr];
    }
    
    return wifiInfo;
}
@end

@implementation UpTimeInfo 
-(NSString *)upTimeStr{
    return [NSString stringWithFormat:@"%.2f hours", _upTime / 3600.0];
}
-(NSString *)bootTimeStr{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:_bootTime];
}

- (NSDictionary *)toDictionary {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *bootTimeStr = @"";
    if (self.bootTime) {
        bootTimeStr = [formatter stringFromDate:self.bootTime];
    }
    
    return @{
        @"upTime": @(self.upTime),
        @"bootTime": bootTimeStr
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    UpTimeInfo *upTimeInfo = [[UpTimeInfo alloc] init];
    upTimeInfo.upTime = [dict[@"upTime"] doubleValue];
    
    NSString *bootTimeStr = dict[@"bootTime"];
    if (bootTimeStr && [bootTimeStr isKindOfClass:[NSString class]] && bootTimeStr.length > 0) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        upTimeInfo.bootTime = [formatter dateFromString:bootTimeStr];
    }
    
    return upTimeInfo;
}

@end

@implementation DeviceModel
- (NSDictionary *)toDictionary {
    return @{
        @"modelName": self.modelName ?: @"",
        @"name": self.name ?: @"",
        @"resolution": self.resolution ?: @"",
        @"viewportResolution": self.viewportResolution ?: @"",
        @"devicePixelRatio": self.devicePixelRatio ?: @1,
        @"screenDensity": self.screenDensity ?: @1,
        @"cpuArchitecture": self.cpuArchitecture ?: @"",
        @"hwModel": self.hwModel ?: @"",
        @"gpuFamily": self.gpuFamily ?: @"",
        @"deviceMemory": self.deviceMemory ?: @0,
        @"cpuCoreCount": self.cpuCoreCount ?: @0,
        @"webGLInfo": [self.webGLInfo toDictionary] ?: @{}
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    DeviceModel *deviceModel = [[DeviceModel alloc] init];
    deviceModel.modelName = dict[@"modelName"] ?: @"";
    deviceModel.name = dict[@"name"] ?: @"";
    deviceModel.resolution = dict[@"resolution"] ?: @"";
    deviceModel.viewportResolution = dict[@"viewportResolution"] ?: @"";
    deviceModel.devicePixelRatio = dict[@"devicePixelRatio"] ?: @1;
    deviceModel.screenDensity = dict[@"screenDensity"] ?: @1;
    deviceModel.cpuArchitecture = dict[@"cpuArchitecture"] ?: @"";
    deviceModel.hwModel = dict[@"hwModel"] ?: @"";
    deviceModel.gpuFamily = dict[@"gpuFamily"] ?: @"";
    deviceModel.deviceMemory = dict[@"deviceMemory"] ?: @0;
    deviceModel.cpuCoreCount = dict[@"cpuCoreCount"] ?: @0;
    
    NSDictionary *webGLInfoDict = dict[@"webGLInfo"];
    if (webGLInfoDict && [webGLInfoDict isKindOfClass:[NSDictionary class]]) {
        deviceModel.webGLInfo = [WebGLInfo fromDictionary:webGLInfoDict];
    }
    
    return deviceModel;
}
- (NSString *) showInfo{
    return _name;
}
@end

@implementation WebGLInfo
- (NSDictionary *)toDictionary {
    return @{
        @"unmaskedVendor": self.unmaskedVendor ?: @"",
        @"unmaskedRenderer": self.unmaskedRenderer ?: @"",
        @"webglVendor": self.webglVendor ?: @"",
        @"webglRenderer": self.webglRenderer ?: @"",
        @"webglVersion": self.webglVersion ?: @"",
        @"maxTextureSize": self.maxTextureSize ?: @0,
        @"maxRenderBufferSize": self.maxRenderBufferSize ?: @0
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    WebGLInfo *webGLInfo = [[WebGLInfo alloc] init];
    webGLInfo.unmaskedVendor = dict[@"unmaskedVendor"] ?: @"";
    webGLInfo.unmaskedRenderer = dict[@"unmaskedRenderer"] ?: @"";
    webGLInfo.webglVendor = dict[@"webglVendor"] ?: @"";
    webGLInfo.webglRenderer = dict[@"webglRenderer"] ?: @"";
    webGLInfo.webglVersion = dict[@"webglVersion"] ?: @"";
    webGLInfo.maxTextureSize = dict[@"maxTextureSize"] ?: @0;
    webGLInfo.maxRenderBufferSize = dict[@"maxRenderBufferSize"] ?: @0;
    return webGLInfo;
}


@end


@implementation NetworkInfo : NSObject

- (NSDictionary *)toDictionary{
      return @{
        @"carrierName": self.carrierName ?: @"",
        @"mcc": self.mcc ?: @"",
        @"mnc": self.mnc ?: @"",
        @"localIPv6Address": self.localIPv6Address ?: @"",
        @"localIPAddress": self.localIPAddress ?: @"",
        @"connectionType": @(self.connectionType)
    };
}
+ (instancetype)fromDictionary:(NSDictionary *)dict{
    NetworkInfo *networkInfo = [[NetworkInfo alloc] init];
    networkInfo.carrierName = dict[@"carrierName"] ?: @"";
    networkInfo.mcc = dict[@"mcc"] ?: @"";
    networkInfo.mnc = dict[@"mnc"] ?: @"";
    networkInfo.localIPv6Address = dict[@"localIPv6Address"] ?: @"";
    networkInfo.localIPAddress = dict[@"localIPAddress"] ?: @"";
    id connectionTypeObj = dict[@"connectionType"];
    if ([connectionTypeObj isKindOfClass:[NSNumber class]]) {
        networkInfo.connectionType = [connectionTypeObj integerValue];
    } else if ([connectionTypeObj isKindOfClass:[NSString class]]) {
        // 兼容：如果存储的是字符串，尝试转换
        networkInfo.connectionType = [connectionTypeObj integerValue];
    } else {
        // 默认值
        networkInfo.connectionType = NetworkConnectionTypeAuto;
    }
    return networkInfo;
}
@end

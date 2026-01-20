#import "DaemonApiManager.h"
#import "HttpRequest.h"
#import "DaemonApi.h"

@implementation DaemonApiManager
+ (instancetype)sharedManager {
    static DaemonApiManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSMutableSet *)getScopeApps {
    // 创建一个 NSMutableSet，用于存储返回的数据
    __block NSMutableSet *scopeApps = [NSMutableSet set];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(GET_SCOPE_APPS,^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            NSString *status = jsonResponse[@"status"];
            if ([status isEqualToString:@"success"]) {
                // 获取 data 字段并确保它是一个数组
                id data = jsonResponse[@"data"];
                if ([data isKindOfClass:[NSArray class]]) {
                    NSArray *dataArray = (NSArray *)data;
                    
                    // 将数组中的元素添加到 NSMutableSet
                    for (id app in dataArray) {
                        if (app) {
                            [scopeApps addObject:app];
                        }
                    }
                } 
            } else {
                NSLog(@"[ProjectXDaemon]success：%@", status);
            }
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return scopeApps;
}

- (void) saveScopeApps:(NSMutableSet *)apps{
    daemonPOST(SAVE_SCOPE_APPS, [apps allObjects], ^(id response, NSError *error) {
        // 处理响应
    });
}


- (NSDictionary *)getHookOptions {
    id response = [self requestWithMethod:@"GET" path:GET_HOOK_OPTIONS data:nil];
    if (![response isKindOfClass:[NSDictionary class]]) return @{};
    NSDictionary *data = response[@"data"];
    return [data isKindOfClass:[NSDictionary class]] ? data : @{};
}

- (void)saveHookOptions:(NSDictionary *)options {
    if (![options isKindOfClass:[NSDictionary class]]) return;
    [self requestWithMethod:@"POST" path:SAVE_HOOK_OPTIONS data:options];
}

- (PhoneInfo *) requestPhoneInfo{
    __block PhoneInfo *phoneInfo;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(GET_PHONE_INFO,^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)jsonResponse;
            phoneInfo = [PhoneInfo fromDictionary:jsonResponse];
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return phoneInfo;
}
- (BOOL) savePhoneInfo:(PhoneInfo *)phoneInfo{
    daemonPOST(SAVE_PHONE_INFO, [phoneInfo toDictionary], ^(id response, NSError *error) {
        // 处理响应
    });
    return YES;
}

- (void) newPhone:(void(^)(id response, NSError *error))completion{
    daemonGET(NEW_PHONE, ^(id response, NSError *error) {
        // 如果有回调，执行回调
        if (completion) {
            completion(response, error);
        }
    });
}

- (void) removeBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion{
    daemonPOST(REMOVE_BACKUP,[profile toDictionary], ^(id response, NSError *error) {
        // 如果有回调，执行回调
        if (completion) {
            completion(response, error);
        }
    });
}

- (void) renameBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion{
    daemonPOST(RENAME_BACKUP,[profile toDictionary], ^(id response, NSError *error) {
        // 如果有回调，执行回调
        if (completion) {
            completion(response, error);
        }
    });
}

- (void) switchBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion{
    daemonPOST(SWITCH_BACKUP,[profile toDictionary], ^(id response, NSError *error) {
        // 如果有回调，执行回调
        if (completion) {
            completion(response, error);
        }
    });
}
- (NSArray *) getAllCarrier{
    __block NSArray *dataArray = @[];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(GET_ALL_CARRIER,^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            NSString *status = jsonResponse[@"status"];
            if ([status isEqualToString:@"success"]) {
                // 获取 data 字段并确保它是一个数组
                id data = jsonResponse[@"data"];
                if ([data isKindOfClass:[NSArray class]]) {
                    dataArray = (NSArray *)data;
                } 
            } else {
                NSLog(@"[ProjectXDaemon]success：%@", status);
            }
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return dataArray;
}
- (NSArray *) getAllVersions{
    __block NSArray *dataArray = @[];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(GET_ALL_VERSIONS,^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            NSString *status = jsonResponse[@"status"];
            if ([status isEqualToString:@"success"]) {
                // 获取 data 字段并确保它是一个数组
                id data = jsonResponse[@"data"];
                if ([data isKindOfClass:[NSArray class]]) {
                    dataArray = (NSArray *)data;
                } 
            } else {
                NSLog(@"[ProjectXDaemon]success：%@", status);
            }
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return dataArray;
}
@end
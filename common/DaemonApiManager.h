#import <Foundation/Foundation.h>
#import "PhoneInfo.h"
#import "ProfileManager.h"

@interface DaemonApiManager:NSObject

+ (instancetype)sharedManager;

- (NSMutableSet *) getScopeApps;
- (void) saveScopeApps:(NSMutableSet *)apps;

- (NSDictionary *)getHookOptions;
- (void)saveHookOptions:(NSDictionary *)options;
- (PhoneInfo *) requestPhoneInfo;
- (BOOL) savePhoneInfo:(PhoneInfo *)phoneInfo;
- (void) newPhone:(void(^)(id response, NSError *error))completion;
- (void) removeBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion;
- (void) renameBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion;
- (void) switchBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion;
- (NSArray *) getAllCarrier;
- (NSArray *) getAllVersions;
@end
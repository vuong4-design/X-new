#import "DataManager.h"
#import "DaemonApiManager.h"
#import "ProjectXLogging.h"

@interface DataManager()
@property (nonatomic, strong) PhoneInfo *phoneInfo;
@end

@implementation DataManager
+ (instancetype)sharedManager {
    static DataManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}
-(instancetype) init{
    self = [super init];
    if (self) {
        [self freshCacheData];
    }
    return self;
}
- (PhoneInfo *) getPhoneInfo{
    if (!_phoneInfo) {
        [self freshCacheData];
    }
    return _phoneInfo;
}
- (void) freshCacheData{
    _phoneInfo = [PhoneInfo loadFromPrefs];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!_phoneInfo) {
        PXLog(@"[DataManager] ⚠️ PhoneInfo is nil for bundle=%@", bundleID);
        return;
    }
    NSString *modelName = _phoneInfo.deviceModel.modelName;
    NSString *build = _phoneInfo.iosVersion.build;
    if (modelName.length == 0 || build.length == 0) {
        PXLog(@"[DataManager] ⚠️ Missing values for bundle=%@ model=%@ build=%@", bundleID, modelName ?: @"<nil>", build ?: @"<nil>");
    }
}
@end

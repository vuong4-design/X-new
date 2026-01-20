#import <Foundation/Foundation.h>
#import "PhoneInfo.h"

#define CurrentPhoneInfo() [[DataManager sharedManager]getPhoneInfo]
@interface DataManager : NSObject 

+ (instancetype)sharedManager;
- (PhoneInfo *) getPhoneInfo;
- (void) freshCacheData;
@end
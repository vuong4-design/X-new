#import <Foundation/Foundation.h>
#import "PhoneInfo.h"

@interface DataGenManager : NSObject
+ (instancetype)sharedManager;
- (PhoneInfo *) generatePhoneInfo;
// - (IosVersion *) generateIOSVersion;
@end
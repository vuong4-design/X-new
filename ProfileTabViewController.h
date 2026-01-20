#import <UIKit/UIKit.h>
#import "ProfileManager.h"

@class ProfileTabViewController;

@protocol ProfileTabViewControllerDelegate <NSObject>

- (void)ProfileTabViewController:(ProfileTabViewController *)viewController didUpdateProfiles:(NSArray<Profile *> *)profiles;

@optional
- (void)ProfileTabViewController:(ProfileTabViewController *)viewController didSelectProfile:(Profile *)profile;

@end

@interface ProfileTabViewController : UIViewController

@property (nonatomic, weak) id<ProfileTabViewControllerDelegate> delegate;
@property (nonatomic, strong) NSMutableArray<Profile *> *profiles;
@property (nonatomic, strong) UITableView *tableView;

- (instancetype)initWithProfiles:(NSMutableArray<Profile *> *)profiles;

@end 
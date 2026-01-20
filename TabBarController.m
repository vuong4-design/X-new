#import "TabBarController.h"
#import "ProjectXViewController.h"
#import "SettingTabViewController.h"
#import <objc/runtime.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/sysctl.h>
#import "ProfileTabViewController.h"
#import "AppTabViewController.h"
#import "HookOptionsViewController.h"
@interface TabBarController ()
// Add a property to hold the Account nav controller
// @property (nonatomic, strong) UINavigationController *accountNavController;
@property (nonatomic, strong) UILabel *networkStatusLabel;
@property (nonatomic, strong) NSMutableDictionary *tabVerificationStatus; // Track which tabs have been verified
@property (nonatomic, strong) NSMutableDictionary *tabLastVerificationTime; // Track when tabs were last verified
@property (nonatomic, assign) BOOL isIPad; // Property to track if device is iPad
@end

@implementation TabBarController

// Helper method to determine if the current device is an iPad
- (BOOL)isDeviceIPad {
    // Use both model check and user interface idiom for better detection
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Set iPad flag
    self.isIPad = [self isDeviceIPad];
    NSLog(@"[WeaponX] Device detected: %@", self.isIPad ? @"iPad" : @"iPhone");
    
    // Initialize verification status tracking
    self.tabVerificationStatus = [NSMutableDictionary dictionaryWithDictionary:@{
        @"map_tab": @NO,
        @"security_tab": @NO
    }];
    
    // Initialize last verification time tracking
    self.tabLastVerificationTime = [NSMutableDictionary dictionary];
    
    // Don't automatically clear verification data on startup since this breaks offline functionality
    // Only clear verification if there's a specific need, like after login/logout or when the plan changes
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    
    // Store configurable grace period if not set
    if ([defaults doubleForKey:@"WeaponXOfflineGracePeriod"] <= 0) {
        // Default to 24 hours (in seconds)
        [defaults setDouble:(24 * 60 * 60) forKey:@"WeaponXOfflineGracePeriod"];
    }
    
    // Set delegate to self for tab change notifications
    self.delegate = self;

    
    
    // Create view controllers
    ProjectXViewController *identityVC = [[ProjectXViewController alloc] init];
    ProjectXViewController *profileVC = [[ProfileTabViewController alloc] init];
    SettingTabViewController *securityVC = [[SettingTabViewController alloc] init];
    AppTabViewController  *appVC = [[AppTabViewController  alloc] init];
    HookOptionsViewController *hooksVC = [[HookOptionsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];

    // AccountViewController *accountVC = [[AccountViewController alloc] init];
    
    // Wrap each view controller in a navigation controller
    UINavigationController *identityNav = [[UINavigationController alloc] initWithRootViewController:identityVC];
    UINavigationController *profileNav = [[UINavigationController alloc] initWithRootViewController:profileVC];
    UINavigationController *securityNav = [[UINavigationController alloc] initWithRootViewController:securityVC];
    UINavigationController *appNav = [[UINavigationController alloc] initWithRootViewController:appVC];
    UINavigationController *hooksNav = [[UINavigationController alloc] initWithRootViewController:hooksVC];
    
    // Create account nav controller but don't add it to tab bar
    // self.accountNavController = [[UINavigationController alloc] initWithRootViewController:accountVC];
    
    // Configure tab bar items (excluding account)
    identityNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Home" 
                                                        image:[UIImage systemImageNamed:@"house.fill"] 
                                                            tag:0];

    profileNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Backups" 
                                                        image:[UIImage systemImageNamed:@"arrow.up.doc.on.clipboard"] 
                                                        tag:1];

    appNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Apps" 
                                                    image:[UIImage systemImageNamed:@"square.grid.2x2"] 
                                                    tag:2];

    securityNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" 
                                                        image:[UIImage systemImageNamed:@"gear"] 
                                                            tag:3];
    hooksNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Hooks"
                                                        image:[UIImage systemImageNamed:@"slider.horizontal.3"]
                                                            tag:4];


    // Set view controllers (excluding account)
    self.viewControllers = @[identityNav, profileNav, appNav, hooksNav, securityNav];
    
    // Set Home tab as default selected tab
    self.selectedIndex = 0;
    
    // Configure tab bar appearance
    self.tabBar.tintColor = [UIColor systemBlueColor];
    self.tabBar.backgroundColor = [UIColor systemBackgroundColor];
    
    // iPad-specific UI adjustments - don't use SplitViewController directly in tabs
    if (self.isIPad) {
        // For iPad, adjust tab bar size and appearance for better use of screen space
        self.tabBar.itemWidth = 120; // Give more space for tab items on iPad
        self.tabBar.itemPositioning = UITabBarItemPositioningCentered;
        
        // Add additional iPad-specific UI setup if needed
        NSLog(@"[WeaponX] Applied iPad-specific TabBar customizations");
    }
    
    
    
}


- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    
    // Verify authentication status whenever tab bar controller appears
    static BOOL firstAppearance = YES;
    
    // Only run this check once during the app launch sequence to avoid 
    // duplicate login screen presentations
    
    firstAppearance = NO;
}


#pragma mark - UITabBarControllerDelegate

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
}



// Add this method to update notification badges on refresh
- (void)updateNotificationBadges {
    [self updateNotificationBadge];
}


@end

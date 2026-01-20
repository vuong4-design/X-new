#import <UIKit/UIKit.h>
#import "TabBarController.h"
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor systemBackgroundColor];
    
    // Set notification delegate
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    
    TabBarController *tabBarController = [[TabBarController alloc] init];
    
    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Set a flag to indicate the app is resuming from recents
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"WeaponXIsResuming"];
    [defaults synchronize];
    
    TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
    
    
    // Reset the resuming flag after a delay to ensure it's used by all components
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [defaults setBool:NO forKey:@"WeaponXIsResuming"];
        [defaults synchronize];
    });
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Use an atomic flag to prevent multiple concurrent auth checks
 
}

- (void)applicationWillTerminate:(UIApplication *)application {
    
    // Clean up notification center if needed
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}




// Helper method to use APIManager's setCurrentScreen method if it exists
- (void)updateCurrentScreen:(NSString *)screenName {

}





@end

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
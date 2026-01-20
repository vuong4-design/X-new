#import "ProjectXSceneDelegate.h"
#import "ProjectXViewController.h"
#import "TabBarController.h"

@interface ProjectXSceneDelegate ()
@property (nonatomic, strong) UINavigationController *navigationController;
@end

@implementation ProjectXSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    
    // Ensure we're on the main thread for UI operations
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scene:scene willConnectToSession:session options:connectionOptions];
        });
        return;
    }
    
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.backgroundColor = [UIColor systemBackgroundColor];
    
    // Create the tab bar controller
    TabBarController *tabBarController = [[TabBarController alloc] init];
    
    // Configure for iPad
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        // For iPad, don't use UISplitViewController with TabBarController
        // Just use the TabBarController directly to avoid the crash
        self.window.rootViewController = tabBarController;
        
        // Alternatively, if you want to maintain a navigation structure:
        // UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:tabBarController];
        // self.window.rootViewController = navController;
    } else {
        // For iPhone, use the tab bar controller directly
        self.window.rootViewController = tabBarController;
    }
    
    [self.window makeKeyAndVisible];
    
    
    // Handle any URL contexts for deep linking
    if (connectionOptions.URLContexts.count > 0) {
        NSSet<UIOpenURLContext *> *urlContexts = connectionOptions.URLContexts;
        UIOpenURLContext *firstContext = urlContexts.allObjects.firstObject;
        NSURL *url = firstContext.URL;
        
    }
}



- (NSUserActivity *)stateRestorationActivityForScene:(UIScene *)scene {
    // Create state restoration activity
    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:@"com.hydra.projectx.state-restoration"];
    activity.title = @"ProjectX State";
    
    // Save view hierarchy state
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        UIViewController *topController = self.navigationController.topViewController;
        if ([topController respondsToSelector:@selector(saveState)]) {
            [topController performSelector:@selector(saveState)];
        }
        
        // Add navigation state
        if (self.navigationController) {
            NSMutableArray *viewControllerTitles = [NSMutableArray array];
            for (UIViewController *controller in self.navigationController.viewControllers) {
                [viewControllerTitles addObject:controller.title ?: @""];
            }
            [activity addUserInfoEntriesFromDictionary:@{
                @"navigation_stack": viewControllerTitles,
                @"selected_index": @(self.navigationController.topViewController ? [self.navigationController.viewControllers indexOfObject:self.navigationController.topViewController] : 0)
            }];
        }
    }
    
    return activity;
}

- (void)scene:(UIScene *)scene restoreInteractionStateWithUserActivity:(NSUserActivity *)activity {
    if ([activity.activityType isEqualToString:@"com.hydra.projectx.state-restoration"]) {
        // Restore navigation state if needed
        NSArray *navigationStack = activity.userInfo[@"navigation_stack"];
        NSNumber *selectedIndex = activity.userInfo[@"selected_index"];
        
        if (navigationStack && selectedIndex && self.navigationController) {
            // Implement navigation stack restoration based on your app's needs
            NSUInteger index = [selectedIndex unsignedIntegerValue];
            if (index < self.navigationController.viewControllers.count) {
                [self.navigationController popToViewController:self.navigationController.viewControllers[index] animated:NO];
            }
        }
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    [self stateRestorationActivityForScene:scene];
    self.window = nil;
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
}

- (void)sceneWillResignActive:(UIScene *)scene {
    [self stateRestorationActivityForScene:scene];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    [self stateRestorationActivityForScene:scene];
}

- (void)windowScene:(UIWindowScene *)windowScene didUpdateCoordinateSpace:(id<UICoordinateSpace>)previousCoordinateSpace interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation traitCollection:(UITraitCollection *)previousTraitCollection {

}

@end 
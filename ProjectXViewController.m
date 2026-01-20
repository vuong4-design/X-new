#import "ProjectXViewController.h"
#import "BottomButtons.h"
#import "ProfileManager.h"
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "DataManager.h"

// Add missing methods via category
@interface LSApplicationWorkspace (ProjectX)
- (NSArray *)allInstalledApplications;
@end

// Add missing properties via category
@interface LSApplicationProxy (ProjectX)
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) NSString *buildVersionString;  // Add this line to get build number
@end

@interface ProjectXViewController () <UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStackView;

@property (nonatomic, strong) NSMutableDictionary *identifierSwitches;
@property (nonatomic, strong) UITableView *appsTableView;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) UIButton *scrollToBottomButton;

// Trial offer banner properties
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *identifierLabels;

// Method declarations
- (void)showError:(NSError *)error;
- (void)setupUI;
- (void)addIdentifierSection:(NSString *)type title:(NSString *)title;
- (void)addAppManagementSection;
- (instancetype)init;
// Add this new method to directly update identifier values
- (void)directUpdateIdentifierValue:(NSString *)identifierType withValue:(NSString *)value;


// Helper methods for finding view controllers
- (UIViewController *)findTopViewController;
- (UITabBarController *)findTabBarController;

@property (nonatomic, strong) NSMutableArray *profiles;


- (NSArray *)findSubviewsOfClass:(Class)cls inView:(UIView *)view;

// Add property to track advanced identifiers visibility in the @interface section
@property (nonatomic, assign) BOOL showAdvancedIdentifiers;
@property (nonatomic, strong) UIButton *showAdvancedButton;
@property (nonatomic, strong) NSMutableArray *advancedIdentifierViews;

// Modify setupUI method to add a "Show Advanced" button and initially hide the advanced identifier sections
- (void)setupUI;

// Add a version of addIdentifierSection that adds to our tracking array and hides them initially
- (void)addAdvancedIdentifierSection:(NSString *)type title:(NSString *)title;

// Handle toggle of advanced identifiers
- (void)toggleAdvancedIdentifiers:(UIButton *)sender;
@end

@implementation ProjectXViewController

- (void)floatingScrollButtonTapped:(UIButton *)sender {
    CGFloat y = self.scrollView.contentOffset.y;
    CGFloat maxY = self.scrollView.contentSize.height - self.scrollView.bounds.size.height;
    if (maxY <= 0) return;
    if (y <= maxY * 0.20) {
        // Scroll to bottom
        CGFloat bottomOffset = self.scrollView.contentSize.height - self.scrollView.bounds.size.height + self.scrollView.contentInset.bottom;
        if (bottomOffset > 0) {
            [self.scrollView setContentOffset:CGPointMake(0, bottomOffset) animated:YES];
        }
    } else if (y >= maxY * 0.80) {
        // Scroll to top
        [self.scrollView setContentOffset:CGPointZero animated:YES];
    }
    // Hide the button after tap
    [UIView animateWithDuration:0.2 animations:^{
        self.scrollToBottomButton.alpha = 0.0;
    }];
}

// Show/hide scrollToBottomButton based on scroll position
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat y = scrollView.contentOffset.y;
    CGFloat maxY = scrollView.contentSize.height - scrollView.bounds.size.height;
    if (maxY <= 0) {
        self.scrollToBottomButton.alpha = 0.0;
        return;
    }
    UIImage *downArrow = [[UIImage systemImageNamed:@"arrow.down"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *upArrow = [[UIImage systemImageNamed:@"arrow.up"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (y <= maxY * 0.20) {
        // Top 20%: show button to scroll to bottom
        [self.scrollToBottomButton setImage:downArrow forState:UIControlStateNormal];
        self.scrollToBottomButton.accessibilityLabel = @"Scroll to bottom";
        [self.scrollToBottomButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [self.scrollToBottomButton addTarget:self action:@selector(floatingScrollButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 1.0;
        }];
    } else if (y >= maxY * 0.80) {
        // Bottom 20%: show button to scroll to top
        [self.scrollToBottomButton setImage:upArrow forState:UIControlStateNormal];
        self.scrollToBottomButton.accessibilityLabel = @"Scroll to top";
        [self.scrollToBottomButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [self.scrollToBottomButton addTarget:self action:@selector(floatingScrollButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 1.0;
        }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 0.0;
        }];
    }
}

#pragma mark - Helper Methods

// Helper method to find top view controller without using keyWindow
- (UIViewController *)findTopViewController {
    UIViewController *rootVC = nil;
    
    // Get the key window using the modern approach for iOS 13+
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        rootVC = window.rootViewController;
                        break;
                    }
                }
                if (rootVC) break;
            }
        }
        
        // Fallback if we couldn't find the key window
        if (!rootVC) {
            UIWindowScene *windowScene = (UIWindowScene *)[connectedScenes anyObject];
            rootVC = windowScene.windows.firstObject.rootViewController;
        }
    } else {
        // Fallback for iOS 12 and below (though this is less likely to be used in iOS 15)
        rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
    }
    
    // Navigate through presented view controllers to find the topmost one
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    return rootVC;
}

- (UIViewController *)findTopViewControllerFromViewController:(UIViewController *)viewController {
    if (viewController.presentedViewController) {
        return [self findTopViewControllerFromViewController:viewController.presentedViewController];
    } else if ([viewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)viewController;
        return [self findTopViewControllerFromViewController:navigationController.topViewController];
    } else if ([viewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)viewController;
        return [self findTopViewControllerFromViewController:tabController.selectedViewController];
    } else {
        return viewController;
    }
}

- (UITabBarController *)findTabBarController {
    UIViewController *rootViewController = [self findTopViewController];
    
    // Check if root is a tab bar controller
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        return (UITabBarController *)rootViewController;
    }
    
    // Check if root is a navigation controller with a tab bar controller
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)rootViewController;
        if ([navController.viewControllers.firstObject isKindOfClass:[UITabBarController class]]) {
            return (UITabBarController *)navController.viewControllers.firstObject;
        }
    }
    
    // Check if tab bar controller is presented
    if ([rootViewController.presentedViewController isKindOfClass:[UITabBarController class]]) {
        return (UITabBarController *)rootViewController.presentedViewController;
    }
    
    return nil;
}


#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if(self){
        _identifierLabels = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Add iPad-specific layout adaptations
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        // Use regular width size class layout for iPad
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        
        // Create container view for iPad layout
        UIView *containerView = [[UIView alloc] init];
        containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:containerView];
        
        // Center container with max width for iPad
        [NSLayoutConstraint activateConstraints:@[
            [containerView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [containerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [containerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            [containerView.widthAnchor constraintLessThanOrEqualToConstant:768], // iPad-appropriate max width
            [containerView.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-40],
            [containerView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
            [containerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20]
        ]];
        
        // Move existing content to container
        for (UIView *subview in self.view.subviews) {
            if (subview != containerView) {
                [containerView addSubview:subview];
            }
        }
    }
    
    self.title = @"Project X";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();

    CFNotificationCenterAddObserver(darwinCenter,
                                (__bridge const void *)self,
                                darwinNotificationCallback,
                                CFSTR("projectx.newPhoneFinish"),
                                NULL,
                                CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(darwinCenter,
                            (__bridge const void *)self,
                            darwinNotificationCallback,
                            CFSTR("com.hydra.projectx.profileChanged"),
                            NULL,
                            CFNotificationSuspensionBehaviorDeliverImmediately);

    
    [self setupUI];
}
static void darwinNotificationCallback(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    // 这里是 C 函数，需要处理桥接
    ProjectXViewController *selfInstance = (__bridge ProjectXViewController *)observer;
    [selfInstance handleProfileChanged:name];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // ... existing code ...
    
    // Check if we should refresh the trial offer banner
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

#pragma mark - UI Setup

- (void)setupUI {
    // Setup scroll view with refresh control
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    
    // Hide vertical scroll indicator (removes the scrollbar line when scrolling)
    self.scrollView.showsVerticalScrollIndicator = NO;
    
    // Set delegate to self to implement scroll restriction
    self.scrollView.delegate = self;
    
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    self.scrollView.refreshControl = refreshControl;
    [self.view addSubview:self.scrollView];
    
    // Setup main stack view with improved spacing
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    self.mainStackView.spacing = 24;
    self.mainStackView.alignment = UIStackViewAlignmentFill;
    self.mainStackView.layoutMargins = UIEdgeInsetsMake(0, 0, 100, 0);
    self.mainStackView.layoutMarginsRelativeArrangement = YES;
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStackView];
    
    // Initialize the advanced identifiers tracking array and flag
    self.advancedIdentifierViews = [NSMutableArray array];
    self.showAdvancedIdentifiers = NO;
    
    // Setup constraints with safe area
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [self.mainStackView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.mainStackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32]
    ]];
    
    
    // Create header stack view for title and generate button
    UIStackView *headerStack = [[UIStackView alloc] init];
    headerStack.axis = UILayoutConstraintAxisHorizontal;
    headerStack.spacing = 8;
    headerStack.alignment = UIStackViewAlignmentCenter;
    headerStack.distribution = UIStackViewDistributionEqualSpacing;
    
    
    
    [self.mainStackView addArrangedSubview:headerStack];
    
    // Add basic identifier sections
    [self addIdentifierSection:@"IDFA" title:@"IDFA"];
    [self addIdentifierSection:@"IDFV" title:@"IDFV"];
    [self addIdentifierSection:@"DeviceModel" title:@"Device Model"];
    [self addIdentifierSection:@"DeviceName" title:@"Device Name"];
    [self addIdentifierSection:@"IOSVersion" title:@"iOS Version"];
    [self addIdentifierSection:@"WiFi" title:@"Wi-Fi Info"];
    [self addIdentifierSection:@"StorageSystem" title:@"Storage Info"];
    [self addIdentifierSection:@"Battery" title:@"Battery Info"];
    
    // Add basic UUID sections - moved System Uptime and Boot Time from advanced to basic
    [self addIdentifierSection:@"SystemUptime" title:@"Uptime"];
    [self addIdentifierSection:@"BootTime" title:@"Boot Time"];
    
    
    // Add advanced identifier sections (will be initially hidden)
    [self addIdentifierSection:@"KeychainUUID" title:@"Keychain UUID"];
    [self addIdentifierSection:@"UserDefaultsUUID" title:@"UserDefaults UUID"];
    [self addIdentifierSection:@"AppGroupUUID" title:@"App Group UUID"];
    [self addIdentifierSection:@"CoreDataUUID" title:@"Core Data UUID"];
    [self addIdentifierSection:@"AppInstallUUID" title:@"App Install UUID"];
    [self addIdentifierSection:@"AppContainerUUID" title:@"App Container UUID"];
    // Moved Serial Number and Pasteboard UUID from basic to advanced
    [self addIdentifierSection:@"SerialNumber" title:@"Serial Number"];
    [self addIdentifierSection:@"PasteboardUUID" title:@"Pasteboard UUID"];
    // Moved System Boot UUID and Dyld Cache UUID from basic to advanced
    [self addIdentifierSection:@"SystemBootUUID" title:@"System Boot UUID"];
    [self addIdentifierSection:@"DyldCacheUUID" title:@"Dyld Cache UUID"];
        
    
    // Add bottom buttons view
    UIView *bottomButtonsView = [[BottomButtons sharedInstance] createBottomButtonsView];
    [self.view addSubview:bottomButtonsView];
    
    // Setup constraints for bottom buttons view
    [NSLayoutConstraint activateConstraints:@[
        [bottomButtonsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bottomButtonsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bottomButtonsView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    
}



#pragma mark - Error Handling

- (void)showError:(NSError *)error {
    if (!error) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                 message:error.localizedDescription
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil];
    
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}


#pragma mark - UI Components

- (void)addIdentifierSection:(NSString *)type title:(NSString *)title {
    // Create section title
    if (@available(iOS 15.0, *)) {
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        titleLabel.textColor = [UIColor labelColor];
        
        // Determine which icon to use based on type

        titleLabel.text = title;
        
        [self.mainStackView addArrangedSubview:titleLabel];
    } else {
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = title;
        titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        titleLabel.textColor = [UIColor labelColor];
        [self.mainStackView addArrangedSubview:titleLabel];
    }
    
    // Reduce spacing between title and container by 50%
    UIView *lastTitleView = self.mainStackView.arrangedSubviews.lastObject; // titleStack
 
    if (lastTitleView) {
        [self.mainStackView setCustomSpacing:4 afterView:lastTitleView];
    }
    
    // Create container view with glassmorphism effect
    UIView *containerView = [[UIView alloc] init];
    
    // Set up glassmorphism effect - works in both light and dark mode
    containerView.backgroundColor = [UIColor clearColor];
    
    // Create blur effect - adapts to light/dark mode automatically
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:blurView];
    
    // Add vibrancy effect for content
    UIVibrancyEffect *vibrancyEffect = [UIVibrancyEffect effectForBlurEffect:blurEffect];
    UIVisualEffectView *vibrancyView = [[UIVisualEffectView alloc] initWithEffect:vibrancyEffect];
    vibrancyView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Setup blur view constraints to fill container
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];
    
    // Add subtle border
    containerView.layer.borderWidth = 0.5;
    containerView.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.2].CGColor;
    containerView.layer.cornerRadius = 20;
    containerView.clipsToBounds = YES;
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add subtle shadow
    containerView.layer.shadowColor = [UIColor blackColor].CGColor;
    containerView.layer.shadowOffset = CGSizeMake(0, 4);
    containerView.layer.shadowRadius = 8;
    containerView.layer.shadowOpacity = 0.1;
    
    // Create vertical stack for identifier and controls
    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 10;
    contentStack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
    contentStack.layoutMarginsRelativeArrangement = YES;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:contentStack];
    
    // Setup content stack constraints
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [contentStack.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];
    
    // Create identifier container with background
    UIView *identifierContainer = [[UIView alloc] init];
    identifierContainer.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.1];
    identifierContainer.layer.cornerRadius = 12;
    identifierContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create identifier label
    UILabel *identifierLabel = [[UILabel alloc] init];

    NSString *currentValue = [self identifierValueForType:type];

    identifierLabel.text = currentValue ?: @"Not Set";
    identifierLabel.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightRegular];
    identifierLabel.textColor = [UIColor labelColor];
    identifierLabel.numberOfLines = 1;
    identifierLabel.adjustsFontSizeToFitWidth = YES;
    identifierLabel.minimumScaleFactor = 0.5;
    identifierLabel.textAlignment = NSTextAlignmentCenter;
    identifierLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.identifierLabels[type] = identifierLabel;
    // Add padding to identifier label
    [identifierContainer addSubview:identifierLabel];
    [NSLayoutConstraint activateConstraints:@[
        [identifierLabel.topAnchor constraintEqualToAnchor:identifierContainer.topAnchor constant:12],
        [identifierLabel.leadingAnchor constraintEqualToAnchor:identifierContainer.leadingAnchor constant:12],
        [identifierLabel.trailingAnchor constraintEqualToAnchor:identifierContainer.trailingAnchor constant:-12],
        [identifierLabel.bottomAnchor constraintEqualToAnchor:identifierContainer.bottomAnchor constant:-12]
    ]];
    
    [contentStack addArrangedSubview:identifierContainer];
    
    // Create horizontal stack for controls
    UIStackView *controlsStack = [[UIStackView alloc] init];
    controlsStack.axis = UILayoutConstraintAxisHorizontal;
    controlsStack.distribution = UIStackViewDistributionEqualSpacing;
    controlsStack.alignment = UIStackViewAlignmentCenter;
    

    
    // Add controls stack to content stack
    [contentStack addArrangedSubview:controlsStack];
    
    // Add container to main stack
    [self.mainStackView addArrangedSubview:containerView];
    
    // Add spacing after the container - reduce by 50% from default spacing
    [self.mainStackView setCustomSpacing:12 afterView:containerView]; // 50% of the default 24 spacing
    
}



#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Get the new text that would result from this change
    NSString *newText = [textField.text stringByReplacingCharactersInRange:range withString:string];
    
    // Limit text field to 50 characters (increased from 26)
    if (newText.length > 50) {
        return NO;
    }
    
    // Only allow alphanumeric characters, dots, and hyphens
    NSCharacterSet *allowedCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    NSCharacterSet *characterSet = [NSCharacterSet characterSetWithCharactersInString:string];
    return [allowedCharacters isSupersetOfSet:characterSet] || [string isEqualToString:@""];
}



#pragma mark - Switch Actions


- (void)refreshData {
    [self.scrollView.refreshControl endRefreshing];
}


- (NSString *)identifierValueForType:(NSString *)type {
    [[DataManager sharedManager] freshCacheData];
    PhoneInfo * phoneInfo = CurrentPhoneInfo();
    // 转换为小写或保持原样，根据你的实际需求
    NSString *lowerType = [type lowercaseString];
    if ([lowerType isEqualToString:@"idfa"]) {
        return phoneInfo.idfa ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"idfv"]) {
        return phoneInfo.idfv ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"devicename"]) {
        return phoneInfo.deviceName ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"serialnumber"]) {
        return phoneInfo.serialNumber ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"iosversion"]) {
        NSString *version = [phoneInfo.iosVersion versionAndBuild];
        if (version.length > 0) {
            return version;
        }
        return [[UIDevice currentDevice] systemVersion] ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"wifi"]) {
        return [phoneInfo.wifiInfo showInfo] ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"storagesystem"]) {
        return [phoneInfo.storageInfo showInfo] ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"battery"]) {
        return phoneInfo.batteryInfo.batteryLevel ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"systembootuuid"]) {
        return phoneInfo.systemBootUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"dyldcacheuuid"]) {
        return phoneInfo.dyldCacheUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"pasteboarduuid"]) {
        return phoneInfo.pasteboardUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"keychainuuid"]) {
        return phoneInfo.keychainUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"userdefaultsuuid"]) {
        return phoneInfo.userDefaultsUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"appgroupuuid"]) {
        return phoneInfo.appGroupUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"systemuptime"]) {
        return phoneInfo.upTimeInfo.upTimeStr ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"boottime"]) {
        return phoneInfo.upTimeInfo.bootTimeStr ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"coredatauuid"]) {
        return phoneInfo.coreDataUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"appinstalluuid"]) {
        return phoneInfo.appInstallUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"appcontaineruuid"]) {
        return phoneInfo.appContainerUUID ?: @"Not Set";
    }
    else if ([lowerType isEqualToString:@"devicemodel"]) {
        NSString *modelName = phoneInfo.deviceModel.showInfo;
        if (modelName.length > 0) {
            return modelName;
        }
        return [[UIDevice currentDevice] model] ?: @"Not Set";
    }
    
    // 如果没有匹配的类型，返回 nil 或默认值
    return @"Not Set";
}
- (NSArray<NSString *> *)allIdentifierTypes {
    return  @[
            @"IDFA",
            @"IDFV", 
            @"DeviceName",
            @"SerialNumber",
            @"IOSVersion",
            @"WiFi",
            @"StorageSystem",
            @"Battery",
            @"SystemBootUUID",
            @"DyldCacheUUID",
            @"PasteboardUUID",
            @"KeychainUUID",
            @"UserDefaultsUUID",
            @"AppGroupUUID",
            @"SystemUptime",
            @"BootTime",
            @"CoreDataUUID",
            @"AppInstallUUID",
            @"AppContainerUUID",
            @"DeviceModel"
        ];
}





- (NSArray *)findSubviewsOfClass:(Class)cls inView:(UIView *)view {
    NSMutableArray *result = [NSMutableArray array];
    
    if ([view isKindOfClass:cls]) {
        [result addObject:view];
    }
    
    for (UIView *subview in view.subviews) {
        [result addObjectsFromArray:[self findSubviewsOfClass:cls inView:subview]];
    }
    
    return result;
}



// Add iPad orientation support
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskPortrait;
}



#pragma mark - More Options Button Action


- (void)handleProfileChanged:(CFStringRef)notificationName {
    // This method is called when the profile changes
    
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSString *type in [self allIdentifierTypes]) {
            UILabel *label = self.identifierLabels[type];
            if (label) {
                label.text = [self identifierValueForType:type];
            }
        }
    });
}

#pragma mark - Memory Management

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterRemoveObserver(darwinCenter,
                                       (__bridge const void *)self,
                                       CFSTR("projectx.newPhoneFinish"),
                                       NULL);
    CFNotificationCenterRemoveObserver(darwinCenter,
                                       (__bridge const void *)self,
                                       CFSTR("com.hydra.projectx.profileChanged"),
                                       NULL);
}
@end

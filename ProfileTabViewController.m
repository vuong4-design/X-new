#import "ProfileTabViewController.h"
#import "ProfileManager.h"
#import "DaemonApiManager.h"
#import "LoadingView.h"

// Custom ProfileTableViewCell class
@interface ProfileTableViewCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *innerCard;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *idLabel;
@property (nonatomic, strong) UIButton *renameButton;
@property (nonatomic, strong) UIButton *infoButton;
@property (nonatomic, strong) UIButton *switchButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, assign) BOOL isCurrentProfile;

- (void)configureWithProfile:(Profile *)profile isCurrentProfile:(BOOL)isCurrentProfile tableWidth:(CGFloat)tableWidth;

@end

@interface ProfileTabViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIDocumentInteractionControllerDelegate>

@property (nonatomic, strong) UIBarButtonItem *editButton;
@property (nonatomic, strong) UIBarButtonItem *doneButton;
@property (nonatomic, strong) NSDictionary *storageInfo;
@property (nonatomic, strong) UILabel *profileCountLabel;
@property (nonatomic, strong) UILabel *currentProfileIdLabel;
@property (nonatomic, strong) NSMutableArray<Profile *> *filteredProfiles;
@property (nonatomic, strong) NSMutableArray<Profile *> *allProfiles;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, assign) BOOL isSearchActive;
@property (nonatomic, strong) UIImageView *searchIcon;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIDocumentInteractionController *documentInteractionController;

@end

@implementation ProfileTabViewController

- (instancetype)initWithProfiles:(NSMutableArray<Profile *> *)profiles {
    self = [super init];
    if (self) {
        if (profiles) {
            _profiles = profiles;
        } else {
            _profiles = [NSMutableArray array];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.filteredProfiles = [NSMutableArray array];
    self.isSearchActive = NO;
    [self setupUI];
    [self updateStorageInfo];
    
    // Setup tap gesture to dismiss keyboard
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    // Optimize tableview for smoother scrolling
    self.tableView.estimatedRowHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.estimatedSectionFooterHeight = 0;
    self.tableView.showsVerticalScrollIndicator = NO;
    
    // Register custom profile cell class
    [self.tableView registerClass:[ProfileTableViewCell class] forCellReuseIdentifier:@"ProfileCell"];
    
    // Pre-layout cells to avoid resize delays
    [self.tableView prefetchDataSource];
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
}
static void darwinNotificationCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    ProfileTabViewController *selfInstance =
        (__bridge ProfileTabViewController *)observer;

    // 立刻切回主线程
    dispatch_async(dispatch_get_main_queue(), ^{
        [selfInstance loadProfilesFromDisk];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Load profiles directly from disk
    [self loadProfilesFromDisk];
    // Update storage info
    [self updateStorageInfo];
}

- (void)updateStorageInfo {
    NSError *error = nil;
    NSURL *documentURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    
    if (error) {
        return;
    }
    
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:documentURL.path error:&error];
    
    if (error) {
        return;
    }
    
    NSNumber *totalSpace = attributes[NSFileSystemSize];
    NSNumber *freeSpace = attributes[NSFileSystemFreeSize];
    
    if (totalSpace && freeSpace) {
        self.storageInfo = @{
            @"totalSpace": totalSpace,
            @"freeSpace": freeSpace
        };
        
        [self.tableView reloadData];
    }
}

- (void)loadProfilesFromDisk {
    NSLog(@"[DEBUG] loadProfilesFromDisk");
    // Get active profile ID directly from central info store first
    [[ProfileManager sharedManager] loadData];
    self.profiles = [ProfileManager sharedManager].mutableProfiles;
    self.allProfiles = [ProfileManager sharedManager].mutableProfiles;
    [self.tableView reloadData];
    [self updateProfileCount];
}


- (void)updateProfileCount {
    if (self.profileCountLabel) {
        // Use the count from all profiles array 
        NSInteger profileCount = self.allProfiles.count;
        NSString *countText = [NSString stringWithFormat:@"%ld", (long)profileCount];
        self.profileCountLabel.text = countText;
    }
    
    // Update the current profile ID label
    [self updateCurrentProfileIdLabel];
}

- (void)updateCurrentProfileIdLabel {
    if (self.currentProfileIdLabel) {
        // Get the active profile from central info store
        NSString *currentProfileId = @"—";
        
        // Get the current profile info from ProfileManager
        ProfileManager *manager = [ProfileManager sharedManager];
        
        if (manager.currentId) {
            // Update the label with current profile ID
            currentProfileId = manager.currentId;
        }
        self.currentProfileIdLabel.text = currentProfileId;
    }
}

- (void)setupUI {
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Setup custom title view with centered title and count
    UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width - 100, 44)];
    
    // Profile count pill - on the left side
    UILabel *countLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 44, 24)];
    countLabel.text = @"0"; // Start with 0, will update after profiles are loaded
    countLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    countLabel.textColor = [UIColor systemBlueColor];
    countLabel.textAlignment = NSTextAlignmentCenter;
    countLabel.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.15];
    countLabel.layer.cornerRadius = 12;
    countLabel.layer.masksToBounds = YES;
    [titleView addSubview:countLabel];
    self.profileCountLabel = countLabel; // Save reference to update later
    
    // "Profiles" text - centered in the title view
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 0, 100, 44)];
    titleLabel.text = @"Backups";
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleView addSubview:titleLabel];
    
    // Current profile ID pill - positioned on the right side
    UIView *rightContainer = [[UIView alloc] initWithFrame:CGRectMake(titleView.bounds.size.width - 70, 6, 200, 32)];
    rightContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
    rightContainer.layer.cornerRadius = 16;
    rightContainer.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [titleView addSubview:rightContainer];
    
    // "Current" and "Profile" text as a two-line label to the left of the profile ID pill
    UIView *labelContainer = [[UIView alloc] initWithFrame:CGRectMake(rightContainer.frame.origin.x - 45, 6, 40, 32)];
    labelContainer.backgroundColor = [UIColor clearColor];
    [titleView addSubview:labelContainer];
    
    // "Current" text (top line)
    UILabel *currentLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, 40, 14)];
    currentLabel.text = @"Current";
    currentLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    currentLabel.textColor = [UIColor secondaryLabelColor];
    currentLabel.textAlignment = NSTextAlignmentRight;
    currentLabel.adjustsFontSizeToFitWidth = YES;
    currentLabel.minimumScaleFactor = 0.8;
    [labelContainer addSubview:currentLabel];
    
    // "Profile" text (bottom line)
    UILabel *profileSubLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, 40, 14)];
    profileSubLabel.text = @"Backup";
    profileSubLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    profileSubLabel.textColor = [UIColor secondaryLabelColor];
    profileSubLabel.textAlignment = NSTextAlignmentRight;
    profileSubLabel.adjustsFontSizeToFitWidth = YES;
    profileSubLabel.minimumScaleFactor = 0.8;
    [labelContainer addSubview:profileSubLabel];
    
    UILabel *idLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 4, 110, 24)];
    idLabel.text = @"—"; // Will update after profiles are loaded
    idLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    idLabel.textColor = [UIColor systemGreenColor];
    idLabel.textAlignment = NSTextAlignmentCenter;
    idLabel.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
    idLabel.layer.cornerRadius = 12;
    idLabel.layer.masksToBounds = YES;
    idLabel.adjustsFontSizeToFitWidth = YES;
    idLabel.minimumScaleFactor = 0.7;
    [rightContainer addSubview:idLabel];
    self.currentProfileIdLabel = idLabel; // Save reference to update later
    
    self.navigationItem.titleView = titleView;
    
    // Setup table view
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    

    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    // Force refresh data
    [self.tableView reloadData];
}


- (void)toggleEditMode {
    BOOL isEditing = self.tableView.isEditing;
    [self.tableView setEditing:!isEditing animated:YES];
    self.navigationItem.rightBarButtonItem = isEditing ? self.editButton : self.doneButton;
}

- (void)dismissKeyboard {
    [self.searchTextField resignFirstResponder];
}

#pragma mark - Search Functionality

- (void)performSearch {
    NSString *searchText = self.searchTextField.text;
    
    // Safety check - ensure filteredProfiles exists
    if (!self.filteredProfiles) {
        self.filteredProfiles = [NSMutableArray array];
    }
    
    if (searchText.length == 0) {
        self.isSearchActive = NO;
        self.filteredProfiles = [self.profiles mutableCopy] ?: [NSMutableArray array];
    } else {
        self.isSearchActive = YES;
        [self.filteredProfiles removeAllObjects];
        
        NSString *lowercaseSearchText = [searchText lowercaseString];
        
        // Search through ALL profiles, not just loaded ones
        for (Profile *profile in self.allProfiles) {    
            
            // Search across all available profile information fields
            NSString *lowercaseName = profile.name ? [profile.name lowercaseString] : @"";
            NSString *lowercaseId = profile.id ? [profile.id lowercaseString] : @"";
            
            // Extract just the number part of the profile ID for easier searching
            NSString *numberPart = @"";
            if ([lowercaseId hasPrefix:@"profile_"]) {
                numberPart = [lowercaseId substringFromIndex:8]; // Skip "profile_"
            }
            
            if ([lowercaseName containsString:lowercaseSearchText] || 
                [lowercaseId containsString:lowercaseSearchText] ||
                [numberPart containsString:lowercaseSearchText]) {
                
                [self.filteredProfiles addObject:profile];
            }
        }
    }
    
    // Safety check - ensure we have a valid table view and the correct section exists
    if (self.tableView && self.tableView.numberOfSections > 3) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView reloadData];
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self performSearch];
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    // When clear button is pressed, reset search immediately
    self.isSearchActive = NO;
    
    // Safety check - ensure profiles exists and make a safe copy
    if (!self.filteredProfiles) {
        self.filteredProfiles = [NSMutableArray array];
    }
    self.filteredProfiles = [self.profiles mutableCopy] ?: [NSMutableArray array];
    
    // Safety check - ensure table view exists and has the correct section
    if (self.tableView && self.tableView.numberOfSections > 3) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationFade];
    } else if (self.tableView) {
        [self.tableView reloadData];
    }
    
    // Show search icon, hide cancel button
    if (self.searchIcon) self.searchIcon.hidden = NO;
    if (self.cancelButton) self.cancelButton.hidden = YES;
    
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    // When ending editing, if the text is empty, ensure visible profiles are showing
    if (textField.text.length == 0 && self.isSearchActive) {
        self.isSearchActive = NO;
        
        // Safety check - ensure profiles exists and make a safe copy
        if (!self.filteredProfiles) {
            self.filteredProfiles = [NSMutableArray array];
        }
        self.filteredProfiles = [self.profiles mutableCopy] ?: [NSMutableArray array];
        
        // Safety check - ensure table view exists and has the correct section
        if (self.tableView && self.tableView.numberOfSections > 3) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationFade];
        } else if (self.tableView) {
            [self.tableView reloadData];
        }
        
        // Show search icon, hide cancel button
        if (self.searchIcon) self.searchIcon.hidden = NO;
        if (self.cancelButton) self.cancelButton.hidden = YES;
    }
}

- (void)textFieldDidChangeSelection:(UITextField *)textField {
    // Nil check for text
    NSString *text = textField.text ?: @"";
    
    // Show/hide cancel button based on text content
    if (text.length > 0) {
        if (self.searchIcon) self.searchIcon.hidden = YES;
        if (self.cancelButton) self.cancelButton.hidden = NO;
        
        // Perform search as user types for immediate feedback
        [self performSearch];
    } else {
        if (self.searchIcon) self.searchIcon.hidden = NO;
        if (self.cancelButton) self.cancelButton.hidden = YES;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4; // Storage section + Search section + Action Buttons section + Profiles section
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        // Storage section
        return 1;
    } else if (section == 1) {
        // Search section
        return 1;
    } else if (section == 2) {
        // Action buttons section
        return 1;
    } else {
        // Profiles section
        if (self.isSearchActive) {
            return self.filteredProfiles.count;
        }else{
            return self.profiles.count;
        } 
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Storage";
    } else if (section == 1) {
        return @"Search Backups";
    } else if (section == 2) {
        return @"Actions";
    } else {
        return @"Backups";
    }
}

// Add custom header view method to include the toggle
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 1) { // Search Profiles section
        // Create a container view for the header
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 44)];
        
        // Create the label
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, 150, 30)];
        titleLabel.text = @"Search Backups";
        titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        titleLabel.textColor = [UIColor secondaryLabelColor];
        [headerView addSubview:titleLabel];
        
  
        return headerView;
    }
    
    // For other sections, use the default header
    return nil;
}


// Override height for header in section
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 1) {
        return 44; // Taller header for the container toggle
    }
    return 30.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        // Storage info cell - enhanced futuristic design
        static NSString *storageIdentifier = @"StorageCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:storageIdentifier];
        
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:storageIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];
            // Pre-set cell frame to avoid resize issues
            CGRect frame = cell.frame;
            frame.size.height = 100;
            frame.size.width = tableView.bounds.size.width;
            cell.frame = frame;
        }
        
        // Remove any existing subviews to prevent duplication
        for (UIView *subview in cell.contentView.subviews) {
            [subview removeFromSuperview];
        }
        
        if (self.storageInfo) {
            NSNumber *totalSpace = self.storageInfo[@"totalSpace"];
            NSNumber *freeSpace = self.storageInfo[@"freeSpace"];
            
            // Format bytes
            NSString *freeSpaceStr = [NSByteCountFormatter stringFromByteCount:freeSpace.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
            NSString *totalSpaceStr = [NSByteCountFormatter stringFromByteCount:totalSpace.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
            
            // Calculate used percentage (still needed for progress bar)
            double usedPercentage = 100.0 * (1.0 - ([freeSpace doubleValue] / [totalSpace doubleValue]));
            
            // Create color based on storage levels
            UIColor *primaryColor;
            UIColor *secondaryColor;
            if (usedPercentage > 90) {
                primaryColor = [UIColor systemRedColor];
                secondaryColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
            } else if (usedPercentage > 75) {
                primaryColor = [UIColor systemOrangeColor];
                secondaryColor = [UIColor colorWithRed:0.9 green:0.6 blue:0.0 alpha:1.0];
            } else {
                primaryColor = [UIColor systemGreenColor];
                secondaryColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.3 alpha:1.0];
            }
            
            // Container card view with shadow
            UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cell.contentView.bounds.size.width - 30, 80)];
            cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
            cardView.layer.cornerRadius = 15;
            cardView.layer.shadowColor = [UIColor blackColor].CGColor;
            cardView.layer.shadowOffset = CGSizeMake(0, 2);
            cardView.layer.shadowOpacity = 0.1;
            cardView.layer.shadowRadius = 4;
            cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:cardView];
            
            // Primary storage label with large font - increased width now that percentage is gone
            UILabel *storageLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, cardView.bounds.size.width - 80, 30)];
            storageLabel.text = freeSpaceStr;
            storageLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
            storageLabel.textColor = primaryColor;
            storageLabel.adjustsFontSizeToFitWidth = YES;
            storageLabel.minimumScaleFactor = 0.7;
            [cardView addSubview:storageLabel];
            
            // "AVAILABLE" text positioned below the primary storage label
            UILabel *availableLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 45, 100, 16)];
            availableLabel.text = @"Available";
            availableLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            availableLabel.textColor = [UIColor secondaryLabelColor];
            [cardView addSubview:availableLabel];
            
            // Total space label - now positioned at the right side
            UILabel *totalLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardView.bounds.size.width - 120, 45, 100, 16)];
            totalLabel.text = [NSString stringWithFormat:@"of %@", totalSpaceStr];
            totalLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
            totalLabel.textColor = [UIColor tertiaryLabelColor];
            totalLabel.textAlignment = NSTextAlignmentRight;
            totalLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            [cardView addSubview:totalLabel];
            
            // Create a custom progress track
            UIView *progressTrack = [[UIView alloc] initWithFrame:CGRectMake(20, 65, cardView.bounds.size.width - 40, 8)];
            progressTrack.backgroundColor = [UIColor systemFillColor];
            progressTrack.layer.cornerRadius = 4;
            progressTrack.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cardView addSubview:progressTrack];
            
            // Create gradient progress fill
            CAGradientLayer *gradientLayer = [CAGradientLayer layer];
            gradientLayer.frame = CGRectMake(0, 0, progressTrack.bounds.size.width * (usedPercentage / 100.0), progressTrack.bounds.size.height);
            gradientLayer.colors = @[(id)primaryColor.CGColor, (id)secondaryColor.CGColor];
            gradientLayer.startPoint = CGPointMake(0.0, 0.5);
            gradientLayer.endPoint = CGPointMake(1.0, 0.5);
            gradientLayer.cornerRadius = progressTrack.layer.cornerRadius;
            
            UIView *progressFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, progressTrack.bounds.size.width * (usedPercentage / 100.0), progressTrack.bounds.size.height)];
            progressFill.layer.cornerRadius = progressTrack.layer.cornerRadius;
            progressFill.layer.masksToBounds = YES;
            progressFill.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [progressFill.layer addSublayer:gradientLayer];
            [progressTrack addSubview:progressFill];
            
            // Add shimmer effect to progress bar for futuristic look
            [self addShimmerToView:progressFill];
            
            // Add storage icon
            UIImageView *storageIcon = [[UIImageView alloc] initWithFrame:CGRectMake(cardView.bounds.size.width - 35, 15, 24, 24)];
            UIImage *diskImage = [UIImage systemImageNamed:@"internaldrive"];
            storageIcon.image = [diskImage imageWithTintColor:primaryColor renderingMode:UIImageRenderingModeAlwaysTemplate];
            storageIcon.tintColor = primaryColor;
            storageIcon.contentMode = UIViewContentModeScaleAspectFit;
            storageIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            [cardView addSubview:storageIcon];
        } else {
            // Loading state
            UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            loadingIndicator.center = CGPointMake(cell.contentView.bounds.size.width / 2, cell.contentView.bounds.size.height / 2);
            loadingIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
            [loadingIndicator startAnimating];
            [cell.contentView addSubview:loadingIndicator];
            
            UILabel *loadingLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, loadingIndicator.frame.origin.y + 30, cell.contentView.bounds.size.width, 20)];
            loadingLabel.text = @"Scanning storage...";
            loadingLabel.textAlignment = NSTextAlignmentCenter;
            loadingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
            loadingLabel.textColor = [UIColor secondaryLabelColor];
            loadingLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:loadingLabel];
        }
        
        // Hide default labels since we're using custom views
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        
        return cell;
    } else if (indexPath.section == 1) {
        // Search cell - modern futuristic design
        static NSString *searchIdentifier = @"SearchCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:searchIdentifier];
        
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:searchIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];
            // Pre-set cell frame to avoid resize issues
            CGRect frame = cell.frame;
            frame.size.height = 70;
            frame.size.width = tableView.bounds.size.width;
            cell.frame = frame;
        }
        
        // Remove any existing subviews to prevent duplication
        for (UIView *subview in cell.contentView.subviews) {
            [subview removeFromSuperview];
        }
        
        // Create a container for our search UI
        UIView *searchContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cell.contentView.bounds.size.width - 30, 60)];
        searchContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
        searchContainer.layer.cornerRadius = 15;
        searchContainer.layer.shadowColor = [UIColor blackColor].CGColor;
        searchContainer.layer.shadowOffset = CGSizeMake(0, 2);
        searchContainer.layer.shadowOpacity = 0.1;
        searchContainer.layer.shadowRadius = 4;
        searchContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:searchContainer];
        
        // Create a modern search text field
        UITextField *searchField = [[UITextField alloc] initWithFrame:CGRectMake(15, 10, searchContainer.bounds.size.width - 80, 40)];
        searchField.placeholder = @"Search by backup name or ID";
        searchField.font = [UIFont systemFontOfSize:16];
        searchField.backgroundColor = [UIColor tertiarySystemBackgroundColor];
        searchField.layer.cornerRadius = 10;
        searchField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 40)];
        searchField.leftViewMode = UITextFieldViewModeAlways;
        searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
        searchField.delegate = self;
        searchField.returnKeyType = UIReturnKeySearch;
        searchField.autocorrectionType = UITextAutocorrectionTypeNo;
        searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        searchField.layer.borderColor = [UIColor systemBlueColor].CGColor;
        searchField.layer.borderWidth = 1.0;
        searchField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [searchContainer addSubview:searchField];
        self.searchTextField = searchField;
        
        // Add search icon
        UIImageView *searchIcon = [[UIImageView alloc] initWithFrame:CGRectMake(searchContainer.bounds.size.width - 55, 15, 30, 30)];
        UIImage *icon = [UIImage systemImageNamed:@"magnifyingglass.circle.fill"];
        searchIcon.image = [icon imageWithTintColor:[UIColor systemBlueColor] renderingMode:UIImageRenderingModeAlwaysTemplate];
        searchIcon.tintColor = [UIColor systemBlueColor];
        searchIcon.contentMode = UIViewContentModeScaleAspectFit;
        searchIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        searchIcon.userInteractionEnabled = YES;
        [searchContainer addSubview:searchIcon];
        self.searchIcon = searchIcon;
        
        // Add a tap gesture to the search icon
        UITapGestureRecognizer *searchTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(searchIconTapped)];
        [searchIcon addGestureRecognizer:searchTap];
        
        // Add cancel button that appears when searching
        UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        cancelButton.frame = CGRectMake(searchContainer.bounds.size.width - 30, 10, 80, 40);
        [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
        cancelButton.titleLabel.font = [UIFont systemFontOfSize:14];
        cancelButton.tintColor = [UIColor systemBlueColor];
        cancelButton.alpha = 0.0; // Initially hidden
        cancelButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [cancelButton addTarget:self action:@selector(cancelSearch) forControlEvents:UIControlEventTouchUpInside];
        [searchContainer addSubview:cancelButton];
        self.cancelButton = cancelButton;
        
        return cell;
    } else if (indexPath.section == 2) {
        // Action buttons cell
        static NSString *actionsIdentifier = @"ActionsCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actionsIdentifier];
        
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:actionsIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];
            // Reduce cell frame height
            CGRect frame = cell.frame;
            frame.size.height = 60; // Reduced from 70
            frame.size.width = tableView.bounds.size.width;
            cell.frame = frame;
        }
        
        // Remove any existing subviews to prevent duplication
        for (UIView *subview in cell.contentView.subviews) {
            [subview removeFromSuperview];
        }
        
        // Create a container for the buttons - reduce height
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cell.contentView.bounds.size.width - 30, 50)]; // Reduced from 60
        container.backgroundColor = [UIColor secondarySystemBackgroundColor];
        container.layer.cornerRadius = 12; // Reduced from 15
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:container];
        
        // Add Import/Export button on the left side - reduce height and adjust position
        UIButton *importExportButton = [UIButton buttonWithType:UIButtonTypeSystem];
        importExportButton.frame = CGRectMake(15, 8, (container.bounds.size.width / 2) - 25, 34); // Reduced height from 40 to 34
        
        // Configure button with icon and text - smaller font
        UIImage *importExportIcon = [UIImage systemImageNamed:@"square.and.arrow.up.on.square"];
        NSString *importExportTitle = @"Import/Export";
        
        // Create configuration for button with smaller text
        UIFont *smallerFont = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium]; // Reduced font size
        [importExportButton setTitle:importExportTitle forState:UIControlStateNormal];
        [importExportButton setImage:importExportIcon forState:UIControlStateNormal];
        importExportButton.titleLabel.font = smallerFont;
        importExportButton.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.1];
        [importExportButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
        importExportButton.contentEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 8);
        importExportButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
        importExportButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
        [importExportButton addTarget:self action:@selector(importExportButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        // Add border
        importExportButton.layer.borderWidth = 1.0;
        importExportButton.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.3].CGColor;
        importExportButton.layer.cornerRadius = 10; // Reduced from 12
        
        [container addSubview:importExportButton];
        
        // Add Trash All Profiles button to the right side - reduce height and adjust position
        UIButton *trashAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
        trashAllButton.frame = CGRectMake(container.bounds.size.width/2 + 10, 8, (container.bounds.size.width / 2) - 25, 34); // Reduced height from 40 to 34
        
        // Configure button with icon and text - smaller text
        UIImage *trashIcon = [UIImage systemImageNamed:@"trash"];
        NSString *trashTitle = @"Delete All Backups";
        
        [trashAllButton setTitle:trashTitle forState:UIControlStateNormal];
        [trashAllButton setImage:trashIcon forState:UIControlStateNormal];
        trashAllButton.titleLabel.font = smallerFont;
        trashAllButton.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.1];
        [trashAllButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        trashAllButton.contentEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 8);
        trashAllButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
        trashAllButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
        [trashAllButton addTarget:self action:@selector(trashAllButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        // Add border
        trashAllButton.layer.borderWidth = 1.0;
        trashAllButton.layer.borderColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.3].CGColor;
        trashAllButton.layer.cornerRadius = 10; // Reduced from 12
        
        [container addSubview:trashAllButton];
        
        // Hide default labels
        cell.textLabel.text = nil;
        
        return cell;
    } else {
        // Profiles section - Show More button
        // Regular profile cells - Use custom ProfileTableViewCell
        static NSString *cellIdentifier = @"ProfileCell";
        ProfileTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        
        if (!cell) {
            cell = [[ProfileTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
            
            // Set up button targets
            [cell.renameButton addTarget:self action:@selector(renameTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.infoButton addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.switchButton addTarget:self action:@selector(switchTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.deleteButton addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];
        }
        
        Profile *profile = self.isSearchActive ? self.filteredProfiles[indexPath.row] : self.profiles[indexPath.row];
        
        // Check if this is the current profile using direct access to central profile info
        BOOL isCurrentProfile = [[ProfileManager sharedManager] isCurrent:profile];
        // Configure the cell with the profile
        [cell configureWithProfile:profile isCurrentProfile:isCurrentProfile tableWidth:tableView.bounds.size.width];
        
        // Set button tags and ensure targets are set up every time 
        // (not just during cell creation) to prevent issues with reused cells
        cell.renameButton.tag = indexPath.row;
        cell.infoButton.tag = indexPath.row;
        cell.switchButton.tag = indexPath.row;
        cell.deleteButton.tag = indexPath.row;
        
        // Remove existing targets first to avoid duplicate actions
        [cell.renameButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.infoButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.switchButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.deleteButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        
        // Re-add targets every time to ensure they work for reused cells
        [cell.renameButton addTarget:self action:@selector(renameTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.infoButton addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.switchButton addTarget:self action:@selector(switchTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.deleteButton addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        return cell;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return 100; // Height for storage cell
    } else if (indexPath.section == 1) {
        return 70; // Height for search cell
    } else if (indexPath.section == 2) {
        return 60; // Reduced from 70 for action buttons cell
    }
    
    // Use a fixed height for profile cards to avoid resize issues
    return 110; // Height for profile cards
}

// Override layoutSubviews to ensure cardView is sized correctly immediately
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // For profile cells, force immediate layout to ensure proper rendering
    if (indexPath.section == 2 && [cell isKindOfClass:[ProfileTableViewCell class]]) {
        [(ProfileTableViewCell *)cell layoutIfNeeded];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only allow editing profile cells, not storage or search
    return indexPath.section == 2;
}

// Leading swipe actions (swipe from left to right) - Switch profile action
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only add actions for profile cells
    if (indexPath.section != 2) {
        return nil;
    }
    
    // Get the profile at this row
    Profile *profile = self.isSearchActive ? self.filteredProfiles[indexPath.row] : self.profiles[indexPath.row];
    
    // Check if this is the current profile
    BOOL isCurrentProfile = NO;
    ProfileManager *manager = [ProfileManager sharedManager];
    if ([manager isCurrent:profile]) {
        isCurrentProfile = YES;
    }
    
    // Don't add switch action if this is already the current profile
    if (isCurrentProfile) {
        return nil;
    }
    
    // Create switch action
    UIContextualAction *switchAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                               title:@"Switch"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        // Call the switch profile method
        [self switchToProfile:profile];
        completionHandler(YES);
    }];
    
    // Set switch action color and image
    switchAction.backgroundColor = [UIColor systemBlueColor];
    switchAction.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
    
    // Create swipe action configuration
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[switchAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    
    return configuration;
}

// Trailing swipe actions (swipe from right to left) - Delete action
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only add actions for profile cells
    if (indexPath.section != 2) {
        return nil;
    }
    
    // Get the profile at this row
    Profile *profile = self.isSearchActive ? self.filteredProfiles[indexPath.row] : self.profiles[indexPath.row];
    
    // Check if this is the current profile
    BOOL isCurrentProfile = NO;
    ProfileManager *manager = [ProfileManager sharedManager];
    if ([manager isCurrent:profile]) {
        isCurrentProfile = YES;
    }
    
    // Create delete action
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        // Check if we can delete this profile (not the last one and not the current one)
        if (self.profiles.count <= 1) {
            // Show error - can't delete last profile
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Delete"
                                                                       message:@"You cannot delete the last profile. At least one profile must remain."
                                                                preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            completionHandler(NO);
            return;
        }
        
        // Check if this is the current active profile
        if (isCurrentProfile) {
            // Show error - can't delete current profile
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Delete"
                                                                           message:@"You cannot delete the currently active profile. Please switch to another profile first."
                                                                preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            completionHandler(NO);
            return;
        }
        
        // Confirm deletion
        UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Delete Profile"
                                                                           message:@"Are you sure you want to delete this profile? This action cannot be undone."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        
        [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                    handler:^(UIAlertAction * _Nonnull action) {
            completionHandler(NO);
        }]];
        
        [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                    style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction * _Nonnull action) {
            
            BOOL success = [[ProfileManager sharedManager] remove:profile];
            if (success) {
                
                // Update local arrays and table view
                if (self.isSearchActive) {
                    [self.filteredProfiles removeObjectAtIndex:indexPath.row];
                    
                    // Also remove from main profiles array
                    NSInteger mainIndex = [self.profiles indexOfObject:profile];
                    if (mainIndex != NSNotFound) {
                        [self.profiles removeObjectAtIndex:mainIndex];
                    }
                } else {
                    [self.profiles removeObjectAtIndex:indexPath.row];
                }
                
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                [self updateProfileCount];
                
                // Notify delegate
                if ([self.delegate respondsToSelector:@selector(ProfileTabViewController:didUpdateProfiles:)]) {
                    [self.delegate ProfileTabViewController:self didUpdateProfiles:self.profiles];
                }
            } else {
                
                // Show error alert
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                           message:[NSString stringWithFormat:@"Failed to delete profile"]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
                
                // Reload profiles from disk to ensure UI is in sync
                [self loadProfilesFromDisk];
            }
            
            completionHandler(YES);
        }]];
        
        [self presentViewController:confirmAlert animated:YES completion:nil];
    }];
    
    // Set delete action image
    deleteAction.image = [UIImage systemImageNamed:@"trash"];
    
    // Create swipe action configuration
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = NO; // Require confirmation for delete
    
    return configuration;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // We're now using dedicated buttons for actions instead of row selection
    // This method is kept for future functionality if needed
}

- (void)switchToProfile:(Profile *)profile {
    // Show loading indicator
    [[LoadingView sharedInstance] showWithMessage:@"Switching backup..."];
    
    // Switch to the selected profile
    [[DaemonApiManager sharedManager] switchBackup:profile comp:^(id response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[LoadingView sharedInstance] hide];

                
            // Show success message
            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Profile Switched"
                                                                                message:[NSString stringWithFormat:@"Successfully switched to profile: %@", profile.name]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                // Notify delegate that a profile was selected
                if ([self.delegate respondsToSelector:@selector(ProfileTabViewController:didSelectProfile:)]) {
                    [self.delegate ProfileTabViewController:self didSelectProfile:profile];
                }
                
                // Dismiss the profile manager
                [self dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:successAlert animated:YES completion:nil];
            [self loadProfilesFromDisk];

        });
    }];
}

- (void)showRenameDialogForProfile:(Profile *)profile {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Profile"
                                                                 message:@"Enter new name for the profile"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = profile.name;
        textField.placeholder = @"Backup name";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction * _Nonnull action) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newName.length > 0) {
            // Show loading indicator
            [[LoadingView sharedInstance] showWithMessage:@"Processing..."];

            profile.name = newName;
            // profile 修改为newName
            [[DaemonApiManager sharedManager] renameBackup:profile comp:^(id response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[LoadingView sharedInstance] hide];
                
                    // Show success message
                    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Profile Renamed"
                                                                                        message:[NSString stringWithFormat:@"Profile successfully renamed to '%@'", newName]
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                    [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:successAlert animated:YES completion:nil];
        
                    
                    // Load profiles from disk to ensure UI is in sync
                    [self loadProfilesFromDisk];
                    
                    // Notify delegate
                    if ([self.delegate respondsToSelector:@selector(ProfileTabViewController:didUpdateProfiles:)]) {
                        if (self.isSearchActive) {
                            [self.delegate ProfileTabViewController:self didUpdateProfiles:self.filteredProfiles];
                        } else {
                            [self.delegate ProfileTabViewController:self didUpdateProfiles:self.profiles];
                        }
                    }
                });
            }];
        
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDeleteConfirmationForProfile:(Profile *)profile {
    // Verify we have more than one profile
    if (self.profiles.count <= 1) {
        // Show error - can't delete last profile
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Delete"
                                                                 message:@"You cannot delete the last profile. At least one profile must remain."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Check if this is the current active profile
    ProfileManager *manager = [ProfileManager sharedManager];
    if ([manager isCurrent:profile]) {
        // Show error - can't delete current profile
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Delete"
                                                                     message:@"You cannot delete the currently active profile. Please switch to another profile first."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Profile"
                                                                 message:@"Are you sure you want to delete this profile? This action cannot be undone."
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction * _Nonnull action) {
        // Show loading indicator
        [[LoadingView sharedInstance] showWithMessage:@"Processing..."];
        
        [manager remove:profile];
        [[DaemonApiManager sharedManager] removeBackup:profile comp:^(id response, NSError *error){
            dispatch_async(dispatch_get_main_queue(), ^{
                [[LoadingView sharedInstance] hide];
                
                // Reload the table view
                [self.tableView reloadData];
                [self updateProfileCount];
                
                // Notify delegate
                if ([self.delegate respondsToSelector:@selector(ProfileTabViewController:didUpdateProfiles:)]) {
                    [self.delegate ProfileTabViewController:self didUpdateProfiles:self.profiles];
                }
                
                // Show success alert
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                                    message:@"Profile deleted successfully"
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
            
            
                // Reload profiles from disk to ensure UI is in sync
                [self loadProfilesFromDisk];
            });
        }];
        // dispatch_async(dispatch_get_main_queue(), );
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)infoTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    
    // Show info/description dialog
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Profile Information"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Description";
        textField.text = profile.id;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                             style:UIAlertActionStyleCancel 
                                           handler:nil]];
    
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Add shimmer effect for futuristic look
- (void)addShimmerToView:(UIView *)view {
    CAGradientLayer *shimmerLayer = [CAGradientLayer layer];
    shimmerLayer.frame = CGRectMake(0, 0, view.bounds.size.width * 3, view.bounds.size.height);
    
    shimmerLayer.colors = @[
        (id)[UIColor colorWithWhite:1 alpha:0.1].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:0.2].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:0.1].CGColor
    ];
    
    shimmerLayer.locations = @[@0.0, @0.5, @1.0];
    shimmerLayer.startPoint = CGPointMake(0, 0.5);
    shimmerLayer.endPoint = CGPointMake(1, 0.5);
    
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position.x"];
    animation.fromValue = @(-view.bounds.size.width * 1.5);
    animation.toValue = @(view.bounds.size.width * 1.5);
    animation.repeatCount = HUGE_VALF;
    animation.duration = 3.0;
    
    [shimmerLayer addAnimation:animation forKey:@"shimmerAnimation"];
    view.layer.mask = nil;
    [view.layer addSublayer:shimmerLayer];
}



- (void)cancelSearch {
    // Clear the search field
    if (self.searchTextField) {
        self.searchTextField.text = @"";
    }
    
    // Reset search state
    self.isSearchActive = NO;
    
    // Safety check for profiles property
    if (!self.filteredProfiles) {
        self.filteredProfiles = [NSMutableArray array];
    }
    self.filteredProfiles = [self.profiles mutableCopy] ?: [NSMutableArray array];
    
    // Safety check for table view
    if (self.tableView && self.tableView.numberOfSections > 3) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationFade];
    } else if (self.tableView) {
        [self.tableView reloadData];
    }
    
    // Show search icon, hide cancel button
    if (self.searchIcon) self.searchIcon.hidden = NO;
    if (self.cancelButton) self.cancelButton.hidden = YES;
    
    // Dismiss keyboard
    if (self.searchTextField) {
        [self.searchTextField resignFirstResponder];
    }
}

- (void)searchIconTapped {
    // Focus on the search text field when search icon is tapped
    if (self.searchTextField) {
        [self.searchTextField becomeFirstResponder];
    }
}

#pragma mark - Profile Card Button Actions

- (void)renameTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    [self showRenameDialogForProfile:profile];
}



- (void)switchTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    
    // Show confirmation dialog for switching profiles
    NSString *message = [NSString stringWithFormat:@"Switch to profile '%@'?", profile.name];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Switch Profile"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                             style:UIAlertActionStyleCancel 
                                           handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Switch" 
                                             style:UIAlertActionStyleDefault 
                                           handler:^(UIAlertAction * _Nonnull action) {
        [self switchToProfile:profile];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    [self showDeleteConfirmationForProfile:profile];
}





- (void)importExportButtonTapped:(UIButton *)sender {
    // To be implemented later
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import/Export"
                                                               message:@"Import/Export functionality will be configured later."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)trashAllButtonTapped:(UIButton *)sender {
    // Show confirmation alert
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete All Profiles"
                                                               message:@"Are you sure you want to delete all profiles? This action cannot be undone. The current active profile and profile '0' will be preserved."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteAllProfiles];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteAllProfiles {
    // Show loading indicator
    [[LoadingView sharedInstance] showWithMessage:@"Processing..."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[LoadingView sharedInstance] hide];
                
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                                   message:[NSString stringWithFormat:@"Failed to access profiles directory: %@", error.localizedDescription]
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            });
            return;
        }
        

        dispatch_async(dispatch_get_main_queue(), ^{
            [[LoadingView sharedInstance] hide];
            // TODO clearAll

            // Reload profiles from disk
            [self loadProfilesFromDisk];
            
            // Show results
            NSString *resultMessage;
                        
            UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:@"Delete Complete"
                                                                              message:resultMessage
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [resultAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:resultAlert animated:YES completion:nil];
        });
    });
}


#pragma mark - UIDocumentInteractionControllerDelegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return self;
}

- (UIView *)documentInteractionControllerViewForPreview:(UIDocumentInteractionController *)controller {
    return self.view;
}

- (CGRect)documentInteractionControllerRectForPreview:(UIDocumentInteractionController *)controller {
    return self.view.bounds;
}

@end

@implementation ProfileTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.backgroundColor = [UIColor clearColor];
        [self setupCell];
    }
    return self;
}

- (void)setupCell {
    // Create all views upfront
    CGFloat cardWidth = self.contentView.bounds.size.width - 30;
    
    // Main card container
    self.cardView = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cardWidth, 100)];
    self.cardView.layer.cornerRadius = 18;
    self.cardView.clipsToBounds = NO;
    self.cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // Add shadow
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 3);
    self.cardView.layer.shadowOpacity = 0.12;
    self.cardView.layer.shadowRadius = 8;
    
    // Inner card
    self.innerCard = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cardWidth, 100)];
    self.innerCard.layer.cornerRadius = 18;
    self.innerCard.clipsToBounds = YES;
    self.innerCard.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Create gradient layer
    self.gradientLayer = [CAGradientLayer layer];
    self.gradientLayer.frame = self.innerCard.bounds;
    self.gradientLayer.cornerRadius = 18;
    self.gradientLayer.startPoint = CGPointMake(0.0, 0.0);
    self.gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    
    // Default gradient colors (will update in configure method)
    self.gradientLayer.colors = @[
        (id)[UIColor secondarySystemBackgroundColor].CGColor,
        (id)[UIColor tertiarySystemBackgroundColor].CGColor
    ];
    
    [self.innerCard.layer insertSublayer:self.gradientLayer atIndex:0];
    [self.cardView addSubview:self.innerCard];
    
    // Profile ID Badge
    // UIView *idBadge = [[UIView alloc] initWithFrame:CGRectMake(15, 15, 40, 40)];
    // idBadge.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.15];
    // idBadge.layer.cornerRadius = 20;
    // [self.innerCard addSubview:idBadge];
    
    // ID Label
    // self.idLabel = [[UILabel alloc] initWithFrame:idBadge.bounds];
    // self.idLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    // self.idLabel.textAlignment = NSTextAlignmentCenter;
    // self.idLabel.adjustsFontSizeToFitWidth = YES;
    // self.idLabel.minimumScaleFactor = 0.7;
    // [idBadge addSubview:self.idLabel];
    
    // Profile Name Label
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(70, 22, self.innerCard.bounds.size.width - 130, 28)];
    self.nameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold]; // Reduced from 20 to 18
    self.nameLabel.textColor = [UIColor labelColor];
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.minimumScaleFactor = 0.7;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail; // Add truncation for long names
    self.nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.innerCard addSubview:self.nameLabel];
    
    // Rename button - increase hit area and add proper background
    self.renameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.renameButton.frame = CGRectMake(200, 22, 30, 30);
    
    [self.renameButton setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
    [self.renameButton setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    self.renameButton.contentEdgeInsets = UIEdgeInsetsMake(5, 5, 5, 5);
    
    self.renameButton.userInteractionEnabled = YES;
    [self.innerCard addSubview:self.renameButton];
    
    // Info button - increase hit area
    self.infoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.infoButton.frame = CGRectMake(self.innerCard.bounds.size.width - 44, 13, 32, 32);
    
    [self.infoButton setImage:[UIImage systemImageNamed:@"info.circle"] forState:UIControlStateNormal];
    [self.infoButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    self.infoButton.contentEdgeInsets = UIEdgeInsetsMake(5, 5, 5, 5);
    
    self.infoButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.infoButton.userInteractionEnabled = YES;
    [self.innerCard addSubview:self.infoButton];
    
    // Create action container
    UIView *actionContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 60, self.innerCard.bounds.size.width, 40)];
    actionContainer.backgroundColor = [UIColor clearColor];
    actionContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.innerCard addSubview:actionContainer];
    
    // Add separator
    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(15, 0, actionContainer.bounds.size.width - 30, 1)];
    separator.backgroundColor = [[UIColor separatorColor] colorWithAlphaComponent:0.3];
    separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [actionContainer addSubview:separator];
    
    // Enhance bottom action buttons with larger touch targets - adjust for 4 buttons
    CGFloat buttonSize = 30; // Slightly smaller for 4 buttons
    CGFloat availableWidth = actionContainer.bounds.size.width - 30; // Total width minus margins
    CGFloat buttonSpacing = (availableWidth - (4 * buttonSize)) / 3; // Space between 4 buttons
    
    
    // Switch button - enhanced for better touch - position after export button
    self.switchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat switchX = buttonSize + buttonSpacing;
    self.switchButton.frame = CGRectMake(switchX, 5, buttonSize, buttonSize);
    
    // Use a simpler SF Symbol that's definitely available in iOS 13+
    [self.switchButton setImage:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"] forState:UIControlStateNormal];
    [self.switchButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    self.switchButton.contentEdgeInsets = UIEdgeInsetsMake(5, 5, 5, 5);
    
    self.switchButton.userInteractionEnabled = YES;
    [actionContainer addSubview:self.switchButton];
    
    // Delete button - enhanced for better touch - move to rightmost position
    self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat deleteX = switchX + buttonSize + buttonSpacing;
    self.deleteButton.frame = CGRectMake(deleteX, 5, buttonSize, buttonSize);
    
    [self.deleteButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    [self.deleteButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    self.deleteButton.contentEdgeInsets = UIEdgeInsetsMake(5, 5, 5, 5);
    
    self.deleteButton.userInteractionEnabled = YES;
    [actionContainer addSubview:self.deleteButton];
    
    // Add button highlights for visual feedback
    [self addButtonHighlightEffects:self.renameButton];
    [self addButtonHighlightEffects:self.infoButton];
    [self addButtonHighlightEffects:self.switchButton];
    [self addButtonHighlightEffects:self.deleteButton];
    
    [self.contentView addSubview:self.cardView];
    
    // Enable user interaction for the entire cell and its subviews
    self.userInteractionEnabled = YES;
    self.contentView.userInteractionEnabled = YES;
    self.cardView.userInteractionEnabled = YES;
    self.innerCard.userInteractionEnabled = YES;
    
    // Hide default labels
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
}

- (void)addButtonHighlightEffects:(UIButton *)button {
    // No-op for legacy button styling to avoid iOS 15-only APIs.
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // Force all views to layout properly
    CGFloat cardWidth = self.contentView.bounds.size.width - 30;
    
    // Update frames to ensure proper layout
    self.cardView.frame = CGRectMake(15, 5, cardWidth, 100);
    self.innerCard.frame = CGRectMake(0, 0, cardWidth, 100);
    self.gradientLayer.frame = self.innerCard.bounds;
    
    // Update rename button position based on actual name width
    if (self.nameLabel.text) {
        CGSize nameSize = [self.nameLabel.text sizeWithAttributes:@{NSFontAttributeName: self.nameLabel.font}];
        
        // Set a maximum position for the pencil button to prevent overlap with info button
        CGFloat maxPencilX = self.innerCard.bounds.size.width - 90; // Keep at least 90px from right edge
        CGFloat calculatedPencilX = self.nameLabel.frame.origin.x + MIN(nameSize.width, self.nameLabel.frame.size.width) + 5;
        CGFloat pencilX = MIN(calculatedPencilX, maxPencilX); // Take the leftmost position
        
        self.renameButton.frame = CGRectMake(pencilX, 22, 30, 30); // Larger touch target
    }
    
    // Update info button position
    self.infoButton.frame = CGRectMake(self.innerCard.bounds.size.width - 44, 13, 32, 32);
    
    // Force immediate layout
    [self.cardView setNeedsLayout];
    [self.innerCard setNeedsLayout];
    [self.cardView layoutIfNeeded];
    [self.innerCard layoutIfNeeded];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    // Reset the cell state
    self.isCurrentProfile = NO;
    self.nameLabel.text = nil;
    self.idLabel.text = nil;
    
    // Reset border
    self.innerCard.layer.borderWidth = 0;
    
    // Reset button visual states
    self.renameButton.backgroundColor = nil;
    self.infoButton.backgroundColor = nil;
    self.switchButton.backgroundColor = nil;
    self.deleteButton.backgroundColor = nil;
    
    // Reset visibility of switchButton
    self.switchButton.hidden = NO;
}

- (void)configureWithProfile:(Profile *)profile isCurrentProfile:(BOOL)isCurrentProfile tableWidth:(CGFloat)tableWidth {
    self.isCurrentProfile = isCurrentProfile;
    
    // Apply color scheme based on current profile status
    if (isCurrentProfile) {
        // Active profile - green theme
        self.gradientLayer.colors = @[
            (id)[[UIColor systemGreenColor] colorWithAlphaComponent:0.2].CGColor,
            (id)[[UIColor systemGreenColor] colorWithAlphaComponent:0.08].CGColor
        ];
        self.innerCard.layer.borderWidth = 1.5;
        self.innerCard.layer.borderColor = [UIColor systemGreenColor].CGColor;
        
        // ID badge background and text
        UIView *idBadge = [self.innerCard.subviews objectAtIndex:0];
        idBadge.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
        self.idLabel.textColor = [UIColor systemGreenColor];
        
        // Hide switch button for the current profile (no need to switch to current profile)
        self.switchButton.hidden = YES;
    } else {
        // Inactive profile - default theme
        self.gradientLayer.colors = @[
            (id)[UIColor secondarySystemBackgroundColor].CGColor,
            (id)[UIColor tertiarySystemBackgroundColor].CGColor
        ];
        self.innerCard.layer.borderWidth = 0;
        
        // ID badge background and text
        UIView *idBadge = [self.innerCard.subviews objectAtIndex:0];
        idBadge.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.15];
        self.idLabel.textColor = [UIColor labelColor];
        
        // Show switch button for inactive profiles
        self.switchButton.hidden = NO;
    }
    
    // Set ID label
    self.idLabel.text = profile.id;
    
    // Set name label with truncation if needed
    NSString *displayName = profile.name;
    // Limit display name to 15 characters to prevent overlap with info button
    if (displayName.length > 15) {
        displayName = [NSString stringWithFormat:@"%@...", [displayName substringToIndex:12]];
    }
    self.nameLabel.text = displayName;
    
    // Update layout to ensure proper positioning of elements
    [self setNeedsLayout];
    [self layoutIfNeeded];
    
    // Calculate pencil position based on visible name width, with a maximum position to prevent overlap
    CGSize nameSize = [displayName sizeWithAttributes:@{NSFontAttributeName: self.nameLabel.font}];
    CGFloat maxPencilX = self.innerCard.bounds.size.width - 90; // Keep at least 90px from right edge
    CGFloat calculatedPencilX = self.nameLabel.frame.origin.x + MIN(nameSize.width, self.nameLabel.frame.size.width) + 5;
    CGFloat pencilX = MIN(calculatedPencilX, maxPencilX); // Take the leftmost position
    
    self.renameButton.frame = CGRectMake(pencilX, 22, 30, 30);
}
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

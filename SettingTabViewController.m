#import "SettingTabViewController.h"
#import "ProjectXLogging.h"
#import <notify.h>  // Add this import for Darwin notification functions
#import <CoreLocation/CoreLocation.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <MapKit/MapKit.h>
#import "SettingManager.h"
#import "DaemonApiManager.h"

@implementation SettingTabViewController

- (instancetype)init {
    self = [super init];
    if (self) {
 
    }
    return self;
}



- (void)refreshPinnedCoordinates {
    // Set the main title directly
    self.title = @"Settings";
    
    // Remove any existing barButtonItems to prevent duplication
    self.navigationItem.rightBarButtonItems = nil;
    self.navigationItem.leftBarButtonItems = nil;
    
    // Create a custom view for the right bar button item (coordinates and time)    


}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshPinnedCoordinates];
    
}



- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor]; // Use system theme color
    
    
    // Create scroll view container
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.showsVerticalScrollIndicator = NO; // Hide the vertical scroll indicator
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];
    
    // Create content view for scroll view
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];
    
    // Setup scroll view constraints
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        
        [contentView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor]
    ]];
    
    // 固定可选项
    self.carrierOptions = [[DaemonApiManager sharedManager] getAllCarrier];
    self.systemVersionOptions = [[DaemonApiManager sharedManager] getAllVersions];

    // 运营商标题
    UILabel *carrierLabel = [[UILabel alloc] init];
    carrierLabel.text = @"Carrier";
    carrierLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    carrierLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:carrierLabel];

    // 运营商下拉
    self.carrierPicker = [[UIPickerView alloc] init];
    self.carrierPicker.delegate = self;
    self.carrierPicker.dataSource = self;
    self.carrierPicker.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.carrierPicker];

    // 系统版本标题
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = @"System Version";
    versionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:versionLabel];

    // 最低版本标题
    UILabel *minLabel = [[UILabel alloc] init];
    minLabel.text = @"Minimum Version";
    minLabel.font = [UIFont systemFontOfSize:14];
    minLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:minLabel];

    // 最低版本下拉
    self.systemPicker1 = [[UIPickerView alloc] init];
    self.systemPicker1.delegate = self;
    self.systemPicker1.dataSource = self;
    self.systemPicker1.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.systemPicker1];

    // 最高版本标题
    UILabel *maxLabel = [[UILabel alloc] init];
    maxLabel.text = @"Maximum Version";
    maxLabel.font = [UIFont systemFontOfSize:14];
    maxLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:maxLabel];

    // 最高版本下拉
    self.systemPicker2 = [[UIPickerView alloc] init];
    self.systemPicker2.delegate = self;
    self.systemPicker2.dataSource = self;
    self.systemPicker2.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.systemPicker2];


    // 保存按钮
    UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveButton setTitle:@"Save Settings" forState:UIControlStateNormal];
    saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [saveButton addTarget:self action:@selector(saveSettings) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:saveButton];

    // 约束
    [NSLayoutConstraint activateConstraints:@[
        [carrierLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [carrierLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16],

        [self.carrierPicker.topAnchor constraintEqualToAnchor:carrierLabel.bottomAnchor constant:8],
        [self.carrierPicker.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.carrierPicker.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.carrierPicker.heightAnchor constraintEqualToConstant:120],

        [versionLabel.topAnchor constraintEqualToAnchor:self.carrierPicker.bottomAnchor constant:25],
        [versionLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16],

        // 最低版本
        [minLabel.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:8],
        [minLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16],

        [self.systemPicker1.topAnchor constraintEqualToAnchor:minLabel.bottomAnchor constant:4],
        [self.systemPicker1.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.systemPicker1.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.systemPicker1.heightAnchor constraintEqualToConstant:120],

        // 最高版本
        [maxLabel.topAnchor constraintEqualToAnchor:self.systemPicker1.bottomAnchor constant:12],
        [maxLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16],

        [self.systemPicker2.topAnchor constraintEqualToAnchor:maxLabel.bottomAnchor constant:4],
        [self.systemPicker2.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.systemPicker2.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.systemPicker2.heightAnchor constraintEqualToConstant:120],

        [saveButton.topAnchor constraintEqualToAnchor:self.systemPicker2.bottomAnchor constant:30],
        [saveButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [saveButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-30]
    ]];
    [self loadSavedSettings];

    
}




#pragma mark - Time Spoofing Control

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
}

// Method to dismiss keyboard when tapping outside text fields
- (void)dismissKeyboard {

}


#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // We don't use the table view anymore, but need to implement the required method
    return 0;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // We don't use the table view anymore, but need to implement the required method
    return [[UITableViewCell alloc] init];
}


- (void)dealloc {
}


#pragma mark - UIPicker Delegate

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    if (pickerView == self.carrierPicker) return self.carrierOptions.count;
    return self.systemVersionOptions.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView
             titleForRow:(NSInteger)row
            forComponent:(NSInteger)component {

    if (pickerView == self.carrierPicker)
        return self.carrierOptions[row];

    return self.systemVersionOptions[row];
}

- (void)pickerView:(UIPickerView *)pickerView
    didSelectRow:(NSInteger)row
       inComponent:(NSInteger)component {

    if (pickerView == self.carrierPicker) {
        self.selectedCarrierIndex = row;
    } else if (pickerView == self.systemPicker1) {
        self.selectedSystemIndex1 = row;
    } else if (pickerView == self.systemPicker2) {
        self.selectedSystemIndex2 = row;
    }
}

- (void)saveSettings {
    NSString *carrier = self.carrierOptions[self.selectedCarrierIndex];
    NSString *system1 = self.systemVersionOptions[self.selectedSystemIndex1];
    NSString *system2 = self.systemVersionOptions[self.selectedSystemIndex2];
    SettingManager * settingManager = [SettingManager sharedManager];
    settingManager.carrierCountryCode = carrier;
    settingManager.minVersion = system1;
    settingManager.maxVersion = system2;
    [settingManager saveToPrefs];
    [self showSuccessMessage:@"Settings saved"];
}
- (void)showSuccessMessage:(NSString *)message {
    // 方法1：使用 UIAlertController（iOS 8+）
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    
    // 1.5秒后自动消失
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}
- (void)loadSavedSettings {
    SettingManager * settingManager = [SettingManager sharedManager];
    [settingManager loadFromPrefs];
    
    NSString *carrier = settingManager.carrierCountryCode;
    self.selectedCarrierIndex = [self.carrierOptions indexOfObject:carrier];
    if (self.selectedCarrierIndex == NSNotFound) self.selectedCarrierIndex = 0;
    [self.carrierPicker selectRow:self.selectedCarrierIndex inComponent:0 animated:NO];

    NSString *minVersion = settingManager.minVersion;
    self.selectedSystemIndex1 = [self.systemVersionOptions indexOfObject:minVersion];
    if (self.selectedSystemIndex1 == NSNotFound) self.selectedSystemIndex1 = 0;
    [self.systemPicker1 selectRow:self.selectedSystemIndex1 inComponent:0 animated:NO];

    NSString *maxVersion = settingManager.maxVersion;
    self.selectedSystemIndex2 = [self.systemVersionOptions indexOfObject:maxVersion];
    if (self.selectedSystemIndex2 == NSNotFound) self.selectedSystemIndex2 = 0;
    [self.systemPicker2 selectRow:self.selectedSystemIndex2 inComponent:0 animated:NO];
}

@end

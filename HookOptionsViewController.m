#import "HookOptionsViewController.h"
#import "DaemonApiManager.h"
#import <notify.h>

static NSString * const kDefaultTargetBundleID = @"com.facebook.Facebook";
static const char *kPrefsChangedNotifyName = "com.projectx.hookprefs.changed";

typedef NS_ENUM(NSInteger, PXSection) {
    PXSectionGlobal = 0,
    PXSectionPerApp = 1,
};

@interface HookOptionsViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *hookItems; // {key,title}
@property (nonatomic, strong) NSMutableDictionary *globalOptions;
@property (nonatomic, strong) NSMutableDictionary *perAppOptionsAll;
@property (nonatomic, copy) NSString *targetBundleID;
@end

@implementation HookOptionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Hooks";
    self.targetBundleID = kDefaultTargetBundleID;

    self.hookItems = @[
        @{@"key": @"core", @"title": @"Core spoofing"},
        @{@"key": @"devicemodel", @"title": @"Device Model"},
        @{@"key": @"devicespec", @"title": @"Device Specs"},
        @{@"key": @"iosversion", @"title": @"iOS Version"},
        @{@"key": @"uuid", @"title": @"UUID"},
        @{@"key": @"wifi", @"title": @"Wi‑Fi"},
        @{@"key": @"network", @"title": @"Network Type"},
        @{@"key": @"battery", @"title": @"Battery"},
        @{@"key": @"storage", @"title": @"Storage"},
        @{@"key": @"pasteboard", @"title": @"Pasteboard"},
        @{@"key": @"userdefaults", @"title": @"UserDefaults"},
        @{@"key": @"canvas", @"title": @"Canvas Fingerprint"},
        @{@"key": @"boottime", @"title": @"Boot Time"},
    ];

    [self reloadFromDaemon];
}

- (void)reloadFromDaemon {
    NSDictionary *data = [[DaemonApiManager sharedManager] getHookOptions];
    NSDictionary *g = data[@"HookOptions"];
    NSDictionary *p = data[@"PerAppHookOptions"];

    self.globalOptions = [([g isKindOfClass:[NSDictionary class]] ? g : @{}) mutableCopy];
    self.perAppOptionsAll = [([p isKindOfClass:[NSDictionary class]] ? p : @{}) mutableCopy];

    [self.tableView reloadData];
}

- (NSMutableDictionary *)mutablePerAppForCurrentTargetCreate:(BOOL)create {
    NSMutableDictionary *perApp = [self.perAppOptionsAll[self.targetBundleID] mutableCopy];
    if (!perApp && create) {
        perApp = [NSMutableDictionary dictionary];
    }
    return perApp;
}

- (BOOL)isEnabledForKey:(NSString *)key inPerApp:(BOOL)perApp {
    if (perApp) {
        NSDictionary *dict = self.perAppOptionsAll[self.targetBundleID];
        id v = [dict isKindOfClass:[NSDictionary class]] ? dict[key] : nil;
        if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    }
    id v = self.globalOptions[key];
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return YES;
}

- (void)setEnabled:(BOOL)enabled forKey:(NSString *)key perApp:(BOOL)perApp {
    if (perApp) {
        NSMutableDictionary *dict = [self mutablePerAppForCurrentTargetCreate:YES];
        dict[key] = @(enabled);
        self.perAppOptionsAll[self.targetBundleID] = dict;
    } else {
        self.globalOptions[key] = @(enabled);
    }

    NSDictionary *payload = @{
        @"HookOptions": self.globalOptions ?: @{},
        @"PerAppHookOptions": self.perAppOptionsAll ?: @{}
    };
    [[DaemonApiManager sharedManager] saveHookOptions:payload];

    notify_post(kPrefsChangedNotifyName);
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == PXSectionGlobal) return @"Global defaults";
    return @"Per‑app override";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == PXSectionPerApp) return self.hookItems.count + 1; // + bundle id row
    return self.hookItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == PXSectionPerApp && indexPath.row == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bundle"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"bundle"];
        cell.textLabel.text = @"Target bundle ID";
        cell.detailTextLabel.text = self.targetBundleID ?: @"";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    NSInteger itemIndex = indexPath.row;
    BOOL perApp = (indexPath.section == PXSectionPerApp);
    if (perApp) itemIndex -= 1;

    NSDictionary *item = self.hookItems[itemIndex];
    NSString *key = item[@"key"];
    NSString *title = item[@"title"];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"switch"];

    cell.textLabel.text = title;

    UISwitch *sw = (UISwitch *)cell.accessoryView;
    if (![sw isKindOfClass:[UISwitch class]]) {
        sw = [[UISwitch alloc] initWithFrame:CGRectZero];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    sw.on = [self isEnabledForKey:key inPerApp:perApp];
    sw.tag = (perApp ? 1000 : 0) + itemIndex;
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    BOOL perApp = (sender.tag >= 1000);
    NSInteger idx = perApp ? (sender.tag - 1000) : sender.tag;
    NSDictionary *item = self.hookItems[idx];
    [self setEnabled:sender.isOn forKey:item[@"key"] perApp:perApp];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == PXSectionPerApp && indexPath.row == 0) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Target bundle ID"
                                                                    message:@"Enter bundle identifier to override (e.g. com.facebook.Facebook)."
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [ac addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.text = self.targetBundleID ?: kDefaultTargetBundleID;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
        }];
        __weak typeof(self) weakSelf = self;
        [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *bid = ac.textFields.firstObject.text ?: @"";
            if (bid.length == 0) bid = kDefaultTargetBundleID;
            weakSelf.targetBundleID = bid;
            [weakSelf.tableView reloadData];
        }]];
        [self presentViewController:ac animated:YES completion:nil];
    }
}

@end

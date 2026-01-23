#import "HookOptionsViewController.h"
#import "DaemonApiManager.h" // kept for later HTTP integration
#import "PXHookPrefsStore.h"
#import "common/PXHookKeys.h"
#import <notify.h>

static NSString * const kDefaultTargetBundleID = @"com.facebook.Facebook";
static const char *kPrefsChangedNotifyName = "com.projectx.hookprefs.changed";

typedef NS_ENUM(NSInteger, PXSection) {
    PXSectionGlobal = 0,
    PXSectionPerApp = 1,
};

@interface HookOptionsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *hookItems; // {key,title}
@property (nonatomic, strong) NSMutableDictionary *globalOptions;
@property (nonatomic, strong) NSMutableDictionary *perAppOptionsAll;
@property (nonatomic, copy) NSString *targetBundleID;
@end

@implementation HookOptionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Hooks";

    // Save/Export/Import + Reset
    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(saveToStorage)];
    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc] initWithTitle:@"Export" style:UIBarButtonItemStylePlain target:self action:@selector(exportConfig)];
    UIBarButtonItem *importBtn = [[UIBarButtonItem alloc] initWithTitle:@"Import" style:UIBarButtonItemStylePlain target:self action:@selector(importConfig)];
    self.navigationItem.rightBarButtonItems = @[saveBtn, exportBtn, importBtn];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(resetMenu)];
    self.targetBundleID = kDefaultTargetBundleID;

    NSDictionary<NSString *, NSString *> *titleMap = @{
        @"battery": @"Battery",
        @"boottime": @"Boot Time",
        @"canvas": @"Canvas Fingerprint",
        @"core": @"Core spoofing",
        @"devicemodel": @"Device Model",
        @"mgprobe": @"MG Probe",
        @"devicespec": @"Device Specs",
        @"identifier": @"Identifiers",
        @"iosversion": @"iOS Version",
        @"jailbreak": @"Jailbreak",
        @"network": @"Network Type",
        @"pasteboard": @"Pasteboard",
        @"storage": @"Storage",
        @"userdefaults": @"UserDefaults",
        @"uuid": @"UUID",
        @"wifi": @"Wi‑Fi",
    };

    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in PXAllHookKeys()) {
        NSString *title = titleMap[key] ?: [key capitalizedString];
        [items addObject:@{@"key": key, @"title": title}];
    }
    self.hookItems = items;

    [self reloadFromStorage];
}


- (void)reloadFromStorage {
    // Global + per-app dictionaries live in local preferences.
    self.globalOptions = [[PXHookPrefsStore globalOptions] mutableCopy];
    self.perAppOptionsAll = [[PXHookPrefsStore perAppOptionsAll] mutableCopy];

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

    // Persist only when user taps "Save" (so they can batch edits)
}

#pragma mark - Actions

- (void)saveToStorage {
    [PXHookPrefsStore saveGlobalOptions:self.globalOptions ?: @{}];
    [PXHookPrefsStore savePerAppOptions:self.perAppOptionsAll ?: @{}];
    notify_post(kPrefsChangedNotifyName);

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Saved" message:@"Hook options were saved to local preferences." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)resetMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Reset" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Reset ALL (global + all apps)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [PXHookPrefsStore resetAllToDefault];
        [self reloadFromStorage];
        notify_post(kPrefsChangedNotifyName);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Reset global defaults" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [PXHookPrefsStore resetGlobalToDefault];
        [self reloadFromStorage];
        notify_post(kPrefsChangedNotifyName);
    }]];
    if (self.targetBundleID.length) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Reset this app" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [PXHookPrefsStore resetAppToDefault:self.targetBundleID];
            [self reloadFromStorage];
            notify_post(kPrefsChangedNotifyName);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)exportConfig {
    NSURL *fileURL = [PXHookPrefsStore exportConfigToTemporaryFile];
    if (!fileURL) return;

    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    av.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:av animated:YES completion:nil];
}

- (void)importConfig {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.json", @"com.apple.property-list"] inMode:UIDocumentPickerModeImport];
    picker.delegate = (id<UIDocumentPickerDelegate>)self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
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

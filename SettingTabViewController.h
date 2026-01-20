#import "UIKit/UIKit.h"



@interface SettingTabViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>


@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *carrierOptions;
@property (nonatomic, strong) NSArray *systemVersionOptions;

@property (nonatomic, strong) UIPickerView *carrierPicker;
@property (nonatomic, strong) UIPickerView *systemPicker1;
@property (nonatomic, strong) UIPickerView *systemPicker2;

@property (nonatomic, assign) NSInteger selectedCarrierIndex;
@property (nonatomic, assign) NSInteger selectedSystemIndex1;
@property (nonatomic, assign) NSInteger selectedSystemIndex2;

@end
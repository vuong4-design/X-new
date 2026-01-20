#import "AppTabViewController.h"
#import "AppTabViewController.h"
#import "DaemonApiManager.h"

@implementation AppTabViewController
- (void)loadPreferences
{
    _selectedApplications = [[DaemonApiManager sharedManager] getScopeApps];
    if(!_selectedApplications){
        [super loadPreferences];
    }

}

- (void)savePreferences
{
    [[DaemonApiManager sharedManager] saveScopeApps:_selectedApplications];
}

@end 

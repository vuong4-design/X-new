#import <Foundation/Foundation.h>
#import <MobileCoreServices/LSApplicationWorkspace.h>
#import <MobileCoreServices/LSApplicationProxy.h>

@interface ActionManager : NSObject
+ (instancetype)sharedManager;

- (void) newPhone;
- (void) removeBackup:(NSString *)id;
-(void) switchBackup:(NSString *) id;
@end

@interface LSApplicationProxy(Private)
    @property(readonly, nonatomic) NSUUID *deviceIdentifierForAdvertising;
    @property(readonly, nonatomic) NSUUID *deviceIdentifierForVendor;
    -(BOOL)isDeletable;
@end

@interface LSApplicationWorkspace(Private)

    + (instancetype)defaultWorkspace;
    - (void)clearAdvertisingIdentifier;
    - (id)deviceIdentifierForAdvertising;
    - (void)removeDeviceIdentifierForVendorName:(id)arg1 bundleIdentifier:(id)arg2;
@end
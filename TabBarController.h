#import <UIKit/UIKit.h>

@interface TabBarController : UITabBarController <UITabBarControllerDelegate, NSURLSessionDelegate>

// Property to store certificate data for pinning
@property (nonatomic, strong) NSData *trustedServerCertificateData;

// Secure session property for certificate pinning
@property (nonatomic, strong) NSURLSession *secureSession;

// We need this property to avoid circular references
@property (nonatomic, strong) id sessionDelegate;

// Device type detection - helpful for iPad-specific handling
@property (nonatomic, assign, readonly) BOOL isDeviceIPad;



// Method to update notification badge on the support tab
- (void)updateNotificationBadge;

// Method to restrict access to only the account tab
- (void)restrictAccessToAccountTabOnly:(BOOL)restricted;


// Toast message methods
- (void)showToastMessage:(NSString *)message success:(BOOL)success;
- (void)showToastMessage:(NSString *)message withDuration:(CGFloat)duration isSuccess:(BOOL)isSuccess;

@end
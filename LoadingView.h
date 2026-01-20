#import <UIKit/UIKit.h>

@interface LoadingView : UIView

+ (instancetype)sharedInstance;
- (void)showInView:(UIView *)view withMessage:(NSString *)message;
- (void)showInView:(UIView *)view; // 默认消息
- (void)showWithMessage:(NSString *)message; // 自动获取 window
- (void)show; // 最简单的方式
- (void)hide;

@end
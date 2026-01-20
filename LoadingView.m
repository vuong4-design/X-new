#import "LoadingView.h"

@interface LoadingView()
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIActivityIndicatorView *indicator;
@property (nonatomic, strong) UILabel *messageLabel;
@end

@implementation LoadingView

+ (instancetype)sharedInstance {
    static LoadingView *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[LoadingView alloc] init];
    });
    return sharedInstance;
}

- (void)showInView:(UIView *)view {
    [self showInView:view withMessage:@"Loading..."];
}

- (void)showInView:(UIView *)view withMessage:(NSString *)message {
    // 如果已经显示，先移除
    if (self.superview) {
        [self removeFromSuperview];
    }
    
    // 设置自身 frame
    self.frame = view.bounds;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    
    // 创建内容视图
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 140, 140)];
    self.contentView.center = self.center;
    self.contentView.backgroundColor = [UIColor whiteColor];
    self.contentView.layer.cornerRadius = 10;
    self.contentView.layer.masksToBounds = YES;
    
    // 添加阴影
    self.contentView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.contentView.layer.shadowOffset = CGSizeMake(0, 2);
    self.contentView.layer.shadowOpacity = 0.3;
    self.contentView.layer.shadowRadius = 4;
    
    // 添加活动指示器
    self.indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.indicator.center = CGPointMake(70, 60);
    [self.indicator startAnimating];
    
    // 添加消息标签
    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 100, 120, 30)];
    self.messageLabel.text = message;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [UIFont systemFontOfSize:14];
    self.messageLabel.textColor = [UIColor darkGrayColor];
    
    [self.contentView addSubview:self.indicator];
    [self.contentView addSubview:self.messageLabel];
    [self addSubview:self.contentView];
    
    [view addSubview:self];
}

- (void)hide {
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        self.alpha = 1.0;
    }];
}
// 添加新方法
- (void)showWithMessage:(NSString *)message {
    UIWindow *window = [self getKeyWindow];
    if (window) {
        [self showInView:window withMessage:message];
    }
}

- (void)show {
    [self showWithMessage:@"Loading..."];
}

// 获取 keyWindow 的辅助方法
- (UIWindow *)getKeyWindow {
    UIWindow *window = nil;
    
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
            if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *sceneWindow in windowScene.windows) {
                    if (sceneWindow.isKeyWindow) {
                        window = sceneWindow;
                        break;
                    }
                }
                if (window) break;
            }
        }
    } else {
        window = [UIApplication sharedApplication].keyWindow;
    }
    
    return window;
}
@end

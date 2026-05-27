#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ========== 你可以在这里修改固定激活码 ==========
static NSString * const FIXED_ACTIVATE_CODE = @"123456"; // 改成你想要的验证码就行

// ========== 提前声明函数 ==========
static void showDisclaimerAlert(UIWindow *window);
static void showActivateAlert(UIWindow *window);
static void showToast(NSString *message, UIColor *color);
static BOOL needActivate();
static void saveActivateTime();

// ========== 你原来的移除Tab代码，完全保留，没有修改 ==========
%hook UITabBarController

- (void)viewDidLoad {
    %orig;
    
    // 延迟执行，等界面完全稳定
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSArray *vcs = self.viewControllers;
        if (!vcs || vcs.count <= 2) return;
        
        // 只保留前2个Tab
        NSArray *newVCs = [vcs subarrayWithRange:NSMakeRange(0, 2)];
        
        // 关键：先切到第0个Tab，再移除，避免选中被移除的Tab
        self.selectedIndex = 0;
        
        // 动画移除，减少闪退概率
        [self setViewControllers:newVCs animated:NO];
        
        // 清理TabBar按钮
        UITabBar *tabBar = self.tabBar;
        NSArray *items = tabBar.items;
        if (items.count > 2) {
            NSArray *newItems = [items subarrayWithRange:NSMakeRange(0, 2)];
            [tabBar setItems:newItems animated:NO];
        }
    });
}

%end


// ========== 新增的启动弹窗功能 ==========
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 延迟1.5秒，等界面完全初始化
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            // 兼容iOS13+的Scene
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        UIWindowScene *windowScene = (UIWindowScene *)scene;
                        for (UIWindow *w in windowScene.windows) {
                            if (w.isKeyWindow) {
                                keyWindow = w;
                                break;
                            }
                        }
                        if (keyWindow) break;
                    }
                }
            }
            if (!keyWindow) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                keyWindow = [UIApplication sharedApplication].keyWindow;
                #pragma clang diagnostic pop
            }
            
            // 重试机制
            if (!keyWindow || !keyWindow.rootViewController) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIWindow *retryWindow = nil;
                    if (@available(iOS 13.0, *)) {
                        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                            if ([scene isKindOfClass:[UIWindowScene class]]) {
                                UIWindowScene *windowScene = (UIWindowScene *)scene;
                                for (UIWindow *w in windowScene.windows) {
                                    if (w.isKeyWindow) {
                                        retryWindow = w;
                                        break;
                                    }
                                }
                                if (retryWindow) break;
                            }
                        }
                    }
                    if (!retryWindow) {
                        #pragma clang diagnostic push
                        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                        retryWindow = [UIApplication sharedApplication].keyWindow;
                        #pragma clang diagnostic pop
                    }
                    
                    if (retryWindow && retryWindow.rootViewController) {
                        showDisclaimerAlert(retryWindow);
                    }
                });
                return;
            }
            
            // 先弹免责声明（每次都弹）
            showDisclaimerAlert(keyWindow);
        });
    });
}

%end


// ========== 临时的Target类，处理按钮点击 ==========
@interface PopupTarget : NSObject
@property (nonatomic, copy) void(^cancelBlock)(void);
@property (nonatomic, copy) void(^agreeBlock)(void);
@property (nonatomic, copy) void(^confirmBlock)(NSString *input);
@property (nonatomic, weak) UITextField *inputField;
@end
@implementation PopupTarget
- (void)cancelClicked {
    if (self.cancelBlock) self.cancelBlock();
}
- (void)agreeClicked {
    if (self.agreeBlock) self.agreeBlock();
}
- (void)confirmClicked {
    if (self.confirmBlock && self.inputField) {
        self.confirmBlock(self.inputField.text ?: @"");
    }
}
@end


// ========== Toast提示 ==========
static void showToast(NSString *message, UIColor *color) {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
                if (window) break;
            }
        }
    }
    if (!window) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        window = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    if (!window) return;
    
    // 清理旧的Toast
    for (UIView *v in window.subviews) {
        if (v.tag == 9999) {
            [v removeFromSuperview];
        }
    }
    
    UILabel *label = [[UILabel alloc] init];
    label.tag = 9999;
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = color ?: [UIColor colorWithWhite:0 alpha:0.8];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:16];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;
    
    CGSize size = [message boundingRectWithSize:CGSizeMake(280, 999)
                                        options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName: label.font}
                                        context:nil].size;
    label.frame = CGRectMake(0, 0, size.width + 32, size.height + 16);
    label.center = CGPointMake(window.center.x, window.center.y - 60);
    
    [window addSubview:label];
    
    [UIView animateWithDuration:0.3 delay:2.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        label.alpha = 0;
    } completion:^(BOOL finished) {
        [label removeFromSuperview];
    }];
}


// ========== 激活状态检查 ==========
static BOOL needActivate() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id obj = [defaults objectForKey:@"hmt_last_activate_time"];
    
    // 严格类型校验，防止旧数据导致崩溃
    if (!obj || ![obj isKindOfClass:[NSNumber class]]) {
        return YES;
    }
    
    NSTimeInterval lastTime = [(NSNumber *)obj doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    // 30天过期（2592000秒）
    return (now - lastTime) > 2592000;
}

// 保存激活时间
static void saveActivateTime() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [defaults setObject:@(now) forKey:@"hmt_last_activate_time"];
    [defaults synchronize];
}


// ========== 免责声明弹窗 ==========
static void showDisclaimerAlert(UIWindow *window) {
    // 1. 半透明背景
    UIView *maskView = [[UIView alloc] initWithFrame:window.bounds];
    maskView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    maskView.tag = 99999;
    [window addSubview:maskView];
    
    // 2. 弹窗容器
    CGFloat popupWidth = MIN(window.bounds.size.width - 48, 320);
    CGFloat popupHeight = 300;
    UIView *popupView = [[UIView alloc] initWithFrame:CGRectMake(
        (window.bounds.size.width - popupWidth)/2,
        (window.bounds.size.height - popupHeight)/2,
        popupWidth,
        popupHeight
    )];
    popupView.backgroundColor = [UIColor whiteColor];
    popupView.layer.cornerRadius = 16;
    popupView.layer.shadowColor = [UIColor blackColor].CGColor;
    popupView.layer.shadowOpacity = 0.2;
    popupView.layer.shadowOffset = CGSizeMake(0, 10);
    popupView.layer.shadowRadius = 20;
    popupView.clipsToBounds = NO;
    [maskView addSubview:popupView];
    
    // 3. 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 24, popupWidth - 48, 30)];
    titleLabel.text = @"⚠️ 免责声明";
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [popupView addSubview:titleLabel];
    
    // 4. 内容
    UILabel *contentLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 64, popupWidth - 48, 160)];
    contentLabel.text = @"该软件仅用于内部使用，请勿用于非法用途，违者后果自负。\n\n软件有问题联系【乌梢蛇】处理，其他问题一概不知。";
    contentLabel.font = [UIFont systemFontOfSize:15];
    contentLabel.textColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
    contentLabel.numberOfLines = 0;
    contentLabel.lineBreakMode = NSLineBreakByWordWrapping;
    contentLabel.textAlignment = NSTextAlignmentLeft;
    [popupView addSubview:contentLabel];
    
    // 5. 按钮
    UIView *buttonContainer = [[UIView alloc] initWithFrame:CGRectMake(16, popupHeight - 64, popupWidth - 32, 44)];
    [popupView addSubview:buttonContainer];
    
    UIButton *cancelBtn = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, (popupWidth - 48)/2, 44)];
    cancelBtn.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    cancelBtn.layer.cornerRadius = 10;
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0] forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [buttonContainer addSubview:cancelBtn];
    
    UIButton *agreeBtn = [[UIButton alloc] initWithFrame:CGRectMake((popupWidth - 48)/2 + 16, 0, (popupWidth - 48)/2, 44)];
    agreeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0];
    agreeBtn.layer.cornerRadius = 10;
    [agreeBtn setTitle:@"我已知晓" forState:UIControlStateNormal];
    [agreeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    agreeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [buttonContainer addSubview:agreeBtn];
    
    // 6. 点击事件
    __weak UIView *weakMask = maskView;
    __weak UIView *weakPopup = popupView;
    void(^dismissBlock)(void) = ^{
        [UIView animateWithDuration:0.25 animations:^{
            weakMask.alpha = 0;
            weakPopup.transform = CGAffineTransformMakeScale(0.9, 0.9);
            weakPopup.alpha = 0;
        } completion:^(BOOL finished) {
            [weakMask removeFromSuperview];
        }];
    };
    
    PopupTarget *target = [[PopupTarget alloc] init];
    target.cancelBlock = ^{
        exit(0);
    };
    target.agreeBlock = ^{
        // 同意免责后，检查是否需要激活
        dismissBlock();
        if (needActivate()) {
            // 需要激活，弹激活界面
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                showActivateAlert(window);
            });
        }
        // 不需要激活，直接进App
    };
    
    // 绑定target防止释放
    objc_setAssociatedObject(maskView, "popup_target", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    [cancelBtn addTarget:target action:@selector(cancelClicked) forControlEvents:UIControlEventTouchUpInside];
    [agreeBtn addTarget:target action:@selector(agreeClicked) forControlEvents:UIControlEventTouchUpInside];
    
    // 7. 入场动画
    popupView.transform = CGAffineTransformMakeScale(0.85, 0.85);
    popupView.alpha = 0;
    maskView.alpha = 0;
    
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        popupView.transform = CGAffineTransformIdentity;
        popupView.alpha = 1;
        maskView.alpha = 1;
    } completion:nil];
}


// ========== 激活码输入弹窗 ==========
static void showActivateAlert(UIWindow *window) {
    // 1. 半透明背景
    UIView *maskView = [[UIView alloc] initWithFrame:window.bounds];
    maskView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    maskView.tag = 99999;
    [window addSubview:maskView];
    
    // 2. 弹窗容器
    CGFloat popupWidth = MIN(window.bounds.size.width - 48, 300);
    CGFloat popupHeight = 260;
    UIView *popupView = [[UIView alloc] initWithFrame:CGRectMake(
        (window.bounds.size.width - popupWidth)/2,
        (window.bounds.size.height - popupHeight)/2,
        popupWidth,
        popupHeight
    )];
    popupView.backgroundColor = [UIColor whiteColor];
    popupView.layer.cornerRadius = 16;
    popupView.layer.shadowColor = [UIColor blackColor].CGColor;
    popupView.layer.shadowOpacity = 0.2;
    popupView.layer.shadowOffset = CGSizeMake(0, 10);
    popupView.layer.shadowRadius = 20;
    popupView.clipsToBounds = NO;
    [maskView addSubview:popupView];
    
    // 3. 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 20, popupWidth - 48, 30)];
    titleLabel.text = @"🔐 激活验证";
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [popupView addSubview:titleLabel];
    
    // 4. 提示文本
    UILabel *tipLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 54, popupWidth - 48, 20)];
    tipLabel.text = @"请输入激活码，激活后可使用30天";
    tipLabel.font = [UIFont systemFontOfSize:13];
    tipLabel.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0];
    tipLabel.textAlignment = NSTextAlignmentCenter;
    [popupView addSubview:tipLabel];
    
    // 5. 输入框
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(24, 88, popupWidth - 48, 48)];
    inputField.placeholder = @"请输入6位激活码";
    inputField.keyboardType = UIKeyboardTypeNumberPad;
    inputField.secureTextEntry = YES;
    inputField.textAlignment = NSTextAlignmentCenter;
    inputField.font = [UIFont systemFontOfSize:20];
    inputField.layer.cornerRadius = 10;
    inputField.layer.borderWidth = 1;
    inputField.layer.borderColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0].CGColor;
    [popupView addSubview:inputField];
    
    // 自动弹出键盘
    [inputField becomeFirstResponder];
    
    // 6. 按钮
    UIView *buttonContainer = [[UIView alloc] initWithFrame:CGRectMake(16, popupHeight - 64, popupWidth - 32, 44)];
    [popupView addSubview:buttonContainer];
    
    UIButton *cancelBtn = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, (popupWidth - 48)/2, 44)];
    cancelBtn.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    cancelBtn.layer.cornerRadius = 10;
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0] forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [buttonContainer addSubview:cancelBtn];
    
    UIButton *confirmBtn = [[UIButton alloc] initWithFrame:CGRectMake((popupWidth - 48)/2 + 16, 0, (popupWidth - 48)/2, 44)];
    confirmBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0];
    confirmBtn.layer.cornerRadius = 10;
    [confirmBtn setTitle:@"确认激活" forState:UIControlStateNormal];
    [confirmBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    confirmBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [buttonContainer addSubview:confirmBtn];
    
    // 7. 点击事件
    __weak UIView *weakMask = maskView;
    __weak UIView *weakPopup = popupView;
    __weak UITextField *weakInput = inputField;
    void(^dismissBlock)(void) = ^{
        [inputField resignFirstResponder];
        [UIView animateWithDuration:0.25 animations:^{
            weakMask.alpha = 0;
            weakPopup.transform = CGAffineTransformMakeScale(0.9, 0.9);
            weakPopup.alpha = 0;
        } completion:^(BOOL finished) {
            [weakMask removeFromSuperview];
        }];
    };
    
    PopupTarget *target = [[PopupTarget alloc] init];
    target.inputField = inputField;
    target.cancelBlock = ^{
        exit(0);
    };
    target.confirmBlock = ^(NSString *input) {
        // 检查验证码
        if ([input isEqualToString:FIXED_ACTIVATE_CODE]) {
            // 正确
            saveActivateTime();
            dismissBlock();
            showToast(@"✅ 激活成功", [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0]);
        } else {
            // 错误
            weakInput.text = @"";
            showToast(@"❌ 验证码错误，请重试", [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0]);
            // 重新弹出键盘
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [weakInput becomeFirstResponder];
            });
        }
    };
    
    // 绑定target
    objc_setAssociatedObject(maskView, "activate_target", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    [cancelBtn addTarget:target action:@selector(cancelClicked) forControlEvents:UIControlEventTouchUpInside];
    [confirmBtn addTarget:target action:@selector(confirmClicked) forControlEvents:UIControlEventTouchUpInside];
    
    // 8. 入场动画
    popupView.transform = CGAffineTransformMakeScale(0.85, 0.85);
    popupView.alpha = 0;
    maskView.alpha = 0;
    
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        popupView.transform = CGAffineTransformIdentity;
        popupView.alpha = 1;
        maskView.alpha = 1;
    } completion:nil];
}
